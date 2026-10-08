/* usb-host-probe: a one-shot test of the USB host mode through a USB-C mod.
 * Refer to USB-AUDIO-OUT.md (Stage 0) and re/usb-host.md.
 *
 * The stock firmware starts its USB host stack only after an iAP exchange (lingo 6) with a
 * Camera Connector. This patch starts the host stack itself, one time, gives tones, and logs
 * each call of a class driver. Thus the owner can test the host mode with an OTG adapter.
 *
 * The trigger: iPodFirm writes '1' to iPod_Control\iTunes\iPodFirmUSBProbe. At the first button
 * or wheel event after the next start, the patch reads the file. Other event types do not count,
 * because they also occur during the start, before the disk is ready. If it contains '1', the patch
 * writes '0' first, so that the next start is normal again. Then it plays the sequence below and
 * starts the host stack (0x2860e8). With no file or '0', the patch does nothing.
 *
 * The sequence, so that the owner knows the tones before the test:
 *  1. Demonstration: the hub sign, a pause, the storage sign, a pause.
 *  2. Countdown: three short beeps.
 *  3. Silence (SILENCE_MS).
 *  4. The host start. The real signs follow.
 * tone() only puts a tone in the queue of the piezo task. Thus the pauses come from a task sleep
 * (0x11c9fc, ms) after each sign. The UI task does not react during the sequence (approximately
 * 7 s).
 *
 * The signs (0xcd430: pitch, duration in microseconds):
 *  - long low: the hub driver initializes a hub device (the root hub: the host stack runs; a
 *    second one: a hub in the adapter or the dock);
 *  - high, low, high: the storage driver initializes an interface (a USB flash drive or a card
 *    reader enumerated through the USB-C port).
 *
 * The log: the class driver dispatch tables (RW data, format of the Mac OS 9 USB family) have
 * the entries 1 "validate hardware" (device, device descriptor), 2 "initialize device" (index,
 * device descriptor, power) and 3 "initialize interface" (number, interface descriptor, device
 * descriptor, interface). A naked wrapper for each entry records the driver, the entry, r0-r3
 * and 20 bytes at r1 and at r2 (if they point into RAM), then continues in the original
 * function with r0-r3 and the stack unchanged. LOG_WAIT_MS after the host start, the patch writes
 * the log to iPod_Control\iTunes\iPodFirmUSBLog and gives two short low beeps. A later button or
 * wheel event writes it again if it has new records (if the event reaches the hook). iPodFirm makes that file (LOG_BYTES)
 * when it sets the trigger, because the file functions can only write to an existing file.
 *
 * Log format (little-endian): "UL01", u32 record count, then LOG_MAX records of 64 bytes:
 * u8 0xA5, u8 tag (driver * 4 + entry), u16 0, u32 r0-r3, 20 bytes at r1, 20 bytes at r2, 4 x 0.
 * Driver numbers: 0 hub, 1 composite, 3 storage, 4 ICA camera, 5 PTP camera. Number 7, entry 2:
 * a root port status record: r0 port, r1 wPortStatus | wPortChange << 16, r2 PORTSC, r3 result.
 * Number 7, entry 3: a register record: r0 USBCMD, r1 USBSTS, r2 PORTSC, r3 OTGSC. The probe
 * makes one after the host start and one before each log write. Number 7, entry 0: "add device"
 * (0xd377c): r0 device, r1 parent, r2 port, r3 device descriptor, with 20 bytes of the descriptor.
 * Number 7, entry 1: a queue
 * record: r0 USBINTR, r1 ASYNCLISTADDR, r2 ASYNCLISTADDR + 0x10, r3 FRINDEX, with 20 bytes of the
 * first queue head at r1 and at r2 (the qTD token of the overlay is at +0x18).
 * Number 6 is the UIM (host controller driver, table 0x6c8820): entry 1 "create control endpoint"
 * (address, endpoint, maximum packet size, speed); entry 2 "control transfer": r0-r2, and r3 is
 * the device address (the fifth argument, on the stack); entry 3 "IRQ install": the results of
 * r0 disable, r1 removal of the device handler, r2 install of the UIM handler, r3 enable;
 * entry 0 "completion": the callback 0xcb118 of a control transfer stage (r0 request | stage bit,
 * r1 status, 0 = correct, r2 bytes), with 20 bytes of the request block at +0 and at +0x20.
 *
 * Hooks:
 *  - bl at 0x1d8260 in the UI event handler 0x1d81cc (the call of the long-push timer 0x1d8570).
 *    The code after the site loads r0 again, thus the return value is not used.
 *  - word hooks on 14 dispatch table entries (refer to patch.json). The start code copies the RW
 *    data to RAM with the changes. */

#define FILE_PATH  "iPod_Control\\iTunes\\iPodFirmUSBProbe"
#define LOG_PATH   "iPod_Control\\iTunes\\iPodFirmUSBLog"
#define MODE_DATA  0x64617461u                          /* 'data' */
#define HIGH       0xb4
#define LOW        0x90
#define PAUSE_MS   1200                                 /* after each sign in the demonstration */
#define BEEP_MS    400                                  /* from one countdown beep to the next */
#define SILENCE_MS 2000                                 /* after the countdown */
#define LOG_WAIT_MS 10000                               /* from the host start to the first log write */
#define LOG_WAIT2_MS 20000                              /* from the first to the second log write */
#define LOG_MAX    511
#define LOG_BYTES  (8 + LOG_MAX * 64)                   /* 32712: iPodFirm makes a 32768-byte file */
#define TAG_HUB_INIT_DEVICE      (0 * 4 + 2)
#define TAG_STORAGE_INIT_IFACE   (3 * 4 + 3)
#define TAG_PORT_STATUS          (7 * 4 + 2)
#define PORT_LOGS  40                                   /* the maximum of port records */
#define UIM_LOGS   200                                  /* the maximum of UIM records */
#define COMPLETION_LOGS 200                             /* the maximum of completion records */
#define TAG_INTERRUPT_ENDPOINT   (8 * 4 + 1)
#define TAG_INTERRUPT_TRANSFER   (8 * 4 + 2)
#define TAG_INTERRUPT_COMPLETION (8 * 4 + 3)
#define TAG_ASYNC_QH             (9 * 4 + 1)
#define TAG_PERIODIC_QH          (9 * 4 + 2)
#define PERIODICBASE (*(volatile unsigned *)0xc5000154)
#define TAG_PERIODIC_SOFT        (9 * 4 + 3)
#define TAG_EXPERIMENT           (10 * 4 + 0)
#define UIM_STATE  0x1084a778                           /* +0xc: the controller object of the UIM */
#define TAG_REGISTERS            (7 * 4 + 3)
#define TAG_QUEUE                (7 * 4 + 1)
#define TAG_ADD_DEVICE           (7 * 4 + 0)
#define USB_GLOBALS ((volatile unsigned char *)0x1083e0f8) /* the global block of the USB host stack */
#define TAG_COMPLETION           (6 * 4 + 0)
#define TAG_CONTROL_ENDPOINT     (6 * 4 + 1)
#define TAG_CONTROL_TRANSFER     (6 * 4 + 2)
#define TAG_IRQ_INSTALL          (6 * 4 + 3)
#define USB_IRQ    20                                   /* the USB interrupt source of the PP5022 */
#define DEVICE_ISR ((void *)0xcd8e0)                    /* the handler of the device driver (0x220ef0) */
#define USBINTR    (*(volatile unsigned *)0xc5000148)
#define FRINDEX    (*(volatile unsigned *)0xc500014c)
#define ASYNCLIST  (*(volatile unsigned *)0xc5000158)
#define USBCMD     (*(volatile unsigned *)0xc5000140)
#define USBSTS     (*(volatile unsigned *)0xc5000144)
#define PORTSC1    (*(volatile unsigned *)0xc5000184)
#define OTGSC      (*(volatile unsigned *)0xc50001a4)

void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_write(void *fh, unsigned *len, const void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
int fw_long_play_timer(void *ui, void *event);         /* the original call at 0x1d8260 */
int fw_port_status(int port, unsigned short *status);  /* 0xe7980: the original call at 0xd28f0 */
int fw_chip_check(void);                               /* 0x266794 -> 0x598: 1 if the chip ID byte is 0x32 */
int fw_irq_attach(void *irq_object, void *handler);    /* 0x18a83c: install (manager method +0x48) */
void *fw_irq_manager(void);                            /* 0x127618 */
int fw_irq_disable(void *manager, int source);         /* 0x127888 */
int fw_irq_remove(void *manager, int source, void *handler, int zero);  /* 0x1277d0 */
void host_start(int a, int b, int c, int d);           /* 0x2860e8 */
void tone(int pitch, int microseconds);                /* 0xcd430 */
void task_sleep(int ms);                               /* 0x11c9fc */
void *cache_object(void);                              /* 0x1a0120 */
void cache_flush(void *cache);                         /* 0x19ff0c: writes the disk cache */
void sign_hub(void);
void sign_storage(void);
void log_call(int tag, const unsigned *regs);
void *fw_new(unsigned size);                           /* 0x25a974: the allocator (operator new) */

struct record {
    unsigned char magic, tag;
    unsigned short zero;
    unsigned regs[4];
    unsigned char at_r1[20], at_r2[20];
    unsigned pad;
};

static int checked, started;
static unsigned root_hub_address = 0xffffffff;
static unsigned completion_logs, interrupt_logs;
static unsigned device_requests[4], next_request;       /* the request blocks of logged device transfers */
static unsigned log_saved, port_logs, uim_logs, last_status = 0xffffffff, last_portsc = 0xffffffff;
/* The log buffer (32 KB) comes from the allocator when the probe starts, not from the image:
 * with a large theme, the space after osos is only approximately 10 KB. */
struct usb_log {
    unsigned magic, count;
    struct record r[LOG_MAX];
};
static struct usb_log *L;

static void make_path(unsigned *path, const char *name)
{
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, name);
}

/* Returns 1 if the trigger file contains '1'. */
static int read_flag(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], got = 1;
    unsigned char c = 0;
    int err;
    make_path(path, FILE_PATH);
    fw_memset0(fh, sizeof fh);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return 0;
    err = file_read(fh, &got, &c);
    file_close(fh);
    return err == 0 && got == 1 && c == '1';
}

/* Writes len bytes at the start of an existing file. Returns 0 if the write is correct.
 * The firmware keeps the write in its disk cache and writes it to the disk later (in the emulator,
 * after more than 10 s). The owner resets the iPod after the test, thus write_log() flushes the
 * cache with the same calls as the sleep sequence (0x1ed8cc, 0xb4430: 0x1a0120, then 0x19ff0c). */
static int write_file(const char *name, const void *data, unsigned len)
{
    unsigned path[0x108 / 4], fh[0x30 / 4];
    int err, err2;
    make_path(path, name);
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

/* Read a word of the RAM. The USB hardware uses the uncached window (RAM | 0x80000000); read the
 * same RAM through 0x10000000. Other addresses give 0 (the real iPod stops at a bad read). */
static unsigned read32(unsigned a)
{
    if (a >= 0x90000000 && a < 0x94000000)
        a -= 0x80000000;
    if (a < 0x10000000 || a >= 0x14000000 || (a & 3))
        return 0;
    return *(volatile unsigned *)a;
}

static void log_qh(int tag, unsigned qh)
{
    unsigned regs[4];
    regs[0] = qh;
    regs[1] = read32(qh + 4);                           /* endpoint characteristics */
    regs[2] = read32(qh + 8);                           /* endpoint capabilities: S-mask, C-mask, hub, port */
    regs[3] = read32(qh + 0x18);                        /* the token of the overlay */
    log_call(tag, regs);
}

/* Each queue head of the asynchronous list (control and bulk), and each queue head in the periodic
 * frame list (interrupt), with its state. At most 8 of each. */
static void log_queues(void)
{
    unsigned first = ASYNCLIST, qh = first, seen[8], n = 0, i, k, size, base, e, depth;
    for (i = 0; i < 8 && qh; i++) {
        log_qh(TAG_ASYNC_QH, qh);
        qh = read32(qh) & ~0x1fu;
        if (qh == first)
            break;
    }
    size = 1024 >> ((USBCMD >> 2) & 3);
    base = PERIODICBASE & ~0xfffu;
    for (i = 0; i < size && n < 8; i++) {
        e = read32(base + 4 * i);
        for (depth = 0; depth < 4 && !(e & 1) && ((e >> 1) & 3) == 1 && n < 8; depth++) {
            qh = e & ~0x1fu;
            for (k = 0; k < n && seen[k] != qh; k++)
                ;
            if (k == n) {
                seen[n++] = qh;
                log_qh(TAG_PERIODIC_QH, qh);
            }
            e = read32(qh);
        }
    }
}

/* Apple's own periodic table (0xf5c80): the controller object +0x3c holds the processor address of
 * the first queue head of each frame, +0x44 the frame list (controller addresses). Frames 0-7: the
 * frame list word, the queue head, its hardware link and 20 bytes at +0 and +0x30 (the software
 * next pointer, the interval byte +0x3c and the offset +0x3d). */
static void log_periodic_table(void)
{
    unsigned ctrl = read32(UIM_STATE + 0xc), heads = read32(ctrl + 0x3c), frames = read32(ctrl + 0x44), i;
    for (i = 0; i < 8; i++) {
        unsigned regs[4];
        regs[0] = i;
        regs[1] = read32(frames + 4 * i);
        regs[2] = read32(heads + 4 * i);
        regs[3] = read32(regs[2]);
        log_call(TAG_PERIODIC_SOFT, regs);
    }
}

static void log_registers(void)
{
    unsigned regs[4];
    regs[0] = USBCMD;
    regs[1] = USBSTS;
    regs[2] = PORTSC1;
    regs[3] = OTGSC;
    log_call(TAG_REGISTERS, regs);
    regs[0] = USBINTR;
    regs[1] = ASYNCLIST;
    regs[2] = regs[1] + 0x10;
    regs[3] = FRINDEX;
    log_call(TAG_QUEUE, regs);
}

static int write_log(void)
{
    int err;
    log_registers();
    if (!L)
        return -1;
    log_queues();
    log_periodic_table();
    log_saved = L->count;
    err = write_file(LOG_PATH, L, LOG_BYTES);
    if (err == 0)
        cache_flush(cache_object());
    return err;
}

static void copy_from(unsigned char *dst, unsigned src)
{
    int i;
    /* Only RAM: an argument can be a number. The USB code gives the buffers with addresses in a
     * window at 0x90000000 (emulator: setup packets at 0x93b5dd40). A read there stopped the probe
     * on the real iPod (version 0.1.62), thus read the same RAM in the normal window at 0x10000000.
     * The owner's iPod has 64 MB of RAM (real log: pointers at 0x1362xxxx). */
    if (src >= 0x90000000 && src < 0x94000000)
        src -= 0x80000000;
    if (src < 0x10000000 || src >= 0x14000000)
        return;
    for (i = 0; i < 20; i++)
        dst[i] = ((const unsigned char *)src)[i];
}

/* Called by the wrappers with the saved r0-r3. Runs in the task of the USB host stack. */
void log_call(int tag, const unsigned *regs)
{
    /* The root hub gets many transfers: skip the ones at address 0 before its control endpoint,
     * and the ones at its address. A new device then also starts at address 0. */
    if (tag == TAG_CONTROL_ENDPOINT && root_hub_address == 0xffffffff)
        root_hub_address = regs[0];
    if (tag == TAG_CONTROL_TRANSFER && (root_hub_address == 0xffffffff || regs[5] == root_hub_address))
        return;
    if ((tag == TAG_CONTROL_ENDPOINT || tag == TAG_CONTROL_TRANSFER) && uim_logs++ >= UIM_LOGS)
        return;
    /* The root hub polls its port all the time, and each poll ends in a completion. Log only the
     * completions of the requests of logged device transfers (r0 without the stage bit). */
    if (tag == TAG_COMPLETION) {
        unsigned request = regs[0] & ~1u, i, known = 0;
        for (i = 0; i < 4; i++)
            if (device_requests[i] == request)
                known = 1;
        if (!known || completion_logs++ >= COMPLETION_LOGS)
            return;
    }
    if (tag == TAG_INTERRUPT_COMPLETION && interrupt_logs++ >= 100)
        return;
    if ((tag == TAG_INTERRUPT_ENDPOINT || tag == TAG_INTERRUPT_TRANSFER)
        && (regs[0] == root_hub_address || uim_logs++ >= UIM_LOGS))
        return;
    if (tag == TAG_CONTROL_TRANSFER) {
        unsigned request = regs[0] & ~1u, i, known = 0;
        for (i = 0; i < 4; i++)
            if (device_requests[i] == request)
                known = 1;
        if (!known) {
            device_requests[next_request] = request;
            next_request = (next_request + 1) & 3;
        }
    }
    if (L && L->count < LOG_MAX) {
        struct record *r = &L->r[L->count];
        int i;
        for (i = 0; i < (int)(sizeof *r / 4); i++)      /* the allocator does not clear the buffer; */
            ((unsigned *)r)[i] = 0;                     /* no firmware call: this can run in an interrupt */
        r->magic = 0xa5;
        r->tag = tag;
        for (i = 0; i < 4; i++)
            r->regs[i] = regs[i];
        if (tag == TAG_CONTROL_TRANSFER)                /* the wrapper saved r0-r3, lr; then the stack arguments */
            r->regs[3] = regs[5];
        if (tag == TAG_PERIODIC_SOFT) {                 /* the queue head of Apple's periodic table */
            copy_from(r->at_r1, regs[2]);
            copy_from(r->at_r2, regs[2] + 0x30);
        } else if (tag == TAG_INTERRUPT_COMPLETION) {   /* the request block, as for a control completion */
            copy_from(r->at_r1, regs[0]);
            copy_from(r->at_r2, regs[0] + 0x20);
        } else if (tag == TAG_ADD_DEVICE) {                    /* the device descriptor is the 4th argument */
            copy_from(r->at_r1, regs[3]);
        } else if (tag == TAG_COMPLETION) {             /* the request block: +10 address, +0x2c flags */
            copy_from(r->at_r1, regs[0] & ~1u);
            copy_from(r->at_r2, (regs[0] & ~1u) + 0x20);
        } else {
            copy_from(r->at_r1, regs[1]);
            copy_from(r->at_r2, regs[2]);
        }
        L->count++;
    }
    if (tag == TAG_HUB_INIT_DEVICE)
        sign_hub();
    else if (tag == TAG_STORAGE_INIT_IFACE)
        sign_storage();
}

/* Full speed. The UIM init 0x97300 calls the chip check at 0x97364 and stores (result == 0) at
 * +0x60 of the controller object. Later it sets PFSC (bit 24, "port force full speed") in PORTSC if
 * that value is 1. On the owner's iPod the check returns 1, thus the port ran at high speed, and no
 * device descriptor arrived (log of 2026-10-07). While the probe runs, this hook returns 0. Thus
 * the firmware itself forces full speed, with the same code path as for the other chip type. */
int hook_chip_check(void)
{
    return started ? 0 : fw_chip_check();
}

/* The USB interrupt. The UIM init installs its handler 0xffd1c for source 20 with 0x18a870 at
 * 0x9741c. 0x18a870 calls the install 0x18a83c (manager method +0x48) and ignores its result, then
 * enables the source (method +0x30) and returns that result. The device driver installs its own
 * handler 0xcd8e0 for the same source (0x220e0c), for example when the iPod sees VBUS. Possibly the
 * device handler then takes the interrupts of the host (real log: the qTD completed, but the host
 * stack never sent the next request).
 * While the probe runs, this hook removes the device handler first (the sequence of 0x18a888:
 * disable the source, remove the handler), installs the UIM handler, and enables the source. It
 * logs the result of each step. */
int hook_irq_install(void *irq_object, void *handler)
{
    unsigned regs[4];
    void *manager = fw_irq_manager();
    int **sub = *(int ***)((char *)manager + 4);
    int (*enable)(void *, int) = (int (*)(void *, int))(*sub)[0x30 / 4];
    regs[0] = fw_irq_disable(manager, USB_IRQ);
    regs[1] = fw_irq_remove(manager, USB_IRQ, DEVICE_ISR, 0);
    regs[2] = fw_irq_attach(irq_object, handler);
    regs[3] = enable(sub, USB_IRQ);
    log_call(TAG_IRQ_INSTALL, regs);
    return regs[3] != 0;
}

/* The status of a root port: 0xe7980, called by the root hub GET_STATUS (0xd26b0, at 0xd28f0)
 * and by the root hub status-change poll (0x10e6e0, at 0x10e75c). status[0] is wPortStatus,
 * status[1] is wPortChange. Log each change, with the raw PORTSC register. */
int hook_port_status(int port, unsigned short *status)
{
    int r = fw_port_status(port, status);
    /* PORTSC bits 11:10 are the line state. They change all the time during high-speed traffic. */
    unsigned key = status[0] | (unsigned)status[1] << 16, sc = PORTSC1 & ~0xc00u;
    if (started && port_logs < PORT_LOGS && (key != last_status || sc != last_portsc)) {
        unsigned regs[4];
        last_status = key;
        last_portsc = sc;
        port_logs++;
        regs[0] = port;
        regs[1] = key;
        regs[2] = sc;
        regs[3] = r;
        log_call(TAG_PORT_STATUS, regs);
    }
    return r;
}

int hook_event(void *ui, void *event)
{
    int r = fw_long_play_timer(ui, event);
    int type = ((int *)event)[1];
    /* Only a button or wheel event (types 4, 5 and 7 in 0x1d81cc). Other events also occur
     * during the start, before the disk is ready, and then the file open fails. */
    if (type != 4 && type != 5 && type != 7)
        return r;
    if (!checked) {
        checked = 1;
        /* Clear the flag before the start, so that a stop in the host start cannot repeat. */
        if (read_flag() && write_file(FILE_PATH, "0", 1) == 0) {
            int i;
            sign_hub();                                 /* the demonstration: 400 ms */
            task_sleep(400 + PAUSE_MS);
            sign_storage();                             /* 450 ms */
            task_sleep(450 + PAUSE_MS);
            for (i = 0; i < 3; i++) {                   /* the countdown */
                tone(HIGH, 60000);
                task_sleep(BEEP_MS);
            }
            task_sleep(SILENCE_MS);
            L = fw_new(sizeof *L);
            if (L) {
                L->magic = 0x31304c55;                  /* "UL01" */
                L->count = 0;
            }
            started = 1;
            /* Allow external hubs. "Add device" 0xd377c refuses a hub (class 9) after the root hub,
             * unless the byte at +0 of the global block is not 0 (error 0x673/0x67d, the photo
             * import screen says "unsupported device"). Nothing in the firmware sets it. With 2,
             * the test "1 < byte" is true for each hub. */
            USB_GLOBALS[0] = 2;
            host_start(0, 0, 0, 0);
            USB_GLOBALS[0] = 2;                         /* again: the host start clears parts of the block */
            log_registers();
            /* The USB tasks find the devices during this wait. Then write the log here, because a
             * later button event possibly does not reach this hook: 0x1d81cc gives each event to
             * the active modal screen first (0x12d890, 0x12ddb8), for example the photo import
             * screen, and returns if the screen takes it. */
            task_sleep(LOG_WAIT_MS);
            if (write_log() == 0) {
                tone(LOW, 60000);                       /* "log saved": two short low beeps */
                task_sleep(BEEP_MS);
                tone(LOW, 60000);
            }
            /* Experiment: switch the periodic schedule off for 2 s (USBCMD bit 4), then log the
             * queues again. If a stopped asynchronous transfer then completes, the periodic list
             * blocks the controller. Then switch it on again. */
            {
                unsigned regs[4];
                regs[0] = USBCMD;
                USBCMD = regs[0] & ~0x10u;
                task_sleep(2000);
                regs[1] = USBCMD;
                regs[2] = USBSTS;
                regs[3] = 0;
                log_call(TAG_EXPERIMENT, regs);
                log_queues();
                USBCMD = USBCMD | 0x10u;
            }
            /* A second write: the ports of a hub and the devices behind it take more time. */
            task_sleep(LOG_WAIT2_MS);
            if (write_log() == 0) {
                tone(LOW, 60000);
                task_sleep(BEEP_MS);
                tone(LOW, 60000);
            }
        }
    } else if (started && L && L->count != log_saved) {
        write_log();
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

/* A wrapper: keep r0-r3 and the stack, log, then continue in the original function. */
#define WRAP(name, tag, original)                       \
    __attribute__((naked)) void name(void)              \
    {                                                   \
        __asm__ volatile(                               \
            "push {r0-r3, lr}\n"                        \
            "mov  r1, sp\n"                             \
            "mov  r0, #" #tag "\n"                      \
            "bl   log_call\n"                           \
            "pop  {r0-r3, lr}\n"                        \
            "b    " #original "\n");                    \
    }

/* The completion callback 0xcb118 of the control transfers. A "b" hook replaces its first
 * instruction "stmdb sp!, {r1-r7, lr}". The wrapper logs, runs that instruction and continues at
 * 0xcb11c. The UIM completion code 0xe01a0 calls it, possibly in the interrupt handler: log_call only
 * writes RAM there. */
__attribute__((naked)) void hook_completion(void)
{
    __asm__ volatile(
        "push {r0-r3, lr}\n"
        "mov  r1, sp\n"
        "mov  r0, #24\n"
        "bl   log_call\n"
        "pop  {r0-r3, lr}\n"
        "stmdb sp!, {r1-r7, lr}\n"
        "b    completion_continue\n");
}

/* "Add device" 0xd377c (the Mac OS 9 USBExpertInstallDeviceDriver) at its only call, 0x10c1d8:
 * (device, parent hub, port, device descriptor, power on the stack). It selects and loads the
 * class driver. Log each device that the stack offers to the drivers. */
WRAP(hook_add_device, 28, expert_add_device)

/* Firmware bug: the periodic insert 0xf5c80 makes the frame list word from its second argument:
 * (r1 + 0x34) | 2. Both callers give the new queue head only in r0: 0x974ec ("create interrupt
 * endpoint", call at 0x9761c) leaves r1 = the UIM controller object, and 0x96c44 (call at 0x96d14)
 * leaves r1 unset. Thus the frame list pointed to the controller object's +0x34 (a block of zeros),
 * and no interrupt endpoint was polled (real log of 2026-10-08: frame list 0x9363B682, the dock's hub
 * QH at 0x93623080). The fix: r1 = r0, then continue in 0xf5c80. */
__attribute__((naked)) void hook_periodic_insert(void)
{
    __asm__ volatile(
        "mov  r1, r0\n"
        "b    periodic_insert\n");
}

/* The completion callback 0xcba54 of the interrupt transfers (request, status, bytes), for example
 * the status-change endpoint of a hub. A "b" hook replaces "stmdb sp!, {r4-r8, lr}". */
__attribute__((naked)) void hook_interrupt_completion(void)
{
    __asm__ volatile(
        "push {r0-r3, lr}\n"
        "mov  r1, sp\n"
        "mov  r0, #35\n"
        "bl   log_call\n"
        "pop  {r0-r3, lr}\n"
        "stmdb sp!, {r4-r8, lr}\n"
        "b    interrupt_completion_continue\n");
}
WRAP(hook_uim_control_endpoint, 25, uim_control_endpoint)
WRAP(hook_uim_interrupt_endpoint, 33, uim_interrupt_endpoint)
WRAP(hook_uim_interrupt_transfer, 34, uim_interrupt_transfer)
WRAP(hook_uim_control_transfer, 26, uim_control_transfer)
WRAP(hook_hub_validate, 1, hub_validate)
WRAP(hook_hub_init, 2, hub_init_device)
WRAP(hook_composite_validate, 5, composite_validate)
WRAP(hook_composite_init, 6, composite_init_device)
WRAP(hook_composite_iface, 7, composite_init_interface)
WRAP(hook_storage_validate, 13, storage_validate)
WRAP(hook_storage_device, 14, storage_init_device)
WRAP(hook_storage_init, 15, storage_init_interface)
WRAP(hook_ica_validate, 17, ica_validate)
WRAP(hook_ica_init, 18, ica_init_device)
WRAP(hook_ica_iface, 19, ica_init_interface)
WRAP(hook_ptp_validate, 21, ptp_validate)
WRAP(hook_ptp_init, 22, ptp_init_device)
WRAP(hook_ptp_iface, 23, ptp_init_interface)
