/* up-next: Play Next and Play Last for the iPod Video (RetailOS 1.3).
 *
 * Hold Select on a song, an album or an artist while music plays. The item Settings > Hold Select
 * selects the action of the hold:
 *  - Play Next: the songs play directly after the current song;
 *  - Play Last: the songs play after the last song of the list that plays now;
 *  - On-The-Go: the songs go into the On-The-Go playlist, as without the patch.
 *  - Cover Flow (only if the patch cover-flow is installed): in the Albums list, the hold opens
 *    Cover Flow; in the other lists, it does Play Next.
 * When no music plays, the hold always adds the songs to On-The-Go. The research is in
 * re/play-next.md.
 *
 * Hooks:
 *  - the call of "Add to On-The-Go" (0xadbb8) in its script function 0x1eb5a4, at 0x1eb5b4. r0 is the
 *    browser and r1 is the row (-1 for all rows: an album or an artist);
 *  - the first instruction of the general resource lookup (0x21f254): the texts of the item;
 *  - the "get" and "set" methods of the settings object (vtable 0x66c94c and 0x66c950).
 *
 * The method of a hold:
 * 1. The add method of the play list (vtable + 0x10) puts the songs at the end of the play list.
 *    It uses the filter and the sort of the browser, as 0xadbb8 does for On-The-Go.
 * 2. Play Next without shuffle: the play order is the order of the linked items (slot 1). The patch
 *    moves the new items from the end to the position after the current item.
 * 3. With shuffle, the play order is the shuffle position at item + 0x24 (slot 2). The patch gives
 *    the new items the positions after the current item (Play Next) or after the last position
 *    (Play Last), and moves the later positions.
 * 4. The patch frees the sorted arrays of the track list (0x1137c4) and finds the new index of the
 *    current item (0x9e57c), as 0x196d48 does after a change.
 *
 * The value of the item is in the file iPod_Control\iTunes\iPodFirmHoldSelect: '0' On-The-Go,
 * '1' Play Next, '2' Play Last, '3' Cover Flow. Without the file, the patch uses the option
 * hold_default. The patch makes the file with 0xe468c, as the firmware does for OTGPlaylistInfo.
 * The patch cover-flow reads the same file. Only cover-flow hooks the UI event handler (word at
 * 0x6701f0), so a changed word there shows that cover-flow is installed. */

int otg_add(void *browser, int row);                                      /* 0xadbb8 */
void *playlist_get(void);                                                 /* 0x196418 */
void *playlist_item(void *playlist, int index);                           /* 0x235a54 */
void list_lock(void *lock);                                               /* 0xc9a84 */
void list_unlock(void *lock);                                             /* 0xc9b58 */
void *browser_list(void *browser);                                        /* 0x9bb98 */
int browser_sort(void *browser);                                          /* 0xa00d0 */
void tracklist_invalidate(void *tracklist);                               /* 0x1137c4 */
int item_position(void *item, int type, int reverse);                     /* 0x9e57c */
const char *str_lookup(void *table, int id);                              /* 0x21f418 */
void *str_table(void);                                                    /* 0x21f3b8 */
void fw_memset0(void *p, unsigned size);                                  /* 0x7ccd0 */
void fw_strcpy(char *dst, const char *src);                               /* 0x7cd6c */
int file_open(void *path_record, void *fh, int zero, unsigned mode);      /* 0x8f38c */
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode); /* 0x8f3f8 */
int file_read(void *fh, unsigned *len, void *buf);                        /* 0x8f464 */
int file_write(void *fh, unsigned *len, const void *buf);                 /* 0x8f6f4 */
int file_close(void *fh);                                                 /* 0x8f184 */
void file_create(void *path_record, unsigned type, const char *folder, const char *name); /* 0xe468c */
/* Set by the patcher (chain): the previous targets of the hooks. */
void *lookup_next(void *provider, unsigned type, int id);
int get_next(void *self, unsigned op, unsigned key, void *out);
int set_next(void *self, unsigned op, unsigned key, void *value);
void lookup_continue(void);                                               /* 0x21f258 */

#define FIELD(type, object, offset) (*(type *)((char *)(object) + (offset)))

#define TAG_STR     0x53747220u                       /* 'Str ' */
#define TAG_VIEW    0x56696577u                       /* 'View' */
#define OP_TEXT_ID  0x70724944u                       /* 'prID': the ID of the value text */
#define OP_TEXT     0x53747220u                       /* 'Str ': the value text */
#define NOTIFY_BOOL 0x426f6f6cu                       /* 'Bool': the notice after a change */
#define MODE_DATA   0x64617461u                       /* 'data' */
#define TYPE_ITUN   0x6974756eu                       /* 'itun': the file type of OTGPlaylistInfo */
#define KEY         0x7e0fu                           /* the item (patch.json: 0x60007e0f). Not 0x60ec:
                                                         that is the key of Date & Time > Daylight Saving */
#define LABEL_ID    0x7e0b                            /* "Hold Select" */
#define NEXT_ID     0x7e0c                            /* "Play Next" */
#define LAST_ID     0x7e0d                            /* "Play Last" */
#define OTG_ID      0x63cc                            /* "On-The-Go" (firmware string) */
#define COVER_ID    0x7e0e                            /* "Cover Flow" */
#define UI_EVENT_SLOT (*(volatile unsigned *)0x6701f0) /* 0x1d81cc without cover-flow */

enum { HOLD_OTG = 0, HOLD_NEXT = 1, HOLD_LAST = 2, HOLD_COVER = 3, HOLD_COUNT = 4 };

/* The option in the app: the value without the file. */
unsigned hold_default = HOLD_COVER;

static const char label[] = "Hold Select";
static const char play_next[] = "Play Next";
static const char play_last[] = "Play Last";
static const char cover_flow[] = "Cover Flow";
static const char folder[] = "iPod_Control\\iTunes\\";
static const char name[] = "iPodFirmHoldSelect";
static int hold_mode = -1;                            /* -1: the file is not read yet */

/* ---- The value of the item ------------------------------------------------------------------- */

static void make_path(unsigned *path)
{
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, folder);
    fw_strcpy((char *)path + 4 + sizeof folder - 1, name);
}

static int cover_flow_installed(void)
{
    return UI_EVENT_SLOT != 0x1d81cc;
}

/* Makes the file again and writes the value. */
static void save_mode(int value)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = 1;
    unsigned char c = (unsigned char)('0' + value);
    file_create(path, TYPE_ITUN, folder, name);
    make_path(path);
    fw_memset0(fh, sizeof fh);
    if (file_open_rw(path, fh, 0x1000, MODE_DATA) == 0) {
        file_write(fh, &len, &c);
        file_close(fh);
    }
}

/* Reads the value. Without the file, it uses the option and writes the file, so that cover-flow
 * reads the same value. */
static int mode(void)
{
    if (hold_mode < 0) {
        int found = 0;
        unsigned path[0x108 / 4], fh[0x30 / 4], got = 1;
        unsigned char c = 0;
        hold_mode = hold_default < HOLD_COUNT ? (int)hold_default : HOLD_COVER;
        make_path(path);
        fw_memset0(fh, sizeof fh);
        if (file_open(path, fh, 0, MODE_DATA) == 0) {
            if (file_read(fh, &got, &c) == 0 && got == 1 && c >= '0' && c < '0' + HOLD_COUNT) {
                hold_mode = c - '0';
                found = 1;
            }
            file_close(fh);
        }
        if (hold_mode == HOLD_COVER && !cover_flow_installed())
            hold_mode = HOLD_NEXT;
        if (!found)
            save_mode(hold_mode);
    }
    return hold_mode;
}

static int value_id(void)
{
    int m = mode();
    return m == HOLD_NEXT ? NEXT_ID : m == HOLD_LAST ? LAST_ID : m == HOLD_COVER ? COVER_ID : OTG_ID;
}

/* ---- The play list ----------------------------------------------------------------------------- */

typedef int (*add_method)(void *playlist, void *browser, int row, void *source, int sort, int reverse);

/* Item: + 0x04 the parent, + 0x08 the next item, + 0x0c the previous item, + 0x24 the shuffle
 * position. Parent: + 0x20 the first child, + 0x24 the last child, + 0x32 the count (u16). */
#define PARENT(i) FIELD(void *, i, 0x04)
#define NEXT(i) FIELD(void *, i, 0x08)
#define PREV(i) FIELD(void *, i, 0x0c)
#define POSITION(i) FIELD(unsigned, i, 0x24)
#define FIRST(p) FIELD(void *, p, 0x20)
#define LAST(p) FIELD(void *, p, 0x24)
#define COUNT(p) FIELD(unsigned short, p, 0x32)

/* Move the items from `first` to the last child of `root` to the position after `current`. */
static void move_after(void *root, void *first, void *current)
{
    void *last = LAST(root), *before = PREV(first), *after = NEXT(current);
    if (current == before)
        return;
    NEXT(before) = 0;
    LAST(root) = before;
    NEXT(current) = first;
    PREV(first) = current;
    NEXT(last) = after;
    if (after)
        PREV(after) = last;
    else
        LAST(root) = last;
}

/* Give the new items (from `first` to the end) the shuffle positions after `at`, and move the
 * later positions of the old items. */
static void place_after(void *root, void *first, unsigned at, unsigned added)
{
    unsigned n = 0;
    void *i;
    for (i = FIRST(root); i && i != first; i = NEXT(i))
        if (POSITION(i) > at)
            POSITION(i) += added;
    for (i = first; i; i = NEXT(i))
        POSITION(i) = at + 1 + n++;
}

static unsigned last_position(void *root, void *first)
{
    unsigned at = 0;
    void *i;
    for (i = FIRST(root); i && i != first; i = NEXT(i))
        if (POSITION(i) > at)
            at = POSITION(i);
    return at;
}

int hook_add(void *browser, int row)
{
    int how = mode();
    void *playlist = how != HOLD_OTG ? playlist_get() : 0;
    void *tracklist = playlist ? FIELD(void *, playlist, 0x04) : 0;
    int index = playlist ? FIELD(int, playlist, 0x14) : -1;
    void *current = tracklist && index >= 0 ? playlist_item(playlist, index) : 0;
    void *root = tracklist ? FIELD(void *, tracklist, 0x28) : 0;
    if (!current || PARENT(current) != root)
        return otg_add(browser, row);

    void *last_before = LAST(root);
    unsigned count_before = COUNT(root);
    add_method add = FIELD(add_method, *(void **)playlist, 0x10);
    add(playlist, browser, row, browser_list(browser), browser_sort(browser),
        FIELD(unsigned char, browser, 0xc38));

    void *lock = (char *)playlist + 0x1c;
    list_lock(lock);
    unsigned added = COUNT(root) - count_before;
    void *first = last_before ? NEXT(last_before) : FIRST(root);
    if (added && first) {
        if (FIELD(unsigned char, tracklist, 0xec) & 1)
            place_after(root, first, how != HOLD_LAST ? POSITION(current) : last_position(root, first),
                        added);
        else if (how != HOLD_LAST)
            move_after(root, first, current);
        tracklist_invalidate(tracklist);
        FIELD(int, playlist, 0x14) = item_position(current, 0x33, 0);
    }
    list_unlock(lock);
    return 0;
}

/* ---- The Settings item ------------------------------------------------------------------------- */

/* The first instruction of the general lookup (0x21f254) is replaced by a branch. If no other patch
 * hooks the lookup, lookup_next is this function: it runs that instruction and continues in the firmware. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

void *hook_lookup(void *provider, unsigned type, int id)
{
    if (hold_mode < 0 && type == TAG_VIEW)      /* the first screen: the file system is ready */
        mode();
    if (type == TAG_STR && id == LABEL_ID)
        return (void *)label;
    if (type == TAG_STR && id == NEXT_ID)
        return (void *)play_next;
    if (type == TAG_STR && id == LAST_ID)
        return (void *)play_last;
    if (type == TAG_STR && id == COVER_ID)
        return (void *)cover_flow;
    return lookup_next(provider, type, id);
}

int hook_settings_get(void *self, unsigned op, unsigned key, void *out)
{
    if (key == KEY) {
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = (short)value_id();
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = str_lookup(str_table(), value_id());
            return 1;
        }
    }
    return get_next(self, op, key, out);
}

/* A selection moves to the next value: Play Next, Play Last, On-The-Go, Cover Flow (only with
 * cover-flow). */
int hook_settings_set(void *self, unsigned op, unsigned key, void *value)
{
    if (key == KEY) {
        int m = mode();
        hold_mode = m == HOLD_NEXT ? HOLD_LAST : m == HOLD_LAST ? HOLD_OTG
                  : m == HOLD_OTG && cover_flow_installed() ? HOLD_COVER : HOLD_NEXT;
        save_mode(hold_mode);
        (*(void (**)(void *, unsigned, unsigned))(*(char **)self + 0x54))(self, NOTIFY_BOOL, key);
        return 1;
    }
    return set_next(self, op, key, value);
}
