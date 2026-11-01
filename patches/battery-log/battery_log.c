/* battery-log: a text log of the raw battery value, for a discharge curve. Refer to re/battery.md.
 *
 * The hook is the bl at 0x1d91f8 in 0x1d91dc, the timer handler of the UI that reads the battery icon
 * value (0x1e7fe4). No other patch uses this word. Each sample reads the raw ADC value (0x9b284) and
 * writes one line to iPod_Control\iTunes\iPodFirmBatteryLog. iPodFirm makes this file with the action
 * "Clear the Battery Log", because the file functions write only to an existing file.
 *
 * The file has a header of HEADER bytes with the end of the text. Each line is:
 * seconds raw icon charger. The seconds start at 0 at each start of the iPod. The line "start" marks
 * a new start. The first 60 s have no sample, because the disk can be not ready.
 */

#define USEC       (*(volatile unsigned *)0x60005010)   /* the microsecond timer */
#define MODE_DATA  0x64617461u                          /* 'data' */
#define LOG_PATH   "iPod_Control\\iTunes\\iPodFirmBatteryLog"
#define LOG_BYTES  262144u
#define HEADER     32u
#define FIRST_S    60u

void fw_memset0(void *p, unsigned n);
char *fw_strcpy(char *to, const char *from);
int fw_snprintf(char *to, unsigned n, const char *format, ...);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_write(void *fh, unsigned *len, const void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
int battery_icon(void *provider, int mode);
int battery_raw(void);
int battery_state(void);

unsigned interval_min = 5;                              /* an option in patch.json */

static unsigned last_us, seconds, next_s = FIRST_S, end, started, failed;

static void path_record(unsigned *path)
{
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, LOG_PATH);
}

/* The end of the text from the header. A clear file has no header: the text starts after it. */
static void read_end(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], got = HEADER, value = 0, i;
    char head[HEADER];
    end = HEADER;
    path_record(path);
    fw_memset0(fh, sizeof fh);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return;
    if (file_read(fh, &got, head) == 0 && got == HEADER && head[0] == 'B' && head[1] == 'L'
        && head[2] == '0' && head[3] == '1') {
        for (i = 5; i < 15 && head[i] >= '0' && head[i] <= '9'; i++)
            value = value * 10 + (head[i] - '0');
        if (value >= HEADER && value <= LOG_BYTES)
            end = value;
    }
    file_close(fh);
}

static int write_text(const char *text, unsigned length)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = length, i;
    char head[HEADER];
    int err, err2;
    path_record(path);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err != 0)
        return err;
    err = file_seek(fh, 0, end);
    if (err == 0)
        err = file_write(fh, &len, text);
    if (err == 0) {
        end += length;
        i = fw_snprintf(head, HEADER, "BL01 %010u %u min", end, interval_min);
        for (; i < HEADER - 1; i++)
            head[i] = ' ';
        head[HEADER - 1] = '\n';
        len = HEADER;
        err = file_seek(fh, 0, 0);
        if (err == 0)
            err = file_write(fh, &len, head);
    }
    err2 = file_close(fh);
    return err != 0 ? err : err2;
}

static void sample(int icon)
{
    char line[64];
    unsigned n = 0;
    if (!started) {
        started = 1;
        read_end();
        fw_strcpy(line, "start\n");
        n = 6;
    }
    n += fw_snprintf(line + n, sizeof line - n, "%u %d %d %d\n", seconds, battery_raw(), icon, battery_state());
    if (end + n > LOG_BYTES)
        failed = 1;                                     /* the file is full */
    else if (write_text(line, n) != 0)
        failed = 1;
}

int hook_battery_timer(void *provider, int mode)
{
    int icon = battery_icon(provider, mode);
    unsigned now = USEC, s;
    if (!last_us)
        last_us = now;
    s = (now - last_us) / 1000000;
    seconds += s;
    last_us += s * 1000000;
    if (!failed && seconds >= next_s) {
        next_s = seconds + interval_min * 60;
        sample(icon);
    }
    return icon;
}
