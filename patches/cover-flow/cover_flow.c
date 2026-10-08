/* Cover Flow for RetailOS 1.3 (iPod Video). Research: re/cover-flow.md.
 *
 * Hold Select in the Albums list to open Cover Flow. Turn the click wheel to move through the
 * covers. Push Select to open the album at the centre. Push Menu to close Cover Flow. Play
 * operates as usual. The background is white with the light theme and black with the dark theme.
 *
 * Hooks (all are words in vtables or in a literal pool):
 *  - 0x6772c0: slot +0x30 (event method) of the browse-list class 0x677290. The original method is
 *    0x23b704. The Albums list is the list with the element ID ALBUMS_LIST_ID. The firmware gives
 *    each button and wheel event to the focused list first (dispatcher 0x13d524).
 *  - 0x6701f0: the UI event handler 0x1d81cc. The hook only records its first argument (the UI
 *    object), because the idle function 0x1d813c needs it.
 *  - 0x17ef8c: the literal of the damage function 0x17ef98, which the display registers at the
 *    start (0x17eeb0). While Cover Flow shows, the hook ignores the damage of the firmware, so the
 *    firmware does not send its own drawings to the LCD.
 *
 * The firmware opens an album at the push of Select (event type 4). Thus the hook keeps the push of
 * Select in the Albums list. When the firmware reports the hold (type 6, after 0.5 s), Cover Flow
 * opens. If the release comes first, the hook sends a copy of the push through the dispatcher, and
 * the album opens as usual.
 *
 * The screen: the display server 0x1647c0 has the layer at +0x6c4. The layer has the CPU
 * framebuffer (RGB565) at +4 and the BCM surface at +0xc (stride at surface +0x10). Cover Flow keeps
 * a copy of the framebuffer, draws into it, marks the screen as damaged (0x17ef98) and sends it with
 * the flush 0x1650f8(server, layer index). On close it puts the copy back and sends it again.
 *
 * Cover file iPod_Control\iTunes\iPodFirmCoverFlow (written by iPodFirm), little-endian:
 *   0x00 "IFCF"
 *   0x04 u16 version (1), u16 cover size S (pixels, square)
 *   0x08 u32 album count N, in the order of the Albums list (without "All")
 *   0x0C u32 stamp: FNV-1a hash of all the bytes after the header
 *   0x10 u16 caption width CW, u16 caption height CH
 *   0x14 u32 record size
 *   0x18 u32 offset of the first record
 *   0x1C u32 0
 *   0x20 N x u32: FNV-1a hash of the UTF-8 album name
 *   then N records: S*S RGB565 pixels (row by row), then CW*CH 4-bit grey levels of the caption
 *         (two pixels in each byte, the left pixel in the high bits)
 */

typedef struct { int top, left, bottom, right; } Rect;

/* Firmware functions (addresses are in patch.json). */
int list_event(int *list, int *ev, void *a3, int a4);
int ui_event(void *ui, int *ev);
int display_damage(void *unused, Rect *r, int zero);
void *display_server(void);
int display_flush(void *server, int layer);
int display_bind(void *server, int layer);
void display_lock(void *mutex);
void display_unlock(void *mutex);
void view_invalidate(void *view);
void *ui_context(void);
int dispatch_event(int *ev, void *target);
void ui_activity(void *ui, int button);
void *fw_alloc(unsigned size);
void fw_free(void *p);
void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);

#define FILE_PATH      "iPod_Control\\iTunes\\iPodFirmCoverFlow"
#define MODE_DATA      0x64617461u        /* 'data' */
#define USEC_TIMER     (*(volatile unsigned *)0x60005010)
#define LAYER_INDEX    (*(int *)0x1081e0d4)   /* the layer of the display (literal 0x17f00c) */

#define VIEW_FLAGS     8                  /* word index: bits 0x1800 = 0x800 if the view is visible */
#define VIEW_ELEMENT_ID 0x1c              /* u16: the layout element of a view */
#define VIEW_PARENT    0x10
#define CONTEXT_FOCUS  0x28               /* ui_context() + 0x28: the focused object (0x13d524) */
#define ALBUMS_LIST_ID 0x6382             /* the list of the Albums screen (Artists: 0x6387) */
#define LIST_SELECTION 0x29               /* word index: object with the selected row at +0x14 */
#define LIST_COUNT     0x2e               /* word index: the number of rows */
#define LIST_SET_SELECTION 0x138          /* vtable slot: set the selected row (0x23a04c) */
#define SERVER_LAYERS  0x110              /* the layers of the server (0x164610) */
#define LAYER_SIZE     0x90
#define LAYER_COUNT    11
#define SERVER_LOCK    0x6c8
#define SERVER_DIRTY   0x6be              /* the update of 0x164f44: 1 = send rows top to bottom */
#define SERVER_DIRTY_TOP 0x6c0
#define SERVER_DIRTY_BOTTOM 0x6c2
#define LAYER_FB       4
#define LAYER_SURFACE  0xc
#define SURFACE_STRIDE 0x10

#define EV_KEY_DOWN    4
#define EV_KEY_REPEAT  5
#define EV_KEY_HOLD    6                  /* the key is held for 0.5 s */
#define EV_KEY_UP      7
#define EV_WHEEL       0xf                /* word 3: +1 or -1 for each step, 0 at the end */
#define KEY_OF(ev)     (((unsigned)(ev)[4] >> 16) & 0xff)
#define KEY_PLAY       0x10
#define KEY_MENU       0x6e
#define KEY_SELECT     0x6f
#define EVENT_WORDS    5                  /* an event has 20 bytes: vtable, type, 3 words */
#define UI_KEYS_DOWN   0x44               /* byte in the UI object: keys down (0x1d81cc) */

#define HOLD_US        700000             /* if no hold event (type 6) comes: a push this long opens Cover Flow */
#define W              320
#define H              240
#define MAX_SIZE       160                /* largest cover size in the file */
#define MAX_COUNT      100000
#define CACHE_SLOTS    11
#define SIDE           4                  /* covers at each side of the centre */
#define FRAMES         4                  /* frames for each step of the wheel */
#define FAST_US        80000              /* a step sooner than this after the last one: 1 frame */
#define QUICK_US       200000             /* a step sooner than this after the last one: 2 frames */
#define CENTER_Y       100                /* the middle line of the covers */
#define REFLECT_END    204                /* the reflections end above the caption */
#define CAPTION_Y      206

/* ---------- state ---------- */

static int active;                        /* 1 while Cover Flow shows */
static int *cf_list;                      /* the Albums list of Cover Flow */
static void *ui_object;                   /* the first argument of 0x1d81cc */
static int pending;                       /* 1: a push of Select is kept */
static int *pending_list;                 /* the list that got the kept push */
static unsigned push_time;
static int swallow_key = -1;              /* the events after the push of this key do not go to the firmware */
static int sending;                       /* 1 while send_copy sends a copy through the dispatcher */

static unsigned short *fb;                /* the framebuffer of the firmware */
static unsigned short *saved;             /* the copy of the framebuffer */
static unsigned short *pixels;            /* CACHE_SLOTS covers */
static unsigned char *caption;
static int cache_index[CACHE_SLOTS];
static unsigned fh[0x30 / 4];             /* the open cover file */
static unsigned count, size, cap_w, cap_h, record_size, first_record;
static int caption_index = -1;
static int light;                         /* 1: the firmware shows the light theme (white background) */
static int rows_match;                    /* 1: the list has "All" and the albums of the file */
static int pos;                           /* the position, in 1/256 of a cover */
static int target;                        /* the album at the centre after the movement */
static unsigned recip[MAX_SIZE * 2];      /* (size << 16) / h */
static unsigned short grey[16];

/* ---------- helpers ---------- */

/* The compiler calls a library function for "/" with a variable. There is no library. */
static unsigned udiv(unsigned n, unsigned d)
{
    unsigned q = 0, bit = 1;
    if (d == 0)
        return 0;
    while (d < n && !(d & 0x80000000u)) {
        d <<= 1;
        bit <<= 1;
    }
    while (bit) {
        if (n >= d) {
            n -= d;
            q |= bit;
        }
        d >>= 1;
        bit >>= 1;
    }
    return q;
}

static int sdiv(int n, int d)
{
    int neg = (n < 0) != (d < 0);
    unsigned q = udiv(n < 0 ? -n : n, d < 0 ? -d : d);
    return neg ? -(int)q : (int)q;
}

static int read_at(unsigned offset, void *buf, unsigned len)
{
    unsigned got = len;
    if (file_seek(fh, 0, offset) != 0 || file_read(fh, &got, buf) != 0)
        return -1;
    return got == len ? 0 : -1;
}

/* ---------- the screen ---------- */

/* The same steps as 0x169718. Do not call the damage function 0x17ef98 here: if the flag at
   0x1081ec54 is set, it binds the layer again and waits for the end of this update. */
static void send_screen(void)
{
    char *server = display_server();
    display_bind(server, LAYER_INDEX);    /* waits for the end of the last update */
    display_lock(server + SERVER_LOCK);
    server[SERVER_DIRTY] = 1;
    *(unsigned short *)(server + SERVER_DIRTY_TOP) = 0;
    *(unsigned short *)(server + SERVER_DIRTY_BOTTOM) = H;
    display_unlock(server + SERVER_LOCK);
    display_flush(server, LAYER_INDEX);
}

static void clear(void)
{
    unsigned *p = (unsigned *)fb, bg = light ? 0xffffffffu : 0;
    int i;
    for (i = 0; i < W * H / 2; i++)
        p[i] = bg;
}

/* The theme of the firmware, from the copy of its screen: the left margin of the list rows (x = 2,
   below the title bar). Most of these pixels have the list background; one row has the highlight. */
static int is_light(const unsigned short *screen)
{
    int y, bright = 0, all = 0;
    for (y = 40; y < H; y += 8, all++)
        if (((screen[y * W + 2] >> 5) & 63) >= 32)
            bright++;
    return bright * 2 > all;
}

static unsigned short dim(unsigned short c, int level)
{
    if (level == 0)
        return (c >> 2) & 0x39e7;         /* 1/4 */
    if (level == 1)
        return (c >> 3) & 0x18e3;         /* 1/8 */
    return (c >> 4) & 0x0861;             /* 1/16 */
}

/* The geometry of a cover: the left and the right screen columns, and the heights at the edges. */
typedef struct { int x0, x1, h0, h1; } Place;

/* A cover at `k` covers right of the centre (k >= 0, in 1/256). The outer edge of a side cover is
 * nearer to the viewer, thus it is higher than the inner edge. */
static void place_right(int k, Place *p)
{
    static const short x0[] = { 96, 232, 262, 292, 322, 352 };
    static const short x1[] = { 224, 284, 314, 344, 374, 404 };
    static const short h0[] = { 128, 96, 96, 96, 96, 96 };
    static const short h1[] = { 128, 120, 120, 120, 120, 120 };
    int i = k >> 8, f = k & 255;
    if (i >= 5) {
        i = 4;
        f = 256;
    }
    p->x0 = x0[i] + (((x0[i + 1] - x0[i]) * f) >> 8);
    p->x1 = x1[i] + (((x1[i + 1] - x1[i]) * f) >> 8);
    p->h0 = h0[i] + (((h0[i + 1] - h0[i]) * f) >> 8);
    p->h1 = h1[i] + (((h1[i + 1] - h1[i]) * f) >> 8);
}

static void place(int d, Place *p)
{
    Place q;
    if (d >= 0) {
        place_right(d, p);
        return;
    }
    place_right(-d, &q);                  /* the mirror image */
    p->x0 = W - q.x1;
    p->x1 = W - q.x0;
    p->h0 = q.h1;
    p->h1 = q.h0;
}

static void draw_cover(const unsigned short *tex, const Place *p, int side)
{
    int w = p->x1 - p->x0, c, end;
    int ustep, hstep, u, h;
    if (w <= 0)
        return;
    ustep = (int)udiv(size << 16, w);
    hstep = sdiv((p->h1 - p->h0) << 16, w);
    c = p->x0 < 0 ? 0 : p->x0;
    end = p->x1 > W ? W : p->x1;
    u = (c - p->x0) * ustep;
    h = (p->h0 << 16) + (c - p->x0) * hstep;
    for (; c < end; c++, u += ustep, h += hstep) {
        int hh = h >> 16, top = CENTER_Y - hh / 2, y, v = 0, vstep, rl, b1, b2;
        const unsigned short *col = tex + (u >> 16);
        unsigned short *out;
        if (hh <= 0 || hh >= MAX_SIZE * 2 || top < 0)
            continue;
        vstep = (int)recip[hh];
        out = fb + top * W + c;
        for (y = 0; y < hh; y++, v += vstep, out += W) {
            unsigned short px = col[(v >> 16) * size];
            if (side)                     /* a side cover is a little darker */
                px = ((px >> 1) & 0x7bef) + ((px >> 2) & 0x39e7);
            *out = px;
        }
        /* The reflection: the cover upside down, darker at each third. */
        rl = hh * 3 / 8;
        if (top + hh + rl > REFLECT_END)
            rl = REFLECT_END - top - hh;
        b1 = rl / 3;
        b2 = rl * 2 / 3;
        v = (hh - 1) * vstep;
        for (y = 0; y < rl; y++, v -= vstep, out += W) {
            int level = y < b1 ? 0 : y < b2 ? 1 : 2;
            unsigned short px = col[(v >> 16) * size];
            /* On white, the reflection fades to white: the same as a fade of the inverse to black. */
            *out = light ? (unsigned short)~dim((unsigned short)~px, level) : dim(px, level);
        }
    }
}

static const unsigned short *cover(int i)
{
    int s, far = -1, far_d = -1;
    for (s = 0; s < CACHE_SLOTS; s++)
        if (cache_index[s] == i)
            return pixels + s * size * size;
    for (s = 0; s < CACHE_SLOTS; s++) {   /* replace the cover that is farthest from the target */
        int d = cache_index[s] < 0 ? 0x7fffffff : cache_index[s] - target;
        if (d < 0)
            d = -d;
        if (d > far_d) {
            far_d = d;
            far = s;
        }
    }
    cache_index[far] = -1;
    if (read_at(first_record + i * record_size, pixels + far * size * size, size * size * 2) != 0)
        return 0;
    cache_index[far] = i;
    return pixels + far * size * size;
}

static void draw_caption(int i)
{
    unsigned x, y, x0 = (W - cap_w) / 2;
    if (i != caption_index) {
        caption_index = -1;
        if (read_at(first_record + i * record_size + size * size * 2, caption, cap_w * cap_h / 2) != 0)
            return;
        caption_index = i;
    }
    for (y = 0; y < cap_h && CAPTION_Y + y < H; y++) {
        const unsigned char *row = caption + y * (cap_w / 2);
        unsigned short *out = fb + (CAPTION_Y + y) * W + x0;
        for (x = 0; x < cap_w; x += 2) {
            unsigned b = row[x / 2];
            /* The caption is light text for a black background. On white, use the inverse. */
            if (b >> 4)
                out[x] = light ? (unsigned short)~grey[b >> 4] : grey[b >> 4];
            if (b & 15)
                out[x + 1] = light ? (unsigned short)~grey[b & 15] : grey[b & 15];
        }
    }
}

static void render(void)
{
    int center = (pos + 128) >> 8, k, i;
    clear();
    /* the farthest covers first, the centre cover last */
    for (k = SIDE; k >= 0; k--) {
        for (i = center - k; i <= center + k; i += (k ? 2 * k : 1)) {
            const unsigned short *tex;
            Place p;
            int d = i * 256 - pos;
            if (i < 0 || i >= (int)count || d > (SIDE + 1) * 256 || d < -(SIDE + 1) * 256)
                continue;
            tex = cover(i);
            if (!tex)
                continue;
            place(d, &p);
            draw_cover(tex, &p, d > 128 || d < -128);
        }
    }
    draw_caption(center);
    send_screen();
}

/* ---------- open and close ---------- */

static void release(void)
{
    fw_free(saved);
    fw_free(pixels);
    fw_free(caption);
    saved = 0;
    pixels = 0;
    caption = 0;
    active = 0;
    cf_list = 0;
}

/* Returns 1 if Cover Flow shows. */
static int open_cover_flow(int *list)
{
    unsigned path[0x108 / 4];
    unsigned header[8], i, rows, sel;
    int *layer;
    void *server = display_server();

    if ((unsigned)LAYER_INDEX >= LAYER_COUNT)
        return 0;
    layer = (int *)((char *)server + SERVER_LAYERS + LAYER_INDEX * LAYER_SIZE);
    if (*(char *)layer != 1 || !*(char **)((char *)layer + LAYER_SURFACE) ||
        *(int *)(*(char **)((char *)layer + LAYER_SURFACE) + SURFACE_STRIDE) != W * 2)
        return 0;
    fb = *(unsigned short **)((char *)layer + LAYER_FB);
    fw_memset0(path, sizeof path);
    fw_memset0(fh, sizeof fh);
    fw_strcpy((char *)path + 4, FILE_PATH);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return 0;
    if (read_at(0, header, sizeof header) != 0 || header[0] != 0x46434649u ||   /* "IFCF" */
        (header[1] & 0xffff) != 1)
        goto fail;
    size = header[1] >> 16;
    count = header[2];
    cap_w = header[4] & 0xffff;
    cap_h = header[4] >> 16;
    record_size = header[5];
    first_record = header[6];
    if (size == 0 || size > MAX_SIZE || count == 0 || count > MAX_COUNT || cap_w > W || (cap_w & 1) ||
        cap_h > H - CAPTION_Y || record_size < size * size * 2 + cap_w * cap_h / 2)
        goto fail;
    saved = fw_alloc(W * H * 2);
    pixels = fw_alloc(CACHE_SLOTS * size * size * 2);
    caption = fw_alloc(cap_w * cap_h / 2 + 4);
    if (!saved || !pixels || !caption) {
        release();
        goto fail;
    }
    for (i = 0; i < W * H / 2; i++)
        ((unsigned *)saved)[i] = ((unsigned *)fb)[i];
    light = is_light(saved);
    for (i = 1; i < MAX_SIZE * 2; i++)
        recip[i] = udiv(size << 16, i);
    for (i = 0; i < 16; i++) {
        unsigned r = i * 2 + (i >> 3), g = i * 4 + (i >> 2);
        grey[i] = (unsigned short)(r << 11 | g << 5 | r);
    }
    for (i = 0; i < CACHE_SLOTS; i++)
        cache_index[i] = -1;
    caption_index = -1;
    /* Start at the selected row. Row 0 is "All". If the list has other albums than the file
       (for example the albums of one artist), start at the first album. */
    rows = (unsigned)list[LIST_COUNT];
    sel = *(unsigned *)((char *)list[LIST_SELECTION] + 0x14);
    rows_match = rows == count + 1;
    target = (rows_match && sel >= 1 && sel <= count) ? (int)sel - 1 : 0;
    pos = target * 256;
    cf_list = list;
    active = 1;
    render();
    return 1;
fail:
    file_close(fh);
    return 0;
}

/* Puts the screen of the firmware back. `send`: send it to the LCD now. In the damage hook the
   firmware sends it itself. */
static void close_cover_flow(int send)
{
    unsigned i;
    int *view = cf_list;
    if (!active)
        return;
    for (i = 0; i < W * H / 2; i++)
        ((unsigned *)fb)[i] = ((unsigned *)saved)[i];
    file_close(fh);
    release();
    if (send)
        send_screen();
    /* The firmware can change its views while Cover Flow shows. Thus it draws the top view of the
       list again. A view that is not visible does not change. */
    while (*(int **)((char *)view + VIEW_PARENT))
        view = *(int **)((char *)view + VIEW_PARENT);
    view_invalidate(view);
}

static unsigned last_step;

static void step(int dir)
{
    int start = pos, f, frames = FRAMES;
    unsigned dt = USEC_TIMER - last_step;
    last_step = USEC_TIMER;
    if (dt < FAST_US)                     /* a fast turn of the wheel: do not lag behind it */
        frames = 1;
    else if (dt < QUICK_US)
        frames = 2;
    target += dir;
    if (target < 0)
        target = 0;
    if (target >= (int)count)
        target = count - 1;
    for (f = 1; f <= frames; f++) {
        pos = start + sdiv((target * 256 - start) * f, frames);
        render();
    }
}

/* ---------- the copy of a push of Select ---------- */

static void ev_keep(int *ev)
{
    (void)ev;                             /* the dispatcher deletes an event with slot +4 */
}

/* A copy of the vtable of the key event (0x676974), with a slot +4 that does not delete. */
static void *copy_vtable[6];
static int copy_event[EVENT_WORDS];
static int kept[EVENT_WORDS];             /* the kept push of Select */

static void send_copy(int *ev, int type)
{
    int i;
    void **vt = *(void ***)ev;
    for (i = 0; i < 6; i++)
        copy_vtable[i] = vt[i];
    copy_vtable[1] = (void *)ev_keep;
    for (i = 0; i < EVENT_WORDS; i++)
        copy_event[i] = ev[i];
    copy_event[0] = (int)copy_vtable;
    copy_event[1] = type;
    sending = 1;
    dispatch_event(copy_event, 0);
    sending = 0;
}

/* ---------- hooks ---------- */


static int is_albums_list(int *list)
{
    return *(unsigned short *)((char *)list + VIEW_ELEMENT_ID) == ALBUMS_LIST_ID &&
           (list[VIEW_FLAGS] & 0x1800) == 0x800;
}

static int active_event(int *list, int *ev, void *a3, int a4)
{
    int type = ev[1];
    if (type == EV_WHEEL) {
        if (ui_object)
            ui_activity(ui_object, 0);
        if (ev[3] > 0)
            step(1);
        else if (ev[3] < 0)
            step(-1);
        return 1;
    }
    if (type >= EV_KEY_DOWN && type <= EV_KEY_UP) {
        int key = KEY_OF(ev);
        if (key == KEY_PLAY)
            return list_event(list, ev, a3, a4);
        if (type == EV_KEY_DOWN && key == KEY_SELECT && rows_match) {
            /* Select the row of the centre album in the list (its own method, the same as the
               wheel), close Cover Flow, and give the push to the firmware: it opens the album. */
            int row = target + 1;         /* row 0 is "All" */
            ((void (*)(int *, int))(*(void ***)list)[LIST_SET_SELECTION / 4])(list, row);
            close_cover_flow(1);
            return list_event(list, ev, a3, a4);
        }
        if (type == EV_KEY_DOWN && key == KEY_MENU) {
            close_cover_flow(1);
            swallow_key = KEY_MENU;
        }
        return 1;
    }
    return list_event(list, ev, a3, a4);
}

/* Replaces the event method of the browse-list class (slot +0x30, at 0x6772c0). The list gets the
 * push of a key (type 4) and the wheel. It does not get the release: refer to hook_ui_event. */
int hook_list_event(int *list, int *ev, void *a3, int a4)
{
    int type = ev[1];

    if (sending)
        return list_event(list, ev, a3, a4);
    if (active)
        return list == cf_list ? active_event(list, ev, a3, a4) : list_event(list, ev, a3, a4);
    if (pending && list == pending_list && USEC_TIMER - push_time >= HOLD_US) {
        /* The list gets timer events (type 9) while the button is held. */
        pending = 0;
        if (open_cover_flow(list)) {
            swallow_key = KEY_SELECT;
            return type >= EV_KEY_DOWN && type <= EV_KEY_UP ? 1 : list_event(list, ev, a3, a4);
        }
        send_copy(kept, EV_KEY_DOWN);     /* no cover file: do as the firmware does */
    }
    if (type == EV_KEY_DOWN && KEY_OF(ev) == KEY_SELECT && is_albums_list(list)) {
        int i;
        for (i = 0; i < EVENT_WORDS; i++)
            kept[i] = ev[i];
        pending = 1;
        pending_list = list;
        push_time = USEC_TIMER;
        return 1;
    }
    return list_event(list, ev, a3, a4);
}

/* The release of a key in the UI handler: the same as 0x1d820c. */
static void key_released(void *ui)
{
    unsigned char *keys_down = (unsigned char *)ui + UI_KEYS_DOWN;
    if (*keys_down)
        (*keys_down)--;
}

/* Replaces the UI event handler 0x1d81cc (slot at 0x6701f0). The UI handler gets each key event
 * before the list, and it gets the events after the push (types 5, 6 and 7) alone. The firmware
 * acts on Menu at type 6 or 7 here. */
int hook_ui_event(void *ui, int *ev)
{
    int type = ev[1], key;

    ui_object = ui;
    if (type < EV_KEY_DOWN || type > EV_KEY_UP)
        return ui_event(ui, ev);
    key = KEY_OF(ev);
    if (sending)                          /* this handler had the original push */
        return type == EV_KEY_DOWN ? 0 : ui_event(ui, ev);
    if (key == swallow_key && type != EV_KEY_DOWN) {   /* the rest of a push that Cover Flow used */
        if (type == EV_KEY_UP) {
            swallow_key = -1;
            key_released(ui);
        }
        return 1;
    }
    if (pending && key == KEY_SELECT && type == EV_KEY_HOLD) {
        /* The firmware sends type 6 when a key is held for 0.5 s. */
        pending = 0;
        if (open_cover_flow(pending_list)) {
            swallow_key = KEY_SELECT;
            return 1;
        }
        send_copy(kept, EV_KEY_DOWN);     /* no cover file: do as the firmware does */
        return ui_event(ui, ev);
    }
    if (pending && key == KEY_SELECT && type != EV_KEY_DOWN) {
        if (type != EV_KEY_UP)
            return 1;                     /* keep the repeats */
        pending = 0;
        if (USEC_TIMER - push_time >= HOLD_US && open_cover_flow(pending_list)) {
            key_released(ui);
            return 1;
        }
        send_copy(kept, EV_KEY_DOWN);     /* a short push: the album opens as usual */
        return ui_event(ui, ev);
    }
    return ui_event(ui, ev);
}

/* Replaces the damage function 0x17ef98 (literal at 0x17ef8c). */
int hook_display_damage(void *unused, Rect *r, int zero)
{
    if (active) {
        char *context = ui_context();
        if ((cf_list[VIEW_FLAGS] & 0x1800) == 0x800 && context && *(int **)(context + CONTEXT_FOCUS) == cf_list)
            return 1;                     /* Cover Flow shows: ignore the drawings of the firmware */
        close_cover_flow(0);              /* the firmware shows a new screen or a message */
    }
    return display_damage(unused, r, zero);
}
