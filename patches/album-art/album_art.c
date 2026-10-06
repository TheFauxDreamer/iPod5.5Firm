/* Album artwork thumbnails in the lists of RetailOS 1.3 (iPod Video).
 *
 * Two hooks replace draw methods in the vtables:
 *  - the list-row label class (type 0x3180, draw method 0x1bb260). This class scrolls a long
 *    title on the highlighted row from a cached image of the text, so the complete method is
 *    wrapped, not only its call to the general label draw function;
 *  - the general label class (type 0x1580, draw method 0x244924).
 * If the label shows an album name (element ID ALBUM_NAME_ID) and the text is the name of an
 * album in the thumbnail file, the wrapper moves the left edge of the label to the right, calls
 * the original method, and draws the thumbnail. A song title has a different element ID, thus a
 * song with the name of an album gets no thumbnail.
 * After RECHECK_MISSES list labels without a thumbnail, the patch reads the file header again.
 * If the header changed (for example after a sync that added albums), it loads the file again.
 *
 * Thumbnail file (written by iPodFirm), all values little-endian:
 *   0x00  "IFAT"
 *   0x04  u16 version (1), u16 thumbnail size S (pixels, square)
 *   0x08  u32 count N
 *   0x0C  u32 stamp: FNV-1a hash of the entries. It changes when the albums change.
 *   0x10  N entries { u32 FNV-1a hash of the UTF-8 album name, u32 file offset of the pixels },
 *         sorted by hash
 *   then  N thumbnails of S*S RGB565 pixels, row by row
 */

typedef struct { int top, left, bottom, right; } Rect;

/* Firmware functions (addresses are in patch.json). */
void label_draw(void *view, const char *text, void *a3);
void row_label_draw(void *view, const char *text, void *a3);
void view_bounds(void *view, Rect *r);
void gc_prepare(void *view, void *gc);
void gc_set_color(void *gc, const unsigned char *rgba);
void gc_set_mode(void *gc, int mode);
void gc_fill_rect(void *gc, Rect *r);
void *fw_alloc(unsigned size);
void fw_free(void *p);
void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);

#define FILE_PATH   "iPod_Control\\iTunes\\iPodFirmAlbumArt"
#define MODE_DATA   0x64617461u           /* 'data' */
#define MAX_SIZE    32
#define CACHE_SLOTS 64
#define LOAD_ALL_MAX (1024 * 1024)        /* load all thumbnails if their data is this size or smaller */
#define GAP         4
#define RECHECK_MISSES 100                /* labels without a thumbnail before the header is read again */
#define VIEW_LEFT   0x5c                  /* offset of the left edge in a view */
#define VIEW_GC     0x74                  /* offset of the graphics context in a view */
#define GC_ORIGIN_X 0x2c                  /* gc+0x30 is the y origin */
#define VIEW_PARENT 0x10                  /* offset of the parent view in a view */
#define LIST_CELL_CLASS 0x66b4dc          /* vtable of the parent of a label in a list row */
#define VIEW_ELEMENT_ID 0x1c              /* u16: the layout element of a view, also its data property */
#define ALBUM_NAME_ID   0x6421            /* element of the album name in an album list row */

typedef struct { unsigned hash, offset; } Entry;

static int state;                         /* 0 = not loaded, 1 = loaded, -1 = no file */
static unsigned retry;                    /* draws to wait before the next try to open the file */
static unsigned count, size;
static Entry *index;
static unsigned short *cache_pixels;
static unsigned short *all_pixels;        /* all thumbnails, if the file is small; else 0 */
static unsigned data_start;
static unsigned cache_hash[CACHE_SLOTS];
static unsigned cache_next;
static unsigned loaded_header[4];         /* the header of the loaded file */
static unsigned misses;                   /* list labels without a thumbnail since the last check */

static unsigned fnv1a(const char *s)
{
    unsigned h = 2166136261u;
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= 16777619u;
    }
    return h;
}

/* Reads `len` bytes at `offset` of the thumbnail file. Returns 0 if correct. */
static int read_at(unsigned offset, void *buf, unsigned len)
{
    unsigned path[0x108 / 4];
    unsigned fh[0x30 / 4];
    unsigned got = len;
    int err;

    fw_memset0(path, sizeof path);
    fw_memset0(fh, sizeof fh);
    fw_strcpy((char *)path + 4, FILE_PATH);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return -1;
    err = file_seek(fh, 0, offset);
    if (err == 0)
        err = file_read(fh, &got, buf);
    file_close(fh);
    return (err == 0 && got == len) ? 0 : -1;
}

/* Releases the loaded file, so that load() reads it again. */
static void unload(void);

static void load(void)
{
    unsigned header[4];
    int i;

    if (state != 0)
        return;
    unload();                             /* memory of an earlier load that failed */
    state = -1;
    if (read_at(0, header, sizeof header) != 0 || header[0] != 0x54414649u)   /* "IFAT" */
        return;
    for (i = 0; i < 4; i++)
        loaded_header[i] = header[i];
    if ((header[1] & 0xffff) != 1)
        return;
    size = header[1] >> 16;
    count = header[2];
    if (size == 0 || size > MAX_SIZE || count == 0 || count > 100000)
        return;
    index = fw_alloc(count * sizeof(Entry));
    if (!index || read_at(16, index, count * sizeof(Entry)) != 0)
        return;
    data_start = 16 + count * sizeof(Entry);
    if (count * size * size * 2 <= LOAD_ALL_MAX) {
        all_pixels = fw_alloc(count * size * size * 2);
        if (all_pixels && read_at(data_start, all_pixels, count * size * size * 2) != 0)
            all_pixels = 0;
    }
    if (!all_pixels) {
        cache_pixels = fw_alloc(CACHE_SLOTS * size * size * 2);
        if (!cache_pixels)
            return;
    }
    state = 1;
}

static const Entry *find(unsigned hash)
{
    unsigned lo = 0, hi = count;
    while (lo < hi) {
        unsigned mid = (lo + hi) / 2;
        if (index[mid].hash < hash)
            lo = mid + 1;
        else
            hi = mid;
    }
    return (lo < count && index[lo].hash == hash) ? &index[lo] : 0;
}

static const unsigned short *pixels(const Entry *e)
{
    unsigned n = size * size;
    unsigned i;
    if (all_pixels)
        return all_pixels + (e->offset - data_start) / 2;
    for (i = 0; i < CACHE_SLOTS; i++)
        if (cache_hash[i] == e->hash && e->hash != 0)
            return cache_pixels + i * n;
    i = cache_next;
    cache_next = (cache_next + 1) % CACHE_SLOTS;
    cache_hash[i] = 0;
    if (read_at(e->offset, cache_pixels + i * n, n * 2) != 0)
        return 0;
    cache_hash[i] = e->hash;
    return cache_pixels + i * n;
}

/* Draws the thumbnail with runs of pixels that have the same colour. */
static void draw_thumbnail(void *gc, const unsigned short *px, int top, int left)
{
    unsigned char rgba[4];
    int y, x;
    /* Mode 0 replaces the pixels. Mode 1 blends with the background, so on a dark theme the
       thumbnail is not visible. */
    gc_set_mode(gc, 0);
    for (y = 0; y < (int)size; y++) {
        x = 0;
        while (x < (int)size) {
            unsigned short c = px[y * size + x];
            int end = x + 1;
            Rect r;
            while (end < (int)size && px[y * size + end] == c)
                end++;
            rgba[0] = (unsigned char)(((c >> 11) & 31) << 3 | ((c >> 13) & 7));
            rgba[1] = (unsigned char)(((c >> 5) & 63) << 2 | ((c >> 9) & 3));
            rgba[2] = (unsigned char)((c & 31) << 3 | ((c >> 2) & 7));
            rgba[3] = 0xff;
            gc_set_color(gc, rgba);
            r.top = top + y;
            r.bottom = top + y + 1;
            r.left = left + x;
            r.right = left + end;
            gc_fill_rect(gc, &r);
            x = end;
        }
    }
}

typedef void (*draw_fn)(void *view, const char *text, void *a3);

/* The album of each label view, from its last draw with text. The highlighted row with a long
 * title scrolls the title: these draws come without text (the label uses a cached image of
 * the text), so the album must be known from an earlier draw. */
#define VIEW_SLOTS 32
static void *slot_view[VIEW_SLOTS];
static const Entry *slot_entry[VIEW_SLOTS];

static int view_slot(void *view, int make)
{
    int i, empty = -1;
    for (i = 0; i < VIEW_SLOTS; i++) {
        if (slot_view[i] == view)
            return i;
        if (!slot_view[i] && empty < 0)
            empty = i;
    }
    if (!make)
        return -1;
    if (empty < 0)
        empty = (int)(((unsigned)view >> 4) % VIEW_SLOTS);
    slot_view[empty] = view;
    return empty;
}

static void unload(void)
{
    int i;
    fw_free(index);
    fw_free(all_pixels);
    fw_free(cache_pixels);
    index = 0;
    all_pixels = 0;
    cache_pixels = 0;
    count = 0;
    cache_next = 0;
    for (i = 0; i < CACHE_SLOTS; i++)
        cache_hash[i] = 0;
    for (i = 0; i < VIEW_SLOTS; i++) {    /* the slots point into the index */
        slot_view[i] = 0;
        slot_entry[i] = 0;
    }
    state = 0;
}

/* A list label without a thumbnail can be a new album. Read the header again after some of
 * them; if the file changed, release it so that the next draw loads the new file. */
static void check_for_new_file(void)
{
    unsigned header[4];
    int i;
    if (++misses < RECHECK_MISSES)
        return;
    misses = 0;
    if (read_at(0, header, sizeof header) != 0)
        return;                           /* no file now: keep the loaded thumbnails */
    for (i = 0; i < 4; i++)
        if (header[i] != loaded_header[i]) {
            unload();
            return;
        }
}

static void draw_with_thumbnail(draw_fn original, void *view, const char *text, void *a3)
{
    Rect r;
    void *gc = (char *)view + VIEW_GC;
    const Entry *e = 0;
    const unsigned short *px;
    int height, *left, i;

    if (state == -1 && ++retry >= 200) {      /* try again later: the file can be added by a sync */
        retry = 0;
        state = 0;
    }
    load();
    if (state != 1) {
        original(view, text, a3);
        return;
    }
    view_bounds(view, &r);
    height = r.bottom - r.top;
    /* Only album names in rows of a list: at the left edge of the screen, with the height of a
       list row. A song can have the same title as an album, but its label has a different ID. */
    if (*(unsigned short *)((char *)view + VIEW_ELEMENT_ID) == ALBUM_NAME_ID &&
        height >= (int)size && height <= (int)size + 12 &&
        r.left + *(int *)((char *)gc + GC_ORIGIN_X) <= 8) {
        /* Some draws pass a structure instead of the text; it starts with pointer bytes. */
        if (text && (unsigned char)*text >= 0x20) {
            e = find(fnv1a(text));
            i = view_slot(view, e != 0);
            if (i >= 0) {
                slot_entry[i] = e;
                if (!e)
                    slot_view[i] = 0;
            }
            if (!e)
                check_for_new_file();     /* can release the file: e stays 0 */
        } else if ((i = view_slot(view, 0)) >= 0) {
            e = slot_entry[i];
        }
    }
    if (!e || (px = pixels(e)) == 0) {
        original(view, text, a3);
        return;
    }
    left = (int *)((char *)view + VIEW_LEFT);
    *left += (int)size + GAP;
    original(view, text, a3);
    *left -= (int)size + GAP;
    gc_prepare(view, gc);                 /* set the origin and the clip for the original bounds */
    draw_thumbnail(gc, px, r.top + (height - (int)size) / 2, r.left + 1);
}

void hook_row_label_draw(void *view, const char *text, void *a3)
{
    draw_with_thumbnail(row_label_draw, view, text, a3);
}

/* The general label class is also used outside the lists, for example for the album name in
 * Now Playing. Draw a thumbnail only if the parent of the label is a list row. */
void hook_label_draw(void *view, const char *text, void *a3)
{
    void *parent = *(void **)((char *)view + VIEW_PARENT);
    if (!parent || *(unsigned *)parent != LIST_CELL_CLASS) {
        label_draw(view, text, a3);
        return;
    }
    draw_with_thumbnail(label_draw, view, text, a3);
}
