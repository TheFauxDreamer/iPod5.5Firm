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
 *
 * The option Analogue (clock_face 1). The build adds the face of the Clock app in place of the time
 * line: an element of the class 0x5a80 with the ID FACE_ID and the owner word of the panel. Then
 * element + 0x148 is 0. In the Clock app it is the Clock provider. The hooks:
 *   0x1ab498: the call of the row draw 0x1ab064 in the draw method of the class ("bl"). For the
 *             panel face, the patch draws the face, the hands and the dot with the current time,
 *             in the same sequence as 0x1ab064.
 *   0x66d774: the delete method of the class (0x1ab664, chain). For the panel face, the patch
 *             forgets the element and frees its 50 picture bindings, as the label destructor
 *             0x244aac does. 0x1ab664 does not free them.
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
#define FACE_ID      0x7e44              /* the face element of the option Analogue */
#define ELEMENT_OWNER 0x14               /* element + 0x14: the owner */
#define ELEMENT_ID   0x1c                /* element + 0x1c: the ID (16 bits) */
#define FACE_DAY     0x80                /* the binding of the day face; the night face is + 0x88 */
#define FACE_NIGHT   0x88
#define FACE_BINDINGS 0x80               /* 6 face bindings from + 0x80, then 44 hand bindings */
#define FACE_COUNT   6
#define HAND_COUNT   44
#define HAND_IDS     0x7c                /* element + 0x7c: the first minute and hour hand IDs */
#define FACE_LIST    0x148               /* the Clock provider in the Clock app, 0 in the panel */
#define KEY_MODE     0x20                /* the colour of the gc is transparent */
#define SMALL        45                  /* the size of the clock pictures */
#define BIG          90                  /* the size of the panel face: 2 x SMALL */
#define FACE_R2      (88 * 88)           /* the face: radius 44, in half pixels from the centre */
#define GROUND_R2    (84 * 84)           /* in the rim of 2 pixels */
#define RIM_X        37                  /* a rim pixel of the Apple face: radius 21, 45 degrees */
#define RIM_Y        7
#define TICK_X       22                  /* a pixel of the tick at 12 of the Apple face */
#define TICK_Y       2
#define TICK_OUTER   (44 * SUB)          /* the ticks: from radius 44 to radius 35, 2.5 pixels wide */
#define TICK_INNER   (35 * SUB)
#define TICK_WIDTH   10
#define WHITE        0xffffu             /* the key colour: transparent in the panel */
#define NEAR_WHITE   0xffdfu             /* a white pixel in the face, so that it stays */
#define SPREAD       0x07e0f81fu         /* RGB565 in 32 bits, with a gap after each channel */
#define DAY_HANDS    0x3186u             /* RGB565 of the day dot 25049: (49, 48, 49) */
#define NIGHT_HANDS  0xef7du             /* RGB565 of the night dot 25050: (239, 239, 239) */
#define SUB          8                   /* the hands use 1/8 pixel units */
#define DISPLAY_FORMAT 0x1a              /* display_info + 0x1a: the format of a work surface */
#define SURFACE_PIXELS 4                 /* surface + 4: the pixels, stored in rows */
#define SURFACE_ROW  8                   /* surface + 8: the bytes of one row */
#define SURFACE_BITS 0xc                 /* surface + 0xc: the bits of one pixel */
#define SURFACE_FORMAT 0x14              /* surface + 0x14: the format; 0x2000 swaps the bytes */

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
int face_delete_next(void *element);
void clock_row_draw(void *element, void *gc, void *rect);           /* 0x1ab064 */
void picture_rect(int *rect, void *picture);                       /* 0x250714 */
void picture_draw(void *picture, void *gc, const int *from, void *to);  /* 0x2506bc */
void gc_colour(void *colour, void *gc);                            /* 0x2551dc */
unsigned gc_mode(void *gc);                                        /* 0x2551d4 */
void gc_set_colour(void *gc, const void *colour);                  /* 0x2106dc */
void gc_set_mode(void *gc, unsigned mode);                         /* 0x210290 */
void view_invalidate(void *view);                                  /* 0x21ac04 */
void *binding_free(void *binding);                                 /* 0x149e8c: gives the binding */
void surface_make(void *surface, const int *rect, unsigned format, int a, int b);  /* 0x13b91c */
void surface_free(void *surface);                                  /* 0x13ba74 */
void gc_make(void *gc, void *surface);                             /* 0x211ac8 */
void gc_free(void *gc);                                            /* 0x211c04 */
void blit(void *gc, void *from_gc, const int *from, const void *to);  /* 0x210114 */
extern unsigned char display_info[];                               /* RAM 0x10883614 */
void heap_free(void *memory);                                      /* 0x25a8f4 */

/* 0x11: the short time (12-hour or 24-hour). 2: the name of the day. The date is date_style. */
static const unsigned char styles[LINES - 1] = { 0x11, 2 };

/* An option in patch.json. 14: the short date (string 0xb3 of the language, for example "Nov 4 2026").
 * 8: the long date (string 0xab, for example "4 November 2026"). */
unsigned date_style = 14;

/* An option in patch.json: the seconds of a pause before the clock shows (0: never). A multiple of
 * TICK_S. */
unsigned pause_seconds = 300;

/* An option in patch.json: 0 Digital (the time line), 1 Analogue (the face of the Clock app). The
 * build adds the face element only for Analogue. */
unsigned clock_face = 0;

static const unsigned char white[4] = { 0xff, 0xff, 0xff, 0xff };
static const int small_rect[4] = { 0, 0, SMALL, SMALL }, big_rect[4] = { 0, 0, BIG, BIG };

/* sin(0..90 degrees) x 255 */
static const unsigned char sine[91] = {
    0, 4, 9, 13, 18, 22, 27, 31, 35, 40, 44, 49, 53, 57, 62, 66, 70, 75, 79, 83, 87, 91, 96, 100, 104,
    108, 112, 116, 120, 124, 127, 131, 135, 139, 143, 146, 150, 153, 157, 160, 164, 167, 171, 174, 177,
    180, 183, 186, 190, 192, 195, 198, 201, 204, 206, 209, 211, 214, 216, 219, 221, 223, 225, 227, 229,
    231, 233, 235, 236, 238, 240, 241, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 253, 254,
    254, 254, 255, 255, 255, 255
};

/* The 2 work surfaces (0xb4 bytes) and their graphics contexts (0x44 bytes), as in 0x1ab270. Only the
 * UI task draws, so static objects are safe and use no stack. */
static unsigned small_surface[45], big_surface[45], small_gc[17], big_gc[17];

static unsigned timer[10];               /* a firmware timer: 0x28 bytes */
static void *owner, *labels;             /* labels: the data object that the clock labels ask */
static char *face;                       /* the face element of the panel, until its delete */
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

/* The clock shows if there is no song title, or after a pause of pause_seconds. */
__attribute__((minsize)) static int clock_shows(void *start)
{
    const char *song;

    if (pause_clock)
        return 1;
    song = lookup_next(start, TAG_STR, SONG_TITLE);
    return !song || !*song;
}

__attribute__((minsize)) static void notify(unsigned type, int id)
{
    (*(notify_fn *)(*(char **)labels + NOTIFY_SLOT))(labels, type, id);
}

/* The clock lines, and with `song` also the song lines, the count and the cover of the panel. */
__attribute__((minsize)) static void notify_lines(int song)
{
    int line;

    if (face)
        view_invalidate(face);
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

    if (labels && start == labels && pause_clock &&
        ((type == TAG_STR && (unsigned)(id - SONG_TITLE) < 3) || (type == TAG_DRAW && id == SONG_COVER)))
        return 0;
    if (type == TAG_STR && id == SONG_COUNT && labels && start == labels && clock_shows(start))
        return 0;                           /* no "0 of 0" with no song */
    if (type != TAG_STR || line >= LINES)
        return lookup_next(start, type, id);
    if (start != labels) {
        /* The count line is before the clock lines in the View, so it asked before the patch knew
         * the panel object. Ask it to ask again: then it gets no answer, and "0 of 0" goes away. */
        labels = start;
        notify(TAG_STR, SONG_COUNT);
    }
    if (!clock_shows(start))
        return 0;
    return (void *)make_text(line);
}

/* The face element of the panel: the ID of the build, and no Clock provider. */
__attribute__((minsize)) static int panel_face(char *element)
{
    return *(unsigned short *)(element + ELEMENT_ID) == FACE_ID && !*(void **)(element + FACE_LIST);
}

/* The pixel (x, y) of a work surface of 16 bits. The firmware stores the pixels in rows. A rectangle
 * of the firmware is (top, left, bottom, right). */
__attribute__((minsize)) static unsigned short *pixel(void *surface, int x, int y)
{
    char *s = surface;

    return (unsigned short *)(*(char **)(s + SURFACE_PIXELS) + y * *(int *)(s + SURFACE_ROW) + x * 2);
}

__attribute__((minsize)) static unsigned spread(unsigned short value, unsigned swap)
{
    unsigned v = swap ? (unsigned short)(value << 8 | value >> 8) : value;

    return (v | v << 16) & SPREAD;
}

/* Writes a pixel of the 90 x 90 surface. A white pixel in the face becomes near white, so that the
 * blit with the key colour keeps it. */
__attribute__((minsize)) static void put(int x, int y, unsigned value, unsigned swap)
{
    value = (value | value >> 16) & 0xffff;
    if (value == WHITE)
        value = NEAR_WHITE;
    if (swap)
        value = (value << 8 | value >> 8) & 0xffff;
    *pixel(big_surface, x, y) = value;
}

/* A colour of the Apple face at 45 x 45, in the form of spread(). */
__attribute__((minsize)) static unsigned sample(int x, int y, unsigned swap)
{
    return spread(*pixel(small_surface, x, y), swap);
}

/* The ground of the face at 90 x 90, with the colours of the Apple face: out of the circle the key
 * colour, then a rim of 2 pixels, then the colour of column 17 of the Apple face at the same height.
 * Column 17 has no tick from row 2 to row 42. It gives the shine and the gradient. */
__attribute__((minsize)) static void ground(unsigned swap)
{
    int x, y, u, v, row;

    for (x = 0; x < BIG; x++)
        for (y = 0; y < BIG; y++) {
            u = 2 * x + 1 - BIG;
            v = 2 * y + 1 - BIG;
            row = y >> 1;
            if (row < 2)
                row = 2;
            if (row > 42)
                row = 42;
            if (u * u + v * v > FACE_R2)
                *pixel(big_surface, x, y) = WHITE;
            else
                put(x, y, u * u + v * v > GROUND_R2 ? sample(RIM_X, RIM_Y, swap) : sample(17, row, swap), swap);
        }
}

/* sin(degrees) x 255, for 0 to 359 degrees. */
__attribute__((minsize)) static int sin255(int degrees)
{
    int sign = degrees >= 180 ? -1 : 1;

    if (degrees >= 180)
        degrees -= 180;
    return sign * sine[degrees > 90 ? 180 - degrees : degrees];
}

/* A sample point in 1/8 pixels is in the shape: a convex polygon of `points` points, or a dot (0
 * points: the centre and the radius). */
__attribute__((minsize)) static int inside(const int *shape, int points, int x, int y)
{
    int i, j, cross, sign = 0;

    if (!points)
        return (x - shape[0]) * (x - shape[0]) + (y - shape[1]) * (y - shape[1]) <= shape[2] * shape[2];
    for (i = 0; i < points; i++) {
        j = i + 1 < points ? i + 1 : 0;
        cross = (shape[2 * j] - shape[2 * i]) * (y - shape[2 * i + 1]) - (shape[2 * j + 1] - shape[2 * i + 1]) * (x - shape[2 * i]);
        if (cross) {
            if (sign && (cross > 0) != (sign > 0))
                return 0;
            sign = cross;
        }
    }
    return 1;
}

/* Paints a shape with 4 x 4 samples in each pixel: the colour covers the pixel in the part of the
 * samples that are in the shape. Only the pixels in the box of the shape are examined. */
__attribute__((minsize)) static void paint(const int *shape, int points, unsigned colour, unsigned swap)
{
    int x, y, i, cover, box[4];

    if (!points) {
        box[0] = shape[0] - shape[2];
        box[1] = shape[1] - shape[2];
        box[2] = shape[0] + shape[2];
        box[3] = shape[1] + shape[2];
    } else {
        box[0] = box[2] = shape[0];
        box[1] = box[3] = shape[1];
        for (i = 2; i < 2 * points; i++) {
            if (shape[i] < box[i & 1])
                box[i & 1] = shape[i];
            if (shape[i] > box[2 + (i & 1)])
                box[2 + (i & 1)] = shape[i];
        }
    }
    for (i = 0; i < 4; i++) {
        box[i] = (box[i] >> 3) + (i >> 1);              /* pixels: the end is the next pixel */
        if (box[i] < 0)
            box[i] = 0;
        if (box[i] > BIG)
            box[i] = BIG;
    }
    for (x = box[0]; x < box[2]; x++)
        for (y = box[1]; y < box[3]; y++) {
            cover = 0;
            for (i = 0; i < 16; i++)
                cover += inside(shape, points, x * SUB + 1 + 2 * (i & 3), y * SUB + 1 + 2 * (i >> 2));
            if (cover)
                put(x, y, (cover * colour + (16 - cover) * spread(*pixel(big_surface, x, y), swap)) >> 4 & SPREAD, swap);
        }
}

/* A point at `radius` from the centre in the direction `degrees`, moved `side` to the right of that
 * direction. The values are in 1/8 pixels. A shift of 8 in place of a division by 255 makes the
 * distances 0.4 % shorter, and needs no division function. */
__attribute__((minsize)) static void point(int *at, int degrees, int radius, int side)
{
    int s = sin255(degrees), c = sin255(degrees < 270 ? degrees + 90 : degrees - 270);

    at[0] = BIG * SUB / 2 + ((radius * s + side * c) >> 8);
    at[1] = BIG * SUB / 2 + ((side * s - radius * c) >> 8);
}

/* A hand (3 points: the tip and the 2 sides of the base) or a tick (4 points). */
__attribute__((minsize)) static void ray(int degrees, int outer, int inner, int width, unsigned colour, unsigned swap)
{
    int shape[8];

    point(shape, degrees, outer, inner ? width : 0);
    point(shape + 2, degrees, inner, width);
    point(shape + 4, degrees, inner, -width);
    point(shape + 6, degrees, outer, -width);
    paint(shape, inner ? 4 : 3, colour, swap);
}

/* Replaces the call of 0x1ab064 in the draw method 0x1ab460 of the class 0x5a80. */
__attribute__((minsize)) void hook_face_draw(char *element, void *gc, void *rect)
{
    unsigned calendar[3], colour, mode, hour, minute, format, swap, ink;
    int from[4], x, y;
    void *picture, *source = small_gc;
    const int *source_rect = small_rect;
    static const int dot[3] = { BIG * SUB / 2, BIG * SUB / 2, 5 * SUB };

    if (!panel_face(element)) {
        clock_row_draw(element, gc, rect);
        return;
    }
    face = element;
    if (!clock_face || !clock_shows(*(void **)(element + ELEMENT_OWNER)))
        return;
    /* The Clock app: the day face from 6:00 to 17:59 (an unsigned compare), else the night face. */
    current_time(calendar);
    hour = (calendar[0] >> 16) & 0xff;
    minute = (calendar[0] >> 8) & 0xff;
    picture = *(void **)(element + (hour - 6 < 12 ? FACE_DAY : FACE_NIGHT));
    ink = hour - 6 < 12 ? DAY_HANDS : NIGHT_HANDS;

    /* The Apple face at 45 x 45 on white in a work surface, as 0x1ab064 draws it. The patch takes its
     * colours from it. */
    format = *(unsigned short *)(display_info + DISPLAY_FORMAT);
    surface_make(small_surface, small_rect, format, 0, 0);
    gc_make(small_gc, small_surface);
    if (((unsigned *)small_surface)[SURFACE_BITS / 4] == 16)
        for (x = 0; x < SMALL; x++)
            for (y = 0; y < SMALL; y++)
                *pixel(small_surface, x, y) = WHITE;
    gc_set_colour(small_gc, white);
    gc_set_mode(small_gc, KEY_MODE);
    if (picture) {
        picture_rect(from, picture);
        picture_draw(picture, small_gc, from, from);
    }

    /* The firmware cannot scale a picture (the blit 0x1216a0 copies 1:1), and a scale of 45 x 45 is not
     * sharp. Thus draw the face, the ticks, the hands and the dot at 90 x 90, with the colours of the
     * Apple face. */
    surface_make(big_surface, big_rect, format, 0, 0);
    gc_make(big_gc, big_surface);
    if (((unsigned *)small_surface)[SURFACE_BITS / 4] == 16 && ((unsigned *)big_surface)[SURFACE_BITS / 4] == 16) {
        swap = *(unsigned short *)((char *)small_surface + SURFACE_FORMAT) & 0x2000;
        ground(swap);
        for (x = 0; x < 360; x += 30)
            ray(x, TICK_OUTER, TICK_INNER, TICK_WIDTH, sample(TICK_X, TICK_Y, swap), swap);
        if (hour >= 12)
            hour -= 12;
        ray(hour * 30 + (minute >> 1), 22 * SUB, 0, 4 * SUB, spread(ink, 0), swap);
        ray(minute * 6, 36 * SUB, 0, 3 * SUB, spread(ink, 0), swap);
        paint(dot, 0, spread(ink, 0), swap);
        source = big_gc;
        source_rect = big_rect;
    }

    /* The blit with the key colour white: the corners and the ground do not show. */
    gc_colour(&colour, gc);
    mode = gc_mode(gc);
    gc_set_colour(gc, white);
    gc_set_mode(gc, KEY_MODE);
    blit(gc, source, source_rect, rect);
    gc_set_mode(gc, mode);
    gc_set_colour(gc, &colour);
    gc_free(big_gc);
    surface_free(big_surface);
    gc_free(small_gc);
    surface_free(small_surface);
}

/* The delete method of the class 0x5a80 (vtable + 4). */
__attribute__((minsize)) int hook_face_delete(char *element)
{
    void **binding;

    if (element && panel_face(element)) {
        if (element == face)
            face = 0;
        /* The build gives hand IDs 0, so 0x1ab4ac makes no hand bindings and does not set their words. */
        for (binding = (void **)(element + FACE_BINDINGS);
             binding < (void **)(element + FACE_BINDINGS) + FACE_COUNT + (*(unsigned *)(element + HAND_IDS) ? HAND_COUNT : 0);
             binding++)
            if (*binding) {
                heap_free(binding_free(*binding));
                *binding = 0;
            }
    }
    return face_delete_next(element);
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
