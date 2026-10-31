/* diagnostic-log: a text log of the playback, the memory, the power, the artwork and the performance.
 * Each area has an option in patch.json. An area that is off writes no lines. Refer to re/diagnostic-log.md
 * and re/playback-log.md. This patch has the hooks of playback-log, thus only one of the two can be on.
 *
 * Hooks of the shuffle:
 *  - b at 0xb40c4 (start a shuffled play list; first instruction push {r3-r5, lr}): the caller,
 *    the count, the current song, the settings bytes +0x92 (albums) and +0x93 (Album Mix).
 *  - bl at 0xb4128 (the call of the shuffle 0x94440 in 0xb40c4): the time, the random state before
 *    and after, the count of the result, empty positions and repeated songs, the first songs.
 *  - bl at 0xbb440 (the call of the shuffle in the smart playlist evaluation 0xbb28c).
 * Hooks of the playback:
 *  - b at 0xac4c4 (the "next song" action; push {r3-r11, lr}): the caller, the flags, the position.
 *  - bl at 0xac55c (0x1968c0, the next item of the play list), bl at 0xac588 (0xeb610 with no
 *    song: the stop) and bl at 0xac5d4 (0xeb610 when the player does not play).
 *  - b at 0xac6f4 (play a song; push {r4-r11, lr}): the caller, the item, the result.
 *  - bl at 0xac750 (0xeb610, set the song) and bl at 0xac7b4 (0x10b894, open the decoder) in 0xac6f4.
 * Hooks of the memory:
 *  - b at 0xc7518 and b at 0x11ca20 (the two allocators; push {r4-r6, lr}): each failed allocation.
 * The file:
 *  - bl at 0x1d8260 in the UI event handler (the call of 0x1d8570), the site of video-log and
 *    usb-host-probe. On a button or wheel event, at most one time each 5 s, the patch writes the log
 *    to iPod_Control\iTunes\iPodFirmDiagnosticLog. iPodFirm makes the file (LOG_BYTES) with the action
 *    "Clear the Diagnostic Log", because the file functions write only to an existing file.
 *    This hook also records each key push and release (key code: bits 16-23 of event + 0x10).
 *  - bl at 0x1d9344 (0x1ee8d0, the sleep sequence): a line and a file write before the sleep. The
 *    sleep sequence itself writes the settings file, thus a file write is safe at this site.
 * Hooks of the power:
 *  - bl at 0x1dfe18 (0xb43dc, the sleep function): a line before the sleep and a line after the wake.
 *  - b at 0x265cc8 (storage power; push {r3-r11, lr}): each change of the state.
 * Hooks of the artwork:
 *  - bl at 0x2055dc (0x1f161c) and bl at 0x205854 (0x2258a4) in ArtworkLoadTask: the lookup and the load.
 *  - b at 0x8f38c and b at 0x8f464 (file open and file read): each slow open, and each large or slow read.
 * Hook of the performance:
 *  - word at 0x6701f0 (the event method 0x1d81cc): the longest UI event in each sample.
 *
 * The buffer is in the patch (.bss), thus the log operates also when the heap is full. The hooks
 * disable the interrupts while a line goes into the buffer, because several tasks write lines.
 *
 * File format: plain text, LOG_BYTES bytes. The first INFO bytes are the information block: the
 * line "PL02 diagnostic-log 2.0", the RAM line, the counts, the line "areas ...", the line "settings ..." (Shuffle, Repeat and
 * the Hold Select value of up-next) and the line "list <JSON>" (the iPodFirm list of the build, with
 * the names, the versions and the options of the patches). Spaces fill the rest of the block,
 * and a line end ends it. The log lines follow. Zero bytes fill the rest of the file. When the buffer
 * is full, the patch removes the oldest half of the lines and counts them ("dropped").
 *
 * The UI task reads the settings before each file write. Shuffle and Repeat are in RAM. Hold Select
 * is in the file of up-next, and the patch reads this file only for a write, so that a wheel event
 * does not start the disk. A change of a value also gives a line "settings ..." in the log. */

#include <stdarg.h>

#define LOG_PATH   "iPod_Control\\iTunes\\iPodFirmDiagnosticLog"
#define MODE_DATA  0x64617461u                          /* 'data' */
#define LOG_BYTES  32768                                /* the size of the file and of the buffer */
#define INFO       2048                                 /* the size of the information block */
#define LINE_MAX   192
#define WRITE_US   5000000                              /* at most one file write each 5 s */
#define USEC       (*(volatile unsigned *)0x60005010)   /* the microsecond timer */
#define PLAYLIST   (*(char *volatile *)0x1081d9cc)      /* the play list object (0x196418 makes it) */
#define RAND_STATE (*(volatile unsigned *)0x1081e048)   /* the state of the random index 0xe5978 */
#define RAND_GUARD (*(volatile unsigned *)0x1081e044)   /* 0: the seed is not set yet */
#define LIST_FROM  0x736800                             /* the search area of the iPodFirm list */
#define LIST_TO    0x7f8000
#define HOLD_PATH  "iPod_Control\\iTunes\\iPodFirmHoldSelect"
#define INFO_HEAD  384                                  /* the maximum of the text before the list */
#define LIST_MAX   (INFO - INFO_HEAD - 8)

#define IDLE_STATS ((volatile unsigned *)0x14983040)     /* the statistics of 0xded04: +0 and +8, two cores */
#define SAMPLE_US  30000000                             /* at most one sample each 30 s */
#define HEAP_STEP  65536                                /* the change of the free heap that gives a line */
#define LARGE_READ 16384                                /* the smallest read that gives a line */
#define SLOW_MS    100                                  /* the smallest time of a slow open or read */
#define PATH_MAX   60

#define FIELD(type, object, offset) (*(type *)((char *)(object) + (offset)))
#define LOG(area, ...) do { if (area) line(__VA_ARGS__); } while (0)

void fw_memset0(void *p, unsigned size);                                   /* 0x7ccd0 */
void fw_strcpy(char *dst, const char *src);                                /* 0x7cd6c */
int fw_vsnprintf(char *buf, unsigned size, const char *fmt, va_list args); /* 0x7b114 */
int fw_snprintf(char *buf, unsigned size, const char *fmt, ...);           /* 0x7b240 */
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_write(void *fh, unsigned *len, const void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
int fw_long_play_timer(void *ui, void *event);         /* the original call at 0x1d8260 */
unsigned heap_free(void);                              /* 0xc7444 */
unsigned ram_size(void);                               /* 0x9d9d0: SysInfo + 0xe0 */
void *settings_object(void);                           /* 0x193090 */
int get_mode(void *app);                               /* 0x9edb0: 0 Off, 1 Songs, 2 Albums */
int get_repeat(void *app);                             /* 0x9e96c: 0 Off, 1 One, 2 All */
void *next_item(void *playlist, int song, unsigned flags);                 /* 0x1968c0 */
int set_song(void *player, void *item, unsigned flags);                    /* 0xeb610 */
int open_decoder(void *player, void *item, unsigned flags, void *out, void *cache); /* 0x10b894 */
void *shuffle(void *list, void *current, int albums, int mix);             /* 0x94440 */
/* Set by the patcher (chain): the previous targets of the hooks. */
void next_chain(void *player, unsigned flags, unsigned a2, unsigned a3);
int play_chain(void *player, void *item, unsigned flags);
int start_chain(void *list, void *current, int reset, unsigned a3);
void *alloc_chain(unsigned size, unsigned align);
void *new_chain(unsigned size, unsigned flags);
int drive_chain(int on, unsigned a1, unsigned a2, unsigned a3);
int file_open_chain(void *path_record, void *fh, int zero, unsigned mode);
int file_read_chain(void *fh, unsigned *len, void *buf, unsigned a3);
int ui_chain(void *ui, void *event);
void next_continue(void);                              /* 0xac4c8 */
void play_continue(void);                              /* 0xac6f8 */
void start_continue(void);                             /* 0xb40c8 */
void alloc_continue(void);                             /* 0xc751c */
void new_continue(void);                               /* 0x11ca24 */
void drive_continue(void);                             /* 0x265ccc */
void file_open_continue(void);                         /* 0x8f390 */
void file_read_continue(void);                         /* 0x8f468 */
unsigned power_raw(void);                              /* 0x265164: high 16 bits the channel, low 16 bits the value */
int sleep_sequence(void *app, int flag);               /* 0x1ee8d0: the original call at 0x1d9344 */
void sleep_function(unsigned a, int b);                /* 0xb43dc: the original call at 0x1dfe18 */
void *art_find(void *a, void *b);                      /* 0x1f161c: the original call at 0x2055dc */
int art_load(void *a, void *b, unsigned c, int d, int e); /* 0x2258a4: the original call at 0x205854 */

/* The areas of the log. The app writes these values at the build (options in patch.json). */
unsigned log_playback = 1, log_memory = 1, log_power = 1, log_artwork = 1, log_performance = 1;

static char L[LOG_BYTES];                              /* the log: INFO, then the lines */
static unsigned used = INFO, lines, dropped, lost, writes, last_write_us, changed;
static unsigned last_us, ms_total, us_rest, started;
static unsigned lowest, failures, fail_size, fail_from, fail_repeats;
static int writing;

/* ---- The buffer ------------------------------------------------------------------------------- */

static unsigned irq_off(void)
{
    unsigned old, tmp;
    __asm__ volatile("mrs %0, cpsr\n\torr %1, %0, #0xc0\n\tmsr cpsr_c, %1" : "=r"(old), "=r"(tmp) : : "memory");
    return old;
}

static void irq_restore(unsigned old)
{
    __asm__ volatile("msr cpsr_c, %0" : : "r"(old) : "memory");
}

/* Removes the oldest half of the lines. Not during a file write. */
static int make_room(unsigned n)
{
    unsigned cut, i, j;
    if (used + n <= LOG_BYTES)
        return 1;
    if (writing)
        return 0;
    cut = INFO + (LOG_BYTES - INFO) / 2;
    while (cut < used && L[cut - 1] != '\n')
        cut++;
    for (i = INFO; i < cut; i++)
        if (L[i] == '\n')
            dropped++;
    for (i = INFO, j = cut; j < used; )
        L[i++] = L[j++];
    for (j = i; j < used; j++)
        L[j] = 0;
    used = i;
    return used + n <= LOG_BYTES;
}

/* One line: the time in seconds since the first line, then the text. */
static void line(const char *fmt, ...)
{
    char t[LINE_MAX];
    unsigned n, i, old, now;
    va_list ap;
    old = irq_off();
    now = USEC;
    if (!started) {
        started = 1;
        last_us = now;
    }
    us_rest += now - last_us;
    last_us = now;
    ms_total += us_rest / 1000;
    us_rest %= 1000;
    n = fw_snprintf(t, 16, "%6u.%03u ", ms_total / 1000, ms_total % 1000);
    if (n > 15)
        n = 15;
    va_start(ap, fmt);
    i = fw_vsnprintf(t + n, sizeof t - n - 1, fmt, ap);
    va_end(ap);
    n += i < sizeof t - n - 1 ? i : sizeof t - n - 2;
    t[n++] = '\n';
    if (make_room(n)) {
        for (i = 0; i < n; i++) {
            char c = t[i];
            L[used + i] = (c == '\n' && i != n - 1) || c == '\t' ? ' ' : c;
        }
        used += n;
        lines++;
        changed = 1;
    } else {
        lost++;
    }
    irq_restore(old);
}

/* The free heap, and the lowest value since the start. */
static unsigned heap(void)
{
    unsigned f = heap_free();
    if (!lowest || f < lowest)
        lowest = f;
    return f;
}

/* The play list: the position (1 = the first song, 0 = none), the count and the shuffle bit. */
static void list_state(int *at, int *count, int *shuffled)
{
    char *pl = PLAYLIST, *tl = pl ? FIELD(char *, pl, 0x04) : 0, *root = tl ? FIELD(char *, tl, 0x28) : 0;
    *at = pl ? FIELD(int, pl, 0x14) + 1 : 0;
    *count = root ? FIELD(unsigned short, root, 0x32) : 0;
    *shuffled = tl ? FIELD(unsigned char, tl, 0xec) & 1 : 0;
}

/* The low 32 bits of the dbid (mhit + 0x70) of an item: item + 0x20 is the track, and track + 0x108 is
 * the dbid, which album-art also uses. Item + 0x10 comes from a counter (0xa01e8), and track + 0x20
 * was 0 on the real iPod. The app finds the song with this value. */
static unsigned song_of(void *item)
{
    char *track = item ? FIELD(char *, item, 0x20) : 0;
    return track ? FIELD(unsigned, track, 0x108) : 0;
}

/* ---- The shuffle ------------------------------------------------------------------------------ */

__attribute__((naked)) int start_original(void *list, void *current, int reset, unsigned a3)
{
    __asm__ volatile("push {r3, r4, r5, lr}\n\tb start_continue\n");
}

int hook_start(void *list, void *current, int reset, unsigned a3)
{
    unsigned from = (unsigned)__builtin_return_address(0);
    char *root = list ? FIELD(char *, list, 0x28) : 0, *settings = list ? FIELD(char *, list, 0x08) : 0;
    int r;
    LOG(log_playback, "shuffle start from=%x count=%u current=%x albums=%u mix=%u reset=%d heap=%u", from,
         root ? FIELD(unsigned short, root, 0x32) : 0, song_of(current),
         settings ? settings[0x92] : 0, settings ? settings[0x93] : 0, reset, heap());
    r = start_chain(list, current, reset, a3);
    LOG(log_playback, "shuffle end result=%d", r);
    return r;
}

/* The call of 0x94440 in 0xb40c4. 0xb40c4 then writes the position i to item + 0x24 of each item of
 * the result. The hook does this write first and then reads it again: an item that occurs two times
 * keeps only its last position, thus the count of the differences is the count of repeated songs. */
void *hook_shuffle(void *list, void *current, int albums, int mix)
{
    unsigned t0 = USEC, s0 = RAND_STATE, g0 = RAND_GUARD, n, i, empty = 0, repeated = 0, first[3] = {0, 0, 0};
    void *r = shuffle(list, current, albums, mix);
    unsigned ms = (USEC - t0) / 1000;
    if (!r) {
        LOG(log_playback, "  shuffle failed: no list (ms=%u heap=%u)", ms, heap());
        return r;
    }
    n = FIELD(unsigned, r, 0x0c);
    for (i = 0; i < n; i++) {
        char *item = FIELD(char *, r, 0x10 + i * 4);
        if (item)
            FIELD(unsigned, item, 0x24) = i;
    }
    for (i = 0; i < n; i++) {
        char *item = FIELD(char *, r, 0x10 + i * 4);
        if (!item)
            empty++;
        else if (FIELD(unsigned, item, 0x24) != i)
            repeated++;
        if (i < 3)
            first[i] = song_of(item);
    }
    LOG(log_playback, "  shuffle n=%u empty=%u repeated=%u ms=%u seeded=%u state %x->%x first=%x,%x,%x heap=%u", n, empty,
         repeated, ms, g0 != 0, s0, RAND_STATE, first[0], first[1], first[2], heap());
    return r;
}

/* The call of 0x94440 in the smart playlist evaluation ("selected by random"). */
void *hook_smart_shuffle(void *list, void *current, int albums, int mix)
{
    unsigned t0 = USEC;
    void *r = shuffle(list, current, albums, mix);
    LOG(log_playback, "smart playlist shuffle n=%u ms=%u heap=%u", r ? FIELD(unsigned, r, 0x0c) : 0, (USEC - t0) / 1000, heap());
    return r;
}

/* ---- The playback ----------------------------------------------------------------------------- */

__attribute__((naked)) void next_original(void *player, unsigned flags, unsigned a2, unsigned a3)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}\n\tb next_continue\n");
}

/* The "next song" action 0xac4c4(player, flags). The current item is player + 0x2a4. */
void hook_next(void *player, unsigned flags, unsigned a2, unsigned a3)
{
    unsigned from = (unsigned)__builtin_return_address(0);
    int at, count, shuffled;
    list_state(&at, &count, &shuffled);
    LOG(log_playback, "next from=%x flags=%x at=%d/%d shuffle=%d song=%x heap=%u", from, flags, at, count, shuffled,
         song_of(FIELD(void *, player, 0x2a4)), heap());
    next_chain(player, flags, a2, a3);
    list_state(&at, &count, &shuffled);
    LOG(log_playback, "next end at=%d/%d song=%x", at, count, song_of(FIELD(void *, player, 0x2a4)));
}

void *hook_next_item(void *playlist, int song, unsigned flags)
{
    void *r = next_item(playlist, song, flags);
    int at, count, shuffled;
    list_state(&at, &count, &shuffled);
    LOG(log_playback, "  next item=%x song=%x at=%d/%d", (unsigned)r, song_of(r), at, count);
    return r;
}

/* 0xeb610(player, 0, 0) in 0xac4c4: no next song. The player stops, and the menus show. */
int hook_stop(void *player, void *item, unsigned flags)
{
    int at, count, shuffled;
    list_state(&at, &count, &shuffled);
    LOG(log_playback, "  stop: no next song at=%d/%d heap=%u", at, count, heap());
    return set_song(player, item, flags);
}

/* 0xeb610 in 0xac4c4 when the player does not play, and in 0xac6f4. -0x32: the song cannot play.
 * -0x6c: no memory (0xa8dc4). */
int hook_set(void *player, void *item, unsigned flags)
{
    int r = set_song(player, item, flags);
    if (r != 0)
        LOG(log_playback, "  set song failed: %d song=%x heap=%u", r, song_of(item), heap());
    return r;
}

int hook_open(void *player, void *item, unsigned flags, void *out, void *cache)
{
    int r = open_decoder(player, item, flags, out, cache);
    if (r != 0)
        LOG(log_playback, "  decoder open failed: %d heap=%u", r, heap());
    return r;
}

__attribute__((naked)) int play_original(void *player, void *item, unsigned flags)
{
    __asm__ volatile("push {r4, r5, r6, r7, r8, r9, r10, r11, lr}\n\tb play_continue\n");
}

/* Play a song: 0xac6f4(player, item, flags). 0: correct. */
int hook_play(void *player, void *item, unsigned flags)
{
    unsigned from = (unsigned)__builtin_return_address(0);
    int r;
    LOG(log_playback, "play from=%x song=%x flags=%x heap=%u", from, song_of(item), flags, heap());
    r = play_chain(player, item, flags);
    LOG(log_playback, "play end result=%d", r);
    return r;
}

/* ---- The memory ------------------------------------------------------------------------------- */

static void failed(unsigned size, unsigned from, int kind)
{
    failures++;
    if (size == fail_size && from == fail_from) {
        fail_repeats++;
        return;
    }
    if (fail_repeats)
        LOG(log_memory, "  = the last failed allocation %u more times", fail_repeats);
    fail_size = size;
    fail_from = from;
    fail_repeats = 0;
    LOG(log_memory, "no memory: size=%u allocator=%d from=%x heap=%u", size, kind, from, heap());
}

__attribute__((naked)) void *alloc_original(unsigned size, unsigned align)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb alloc_continue\n");
}

__attribute__((naked)) void *new_original(unsigned size, unsigned flags)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb new_continue\n");
}

void *hook_alloc(unsigned size, unsigned align)
{
    unsigned from = (unsigned)__builtin_return_address(0);
    void *p = alloc_chain(size, align);
    if (!p && size)
        failed(size, from, 1);
    return p;
}

void *hook_new(unsigned size, unsigned flags)
{
    unsigned from = (unsigned)__builtin_return_address(0);
    void *p = new_chain(size, flags);
    if (!p && size)
        failed(size, from, 2);
    return p;
}

/* ---- The power ------------------------------------------------------------------------------- */

static void flush_log(void);

/* The sleep sequence. It runs before the sleep, thus the log gets to the disk in time. */
int hook_sleep_start(void *app, int flag)
{
    LOG(log_power, "sleep start flag=%d heap=%u", flag, heap());
    flush_log();
    return sleep_sequence(app, flag);
}

/* The sleep function returns after the wake. */
void hook_sleep(unsigned a, int b)
{
    LOG(log_power, "sleep now a=%x b=%d", a, b);
    sleep_function(a, b);
    LOG(log_power, "wake heap=%u", heap());
}

__attribute__((naked)) int drive_original(int on, unsigned a1, unsigned a2, unsigned a3)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}\n\tb drive_continue\n");
}

static int drive_state = -1;

/* The storage power: 0x265cc8(on). The function returns at once if the state does not change. */
int hook_drive(int on, unsigned a1, unsigned a2, unsigned a3)
{
    unsigned from = (unsigned)__builtin_return_address(0);
    int r = drive_chain(on, a1, a2, a3);
    if (on != drive_state) {
        drive_state = on;
        LOG(log_power, "storage power=%d from=%x", on, from);
    }
    return r;
}

/* ---- The artwork ------------------------------------------------------------------------------ */

void *hook_art_find(void *a, void *b)
{
    unsigned t0 = USEC;
    void *r = art_find(a, b);
    LOG(log_artwork, "art find found=%d ms=%u", r != 0, (USEC - t0) / 1000);
    return r;
}

int hook_art_load(void *a, void *b, unsigned c, int d, int e)
{
    unsigned t0 = USEC;
    int r = art_load(a, b, c, d, e);
    LOG(log_artwork, "art load result=%d ms=%u", r, (USEC - t0) / 1000);
    return r;
}

__attribute__((naked)) int file_open_original(void *path_record, void *fh, int zero, unsigned mode)
{
    __asm__ volatile("push {r2, r3, r4, r5, r6, r7, r8, lr}\n\tb file_open_continue\n");
}

__attribute__((naked)) int file_read_original(void *fh, unsigned *len, void *buf, unsigned a3)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, r8, r9, r10, r11, lr}\n\tb file_read_continue\n");
}

/* Keep this hook short: it runs in many tasks. The path text is at path record + 4. */
int hook_file_open(void *path_record, void *fh, int zero, unsigned mode)
{
    unsigned from = (unsigned)__builtin_return_address(0), t0, ms, i;
    char name[PATH_MAX + 1];
    int r;
    if (!log_artwork || writing)
        return file_open_chain(path_record, fh, zero, mode);
    t0 = USEC;
    r = file_open_chain(path_record, fh, zero, mode);
    ms = (USEC - t0) / 1000;
    if (ms < SLOW_MS)
        return r;
    for (i = 0; i < PATH_MAX; i++) {
        char c = ((char *)path_record)[4 + i];
        if (c < 0x20 || c > 0x7e)
            break;
        name[i] = c;
    }
    name[i] = 0;
    line("file open ms=%u from=%x result=%d path=%s", ms, from, r, name);
    return r;
}

/* Keep this hook short: it runs in many tasks. */
int hook_file_read(void *fh, unsigned *len, void *buf, unsigned a3)
{
    unsigned from = (unsigned)__builtin_return_address(0), want, t0, ms;
    int r;
    if (!log_artwork || writing)
        return file_read_chain(fh, len, buf, a3);
    want = *len;
    t0 = USEC;
    r = file_read_chain(fh, len, buf, a3);
    ms = (USEC - t0) / 1000;
    if (want >= LARGE_READ || ms >= SLOW_MS)
        line("file read size=%u ms=%u from=%x result=%d", want, ms, from, r);
    return r;
}

/* ---- The performance -------------------------------------------------------------------------- */

static unsigned ui_longest, write_ms;
static unsigned sample_us, sample_core0, sample_core1, power_log, heap_log;

int hook_ui(void *ui, void *event)
{
    unsigned t0 = USEC, us;
    int r = ui_chain(ui, event);
    us = USEC - t0;
    if (us > ui_longest)
        ui_longest = us;
    return r;
}

/* One sample at most each 30 s, at a button or wheel event. Thus a time with no event has no sample.
 * idle is the part of the time, in tenths of a percent, that each core was idle. */
static void sample(void)
{
    unsigned now = USEC, i0 = IDLE_STATS[0], i1 = IDLE_STATS[2], ms = (now - sample_us) / 1000, raw, f;
    if (log_performance && sample_us && ms)
        line("perf ms=%u idle=%u,%u ui=%u us write=%u ms heap=%u", ms, (i0 - sample_core0) / ms,
             (i1 - sample_core1) / ms, ui_longest, write_ms, heap());
    sample_us = now;
    sample_core0 = i0;
    sample_core1 = i1;
    ui_longest = 0;
    f = heap();
    if (f + HEAP_STEP <= heap_log || heap_log + HEAP_STEP <= f) {
        heap_log = f;
        LOG(log_memory, "memory heap=%u lowest=%u failed=%u", f, lowest, failures);
    }
    raw = power_raw();
    if (raw != power_log) {
        power_log = raw;
        LOG(log_power, "power channel=%u value=%u", raw >> 16, raw & 0xffff);
    }
}

/* ---- The file --------------------------------------------------------------------------------- */

/* The iPodFirm list of the build in RAM (osos is in RAM), or 0. The magic text is kept with each
 * byte XOR 0x55, so that the search does not find the text in this patch. */
static const unsigned char magic[] = {
    'i' ^ 0x55, 'P' ^ 0x55, 'o' ^ 0x55, 'd' ^ 0x55, 'F' ^ 0x55, 'i' ^ 0x55, 'r' ^ 0x55, 'm' ^ 0x55, 'M' ^ 0x55,
    'a' ^ 0x55, 'n' ^ 0x55, 'i' ^ 0x55, 'f' ^ 0x55, 'e' ^ 0x55, 's' ^ 0x55, 't' ^ 0x55, '1' ^ 0x55, 0 ^ 0x55,
};
static const char *list_json;
static unsigned list_length, list_searched;

static void find_list(void)
{
    const unsigned char *p;
    unsigned i;
    if (list_searched)
        return;
    list_searched = 1;
    for (p = (const unsigned char *)LIST_FROM; p + sizeof magic + 4 <= (const unsigned char *)LIST_TO; p += 16) {
        if (p[0] != (magic[0] ^ 0x55))
            continue;
        for (i = 1; i < sizeof magic && p[i] == (magic[i] ^ 0x55); i++)
            ;
        if (i == sizeof magic) {
            list_json = (const char *)p + sizeof magic + 4;
            list_length = p[sizeof magic] | p[sizeof magic + 1] << 8 | p[sizeof magic + 2] << 16 | p[sizeof magic + 3] << 24;
        }
    }
}

/* The settings. -1: not known. Only the UI task calls these functions. */
static int shuffle_now = -1, repeat_now = -1, hold_now = -1;
static int shuffle_log = -2, repeat_log = -2, hold_log = -2;

static const char *const shuffle_names[] = {"Off", "Songs", "Albums", "Album Mix"};
static const char *const repeat_names[] = {"Off", "One", "All"};
static const char *const hold_names[] = {"On-The-Go", "Play Next", "Play Last", "Cover Flow"};

static const char *name_of(const char *const *names, int count, int value)
{
    return value >= 0 && value < count ? names[value] : "not known";
}

/* Shuffle and Repeat, from RAM. The app is settings_object + 0x98, as in shuffle-album-mix. */
static void read_ram_settings(void)
{
    void *object = settings_object();
    char *app = object ? FIELD(char *, object, 0x98) : 0;
    char *settings = app ? FIELD(char *, app, 0xca0) : 0;
    if (!settings)
        return;
    shuffle_now = get_mode(app);
    if (shuffle_now == 2 && settings[0x93])
        shuffle_now = 3;
    repeat_now = get_repeat(app);
}

/* The Hold Select value of up-next: one character '0' to '3' in its file. No file: -1. */
static void read_hold(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], got = 1;
    unsigned char c = 0;
    hold_now = -1;
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, HOLD_PATH);
    fw_memset0(fh, sizeof fh);
    if (file_open(path, fh, 0, MODE_DATA) == 0) {
        if (file_read(fh, &got, &c) == 0 && got == 1 && c >= '0' && c <= '3')
            hold_now = c - '0';
        file_close(fh);
    }
}

/* The information block: INFO bytes, spaces at the end and a line end. */
static void info(void)
{
    unsigned n, i, f = heap();
    find_list();
    n = fw_snprintf(L, INFO_HEAD,
                    "PL02 diagnostic-log 2.0\nram=%u MB heap=%u lowest=%u failed=%u\nlines=%u dropped=%u lost=%u writes=%u\n"
                    "areas playback=%u memory=%u power=%u artwork=%u performance=%u\n"
                    "settings shuffle=%s repeat=%s hold=%s\nlist ",
                    ram_size() >> 20, f, lowest, failures, lines, dropped, lost, writes,
                    log_playback, log_memory, log_power, log_artwork, log_performance,
                    name_of(shuffle_names, 4, shuffle_now), name_of(repeat_names, 3, repeat_now),
                    name_of(hold_names, 4, hold_now));
    if (n > INFO_HEAD - 1)
        n = INFO_HEAD - 1;
    if (list_json && list_length <= LIST_MAX) {
        for (i = 0; i < list_length; i++) {
            char c = list_json[i];
            L[n++] = c < 0x20 ? ' ' : c;
        }
    } else {
        fw_strcpy(L + n, list_json ? "too long" : "none");
        n += list_json ? 8 : 4;
    }
    for (i = n; i < INFO - 1; i++)
        L[i] = ' ';
    L[INFO - 1] = '\n';
}

static int write_file(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = LOG_BYTES;
    int err, err2;
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, LOG_PATH);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err != 0)
        return err;
    err = file_seek(fh, 0, 0);
    if (err == 0)
        err = file_write(fh, &len, L);
    err2 = file_close(fh);
    return err != 0 ? err : err2;
}

/* The file write. Only the UI task calls this function. */
static void flush_log(void)
{
    unsigned t0;
    if (writing)
        return;
    read_ram_settings();
    last_write_us = USEC;
    read_hold();
    if (shuffle_now != shuffle_log || repeat_now != repeat_log || hold_now != hold_log) {
        LOG(log_playback, "settings shuffle=%s repeat=%s hold=%s", name_of(shuffle_names, 4, shuffle_now),
            name_of(repeat_names, 3, repeat_now), name_of(hold_names, 4, hold_now));
        shuffle_log = shuffle_now;
        repeat_log = repeat_now;
        hold_log = hold_now;
    }
    if (fail_repeats) {
        LOG(log_memory, "  = the last failed allocation %u more times", fail_repeats);
        fail_repeats = 0;
        fail_size = fail_from = 0;
    }
    changed = 0;
    writes++;
    writing = 1;
    info();
    t0 = USEC;
    if (write_file() != 0)
        changed = 1;
    write_ms = (USEC - t0) / 1000;
    writing = 0;
}

static unsigned key_code, key_us;

/* A key push (type 4) and a key release (type 7). A long hold of Next or Previous is a seek. */
static void log_key(int type, void *event)
{
    unsigned key = (FIELD(unsigned, event, 0x10) >> 16) & 0xff;
    if (!key)
        return;
    if (type == 4) {
        key_code = key;
        key_us = USEC;
        LOG(log_playback, "key push=%x", key);
    } else {
        LOG(log_playback, "key release=%x held=%u ms", key, key == key_code ? (USEC - key_us) / 1000 : 0);
    }
}

int hook_event(void *ui, void *event)
{
    int r = fw_long_play_timer(ui, event);
    int type = ((int *)event)[1];
    /* Only a button or wheel event (types 4, 5 and 7 in 0x1d81cc). Other events also occur during
     * the start, before the disk is ready. */
    if (type != 4 && type != 5 && type != 7)
        return r;
    if (type != 5)
        log_key(type, event);
    if (!sample_us || USEC - sample_us >= SAMPLE_US)
        sample();
    if (USEC - last_write_us < WRITE_US && writes)
        return r;
    read_ram_settings();
    if (!changed && writes && shuffle_now == shuffle_log && repeat_now == repeat_log)
        return r;
    flush_log();
    return r;
}
