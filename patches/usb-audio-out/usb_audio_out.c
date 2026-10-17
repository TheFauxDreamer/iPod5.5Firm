/* usb-audio-out: USB-C audio out for the iPod 5.5G with a USB-C mod (Stage 3 of USB-AUDIO-OUT.md).
 *
 * Settings > "USB-C Audio" switches between the normal USB port (Off, the default after each start)
 * and USB host mode for USB Audio Class 2 headphones (On). The code of the functions comes from the
 * probe patches/usb-host-probe (versions 1.3-1.27, tested on the real iPod). The research is in
 * re/usb-host.md and patches/usb-host-probe/FINDINGS.md.
 *
 * On (the patch task "USBAudioOut"):
 *  1. The USB mode manager (RAM 0x1081edc4) leaves the device mode (0x18482c, mode 1). The patch
 *     waits for Apple's stop of the device session.
 *  2. The manager starts the host client (0x184860, mode 2: 0x1422c0, then the host start 0x2860e8).
 *     The hooks give full speed, the host interrupt handler and the periodic insert fix.
 *  3. When the headphones are enumerated (find_audio reads their configuration), the task starts the
 *     music route: the decoder buffers of Apple's USB audio source go into the siTDs of the patch.
 *     This also occurs after a reconnection.
 *  4. The volume of the headphones follows the iPod volume. The buttons of the headphones operate as
 *     an Apple Remote (0x1ac198). A disconnection pauses the song.
 * Off: the route stops, the manager stops the host client (0x18482c, mode 2: 0x142298, the host stop
 * 0x28608c), and the device mode starts again (0x184860, mode 1) if USB power is present. Then a
 * computer can see the iPod.
 *
 * While host mode runs, the device task cannot start or stop a device session (that takes the
 * controller from the host stack), the USB mode task cannot stop the host mode at a new VBUS, and the
 * iPod shows no USB host messages ("unsupported device").
 *
 * Version 1.3: Settings > Main Menu > "USB-C Audio" shows or hides an item in the main menu (the main
 * menu mask bit 0x80000000, as album-artists does with 0x40000000). The item is a copy of Backlight.
 * A selection of it switches USB-C Audio On or Off, and the firmware does not run the Backlight action.
 *
 * Version 1.4: fewer wakes while the route runs. Apple's USB host task (0xd3390) waits at most 1 tick
 * for a message and then polls (0xb9004): 1000 times each second. While the route runs it waits at most
 * HOST_TICKS. USBAudioTask makes two sets of 12 packets in each wake (about 41 wakes each second).
 *
 * Version 1.9: a fast fill. Apple's fill (0x1e3064) used about 13 % of core 0 on the real iPod, also
 * with silence (measurement builds 1.5-1.8 of the branch usb-audio-speed, re/usb-host.md). While the
 * route runs and the input rate equals the output rate, hook_fill does the same work with word loops:
 * no 0x7cae0 copy, no 0x7cd28 clear, no software division (0x82694). At other rates (the option 48 kHz
 * with a 44.1 kHz song) Apple's fill and its rate converter (about 12 % of core 0) do the work. */

#define APP_OBJECT    0x1081da18                        /* RAM: the app object (+0x1c database, +0x40c output volume) */
#define MODE_MANAGER  (*(volatile unsigned *)0x1081edc4)  /* the USB mode manager (made by the task 0xb95a4) */
#define KEY_PLAY_PAUSE  0x1c                            /* the key codes of the Simple Remote table at 0x63ef30 */
#define KEY_VOLUME_UP   0x20
#define KEY_VOLUME_DOWN 0x1f
#define KEY_NEXT        0x1e                            /* two pushes of the middle button */
#define KEY_PREVIOUS    0x1d                            /* three pushes */
#define KEY_PAUSE       0x3c
#define MULTI_PRESS_US  400000                          /* the time after the last release for one more push */
#define DEVICE_START_BLOCKED     1
#define DEVICE_START_ALLOWED     2
#define DEVICE_STOP_DONE         3
#define DEVICE_STOP_SKIPPED      4
#define DEVICE_MESSAGE_SKIPPED   6
#define DEVICE_WAIT_MS 2500                             /* the wait for the end of the device session */
#define ERROR_STREAK 200                                /* siTD errors in a row: the device is gone */
#define USEC       (*(volatile unsigned *)0x60005010)   /* the microsecond timer (0x282860) */
#define AHEAD_LOW  24                                   /* the frames in front after a wait */
#define AHEAD_HIGH 40                                   /* version 1.4: sleep only above this (two sets in each wake) */
#define HOST_TICKS 8                                    /* version 1.4: the wait of the host task while the route runs */
#define RING       64                                   /* the music buffers (one for each frame) */
#define PACKET_MAX 192                                  /* the largest packet (48 kHz, 16 bits, stereo) */
#define USB_AUDIO_STATE ((volatile unsigned char *)0x108234ec)   /* +1 speed, +2 stream on, +8 rate, +0x10 object, +0x18 event */
#define USB_AUDIO_SOURCE (*(volatile unsigned *)0x10831964)        /* the queue of the music for USB (0x1e30d0) */
#define AUDIO_OUTPUT     (*(volatile unsigned *)(0x108236a4 + 4))  /* the audio output object (0x1a3070) */
/* 0x1e3064 fills a packet from the music queue only if 0x1e2f74 returns 1. Without an iAP "Digital
 * Audio" accessory this byte is 0, and the packets are silence. */
#define DIGITAL_AUDIO_READY (*(volatile unsigned char *)0x1081dff6)
#define FRAMES     1024                                 /* the periodic frame list (USBCMD bits 3:2 = 0) */
#define DMA_LOW    0x90000000u                          /* the RAM window of the USB structures */
#define DMA_HIGH   0x94000000u
#define DATA_MAX   512                                  /* the bytes of a configuration that find_audio reads */
/* The second composite driver record matches device class 2. The patch gives it the class EF/02
 * (interface association, for example USB audio), so that it reads the configuration. */
#define COMPOSITE2_CLASS ((volatile unsigned char *)0x1084a395)
/* The storage driver record (RAM 0x1084a49c): +0x12 the interface class, +0x35 the device class (8).
 * While host mode runs, both are 0xff: no storage device (for example the card slot of a dock) gets a
 * driver, thus the iPod does not enter the photo import state. */
#define STORAGE_RECORD ((volatile unsigned char *)0x1084a49c)
#define UIM_STATE  0x1084a778                           /* +0xc: the controller object of the UIM */
#define USB_GLOBALS ((volatile unsigned char *)0x1083e0f8) /* +0 not 0: hubs behind the root hub are allowed */
#define USB_IRQ    20                                   /* the USB interrupt source of the PP5022 */
#define DEVICE_ISR ((void *)0xcd8e0)                    /* the handler of the device driver */
#define FRINDEX    (*(volatile unsigned *)0xc500014c)
#define ASYNCLIST  (*(volatile unsigned *)0xc5000158)
#define OTGSC      (*(volatile unsigned *)0xc50001a4)
#define TAG_COMPLETION           24                     /* the calls of track_call */
#define TAG_CONTROL_ENDPOINT     25
#define TAG_CONTROL_TRANSFER     26
/* The Settings item. */
#define LABEL_ID   0x7e06                               /* the label "USB-C Audio" */
#define ON_44_ID   0x7e07                               /* the value text "On (44.1 kHz)" (version 1.2) */
#define ON_48_ID   0x7e08                               /* the value text "On (48 kHz)" (version 1.2) */
#define MAIN_ITEM_ID 0x7e0a                             /* the label of the main menu item: "USB-C Audio: Off" and so on */
#define ROW_KEY    0x7e09                               /* the row in Settings > Main Menu (patch.json: 0x60007e09) */
#define SLEEP_LABEL 0x5f94                              /* Sleep: the template of that row */
#define ARTISTS_LABEL 0x5f7c                            /* Artists in the main menu */
#define MAIN_MENU_ID 24094
#define MAIN_MENU_BIT 0x80000000u                       /* a free bit of the main menu mask (outside the merge mask 0x1fffffff) */
#define ITEM_KEY   0x60e8                               /* the settings key 0x600060e8 (low 16 bits) */
#define TAG_STR    0x53747220u                          /* 'Str ' */
#define OP_TEXT_ID 0x70724944u                          /* 'prID': the ID of the value text */
#define OP_TEXT    0x53747220u                          /* 'Str ': the value text */
#define NOTIFY_BOOL 0x426f6f6cu                         /* 'Bool': the notice after a change */
#define STR_ON     0x602e
#define STR_OFF    0x602f

/* The patch keeps no log: the record calls in the code of the probe do nothing. */
#define log_regs(...) ((void)0)
#define log_bytes(...) ((void)0)
#define player_log(...) ((void)0)

int fw_play_state(unsigned database);                  /* 0x9ba00: 1 playing, 2 paused, else stopped */
void fw_key(unsigned code, int down, unsigned interrupt);  /* 0x1ac198: a key push or release to the UI task */
void fw_usb_message(unsigned type, unsigned error);    /* 0xd9cec: the USB host message to the UI */
int fw_device_start(void *device, unsigned mode);      /* 0x24d3c4: the original call at 0x170fc8 */
int fw_device_stop(void *device);                      /* 0x24d49c: the original call at 0x170fe0 */
int fw_port_status(int port, unsigned short *status);  /* 0xe7980: the original call at 0xd28f0 */
int fw_chip_check(void);                               /* 0x266794: 1 if the chip ID byte is 0x32 */
int fw_irq_install(void *irq_object, void *handler);   /* 0x18a870: the original call at 0x9741c */
int fw_irq_attach(void *irq_object, void *handler);    /* 0x18a83c: install (manager method +0x48) */
void *fw_irq_manager(void);                            /* 0x127618 */
int fw_irq_disable(void *manager, int source);         /* 0x127888 */
int fw_irq_remove(void *manager, int source, void *handler, int zero);  /* 0x1277d0 */
void host_start(int a, int b, int c, int d);           /* 0x2860e8 */
void task_sleep(int ms);                               /* 0x11c9fc */
int fw_host_receive(void *queue, void *buffer, int size, int ticks);  /* 0x2782f4: a message, or -1 after the time */
void *fw_fill(void *source, unsigned bytes);           /* 0x1e3064: Apple's packet fill */
void *fw_pool_get(void);                               /* 0xd3e70: a 192-byte packet buffer of the pool */
int fw_usb_music_ok(void *source);                     /* 0x1e2f74: 1 if the music may go to USB */
void fw_decoder_give_back(void *handle, int flag);     /* 0xfed68: a decoder buffer back to the decoder */
void *dma_alloc(unsigned size, int zero);              /* 0xad80c: the memory of the UIM */
int fw_usb_send(void *device, int endpoint, int count, void *packets);   /* 0x24d518 */
int fw_usb_wait(void *device, int endpoint);           /* 0x24c4cc */
void fw_event_signal(void *event);                     /* 0xd1e70 */
void fw_route_usb(void *output, int on);               /* 0x1a2fa0 */
void fw_rate_convert(void *source, unsigned rate);     /* 0x1e2f60 */
void fw_route_flush(void *output, int flush);          /* 0x1a2fa8: gives the USB buffers back to the decoder */
int mode_activate(void *manager, unsigned mode);       /* 0x184860: 0 if the mode starts */
int mode_deactivate(void *manager, unsigned mode);     /* 0x18482c: 0 if the mode stops */
int usb_power(void);                                   /* 0x17108c: 1 if USB power is present */
unsigned task_create(const char *name, void (*entry)(int, char **), const char *arguments,
                     unsigned priority, unsigned stack, unsigned a, unsigned b);  /* 0x11c808 */
const char *str_lookup(void *table, int id);           /* 0x21f418 */
void *str_table(void);                                 /* 0x21f3b8 */
void *lookup_next(void *provider, unsigned type, int id);
int get_next(void *self, unsigned op, unsigned key, void *out);
int set_next(void *self, unsigned op, unsigned key, void *value);
void lookup_continue(void);                            /* 0x21f258 */
void *settings_object(void);                           /* 0x193090 */
int main_menu_visible(void *settings, int label);      /* 0x193470 */
void set_main_menu_visible(void *settings, int label, int on);  /* 0x19351c */
void menu_bit_continue(void);                          /* 0x105a08 */
void visible_continue(void);                           /* 0x19ed5c */
void *menu_item_at(void *menu_data, int row);          /* 0x2183ec */
void list_select(void *list, int row, unsigned tag);   /* 0x239f7c: tag 0 = no selection event */
unsigned menu_bit_next(int label);                     /* set by the patcher (chain) */
int activate_next(void *list, int row);
int visible_next(void *screen, int menu, int label, int kind, int visible);
static void music_stop(int reason);
static int music_wanted, music_restart;
static volatile unsigned stop_request;                  /* a stop for USBAudioTask */
static unsigned output_volume(void);
static unsigned volume_cur(unsigned v);
static volatile int audio_wanted;                       /* the Settings item */
unsigned option_rate = 44100;                           /* the option "Sample Rate" (patch.json): 44100 or 48000 */
static int audio_on;                                    /* host mode of this patch */
static unsigned rate_used;                              /* the rate that the headphones report, 0 = no music route */
static int host_running, device_stopped, device_logs;
static int music_mode;                                  /* 1: the music goes to the USB audio device */

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

static void copy_from(unsigned char *dst, unsigned src)
{
    int i;
    if (!ram_address(src) || !ram_address(src + 19))
        return;
    for (i = 0; i < 20; i++)
        dst[i] = ((const volatile unsigned char *)src)[i];
}

struct hid {                                            /* an HID interface with an interrupt IN endpoint */
    unsigned interface, endpoint, packet, length;       /* length: of the report descriptor */
};

struct audio {
    unsigned address, interface, alt, endpoint, packet, clock;
    unsigned control_interface, volume_unit;            /* the AC interface; the unit before the output terminal */
    unsigned hids;                                      /* version 1.21: the HID interfaces (the buttons) */
    struct hid hid[2];
};

static volatile unsigned char *dma_page;                /* control QH, qTDs, setup, data, tone buffer */
static volatile unsigned *sitd;                         /* FRAMES siTDs of 8 words */
static int control_linked;


/* A UAC2 playback interface in a configuration descriptor. Returns 0 if found. */
static int parse_audio(const unsigned char *d, unsigned len, struct audio *a)
{
    unsigned o = 0, cls = 0, sub = 0, proto = 0, ifn = 0, alt = 0, clock = 0, subslot = 0, channels = 0;
    unsigned control = 0, unit = 0;
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
            if (sub == 1)
                control = ifn;
            if (sub == 1 && b[2] == 2 && l >= 17 && b[4] == 1 && b[5] == 1)
                clock = b[7];                           /* input terminal "USB streaming": its clock source */
            else if (sub == 1 && b[2] == 3 && l >= 12 && !(b[4] == 1 && b[5] == 1))
                unit = b[7];                            /* output terminal (not USB streaming): its source */
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
            a->control_interface = control;
            a->volume_unit = unit;
            return 0;
        }
        o += l;
    }
    return -1;
}

/* A struct copy without memcpy (the firmware gives no memcpy symbol to the probe). */
static void copy_audio(struct audio *dst, const struct audio *src)
{
    unsigned i;
    for (i = 0; i < sizeof *dst / 4; i++)
        ((unsigned *)dst)[i] = ((const unsigned *)src)[i];
}

/* The HID interfaces of a configuration (version 1.21): the interface, its HID descriptor (0x21,
 * wDescriptorLength of the report descriptor) and its interrupt IN endpoint. At most two. */
static void parse_hid(const unsigned char *d, unsigned len, struct audio *a)
{
    unsigned o = 0, cls = 0, ifn = 0, report = 0;
    a->hids = 0;
    while (o + 2 <= len && a->hids < 2) {
        const unsigned char *b = d + o;
        unsigned l = b[0], t = b[1];
        if (l < 2 || o + l > len)
            break;
        if (t == 4 && l >= 9) {
            ifn = b[2];
            cls = b[5];
            report = 0;
        } else if (t == 0x21 && cls == 3 && l >= 9) {
            report = b[7] | b[8] << 8;
        } else if (t == 5 && l >= 7 && cls == 3 && (b[2] & 0x80) && (b[3] & 3) == 3) {
            struct hid *h = &a->hid[a->hids++];
            h->interface = ifn;
            h->endpoint = b[2] & 0xf;
            h->packet = b[4] | (b[5] & 7) << 8;
            h->length = report;
        }
        o += l;
    }
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
    parse_hid(cfg, total < length ? total : length, &found);
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

/* A control transfer through the probe's own queue head in the asynchronous list: setup, an optional
 * data stage, and the status stage. OUT data: at most 4 bytes (the word at +0xc0). IN data (version
 * 1.21): at most 64 bytes, into CONTROL_IN. control_arm() starts the transfer and returns at once;
 * control_check() gives 0x80 while it runs, else the status byte. Returns -1 if the list is not usable. */
#define CONTROL_IN (dma_page + 0x200)
static int control_data;

static int control_arm(unsigned address, unsigned setup0, unsigned setup1, unsigned data, unsigned length, int in)
{
    volatile unsigned *qh = (volatile unsigned *)dma_page;
    volatile unsigned *td_setup = qh + 0x10, *td_data = qh + 0x18, *td_status = qh + 0x20;
    volatile unsigned *setup = qh + 0x28, *buffer = qh + 0x30;
    unsigned i;
    setup[0] = setup0;
    setup[1] = setup1;
    buffer[0] = data;
    control_data = length != 0;
    if (in) {                                           /* IN data, DATA1; then status OUT, DATA1 */
        make_td(td_status, 1, 0x80 | 0 << 8 | 0xc00 | 1u << 31, 0);
        make_td(td_data, (unsigned)td_status, 0x80 | 1 << 8 | 0xc00 | length << 16 | 1u << 31, (unsigned)CONTROL_IN);
    } else {                                            /* OUT data, DATA1; then status IN, DATA1 */
        make_td(td_status, 1, 0x80 | 1 << 8 | 0xc00 | 1u << 31, 0);
        if (length)
            make_td(td_data, (unsigned)td_status, 0x80 | 0 << 8 | 0xc00 | length << 16 | 1u << 31, (unsigned)buffer);
    }
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
        if ((unsigned)head < DMA_LOW || (unsigned)head >= DMA_HIGH)
            return -1;
        qh[0] = head[0];
        head[0] = (unsigned)qh | 2;
        control_linked = 1;
    }
    return 0;
}

static unsigned control_check(void)
{
    volatile unsigned *qh = (volatile unsigned *)dma_page;
    unsigned status = qh[0x20 + 2], all = qh[0x10 + 2] | status | (control_data ? qh[0x18 + 2] : 0);
    if (!(status & 0x80))
        return status & 0xff;
    return all & 0x40 ? 0x40 : 0x80;                    /* a halted stage ends the transfer */
}

/* The blocking form, for the UI task. Returns 0 if correct. */
static int control_wait(unsigned setup0, unsigned setup1)
{
    unsigned status = 0x80, i;
    for (i = 0; i < 100 && status == 0x80; i++) {
        task_sleep(2);
        status = control_check();
    }
    log_regs(TAG_AUDIO_REQUEST, setup0, setup1, qh[0x10 + 2], qh[0x20 + 2]);
    return status == 0 ? 0 : -1;
}

static int control(unsigned address, unsigned setup0, unsigned setup1, unsigned data, unsigned length)
{
    if (control_arm(address, setup0, setup1, data, length, 0) != 0) {
        log_regs(TAG_AUDIO_REQUEST, setup0, setup1, 0, 0x80);
        return -1;
    }
    return control_wait(setup0, setup1);
}

/* Version 1.25: take the probe's queue head out of the asynchronous ring (at a music stop). When the
 * dock goes away, the UIM removes its queue heads and builds a new ring; the probe's link (qh[0]) can
 * then point to a removed queue head. The next control_arm() links the queue head again after the
 * head of the new ring. The memory of the queue head stays, thus the controller can finish a pass. */
static void control_unlink(void)
{
    volatile unsigned *qh = (volatile unsigned *)dma_page;
    unsigned head = ASYNCLIST & ~0x1fu, a = head, i;
    if (!control_linked || !dma_page)
        return;
    control_linked = 0;
    for (i = 0; i < 64 && a >= DMA_LOW && a < DMA_HIGH; i++) {
        volatile unsigned *p = (volatile unsigned *)a;
        if ((p[0] & ~0x1fu) == (unsigned)qh) {
            p[0] = qh[0];
            return;
        }
        a = p[0] & ~0x1fu;
        if (a == head)
            return;
    }
}

/* Returns the count of received bytes (in CONTROL_IN), or -1. */
static int control_in(unsigned address, unsigned setup0, unsigned setup1, unsigned length)
{
    volatile unsigned *qh = (volatile unsigned *)dma_page;
    if (length > 64)
        length = 64;
    if (control_arm(address, setup0, setup1, 0, length, 1) != 0 || control_wait(setup0, setup1) != 0)
        return -1;
    return (int)(length - (qh[0x18 + 2] >> 16 & 0x7fff));
}


/* ---- The configuration of a new device ----------------------------------------------------------
 * The UIM gives each control transfer to 0x96ffc (setup, data and status stage, a word hook on the
 * dispatch table) and calls the completion 0xcb118 for each stage. For a GET_DESCRIPTOR
 * configuration, track_call keeps the data buffer; at the last completion, find_audio reads the
 * configuration. The root hub of the controller is skipped (its address is the one of the first
 * control endpoint). This can run in the interrupt handler: it only reads and writes RAM. */
static unsigned root_hub_address = 0xffffffff;
static unsigned device_requests[4], next_request;       /* the request blocks of followed transfers */
static unsigned data_length[4], data_buffer[4];         /* GET_DESCRIPTOR configuration: wLength, buffer */
static unsigned data_address[4];                        /* the device address of each followed request */

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
        if (data_buffer[slot])
            find_audio(data_buffer[slot], data_length[slot], data_address[slot]);
        data_length[slot] = 0;
        data_buffer[slot] = 0;
    }
}

/* Called by the wrappers with the saved r0-r3 (and the stack arguments after them). */
void track_call(int tag, const unsigned *regs)
{
    unsigned request, i, known = 0;
    if (tag == TAG_CONTROL_ENDPOINT && root_hub_address == 0xffffffff)
        root_hub_address = regs[0];
    if (tag == TAG_CONTROL_TRANSFER && (root_hub_address == 0xffffffff || regs[5] == root_hub_address))
        return;
    if (tag == TAG_CONTROL_TRANSFER) {
        request = regs[0] & ~1u;
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
    } else if (tag == TAG_COMPLETION) {
        request = regs[0] & ~1u;
        for (i = 0; i < 4; i++)
            if (device_requests[i] == request)
                track_data(tag, regs, i);
    }
}

/* ---- The host hooks -------------------------------------------------------------------------------- */

/* Full speed: the UIM init 0x97300 calls the chip check at 0x97364 and sets PFSC ("port force full
 * speed") if the result is 0. The siTDs and the queue heads of the patch use the transaction translator
 * of the controller (hub 0, port 1); that needs a root port at full speed. */
int hook_chip_check(void)
{
    return host_running ? 0 : fw_chip_check();
}

/* The USB interrupt (0x9741c in the UIM init): while host mode of the patch starts, remove the handler
 * of the device driver, install the UIM handler and enable the source. Else Apple's install 0x18a870. */
int hook_irq_install(void *irq_object, void *handler)
{
    void *manager;
    int **sub;
    int (*enable)(void *, int);
    if (!host_running)
        return fw_irq_install(irq_object, handler);
    manager = fw_irq_manager();
    sub = *(int ***)((char *)manager + 4);
    enable = (int (*)(void *, int))(*sub)[0x30 / 4];
    fw_irq_disable(manager, USB_IRQ);
    fw_irq_remove(manager, USB_IRQ, DEVICE_ISR, 0);
    fw_irq_attach(irq_object, handler);
    return enable(sub, USB_IRQ) != 0;
}

/* The status of a root port (0xe7980, at 0xd28f0 and 0x10e75c). A disconnection stops the music route:
 * USBAudioTask makes the stop at its next wait (stop_request). */
int hook_port_status(int port, unsigned short *status)
{
    int r = fw_port_status(port, status);
    if (music_mode && !(status[0] & 1))
        stop_request = 1;
    return r;
}

/* The memory of the control queue head, its qTDs and buffers (dma_page) and of the siTDs. */
static void usb_memory(void)
{
    if (!dma_page) {
        unsigned p = (unsigned)dma_alloc(0x2000, 1), q = (unsigned)dma_alloc(FRAMES * 32 + 32, 1);
        if (!p || !q)
            return;
        dma_page = (volatile unsigned char *)((p + 0xfff) & ~0xfffu);
        sitd = (volatile unsigned *)((q + 31) & ~31u);
        if ((unsigned)dma_page < DMA_LOW || (unsigned)dma_page >= DMA_HIGH || (unsigned)sitd < DMA_LOW
            || (unsigned)sitd >= DMA_HIGH)
            dma_page = 0;
    }
}

static int last_send;
static unsigned next_frame, music_packets, music_underruns, music_max_ahead, music_sound;
static unsigned music_sleeps;
static unsigned music_used, music_checked, music_errors, music_streak;
static unsigned music_send_us, music_fill_us, music_wait_end, music_start_us;
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

/* Version 1.9: the fill of one packet (the two calls of 0x1e3064 in the stream loop 0x132038). The same
 * steps as 0x1e3064 and 0x1e2c90 (re/usb-host.md). The queue of the source: source + 0x10, 6 entries of
 * 12 bytes (+0 the frames, +4 the decoder buffer, +8 the count of frames, 16 bits), the read index at
 * queue + 0x4e and the write index at queue + 0x4c. queue + 0x7c not 0: the rate converter runs; then,
 * and for the test signal (source + 1), Apple's fill does the work. */
void *hook_fill(unsigned char *source, unsigned bytes)
{
    unsigned char *queue = source + 0x10;
    unsigned *out, *start, frames = bytes >> 2, k;
    int silent;
    if (!music_mode || source[1]
        || (queue[0x7c] && *(volatile unsigned *)(source + 4) != *(volatile unsigned *)(source + 0xc))) {
        return fw_fill(source, bytes);
    }
    out = start = fw_pool_get();
    silent = source[0] ? 1 : !fw_usb_music_ok(source);
    while (frames) {
        volatile unsigned short *read = (volatile unsigned short *)(queue + 0x4e);
        unsigned short write = *(volatile unsigned short *)(queue + 0x4c);
        unsigned char *entry;
        unsigned count, n;
        if (silent || *read == write) {
            for (k = 0; k < frames; k++)                /* silence */
                out[k] = 0;
            break;
        }
        entry = queue + 12 * *read;
        count = *(volatile unsigned short *)(entry + 8);
        if (count == 0) {                               /* this entry is empty: give it back, then the next */
            void *handle = *(void **)(entry + 4);
            if (handle) {
                fw_decoder_give_back(handle, 0);
                *(void **)(entry + 4) = 0;
            }
            if (*read == *(volatile unsigned short *)(queue + 0x4c)) {
                for (k = 0; k < frames; k++)
                    out[k] = 0;
                break;
            }
            *read = *read + 1 >= 6 ? 0 : *read + 1;
            continue;
        }
        n = count < frames ? count : frames;
        {
            const unsigned *in = *(const unsigned **)entry;
            for (k = 0; k < n; k++)
                out[k] = in[k];
            *(const unsigned **)entry = in + n;
        }
        *(volatile unsigned short *)(entry + 8) = (unsigned short)(count - n);
        out += n;
        frames -= n;
    }
    return start;                                       /* as 0x1e3064: the packet buffer */
}

int hook_usb_send(void *device, int endpoint, int count, unsigned char *packets)
{
    int i;
    unsigned now, ahead, start = USEC;
    if (!music_mode)
        return last_send = music_used ? 0 : fw_usb_send(device, endpoint, count, packets);
    if (music_wait_end)
        music_fill_us += start - music_wait_end;        /* the 12 packets of the fill and the buffers back */
    DIGITAL_AUDIO_READY = 1;                            /* again, if the firmware cleared it */
    now = frame_now();
    ahead = (next_frame - now) & (FRAMES - 1);
    if (ahead < 2 || ahead > FRAMES / 2) {              /* behind the controller: start again ahead */
        next_frame = (now + 2) & (FRAMES - 1);
        music_underruns++;
    }
    for (i = 0; i < count; i++) {
        unsigned char *p = packets + 12 * i;
        const unsigned *in = *(const unsigned **)p;
        unsigned length = *(unsigned short *)(p + 6), k;
        volatile unsigned *out = (volatile unsigned *)(music_ring + (next_frame & (RING - 1)) * PACKET_MAX);
        if (length > PACKET_MAX)
            length = PACKET_MAX;
        length &= ~3u;
        if (length >= 4 && (in[0] | in[length / 4 - 1]))
            music_sound++;                              /* a packet that is not silence */
        /* Whole stereo frames (32 bits). The volume is set on the device (volume_poll); version 1.8
         * shifted each sample, and that loop took 19 % of the CPU in the emulator. */
        for (k = 0; k < length / 4; k++)
            out[k] = in[k];
        sitd_packet(sitd + 8 * next_frame, (unsigned)out, length);
        next_frame = (next_frame + 1) & (FRAMES - 1);
        music_packets++;
    }
    ahead = (next_frame - frame_now()) & (FRAMES - 1);
    if (ahead > music_max_ahead && ahead < FRAMES / 2)
        music_max_ahead = ahead;
    music_send_us += USEC - start;
    return last_send = 0;
}

/* Count the executed siTDs since the last check. ERROR_STREAK errors in a row: the device is gone (for
 * example the EarPods were disconnected from the dock). */
static void music_check(void)
{
    unsigned now = frame_now(), f;
    for (f = music_checked; f != now; f = (f + 1) & (FRAMES - 1)) {
        unsigned status = sitd[8 * f + 3];
        if (status & 0x80)
            continue;
        if (status & 0x7c) {
            music_errors++;
            if (++music_streak >= ERROR_STREAK) {
                music_stop(2);
                return;
            }
        } else {
            music_streak = 0;
        }
    }
    music_checked = now;
}

/* ---- Version 1.21: the volume and the buttons of the USB audio device --------------------------------
 * The volume: the iPod keeps its output volume (0-256, after the volume limit) at app + 0x40c; 0x1eee50
 * writes it at each change (re/usb-host.md). USBAudioTask reads it in each wait and sends SET_CUR volume
 * to channels 1 and 2 of the feature unit, without a wait: control_arm(), then control_check() in the
 * next waits. The curve is -48 (1 - v / 256) dB (version 1.27: full volume 0 dB, half -24 dB; version
 * 1.21 used 40 log10(v / 256), which was too loud), clamped to the range of the device (UAC2 RANGE).
 * v = 0 gives 0x8000, "silence" in UAC2.
 * The buttons: the HID interfaces of the device send their reports on interrupt IN endpoints. The probe
 * reads the report descriptors, finds the bits of the Consumer page usages (volume +, volume -,
 * play/pause, next, previous), and polls each endpoint with its own periodic queue head. Version 1.21
 * only logs the reports; the actions on the iPod follow in version 1.22. */

static int vol_min = -60 * 256, vol_max = 0;            /* the range of the device, in 1/256 dB */
static int vol_step;                                    /* 0: idle; 1, 2: the channel in transfer */
static unsigned vol_value, vol_sent = 0xffffffff, vol_sets, vol_errors, vol_status1, vol_polls;

static unsigned output_volume(void)
{
    unsigned app = read32(APP_OBJECT), v = app ? read32(app + 0x40c) : 128;
    return v > 256 ? 256 : v;
}

static unsigned volume_cur(unsigned v)
{
    int db;
    if (v == 0)
        return 0x8000;
    db = (int)(48 * v) - 48 * 256;                     /* version 1.27: -48 dB (1 - v / 256), in 1/256 dB */
    if (db < vol_min)
        db = vol_min;
    if (db > vol_max)
        db = vol_max;
    return (unsigned)db & 0xffff;
}

static void volume_send(unsigned channel, unsigned v)
{
    control_arm(music_device.address, 0x21 | 0x01 << 8 | (0x0200 | channel) << 16,
                music_device.volume_unit << 8 | music_device.control_interface | 2 << 16, volume_cur(v), 2, 0);
    vol_polls = 0;
}

/* In USBAudioTask, at each wait. At most one request at a time; only the newest volume counts. */
static void volume_poll(void)
{
    unsigned status;
    if (!music_device.volume_unit || !dma_page)
        return;
    if (vol_step) {
        status = control_check();
        if (status == 0x80 && ++vol_polls < 100)        /* still in transfer (at most about 1 s) */
            return;
        if (status & 0xfc)
            vol_errors++;
        if (vol_step == 1) {
            vol_status1 = status;
            vol_step = 2;
            volume_send(2, vol_value);
            return;
        }
        vol_step = 0;
        vol_sent = vol_value;
        if (++vol_sets <= 30)
            log_regs(TAG_VOLUME_SET, vol_value, volume_cur(vol_value), vol_status1 | (status & 0xff) << 8, vol_sets | vol_errors << 16);
        return;
    }
    vol_value = output_volume();
    if (vol_value != vol_sent) {
        vol_step = 1;
        volume_send(1, vol_value);
    }
}

/* The range of the volume control (UAC2 RANGE: wNumSubRanges, then wMIN, wMAX, wRES of the first
 * sub-range), and the volume at the start. UI task, before the music. */
static void volume_start(const struct audio *a)
{
    volatile unsigned char *d = CONTROL_IN;
    int got, f;
    if (!a->volume_unit)
        return;
    got = control_in(a->address, 0xa1 | 0x02 << 8 | 0x0201u << 16, a->volume_unit << 8 | a->control_interface | 8 << 16, 8);
    if (got >= 8) {
        int lo = (short)(d[2] | d[3] << 8), hi = (short)(d[4] | d[5] << 8);
        if (lo < hi && lo != -32768) {
            vol_min = lo;
            vol_max = hi;
        }
        log_regs(TAG_VOLUME_RANGE, (unsigned)lo & 0xffff, (unsigned)hi & 0xffff, d[6] | d[7] << 8, got | (d[0] | d[1] << 8) << 8);
    } else {
        log_regs(TAG_VOLUME_RANGE, 0, 0, 0, (unsigned)got & 0xff);
    }
    vol_value = output_volume();
    for (f = 1; f <= 2; f++)
        control(a->address, 0x21 | 0x01 << 8 | (0x0200 | f) << 16, a->volume_unit << 8 | a->control_interface | 2 << 16,
                volume_cur(vol_value), 2);
    vol_sent = vol_value;
}

/* The buttons. BUTTON_* are the bits of the decoded mask. */
#define BUTTONS 5
static const unsigned short button_usage[BUTTONS] = { 0xe9, 0xea, 0xcd, 0xb5, 0xb6 };
#define NO_BIT 0xffff

struct hid_map {
    unsigned id;                                        /* the report ID of the Consumer input (0: none) */
    unsigned bit[BUTTONS];                              /* the bit of each variable button, or NO_BIT */
    unsigned array_offset, array_size, array_count;     /* the Consumer array input, if any */
    unsigned array_min, array_logical;                  /* its Usage Minimum and Logical Minimum */
};

static struct hid_map hid_map[2];
static volatile unsigned *hid_qh[2], *hid_td[2];
static volatile unsigned char *hid_buf[2];
static unsigned hid_packet[2], hid_interface[2], hid_count, hid_frames, hid_link, hid_logs, hid_errors;
static unsigned char hid_last[2][12];
static unsigned hid_last_length[2];

/* The short items of a report descriptor (HID 1.11, 6.2.2). Only the inputs of the Consumer page
 * (0x0c) count: one-bit variable fields, or an array of usage values. */
static void parse_report(struct hid_map *m, const volatile unsigned char *d, unsigned len)
{
    unsigned o = 0, page = 0, size = 0, count = 0, id = 0, offset = 0, logical = 0;
    unsigned usage[16], n = 0, umin = 0, umax = 0, k, i;
    for (k = 0; k < BUTTONS; k++)
        m->bit[k] = NO_BIT;
    m->id = 0;
    m->array_count = 0;
    while (o < len) {
        unsigned b = d[o], bytes = b & 3, value = 0;
        if (bytes == 3)
            bytes = 4;
        if (b == 0xfe || o + 1 + bytes > len)           /* a long item, or the end */
            break;
        for (i = 0; i < bytes; i++)
            value |= (unsigned)d[o + 1 + i] << (8 * i);
        switch (b & 0xfc) {
        case 0x04: page = value; break;                 /* Usage Page */
        case 0x14: logical = value; break;              /* Logical Minimum */
        case 0x74: size = value; break;                 /* Report Size */
        case 0x84: id = value; offset = 0; break;       /* Report ID */
        case 0x94: count = value; break;                /* Report Count */
        case 0x08: if (n < 16) usage[n++] = value & 0xffff; break;   /* Usage */
        case 0x18: umin = value & 0xffff; break;        /* Usage Minimum */
        case 0x28: umax = value & 0xffff; break;        /* Usage Maximum */
        case 0x80:                                      /* Input */
            if (page == 0x0c && !(value & 1) && (value & 2) && size == 1) {
                for (i = 0; i < count; i++) {
                    unsigned u = i < n ? usage[i] : (umax >= umin && umax && umin + i <= umax ? umin + i : 0);
                    for (k = 0; k < BUTTONS; k++)
                        if (u == button_usage[k] && m->bit[k] == NO_BIT) {
                            m->bit[k] = offset + i;
                            m->id = id;
                        }
                }
            } else if (page == 0x0c && !(value & 1) && !(value & 2) && size && size <= 16 && !m->array_count) {
                m->array_offset = offset;
                m->array_size = size;
                m->array_count = count;
                m->array_min = umin;
                m->array_logical = logical;
                m->id = id;
            }
            offset += size * count;
            n = umin = umax = 0;
            break;
        case 0x90: case 0xb0: case 0xa0: case 0xc0:     /* Output, Feature, Collection, End Collection */
            n = umin = umax = 0;
            break;
        }
        o += 1 + bytes;
    }
}

static unsigned report_bits(const unsigned char *r, unsigned len, unsigned bit, unsigned size)
{
    unsigned v = 0, i;
    for (i = 0; i < size; i++, bit++)
        if (bit / 8 < len && (r[bit / 8] >> (bit & 7) & 1))
            v |= 1u << i;
    return v;
}

/* The mask of the pushed buttons (bit k = button_usage[k]); 0x80: a report with a different ID. */
static unsigned decode_buttons(const struct hid_map *m, const unsigned char *r, unsigned len)
{
    unsigned base = 0, mask = 0, k, i;
    if (m->id) {
        if (!len || r[0] != m->id)
            return 0x80;
        base = 8;
    }
    for (k = 0; k < BUTTONS; k++)
        if (m->bit[k] != NO_BIT && report_bits(r, len, base + m->bit[k], 1))
            mask |= 1u << k;
    for (i = 0; i < m->array_count; i++) {
        unsigned v = report_bits(r, len, base + m->array_offset + i * m->array_size, m->array_size);
        if (v && v >= m->array_logical)
            for (k = 0; k < BUTTONS; k++)
                if (m->array_min + v - m->array_logical == button_usage[k])
                    mask |= 1u << k;
    }
    return mask;
}

static void hid_arm(unsigned i)
{
    volatile unsigned *qh = hid_qh[i];
    if (qh[6] & 0x40)                                   /* halted: clear the overlay (data toggle 0) */
        qh[6] = 0;
    make_td(hid_td[i], 1, 0x80 | 1 << 8 | 0xc00 | hid_packet[i] << 16, (unsigned)hid_buf[i]);
    qh[4] = (unsigned)hid_td[i];
}

/* UI task, in music_start after the siTDs are in the frame list. Memory in dma_page: the queue head at
 * 0x300 + 0x100 i, its qTD at + 0x40, the report buffer (64 bytes) at + 0x80. */
static void hid_start(const struct audio *a)
{
    unsigned ctrl = read32(UIM_STATE + 0xc), f, i, k, link;
    volatile unsigned *frames = (volatile unsigned *)read32(ctrl + 0x44);
    if (!ram_address((unsigned)frames))
        return;
    hid_count = 0;
    for (i = 0; i < a->hids && i < 2; i++) {
        const struct hid *h = &a->hid[i];
        volatile unsigned *qh = (volatile unsigned *)(dma_page + 0x300 + 0x100 * i);
        unsigned length = h->length < 64 ? h->length : 64, offset;
        int got = control_in(a->address, 0x81 | 0x06 << 8 | 0x2200u << 16, h->interface | length << 16, length);
        struct hid_map *m = &hid_map[i];
        parse_report(m, CONTROL_IN, got > 0 ? (unsigned)got : 0);
        for (offset = 0; offset < (got > 0 ? (unsigned)got : 1); offset += 40)
            log_bytes(TAG_HID_DESC, h->interface | h->endpoint << 8 | (unsigned)(got & 0xff) << 16, offset,
                      map_byte(m->bit[0]) | map_byte(m->bit[1]) << 8 | map_byte(m->bit[2]) << 16 | (m->id & 0xff) << 24,
                      map_byte(m->bit[3]) | map_byte(m->bit[4]) << 8 | (m->array_count ? m->array_size | m->array_count << 8 : 0) << 16,
                      CONTROL_IN + offset, got > (int)offset ? (unsigned)got - offset : 0);
        hid_qh[i] = qh;
        hid_td[i] = qh + 0x10;
        hid_buf[i] = (volatile unsigned char *)(qh + 0x20);
        hid_packet[i] = h->packet && h->packet < 64 ? h->packet : 64;
        hid_interface[i] = h->interface;
        /* Full speed, the endpoint, the data toggle from the queue head, no reclamation (periodic). */
        qh[1] = a->address | h->endpoint << 8 | hid_packet[i] << 16;
        /* S-mask micro-frame 2, C-mask 4-6 (the siTD start splits use 0 and 1); hub 0, port 1; mult 1. */
        qh[2] = 0x04 | 0x70 << 8 | 1 << 23 | 1u << 30;
        qh[3] = 0;
        qh[5] = 1;
        for (k = 6; k < 12; k++)
            qh[k] = 0;
        hid_last_length[i] = 0xffffffff;
        hid_arm(i);
        hid_count++;
    }
    if (!hid_count)
        return;
    /* The chain: siTD -> queue head 1 -> queue head 0 -> the old link of frame 0. Link it in each 8th
     * frame that has the same old link, so that each queue head has one next pointer. */
    link = sitd[0];
    hid_link = link;
    hid_qh[0][0] = link;
    if (hid_count == 2)
        hid_qh[1][0] = (unsigned)hid_qh[0] | 2;
    hid_frames = 0;
    for (f = 0; f < FRAMES; f += 8)
        if (sitd[8 * f] == link) {
            sitd[8 * f] = (unsigned)hid_qh[hid_count - 1] | 2;
            hid_frames++;
        }
}

/* Unlink the queue heads (music_stop). */
static void hid_stop(void)
{
    unsigned f, i;
    if (!hid_count)
        return;
    for (f = 0; f < FRAMES; f += 8)
        if (sitd[8 * f] == ((unsigned)hid_qh[hid_count - 1] | 2))
            sitd[8 * f] = hid_link;
    for (i = 0; i < hid_count; i++)
        hid_td[i][2] = 0;
    hid_count = 0;
}

/* Version 1.23: a push or a release of a button goes to the UI task through 0x1ac198, the function that
 * the front buttons (0xada4c) and the Simple Remote (0x1e6a84) use. It keeps the state of each key and
 * sends a "kDwn" or "kUp " message (0x151a40) to the UI task, which makes the key events, the repeats
 * and the volume bar. The third argument 0 selects the queue for a task (not an interrupt). */
static unsigned key_down, key_posts;
static unsigned middle_presses, middle_deadline;        /* version 1.25: the presses of the middle button */

static void send_key(unsigned code, unsigned down)
{
    fw_key(code, down, 0);
    if (key_posts++ < 40)
        log_regs(TAG_KEY_POST, code | down << 8, 0, 0, 0);
}

/* Volume + and - go to the UI task at once (push and release; the UI task makes the repeats). The
 * middle button counts its releases: after MULTI_PRESS_US without a new press, one press is
 * play/pause, two presses are the next track and three the previous track (as on an iPhone). */
static void buttons_changed(unsigned mask)
{
    static const unsigned char code[2] = { KEY_VOLUME_UP, KEY_VOLUME_DOWN };
    unsigned k;
    if (mask & 0x80)                                    /* a report with a different ID */
        return;
    for (k = 0; k < 2; k++) {
        unsigned bit = 1u << k, down = (mask & bit) != 0;
        if (down != ((key_down & bit) != 0))
            send_key(code[k], down);
    }
    if (!(mask & 4) && (key_down & 4)) {                /* a release of the middle button */
        middle_presses++;
        middle_deadline = USEC + MULTI_PRESS_US;
    }
    key_down = mask & 7;
}

static void buttons_timer(void)
{
    unsigned code;
    if (!middle_presses || (key_down & 4) || (int)(USEC - middle_deadline) < 0)
        return;
    code = middle_presses == 1 ? KEY_PLAY_PAUSE : middle_presses == 2 ? KEY_NEXT : KEY_PREVIOUS;
    middle_presses = 0;
    send_key(code, 1);
    send_key(code, 0);
}

/* USBAudioTask, at each wait: a completed qTD has a report. Log each change, then arm the qTD again. */
static void hid_poll(void)
{
    unsigned i, k, n, same;
    for (i = 0; i < hid_count; i++) {
        unsigned token = hid_td[i][2];
        unsigned char r[12];
        if (token & 0x80)
            continue;
        if (token & 0x7c) {
            hid_errors++;
        } else {
            n = hid_packet[i] - (token >> 16 & 0x7fff);
            for (k = 0; k < 12; k++)
                r[k] = k < n ? hid_buf[i][k] : 0;
            if (n > 12)
                n = 12;
            for (k = 0, same = n == hid_last_length[i]; k < 12; k++)
                same &= r[k] == hid_last[i][k];
            if (!same) {
                unsigned mask = decode_buttons(&hid_map[i], r, n);
                for (k = 0; k < 12; k++)
                    hid_last[i][k] = r[k];
                hid_last_length[i] = n;
                if (n && hid_map[i].id && r[0] == hid_map[i].id)
                    buttons_changed(mask);      /* the buttons as iPod controls (version 1.23) */
                if (hid_logs++ < 40)
                    log_regs(TAG_HID_REPORT, hid_interface[i] | n << 8 | mask << 16 | (hid_errors > 255 ? 255 : hid_errors) << 24,
                             r[0] | r[1] << 8 | r[2] << 16 | (unsigned)r[3] << 24, r[4] | r[5] << 8 | r[6] << 16 | (unsigned)r[7] << 24,
                             r[8] | r[9] << 8 | r[10] << 16 | (unsigned)r[11] << 24);
            }
        }
        hid_arm(i);
    }
    buttons_timer();
}


/* The play state of the database (for the pause at a disconnection). */
static unsigned play_state(void)
{
    unsigned app = read32(APP_OBJECT), db = app ? read32(app + 0x1c) : 0;
    return db ? (unsigned)fw_play_state(db) : 0xff;
}
/* Version 1.4: the receive of Apple's USB host task (the bl at 0xd33b0). Without a message in the time,
 * the task polls the host stack (0xb9004). A message (for example a completion from the interrupt path)
 * ends the wait at once. While the route runs, a longer time gives fewer polls; enumeration and a new
 * connection keep Apple's 1 tick. */
int hook_host_receive(void *queue, void *buffer, int size, int ticks)
{
    return fw_host_receive(queue, buffer, size, music_mode ? HOST_TICKS : ticks);
}

/* Wait until AHEAD_LOW frames are in front of the controller, with one sleep (0x11c9fc).
 * Version 1.4: no sleep while AHEAD_HIGH frames or fewer are in front. After one set (about 36 frames)
 * Apple's loop makes the next set at once; after two sets (about 48) the task sleeps about 24 ms. The emulator
 * profile shows that this sleep blocks: the loop 0xa0be0/0xa69b4 takes less than 1.5 % of the CPU.
 * Probes 1.7 and 1.8 waited on an event from the USB interrupt; the iPod restarted. */
static int music_wait(void *device, int endpoint)
{
    unsigned ahead;
    if (!music_mode)
        return music_used ? 0 : fw_usb_wait(device, endpoint);
    if (stop_request) {                                 /* version 1.26: the stop in this task, between sets */
        unsigned playing = play_state() == 1;
        stop_request = 0;
        player_log(PLAYER_BEFORE_STOP);
        music_stop(1);
        player_log(PLAYER_AFTER_STOP);
        if (playing) {                                  /* pause, as an iPhone does when the headphones go */
            fw_key(KEY_PAUSE, 1, 0);
            fw_key(KEY_PAUSE, 0, 0);
            player_log(PLAYER_PAUSE_SENT);
        }
        music_wait_end = USEC;
        return 0;
    }
    ahead = (next_frame - frame_now()) & (FRAMES - 1);
    if (ahead > AHEAD_HIGH && ahead <= FRAMES / 2) {
        task_sleep(ahead - AHEAD_LOW);
        music_sleeps++;
    }
    if (music_mode) {
        music_check();
        if (music_mode) {
            volume_poll();
            hid_poll();
        }
    }
    music_wait_end = USEC;
    return 0;
}

/* Stop the music route: the stream off, the siTDs out of the frame list (their links end), the decoder
 * buffers back to the codec, and USBAudioTask awake. The hooks then do nothing. reason 1: the root
 * port lost the connection; 2: ERROR_STREAK siTD errors. */
static void music_stop(int reason)
{
    volatile unsigned char *output = (volatile unsigned char *)AUDIO_OUTPUT;
    unsigned ctrl = read32(UIM_STATE + 0xc), f;
    volatile unsigned *frames = (volatile unsigned *)read32(ctrl + 0x44);
    if (!music_mode)
        return;
    USB_AUDIO_STATE[2] = 0;
    music_mode = 0;
    rate_used = 0;
    hid_stop();
    control_unlink();                                   /* version 1.25: for a new start after a reconnection */
    audio_found = 0;                                    /* the next enumeration gives the new address */
    vol_step = 0;
    vol_sent = 0xffffffff;
    key_down = middle_presses = 0;
    music_restart = music_wanted;
    for (f = 0; f < FRAMES; f++) {
        volatile unsigned *sd = sitd + 8 * f;
        sd[3] = 0;
        if (ram_address((unsigned)frames) && frames[f] == ((unsigned)sd | 4))
            frames[f] = sd[0];
        sd[0] = 1;
    }
    if (output) {
        output[0x59] = 0;
        fw_route_usb((void *)output, 0);
        fw_route_flush((void *)output, 1);
    }
    log_regs(TAG_MUSIC_STOP, reason, music_packets, music_errors, music_sleeps);
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

/* Start the music route to the device that find_audio found. The siTDs stay in the frame list. */
static void music_start(const struct audio *a)
{
    volatile unsigned char *output = (volatile unsigned char *)AUDIO_OUTPUT;
    unsigned source = USB_AUDIO_SOURCE, object = *(volatile unsigned *)(USB_AUDIO_STATE + 0x10);
    unsigned event = *(volatile unsigned *)(USB_AUDIO_STATE + 0x18), rate = option_rate == 48000 ? 48000 : 44100, reported, f, ctrl;
    volatile unsigned *frames;
    log_regs(TAG_MUSIC_START, object, source, (unsigned)output, event);
    if (!object || !source || !output || !event || !dma_page)
        return;
    if (!music_ring)
        music_ring = (volatile unsigned char *)dma_alloc(RING * PACKET_MAX, 1);
    if (!ram_address((unsigned)music_ring))
        return;
    copy_audio(&music_device, a);
    if (control(a->address, 0x01 | 0x0b << 8 | a->alt << 16, a->interface, 0, 0) != 0)
        return;
    /* SET_CUR sampling frequency to the clock source: the rate of the option first, else the other one.
     * The converter of Apple's USB source (0x1e2f60) makes the output rate from the rate of the song. */
    if (a->clock && control(a->address, 0x21 | 0x01 << 8 | 0x0100 << 16, a->clock << 8 | 4 << 16, rate, 4) != 0) {
        rate = rate == 48000 ? 44100 : 48000;
        control(a->address, 0x21 | 0x01 << 8 | 0x0100 << 16, a->clock << 8 | 4 << 16, rate, 4);
    }
    /* Version 1.2: GET_CUR sampling frequency. Settings shows this rate. If the headphones do not
     * reply, Settings shows the rate that the patch sent. */
    reported = rate;
    if (a->clock && control_in(a->address, 0xa1 | 0x01 << 8 | 0x0100u << 16, a->clock << 8 | 4 << 16, 4) == 4)
        reported = CONTROL_IN[0] | CONTROL_IN[1] << 8 | CONTROL_IN[2] << 16 | CONTROL_IN[3] << 24;
    /* The volume on the device: SET_CUR volume (control 2) for channels 1 and 2 of the unit before the
     * output terminal (the EarPods: feature unit 2), in 1/256 dB, from the iPod volume (version 1.21;
     * versions 1.9-1.20 used a fixed -20 dB). The digital route of the iPod has no volume. */
    volume_start(a);
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
    hid_start(a);                                       /* the buttons (version 1.21) */
    next_frame = (frame_now() + 4) & (FRAMES - 1);
    music_start_us = USEC;
    music_checked = frame_now();
    music_used = 1;
    music_mode = 1;
    rate_used = reported;
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

/* ---- Version 1.24: the device task and the host mode ------------------------------------------------
 * The device task (0x170f2c) starts a device session (0x24d3c4 -> 0x220e0c: the device interrupt handler
 * and the endpoints) when USB power comes, and stops it (0x24d49c -> 0x220f34: a controller reset with
 * a wait without a limit) when the power goes away. In host mode both take the controller from the
 * host stack: then the UIM unlink 0xe8c20 waits forever, and the iPod freezes at a new connection.
 * While host_running is 1, the hooks do not call them. Before the host start, the probe ends the
 * session of the start with Apple's own stop. */

static void device_log(unsigned event, unsigned argument, unsigned ms)
{
    if (device_logs++ < 50)
        log_regs(TAG_DEVICE, event, argument, ms, OTGSC);
}

int hook_device_start(void *device, unsigned mode)
{
    if (host_running) {
        device_log(DEVICE_START_BLOCKED, mode, 0);
        return 1;                                       /* "the start failed": the task waits again */
    }
    device_log(DEVICE_START_ALLOWED, mode, 0);
    return fw_device_start(device, mode);
}

int hook_device_stop(void *device)
{
    device_stopped = 1;
    if (host_running) {
        device_log(DEVICE_STOP_SKIPPED, 0, 0);
        return 0;
    }
    device_log(DEVICE_STOP_DONE, 0, 0);
    return fw_device_stop(device);
}

/* Version 1.27: no USB host message while host mode runs. The dock has devices without a driver of
 * the probe (the card slot, the billboard): add device (0xd377c) then sends error 0x68c, and the UI
 * shows "unsupported device". At a reconnection that screen ended the playback. Three call sites:
 * 0xd399c (0xd377c), 0x10c204 and 0xe2be0; the code after each call only returns. */
int hook_usb_message(unsigned type, unsigned error)
{
    if (host_running) {
        device_log(DEVICE_MESSAGE_SKIPPED, type, error);
        return 0;
    }
    fw_usb_message(type, error);
    return 0;
}


/* ---- On and Off ------------------------------------------------------------------------------------ */

static unsigned mode_now(void)
{
    unsigned m = MODE_MANAGER;
    return m ? *(volatile unsigned char *)m : 0xff;
}

/* The settings of the host stack for USB audio, and the values of Apple (for Off). */
static void host_settings(int on)
{
    if (on) {
        USB_GLOBALS[0] = 2;
        if (COMPOSITE2_CLASS[0] == 2 && COMPOSITE2_CLASS[1] == 0) {
            COMPOSITE2_CLASS[0] = 0xef;
            COMPOSITE2_CLASS[1] = 2;
        }
        if (STORAGE_RECORD[0x12] == 8 && STORAGE_RECORD[0x35] == 8) {
            STORAGE_RECORD[0x12] = 0xff;
            STORAGE_RECORD[0x35] = 0xff;
        }
    } else {
        USB_GLOBALS[0] = 0;
        if (COMPOSITE2_CLASS[0] == 0xef && COMPOSITE2_CLASS[1] == 2) {
            COMPOSITE2_CLASS[0] = 2;
            COMPOSITE2_CLASS[1] = 0;
        }
        if (STORAGE_RECORD[0x12] == 0xff && STORAGE_RECORD[0x35] == 0xff) {
            STORAGE_RECORD[0x12] = 8;
            STORAGE_RECORD[0x35] = 8;
        }
    }
}

static void audio_start(void)
{
    void *manager = (void *)MODE_MANAGER;
    unsigned waited = 0;
    if (!manager)
        return;
    usb_memory();
    root_hub_address = 0xffffffff;                      /* a new host start can give new addresses */
    next_request = 0;
    for (waited = 0; waited < 4; waited++)
        device_requests[waited] = data_length[waited] = data_buffer[waited] = 0;
    waited = 0;
    audio_found = 0;
    if (mode_now() == 1) {                              /* Apple's end of the device session */
        device_stopped = 0;
        mode_deactivate(manager, 1);
        while (!device_stopped && waited < DEVICE_WAIT_MS && (OTGSC & 0x800)) {
            task_sleep(50);
            waited += 50;
        }
    }
    host_running = 1;
    audio_on = 1;
    host_settings(1);
    if (mode_activate(manager, 2) != 0)                 /* the host client: 0x1422c0, host start */
        host_start(0, 0, 0, 0);
    host_settings(1);                                   /* again: the host start clears parts of the block */
    music_wanted = 1;
}

static void audio_stop(void)
{
    void *manager = (void *)MODE_MANAGER;
    unsigned waited;
    /* The route stops in USBAudioTask at its next wait, between two sets of packets (as at a
     * disconnection; the song pauses). If the task does not run, stop here. */
    if (music_mode) {
        stop_request = 1;
        for (waited = 0; music_mode && waited < 500; waited += 20)
            task_sleep(20);
        if (music_mode)
            music_stop(3);
    }
    stop_request = 0;
    music_used = 0;                                     /* the USBAudioTask hooks call Apple's functions again */
    rate_used = 0;
    music_wanted = music_restart = 0;
    audio_found = 0;
    if (manager && mode_now() == 2)
        mode_deactivate(manager, 2);                    /* the host client: 0x142298, host stop */
    control_linked = 0;                                 /* the UIM memory of the asynchronous list is free */
    host_settings(0);
    host_running = 0;
    audio_on = 0;
    if (manager && mode_now() == 0 && usb_power())
        mode_activate(manager, 1);                      /* the device mode: a computer sees the iPod */
}

/* The task of the patch: it makes each change of the Settings item, and it starts the music route when
 * the headphones are enumerated. */
static unsigned task_handle, start_failures;

static void audio_task(int argc, char **argv)
{
    (void)argc;
    (void)argv;
    for (;;) {
        if (audio_wanted && !audio_on)
            audio_start();
        else if (!audio_wanted && audio_on)
            audio_stop();
        if (audio_on && audio_found && !music_mode && start_failures < 5) {
            music_start(&found);
            if (!music_mode) {
                start_failures++;
                task_sleep(1000);
            }
        }
        if (!audio_found)
            start_failures = 0;
        task_sleep(100);
    }
}

/* The USB mode task 0xb95a4 at a new USB power: "bleq 0x18482c" (manager, 2) at 0xb9614 stops the host
 * mode. The hook is unconditional; only the call with the manager and mode 2 is a real call. While
 * USB-C Audio is On, the host mode stays. The code after the call loads r0 again. */
int hook_mode_stop(void *manager, unsigned mode)
{
    if ((unsigned)manager != MODE_MANAGER || mode != 2)
        return 0;
    if (audio_on)
        return 0;
    return mode_deactivate(manager, mode);
}

/* ---- The Settings item "USB-C Audio" ---------------------------------------------------------------- */

static const char label[] = "USB-C Audio";
static const char on_44[] = "On (44.1 kHz)";
static const char on_48[] = "On (48 kHz)";
static const char main_off[] = "USB-C Audio: Off";
static const char main_on[] = "USB-C Audio: On";
static const char main_44[] = "USB-C Audio: 44.1 kHz";
static const char main_48[] = "USB-C Audio: 48 kHz";

/* The first instruction of the general lookup (0x21f254) is replaced by a branch. If no other patch
 * hooks the lookup, lookup_next is this function: it runs that instruction and continues in the firmware. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

void *hook_lookup(void *provider, unsigned type, int id)
{
    if (type == TAG_STR && id == LABEL_ID)
        return (void *)label;
    if (type == TAG_STR && id == ON_44_ID)
        return (void *)on_44;
    if (type == TAG_STR && id == ON_48_ID)
        return (void *)on_48;
    if (type == TAG_STR && id == MAIN_ITEM_ID)          /* the main menu item shows the state */
        return (void *)(!audio_wanted ? main_off : rate_used == 48000 ? main_48 : rate_used == 44100 ? main_44 : main_on);
    return lookup_next(provider, type, id);
}

int hook_settings_get(void *self, unsigned op, unsigned key, void *out)
{
    if (key == ITEM_KEY) {
        /* Version 1.2: while the music goes to the headphones, the value also shows the rate that
         * the headphones report. The text changes when the menu shows again. */
        short value = !audio_wanted ? STR_OFF : rate_used == 48000 ? ON_48_ID : rate_used == 44100 ? ON_44_ID : STR_ON;
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = value;
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = str_lookup(str_table(), value);
            return 1;
        }
        return 0;
    }
    if (key == ROW_KEY) {                               /* Settings > Main Menu > USB-C Audio */
        short value = main_menu_visible(self, MAIN_ITEM_ID) ? STR_ON : STR_OFF;
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = value;
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = str_lookup(str_table(), value);
            return 1;
        }
        key = SLEEP_LABEL;                              /* the other questions: as for the Sleep row */
    }
    return get_next(self, op, key, out);
}

/* ---- Version 1.3: the item in the main menu ---------------------------------------------------------- */

/* On or Off. The UI task does not wait: the task of the patch makes the change. */
static void audio_toggle(void)
{
    audio_wanted = !audio_wanted;
    if (!task_handle)
        task_handle = task_create("USBAudioOut", audio_task, "USBAudioOut", 0x20, 0x1000, 1, 3);
}

/* A selection in a menu list (vtable slot 0x6776f8, chain: album-artists also hooks it). list + 0x144
 * is the menu data (0 for other lists), the item + 0x10 its resource, and resource + 0x14 the label. */
int hook_activate(void *list, int row)
{
    void *data = *(void **)((char *)list + 0x144);
    void *item = data ? menu_item_at(data, row) : 0;
    const char *res = item ? *(const char **)((char *)item + 0x10) : 0;
    if (res && *(const short *)(res + 0x14) == MAIN_ITEM_ID) {
        audio_toggle();
        list_select(list, row, 0);                      /* the row again, with the new text */
        return 0;                                       /* not the Backlight action of the template */
    }
    return activate_next(list, row);
}

/* The replaced first instruction of 0x105a04 (label -> bit of the main menu mask). */
__attribute__((naked)) unsigned menu_bit_original(int label)
{
    __asm__ volatile("sub r0, r0, #0x5c00\n\tb menu_bit_continue\n");
}

/* The callers of 0x105a04 are the get (0x193470) and the set (0x19351c) of the main menu mask. */
unsigned hook_menu_bit(int label)
{
    return label == MAIN_ITEM_ID ? MAIN_MENU_BIT : menu_bit_next(label);
}

/* The replaced first instruction of 0x19ed58 (show or hide an item of a menu). */
__attribute__((naked)) int visible_original(void *screen, int menu, int label, int kind, int visible)
{
    __asm__ volatile("push {r2, r3, r4, lr}\n\tb visible_continue\n");
}

/* The UI script shows or hides each Apple item of the main menu. It does not know the copy, so the
 * patch does it for the copy when the script does it for Artists. */
int hook_set_visible(void *screen, int menu, int label, int kind, int visible)
{
    int result = visible_next(screen, menu, label, kind, visible);
    if (menu == MAIN_MENU_ID && label == ARTISTS_LABEL)
        visible_next(screen, menu, MAIN_ITEM_ID, kind, main_menu_visible(settings_object(), MAIN_ITEM_ID) != 0);
    return result;
}

/* A selection changes the value. The UI task does not wait: the task of the patch makes the change. */
int hook_settings_set(void *self, unsigned op, unsigned key, void *value)
{
    if (key == ITEM_KEY) {
        audio_toggle();
        (*(void (**)(void *, unsigned, unsigned))(*(char **)self + 0x54))(self, NOTIFY_BOOL, key);
        return 1;
    }
    if (key == ROW_KEY) {                               /* as the firmware does for its rows (0x192774) */
        set_main_menu_visible(self, MAIN_ITEM_ID, !main_menu_visible(self, MAIN_ITEM_ID));
        (*(void (**)(void *, unsigned, unsigned))(*(char **)self + 0x54))(self, NOTIFY_BOOL, key);
        return 1;
    }
    return set_next(self, op, key, value);
}

/* ---- The wrappers ------------------------------------------------------------------------------------ */

#define WRAP(name, tag, original)                       \
    __attribute__((naked)) void name(void)              \
    {                                                   \
        __asm__ volatile(                               \
            "push {r0-r3, lr}\n"                        \
            "mov  r1, sp\n"                             \
            "mov  r0, #" #tag "\n"                      \
            "bl   track_call\n"                         \
            "pop  {r0-r3, lr}\n"                        \
            "b    " #original "\n");                    \
    }

/* The completion callback 0xcb118 of the control transfers. A "b" hook replaces its first instruction
 * "stmdb sp!, {r1-r7, lr}". The wrapper calls track_call, runs that instruction and continues at
 * 0xcb11c. The UIM completion code 0xe01a0 calls it, possibly in the interrupt handler. */
__attribute__((naked)) void hook_completion(void)
{
    __asm__ volatile(
        "push {r0-r3, lr}\n"
        "mov  r1, sp\n"
        "mov  r0, #24\n"
        "bl   track_call\n"
        "pop  {r0-r3, lr}\n"
        "stmdb sp!, {r1-r7, lr}\n"
        "b    completion_continue\n");
}

WRAP(hook_uim_control_endpoint, 25, uim_control_endpoint)
WRAP(hook_uim_control_transfer, 26, uim_control_transfer)

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
