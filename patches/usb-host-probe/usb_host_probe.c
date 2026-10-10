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
 * Number 11, entry 0: data. The received bytes of a GET_DESCRIPTOR configuration request, in
 * records of 40 bytes (at_r1 and at_r2): r0 request, r1 buffer, r2 offset, r3 length (DATA_MAX).
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
#define TAG_DATA                 (11 * 4 + 0)
#define DATA_MAX   512                                  /* the maximum of bytes in one data dump */
#define TAG_AUDIO_DEVICE         (12 * 4 + 0)
#define TAG_AUDIO_REQUEST        (12 * 4 + 1)
#define TAG_AUDIO_STREAM         (12 * 4 + 2)
#define TAG_AUDIO_MEMORY         (12 * 4 + 3)
#define LOG_RESERVE 16                                  /* the records for the audio test at the end */
#define TAG_MUSIC_START          (13 * 4 + 0)
#define TAG_MUSIC_STATS          (13 * 4 + 1)
#define TAG_MUSIC_CHAIN          (13 * 4 + 2)
#define TAG_MUSIC_SLEEP          (13 * 4 + 3)
#define AHEAD_LOW  24                                   /* the frames in front after a wait */
#define AHEAD_HIGH 36                                   /* the frames in front after a send (24 + 12) */
#define STATS_PACKETS 5000                              /* a status record and a log write each 5 s of music */
#define RING       64                                   /* the music buffers (one for each frame) */
#define PACKET_MAX 192                                  /* the largest packet (48 kHz, 16 bits, stereo) */
#define USB_AUDIO_STATE ((volatile unsigned char *)0x108234ec)   /* +1 speed, +2 stream on, +8 rate, +0x10 object, +0x18 event */
#define USB_AUDIO_SOURCE (*(volatile unsigned *)0x10831964)        /* the queue of the music for USB (0x1e30d0) */
#define AUDIO_OUTPUT     (*(volatile unsigned *)(0x108236a4 + 4))  /* the audio output object (0x1a3070) */
/* 0x1e3064 fills a packet from the music queue only if 0x1e2f74 returns 1. With source + 8 = 0 (no
 * rate from an accessory), 0x1e2f74 returns 0 while this byte is 0. An iAP "Digital Audio" accessory
 * sets it; without one, the packets are silence and the decoder stops (probe 1.4: the song stayed
 * at 0:00). Only 0x1e2f74 reads it through its address. */
#define DIGITAL_AUDIO_READY (*(volatile unsigned char *)0x1081dff6)
#define TONE_MS    5000                                 /* the length of the test tone */
#define TONE_LEVEL 4000                                 /* the peak of the test tone (full scale 32767) */
#define FRAMES     1024                                 /* the periodic frame list (USBCMD bits 3:2 = 0) */
#define DMA_LOW    0x90000000u                          /* the RAM window of the USB structures */
#define DMA_HIGH   0x94000000u
/* The second composite driver record (registry entry 0x6bc434) matches device class 2. 0xc50ac gives
 * a driver 100 points if the device class is equal to the byte at +0x35 of the record, and 10 more
 * if the subclass is equal to +0x36. The composite validate 0x108b6c accepts each device. */
#define COMPOSITE2_CLASS ((volatile unsigned char *)0x1084a395)
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
void *dma_alloc(unsigned size, int zero);              /* 0xad80c: the memory of the UIM (frame list, queue heads) */
int fw_usb_send(void *device, int endpoint, int count, void *packets);   /* 0x24d518 */
int fw_usb_wait(void *device, int endpoint);           /* 0x24c4cc */
void fw_event_signal(void *event);                     /* 0xd1e70 */
void fw_route_usb(void *output, int on);               /* 0x1a2fa0 */
void fw_rate_convert(void *source, unsigned rate);     /* 0x1e2f60 */

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
static unsigned data_length[4], data_buffer[4];         /* GET_DESCRIPTOR configuration: wLength, buffer */
static unsigned data_address[4];                        /* the device address of each followed request */
static int music_mode;                                  /* 1: the music goes to the USB audio device */
static void find_audio(unsigned buffer, unsigned length, unsigned address);
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

/* Is the address in a RAM window? 0x90000000-0x94000000 is the window of the UIM memory (0xad80c,
 * not in the cache): the CPU and the controller use these addresses. 0x10000000-0x14000000 is the
 * same RAM through the cache. Version 1.2 read USB buffers through the cache and got old lines (real
 * log of 2026-10-09: the first 16 bytes of a configuration were zeros). Thus read a 0x9xxxxxxx
 * address directly, as the firmware does. Other addresses give 0 (an argument can be a number, and
 * the real iPod stops at a bad read). */
static int ram_address(unsigned a)
{
    return (a >= 0x90000000 && a < 0x94000000) || (a >= 0x10000000 && a < 0x14000000);
}

static unsigned read32(unsigned a)
{
    if (!ram_address(a) || (a & 3))
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
    if (!music_mode) {                                  /* the music test needs the log space */
        log_queues();
        log_periodic_table();
    }
    log_saved = L->count;
    err = write_file(LOG_PATH, L, LOG_BYTES);
    if (err == 0)
        cache_flush(cache_object());
    return err;
}

static void copy_from(unsigned char *dst, unsigned src)
{
    int i;
    /* Only RAM (refer to ram_address). The owner's iPod has 64 MB of RAM. */
    if (!ram_address(src) || !ram_address(src + 19))
        return;
    for (i = 0; i < 20; i++)
        dst[i] = ((const volatile unsigned char *)src)[i];
}

/* Write the received data of a GET_DESCRIPTOR configuration request to the log: records of 40 bytes
 * (at_r1 and at_r2 together). r0 request, r1 buffer, r2 offset, r3 length. */
static void log_data(unsigned request, unsigned buffer, unsigned length, unsigned address)
{
    unsigned offset;
    if (length > DATA_MAX)
        length = DATA_MAX;
    for (offset = 0; offset < length && L && L->count < LOG_MAX - LOG_RESERVE; offset += 40) {
        struct record *r = &L->r[L->count];
        int i;
        for (i = 0; i < (int)(sizeof *r / 4); i++)
            ((unsigned *)r)[i] = 0;
        r->magic = 0xa5;
        r->tag = TAG_DATA;
        r->regs[0] = request;
        r->regs[1] = buffer;
        r->regs[2] = offset;
        r->regs[3] = length;
        r->pad = address;                               /* the device address (the app does not show it) */
        copy_from(r->at_r1, buffer + offset);
        copy_from(r->at_r2, buffer + offset + 20);
        L->count++;
    }
}

/* The configuration descriptors. The control transfer wrapper gets three calls: the setup stage
 * (r2 = the setup packet), the data stage (r2 = the buffer) and the status stage (r2 = 0). The UIM
 * then completes the request two times, and the third completion has the stage bit (r0 | 1). At
 * that time the data is in the buffer. */
static void track_data(int tag, const unsigned *regs, unsigned slot)
{
    if (tag == TAG_CONTROL_TRANSFER && regs[2]) {
        unsigned char setup[20];
        copy_from(setup, regs[2]);
        if (data_length[slot] && !data_buffer[slot]) {
            data_buffer[slot] = regs[2];                /* the data stage */
        } else if (setup[0] == 0x80 && setup[1] == 6 && setup[3] == 2) {
            data_length[slot] = setup[6] | setup[7] << 8;
            data_buffer[slot] = 0;
            data_address[slot] = regs[5];
        }
    } else if (tag == TAG_COMPLETION && (regs[0] & 1) && data_length[slot]) {
        if (data_buffer[slot]) {
            log_data(regs[0] & ~1u, data_buffer[slot], data_length[slot], data_address[slot]);
            find_audio(data_buffer[slot], data_length[slot], data_address[slot]);
        }
        data_length[slot] = 0;
        data_buffer[slot] = 0;
    }
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
    /* Follow each device request before the limit: the data dump needs all of them. */
    if (tag == TAG_CONTROL_TRANSFER) {
        unsigned request = regs[0] & ~1u, i, known = 0;
        for (i = 0; i < 4; i++)
            if (device_requests[i] == request)
                known = 1;
        if (!known) {
            i = next_request;
            device_requests[i] = request;
            data_length[i] = 0;
            data_buffer[i] = 0;
            next_request = (next_request + 1) & 3;
        } else {
            for (i = 0; device_requests[i] != request; i++)
                ;
        }
        track_data(tag, regs, i);
    }
    if ((tag == TAG_CONTROL_ENDPOINT || tag == TAG_CONTROL_TRANSFER) && uim_logs++ >= UIM_LOGS)
        return;
    /* The root hub polls its port all the time, and each poll ends in a completion. Log only the
     * completions of the requests of logged device transfers (r0 without the stage bit). */
    if (tag == TAG_COMPLETION) {
        unsigned request = regs[0] & ~1u, i, known = 0;
        for (i = 0; i < 4; i++)
            if (device_requests[i] == request) {
                known = 1;
                track_data(tag, regs, i);
            }
        if (!known || completion_logs++ >= COMPLETION_LOGS)
            return;
    }
    if (tag == TAG_INTERRUPT_COMPLETION && interrupt_logs++ >= 100)
        return;
    if ((tag == TAG_INTERRUPT_ENDPOINT || tag == TAG_INTERRUPT_TRANSFER)
        && (regs[0] == root_hub_address || uim_logs++ >= UIM_LOGS))
        return;
    /* While the music test runs, log only the audio records (the hub poll fills the log). */
    if (music_mode && tag < TAG_AUDIO_DEVICE)
        return;
    /* Keep the last LOG_RESERVE records for the audio test and the registers. */
    if (L && (L->count < LOG_MAX - LOG_RESERVE || tag >= TAG_AUDIO_DEVICE || tag == TAG_REGISTERS)
        && L->count < LOG_MAX) {
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

/* ---- Stage 2 of USB-AUDIO-OUT.md: isochronous OUT to a USB audio device ----------------------
 * The UIM of the firmware has no isochronous transfers (the table entries 0xd4820 and 0xd4828 return
 * -1). This test makes the transfers itself, without the UIM:
 *  1. It finds a USB Audio Class 2 device in the received configuration descriptors: an audio
 *     streaming interface with 2 channels, 2-byte samples and an isochronous OUT endpoint.
 *  2. It sends SET_INTERFACE and SET_CUR (48 kHz to the clock source of the playback terminal) through
 *     its own control queue head in the asynchronous list.
 *  3. It puts one siTD (split isochronous transfer descriptor) in each of the 1024 frames of the
 *     periodic frame list. Each siTD sends 192 bytes (48 stereo samples, one period of 1 kHz) to the
 *     endpoint through the transaction translator of the controller (hub 0, port 1, as the UIM
 *     queue heads). The UI task makes each executed siTD active again.
 *  4. After TONE_MS it removes the siTDs and sends SET_INTERFACE with alternate setting 0.
 * The memory comes from 0xad80c, as the frame list and the queue heads of the UIM. The CPU and the
 * controller use the same address (0x9xxxxxxx): the cache operation 0xa7164 is empty, and 0x9e2d4
 * gives the same address back. */
static const short sine[48] = {                       /* one period: 1 kHz at 48 kHz, peak TONE_LEVEL */
         0,    522,   1035,   1531,   2000,   2435,   2828,   3173,   3464,   3696,   3864,   3966,
      4000,   3966,   3864,   3696,   3464,   3173,   2828,   2435,   2000,   1531,   1035,    522,
         0,   -522,  -1035,  -1531,  -2000,  -2435,  -2828,  -3173,  -3464,  -3696,  -3864,  -3966,
     -4000,  -3966,  -3864,  -3696,  -3464,  -3173,  -2828,  -2435,  -2000,  -1531,  -1035,   -522
};

struct audio {
    unsigned address, interface, alt, endpoint, packet, clock;
};

static volatile unsigned char *dma_page;                /* control QH, qTDs, setup, data, tone buffer */
static volatile unsigned *sitd;                         /* FRAMES siTDs of 8 words */
static int control_linked;

static void log_regs(int tag, unsigned r0, unsigned r1, unsigned r2, unsigned r3)
{
    unsigned regs[4];
    regs[0] = r0;
    regs[1] = r1;
    regs[2] = r2;
    regs[3] = r3;
    log_call(tag, regs);
}

/* A UAC2 playback interface in a configuration descriptor. Returns 0 if found. */
static int parse_audio(const unsigned char *d, unsigned len, struct audio *a)
{
    unsigned o = 0, cls = 0, sub = 0, proto = 0, ifn = 0, alt = 0, clock = 0, subslot = 0, channels = 0;
    while (o + 2 <= len) {
        const unsigned char *b = d + o;
        unsigned l = b[0], t = b[1];
        if (l < 2 || o + l > len)
            break;
        if (t == 4 && l >= 9) {                         /* interface */
            ifn = b[2];
            alt = b[3];
            cls = b[5];
            sub = b[6];
            proto = b[7];
            subslot = channels = 0;
        } else if (t == 0x24 && cls == 1 && proto == 0x20) {
            if (sub == 1 && b[2] == 2 && l >= 17 && b[4] == 1 && b[5] == 1)
                clock = b[7];                           /* input terminal "USB streaming": its clock source */
            else if (sub == 2 && b[2] == 1 && l >= 16)
                channels = b[10];                       /* AS_GENERAL: bNrChannels */
            else if (sub == 2 && b[2] == 2 && l >= 6)
                subslot = b[4];                         /* FORMAT_TYPE I: bSubslotSize */
        } else if (t == 5 && l >= 7 && cls == 1 && sub == 2 && proto == 0x20 && (b[3] & 3) == 1
                   && !(b[2] & 0x80) && subslot == 2 && channels == 2 && (b[4] | b[5] << 8) >= 192) {
            a->interface = ifn;
            a->alt = alt;
            a->endpoint = b[2] & 0xf;
            a->packet = b[4] | b[5] << 8;
            a->clock = clock;
            return 0;
        }
        o += l;
    }
    return -1;
}

/* The first UAC2 playback interface of a received configuration (called at the completion, possibly in
 * the interrupt handler: it only reads and writes RAM). */
static struct audio found;
static int audio_found;

static void find_audio(unsigned buffer, unsigned length, unsigned address)
{
    static unsigned char cfg[DATA_MAX];
    unsigned n, total;
    if (audio_found || !ram_address(buffer) || !ram_address(buffer + DATA_MAX))
        return;
    if (length > DATA_MAX)
        length = DATA_MAX;
    for (n = 0; n < length; n++)
        cfg[n] = ((const volatile unsigned char *)buffer)[n];
    total = cfg[2] | cfg[3] << 8;
    if (length < 9 || cfg[1] != 2 || parse_audio(cfg, total < length ? total : length, &found) != 0)
        return;
    found.address = address;
    audio_found = 1;
}

static void make_td(volatile unsigned *td, unsigned next, unsigned token, unsigned buffer)
{
    int i;
    td[0] = next;
    td[1] = 1;                                          /* alternate next: none */
    td[3] = buffer;
    td[4] = (buffer & ~0xfffu) + 0x1000;
    for (i = 5; i < 8; i++)
        td[i] = 0;
    td[2] = token;                                      /* last: the token makes it active */
}

/* A control transfer through the probe's own queue head (setup, an optional OUT data stage of at most
 * 4 bytes, status IN). The UI task waits for the result. Returns 0 if correct. */
static int control(unsigned address, unsigned setup0, unsigned setup1, unsigned data, unsigned length)
{
    volatile unsigned *qh = (volatile unsigned *)dma_page;
    volatile unsigned *td_setup = qh + 0x10, *td_data = qh + 0x18, *td_status = qh + 0x20;
    volatile unsigned *setup = qh + 0x28, *buffer = qh + 0x30;
    unsigned status, i;
    setup[0] = setup0;
    setup[1] = setup1;
    buffer[0] = data;
    make_td(td_status, 1, 0x80 | 1 << 8 | 0xc00 | 1u << 31, 0);              /* IN, 0 bytes, DATA1 */
    if (length)
        make_td(td_data, (unsigned)td_status, 0x80 | 0 << 8 | 0xc00 | length << 16 | 1u << 31, (unsigned)buffer);
    make_td(td_setup, length ? (unsigned)td_data : (unsigned)td_status, 0x80 | 2 << 8 | 0xc00 | 8 << 16, (unsigned)setup);
    /* Endpoint 0, full speed, data toggle from the qTD, 64 bytes, control endpoint; hub 0, port 1. */
    qh[1] = address | 0x4000 | 64 << 16 | 0x08000000;
    qh[2] = 0x40800000;
    qh[3] = 0;
    qh[5] = 1;
    for (i = 6; i < 12; i++)
        qh[i] = 0;
    qh[4] = (unsigned)td_setup;
    if (!control_linked) {                              /* after the head of the asynchronous list */
        volatile unsigned *head = (volatile unsigned *)(ASYNCLIST & ~0x1fu);
        if ((unsigned)head < DMA_LOW || (unsigned)head >= DMA_HIGH) {
            log_regs(TAG_AUDIO_REQUEST, setup0, setup1, 0, 0x80);
            return -1;
        }
        qh[0] = head[0];
        head[0] = (unsigned)qh | 2;
        control_linked = 1;
    }
    for (i = 0; i < 100; i++) {
        task_sleep(2);
        status = td_setup[2] | td_data[2] | td_status[2];
        if (!(td_status[2] & 0x80) || (status & 0x40))
            break;
    }
    status = td_status[2];
    log_regs(TAG_AUDIO_REQUEST, setup0, setup1, td_setup[2], status);
    return (status & 0xff) == 0 ? 0 : -1;
}

static void sitd_arm(volatile unsigned *s, unsigned buffer)
{
    s[4] = buffer;
    s[5] = ((buffer + 191) & ~0xfffu) | 1 << 3 | 2;    /* TP "begin", 2 start splits */
    s[3] = 0x80 | 192 << 16;                            /* active, 192 bytes */
}

/* Returns 0 if it logged a result. */
static int audio_test(void)
{
    struct audio a;
    unsigned ctrl, i, f, last, now, ok = 0, errors = 0, last_error = 0, start, tone_buffer;
    volatile unsigned *frames;
    volatile short *pcm;
    if (!audio_found)
        return -1;
    a = found;
    log_regs(TAG_AUDIO_DEVICE, a.address, a.interface | a.alt << 8 | a.endpoint << 16, a.packet, a.clock);
    ctrl = read32(UIM_STATE + 0xc);
    frames = (volatile unsigned *)read32(ctrl + 0x44);
    if (!dma_page) {
        unsigned p = (unsigned)dma_alloc(0x2000, 1), q = (unsigned)dma_alloc(FRAMES * 32 + 32, 1);
        dma_page = (volatile unsigned char *)((p + 0xfff) & ~0xfffu);
        sitd = (volatile unsigned *)((q + 31) & ~31u);
    }
    log_regs(TAG_AUDIO_MEMORY, (unsigned)dma_page, (unsigned)sitd, (unsigned)frames, ASYNCLIST);
    /* Use the memory only in the window of the UIM memory. */
    if ((unsigned)dma_page < DMA_LOW || (unsigned)dma_page >= DMA_HIGH || (unsigned)sitd < DMA_LOW
        || (unsigned)sitd >= DMA_HIGH || (unsigned)frames < DMA_LOW || (unsigned)frames >= DMA_HIGH)
        return 0;
    /* SET_INTERFACE (interface, alternate setting), then SET_CUR sampling frequency 48000 to the clock. */
    if (control(a.address, 0x01 | 0x0b << 8 | a.alt << 16, a.interface, 0, 0) != 0)
        return 0;
    if (a.clock)
        control(a.address, 0x21 | 0x01 << 8 | 0x0100 << 16, a.clock << 8 | 4 << 16, 48000, 4);
    tone_buffer = (unsigned)(dma_page + 0x100);
    pcm = (volatile short *)tone_buffer;
    for (i = 0; i < 48; i++)
        pcm[2 * i] = pcm[2 * i + 1] = sine[i];
    for (f = 0; f < FRAMES; f++) {
        volatile unsigned *s = sitd + 8 * f;
        s[1] = a.address | a.endpoint << 8 | 0 << 16 | 1u << 24;   /* OUT, hub 0, port 1 */
        s[2] = 0x03;                                    /* start splits in micro-frames 0 and 1 */
        s[6] = 1;                                       /* no back pointer */
        sitd_arm(s, tone_buffer);
        s[0] = frames[f];
    }
    tone(HIGH, 60000);                                  /* the iPod sign: the USB tone starts now */
    for (f = 0; f < FRAMES; f++)
        frames[f] = (unsigned)(sitd + 8 * f) | 4;       /* type siTD */
    start = last = FRINDEX >> 3 & (FRAMES - 1);
    for (i = 0; i < TONE_MS / 4; i++) {
        task_sleep(4);
        now = FRINDEX >> 3 & (FRAMES - 1);
        for (f = last; f != now; f = (f + 1) & (FRAMES - 1)) {
            volatile unsigned *s = sitd + 8 * f;
            unsigned status = s[3];
            if (status & 0x80)
                continue;
            if (status & 0x7c) {
                errors++;
                last_error = status;
            } else {
                ok++;
            }
            sitd_arm(s, tone_buffer);
        }
        last = now;
    }
    for (f = 0; f < FRAMES; f++) {
        volatile unsigned *s = sitd + 8 * f;
        s[3] = 0;
        if (frames[f] == ((unsigned)s | 4))
            frames[f] = s[0];
    }
    log_regs(TAG_AUDIO_STREAM, ok, errors, last_error, start | (FRINDEX >> 3 & (FRAMES - 1)) << 16);
    control(a.address, 0x01 | 0x0b << 8, a.interface, 0, 0);   /* alternate setting 0: stop */
    return 0;
}

/* ---- Stage 4 test: the music of the iPod to the USB audio device -----------------------------------
 * The firmware has a USB audio source for accessories (re/usb-audio.md). When +0x5a of the audio output
 * object (0x1a3070) is 1, 0x1a2d60 gives the PCM buffers of the decoder to the USB queue (0x1e2bc8), not
 * to the codec. USBAudioTask (0xc75cc) waits for the event at state + 0x18, then 0x132038 takes 12
 * packets (0x1e3064, the size from 0x10fbb4: rate / 1000 frames of 4 bytes), sends them (0x24d518),
 * waits (0x24c4cc) and gives the buffers of the earlier set back (0x1e2bdc). The bl hooks at these
 * calls put the packets into the siTDs and wait for the frames, when music_mode is 1. Else they call
 * the original functions (the device mode is unchanged). */
static int last_send;
static unsigned next_frame, music_packets, music_underruns, music_max_ahead, music_logged, music_sound;
static unsigned music_sleeps, music_sleep_ms, music_sleep_frames;
static volatile unsigned char *music_ring;              /* RING x PACKET_MAX bytes */
static struct audio music_device;

static unsigned frame_now(void)
{
    return FRINDEX >> 3 & (FRAMES - 1);
}

static void sitd_packet(volatile unsigned *s, unsigned buffer, unsigned length)
{
    s[1] = music_device.address | music_device.endpoint << 8 | 1u << 24;   /* OUT, hub 0, port 1 */
    s[4] = buffer;
    if (length <= 188) {                                /* one start split, "all" */
        s[2] = 0x01;
        s[5] = ((buffer + length - 1) & ~0xfffu) | 0 << 3 | 1;
    } else {                                            /* two start splits, "begin" */
        s[2] = 0x03;
        s[5] = ((buffer + length - 1) & ~0xfffu) | 1 << 3 | 2;
    }
    s[3] = 0x80 | length << 16;
}

int hook_usb_send(void *device, int endpoint, int count, unsigned char *packets)
{
    int i;
    unsigned now, ahead;
    if (!music_mode)
        return last_send = fw_usb_send(device, endpoint, count, packets);
    DIGITAL_AUDIO_READY = 1;                            /* again, if the firmware cleared it */
    now = frame_now();
    ahead = (next_frame - now) & (FRAMES - 1);
    if (ahead < 2 || ahead > FRAMES / 2) {              /* behind the controller: start again ahead */
        next_frame = (now + 2) & (FRAMES - 1);
        music_underruns++;
    }
    for (i = 0; i < count; i++) {
        unsigned char *p = packets + 12 * i;
        const short *in = *(const short **)p;
        unsigned length = *(unsigned short *)(p + 6), k;
        volatile short *out = (volatile short *)(music_ring + (next_frame & (RING - 1)) * PACKET_MAX);
        if (length > PACKET_MAX)
            length = PACKET_MAX;
        if (length >= 4 && (in[0] | in[1] | in[length / 2 - 1]))
            music_sound++;                              /* a packet that is not silence */
        for (k = 0; k < length / 2; k++)
            out[k] = in[k] >> 2;                        /* -12 dB: the digital route has no volume */
        sitd_packet(sitd + 8 * next_frame, (unsigned)out, length);
        next_frame = (next_frame + 1) & (FRAMES - 1);
        music_packets++;
    }
    ahead = (next_frame - frame_now()) & (FRAMES - 1);
    if (ahead > music_max_ahead && ahead < FRAMES / 2)
        music_max_ahead = ahead;
    return last_send = 0;
}

/* Wait until AHEAD_LOW frames are in front of the controller, with one sleep. Version 1.5 slept 1 ms
 * many times in each 12 ms; the menus were very slow (the sleep 0x11c9fc yields in a loop until the
 * time is over). Apple's code blocks on an event of the USB interrupt instead. The sleep records count
 * the requested ms and the frames that passed. */
static int music_wait(void *device, int endpoint)
{
    unsigned ahead, start;
    if (!music_mode)
        return fw_usb_wait(device, endpoint);
    ahead = (next_frame - frame_now()) & (FRAMES - 1);
    if (ahead > AHEAD_LOW && ahead <= FRAMES / 2) {
        start = frame_now();
        task_sleep(ahead - AHEAD_LOW);
        music_sleeps++;
        music_sleep_ms += ahead - AHEAD_LOW;
        music_sleep_frames += (frame_now() - start) & (FRAMES - 1);
    }
    return 0;
}

int hook_usb_wait(void *device, int endpoint)
{
    return music_wait(device, endpoint);
}

/* 0x13218c was "bleq 0x24c4cc": wait only if the send returned 0. */
int hook_usb_wait_if_sent(void *device, int endpoint)
{
    if (last_send != 0)
        return 0;
    return music_wait(device, endpoint);
}

/* Start the music route to the device of audio_test. The siTDs stay in the frame list. */
static void music_start(const struct audio *a)
{
    volatile unsigned char *output = (volatile unsigned char *)AUDIO_OUTPUT;
    unsigned source = USB_AUDIO_SOURCE, object = *(volatile unsigned *)(USB_AUDIO_STATE + 0x10);
    unsigned event = *(volatile unsigned *)(USB_AUDIO_STATE + 0x18), rate = 44100, f, ctrl;
    volatile unsigned *frames;
    log_regs(TAG_MUSIC_START, object, source, (unsigned)output, event);
    if (!object || !source || !output || !event || !dma_page)
        return;
    if (!music_ring)
        music_ring = (volatile unsigned char *)dma_alloc(RING * PACKET_MAX, 1);
    if (!ram_address((unsigned)music_ring))
        return;
    music_device = *a;
    if (control(a->address, 0x01 | 0x0b << 8 | a->alt << 16, a->interface, 0, 0) != 0)
        return;
    if (a->clock && control(a->address, 0x21 | 0x01 << 8 | 0x0100 << 16, a->clock << 8 | 4 << 16, 44100, 4) != 0) {
        rate = 48000;
        control(a->address, 0x21 | 0x01 << 8 | 0x0100 << 16, a->clock << 8 | 4 << 16, 48000, 4);
    }
    /* The rate of the packets: state + 8 (0x10fbb4), and the output rate of the converter (0x1e2f60,
     * as SET_CUR 0x13249c does). State + 1 = 0: 1000 packets each second (full speed). */
    USB_AUDIO_STATE[1] = 0;
    *(volatile unsigned *)(USB_AUDIO_STATE + 8) = rate;
    *(volatile unsigned *)(USB_AUDIO_STATE + 0xc) = 0;
    fw_rate_convert((void *)source, rate);
    /* All siTDs inactive, before the old entry of each frame. */
    ctrl = read32(UIM_STATE + 0xc);
    frames = (volatile unsigned *)read32(ctrl + 0x44);
    if (!ram_address((unsigned)frames))
        return;
    for (f = 0; f < FRAMES; f++) {
        volatile unsigned *s = sitd + 8 * f;
        s[3] = 0;
        s[6] = 1;
        if (frames[f] != ((unsigned)s | 4)) {
            s[0] = frames[f];
            frames[f] = (unsigned)s | 4;
        }
    }
    next_frame = (frame_now() + 4) & (FRAMES - 1);
    music_mode = 1;
    /* The steps of 0x132274 without the device endpoint (0x24bf74): stream on, the event for
     * USBAudioTask, and the route of the audio output to USB (+0x59, then 0x1a2fa0 sets +0x58 and
     * +0x5a). */
    DIGITAL_AUDIO_READY = 1;
    USB_AUDIO_STATE[2] = 1;
    fw_event_signal((void *)event);
    output[0x59] = 1;
    fw_route_usb((void *)output, 1);
    log_regs(TAG_MUSIC_START, rate, output[0x58] | output[0x59] << 8 | output[0x5a] << 16, USB_AUDIO_STATE[2], 1);
}

/* Two records: the USB side, and the chain from the decoder (refer to re/usb-host.md, Stage 4):
 * output + 0x50 codec buffers, + 0x54 USB buffers out; source + 0 and + 1 (1: test signal, no music),
 * + 4 the music rate, + 0xc the output rate, the queue indices + 0x5c and + 0x5e; DIGITAL_AUDIO_READY;
 * the byte 0x1081dff4 (0x1e3040 sets source + 1 if it is not 0). */
static void music_stats(void)
{
    volatile unsigned char *output = (volatile unsigned char *)AUDIO_OUTPUT;
    volatile unsigned char *source = (volatile unsigned char *)USB_AUDIO_SOURCE;
    log_regs(TAG_MUSIC_STATS, music_packets, music_underruns, music_sound,
             (output ? output[0x5a] : 0xff) | (unsigned)USB_AUDIO_STATE[2] << 8
             | (source ? source[0] | source[1] << 8 : 0xffff) << 16);
    log_regs(TAG_MUSIC_CHAIN, output ? read32((unsigned)output + 0x50) : 0, output ? read32((unsigned)output + 0x54) : 0,
             source ? (read32((unsigned)source + 0x5c) & 0xffff) | (read32((unsigned)source + 0x5c) >> 16) << 8
                      | (unsigned)DIGITAL_AUDIO_READY << 16 | (unsigned)*(volatile unsigned char *)0x1081dff4 << 24 : 0,
             source ? (read32((unsigned)source + 4) & 0xffff) | read32((unsigned)source + 0xc) << 16 : 0);
    log_regs(TAG_MUSIC_SLEEP, music_sleeps, music_sleep_ms, music_sleep_frames, music_max_ahead);
    music_logged = music_packets;
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
            /* Give the device class EF/02 (interface association, for example USB audio) to the
             * composite driver, so that it reads the configuration. The stock record has class 2/0
             * (communications). Change it only if it has the expected values. */
            if (COMPOSITE2_CLASS[0] == 2 && COMPOSITE2_CLASS[1] == 0) {
                COMPOSITE2_CLASS[0] = 0xef;
                COMPOSITE2_CLASS[1] = 2;
            }
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
            /* Stage 2 of USB-AUDIO-OUT.md: a test tone to a USB audio device (refer to audio_test). */
            if (audio_test() == 0) {
                /* Stage 4 test: the music to the device. Return at once, so that the owner can
                 * start a song. A later button event logs the statistics. */
                music_start(&found);
                if (write_log() == 0) {
                    tone(LOW, 60000);
                    task_sleep(BEEP_MS);
                    tone(LOW, 60000);
                }
                return r;
            }
            /* A second write: the ports of a hub and the devices behind it take more time. */
            task_sleep(LOG_WAIT2_MS);
            if (write_log() == 0) {
                tone(LOW, 60000);
                task_sleep(BEEP_MS);
                tone(LOW, 60000);
            }
        }
    } else if (started && L) {
        if (music_mode) {
            if (music_packets - music_logged >= STATS_PACKETS) {
                music_stats();                          /* at most one write each 5 s of music */
                write_log();
            }
        } else if (L->count != log_saved) {
            write_log();
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
