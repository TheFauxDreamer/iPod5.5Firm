/* split-clock: the time, the day and the date in the Split panel when there is no current song.
 * Refer to re/split-clock.md.
 *
 * The Split View has 3 text elements with the IDs CLOCK_TIME, CLOCK_DAY and CLOCK_DATE. The build
 * adds them only with this patch. A label with no answer does not draw.
 *
 * The hooks (all with "chain"):
 *   0x670fb0: the text method of the main provider (0x1e804c). It gives the clock text only if the
 *             song title is empty. Thus the clock and the song do not show at the same time.
 *   0x670fa8: the notify method of the main provider (0x21f37c). A notify of the song title also
 *             goes to the clock lines.
 *   0x6701ec: the event method of the status object (0x1d93c4). The first event makes the timer of
 *             the patch with the status object as its owner. The timer comes at each new minute.
 */

#define TAG_STR      0x53747220u         /* 'Str ' */
#define SONG_TITLE   0x63bd
#define CLOCK_TIME   0x7e41
#define LINES        3                   /* the time, the day, the date */
#define EV_TIMER     9
#define FORMAT_SLOT  0x7c                /* the format method of the language manager (0x250c50) */
#define OBJ_PROVIDER 0x18                /* status object + 0x18: the main provider */
#define TEXT_SIZE    40
#define MINUTE_MS    60000u
#define LATE_MS      100u                /* the timer comes just after the new minute */

typedef int (*format_fn)(void *manager, char *text, unsigned size, unsigned style, const void *calendar);

int text_next(void *provider, unsigned type, int id, const char **out);
int notify_next(void *object, unsigned type, int id);
int event_next(void *object, const int *event);
void current_time(void *calendar);                                   /* 0xd252c */
void *language_manager(void);                                        /* 0xcce88 */
void timer_make(void *owner, void *timer, int a, int b);             /* 0x13d7c8 */
void timer_period(void *timer, unsigned ms);                         /* 0x151c24 */
void timer_start(void *timer);                                       /* 0x151694 */

/* 0x11: the short time (12-hour or 24-hour). 2: the name of the day. 8: the long date. */
static const unsigned char styles[LINES] = { 0x11, 2, 8 };

static unsigned timer[10];               /* a firmware timer: 0x28 bytes */
static void *owner, *provider;
static char text[LINES][TEXT_SIZE];

/* The calendar structure of 0xd252c: + 0 seconds ... + 8 day of the week. */
static void make_text(int line)
{
    unsigned calendar[3];
    void *manager = language_manager();

    text[line][0] = 0;
    if (!manager)
        return;
    current_time(calendar);
    (*(format_fn *)(*(char **)manager + FORMAT_SLOT))(manager, text[line], TEXT_SIZE, styles[line], calendar);
}

static void notify_lines(void *object)
{
    int line;

    for (line = 0; line < LINES; line++)
        notify_next(object, TAG_STR, CLOCK_TIME + line);
}

/* The timer for the next minute. */
static void start_timer(void)
{
    unsigned calendar[3], seconds;

    current_time(calendar);
    seconds = calendar[0] & 0xff;
    if (seconds > 59)
        seconds = 59;
    timer_period(timer, MINUTE_MS - seconds * 1000u + LATE_MS);
    timer_start(timer);
}

int hook_text(void *self, unsigned type, int id, const char **out)
{
    unsigned line = (unsigned)(id - CLOCK_TIME);
    const char *song = 0;

    if (line >= LINES || type != TAG_STR)
        return text_next(self, type, id, out);
    if (text_next(self, TAG_STR, SONG_TITLE, &song) && song && *song)
        return 0;
    make_text(line);
    *out = text[line];
    return 1;
}

int hook_notify(void *self, unsigned type, int id)
{
    int result = notify_next(self, type, id);

    if (type == TAG_STR && id == SONG_TITLE)
        notify_lines(self);
    return result;
}

int hook_event(void *self, const int *event)
{
    if (!owner) {
        owner = self;
        provider = *(void **)((char *)self + OBJ_PROVIDER);
        timer_make(self, timer, 0, 0);
        start_timer();
    }
    if (self == owner && event[1] == EV_TIMER && event[2] == (int)timer) {
        if (provider)
            notify_lines(provider);
        start_timer();
        return 1;
    }
    return event_next(self, event);
}
