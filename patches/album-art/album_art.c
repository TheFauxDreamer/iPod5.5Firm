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
 * The thumbnails come from three sources:
 *  - Albums: the artwork that iTunes or Finder put on the iPod. iPod_Control\Artwork\ArtworkDB
 *    links each image (mhii) to the dbid of a track (track + 0x108). The patch reads the 100 x 100
 *    image (format 1028, RGB565) from F1028_N.ithmb and makes a 20 x 20 thumbnail with a 5 x 5
 *    average. The table of the albums is made at the first album row that needs the artwork after
 *    a database load.
 *  - The cache: when each album with artwork has a thumbnail in memory, the patch writes all of
 *    them to iPod_Control\iTunes\iPodFirmAlbumCache. At the next start, the patch reads this file
 *    into memory and does not read the artwork. The stamp of the file is a hash of the start of
 *    ArtworkDB and of the album names. A sync that changes them makes the file not valid.
 *  - The optional thumbnail file iPod_Control\iTunes\iPodFirmAlbumArt, which iPodFirm writes.
 *    It has the playlists, and the albums that iPodFirm found.
 *  - A playlist that is not in that file gets a collage (version 3.0): the first 4 different
 *    albums of the playlist that have a thumbnail, in a 2 x 2 square, as iPodFirm makes it. With
 *    1 to 3 albums, the first thumbnail alone. The patch finds the playlist by the hash of its
 *    name in the list at db + 0x2c (re/playlist-art.md). On-The-Go also gets a collage.
 *  - A folder of the patch playlist-folders gets a fixed folder icon (version 3.4). The patch reads
 *    the folder names from iPodFirmPlaylistFolders (re/playlist-folders.md, "Folder icon").
 * The order for an album (version 2.9): the file of iPodFirm, then a valid cache, then the
 * artwork. Thus the file that the owner wrote comes first, and the patch fills the gaps. The
 * cache always has all albums with artwork, thus it is complete also without the file.
 * The hash of a playlist name starts with the byte 0x01, thus a playlist and an album with the
 * same name have different thumbnails.
 *
 * The open of F1028_N.ithmb is slow if the file is large (one image for each track: 104 MB for
 * 5201 tracks). Thus the patch keeps the file open while it reads covers. It closes the file when
 * the background fill has no more work, and 30 s after the last read (an open takes 0.93 s on the
 * real iPod; version 2.8 closed after 2 s and opened 8 times in one fill). The firmware also keeps its
 * own ArtworkDB handle open during a USB session and closes it after (0xb4fe4 calls 0x91164).
 * Thus after a USB session the patch closes its old handle first.
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
 * Thumbnail file (written by iPodFirm) and cache file (written by the patch), all values
 * little-endian:
 *   0x00  "IFAT"
 *   0x04  u16 version (1), u16 thumbnail size S (pixels, square)
 *   0x08  u32 count N
 *   0x0C  u32 stamp. Thumbnail file: FNV-1a hash of all the bytes after the header. It changes
 *         when the albums or the thumbnails change. Cache file: refer to art_stamp().
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
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_write(void *fh, unsigned *len, const void *buf);
int list_event(int *list, int *ev, void *a3, int a4);   /* the previous target of the hook (chain) */
void timer_start(void *timer);
void view_invalidate(void *view);

/* Code that runs once for each load or each label: small code. The pixel loops stay fast. */
#define COLD __attribute__((minsize))

#define FILE_PATH   "iPod_Control\\iTunes\\iPodFirmAlbumArt"
#define ART_DB_PATH "iPod_Control\\Artwork\\ArtworkDB"
#define ITHMB_PATH  "iPod_Control\\Artwork\\F1028_"   /* + N + ".ithmb" */
#define FOLDERS_PATH "iPod_Control\\iTunes\\iPodFirmPlaylistFolders"   /* of playlist-folders */
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
#define LIBRARY_ALBUMS 0xc60              /* the album list: album pool indexes, without "All" */
#define LIBRARY_ALBUM_COUNT 0xc6c
#define TRACK_NEXT     4
#define TRACK_ALBUM    0x34
#define TRACK_DBID     0x108
/* The playlists (re/playlist-art.md). */
#define DB_PLAYLIST_FIRST 0x2c            /* the first playlist; playlist + 0x00 is the next one */
#define PL_ROOT        0x28               /* the root node of the items */
#define PL_NAME_POOL   0xb4               /* the name pool in the playlist object */
#define PL_NAME_INDEX  0xe0               /* the pool index of the name */
#define NODE_FIRST     0x20               /* root or group: the first child */
#define NODE_COUNT     0x32               /* root: u16 count of items */
#define ITEM_NEXT      0x08
#define ITEM_TRACK     0x20
#define COLLAGE_SLOTS  16
#define WALK_MAX       4000               /* the most items that one walk reads */
#define NAME_BYTES     512                /* UTF-16 bytes of an album name that the patch reads */
/* The folders of the patch playlist-folders. The same limits as playlist_folders.c. */
#define FOLDERS_MAX    64
#define FOLDER_NAME_MAX 63
#define FOLDERS_FILE_MAX 0x10000
#define READ_EOF       (-0x27)            /* 0x8f464: the file has fewer bytes than asked */
#define FOLDERS_NO_ICONS 2                /* the flags of the file: the switch Folder Icons is off */
#define FOLDER_KEY     0xf81f             /* a transparent pixel of folder_px */

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

/* The cache file: all thumbnails from the artwork, written by the patch. */
#define CACHE_PATH     "iPod_Control\\iTunes\\iPodFirmAlbumCache"
#define STAMP_BYTES    0x40               /* the start of ArtworkDB in the stamp (the mhfd header) */
static int cache_state;                   /* 0 = not examined, 1 = valid and in memory, -1 = none */
static int cache_written;                 /* 1: the patch wrote the cache for the current stamp */
static unsigned cache_stamp;              /* the stamp of the artwork and the albums now */
static unsigned cache_count;
static Entry *cache_index;                /* sorted by hash; offset = the index of the thumbnail */
static unsigned short *cache_px;          /* cache_count thumbnails of TH x TH */

/* The collages of the playlists (version 3.0). A slot keeps the hash of the playlist name, the
 * playlist, its item count when the collage was made, and the collage. */
typedef struct {
    unsigned hash;                        /* 0: the slot is empty */
    char *playlist;                       /* 0: no playlist with this name */
    unsigned count;
    int state;                            /* 1: px is the collage, -1: no album thumbnail */
    unsigned short px[TH * TH];
} Collage;
static Collage *collages;                 /* COLLAGE_SLOTS slots, or 0 */
static unsigned collage_next;

/* The open F1028_N.ithmb file (refer to the comment at the top). */
#define ART_CLOSE_US   30000000           /* close the file 30 s after the last read */
static unsigned art_fh[0x30 / 4];
static int art_fh_file;                   /* N of the open file, or 0 */
static unsigned art_used;                 /* USEC_NOW at the last read */

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

/* The albums of the library: the hashes in the order of the list (row_hash) and sorted
 * (album_hashes). The row "All" is not an album. */
static unsigned *album_hashes;
static unsigned *row_hash;
static unsigned album_count;
static int *album_rows;                   /* the album list of the library when the hashes were made */
static int albums_state;                  /* 0 = not made, 1 = made, -1 = not known */

/* The late fill. While the wheel moves, a row whose thumbnail needs the disk gets an empty square.
 * The wheel event with the step 0 (the end of the movement) draws the list again. */
#define EV_WHEEL        0xf               /* word 3: +1 or -1 for each step, 0 at the end */
#define EV_TICK         0xd               /* comes to the lists: each 240 ms in the emulator, each 3-4 s on the iPod */
#define EV_TIMER        9                 /* word 2: the timer */
#define LIST_TIMER      0xcc              /* the 100 ms timer of the list (0x23b97c): the blink of the selected row */
#define TIMER_LOST_US   500000            /* a timer start older than this without its event is lost */
#define KEY_PAUSE_US    1000000           /* after a key push, the list can use its timer for the blink */
#define EV_KEY_DOWN     4
#define EV_KEY_REPEAT   5
#define MOVE_LIMIT_US   300000            /* an older step does not count: the end event can fail */
#define BROWSE_LIST_CLASS 0x677290         /* vtable of a browse list (the Albums list) */
#define VIEW_FLAGS_WORD 8                 /* word index: bits 0x1800 are 0x800 if the view is visible */
#define USEC_NOW        (*(volatile unsigned *)0x60005010)
static int moving;                        /* 1: the wheel moves (set by hook_list_event) */
static unsigned step_time;                /* USEC_NOW at the last step */
static int waiting;                       /* 1: a row has an empty square */
static unsigned last_album_hash;          /* the last album row that was drawn */
static int *album_list;                   /* the browse list of that row (only compared, not read) */
static int timer_on;                      /* 1: the patch started the list timer, its event did not come */
static unsigned timer_started;
static unsigned key_time;                 /* USEC_NOW at the last key push to a list */

/* ---------- the measurement (versions 2.2 to 3.1; off since version 3.2) ----------
 * With ALBUM_ART_STATS 1, the patch counts and times its parts with USEC_TIMER. After each
 * STATS_EVERY album or playlist row draws, it writes one record to the file STATS_PATH. Record N is
 * at offset N * sizeof stats, thus the file shows the change in time. The write can stop the scroll
 * for a short time. re/album-art-stats.py reads the file. To measure again, set ALBUM_ART_STATS to 1,
 * increase "version" and measure "size" in patch.json. Refer to re/album-art-v2.md, "The
 * measurement: how to switch it on again". */
#define ALBUM_ART_STATS 0
#if ALBUM_ART_STATS
#define USEC_TIMER    (*(volatile unsigned *)0x60005010)
#define STATS_PATH    "iPod_Control\\iTunes\\iPodFirmAlbumArtStats"
#define STATS_EVERY   256                 /* a power of 2 */
#define STATS_RECORDS 128

/* The timed parts. re/album-art-stats.py uses the same order. */
enum {
    T_ALBUM_ROW,                          /* all of draw_with_thumbnail for an album or playlist row */
    T_OTHER_ROW,                          /* the original draw of a different list row (reference) */
    T_ORIGINAL_SHIFTED,                   /* the original draw with the left edge moved */
    T_ORIGINAL_PLAIN,                     /* the original draw of an album row with no thumbnail */
    T_BUILD_ART, T_LOAD, T_CHECK_FILE,
    T_ART_FILL,                           /* a thumbnail from the ithmb file: read and average */
    T_FILE_READ,                          /* a thumbnail read from the iPodFirmAlbumArt file */
    T_BLIT, T_RUNS,
    T_ART_OPEN,                           /* an open of F1028_N.ithmb (version 2.8) */
    T_CACHE_LOAD, T_CACHE_WRITE,          /* the cache file (version 2.8) */
    T_COLLAGE,                            /* a playlist collage: find, walk and make (version 3.0) */
    T_COUNT
};
typedef struct { unsigned count, total_us, max_us; } Timer;
static struct {
    unsigned magic, version, record, time_us;     /* "AAST", 6, the record number, USEC_TIMER */
    Timer t[T_COUNT];
    unsigned art_hits, art_failed, file_all_hits, file_cache_hits, db_loaded_calls;
    unsigned cache_hits, art_closes, collage_hits;
    unsigned alloc_failed;                        /* a bit for each allocation that failed */
    unsigned art_state, art_count, art_slots;
    unsigned file_state, file_count, file_size, file_all, file_cache;
    unsigned write_errors, waits, ends, redraws, prefills;
    unsigned cache_state, cache_count, cache_written, cache_errors;
} stats;

static void stat_add(int i, unsigned start)
{
    unsigned d = USEC_TIMER - start;
    Timer *t = &stats.t[i];
    t->count++;
    t->total_us += d;
    if (d > t->max_us)
        t->max_us = d;
}
#define STAT_NOW()         USEC_TIMER
#define STAT_ADD(i, start) stat_add(i, start)
#define STAT_COUNT(field)  (stats.field++)
#else
#define STAT_NOW()         0u
#define STAT_ADD(i, start) ((void)(start))
#define STAT_COUNT(field)  ((void)0)
#endif

/* fw_alloc. The measurement records a failed allocation with the bit `id`. */
COLD static void *alloc(unsigned size, unsigned id)
{
    void *p = fw_alloc(size);
#if ALBUM_ART_STATS
    if (!p)
        stats.alloc_failed |= id;
#else
    (void)id;
#endif
    return p;
}

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

/* Closes the open F1028_N.ithmb file, if a file is open. */
COLD static void art_close(void)
{
    if (art_fh_file) {
        file_close(art_fh);
        art_fh_file = 0;
        STAT_COUNT(art_closes);
    }
}

/* Opens F1028_N.ithmb, if it is not open. Another file closes first. Returns 0 if correct. */
COLD static int art_open(int number)
{
    unsigned t0;
    if (art_fh_file == number)
        return 0;
    art_close();
    t0 = STAT_NOW();
    if (open_path(art_fh, ITHMB_PATH, number) != 0)
        return -1;
    STAT_ADD(T_ART_OPEN, t0);
    art_fh_file = number;
    return 0;
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

COLD static void load_file(void)
{
    unsigned header[4];
    int i;

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
    index = alloc(count * sizeof(Entry), 1);
    if (!index || read_file(16, index, count * sizeof(Entry)) != 0)
        return;
    data_start = 16 + count * sizeof(Entry);
    if (count * size * size * 2 <= LOAD_ALL_MAX) {
        all_pixels = alloc(count * size * size * 2, 2);
        if (all_pixels && read_file(data_start, all_pixels, count * size * size * 2) != 0) {
            fw_free(all_pixels);
            all_pixels = 0;
        }
    }
    if (!all_pixels) {
        cache_pixels = alloc(CACHE_SLOTS * size * size * 2, 4);
        if (!cache_pixels)
            return;
    }
    state = 1;
}

COLD static void load(void)
{
    unsigned t0;
    if (state != 0)
        return;
    t0 = STAT_NOW();
    load_file();
    STAT_ADD(T_LOAD, t0);
}

/* Reads the header again. If the file changed, releases it so that the next load reads the new
 * file. */
COLD static void check_for_new_file(void)
{
    unsigned header[4], t0 = STAT_NOW();
    int i;
    if (read_file(0, header, sizeof header) == 0)  /* no file now: keep the loaded thumbnails */
        for (i = 0; i < 4; i++)
            if (header[i] != loaded_header[i]) {
                unload();
                break;
            }
    STAT_ADD(T_CHECK_FILE, t0);
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
    unsigned i, t0;
    int err;
    if (all_pixels) {
        STAT_COUNT(file_all_hits);
        return all_pixels + ((e->offset - data_start) >> 1);
    }
    for (i = 0; i < CACHE_SLOTS; i++)
        if (cache_hash[i] == e->hash && e->hash != 0) {
            STAT_COUNT(file_cache_hits);
            return cache_pixels + i * n;
        }
    i = cache_next;
    cache_next = (cache_next + 1) & (CACHE_SLOTS - 1);
    cache_hash[i] = 0;
    t0 = STAT_NOW();
    err = read_file(e->offset, cache_pixels + i * n, n * 2);
    STAT_ADD(T_FILE_READ, t0);
    if (err != 0)
        return 0;
    cache_hash[i] = e->hash;
    return cache_pixels + i * n;
}

/* ---------- the artwork of the iPod ---------- */

COLD static void free_art(void)
{
    art_close();
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

/* The FNV-1a hash (from `h`) of the UTF-8 form of a UTF-16 name, as the label text gives it. */
COLD static unsigned name_hash(const unsigned short *name, int n, unsigned h)
{
    unsigned c;
    int k;
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

/* The same hash of a name in a pool. Returns 0 for an empty name. */
COLD static unsigned pool_hash(void *pool, int pool_index, unsigned h, unsigned short *name)
{
    int length = 0, n;
    pool_copy(pool, pool_index, name, &length, NAME_BYTES);
    n = length >> 1;
    return n > 0 ? name_hash(name, n, h) : 0;
}

/* The hash of an album name in the album pool of the database. */
COLD static unsigned album_hash(char *db, int pool_index, unsigned short *name)
{
    return pool_hash(db + DB_ALBUM_POOL, pool_index, FNV_BASIS, name);
}

COLD static void free_album_hashes(void)
{
    fw_free(album_hashes);
    fw_free(row_hash);
    album_hashes = 0;
    row_hash = 0;
    album_count = 0;
    album_rows = 0;
    albums_state = 0;
}

/* Makes the sorted hashes of the albums of the library. Sets albums_state to 1 or -1. */
COLD static void make_album_hashes(void)
{
    char *library, *db;
    int *rows;
    unsigned short *name;
    unsigned n, i, j, gap;

    free_album_hashes();
    albums_state = -1;
    if (!PROVIDER)
        return;
    library = lib_resolve(*(void **)(PROVIDER + PROVIDER_LIBRARY));
    if (!library || !(db = *(char **)(library + LIBRARY_DB)))
        return;
    rows = *(int **)(library + LIBRARY_ALBUMS);
    n = *(unsigned *)(library + LIBRARY_ALBUM_COUNT);
    if (!rows || n == 0 || n > 0xffff)
        return;
    name = alloc(NAME_BYTES, 1024);
    album_hashes = alloc(n * 4, 2048);
    row_hash = alloc(n * 4, 4096);
    if (!name || !album_hashes || !row_hash) {
        fw_free(name);
        free_album_hashes();
        albums_state = -1;
        return;
    }
    for (i = 0; i < n; i++)
        row_hash[i] = album_hashes[i] = album_hash(db, rows[i], name);
    fw_free(name);
    for (gap = n >> 1; gap > 0; gap >>= 1)        /* shell sort */
        for (i = gap; i < n; i++) {
            unsigned v = album_hashes[i];
            for (j = i; j >= gap && album_hashes[j - gap] > v; j -= gap)
                album_hashes[j] = album_hashes[j - gap];
            album_hashes[j] = v;
        }
    album_count = n;
    album_rows = rows;
    albums_state = 1;
}

/* Makes the album hashes if they are not made, or if the album list of the library changed. */
COLD static void albums_ready(void)
{
    char *library = PROVIDER ? lib_resolve(*(void **)(PROVIDER + PROVIDER_LIBRARY)) : 0;
    /* The library makes its album list when the Albums list opens the first time. Thus try
       again after a failure (-1) when the list exists (emulator, 27 October 2026). */
    if (albums_state == 0 ||
        (albums_state == -1 && library && *(int **)(library + LIBRARY_ALBUMS)) ||
        (albums_state == 1 && library &&
         (*(int **)(library + LIBRARY_ALBUMS) != album_rows ||
          *(unsigned *)(library + LIBRARY_ALBUM_COUNT) != album_count)))
        make_album_hashes();
}

/* The music database, or 0. */
COLD static char *music_db(void)
{
    char *library = PROVIDER ? lib_resolve(*(void **)(PROVIDER + PROVIDER_LIBRARY)) : 0;
    return library ? *(char **)(library + LIBRARY_DB) : 0;
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
COLD static void make_art_table(void)
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
    name = alloc(NAME_BYTES, 8);
    keys = alloc(tracks * sizeof(TrackKey), 16);
    art = alloc(tracks * sizeof(Art), 32);
    window = alloc(WINDOW, 64);
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
    art_pixels = alloc(art_slots * TH * TH * 2, 128);
    slot_owner = alloc(art_slots * 2, 256);
    art_buffer = alloc(ART_SIZE * ART_SIZE * 2, 512);
    if (!art_pixels || !slot_owner || !art_buffer) {
        free_art();
        art_state = -1;
        return;
    }
    for (i = 0; i < art_slots; i++)
        slot_owner[i] = NO_SLOT;
    art_state = 1;
}

COLD static void build_art(void)
{
    unsigned t0 = STAT_NOW();
    make_art_table();
    STAT_ADD(T_BUILD_ART, t0);
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
    unsigned s, t0;
    int bad;
    if (a->slot < art_slots) {
        STAT_COUNT(art_hits);
        return art_pixels + a->slot * TH * TH;
    }
    if (a->slot == FAILED) {
        STAT_COUNT(art_failed);
        return 0;
    }
    t0 = STAT_NOW();
    s = art_next;
    art_next = art_next + 1 == art_slots ? 0 : art_next + 1;
    if (slot_owner[s] != NO_SLOT)               /* the oldest thumbnail gives its slot */
        art[slot_owner[s]].slot = NO_SLOT;
    slot_owner[s] = NO_SLOT;
    bad = art_open(a->file);              /* the file stays open for the next cover */
    if (bad == 0)
        bad = read_at(art_fh, a->offset, art_buffer, ART_SIZE * ART_SIZE * 2);
    art_used = USEC_NOW;
    if (bad) {
        art_close();                      /* the next cover opens the file again */
        a->slot = FAILED;
        STAT_COUNT(art_failed);
        return 0;
    }
    shrink(art_buffer, art_pixels + s * TH * TH);
    STAT_ADD(T_ART_FILL, t0);
    slot_owner[s] = (unsigned short)n;
    a->slot = (unsigned short)s;
    return art_pixels + s * TH * TH;
}

/* The background fill: makes one thumbnail that is not in memory. It starts at the last album
 * row that was drawn and goes up and down the album list. Returns 1 if it read a cover. */
COLD static int prefill_one(void)
{
    int c, k, i, n, count2;
    if (art_state != 1 || slot_owner[art_next] != NO_SLOT)
        return 0;                         /* no table, or the memory is full: do not push out covers */
    albums_ready();
    if (albums_state != 1)
        return 0;
    for (c = 0; c < (int)album_count && row_hash[c] != last_album_hash; c++)
        ;
    if (c == (int)album_count)
        c = 0;
    count2 = 2 * (int)album_count;
    for (k = 0; k < count2; k++) {
        i = (k & 1) ? c - ((k + 1) >> 1) : c + (k >> 1);    /* c, c - 1, c + 1, c - 2, ... */
        if (i < 0 || i >= (int)album_count)
            continue;
        n = art_find(row_hash[i]);
        if (n >= 0 && art[n].slot == NO_SLOT) {
            art_thumb(n);
            return 1;
        }
    }
    return 0;
}

/* ---------- the cache file ---------- */

/* The stamp of the cache: the FNV-1a hash of the first STAMP_BYTES of ArtworkDB (the mhfd header
 * has the length of the file and the next image ID) and of the album names of all tracks (the
 * album pool db + DB_ALBUM_POOL). Thus a sync that changes the artwork or the albums gives a
 * different stamp. Version 3.0: the album pool exists from the start. Version 2.9 used the album
 * list of the library, which exists only after the first open of the Albums list. The pool has
 * + 0x08: a handle of the entries {offset, length}, + 0x10: a handle of the UTF-16 data,
 * + 0x14: the count of entries; a free entry has bit 31 set in its offset (0x88a00).
 * Returns 0 if the stamp is not known; *later is 1 if the database is not ready yet. */
COLD static unsigned art_stamp(int *later)
{
    unsigned fh[0x30 / 4], i, k, h = FNV_BASIS, slots;
    unsigned char b[STAMP_BYTES];
    char *db = music_db(), *pool;
    const unsigned *entries;
    const unsigned char *data;
    int err;
    *later = 1;
    if (!db)
        return 0;
    pool = db + DB_ALBUM_POOL;
    if (!*(void **)(pool + 8) || !*(void **)(pool + 0x10))
        return 0;
    entries = **(const unsigned ***)(pool + 8);
    data = **(const unsigned char ***)(pool + 0x10);
    slots = *(unsigned *)(pool + 0x14);
    if (!entries || !data || slots == 0)
        return 0;
    *later = 0;
    if (slots > 0x40000 || open_path(fh, ART_DB_PATH, 0) != 0)
        return 0;
    err = read_at(fh, 0, b, STAMP_BYTES);
    file_close(fh);
    if (err != 0 || get32(b) != TAG('m', 'h', 'f', 'd'))
        return 0;
    for (i = 0; i < STAMP_BYTES; i++)
        h = (h ^ b[i]) * FNV_PRIME;
    for (i = 0; i < slots; i++) {
        unsigned off = entries[2 * i], len = entries[2 * i + 1];
        if ((off & 0x80000000u) || len > NAME_BYTES)
            continue;
        h = (h ^ len) * FNV_PRIME;
        for (k = 0; k < len; k++)
            h = (h ^ data[off + k]) * FNV_PRIME;
    }
    return h ? h : 1;
}

COLD static void free_cache(void)
{
    fw_free(cache_index);
    fw_free(cache_px);
    cache_index = 0;
    cache_px = 0;
    cache_count = 0;
    cache_state = 0;
}

/* Reads the cache file into memory if its stamp is the stamp of the artwork and the albums now.
 * Sets cache_state to 1 or -1. */
COLD static void cache_load(void)
{
    unsigned fh[0x30 / 4], header[4], n, t0 = STAT_NOW();
    int later;
    free_cache();
    cache_state = -1;
    cache_stamp = art_stamp(&later);
    if (!cache_stamp && later)
        cache_state = 0;                  /* the database is not ready: try again later */
    if (!cache_stamp || open_path(fh, CACHE_PATH, 0) != 0) {
        STAT_ADD(T_CACHE_LOAD, t0);
        return;
    }
    n = 0;
    if (read_at(fh, 0, header, sizeof header) == 0 && header[0] == 0x54414649u &&   /* "IFAT" */
        header[1] == (1u | TH << 16) && header[3] == cache_stamp && header[2] <= ART_MAX_SLOTS)
        n = header[2];
    if (n) {
        cache_index = alloc(n * sizeof(Entry), 8192);
        cache_px = alloc(n * TH * TH * 2, 16384);
        if (cache_index && cache_px && read_at(fh, 16, cache_index, n * sizeof(Entry)) == 0 &&
            read_at(fh, 16 + n * sizeof(Entry), cache_px, n * TH * TH * 2) == 0) {
            cache_count = n;
            cache_state = 1;
        }
    }
    file_close(fh);
    if (cache_state != 1) {
        free_cache();
        cache_state = -1;
    }
    STAT_ADD(T_CACHE_LOAD, t0);
}

/* The thumbnail of an album in the valid cache, or 0. The offset of an entry is the file offset
 * of its pixels. The file is longer than the data if an earlier cache was larger. */
COLD static const unsigned short *cache_find(unsigned hash)
{
    unsigned lo = 0, hi = cache_count, base = 16 + cache_count * sizeof(Entry), off;
    if (cache_state != 1)
        return 0;
    while (lo < hi) {
        unsigned mid = (lo + hi) >> 1;
        if (cache_index[mid].hash < hash)
            lo = mid + 1;
        else
            hi = mid;
    }
    if (lo == cache_count || cache_index[lo].hash != hash)
        return 0;
    off = cache_index[lo].offset - base;
    if (cache_index[lo].offset < base || off > (cache_count - 1) * TH * TH * 2 || (off & 1))
        return 0;
    STAT_COUNT(cache_hits);
    return cache_px + (off >> 1);
}

/* 1: each album with artwork has its thumbnail in memory. A cover that failed does not count. */
COLD static int all_filled(void)
{
    unsigned i;
    if (art_state != 1)
        return 0;
    for (i = 0; i < art_count; i++)
        if (art[i].slot >= art_slots && art[i].slot != FAILED)
            return 0;
    return 1;
}

/* Writes the thumbnails in memory to the cache file. `art` is sorted by hash and has one entry for
 * each album, thus the index is sorted. The header is written last: a write that stops leaves the
 * stamp 0, and the next load does not use the file. The patch tries one time for each stamp. */
COLD static void cache_write(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], header[4], len, want, i, k, n = 0, base;
    unsigned t0 = STAT_NOW();
    Entry *idx;
    int err;
    cache_written = 1;
    for (i = 0; i < art_count; i++)
        if (art[i].slot < art_slots)
            n++;
    if (n == 0 || !cache_stamp || !(idx = alloc(n * sizeof(Entry), 32768)))
        return;
    base = 16 + n * sizeof(Entry);
    for (i = k = 0; i < art_count; i++)
        if (art[i].slot < art_slots) {
            idx[k].hash = art[i].hash;
            idx[k].offset = base + k * TH * TH * 2;
            k++;
        }
    header[0] = 0x54414649u;              /* "IFAT" */
    header[1] = 1u | TH << 16;
    header[2] = n;
    header[3] = 0;                        /* not valid until the end */
    fw_memset0(path, sizeof path);
    fw_strcpy((char *)path + 4, CACHE_PATH);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err == 0) {
        err = file_seek(fh, 0, 0);
        len = want = sizeof header;
        if (err == 0)
            err = file_write(fh, &len, header) != 0 || len != want;
        len = want = n * sizeof(Entry);
        if (err == 0)
            err = file_write(fh, &len, idx) != 0 || len != want;
        for (i = 0; err == 0 && i < art_count; i++)
            if (art[i].slot < art_slots) {
                len = want = TH * TH * 2;
                err = file_write(fh, &len, art_pixels + art[i].slot * TH * TH) != 0 || len != want;
            }
        header[3] = cache_stamp;
        if (err == 0)
            err = file_seek(fh, 0, 0);
        len = want = sizeof header;
        if (err == 0)
            err = file_write(fh, &len, header) != 0 || len != want;
        if (file_close(fh) != 0)
            err = -1;
    }
    fw_free(idx);
    STAT_ADD(T_CACHE_WRITE, t0);
#if ALBUM_ART_STATS
    if (err != 0)
        stats.cache_errors++;
#endif
}

/* The background fill has no more work: close the artwork file, and write the cache if each
 * album with artwork is in memory. If not (more albums than ART_MAX_SLOTS, or an album that is
 * not in the album list), the fill cannot complete: do not try again for this stamp. */
COLD static void fill_done(void)
{
    art_close();
    if (art_state != 1 || cache_written || cache_state == 1)
        return;
    if (all_filled())
        cache_write();
    else
        cache_written = 1;
}

/* Starts the 100 ms timer of the list for the patch, if the patch did not start it already. The
 * list uses this timer for the blink of the selected row after a push of Select (0x23b704: method
 * +0x184, count at list + 0xf8). Thus the patch does not start it shortly after a key push. The
 * list stops its timer when it is deleted. Its event comes to hook_list_event. */
COLD static void start_tick(int *list)
{
    if (USEC_NOW - key_time < KEY_PAUSE_US)
        return;
    if (timer_on && USEC_NOW - timer_started < TIMER_LOST_US)
        return;
    timer_on = 1;
    timer_started = USEC_NOW;
    timer_start((char *)list + LIST_TIMER);
}

/* 1: the background fill has work: the table is made and a slot is free. Or the fill is complete
 * and the cache is not written. */
COLD static int fill_has_work(void)
{
    return art_state == 1 && (slot_owner[art_next] == NO_SLOT || (!cache_written && cache_state != 1));
}

/* ---------- the folders of playlist-folders ---------- */

/* The icon of a folder row. Source: re/playlist-folders/folder-icon.png. The script
 * re/playlist-folders/make-folder-icon.py writes this array. */
static const unsigned short folder_px[TH * TH] __attribute__((aligned(4))) = {
    0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f,
    0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f,
    0xf81f, 0xf81f, 0xf81f, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f,
    0xf81f, 0xf81f, 0x1af5, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x1af5, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f,
    0xf81f, 0x1af5, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0xf81f, 0xf81f,
    0xf81f, 0x1af5, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x245b, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0xdf7f, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x455d, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x555d, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x655d, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x65dd, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x75dd, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x8e7d, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xbeff, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x8e7f, 0x1af5, 0xf81f,
    0xf81f, 0x1af5, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0xaeff, 0x1af5, 0xf81f,
    0xf81f, 0xf81f, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0x1af5, 0xf81f, 0xf81f,
    0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f, 0xf81f,
};

static unsigned folder_hash[FOLDERS_MAX];
static int folder_total;
static int folders_read;                  /* 1: folder_hash agrees with the file */

/* Keeps the hash of each folder name, as a playlist row gives it. The format is in
 * playlist_folders.c. With no file, or with the switch Folder Icons off, no row is a folder here. */
COLD static void load_folders(void)
{
    unsigned fh[0x30 / 4], got = FOLDERS_FILE_MAX, at = 12, k, n;
    unsigned char *b;
    int rc;

    folders_read = 1;
    folder_total = 0;
    if (open_path(fh, FOLDERS_PATH, 0) != 0)
        return;
    b = alloc(FOLDERS_FILE_MAX, 131072);
    rc = b ? file_read(fh, &got, b) : -1;
    file_close(fh);
    if (b && (rc == 0 || rc == READ_EOF) && got >= 12 && got <= FOLDERS_FILE_MAX
        && b[0] == 'I' && b[1] == 'F' && b[2] == 'P' && b[3] == 'F' && *(unsigned short *)(b + 4) == 1) {
        n = *(unsigned short *)(b + 6) & FOLDERS_NO_ICONS ? 0 : *(unsigned short *)(b + 8);
        for (k = 0; k < n && k < FOLDERS_MAX; k++) {
            unsigned units, members, name_bytes;
            if (at + 8 > got)
                break;
            units = *(unsigned short *)(b + at + 2);
            members = *(unsigned short *)(b + at + 4);
            name_bytes = (units * 2 + 3) & ~3u;
            if (units == 0 || units > FOLDER_NAME_MAX || at + 8 + name_bytes + members * 8 > got)
                break;
            folder_hash[folder_total++] = name_hash((const unsigned short *)(b + at + 8), (int)units, PLAYLIST_BASIS);
            at += 8 + name_bytes + members * 8;
        }
    }
    fw_free(b);
}

/* 1: the playlist row with the hash `h` is a folder. */
COLD static int is_folder(unsigned h)
{
    int i;
    if (!folders_read)
        load_folders();
    for (i = 0; i < folder_total; i++)
        if (folder_hash[i] == h)
            return 1;
    return 0;
}

/* ---------- the draw ---------- */

/* Draws the thumbnail with runs of pixels that have the same colour. The runs of the colour `key`
 * stay transparent (key -1: no transparent colour). The patch uses this only for the folder icon,
 * and if the target bitmap is not RGB565. */
COLD static void draw_runs(void *gc, const unsigned short *px, int ts, int top, int left, int key)
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
            if (c == key) {
                x = end;
                continue;
            }
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
    unsigned t0 = STAT_NOW();
    Rect s, d;

    /* Mode 0 replaces the pixels. Mode 1 blends with the background, so on a dark theme the
       thumbnail is not visible. */
    gc_set_mode(gc, 0);
    if (!target || target[3] != 16 || (target[5] & 0xdfff) != 0x565 || ((unsigned)px & 3) || (ts & 1)) {
        draw_runs(gc, px, ts, top, left, -1);
        STAT_ADD(T_RUNS, t0);
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
    STAT_ADD(T_BLIT, t0);
}

typedef void (*draw_fn)(void *view, const char *text, void *a3);

/* 1: the thumbnail of the file entry is in memory (no disk read). */
COLD static int file_in_memory(const Entry *e)
{
    int i;
    if (all_pixels)
        return 1;
    for (i = 0; i < CACHE_SLOTS; i++)
        if (cache_hash[i] == e->hash && e->hash != 0)
            return 1;
    return 0;
}

/* 1: the wheel moved in the last MOVE_LIMIT_US. */
COLD static int wheel_moves(void)
{
    if (moving && USEC_NOW - step_time >= MOVE_LIMIT_US)
        moving = 0;
    return moving;
}

/* An empty square in place of a thumbnail that comes later. */
COLD static void draw_empty(void *gc, int ts, int top, int left)
{
    static const unsigned char grey[4] = { 0x80, 0x80, 0x80, 0xff };
    Rect q;
    q.top = top;
    q.left = left;
    q.bottom = top + ts;
    q.right = left + ts;
    gc_set_mode(gc, 0);
    gc_set_color(gc, grey);
    gc_fill_rect(gc, &q);
}

#if ALBUM_ART_STATS
/* Writes one record of the measurement to STATS_PATH at the offset of the record. */
COLD static void write_stats(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = sizeof stats, offset;
    int err;
    stats.magic = 0x54534141u;            /* "AAST" */
    stats.version = 6;                    /* 6: with the playlist collages (version 3.0) */
    stats.time_us = USEC_TIMER;
    stats.art_state = (unsigned)art_state;
    stats.art_count = art_count;
    stats.art_slots = art_slots;
    stats.file_state = (unsigned)state;
    stats.file_count = count;
    stats.file_size = size;
    stats.file_all = all_pixels != 0;
    stats.file_cache = cache_pixels != 0;
    stats.cache_state = (unsigned)cache_state;
    stats.cache_count = cache_count;
    stats.cache_written = cache_written;
    offset = stats.record * sizeof stats;
    fw_memset0(path, sizeof path);
    fw_strcpy((char *)path + 4, STATS_PATH);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err == 0) {
        err = file_seek(fh, 0, offset);
        if (err == 0)
            err = file_write(fh, &len, &stats);
        if (file_close(fh) != 0)
            err = -1;
    }
    if (err != 0)
        stats.write_errors++;             /* the next record shows it */
    if (stats.record + 1 < STATS_RECORDS)
        stats.record++;
}
#endif

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

/* ---------- the playlist collages (version 3.0, re/playlist-art.md) ---------- */

static char *collage_db;                  /* the database of the collages in `collages` */

COLD static void free_collages(void)
{
    fw_free(collages);
    collages = 0;
    collage_next = 0;
    collage_db = 0;
}

/* The item count of a playlist (root + NODE_COUNT). */
COLD static unsigned playlist_count(char *pl)
{
    char *root = *(char **)(pl + PL_ROOT);
    return root ? *(unsigned short *)(root + NODE_COUNT) : 0;
}

/* The playlist whose name has the hash `h` (the hash of a playlist row), or 0. The list at
 * db + DB_PLAYLIST_FIRST also has On-The-Go and the hidden playlists. */
COLD static char *find_playlist(char *db, unsigned h, unsigned short *name)
{
    char *pl = *(char **)(db + DB_PLAYLIST_FIRST);
    int k, index;
    for (k = 0; pl && k < 1000; k++, pl = *(char **)pl) {
        index = *(int *)(pl + PL_NAME_INDEX);
        if (index > 0 && pool_hash(pl + PL_NAME_POOL, index, PLAYLIST_BASIS, name) == h)
            return pl;
    }
    return 0;
}

/* The TH x TH thumbnail of an album, in the order of the album rows: the file of iPodFirm, the
 * cache, then the artwork. Without `disk`, a thumbnail that needs the disk sets *need. */
COLD static const unsigned short *album_px(unsigned h, int disk, int *need)
{
    const Entry *e;
    const unsigned short *p;
    int n;
    if ((e = find(h)) != 0 && size == TH) {
        if (!disk && !file_in_memory(e)) {
            *need = 1;
            return 0;
        }
        if ((p = pixels(e)) != 0)
            return p;
    }
    if ((p = cache_find(h)) != 0)
        return p;
    if (cache_state == 1)
        return 0;                         /* a valid cache has each album with artwork */
    if (art_state == 0) {
        if (!disk) {
            *need = 1;
            return 0;
        }
        build_art();
    }
    if ((n = art_find(h)) < 0 || art[n].slot == FAILED)
        return 0;
    if (art[n].slot < art_slots)
        return art_pixels + art[n].slot * TH * TH;
    if (!disk) {
        *need = 1;
        return 0;
    }
    return art_thumb(n);
}

/* The average of 4 RGB565 pixels, rounded. The channels are spread apart in one word. */
static unsigned short avg4(unsigned a, unsigned b, unsigned c, unsigned d)
{
    unsigned s = ((a | a << 16) & 0x07e0f81fu) + ((b | b << 16) & 0x07e0f81fu) +
                 ((c | c << 16) & 0x07e0f81fu) + ((d | d << 16) & 0x07e0f81fu) + 0x00401002u;
    s = (s >> 2) & 0x07e0f81fu;
    return (unsigned short)(s | s >> 16);
}

/* Makes the collage of a playlist in `dst`, as iPodFirm does (MusicImport.playlistArt): the first
 * 4 different albums that have a thumbnail, in the playlist order, in a 2 x 2 square. With 1 to 3
 * albums, the first thumbnail alone. Returns 1 if made, 0 if no album has a thumbnail, and -1 if
 * a thumbnail needs the disk and `disk` is 0. A podcast playlist has groups: a child of the root
 * can be a group (its first child has the playlist at + 0x00, a track has the db there). */
COLD static int make_collage(char *db, char *pl, unsigned short *dst, int disk, unsigned short *name)
{
    const unsigned short *px[4];
    unsigned albums[4];
    int found = 0, steps = 0, need = 0, i, k, x, y;
    char *root = *(char **)(pl + PL_ROOT), *item, *group = 0;

    if (cache_state == 0) {
        if (!disk)
            return -1;
        cache_load();
    }
    item = root ? *(char **)(root + NODE_FIRST) : 0;
    while (item && found < 4 && steps++ < WALK_MAX) {
        char *track = *(char **)(item + ITEM_TRACK);
        if (track && *(char **)track != db) {
            if (!group && *(char **)track == pl) {
                group = item;             /* go into the group */
                item = track;
                continue;
            }
            track = 0;
        }
        if (track) {
            /* Compare the hashes, not the pool indexes: two tracks of one album can have
               different indexes (emulator, 27 October 2026). */
            unsigned h = album_hash(db, *(int *)(track + TRACK_ALBUM), name);
            for (i = 0; i < found && albums[i] != h; i++)
                ;
            if (h && i == found) {
                const unsigned short *p = album_px(h, disk, &need);
                if (need)
                    return -1;
                if (p) {
                    albums[found] = h;
                    px[found++] = p;
                }
            }
        }
        item = *(char **)(item + ITEM_NEXT);
        if (!item && group) {             /* the end of a group: the next child of the root */
            item = *(char **)(group + ITEM_NEXT);
            group = 0;
        }
    }
    if (found == 0)
        return 0;
    if (found < 4) {
        for (k = 0; k < TH * TH; k++)
            dst[k] = px[0][k];
        return 1;
    }
    for (k = 0; k < 4; k++) {             /* 1 2 in the top row, 3 4 in the bottom row */
        unsigned short *d = dst + (k >> 1) * (TH / 2) * TH + (k & 1) * (TH / 2);
        for (y = 0; y < TH / 2; y++)
            for (x = 0; x < TH / 2; x++) {
                const unsigned short *p = px[k] + 2 * y * TH + 2 * x;
                d[y * TH + x] = avg4(p[0], p[1], p[TH], p[TH + 1]);
            }
    }
    return 1;
}

/* The collage of the playlist row with the hash `h`, or 0. The collage is made at the first draw
 * of the row, and again when the item count of the playlist changes (On-The-Go, a live smart
 * playlist). While the wheel moves, a collage that needs the disk waits (*wait). */
COLD static const unsigned short *playlist_collage(unsigned h, int busy, int *wait)
{
    Collage *c = 0;
    char *db = music_db();
    unsigned short *name;
    unsigned t0;
    int i, r;

    if (!db)
        return 0;
    if (collages && collage_db != db)
        free_collages();                  /* a new database */
    if (!collages) {
        collages = alloc(COLLAGE_SLOTS * sizeof(Collage), 65536);
        if (!collages)
            return 0;
        fw_memset0(collages, COLLAGE_SLOTS * sizeof(Collage));
        collage_db = db;
    }
    for (i = 0; i < COLLAGE_SLOTS; i++)
        if (collages[i].hash == h) {
            c = &collages[i];
            break;
        }
    if (c && (!c->playlist || playlist_count(c->playlist) == c->count)) {
        if (c->state != 1)
            return 0;
        STAT_COUNT(collage_hits);
        return c->px;
    }
    t0 = STAT_NOW();
    if (!(name = alloc(NAME_BYTES, 1024)))
        return 0;
    if (!c) {
        c = &collages[collage_next];
        collage_next = (collage_next + 1) & (COLLAGE_SLOTS - 1);
        c->hash = h;
        c->playlist = find_playlist(db, h, name);
    }
    r = 0;
    if (c->playlist) {
        c->count = playlist_count(c->playlist);
        r = make_collage(db, c->playlist, c->px, !busy, name);
    }
    fw_free(name);
    if (r < 0) {
        c->hash = 0;                      /* make it after the movement */
        *wait = 1;
        return 0;
    }
    c->state = r ? 1 : -1;
    STAT_ADD(T_COLLAGE, t0);
    return r ? c->px : 0;
}

COLD static void draw_with_thumbnail(draw_fn original, void *view, const char *text, void *a3)
{
    Rect r;
    void *gc = (char *)view + VIEW_GC;
    const unsigned short *px = 0;
    const Entry *e;
    unsigned h = 0;
    int height, *left, i, n, ts = 0, wait = 0, busy, icon = 0;
    unsigned id = *(unsigned short *)((char *)view + VIEW_ELEMENT_ID);
    unsigned t0 = STAT_NOW(), t1;

    if (id != ALBUM_NAME_ID && id != PLAYLIST_NAME_ID) {
        original(view, text, a3);
        STAT_ADD(T_OTHER_ROW, t0);
        return;
    }
    /* After a USB session the database, the artwork and the files can be new or changed. The
       artwork file of the patch is still open from before the session: free_art closes it. */
    if (db_loaded) {
        db_loaded = 0;
        free_art();
        free_cache();
        free_collages();
        folders_read = 0;
        cache_written = 0;
        free_album_hashes();
        if (state == 1)
            check_for_new_file();
        else if (state == -1)
            state = 0;
    }
    load();
    if (art_fh_file && USEC_NOW - art_used >= ART_CLOSE_US)
        art_close();
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
    /* While the wheel moves, a thumbnail that needs the disk waits (`wait`): the row gets an
       empty square, and the end of the movement draws the list again. */
    busy = h ? wheel_moves() : 0;
    if (h && id == ALBUM_NAME_ID) {
        int *p = view, k;
        last_album_hash = h;
        for (k = 0; k < 4 && p; k++) {    /* the label, its cell, ..., the list */
            p = *(int **)((char *)p + VIEW_PARENT);
            if (p && *(unsigned *)p == BROWSE_LIST_CLASS) {
                album_list = p;
                break;
            }
        }
    }
    /* The file of iPodFirm first. While the wheel moves, a thumbnail of the file that is not in
       memory waits. */
    if (h && (e = find(h)) != 0) {
        ts = (int)size;
        if (busy && !file_in_memory(e))
            wait = 1;
        else
            px = pixels(e);
    }
    /* A folder of playlist-folders is not a playlist: it gets the folder icon (version 3.4). */
    if (h && !px && !wait && id == PLAYLIST_NAME_ID && is_folder(h)) {
        px = folder_px;
        ts = TH;
        icon = 1;
    }
    /* A playlist that is not in the file gets the collage of its albums (version 3.0). */
    if (h && !px && !wait && id == PLAYLIST_NAME_ID) {
        if ((px = playlist_collage(h, busy, &wait)) != 0 || wait)
            ts = TH;
    }
    /* A valid cache has each album with artwork. Then an album that is not in it has no artwork,
       and the patch does not make the album table. */
    if (h && !px && !wait && id == ALBUM_NAME_ID) {
        if (cache_state == 0)
            cache_load();
        if ((px = cache_find(h)) != 0)
            ts = TH;
    }
    if (h && !px && !wait && id == ALBUM_NAME_ID && cache_state != 1) {
        if (art_state == 0 && busy) {
            wait = 1;                     /* make the table after the movement */
            ts = TH;
        } else {
            if (art_state == 0)
                build_art();              /* only if an album needs the artwork */
            if ((n = art_find(h)) >= 0) {
                ts = TH;
                if (busy && art[n].slot >= art_slots && art[n].slot != FAILED)
                    wait = 1;
                else
                    px = art_thumb(n);
            }
        }
    }
    if (wait && !px) {
        waiting = 1;
        STAT_COUNT(waits);
    } else
        wait = 0;
    /* A list row has the height of the thumbnail and a margin. */
    if ((!px && !wait) || height < ts || height > ts + 12) {
        t1 = STAT_NOW();
        original(view, text, a3);
        STAT_ADD(T_ORIGINAL_PLAIN, t1);
    } else {
        left = (int *)((char *)view + VIEW_LEFT);
        *left += ts + GAP;
        t1 = STAT_NOW();
        original(view, text, a3);
        STAT_ADD(T_ORIGINAL_SHIFTED, t1);
        *left -= ts + GAP;
        gc_prepare(view, gc);             /* set the origin and the clip for the original bounds */
        if (icon) {
            gc_set_mode(gc, 0);           /* the blit cannot leave a pixel transparent */
            draw_runs(gc, px, ts, r.top + ((height - ts) >> 1), r.left + 1, FOLDER_KEY);
        } else if (px)
            draw_thumbnail(gc, px, ts, r.top + ((height - ts) >> 1), r.left + 1);
        else
            draw_empty(gc, ts, r.top + ((height - ts) >> 1), r.left + 1);
    }
    /* The list of this album row is visible now: start the tick for the redraw or the fill. */
    if (id == ALBUM_NAME_ID && album_list && (waiting || fill_has_work())) {
        int *p = view, k;
        for (k = 0; k < 4 && p && p != album_list; k++)
            p = *(int **)((char *)p + VIEW_PARENT);
        if (p == album_list)
            start_tick(album_list);       /* only a list that is a parent of this row now */
    }
#if ALBUM_ART_STATS
    stat_add(T_ALBUM_ROW, t0);
    if ((stats.t[T_ALBUM_ROW].count & (STATS_EVERY - 1)) == 0)
        write_stats();                    /* after the timed part */
#endif
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

/* Replaces the event method of the browse-list class (slot +0x30, at 0x6772c0) with "chain": the
 * cover-flow patch hooks the same slot. A wheel step sets `moving`. At the end of the movement
 * (step 0), the list draws again if a row has an empty square. The real wheel often sends no end
 * event. Thus the patch also uses the 100 ms timer of the list (and the event type 0xd): a tick
 * MOVE_LIMIT_US after the last step does the same. A tick without a redraw makes one thumbnail in
 * the background, if it comes to the visible list of the last album row. When no thumbnail is
 * missing, the tick closes the artwork file and writes the cache (fill_done). */
COLD static void tick(int *list)
{
    if (wheel_moves()) {
        start_tick(list);                 /* wait for 0.3 s without a step */
    } else if (waiting) {
        waiting = 0;
        STAT_COUNT(redraws);
        view_invalidate(list);            /* the draw starts the tick again if there is more work */
    } else if (list == album_list && (list[VIEW_FLAGS_WORD] & 0x1800) == 0x800) {
        if (prefill_one()) {
            STAT_COUNT(prefills);
            start_tick(list);
        } else {
            fill_done();
        }
    }
}

int hook_list_event(int *list, int *ev, void *a3, int a4)
{
    /* The event of the timer that the patch started: do the work, and do not give it to the list.
       The list would change the selected row and count down its blink count (from 255 if 0). */
    if (ev[1] == EV_TIMER && ev[2] == (int)((char *)list + LIST_TIMER) && timer_on) {
        timer_on = 0;
        tick(list);
        return 1;
    }
    if (ev[1] == EV_KEY_DOWN || ev[1] == EV_KEY_REPEAT) {
        key_time = USEC_NOW;              /* the list can start its blink: the timer is for the list */
        timer_on = 0;
    }
    if (art_fh_file && USEC_NOW - art_used >= ART_CLOSE_US)
        art_close();                      /* also when a different list shows */
    if (ev[1] == EV_WHEEL) {
        if (ev[3] != 0) {
            moving = 1;
            step_time = USEC_NOW;
            if (list == album_list && waiting)
                start_tick(list);         /* the redraw after the stop, also with the finger on the wheel */
        } else {
            moving = 0;
            STAT_COUNT(ends);
            if (waiting) {
                waiting = 0;
                STAT_COUNT(redraws);
                view_invalidate(list);
            }
        }
    } else if (ev[1] == EV_TICK && !wheel_moves()) {
        if (waiting) {
            waiting = 0;
            STAT_COUNT(redraws);
            view_invalidate(list);
        } else if (list == album_list && (list[VIEW_FLAGS_WORD] & 0x1800) == 0x800 && prefill_one()) {
            STAT_COUNT(prefills);
        }
    }
    return list_event(list, ev, a3, a4);
}

/* Replaces the call at 0xb4ad4 in the music database load: log_event(log, 0xf, 0). */
void hook_db_loaded(void *log, int event, int value)
{
    log_event(log, event, value);
    STAT_COUNT(db_loaded_calls);
    db_loaded = 1;
}
