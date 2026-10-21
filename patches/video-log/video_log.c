/* video-log: a text log of the commands that the firmware sends to the video processor.
 * Refer to re/video-player.md.
 *
 * The ARM code controls the Broadcom BCM2722 (VideoCore) with text commands, for example
 * "load_application %s", "mp_selectplay passthru:%s %d", "mp_play" and "mp_get_status".
 * Each command goes through 0xe9358 (format and send; it takes the lock 0x123000). Each reply
 * comes back through 0x2872c0 (read the reply; it releases the lock with 0x287140).
 *
 * Hooks:
 *  - b at 0xe9358 (first instruction push {r4-r6, lr}): hook_vc_send runs the original function,
 *    then formats the command a second time with the firmware vsnprintf 0x7b114.
 *  - b at 0x2872c0 (first instruction push {r4-r6, lr}): hook_vc_reply runs the original
 *    function and records the command, the result and the reply.
 *  - bl at 0x1d8260 in the UI event handler 0x1d81cc (the call of the long-push timer 0x1d8570),
 *    the same site as usb-host-probe. On a button or wheel event, at most one time each 5 s, the
 *    patch asks the video processor for its statistics if a video command came, and then writes
 *    the log to iPod_Control\iTunes\iPodFirmVideoLog.
 *
 * The hooks of the commands only write RAM and use little stack, because they run in the task
 * of the player. Only the UI task writes the file. iPodFirm makes the file (LOG_BYTES) with the
 * action "Clear the Video Log", because the file functions write only to an existing file.
 *
 * Log format: plain text. The first HEADER bytes are the header line "VL01 ...", with spaces
 * and a line end. One line follows for each record. Zero bytes fill the rest of the file.
 * A line: "<seconds since the first record> > command" or "... < result reply". A command that
 * the firmware could not send has "[send <result>]". The same command with the same reply (for
 * example the status poll of the player) gives one line "= the last command and reply N more times". */

#define LOG_PATH   "iPod_Control\\iTunes\\iPodFirmVideoLog"
#define MODE_DATA  0x64617461u                          /* 'data' */
#define LOG_BYTES  65536                                /* the size of the file */
#define HEADER     64                                   /* the size of the header line */
#define CMD_MAX    256                                  /* the command buffer of 0xe9358 is 0x100 bytes */
#define REPLY_MAX  1200                                 /* the maximum of reply text in one line */
#define STATS_BYTES 0x400                               /* the reply buffer of mp_get_stats (as 0x1f9754) */
#define WRITE_US   5000000                              /* at most one file write each 5 s */
#define USEC       (*(volatile unsigned *)0x60005010)   /* the microsecond timer */

void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int fw_vsnprintf(char *buf, unsigned size, const char *fmt, void *args);   /* 0x7b114 */
int fw_snprintf(char *buf, unsigned size, const char *fmt, ...);           /* 0x7b240 */
int vc_command(char *reply, int size, const char *fmt, ...);               /* 0x287664 */
void *fw_new(unsigned size);                                               /* 0x25a974 */
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_write(void *fh, unsigned *len, const void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
int fw_long_play_timer(void *ui, void *event);         /* the original call at 0x1d8260 */

static char *L;                                         /* the log text (LOG_BYTES), from fw_new */
static unsigned used, at, lines, lost, writes, start_us, last_write_us, written;
static int no_memory, video_seen, polling;
static char cmd[CMD_MAX], last_cmd[CMD_MAX];            /* the command that waits for its reply, the last one */
static int pending, send_result, last_send, last_result, repeats;
static unsigned last_reply_len, last_reply_sum;
static char stats[STATS_BYTES];

/* Disable the interrupts while a record goes into the buffer: two tasks can send commands. */
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

static int same(const char *a, const char *b)
{
    while (*a && *a == *b)
        a++, b++;
    return *a == *b;
}

static void copy(char *dst, const char *src)
{
    unsigned i;
    for (i = 0; i + 1 < CMD_MAX && src[i]; i++)
        dst[i] = src[i];
    dst[i] = 0;
}

/* Makes the buffer at the first record. The first command comes at the start of the video
 * processor, after the allocator operates. */
static int ready(void)
{
    if (L)
        return 1;
    if (no_memory)
        return 0;
    L = fw_new(LOG_BYTES);
    if (!L) {
        no_memory = 1;
        return 0;
    }
    fw_memset0(L, LOG_BYTES);
    used = written = HEADER;
    start_us = USEC;
    return 1;
}

/* A line goes directly into the buffer: begin_line, add, end_line. A full buffer loses the line. */
static int begin_line(void)
{
    unsigned ms;
    if (!L || used + 40 > LOG_BYTES) {
        lost++;
        return 0;
    }
    ms = (USEC - start_us) / 1000;
    at = used + fw_snprintf(L + used, 32, "%6u.%03u ", ms / 1000, ms % 1000);
    return 1;
}

/* Adds at most max characters. Line ends and other control characters become spaces or dots. */
static void add(const char *s, unsigned max)
{
    while (max-- && *s && at < LOG_BYTES - 1) {
        char c = *s++;
        L[at++] = (c == '\n' || c == '\r' || c == '\t') ? ' ' : (c < 0x20 || c > 0x7e) ? '.' : c;
    }
}

static void add_number(const char *fmt, int value)
{
    char t[24];
    fw_snprintf(t, sizeof t, fmt, value);
    add(t, sizeof t);
}

static void end_line(void)
{
    L[at++] = '\n';
    used = at;
    lines++;
}

static void flush_repeats(void)
{
    if (repeats && begin_line()) {
        add("= the last command and reply ", 32);
        add_number("%d", repeats);
        add(" more times", 16);
        end_line();
    }
    repeats = 0;
}

/* Records the command that waits. 0x2874f0 sends a command with no reply. */
static void flush_command(void)
{
    if (!pending)
        return;
    pending = 0;
    flush_repeats();
    if (begin_line()) {
        add("> ", 2);
        add(cmd, CMD_MAX);
        if (send_result != 0)
            add_number("  [send %d]", send_result);
        end_line();
    }
    last_cmd[0] = 0;
}

/* A simple sum of the reply text. Two equal replies have the same sum. */
static unsigned reply_sum(const char *reply, unsigned n)
{
    unsigned i, s = 0;
    for (i = 0; i < n; i++)
        s = s * 31 + (unsigned char)reply[i];
    return s;
}

/* The first instructions of 0xe9358 and 0x2872c0 are replaced by a branch to the hooks. These
 * functions run that instruction and continue in the firmware function. */
__attribute__((naked)) int vc_send_original(const char *fmt, void *args)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb vc_send_continue\n");
}

__attribute__((naked)) int vc_reply_original(char *reply, int size)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb vc_reply_continue\n");
}

/* 0xe9358(format, arguments): the arguments are a pointer to the words of the variadic call.
 * The format runs two times. This is safe: the firmware gives the pointer by value.
 * Result: 0, or -1 if the channel is not open. */
int hook_vc_send(const char *fmt, void *args)
{
    int r = vc_send_original(fmt, args);
    unsigned old;
    if (!ready())
        return r;
    old = irq_off();
    flush_command();
    cmd[0] = 0;
    fw_vsnprintf(cmd, CMD_MAX, fmt, args);
    send_result = r;
    pending = 1;
    if (cmd[0] == 'm' && cmd[1] == 'p' && cmd[2] == '_' && !polling)
        video_seen = 1;
    irq_restore(old);
    return r;
}

/* 0x2872c0(reply, size): 0 if the reply has more than one byte, else 1. */
int hook_vc_reply(char *reply, int size)
{
    int r = vc_reply_original(reply, size);
    unsigned old, n = 0, sum;
    if (!L)
        return r;
    while (size > 0 && n < (unsigned)size && n < REPLY_MAX && reply[n])
        n++;
    sum = reply_sum(reply, n);
    old = irq_off();
    if (pending && send_result == last_send && r == last_result && n == last_reply_len
        && sum == last_reply_sum && same(cmd, last_cmd)) {
        pending = 0;
        repeats++;
    } else {
        int had_command = pending;
        flush_command();
        if (had_command) {
            copy(last_cmd, cmd);
            last_send = send_result;
        }
        last_result = r;
        last_reply_len = n;
        last_reply_sum = sum;
        if (begin_line()) {
            add_number("< %d ", r);
            add(reply, n);
            end_line();
        }
    }
    irq_restore(old);
    return r;
}

/* Writes the header line: "VL01 video-log", the counts, spaces, a line end. */
static void header(void)
{
    unsigned n, i;
    n = fw_snprintf(L, HEADER, "VL01 video-log 1.1 lines=%u lost=%u writes=%u", lines, lost, writes);
    if (n > HEADER - 1)
        n = HEADER - 1;
    for (i = n; i < HEADER - 1; i++)
        L[i] = ' ';
    L[HEADER - 1] = '\n';
}

static int write_file(const char *name, const void *data, unsigned len)
{
    unsigned path[0x108 / 4], fh[0x30 / 4];
    int err, err2;
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, name);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err != 0)
        return err;
    err = file_seek(fh, 0, 0);
    if (err == 0)
        err = file_write(fh, &len, data);
    err2 = file_close(fh);
    return err != 0 ? err : err2;
}

/* Asks for the status and the statistics of the player (as 0x1f9754). The hooks record the
 * replies. This runs in the UI task, as the other users of the channel do. */
static void poll_player(void)
{
    polling = 1;
    vc_command(stats, STATS_BYTES, "mp_get_status");
    vc_command(stats, STATS_BYTES, "mp_get_stats video");
    vc_command(stats, STATS_BYTES, "mp_get_stats audio");
    polling = 0;
}

int hook_event(void *ui, void *event)
{
    int r = fw_long_play_timer(ui, event);
    int type = ((int *)event)[1];
    unsigned now, old;
    /* Only a button or wheel event (types 4, 5 and 7 in 0x1d81cc). Other events also occur
     * during the start, before the disk is ready. */
    if (type != 4 && type != 5 && type != 7)
        return r;
    now = USEC;
    if (!L || now - last_write_us < WRITE_US)
        return r;
    last_write_us = now;
    if (video_seen) {
        video_seen = 0;
        poll_player();
    }
    old = irq_off();
    flush_repeats();
    irq_restore(old);
    if (used == written)
        return r;
    writes++;
    header();
    if (write_file(LOG_PATH, L, used) == 0)
        written = used;
    return r;
}
