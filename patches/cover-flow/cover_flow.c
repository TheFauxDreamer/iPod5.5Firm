/* Cover Flow for RetailOS 1.3 (iPod Video). Research: re/cover-flow.md.
 *
 * Hold Select in the Albums list to open Cover Flow. Turn the click wheel to move through the
 * covers, with the click of the lists. Push Select to open the album at the centre. Push Menu to close Cover Flow. Play
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
 * The covers come from the iPod itself, without a file of iPodFirm:
 *  - The albums: the album list of the library (library + 0xc60: album pool indexes, count at
 *    + 0xc6c). This is the Albums list without "All", in its order. The patch finds the tracks of
 *    each album with a hash of the album name (album pool db + 0x138).
 *  - The artwork: iPod_Control\Artwork\ArtworkDB links each image (mhii) to the dbid of a track
 *    (track + 0x108). The patch reads the 100 x 100 image (format 1028, RGB565) from F1028_N.ithmb.
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
void ui_click(void);
int dispatch_event(int *ev, void *target);
void ui_activity(void *ui, int button);
void *lib_resolve(void *ref);
void label_draw(void *view, const char *text, void *a3);
int pool_copy(void *pool, int index, void *buffer, int *length, int maximum);
void *fw_alloc(unsigned size);
void fw_free(void *p);
void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);

#define ART_DB_PATH    "iPod_Control\\Artwork\\ArtworkDB"
#define ITHMB_PATH     "iPod_Control\\Artwork\\F1028_"     /* + N + ".ithmb" */
#define ART_FORMAT     1028               /* 100 x 100 RGB565 */
#define ART_SIZE       100
#define PROVIDER       (*(char **)0x1081da18) /* the main provider of the music screens */
#define PROVIDER_LIBRARY 0x1c
#define LIBRARY_TRACKS 0xcf0              /* the list of all tracks */
#define LIBRARY_DB     0xcf8              /* the music database */
#define LIBRARY_ALBUMS 0xc60              /* the album list: album pool indexes, in the order of the list */
#define LIBRARY_ALBUM_COUNT 0xc6c
#define DB_TRACK_COUNT 0x1c
#define DB_TRACKS      0x20               /* the first track */
#define TRACK_NEXT     4
#define DB_ALBUM_POOL  0x138
#define DB_ARTIST_POOL 0xe0
#define TRACK_ARTIST   0x2c
#define TRACK_ALBUM    0x34
#define TRACK_DBID     0x108
#define NAME_MAX       96                 /* bytes of UTF-16 that the patch compares */
#define TEXT_MAX       160                /* bytes of UTF-16 in a caption line */
#define CELL_ID_ALBUM  0x6421             /* the album label of a row of the Albums list */
#define LIST_CELL      0x2a               /* word index: the template cell of a list */
#define VIEW_CHILD_COUNT 0x7c
#define VIEW_CHILDREN  0x80
#define VIEW_RECT      0x58               /* top, left, bottom, right in the parent */
#define LABEL_STATE    0x1b8              /* byte that 0x244924 writes */

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
#define MAX_SIZE       160                /* largest cover height on the screen / 2 */
#define CACHE_SLOTS    11
#define SIDE           4                  /* covers at each side of the centre */
#define FRAMES         4                  /* frames for each step of the wheel */
#define FAST_US        80000              /* a step sooner than this after the last one: 1 frame */
#define QUICK_US       200000             /* a step sooner than this after the last one: 2 frames */
#define CENTER_Y       100                /* the middle line of the covers */
#define REFLECT_END    198                /* the reflections end above the caption */
#define ALBUM_TOP      198                /* the album line: 198-220, the artist line: 220-240 */
#define ARTIST_TOP     220

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
static unsigned short *placeholder;       /* the cover of an album without artwork */
static int cache_index[CACHE_SLOTS];
static unsigned count, size = ART_SIZE;

/* The albums. They stay in memory while the database does not change. */
static int **album_track;                 /* the first track of each album */
static unsigned *art_offset;              /* the offset in F1028_N.ithmb, or 0xffffffff */
static unsigned char *art_file;           /* N */
static int *built_list;
static unsigned built_tracks;
static char *album_db;                    /* the database of the table */
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

static int open_path(unsigned *fh, const char *path, int number)
{
    unsigned record[0x108 / 4];
    char *p = (char *)record + 4;
    fw_memset0(record, sizeof record);
    fw_memset0(fh, 0x30);
    fw_strcpy(p, path);
    if (number) {                         /* add N and ".ithmb" */
        while (*p)
            p++;
        if (number >= 10)
            *p++ = (char)('0' + udiv(number, 10));
        *p++ = (char)('0' + number - 10 * udiv(number, 10));
        fw_strcpy(p, ".ithmb");
    }
    return file_open(record, fh, 0, MODE_DATA);
}

static int read_at(unsigned *fh, unsigned offset, void *buf, unsigned len)
{
    unsigned got = len;
    if (file_seek(fh, 0, offset) != 0 || file_read(fh, &got, buf) != 0)
        return -1;
    return got == len ? 0 : -1;
}

/* ---------- the albums and their artwork ---------- */

static void free_albums(void)
{
    fw_free(album_track);
    fw_free(art_offset);
    fw_free(art_file);
    album_track = 0;
    art_offset = 0;
    art_file = 0;
    count = 0;
    built_list = 0;
}

static unsigned get32(const unsigned char *b)
{
    return b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
}

#define TAG(a, b, c, d) ((unsigned)(a) | (unsigned)(b) << 8 | (unsigned)(c) << 16 | (unsigned)(d) << 24)

/* The tracks sorted by dbid, with the row of their album (only while the table is made). */
typedef struct { unsigned lo, hi, row; } TrackKey;
static TrackKey *keys;
static unsigned key_count;

static int album_of(unsigned lo, unsigned hi)
{
    unsigned a = 0, b = key_count;
    while (a < b) {
        unsigned m = (a + b) >> 1;
        if (keys[m].hi < hi || (keys[m].hi == hi && keys[m].lo < lo))
            a = m + 1;
        else
            b = m;
    }
    return (a < key_count && keys[a].lo == lo && keys[a].hi == hi) ? (int)keys[a].row : -1;
}

/* Reads ArtworkDB and keeps the offset of the 100 x 100 image of each album. The file has
 * mhfd { mhsd (type 1) { mhli { mhii { mhod (type 2) { mhni { mhod (type 3: file name) } } } } } }. */
/* A read window over ArtworkDB: the parser makes many small reads; the window makes a few large
 * reads of the file. */
#define WINDOW 32768
static unsigned char *window;
static unsigned window_pos, window_len;

static int db_read(unsigned *fh, unsigned pos, void *dst, unsigned len)
{
    unsigned k;
    if (pos < window_pos || pos + len > window_pos + window_len) {
        unsigned got = WINDOW;
        window_pos = pos;
        window_len = 0;
        if (file_seek(fh, 0, pos) != 0 || file_read(fh, &got, window) != 0)
            return -1;                    /* a short read at the end of the file is correct */
        window_len = got;
        if (len > window_len)
            return -1;
    }
    for (k = 0; k < len; k++)
        ((unsigned char *)dst)[k] = window[pos - window_pos + k];
    return 0;
}

static void find_artwork(void)
{
    unsigned fh[0x30 / 4];
    unsigned char h[0x30];
    unsigned pos, end;
    if (key_count == 0 || !(window = fw_alloc(WINDOW)))
        return;
    window_len = 0;
    if (open_path(fh, ART_DB_PATH, 0) != 0) {
        fw_free(window);
        return;
    }
    if (db_read(fh, 0, h, 12) != 0 || get32(h) != TAG('m', 'h', 'f', 'd'))
        goto done;
    pos = get32(h + 4);
    end = get32(h + 8);
    while (pos + 16 <= end) {                     /* the mhsd sections */
        unsigned slen, p, items, k;
        if (db_read(fh, pos, h, 16) != 0 || get32(h) != TAG('m', 'h', 's', 'd'))
            break;
        slen = get32(h + 8);
        if (slen == 0)
            break;
        if ((get32(h + 12) & 0xffff) == 1) {      /* the image list */
            p = pos + get32(h + 4);
            if (db_read(fh, p, h, 12) != 0 || get32(h) != TAG('m', 'h', 'l', 'i'))
                break;
            items = get32(h + 8);
            p += get32(h + 4);
            for (k = 0; k < items; k++) {
                unsigned ilen, children, q, c;
                int album;
                if (db_read(fh, p, h, 0x1c) != 0 || get32(h) != TAG('m', 'h', 'i', 'i'))
                    break;
                ilen = get32(h + 8);
                children = get32(h + 12);
                album = album_of(get32(h + 0x14), get32(h + 0x18));
                if (album >= 0 && art_offset[album] != 0xffffffffu)
                    album = -1;                   /* the album has a cover already */
                q = p + get32(h + 4);
                for (c = 0; album >= 0 && c < children; c++) {
                    unsigned mlen, ni;
                    if (db_read(fh, q, h, 0x18) != 0 || get32(h) != TAG('m', 'h', 'o', 'd'))
                        break;
                    mlen = get32(h + 8);
                    ni = q + get32(h + 4);
                    if ((get32(h + 12) & 0xffff) == 2 && db_read(fh, ni, h, 0x24) == 0 &&
                        get32(h) == TAG('m', 'h', 'n', 'i') && get32(h + 0x10) == ART_FORMAT &&
                        get32(h + 0x18) == ART_SIZE * ART_SIZE * 2) {
                        unsigned offset = get32(h + 0x14), name = ni + get32(h + 4);
                        int number = 1;
                        /* the file name ":F1028_N.ithmb" (UTF-16): the digits after '_' */
                        if (db_read(fh, name, h, 0x24 + 2 * 12) == 0 && get32(h) == TAG('m', 'h', 'o', 'd')) {
                            int x, d = 0, seen = 0;
                            for (x = 0x24; x < 0x24 + 2 * 12; x += 2) {
                                if (h[x] == '_')
                                    seen = 1;
                                else if (seen && h[x] >= '0' && h[x] <= '9')
                                    d = d * 10 + h[x] - '0';
                                else if (seen)
                                    break;
                            }
                            if (d > 0 && d < 100)
                                number = d;
                        }
                        art_offset[album] = offset;
                        art_file[album] = (unsigned char)number;
                        break;
                    }
                    if (mlen == 0)
                        break;
                    q += mlen;
                }
                if (ilen == 0)
                    break;
                p += ilen;
            }
        }
        pos += slen;
    }
done:
    file_close(fh);
    fw_free(window);
    window = 0;
}

static unsigned name_hash(char *db, int index)
{
    unsigned short name[NAME_MAX / 2];
    unsigned h = 2166136261u;
    int length = 0, k;
    pool_copy(db + DB_ALBUM_POOL, index, name, &length, sizeof name);
    if (length <= 0)
        return 0;
    for (k = 0; k < length; k++) {
        h ^= ((unsigned char *)name)[k];
        h *= 16777619u;
    }
    return h;
}

/* Makes the album table from the album list of the library (the rows of the Albums list without
 * "All"). Returns the album count. */
static unsigned build_albums(void)
{
    char *library, *db;
    int *rows, *track;
    unsigned albums, tracks, i, gap, *hash = 0, *order = 0;

    if (!PROVIDER)
        return 0;
    library = lib_resolve(*(void **)(PROVIDER + PROVIDER_LIBRARY));
    if (!library || !(db = *(char **)(library + LIBRARY_DB)))
        return 0;
    rows = *(int **)(library + LIBRARY_ALBUMS);
    albums = *(unsigned *)(library + LIBRARY_ALBUM_COUNT);
    tracks = *(unsigned *)(db + DB_TRACK_COUNT);
    if (!rows || albums == 0 || albums > 0xffff)
        return 0;
    if (count && built_list == rows && count == albums && built_tracks == tracks)
        return count;                             /* the same database */
    free_albums();
    album_track = fw_alloc(albums * 4);
    art_offset = fw_alloc(albums * 4);
    art_file = fw_alloc(albums);
    hash = fw_alloc(albums * 4);
    order = fw_alloc(albums * 4);
    keys = fw_alloc(tracks * sizeof(TrackKey) + 4);
    key_count = 0;
    if (!album_track || !art_offset || !art_file || !hash || !order || !keys) {
        free_albums();
        fw_free(hash);
        fw_free(order);
        fw_free(keys);
        keys = 0;
        return 0;
    }
    for (i = 0; i < albums; i++) {
        album_track[i] = 0;
        art_offset[i] = 0xffffffffu;
        hash[i] = name_hash(db, rows[i]);
        order[i] = i;
    }
    for (gap = albums >> 1; gap > 0; gap >>= 1)   /* shell sort of the rows by the hash */
        for (i = gap; i < albums; i++) {
            unsigned v = order[i], j = i;
            while (j >= gap && hash[v] < hash[order[j - gap]]) {
                order[j] = order[j - gap];
                j -= gap;
            }
            order[j] = v;
        }
    /* Each track: find the row of its album name. Keep the first track of each row (for the
       artist), and the dbid and the row of each track (for the artwork). */
    track = *(int **)(db + DB_TRACKS);
    for (i = 0; i < tracks && track; i++, track = *(int **)((char *)track + TRACK_NEXT)) {
        unsigned h = name_hash(db, *(int *)((char *)track + TRACK_ALBUM)), a = 0, b = albums;
        while (a < b) {
            unsigned m = (a + b) >> 1;
            if (hash[order[m]] < h)
                a = m + 1;
            else
                b = m;
        }
        if (a < albums && hash[order[a]] == h && h != 0) {
            unsigned row = order[a];
            if (!album_track[row])
                album_track[row] = track;
            keys[key_count].lo = *(unsigned *)((char *)track + TRACK_DBID);
            keys[key_count].hi = *(unsigned *)((char *)track + TRACK_DBID + 4);
            keys[key_count].row = row;
            key_count++;
        }
    }
    for (gap = key_count >> 1; gap > 0; gap >>= 1)    /* shell sort of the tracks by the dbid */
        for (i = gap; i < key_count; i++) {
            TrackKey v = keys[i];
            unsigned j = i;
            while (j >= gap && (keys[j - gap].hi > v.hi || (keys[j - gap].hi == v.hi && keys[j - gap].lo > v.lo))) {
                keys[j] = keys[j - gap];
                j -= gap;
            }
            keys[j] = v;
        }
    fw_free(hash);
    fw_free(order);
    count = albums;
    album_db = db;
    built_list = rows;
    built_tracks = tracks;
    find_artwork();
    fw_free(keys);
    keys = 0;
    key_count = 0;
    return count;
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
    if (art_offset[i] == 0xffffffffu)
        return placeholder;
    {
        unsigned fh[0x30 / 4];
        int bad;
        if (open_path(fh, ITHMB_PATH, art_file[i]) != 0)
            return placeholder;
        bad = read_at(fh, art_offset[i], pixels + far * size * size, size * size * 2);
        file_close(fh);
        if (bad)
            return placeholder;
    }
    cache_index[far] = i;
    return pixels + far * size * size;
}

/* UTF-16 to UTF-8, with a 0 at the end. */
static void utf8(const unsigned short *in, int bytes, char *out, int max)
{
    int i, o = 0;
    for (i = 0; i < bytes / 2; i++) {
        unsigned c = in[i];
        if (c < 0x80 && o + 1 < max)
            out[o++] = (char)c;
        else if (c < 0x800 && o + 2 < max) {
            out[o++] = (char)(0xc0 | c >> 6);
            out[o++] = (char)(0x80 | (c & 0x3f));
        } else if (c >= 0x800 && o + 3 < max) {
            out[o++] = (char)(0xe0 | c >> 12);
            out[o++] = (char)(0x80 | ((c >> 6) & 0x3f));
            out[o++] = (char)(0x80 | (c & 0x3f));
        } else
            break;
    }
    out[o] = 0;
}

/* The album label of the template cell of the list: it has the font and the colours of the rows. */
static int *row_label(void)
{
    int *cell = (int *)cf_list[LIST_CELL], k, n;
    int **kids;
    if (!cell)
        return 0;
    n = *(int *)((char *)cell + VIEW_CHILD_COUNT);
    kids = *(int ***)((char *)cell + VIEW_CHILDREN);
    for (k = 0; kids && k < n; k++)
        if (*(unsigned short *)((char *)kids[k] + VIEW_ELEMENT_ID) == CELL_ID_ALBUM)
            return kids[k];
    return 0;
}

/* Moves the text between the rows `top` and `bottom` to the centre of the screen. The background
 * is exactly white or black, so each other pixel is text. `dim`: mix the text halfway to the
 * background (a grey artist line). */
static void centre_line(int top, int bottom, int dim_text)
{
    unsigned short bg = light ? 0xffff : 0;
    int x, y, min = W, max = -1, shift;
    for (y = top; y < bottom; y++)
        for (x = 0; x < W; x++)
            if (fb[y * W + x] != bg) {
                if (x < min)
                    min = x;
                if (x > max)
                    max = x;
            }
    if (max < 0)
        return;
    shift = (W - (max - min + 1)) / 2 - min;
    for (y = top; y < bottom; y++) {
        unsigned short *row = fb + y * W;
        if (shift > 0) {
            for (x = max; x >= min; x--)
                row[x + shift] = row[x];
            for (x = min; x < min + shift; x++)
                row[x] = bg;
        }
        if (dim_text)
            for (x = 0; x < W; x++)
                if (row[x] != bg)
                    row[x] = (unsigned short)(((row[x] >> 1) & 0x7bef) + ((bg >> 1) & 0x7bef));
    }
}

/* Draws a text with the label between `top` and `bottom` of the screen. The label goes on
 * the top view for this draw; then all the changed fields go back. */
static void label_text(int *label, const char *text, int top, int bottom)
{
    int *root = cf_list, saved_rect[4], k;
    void *saved_parent = *(void **)((char *)label + VIEW_PARENT);
    unsigned saved_flags = (unsigned)label[VIEW_FLAGS];
    unsigned char saved_state = *((unsigned char *)label + LABEL_STATE);
    int *rect = (int *)((char *)label + VIEW_RECT);

    while (*(int **)((char *)root + VIEW_PARENT))
        root = *(int **)((char *)root + VIEW_PARENT);
    for (k = 0; k < 4; k++)
        saved_rect[k] = rect[k];
    *(void **)((char *)label + VIEW_PARENT) = root;
    rect[0] = top;
    rect[1] = 8;
    rect[2] = bottom;
    rect[3] = W - 8;
    label_draw(label, text, 0);
    for (k = 0; k < 4; k++)
        rect[k] = saved_rect[k];
    label[VIEW_FLAGS] = (int)saved_flags;
    *(void **)((char *)label + VIEW_PARENT) = saved_parent;
    *((unsigned char *)label + LABEL_STATE) = saved_state;
}

/* The album name and the artist below the covers, with the font of the list rows. */
static void draw_caption(int i)
{
    unsigned short name[TEXT_MAX / 2];
    char text[TEXT_MAX * 3 / 2 + 1];
    int length = 0, *label = row_label(), *track;
    if (!label || i < 0 || i >= (int)count)
        return;
    pool_copy(album_db + DB_ALBUM_POOL, built_list[i], name, &length, sizeof name);
    utf8(name, length, text, sizeof text);
    label_text(label, text, ALBUM_TOP, ARTIST_TOP);
    centre_line(ALBUM_TOP, ARTIST_TOP, 0);
    track = album_track[i];
    if (!track)
        return;
    length = 0;
    pool_copy(album_db + DB_ARTIST_POOL, *(int *)((char *)track + TRACK_ARTIST), name, &length, sizeof name);
    utf8(name, length, text, sizeof text);
    label_text(label, text, ARTIST_TOP, H);
    centre_line(ARTIST_TOP, H, 1);
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
    fw_free(placeholder);
    saved = 0;
    pixels = 0;
    placeholder = 0;
    active = 0;
    cf_list = 0;
}

/* Returns 1 if Cover Flow shows. */
static int open_cover_flow(int *list)
{
    unsigned i, rows, sel;
    int *layer;
    void *server = display_server();

    if ((unsigned)LAYER_INDEX >= LAYER_COUNT)
        return 0;
    layer = (int *)((char *)server + SERVER_LAYERS + LAYER_INDEX * LAYER_SIZE);
    if (*(char *)layer != 1 || !*(char **)((char *)layer + LAYER_SURFACE) ||
        *(int *)(*(char **)((char *)layer + LAYER_SURFACE) + SURFACE_STRIDE) != W * 2)
        return 0;
    fb = *(unsigned short **)((char *)layer + LAYER_FB);
    if (build_albums() == 0)
        return 0;
    saved = fw_alloc(W * H * 2);
    pixels = fw_alloc(CACHE_SLOTS * size * size * 2);
    placeholder = fw_alloc(size * size * 2);
    if (!saved || !pixels || !placeholder) {
        release();
        return 0;
    }
    for (i = 0; i < W * H / 2; i++)
        ((unsigned *)saved)[i] = ((unsigned *)fb)[i];
    light = is_light(saved);
    for (i = 0; i < size * size; i++) {   /* a grey square with a lighter frame */
        unsigned x = i - size * udiv(i, size), y = udiv(i, size);
        int frame = x < 4 || y < 4 || x >= size - 4 || y >= size - 4;
        placeholder[i] = frame ? 0x8410 : 0x4a69;
    }
    for (i = 1; i < MAX_SIZE * 2; i++)
        recip[i] = udiv(size << 16, i);
    for (i = 0; i < 16; i++) {
        unsigned r = i * 2 + (i >> 3), g = i * 4 + (i >> 2);
        grey[i] = (unsigned short)(r << 11 | g << 5 | r);
    }
    for (i = 0; i < CACHE_SLOTS; i++)
        cache_index[i] = -1;
    /* Start at the selected row. Row 0 is "All". If the list has other albums (for example the
       albums of one artist), start at the first album. */
    rows = (unsigned)list[LIST_COUNT];
    sel = *(unsigned *)((char *)list[LIST_SELECTION] + 0x14);
    rows_match = rows == count + 1;
    target = (rows_match && sel >= 1 && sel <= count) ? (int)sel - 1 : 0;
    pos = target * 256;
    cf_list = list;
    active = 1;
    render();
    return 1;
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
    if (target * 256 != start)
        ui_click();                       /* the click of the lists, as the Clicker setting gives */
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
