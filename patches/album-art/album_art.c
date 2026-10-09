/* Album artwork thumbnails in the lists of RetailOS 1.3 (iPod Video). Research: re/album-art-v2.md.
 *
 * Two hooks replace draw methods in the vtables:
 *  - the list-row label class (type 0x3180, draw method 0x1bb260). This class scrolls a long
 *    title on the highlighted row from a cached image of the text, so the complete method is
 *    wrapped, not only its call to the general label draw function;
 *  - the general label class (type 0x1580, draw method 0x244924).
 * If the label shows an album name (element ID ALBUM_NAME_ID) or a playlist name (element ID
 * PLAYLIST_NAME_ID) and a thumbnail is available, the wrapper moves the left edge of the label to
 * the right, calls the original method, and draws the thumbnail. A song title has a different
 * element ID, thus a song with the name of an album gets no thumbnail.
 *
 * The thumbnails come from two sources:
 *  - Albums: the artwork that iTunes or Finder put on the iPod. iPod_Control\Artwork\ArtworkDB
 *    links each image (mhii) to the dbid of a track (track + 0x108). The patch reads the 100 x 100
 *    image (format 1028, RGB565) from F1028_N.ithmb and makes a 20 x 20 thumbnail with a 5 x 5
 *    average. The table of the albums is made at the first album label after a database load.
 *  - Playlists, and albums without artwork on the iPod: the optional thumbnail file
 *    iPod_Control\iTunes\iPodFirmAlbumArt, which iPodFirm writes.
 * The hash of a playlist name starts with the byte 0x01, thus a playlist and an album with the
 * same name have different thumbnails.
 *
 * A thumbnail draws with one call of the firmware blit 0x210114. The source of the blit is a
 * graphics context with a bitmap around the thumbnail pixels. The firmware clips the blit and
 * marks the damaged area. If the target bitmap is not RGB565, the patch fills runs of pixels.
 *
 * A thumbnail from the artwork needs one read of 20000 bytes at its first draw. Then it stays in
 * memory (a maximum of 1 MB of thumbnails). A mark of the label for a new draw (0x21ac04) during
 * a draw does not start a new draw, thus the patch makes each thumbnail at its first draw.
 *
 * A third hook replaces a call in the music database load 0xb4a64. The firmware does this load
 * at the start and after each USB session ("Exit Disk Mode", event 0xf of the usage log). The hook
 * only sets a flag, because the load runs in a different task. At the next album or playlist
 * label, the patch makes the album table again and reads the header of the file again. If the
 * header changed, it loads the file again. If there was no file, it tries to load the file.
 *
 * Thumbnail file (written by iPodFirm), all values little-endian:
 *   0x00  "IFAT"
 *   0x04  u16 version (1), u16 thumbnail size S (pixels, square)
 *   0x08  u32 count N
 *   0x0C  u32 stamp: FNV-1a hash of all the bytes after the header. It changes when the albums
 *         or the thumbnails change.
 *   0x10  N entries { u32 FNV-1a hash of the UTF-8 album name (or of 0x01 and the playlist
 *         name), u32 file offset of the pixels }, sorted by hash
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
void gc_blit(void *gc, void *src_gc, Rect *src, Rect *dst);
void *lib_resolve(void *ref);
int pool_copy(void *pool, int index, void *buffer, int *length, int maximum);
void *fw_alloc(unsigned size);
void fw_free(void *p);
void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
void log_event(void *log, int event, int value);

/* Code that runs once for each load or each label: small code. The pixel loops stay fast. */
#define COLD __attribute__((minsize))

#define FILE_PATH   "iPod_Control\\iTunes\\iPodFirmAlbumArt"
#define ART_DB_PATH "iPod_Control\\Artwork\\ArtworkDB"
#define ITHMB_PATH  "iPod_Control\\Artwork\\F1028_"   /* + N + ".ithmb" */
#define MODE_DATA   0x64617461u           /* 'data' */
#define MAX_SIZE    32
#define CACHE_SLOTS 64
#define LOAD_ALL_MAX (1024 * 1024)        /* load all thumbnails if their data is this size or smaller */
#define GAP         4
#define VIEW_LEFT   0x5c                  /* offset of the left edge in a view */
#define VIEW_GC     0x74                  /* offset of the graphics context in a view */
#define GC_ORIGIN_X 0x2c                  /* gc+0x30 is the y origin */
#define GC_BITMAP   0x1c                  /* the bitmap of the gc; bitmap + 4 is its descriptor */
#define GC_WORDS    (0x44 / 4)            /* the size of a gc (0x210638 sets 0x44 bytes) */
#define VIEW_PARENT 0x10                  /* offset of the parent view in a view */
#define LIST_CELL_CLASS 0x66b4dc          /* vtable of the parent of a label in a list row */
#define VIEW_ELEMENT_ID 0x1c              /* u16: the layout element of a view, also its data property */
#define ALBUM_NAME_ID   0x6421            /* element of the album name in an album list row */
#define PLAYLIST_NAME_ID 0x6425           /* element of the playlist name in a playlist list row */
#define FNV_BASIS       2166136261u
#define FNV_PRIME       16777619u
#define PLAYLIST_BASIS  ((FNV_BASIS ^ 1u) * FNV_PRIME)   /* the FNV-1a state after the byte 0x01 */

/* The music database in RAM (re/cover-flow.md, "The RAM database"). */
#define PROVIDER       (*(char **)0x1081da18) /* the main provider of the music screens */
#define PROVIDER_LIBRARY 0x1c
#define LIBRARY_DB     0xcf8              /* the music database */
#define DB_TRACK_COUNT 0x1c
#define DB_TRACKS      0x20               /* the first track */
#define DB_ALBUM_POOL  0x138
#define TRACK_NEXT     4
#define TRACK_ALBUM    0x34
#define TRACK_DBID     0x108
#define NAME_BYTES     512                /* UTF-16 bytes of an album name that the patch reads */

/* The artwork. */
#define ART_FORMAT     1028               /* 100 x 100 RGB565 */
#define ART_SIZE       100
#define TH             20                 /* the size of a thumbnail from the artwork */
#define ART_MAX_SLOTS  ((1024 * 1024) / (TH * TH * 2))   /* 1 MB of thumbnails */
#define NO_SLOT        0xffff
#define FAILED         0xfffe             /* the read failed: do not try again */
#define WINDOW         32768

typedef struct { unsigned hash, offset; } Entry;

/* An album with artwork. `slot` is its thumbnail in art_pixels, NO_SLOT or FAILED. */
typedef struct { unsigned hash, offset; unsigned short slot; unsigned char file, pad; } Art;

/* The thumbnail file. */
static int state;                         /* 0 = not loaded, 1 = loaded, -1 = no file */
static unsigned count, size;
static Entry *index;
static unsigned short *cache_pixels;
static unsigned short *all_pixels;        /* all thumbnails, if the file is small; else 0 */
static unsigned data_start;
static unsigned cache_hash[CACHE_SLOTS];
static unsigned cache_next;
static unsigned loaded_header[4];         /* the header of the loaded file */
static volatile int db_loaded;            /* set by the database load after a USB session */

/* The artwork. */
static int art_state;                     /* 0 = not made, 1 = made, -1 = no artwork */
static Art *art;                          /* sorted by hash */
static unsigned art_count;
static unsigned short *art_pixels;        /* art_slots thumbnails of TH x TH */
static unsigned short *slot_owner;        /* the index in `art` of each slot, or NO_SLOT */
static unsigned art_slots, art_next;
static unsigned short *art_buffer;        /* one 100 x 100 image */

static unsigned fnv1a(unsigned h, const char *s)
{
    while (*s) {
        h ^= (unsigned char)*s++;
        h *= FNV_PRIME;
    }
    return h;
}

/* Opens a file. `number` > 0: add N and ".ithmb" (N < 100). The same as cover_flow.c. */
COLD static int open_path(unsigned *fh, const char *path, int number)
{
    unsigned record[0x108 / 4];
    char *p = (char *)record + 4;
    fw_memset0(record, sizeof record);
    fw_memset0(fh, 0x30);
    fw_strcpy(p, path);
    if (number) {
        int tens = (number * 205) >> 11;  /* number / 10 for number < 1029; "/" calls a library */
        while (*p)
            p++;
        number -= tens * 10;
        if (tens)
            *p++ = (char)('0' + tens);
        *p++ = (char)('0' + number);
        fw_strcpy(p, ".ithmb");
    }
    return file_open(record, fh, 0, MODE_DATA);
}

/* Reads `len` bytes at `offset` of an open file. Returns 0 if correct. The same as cover_flow.c. */
COLD static int read_at(unsigned *fh, unsigned offset, void *buf, unsigned len)
{
    unsigned got = len;
    if (file_seek(fh, 0, offset) != 0 || file_read(fh, &got, buf) != 0)
        return -1;
    return got == len ? 0 : -1;
}

/* Reads `len` bytes at `offset` of the thumbnail file. Returns 0 if correct. */
COLD static int read_file(unsigned offset, void *buf, unsigned len)
{
    unsigned fh[0x30 / 4];
    int err;
    if (open_path(fh, FILE_PATH, 0) != 0)
        return -1;
    err = read_at(fh, offset, buf, len);
    file_close(fh);
    return err;
}

/* ---------- the thumbnail file ---------- */

/* Releases the loaded file, so that load() reads it again. */
COLD static void unload(void)
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
    state = 0;
}

COLD static void load(void)
{
    unsigned header[4];
    int i;

    if (state != 0)
        return;
    unload();                             /* memory of an earlier load that failed */
    state = -1;
    if (read_file(0, header, sizeof header) != 0 || header[0] != 0x54414649u)   /* "IFAT" */
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
    if (!index || read_file(16, index, count * sizeof(Entry)) != 0)
        return;
    data_start = 16 + count * sizeof(Entry);
    if (count * size * size * 2 <= LOAD_ALL_MAX) {
        all_pixels = fw_alloc(count * size * size * 2);
        if (all_pixels && read_file(data_start, all_pixels, count * size * size * 2) != 0) {
            fw_free(all_pixels);
            all_pixels = 0;
        }
    }
    if (!all_pixels) {
        cache_pixels = fw_alloc(CACHE_SLOTS * size * size * 2);
        if (!cache_pixels)
            return;
    }
    state = 1;
}

/* Reads the header again. If the file changed, releases it so that the next load reads the new
 * file. */
COLD static void check_for_new_file(void)
{
    unsigned header[4];
    int i;
    if (read_file(0, header, sizeof header) != 0)
        return;                           /* no file now: keep the loaded thumbnails */
    for (i = 0; i < 4; i++)
        if (header[i] != loaded_header[i]) {
            unload();
            return;
        }
}

COLD static const Entry *find(unsigned hash)
{
    unsigned lo = 0, hi = count;
    if (state != 1)
        return 0;
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        if (index[mid].hash < hash)
            lo = mid + 1;
        else
            hi = mid;
    }
    return (lo < count && index[lo].hash == hash) ? &index[lo] : 0;
}

COLD static const unsigned short *pixels(const Entry *e)
{
    unsigned n = size * size;
    unsigned i;
    if (all_pixels)
        return all_pixels + ((e->offset - data_start) >> 1);
    for (i = 0; i < CACHE_SLOTS; i++)
        if (cache_hash[i] == e->hash && e->hash != 0)
            return cache_pixels + i * n;
    i = cache_next;
    cache_next = (cache_next + 1) & (CACHE_SLOTS - 1);
    cache_hash[i] = 0;
    if (read_file(e->offset, cache_pixels + i * n, n * 2) != 0)
        return 0;
    cache_hash[i] = e->hash;
    return cache_pixels + i * n;
}

/* ---------- the artwork of the iPod ---------- */

COLD static void free_art(void)
{
    fw_free(art);
    fw_free(art_pixels);
    fw_free(slot_owner);
    fw_free(art_buffer);
    art = 0;
    art_pixels = 0;
    slot_owner = 0;
    art_buffer = 0;
    art_count = 0;
    art_slots = 0;
    art_next = 0;
    art_state = 0;
}

COLD static unsigned get32(const unsigned char *b)
{
    return b[0] | b[1] << 8 | b[2] << 16 | (unsigned)b[3] << 24;
}

#define TAG(a, b, c, d) ((unsigned)(a) | (unsigned)(b) << 8 | (unsigned)(c) << 16 | (unsigned)(d) << 24)

COLD static unsigned fnv_byte(unsigned h, unsigned b)
{
    return (h ^ (b & 0xff)) * FNV_PRIME;
}

/* The FNV-1a hash of the UTF-8 form of an album name in the pool, as the label text gives it.
 * Returns 0 for an empty name. */
COLD static unsigned album_hash(char *db, int pool_index, unsigned short *name)
{
    unsigned h = FNV_BASIS, c;
    int length = 0, n, k;
    pool_copy(db + DB_ALBUM_POOL, pool_index, name, &length, NAME_BYTES);
    n = length >> 1;
    if (n <= 0)
        return 0;
    for (k = 0; k < n; k++) {
        c = name[k];
        if (c >= 0xd800 && c < 0xdc00 && k + 1 < n && name[k + 1] >= 0xdc00 && name[k + 1] < 0xe000) {
            c = 0x10000 + ((c - 0xd800) << 10) + (name[k + 1] - 0xdc00);   /* a surrogate pair */
            k++;
        }
        if (c < 0x80) {
            h = fnv_byte(h, c);
        } else if (c < 0x800) {
            h = fnv_byte(h, 0xc0 | c >> 6);
            h = fnv_byte(h, 0x80 | (c & 0x3f));
        } else if (c < 0x10000) {
            h = fnv_byte(h, 0xe0 | c >> 12);
            h = fnv_byte(h, 0x80 | ((c >> 6) & 0x3f));
            h = fnv_byte(h, 0x80 | (c & 0x3f));
        } else {
            h = fnv_byte(h, 0xf0 | c >> 18);
            h = fnv_byte(h, 0x80 | ((c >> 12) & 0x3f));
            h = fnv_byte(h, 0x80 | ((c >> 6) & 0x3f));
            h = fnv_byte(h, 0x80 | (c & 0x3f));
        }
    }
    return h;
}

/* The tracks sorted by dbid, with the hash of their album (only while the table is made). */
typedef struct { unsigned lo, hi, hash; } TrackKey;
static TrackKey *keys;
static unsigned key_count;

COLD static unsigned album_of(unsigned lo, unsigned hi)
{
    unsigned a = 0, b = key_count;
    while (a < b) {
        unsigned m = (a + b) >> 1;
        if (keys[m].hi < hi || (keys[m].hi == hi && keys[m].lo < lo))
            a = m + 1;
        else
            b = m;
    }
    return (a < key_count && keys[a].lo == lo && keys[a].hi == hi) ? keys[a].hash : 0;
}

/* A read window over ArtworkDB: the parser makes many small reads; the window makes a few large
 * reads of the file. The same as cover_flow.c. */
static unsigned char *window;
static unsigned window_pos, window_len;

COLD static int db_read(unsigned *fh, unsigned pos, void *dst, unsigned len)
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

/* Reads ArtworkDB. Adds an entry to `art` for each image of format 1028 that belongs to a track
 * with an album. The file has
 * mhfd { mhsd (type 1) { mhli { mhii { mhod (type 2) { mhni { mhod (type 3: file name) } } } } } }.
 * Adapted from find_artwork in cover_flow.c. */
COLD static void find_artwork(void)
{
    unsigned fh[0x30 / 4];
    unsigned char h[0x40];                 /* the largest read is 0x24 + 2 * 12 bytes (a file name) */
    unsigned pos, end;
    window_len = 0;
    if (open_path(fh, ART_DB_PATH, 0) != 0)
        return;
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
            for (k = 0; k < items && art_count < key_count; k++) {
                unsigned ilen, children, q, c, album;
                if (db_read(fh, p, h, 0x1c) != 0 || get32(h) != TAG('m', 'h', 'i', 'i'))
                    break;
                ilen = get32(h + 8);
                children = get32(h + 12);
                album = album_of(get32(h + 0x14), get32(h + 0x18));
                q = p + get32(h + 4);
                for (c = 0; album && c < children; c++) {
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
                        art[art_count].hash = album;
                        art[art_count].offset = offset;
                        art[art_count].file = (unsigned char)number;
                        art[art_count].slot = NO_SLOT;
                        art_count++;
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
}

/* Makes the table of the albums with artwork. Sets art_state to 1 or -1. */
COLD static void build_art(void)
{
    char *library, *db;
    int *track;
    unsigned short *name;
    unsigned tracks, i, j, gap;

    free_art();
    art_state = -1;
    if (!PROVIDER)
        return;
    library = lib_resolve(*(void **)(PROVIDER + PROVIDER_LIBRARY));
    if (!library || !(db = *(char **)(library + LIBRARY_DB)))
        return;
    tracks = *(unsigned *)(db + DB_TRACK_COUNT);
    if (tracks == 0 || tracks > 0xfff0)
        return;
    name = fw_alloc(NAME_BYTES);
    keys = fw_alloc(tracks * sizeof(TrackKey));
    art = fw_alloc(tracks * sizeof(Art));
    window = fw_alloc(WINDOW);
    key_count = 0;
    if (name && keys && art && window) {
        /* Each track with an album: its dbid and the hash of its album. */
        track = *(int **)(db + DB_TRACKS);
        for (i = 0; i < tracks && track; i++, track = *(int **)((char *)track + TRACK_NEXT)) {
            unsigned h = album_hash(db, *(int *)((char *)track + TRACK_ALBUM), name);
            if (!h)
                continue;
            keys[key_count].lo = *(unsigned *)((char *)track + TRACK_DBID);
            keys[key_count].hi = *(unsigned *)((char *)track + TRACK_DBID + 4);
            keys[key_count].hash = h;
            key_count++;
        }
        for (gap = key_count >> 1; gap > 0; gap >>= 1)    /* shell sort of the tracks by the dbid */
            for (i = gap; i < key_count; i++) {
                TrackKey v = keys[i];
                j = i;
                while (j >= gap && (keys[j - gap].hi > v.hi || (keys[j - gap].hi == v.hi && keys[j - gap].lo > v.lo))) {
                    keys[j] = keys[j - gap];
                    j -= gap;
                }
                keys[j] = v;
            }
        find_artwork();
        for (gap = art_count >> 1; gap > 0; gap >>= 1)    /* shell sort of the images by the hash */
            for (i = gap; i < art_count; i++) {
                Art v = art[i];
                j = i;
                while (j >= gap && art[j - gap].hash > v.hash) {
                    art[j] = art[j - gap];
                    j -= gap;
                }
                art[j] = v;
            }
        for (i = j = 0; i < art_count; i++)               /* one image for each album */
            if (j == 0 || art[i].hash != art[j - 1].hash)
                art[j++] = art[i];
        art_count = j;
    }
    fw_free(name);
    fw_free(keys);
    fw_free(window);
    keys = 0;
    key_count = 0;
    window = 0;
    if (art_count == 0) {
        free_art();
        art_state = -1;
        return;
    }
    art_slots = art_count < ART_MAX_SLOTS ? art_count : ART_MAX_SLOTS;
    art_pixels = fw_alloc(art_slots * TH * TH * 2);
    slot_owner = fw_alloc(art_slots * 2);
    art_buffer = fw_alloc(ART_SIZE * ART_SIZE * 2);
    if (!art_pixels || !slot_owner || !art_buffer) {
        free_art();
        art_state = -1;
        return;
    }
    for (i = 0; i < art_slots; i++)
        slot_owner[i] = NO_SLOT;
    art_state = 1;
}

/* The index of the album in `art`, or -1. */
COLD static int art_find(unsigned hash)
{
    unsigned lo = 0, hi = art_count;
    if (art_state != 1)
        return -1;
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        if (art[mid].hash < hash)
            lo = mid + 1;
        else
            hi = mid;
    }
    return (lo < art_count && art[lo].hash == hash) ? (int)lo : -1;
}

/* Makes a TH x TH thumbnail from a 100 x 100 image: the average of each 5 x 5 square.
 * (sum * 2621 + 32768) >> 16 is sum / 25, rounded. Not inlined: fast code, not small code. */
__attribute__((noinline)) static void shrink(const unsigned short *in, unsigned short *out)
{
    int x, y, i, j;
    for (y = 0; y < TH; y++)
        for (x = 0; x < TH; x++) {
            const unsigned short *p = in + y * 5 * ART_SIZE + x * 5;
            unsigned r = 0, g = 0, b = 0;
            for (j = 0; j < 5; j++, p += ART_SIZE)
                for (i = 0; i < 5; i++) {
                    unsigned c = p[i];
                    r += c >> 11;
                    g += (c >> 5) & 63;
                    b += c & 31;
                }
            *out++ = (unsigned short)(((r * 2621 + 32768) >> 16) << 11 |
                                      ((g * 2621 + 32768) >> 16) << 5 |
                                      ((b * 2621 + 32768) >> 16));
        }
}

/* The thumbnail of an album from the artwork, or 0. */
COLD static const unsigned short *art_thumb(int n)
{
    Art *a = &art[n];
    unsigned fh[0x30 / 4];
    unsigned s;
    int bad;
    if (a->slot < art_slots)
        return art_pixels + a->slot * TH * TH;
    if (a->slot == FAILED)
        return 0;
    s = art_next;
    art_next = art_next + 1 == art_slots ? 0 : art_next + 1;
    if (slot_owner[s] != NO_SLOT)               /* the oldest thumbnail gives its slot */
        art[slot_owner[s]].slot = NO_SLOT;
    slot_owner[s] = NO_SLOT;
    bad = open_path(fh, ITHMB_PATH, a->file);
    if (bad == 0) {
        bad = read_at(fh, a->offset, art_buffer, ART_SIZE * ART_SIZE * 2);
        file_close(fh);
    }
    if (bad) {
        a->slot = FAILED;
        return 0;
    }
    shrink(art_buffer, art_pixels + s * TH * TH);
    slot_owner[s] = (unsigned short)n;
    a->slot = (unsigned short)s;
    return art_pixels + s * TH * TH;
}

/* ---------- the draw ---------- */

/* Draws the thumbnail with runs of pixels that have the same colour. Used only if the target
 * bitmap is not RGB565. */
COLD static void draw_runs(void *gc, const unsigned short *px, int ts, int top, int left)
{
    unsigned char rgba[4];
    int y, x;
    for (y = 0; y < ts; y++) {
        x = 0;
        while (x < ts) {
            unsigned short c = px[y * ts + x];
            int end = x + 1;
            Rect r;
            while (end < ts && px[y * ts + end] == c)
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

/* Draws a ts x ts RGB565 thumbnail at (left, top) of the gc.
 * A bitmap object has the descriptor at +4 (0x1216a0): pixels, stride in bytes, bits for each
 * pixel, shift (x << shift is the bit offset), u16 format (0x565; bit 0x2000 swaps the bytes),
 * then the bounds top, left, bottom, right. The blit 0x210114(gc, source gc, source rect, target
 * rect) adds the origins of the two gcs, clips with gc + 0x34, copies and marks the damage. */
COLD static void draw_thumbnail(void *gc, const unsigned short *px, int ts, int top, int left)
{
    int *target = *(int **)((char *)gc + GC_BITMAP);
    int bitmap[10], source[GC_WORDS], k;
    Rect s, d;

    /* Mode 0 replaces the pixels. Mode 1 blends with the background, so on a dark theme the
       thumbnail is not visible. */
    gc_set_mode(gc, 0);
    if (!target || target[3] != 16 || (target[5] & 0xdfff) != 0x565 || ((unsigned)px & 3) || (ts & 1)) {
        draw_runs(gc, px, ts, top, left);
        return;
    }
    for (k = 0; k < GC_WORDS; k++)
        source[k] = 0;
    bitmap[0] = 0;
    bitmap[1] = (int)px;
    bitmap[2] = ts * 2;
    bitmap[3] = 16;
    bitmap[4] = target[4];
    bitmap[5] = target[5];                /* the same format: the blit copies, it does not convert */
    bitmap[6] = 0;
    bitmap[7] = 0;
    bitmap[8] = ts;
    bitmap[9] = ts;
    source[GC_BITMAP / 4] = (int)bitmap;
    s.top = 0;
    s.left = 0;
    s.bottom = ts;
    s.right = ts;
    d.top = top;
    d.left = left;
    d.bottom = top + ts;
    d.right = left + ts;
    gc_blit(gc, source, &s, &d);
}

typedef void (*draw_fn)(void *view, const char *text, void *a3);

/* The hash of each label view, from its last draw with text. The highlighted row with a long
 * title scrolls the title: these draws come without text (the label uses a cached image of
 * the text), so the album must be known from an earlier draw. */
#define VIEW_SLOTS 32
static void *slot_view[VIEW_SLOTS];
static unsigned slot_hash[VIEW_SLOTS];

COLD static int view_slot(void *view, int make)
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
        empty = (int)(((unsigned)view >> 4) & (VIEW_SLOTS - 1));
    slot_view[empty] = view;
    return empty;
}

COLD static void draw_with_thumbnail(draw_fn original, void *view, const char *text, void *a3)
{
    Rect r;
    void *gc = (char *)view + VIEW_GC;
    const unsigned short *px = 0;
    const Entry *e;
    unsigned h = 0;
    int height, *left, i, n, ts = 0;
    unsigned id = *(unsigned short *)((char *)view + VIEW_ELEMENT_ID);

    if (id != ALBUM_NAME_ID && id != PLAYLIST_NAME_ID) {
        original(view, text, a3);
        return;
    }
    /* After a USB session the database, the artwork and the file can be new or changed. */
    if (db_loaded) {
        db_loaded = 0;
        art_state = 0;
        if (state == 1)
            check_for_new_file();
        else if (state == -1)
            state = 0;
    }
    if (art_state == 0)
        build_art();
    load();
    view_bounds(view, &r);
    height = r.bottom - r.top;
    /* Only rows of a list: at the left edge of the screen. */
    if (r.left + *(int *)((char *)gc + GC_ORIGIN_X) <= 8) {
        /* Some draws pass a structure instead of the text; it starts with pointer bytes. */
        if (text && (unsigned char)*text >= 0x20) {
            h = fnv1a(id == PLAYLIST_NAME_ID ? PLAYLIST_BASIS : FNV_BASIS, text);
            slot_hash[view_slot(view, 1)] = h;
        } else if ((i = view_slot(view, 0)) >= 0) {
            h = slot_hash[i];
        }
    }
    if (h && id == ALBUM_NAME_ID && (n = art_find(h)) >= 0) {
        px = art_thumb(n);
        ts = TH;
    }
    if (h && !px && (e = find(h)) != 0) {
        px = pixels(e);
        ts = (int)size;
    }
    /* A list row has the height of the thumbnail and a margin. */
    if (!px || height < ts || height > ts + 12) {
        original(view, text, a3);
        return;
    }
    left = (int *)((char *)view + VIEW_LEFT);
    *left += ts + GAP;
    original(view, text, a3);
    *left -= ts + GAP;
    gc_prepare(view, gc);                 /* set the origin and the clip for the original bounds */
    draw_thumbnail(gc, px, ts, r.top + ((height - ts) >> 1), r.left + 1);
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

/* Replaces the call at 0xb4ad4 in the music database load: log_event(log, 0xf, 0). */
void hook_db_loaded(void *log, int event, int value)
{
    log_event(log, event, value);
    db_loaded = 1;
}
