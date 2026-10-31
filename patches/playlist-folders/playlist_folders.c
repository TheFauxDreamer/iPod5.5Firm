/* playlist-folders: folders in the Playlists list (RetailOS 1.3, iPod Video).
 *
 * The iPodFirm app writes the folders into iPod_Control/iTunes/iPodFirmPlaylistFolders. The top
 * Playlists list shows the folders and the playlists that are not in a folder. Select on a folder
 * shows its playlists on the same screen. Menu goes back to the top list. A folder cannot contain
 * a folder. The research is in re/playlist-folders.md (experiment 3).
 *
 * The screen shows array entry row + 1 of the playlist array (main browser + 0xcfc). Only four
 * calls change a screen row into an array index. The patch hooks these calls and gives them the
 * index from its own view (the top list or one folder):
 *  - A, the count in 0x1ea660 (bl at 0x1ea66c): the count of the view + 1;
 *  - B, the name of a row in 0x1ec614 (bl at 0x1ec914): the folder name, or the playlist name;
 *  - C, the selection in 0x1e7e34 (bl at 0x1e7e7c): the playlist of the row;
 *  - D, the On-The-Go test 0x254cac (bl at 0x254cc4): 0 for a folder.
 * Other hooks:
 *  - E, the first instruction of 0x1ea660: the patch keeps the JS browser of the screen. A change
 *    of the view calls 0x1ea660 again ('VMax') and sends 'Str ' to read the labels again;
 *  - F, the event method of the browse lists (0x6772c0, chain): Select on a folder and Menu in a
 *    folder. The list gets the push of a key;
 *  - G, the first instruction of the UI handler 0x1d81cc: the patch stops the rest of a push that
 *    it used (types 5-7). Without this, the firmware does the action of the key a second time.
 *    The patch does not change the slot 0x6701f0: cover-flow hooks it, and up-next reads it.
 *
 * The file (little-endian). All parts start at a multiple of 4 bytes:
 *   "IFPF", u16 version (1), u16 flags (bit 0: alphabetical order; bit 1: no folder icons, read
 *   only by album-art), u16 folder count, u16 0
 *   for each folder: u16 colour (RGB565, for the app), u16 name units, u16 member count, u16 0,
 *                    the name (UTF-16, padded to 4 bytes), the members (u32 low, u32 high: the
 *                    persistent ID of a playlist, mhyp +0x1c)
 * The patch reads the file again when the playlist array changes (a new database) and when the
 * Playlists screen opens with the top list. */

typedef unsigned short u16;

/* Firmware functions (symbols in patch.json). */
int count_original(void *browser);                                   /* 0x9e008 */
int name_original(void *browser, int index, u16 *out);               /* 0x9cf90 */
int select_original(void *browser, int index);                       /* 0xb29b0 */
int otg_original(void *browser, int index);                          /* 0xa39c4 */
void *browser_main(void *browser);                                   /* 0x9bc6c */
void view_invalidate(void *view);                                    /* 0x21ac04 */
void *fw_alloc(unsigned size);                                       /* 0x25a974 */
void fw_free(void *p);                                               /* 0x25a8e4 */
void fw_memset0(void *p, unsigned size);                             /* 0x7ccd0 */
void fw_strcpy(char *dst, const char *src);                          /* 0x7cd6c */
int file_open(void *path_record, void *fh, int zero, unsigned mode); /* 0x8f38c */
int file_read(void *fh, unsigned *len, void *buf);                   /* 0x8f464 */
int file_close(void *fh);                                            /* 0x8f184 */
void vmax_continue(void);                                            /* 0x1ea664 */
void ui_continue(void);                                              /* 0x1d81d0 */
/* Set by the patcher (chain): the previous target of the hook. */
int list_event(int *list, int *ev, void *a3, int a4);

#define FIELD(type, object, offset) (*(type *)((char *)(object) + (offset)))

#define MAIN_PLAYLISTS   0xcfc            /* main browser: the playlist array */
#define MAIN_COUNT       0xd00            /* main browser: the count of the array */
#define MAIN_OTG         0xce0            /* main browser: the On-The-Go playlist */
#define PL_ID_LOW        0x18             /* playlist: the persistent ID (mhyp +0x1c) */
#define PL_ID_HIGH       0x1c
#define JS_VMAX          0x35             /* word index in the JS browser: count - 1 of the list */
#define TAG_STR          0x53747220u      /* 'Str ' */
#define LIST_ELEMENT     0x6387           /* the element of the list on the Playlists screen */
#define NAME_ELEMENT     0x6425           /* the playlist label of a row */
#define EV_KEY_DOWN      4
#define EV_KEY_UP        7
#define KEY_OF(ev)       (((unsigned)(ev)[4] >> 16) & 0xff)
#define KEY_MENU         0x6e
#define KEY_SELECT       0x6f
#define LIST_SELECTION   0x29             /* word index: object with the selected row at +0x14 */
#define LIST_CELL        0x2a             /* word index: the template cell of a list */
#define LIST_SET_SELECTION 0x138          /* vtable slot: set the selected row */
#define VIEW_FLAGS       8                /* word index: bits 0x1800 = 0x800 if the view is visible */
#define VIEW_ELEMENT_ID  0x1c
#define VIEW_CHILD_COUNT 0x7c
#define VIEW_CHILDREN    0x80
#define UI_KEYS_DOWN     0x44             /* byte in the UI object: keys down */
#define MODE_DATA        0x64617461u      /* 'data' */
#define READ_EOF         (-0x27)          /* 0x8f464: the file has fewer bytes than asked */
#define FILE_MAX         0x10000          /* the largest file that the patch reads */
#define MAX_FOLDERS      64
#define NAME_MAX         63
#define FOLDER_BIT       0x8000           /* a view item with this bit is a folder */
#define FLAG_ALPHABETICAL 1

static const char folder_path[] = "iPod_Control\\iTunes\\";
static const char file_name[] = "iPodFirmPlaylistFolders";

struct folder {
    const u16 *name;                      /* in the file buffer */
    unsigned units;
    const unsigned *members;              /* pairs: low, high */
    unsigned count;
    unsigned first, used;                 /* the playlists of the folder: in folder_items */
};

static unsigned char *file_buf;           /* the file, or 0 */
static unsigned flags;
static struct folder folders[MAX_FOLDERS];
static unsigned folder_count;

static void *seen_array;                  /* the array of the last build */
static unsigned seen_count, seen_sum;
static int need_read = 1;                 /* 1: read the file at the next build */
static u16 *top_items;                    /* the top view */
static unsigned top_used;
static u16 *folder_items;                 /* the playlists of all folders */
static int current = -1;                  /* -1: the top list; else the open folder */
static unsigned folder_row;               /* the row of the open folder in the top list */
static int *screen_js;                    /* the JS browser of the Playlists screen */
static int swallow_key = -1;              /* the rest of this push does not go to the firmware */

/* ---- The file ------------------------------------------------------------------------------ */

static void read_file(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], got = FILE_MAX;
    unsigned char *b;
    unsigned at, k, n;
    int rc;

    fw_free(file_buf);
    file_buf = 0;
    folder_count = 0;
    flags = 0;
    fw_memset0(path, sizeof path);
    fw_strcpy((char *)path + 4, folder_path);
    fw_strcpy((char *)path + 4 + sizeof folder_path - 1, file_name);
    fw_memset0(fh, sizeof fh);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return;
    b = fw_alloc(FILE_MAX);
    rc = b ? file_read(fh, &got, b) : -1;
    if (b && ((rc != 0 && rc != READ_EOF) || got < 12 || got > FILE_MAX)) {
        fw_free(b);
        b = 0;
    }
    file_close(fh);
    if (!b)
        return;
    if (b[0] != 'I' || b[1] != 'F' || b[2] != 'P' || b[3] != 'F' || FIELD(u16, b, 4) != 1) {
        fw_free(b);
        return;
    }
    file_buf = b;
    flags = FIELD(u16, b, 6);
    n = FIELD(u16, b, 8);
    at = 12;
    for (k = 0; k < n && folder_count < MAX_FOLDERS; k++) {
        unsigned units, members, name_bytes;
        if (at + 8 > got)
            break;
        units = FIELD(u16, b, at + 2);
        members = FIELD(u16, b, at + 4);
        name_bytes = (units * 2 + 3) & ~3u;
        if (units == 0 || units > NAME_MAX || at + 8 + name_bytes + members * 8 > got)
            break;
        folders[folder_count].name = (const u16 *)(b + at + 8);
        folders[folder_count].units = units;
        folders[folder_count].members = (const unsigned *)(b + at + 8 + name_bytes);
        folders[folder_count].count = members;
        folder_count++;
        at += 8 + name_bytes + members * 8;
    }
}

/* ---- The views ----------------------------------------------------------------------------- */

static int folder_of(void *pl)
{
    unsigned lo = FIELD(unsigned, pl, PL_ID_LOW), hi = FIELD(unsigned, pl, PL_ID_HIGH), k, m;
    for (k = 0; k < folder_count; k++)
        for (m = 0; m < folders[k].count; m++)
            if (folders[k].members[2 * m] == lo && folders[k].members[2 * m + 1] == hi)
                return (int)k;
    return -1;
}

static u16 fold(u16 c)
{
    return c >= 'a' && c <= 'z' ? (u16)(c - 32) : c;
}

/* < 0 if the text a goes before the text b. The compare ignores the case of a-z. */
static int compare(const u16 *a, unsigned an, const u16 *b, unsigned bn)
{
    unsigned i, n = an < bn ? an : bn;
    for (i = 0; i < n; i++) {
        u16 x = fold(a[i]), y = fold(b[i]);
        if (x != y)
            return x < y ? -1 : 1;
    }
    return (int)an - (int)bn;
}

/* Adds, in alphabetical order, each folder with playlists that is not placed yet and goes before
 * the name (u16 count, then the text). name = 0: all these folders. */
static void place_folders(unsigned char *placed, const u16 *name)
{
    for (;;) {
        int best = -1;
        unsigned k;
        for (k = 0; k < folder_count; k++) {
            const struct folder *f = &folders[k];
            if (placed[k] || !f->used || (name && compare(f->name, f->units, name + 1, name[0]) >= 0))
                continue;
            if (best < 0 || compare(f->name, f->units, folders[best].name, folders[best].units) < 0)
                best = (int)k;
        }
        if (best < 0)
            return;
        placed[best] = 1;
        top_items[top_used++] = (u16)(FOLDER_BIT | best);
    }
}

/* Makes the views again if the array changed. Returns 0 if there are no folders. */
static int ensure(void *browser)
{
    void *main = browser_main(browser);
    void **array = FIELD(void **, main, MAIN_PLAYLISTS);
    unsigned n = FIELD(unsigned, main, MAIN_COUNT), sum = n, i, k;
    void *otg = FIELD(void *, main, MAIN_OTG);
    int *home;

    for (i = 0; array && i < n; i++)
        sum = sum * 31 + (unsigned)array[i] + FIELD(unsigned, array[i], PL_ID_LOW);
    if (!need_read && array == seen_array && n == seen_count && sum == seen_sum)
        return top_items != 0;
    if (need_read || array != seen_array || n != seen_count || sum != seen_sum) {
        read_file();
        need_read = 0;
    }
    seen_array = array;
    seen_count = n;
    seen_sum = sum;
    current = -1;
    fw_free(top_items);
    fw_free(folder_items);
    top_items = folder_items = 0;
    top_used = 0;
    if (!folder_count || !array || n < 2)
        return 0;
    top_items = fw_alloc((n + folder_count) * sizeof(u16));
    folder_items = fw_alloc(n * sizeof(u16));
    home = fw_alloc(n * sizeof(int));
    if (!top_items || !folder_items || !home) {
        fw_free(top_items);
        fw_free(folder_items);
        fw_free(home);
        top_items = folder_items = 0;
        return 0;
    }
    for (k = 0; k < folder_count; k++)
        folders[k].used = 0;
    for (i = 1; i < n; i++) {
        home[i] = array[i] == otg ? -1 : folder_of(array[i]);
        if (home[i] >= 0)
            folders[home[i]].used++;
    }
    {
        unsigned at = 0;
        for (k = 0; k < folder_count; k++) {
            folders[k].first = at;
            at += folders[k].used;
            folders[k].used = 0;
        }
    }
    for (i = 1; i < n; i++)
        if (home[i] >= 0) {
            struct folder *f = &folders[home[i]];
            folder_items[f->first + f->used++] = (u16)i;
        }
    if (flags & FLAG_ALPHABETICAL) {
        /* Each folder goes before the first playlist with a greater name. On-The-Go stays last. */
        u16 name[256];
        unsigned char placed[MAX_FOLDERS];
        for (k = 0; k < folder_count; k++)
            placed[k] = 0;
        for (i = 1; i < n; i++) {
            if (home[i] >= 0)
                continue;
            if (array[i] != otg) {
                name_original(browser, (int)i, name);
                place_folders(placed, name);
            } else {
                place_folders(placed, 0);
            }
            top_items[top_used++] = (u16)i;
        }
        place_folders(placed, 0);
    } else {
        for (k = 0; k < folder_count; k++)
            if (folders[k].used)
                top_items[top_used++] = (u16)(FOLDER_BIT | k);
        for (i = 1; i < n; i++)
            if (home[i] < 0)
                top_items[top_used++] = (u16)i;
    }
    fw_free(home);
    return 1;
}

/* The view item of a screen row, or -1. */
static int item_of(void *browser, int row)
{
    if (!ensure(browser) || row < 0)
        return -1;
    if (current < 0)
        return (unsigned)row < top_used ? top_items[row] : -1;
    if ((unsigned)row < folders[current].used)
        return folder_items[folders[current].first + row];
    return -1;
}

/* ---- Hooks A-D: the row map ------------------------------------------------------------------ */

int hook_count(void *browser)
{
    if (!ensure(browser))
        return count_original(browser);
    return 1 + (int)(current < 0 ? top_used : folders[current].used);
}

int hook_name(void *browser, int index, u16 *out)
{
    int item = item_of(browser, index - 1);
    if (item < 0)
        return name_original(browser, index, out);
    if (item & FOLDER_BIT) {
        const struct folder *f = &folders[item & ~FOLDER_BIT];
        unsigned i;
        out[0] = (u16)f->units;
        for (i = 0; i < f->units; i++)
            out[i + 1] = f->name[i];
        return 0;
    }
    return name_original(browser, item, out);
}

int hook_select(void *browser, int index)
{
    int item = item_of(browser, index - 1);
    if (item < 0)
        return select_original(browser, index);
    if (item & FOLDER_BIT)
        return -50;                       /* as for a row that is not there */
    return select_original(browser, item);
}

int hook_otg(void *browser, int index)
{
    int item = item_of(browser, index - 1);
    if (item < 0)
        return otg_original(browser, index);
    if (item & FOLDER_BIT)
        return 0;
    return otg_original(browser, item);
}

/* ---- Hook E: the JS browser ------------------------------------------------------------------ */

__attribute__((naked)) void vmax_original(int *js)
{
    __asm__ volatile("push {r4, lr}\n\tb vmax_continue\n");
}

void hook_vmax(int *js)
{
    screen_js = js;
    vmax_original(js);
}

/* ---- Hooks F and G: the keys ----------------------------------------------------------------- */

static int is_playlists(int *list)
{
    int *cell = (int *)list[LIST_CELL], k, n;
    int **kids;
    if (!cell || (list[VIEW_FLAGS] & 0x1800) != 0x800 ||
        FIELD(u16, list, VIEW_ELEMENT_ID) != LIST_ELEMENT)
        return 0;
    n = FIELD(int, cell, VIEW_CHILD_COUNT);
    kids = FIELD(int **, cell, VIEW_CHILDREN);
    for (k = 0; kids && k < n; k++)
        if (FIELD(u16, kids[k], VIEW_ELEMENT_ID) == NAME_ELEMENT)
            return 1;
    return 0;
}

/* Shows the current view: a new count, new labels and the selected row. */
static void show(int *list, unsigned row)
{
    if (screen_js) {
        screen_js[JS_VMAX] = -2;          /* 0x1ea660 sends 'VMax' only after a change */
        vmax_original(screen_js);
        ((void (*)(void *, unsigned, unsigned))(*(void ***)screen_js)[0x54 / 4])(screen_js, TAG_STR, LIST_ELEMENT);
    }
    ((void (*)(int *, int))(*(void ***)list)[LIST_SET_SELECTION / 4])(list, (int)row);
    view_invalidate(list);
}

int hook_list_event(int *list, int *ev, void *a3, int a4)
{
    if (ev[1] == EV_KEY_DOWN && screen_js && is_playlists(list)) {
        unsigned key = KEY_OF(ev);
        int row = FIELD(int, list[LIST_SELECTION], 0x14);
        void *browser = FIELD(void *, screen_js, 0x1c);
        if (key == KEY_SELECT && current < 0) {
            int item = item_of(browser, row);
            if (item >= 0 && (item & FOLDER_BIT)) {
                current = item & ~FOLDER_BIT;
                folder_row = (unsigned)row;
                show(list, 0);
                swallow_key = KEY_SELECT;
                return 1;
            }
        } else if (key == KEY_MENU && current >= 0) {
            current = -1;
            show(list, folder_row);
            swallow_key = KEY_MENU;
            return 1;
        } else if (key == KEY_MENU) {
            need_read = 1;                /* the top list closes: read the file at the next open */
        }
    }
    return list_event(list, ev, a3, a4);
}

__attribute__((naked)) int ui_original(void *ui, int *ev)
{
    __asm__ volatile("push {r4, r5, r6, r7, r8, lr}\n\tb ui_continue\n");
}

int hook_ui_event(void *ui, int *ev)
{
    int type = ev[1];
    if (type > EV_KEY_DOWN && type <= EV_KEY_UP && (int)KEY_OF(ev) == swallow_key) {
        if (type == EV_KEY_UP) {
            unsigned char *down = (unsigned char *)ui + UI_KEYS_DOWN;
            swallow_key = -1;
            if (*down)
                (*down)--;
        }
        return 1;
    }
    return ui_original(ui, ev);
}
