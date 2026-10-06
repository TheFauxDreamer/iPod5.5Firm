/* usb-host-probe: a one-shot test of the USB host mode through a USB-C mod.
 * Refer to USB-AUDIO-OUT.md (Stage 0) and re/usb-host.md.
 *
 * The stock firmware starts its USB host stack only after an iAP exchange (lingo 6) with a
 * Camera Connector. This patch starts the host stack itself, one time, and gives a tone when
 * the stack loads a driver. Thus the owner can test the host mode with an OTG adapter.
 *
 * The trigger: iPodFirm writes '1' to iPod_Control\iTunes\iPodFirmUSBProbe. At the first button
 * or wheel event after the next start, the patch reads the file. Other event types do not count,
 * because they also occur during the start, before the disk is ready. If it contains '1', the patch
 * writes '0' first, so that the next start is normal again. Then it gives a short high tone and
 * starts the host stack (0x2860e8). With no file or '0', the patch does nothing.
 *
 * The tones (0xcd430: pitch, duration in microseconds):
 *  - short high: the probe starts the host stack;
 *  - long low: the hub driver initializes a hub device (the root hub: the host stack runs);
 *  - high, low, high: the storage driver initializes an interface (a USB flash drive or a card
 *    reader enumerated through the USB-C port).
 *
 * Hooks:
 *  - bl at 0x1d8260 in the UI event handler 0x1d81cc (the call of the long-push timer 0x1d8570).
 *    The code after the site loads r0 again, thus the return value is not used.
 *  - word at 0x6c8730: the "initialize device" entry of the hub driver dispatch table.
 *  - word at 0x6c878c: the "initialize interface" entry of the storage driver dispatch table.
 *  The two tables are RW data: the start code copies them to RAM with the changes.
 *  The driver functions can have arguments on the stack, thus the wrappers are naked: they keep
 *  r0-r3 and the stack, and they continue in the original function. */

#define FILE_PATH  "iPod_Control\\iTunes\\iPodFirmUSBProbe"
#define MODE_DATA  0x64617461u                          /* 'data' */
#define HIGH       0xb4
#define LOW        0x90

void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_write(void *fh, unsigned *len, const void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
int fw_long_play_timer(void *ui, void *event);         /* the original call at 0x1d8260 */
void host_start(int a, int b, int c, int d);           /* 0x2860e8 */
void tone(int pitch, int microseconds);                /* 0xcd430 */

static int checked;

static void make_path(unsigned *path)
{
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, FILE_PATH);
}

/* Returns 1 if the file contains '1'. */
static int read_flag(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], got = 1;
    unsigned char c = 0;
    int err;
    make_path(path);
    fw_memset0(fh, sizeof fh);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return 0;
    err = file_read(fh, &got, &c);
    file_close(fh);
    return err == 0 && got == 1 && c == '1';
}

/* Writes '0' at the start of the file. Returns 0 if the write is correct. */
static int clear_flag(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = 1;
    unsigned char c = '0';
    int err, err2;
    make_path(path);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err != 0)
        return err;
    err = file_seek(fh, 0, 0);
    if (err == 0)
        err = file_write(fh, &len, &c);
    err2 = file_close(fh);
    return err != 0 ? err : err2;
}

int hook_event(void *ui, void *event)
{
    int r = fw_long_play_timer(ui, event);
    int type = ((int *)event)[1];
    /* Only a button or wheel event (types 4, 5 and 7 in 0x1d81cc). Other events also occur
     * during the start, before the disk is ready, and then the file open fails. */
    if (!checked && (type == 4 || type == 5 || type == 7)) {
        checked = 1;
        /* Clear the flag before the start, so that a stop in the host start cannot repeat. */
        if (read_flag() && clear_flag() == 0) {
            tone(HIGH, 100000);
            host_start(0, 0, 0, 0);
        }
    }
    return r;
}

void sign_hub(void)
{
    tone(LOW, 400000);
}

void sign_storage(void)
{
    tone(HIGH, 150000);
    tone(LOW, 150000);
    tone(HIGH, 150000);
}

__attribute__((naked)) void hook_hub_init(void)
{
    __asm__ volatile(
        "push {r0-r3, lr}\n"
        "bl   sign_hub\n"
        "pop  {r0-r3, lr}\n"
        "b    hub_init_device\n");
}

__attribute__((naked)) void hook_storage_init(void)
{
    __asm__ volatile(
        "push {r0-r3, lr}\n"
        "bl   sign_storage\n"
        "pop  {r0-r3, lr}\n"
        "b    storage_init_interface\n");
}
