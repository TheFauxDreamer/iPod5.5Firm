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
#define TEXT_TYPE    24197                                /* Espy Sans, size 10 */
#define VIEW_FLAGS   0x20
#define VIEW_SMALL   0x1000000u                           /* a view with fewer pictures */
#define VIEW_LIST    0x78
#define VIEW_RECT    0x58                                 /* top, left, bottom, right in the parent */
#define VIEW_SHOW    0x9c                                 /* the vtable offset of the show method */
#define VIEW_TYPE    0xc8                                 /* the Type record of a label */
#define TEXT_CHILD   0x1b
#define NO_CHILD     0x1c
#define SMALL_TEXT   0x17
#define SMALL_ICON   4
#define BOX_WIDTH    27
#define TEXT_WIDTH   30                                   /* the space for the text at the left */

void read_switches(void *a);
unsigned hardware_revision(void);
int battery_icon(void *provider, int mode);
int battery_raw(void);
void show_child(void *view, int index);
void child_first(void *walk, void *list, int from);
int child_next(void *walk, void **child);
void child_end(void *walk);
void *str_table(void);
void set_label_type(void *label, void *provider, int type, int redraw);

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
static void *styled_type;
static char text[6];
static int text_left, text_right;

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

/* The icon value of the battery picture. */
int hook_icon(void *provider, int mode)
{
    int value = battery_icon(provider, mode);

    return battery_data ? percent(provider) / 5 : value;
}

/* Moves a child for the wide view (change 1), or back (change -1). The text goes at the left. */
static void move_child(void *child, int index, int text_child, int change)
{
    int *rect = (int *)((char *)child + VIEW_RECT);

    if (index != text_child) {
        rect[1] += change * TEXT_WIDTH;
        rect[3] += change * TEXT_WIDTH;
    } else if (change > 0) {
        text_left = rect[1];
        text_right = rect[3];
        rect[1] = 0;
        rect[3] = TEXT_WIDTH;
    } else {
        rect[1] = text_left;
        rect[3] = text_right;
    }
}

/* Replaces the call of 0x1ae6d0 (view, index). The index is the text if the switch is on, or a
 * charge picture during a charge. With 2 items, the view is wide. Percent goes back to the normal
 * width after a charge. */
void hook_show(void *view, int index)
{
    unsigned char walk[20];
    void *child;
    int small, text_child, second = -1, change = 0, width, i = 0;
    int *rect = (int *)((char *)view + VIEW_RECT);

    show_child(view, index);
    if (!display_mode || index >= NO_CHILD)
        return;
    small = (*(unsigned *)((char *)view + VIEW_FLAGS) & VIEW_SMALL) != 0;
    text_child = small ? SMALL_TEXT : TEXT_CHILD;
    if (index != text_child) {
        if (small)
            return;
        second = text_child;
    } else if (display_mode == 1 && last_provider) {
        second = small ? SMALL_ICON : hook_icon(last_provider, 0) + 4;
    }
    width = rect[3] - rect[1];
    if (!small && second >= 0 && width == BOX_WIDTH)
        change = 1;
    else if (!small && second < 0 && width == BOX_WIDTH + TEXT_WIDTH)
        change = -1;
    child_first(walk, (char *)view + VIEW_LIST, -2);
    while (child_next(walk, &child)) {
        if (i == text_child) {
            void **type = (void **)((char *)child + VIEW_TYPE);
            if (!styled_type || *type != styled_type) {
                set_label_type(child, str_table(), TEXT_TYPE, 1);
                styled_type = *type;
            }
        }
        if (i == second)
            (*(void (**)(void *, int))(*(char **)child + VIEW_SHOW))(child, 1);
        if (change)
            move_child(child, i, text_child, change);
        i++;
    }
    child_end(walk);
    rect[1] -= change * TEXT_WIDTH;
}
