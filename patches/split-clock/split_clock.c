/* split-clock: the time, the day and the date in the Split panel when there is no current song.
 * Refer to re/split-clock.md.
 *
 * The Split View has 3 text elements with the IDs CLOCK_TIME, CLOCK_DAY and CLOCK_DATE. The build
 * adds them only with this patch. A label with no answer does not draw.
 *
 * The hooks:
 *   0x21f254: the general lookup ("b", chain). A panel label asks its data object, then the language
 *             manager and the root object. The main provider is not in this chain: the data object
 *             sends it only the music IDs. Thus the patch answers the clock IDs here. The clock shows
 *             if the song title is empty, or after a pause of pause_seconds. Then the patch also gives
 *             no answer for the song lines, the count and the cover of the panel. Now Playing asks the
 *             main provider directly, so it keeps the paused song.
 *   0x670fa8: the notify method of the main provider (0x21f37c, chain). A notify of the song title
 *             also goes to the clock lines.
 *   0x6701ec: the event method of the status object (0x1d93c4, chain). The first event makes the
 *             timer of the patch with the status object as its owner. The timer comes at each half
 *             minute (:00 and :30). It counts the half minutes of a pause (0x9ba00 gives 2).
 */

#define TAG_STR      0x53747220u         /* 'Str ' */
#define TAG_DRAW     0x44726177u         /* 'Draw' */
#define SONG_TITLE   0x63bd              /* then 0x63be the artist, 0x63bf the album */
#define SONG_COUNT   0x63c3              /* "%d of %d" */
#define SONG_COVER   0x63c7              /* asked with 'Draw' */
#define PLAYING      1                   /* 0x9ba00 */
#define PAUSED       2
#define OBJ_PROVIDER 0x18                /* status object + 0x18: the main provider */
#define PROVIDER_LIBRARY 0x1c            /* main provider + 0x1c: the library */
#define CLOCK_TIME   0x7e41
#define LINES        3                   /* the time, the day, the date */
#define EV_TIMER     9
#define FORMAT_SLOT  0x7c                /* the format method of the language manager (0x250c50) */
#define NOTIFY_SLOT  0x54                /* the notify method of an object (0x21f37c) */
#define TEXT_SIZE    40
#define TICK_S       30u                 /* the timer comes at each half minute */
#define LATE_MS      100u                /* the timer comes just after :00 or :30 */

typedef int (*format_fn)(void *manager, char *text, unsigned size, unsigned style, const void *calendar);
typedef int (*notify_fn)(void *object, unsigned type, int id);

void *lookup_next(void *start, unsigned type, int id);
int notify_next(void *object, unsigned type, int id);
int event_next(void *object, const int *event);
void current_time(void *calendar);                                   /* 0xd252c */
void *language_manager(void);                                        /* 0x21f3b8: the string table */
void timer_make(void *owner, void *timer, int a, int b);             /* 0x13d7c8 */
void timer_period(void *timer, unsigned ms);                         /* 0x151c24 */
void timer_start(void *timer);                                       /* 0x151694 */
int play_state(void *library);                                       /* 0x9ba00 */

/* 0x11: the short time (12-hour or 24-hour). 2: the name of the day. The date is date_style. */
static const unsigned char styles[LINES - 1] = { 0x11, 2 };

/* An option in patch.json. 14: the short date (string 0xb3 of the language, for example "Nov 4 2026").
 * 8: the long date (string 0xab, for example "4 November 2026"). */
unsigned date_style = 14;

/* An option in patch.json: the seconds of a pause before the clock shows (0: never). A multiple of
 * TICK_S. */
unsigned pause_seconds = 300;

static unsigned timer[10];               /* a firmware timer: 0x28 bytes */
static void *owner, *labels;             /* labels: the data object that the clock labels ask */
static void *library;
static unsigned paused_s;                /* the seconds of the pause, in steps of TICK_S */
static int pause_clock;                  /* 1: the clock shows in place of the paused song */
static char text[LINES][TEXT_SIZE];

/* The replaced first instruction of 0x21f254. Without an earlier hook, lookup_next is this function. */
__attribute__((naked)) void *lookup_original(void *start, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

/* The calendar structure of 0xd252c: + 0 seconds, + 1 minutes, + 2 hours, + 3 day, + 4 month,
 * + 6 year, + 8 day of the week. A clock chip with no date gives day 0 and month 0. Then the patch
 * gives no text, so the clock does not show. */
static const char *make_text(int line)
{
    unsigned calendar[3], day, month;
    void *manager = language_manager();

    current_time(calendar);
    day = calendar[0] >> 24;
    month = calendar[1] & 0xff;
    if (!manager || day < 1 || day > 31 || month < 1 || month > 12)
        return 0;
    text[line][0] = 0;
    (*(format_fn *)(*(char **)manager + FORMAT_SLOT))(manager, text[line], TEXT_SIZE,
                                                         line < LINES - 1 ? styles[line] : date_style, calendar);
    return text[line][0] ? text[line] : 0;
}

__attribute__((minsize)) static void notify(unsigned type, int id)
{
    (*(notify_fn *)(*(char **)labels + NOTIFY_SLOT))(labels, type, id);
}

/* The clock lines, and with `song` also the song lines, the count and the cover of the panel. */
__attribute__((minsize)) static void notify_lines(int song)
{
    int line;

    if (!labels)
        return;
    for (line = 0; line < LINES; line++)
        notify(TAG_STR, CLOCK_TIME + line);
    if (!song)
        return;
    for (line = SONG_TITLE; line <= SONG_TITLE + 2; line++)
        notify(TAG_STR, line);
    notify(TAG_STR, SONG_COUNT);
    notify(TAG_DRAW, SONG_COVER);
}

__attribute__((minsize)) static void set_pause_clock(int on)
{
    if (pause_clock == on)
        return;
    pause_clock = on;
    notify_lines(1);
}

/* At each timer event. The first event of a pause counts TICK_S, but it comes 0 to TICK_S seconds
 * after the pause. Thus the clock shows pause_seconds to pause_seconds + TICK_S seconds after it. */
__attribute__((minsize)) static void count_pause(void)
{
    int state = library ? play_state(library) : 0;

    if (state != PAUSED) {
        paused_s = 0;
        set_pause_clock(0);
        return;
    }
    if (paused_s <= pause_seconds)
        paused_s += TICK_S;
    if (pause_seconds && paused_s > pause_seconds)
        set_pause_clock(1);
}

/* The timer for the next :00 or :30. */
__attribute__((minsize)) static void start_timer(void)
{
    unsigned calendar[3], seconds;

    current_time(calendar);
    seconds = calendar[0] & 0xff;
    if (seconds > 59)
        seconds = 59;
    if (seconds >= TICK_S)
        seconds -= TICK_S;
    timer_period(timer, (TICK_S - seconds) * 1000u + LATE_MS);
    timer_start(timer);
}

__attribute__((minsize)) void *hook_lookup(void *start, unsigned type, int id)
{
    unsigned line = (unsigned)(id - CLOCK_TIME);
    const char *song;

    if (labels && start == labels && pause_clock &&
        ((type == TAG_STR && (unsigned)(id - SONG_TITLE) < 3) || (type == TAG_DRAW && id == SONG_COVER)))
        return 0;
    if (type == TAG_STR && id == SONG_COUNT && labels && start == labels) {
        song = lookup_next(start, TAG_STR, SONG_TITLE);
        if (pause_clock || !song || !*song)
            return 0;                       /* no "0 of 0" with no song */
    }
    if (type != TAG_STR || line >= LINES)
        return lookup_next(start, type, id);
    if (start != labels) {
        /* The count line is before the clock lines in the View, so it asked before the patch knew
         * the panel object. Ask it to ask again: then it gets no answer, and "0 of 0" goes away. */
        labels = start;
        notify(TAG_STR, SONG_COUNT);
    }
    if (!pause_clock) {
        song = lookup_next(start, TAG_STR, SONG_TITLE);
        if (song && *song)
            return 0;
    }
    return (void *)make_text(line);
}

__attribute__((minsize)) int hook_notify(void *self, unsigned type, int id)
{
    int result = notify_next(self, type, id);

    if (type == TAG_STR && id == SONG_TITLE)
        notify_lines(0);
    /* Play brings the paused song back at once. */
    if (pause_clock && library && play_state(library) == PLAYING) {
        paused_s = 0;
        set_pause_clock(0);
    }
    return result;
}

__attribute__((minsize)) int hook_event(void *self, const int *event)
{
    if (!owner) {
        owner = self;
        void *provider = *(void **)((char *)self + OBJ_PROVIDER);
        library = provider ? *(void **)((char *)provider + PROVIDER_LIBRARY) : 0;
        timer_make(self, timer, 0, 0);
        start_timer();
    }
    if (self == owner && event[1] == EV_TIMER && event[2] == (int)timer) {
        notify_lines(0);
        count_pause();
        start_timer();
        return 1;
    }
    return event_next(self, event);
}
