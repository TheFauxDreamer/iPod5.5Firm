/* battery-display: a battery percentage, and a choice of the battery data. Refer to re/battery.md.
 *
 * Options in patch.json:
 *   display_mode: 0 icon, 1 icon and percent, 2 percent.
 *   battery_data: 0 Apple (the icon value x 5), 1 custom battery (the table below).
 *   smoothing: 1 uses a longer average and stops small rises of the percentage. It also gives Apple
 *   data steps of 1 %, with a line between the limits of the firmware table.
 *
 * The hooks:
 *   0xb4abc:  after the read of the switch files, sets the byte of _show_voltage.
 *   0x1e8af8: in case 0x63fc, gives the text of the percentage in place of the raw value.
 *   0x1ae820: records the provider before the first text request, so that the first show has it.
 *   0x1ae838: the only icon call for the battery picture. Other callers keep the Apple value, so the
 *             low battery behaviour does not change.
 *   0x1ae6b8: sets the small text style, and shows a second item: the icon or the charge picture.
 *
 * A charge takes the other path in 0x1ae774, so the charge pictures stay. hook_show also shows the
 * text. The value reads high during a charge, because the charge raises the voltage.
 */

#define USEC         (*(volatile unsigned *)0x60005010)   /* the microsecond timer */
#define SHOW_VOLTAGE (*(volatile char *)0x1081dfe3)       /* the byte of _show_voltage */
#define READ_US      30000000u                            /* the shortest time between raw reads */
#define AVERAGE      8
#define LONG_AVERAGE 32
#define RISE_PERCENT 5                                    /* a smaller rise does not show */
#define LIMITS       15                                   /* the limits of a firmware battery table */
#define TEXT_FONT    0x5e3c                               /* Podium Sans, as in the stock Type 24223 */
#define TEXT_SIZE    14                                   /* the smallest size of a Podium Sans Type */
#define TEXT_FLAGS   0x201                                /* byte + 0xd: 2 = right aligned */
#define VIEW_FLAGS   0x20
#define VIEW_SMALL   0x1000000u                           /* a view with fewer pictures */
#define VIEW_LIST    0x78
#define VIEW_RECT    0x58                                 /* top, left, bottom, right on the screen */
#define VIEW_SHOW    0x9c                                 /* the vtable offset of the show method */
#define VIEW_TYPE    0xc8                                 /* the Type record of a label */
#define VIEW_REDRAW  0xc8                                 /* the vtable offset of the redraw method */
#define VIEW_INVERT  0x8                                  /* + 0x20: 0x2438bc uses the colour at 0x10823394 */
#define LABEL_FONT   0x74                                 /* the font and the colour of a label */
#define LABEL_ALIGN  0xb9
#define LABEL_FLAGS  0xc0
#define TYPE_COLOUR  0x200                                /* + 0xc0: 0x2438bc uses the Type colour */
#define TEXT_CHILD   0x1b
#define NO_CHILD     0x1c
#define SMALL_TEXT   0x17
#define SMALL_ICON   4
#define TEXT_WIDTH   40                                   /* the space for the text at the left */
#define TEXT_GAP     2                                    /* the space between the text and the icon */
#define TEXT_BOX     (TEXT_WIDTH - TEXT_GAP)              /* "100%" is approximately 32 pixels */
#define TEXT_RAISE   1                                    /* the text is higher than the icon box */
#define VIEWS        8

void read_switches(void *a);
unsigned hardware_revision(void);
int battery_icon(void *provider, int mode);
int text_wanted(void *provider);
int battery_raw(void);
void show_child(void *view, int index);
void child_first(void *walk, void *list, int from);
int child_next(void *walk, void **child);
void child_end(void *walk);
void apply_type(void *label, const unsigned *type, void *font, void *align);

unsigned display_mode = 2;                                /* an option in patch.json */
unsigned battery_data = 0;                                /* an option in patch.json */
unsigned smoothing = 0;                                   /* an option in patch.json */

/* Provisional: the second log of the owner's larger battery, with 20.3 hours from raw 438. The app
 * writes a curve from an imported log over these values. The raw values decrease. */
#define CURVE_POINTS 16u
unsigned short curve_raw[CURVE_POINTS] = { 438, 423, 415, 405, 380, 363, 350, 337, 325, 311, 300, 284, 250, 200, 150, 116 };
unsigned short curve_pct[CURVE_POINTS] = { 100,  89,  83,  77,  68,  61,  55,  50,  43,  37,  34,  31,  24,  12,   4,   0 };

static unsigned samples[LONG_AVERAGE], sample_count, sample_next, sample_sum;
static unsigned last_read;
static int last_percent = -1;
static void *last_provider;
static const unsigned *stock_type;
static unsigned text_type[4];
static char text[6];
static void *views[VIEWS];
static int view_left[VIEWS], text_top[VIEWS], text_bottom[VIEWS], text_left[VIEWS], text_right[VIEWS];
static unsigned text_colour[VIEWS];

/* The average of the last raw values, or 0 if the iPod has no value yet. */
static unsigned mean_raw(void)
{
    unsigned now = USEC, size = smoothing ? LONG_AVERAGE : AVERAGE;

    if (!sample_count || now - last_read >= READ_US) {
        int raw = battery_raw();
        last_read = now;
        if (raw > 0 && raw < 1024) {
            if (sample_count == size)
                sample_sum -= samples[sample_next];
            else
                sample_count++;
            samples[sample_next] = raw;
            sample_sum += raw;
            sample_next = sample_next + 1 == size ? 0 : sample_next + 1;
        }
    }
    return sample_count ? sample_sum / sample_count : 0;
}

static int custom_percent(unsigned mean)
{
    unsigned i, span;

    if (mean >= curve_raw[0])
        return 100;
    for (i = 1; i < CURVE_POINTS; i++) {
        if (mean >= curve_raw[i]) {
            span = curve_raw[i - 1] - curve_raw[i];
            return curve_pct[i] + (mean - curve_raw[i]) * (curve_pct[i - 1] - curve_pct[i]) / span;
        }
    }
    return 0;
}

/* The limits that 0x264ee8 selects from the hardware revision. */
static const unsigned short *apple_limits(void)
{
    switch (hardware_revision() >> 16) {
    case 4: case 5: return (const unsigned short *)0x1081de98;
    case 7:         return (const unsigned short *)0x1081ded4;
    case 9:         return (const unsigned short *)0x1081def2;
    case 0xb:       return (const unsigned short *)0x1081df10;
    case 0xc:       return (const unsigned short *)0x1081df2e;
    default:        return (const unsigned short *)0x1081deb6;
    }
}

/* A line between the limits. Each limit is one level of 15, as in 0x1dfe44. */
static int apple_percent(unsigned mean)
{
    const unsigned short *limit = apple_limits();
    unsigned i;

    if (mean < limit[0])
        return 0;
    for (i = 1; i < LIMITS; i++)
        if (mean < limit[i])
            return (i * 100 + (mean - limit[i - 1]) * 100 / (limit[i] - limit[i - 1])) / LIMITS;
    return 100;
}

static int percent(void *provider)
{
    int value;

    if (battery_data || smoothing) {
        unsigned mean = mean_raw();
        if (!mean)
            return last_percent < 0 ? 0 : last_percent;
        value = battery_data ? custom_percent(mean) : apple_percent(mean);
        if (smoothing && last_percent >= 0 && value > last_percent && value < last_percent + RISE_PERCENT)
            return last_percent;
    } else {
        value = battery_icon(provider, 0);
        if (value < 0 || value > 20)                      /* 21: no value yet */
            return last_percent < 0 ? 0 : last_percent;
        value *= 5;
    }
    last_percent = value;
    return value;
}

/* The text of the percentage. The firmware gives it to sprintf with the format "%s". */
const char *battery_text(void *provider)
{
    unsigned value = percent(provider), n = 0;

    last_provider = provider;
    if (value >= 100)
        text[n++] = '0' + value / 100;
    if (value >= 10)
        text[n++] = '0' + value / 10 % 10;
    text[n++] = '0' + value % 10;
    text[n++] = '%';
    text[n] = 0;
    return text;
}

const char *text_format(void)
{
    return "%s";
}

/* In place of "adr r1, %ld" at 0x1e8af8. r5 is the provider. r2 is the raw value. The next
 * instructions set r0 and call sprintf with r1 and r2. */
__attribute__((naked)) void hook_text(void)
{
    __asm__ volatile(
        "push  {r4, lr}\n"
        "mov   r0, r5\n"
        "bl    battery_text\n"
        "mov   r4, r0\n"
        "bl    text_format\n"
        "mov   r1, r0\n"
        "mov   r2, r4\n"
        "pop   {r4, pc}\n");
}

/* Replaces the call of 0x1d3ac4. That function clears the byte, so set the byte after it. */
void hook_switches(void *a)
{
    read_switches(a);
    if (display_mode)
        SHOW_VOLTAGE = 1;
}

/* In place of the call of 0x1ebfec in 0x1ae774 (not during a charge). It runs before each show. */
int hook_text_wanted(void *provider)
{
    last_provider = provider;
    return text_wanted(provider);
}

/* The icon value of the battery picture. */
int hook_icon(void *provider, int mode)
{
    int value = battery_icon(provider, mode);

    return battery_data ? percent(provider) / 5 : value;
}

/* The slot of a view, with the stock left edge of the view. The text rectangle is recorded later.
 * Returns -1 if the table is full. A rectangle that is not stock or wide is a new view. */
static int view_slot(void *view, int left)
{
    int s, free = -1;

    for (s = 0; s < VIEWS; s++) {
        if (views[s] == view) {
            if (left <= view_left[s] && left >= view_left[s] - TEXT_WIDTH)
                return s;
            break;
        }
        if (!views[s] && free < 0)
            free = s;
    }
    if (s == VIEWS)
        s = free;
    if (s >= 0) {
        views[s] = view;
        view_left[s] = left;
        text_left[s] = text_right[s] = 0;
        text_colour[s] = 0;
    }
    return s;
}

/* Gives the label the small font, with the colour of the stock record. A theme switch changes the
 * colour of the stock record. 0x21a168 copies the style into the label, so apply it again then.
 * The battery label has VIEW_INVERT, so 0x2438bc ignores the Type colour without TYPE_COLOUR. */
static void style_text(void *label, int s)
{
    const unsigned **type = (const unsigned **)((char *)label + VIEW_TYPE);

    *(unsigned *)((char *)label + LABEL_FLAGS) |= TYPE_COLOUR;
    if (*type != text_type) {
        if (!stock_type)
            stock_type = *type;
        *type = text_type;
        text_colour[s] = 0;
    }
    if (text_colour[s] == stock_type[2])
        return;
    text_type[0] = TEXT_FONT;
    text_type[1] = TEXT_SIZE;
    text_type[2] = text_colour[s] = stock_type[2];
    text_type[3] = TEXT_FLAGS;
    apply_type(label, text_type, (char *)label + LABEL_FONT, (char *)label + LABEL_ALIGN);
    (*(void (**)(void *))(*(char **)label + VIEW_REDRAW))(label);
}

/* The rectangles are screen positions. Layout 0: stock. 1: the text only, in a box that ends at the
 * right edge of the stock box. 2: the icon stays, and the text is at its left. Returns the left edge
 * of the text. */
static int place_text(void *label, int s, int layout)
{
    int *rect = (int *)((char *)label + VIEW_RECT);

    if (!text_right[s]) {
        text_top[s] = rect[0];
        text_left[s] = rect[1];
        text_bottom[s] = rect[2];
        text_right[s] = rect[3];
    }
    rect[0] = layout ? text_top[s] - TEXT_RAISE : text_top[s];
    rect[2] = layout ? text_bottom[s] - TEXT_RAISE : text_bottom[s];
    rect[3] = layout == 2 ? view_left[s] - TEXT_GAP : text_right[s];
    rect[1] = layout ? rect[3] - TEXT_BOX : text_left[s];
    return rect[1];
}

/* The child of the battery picture, or -1 if the firmware has no value yet (as 0x1ae838). */
static int icon_child(int small)
{
    int value;

    if (!last_provider)
        return -1;
    if (small)
        return SMALL_ICON;
    value = hook_icon(last_provider, 0);
    return value >= 0 && value <= 20 ? value + 4 : -1;
}

/* Replaces the call of 0x1ae6d0 (view, index). The index is the text if the switch is on, or a
 * charge picture during a charge. The text shows only after the first valid percentage; until
 * then the view shows the icon. The view gets wider to the left for the text, and it goes back to
 * the stock width in a small view. */
void hook_show(void *view, int index)
{
    unsigned char walk[20];
    void *child;
    int small, text_child, ready, second = -1, hide = -1, layout, slot, left, i = 0;
    int *rect = (int *)((char *)view + VIEW_RECT);

    show_child(view, index);
    if (!display_mode || index >= NO_CHILD)
        return;
    small = (*(unsigned *)((char *)view + VIEW_FLAGS) & VIEW_SMALL) != 0;
    text_child = small ? SMALL_TEXT : TEXT_CHILD;
    if (last_provider && last_percent < 0)
        percent(last_provider);
    ready = last_percent >= 0;
    if (index != text_child) {
        if (small || !ready)
            return;
        second = text_child;
    } else if (!ready) {
        hide = text_child;
        second = icon_child(small);
    } else if (display_mode == 1) {
        second = icon_child(small);
    }
    slot = view_slot(view, rect[1]);
    if (slot < 0)
        return;
    layout = small || !ready ? 0 : second >= 0 ? 2 : 1;
    left = view_left[slot];
    child_first(walk, (char *)view + VIEW_LIST, -2);
    while (child_next(walk, &child)) {
        if (i == text_child) {
            style_text(child, slot);
            left = place_text(child, slot, layout);
        }
        if (i == second || i == hide)
            (*(void (**)(void *, int))(*(char **)child + VIEW_SHOW))(child, i == second);
        i++;
    }
    child_end(walk);
    rect[1] = left < view_left[slot] ? left : view_left[slot];
}
