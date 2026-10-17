/* album-artists: an "Album Artists" item in the Music menu (RetailOS 1.3, iPod Video).
 *
 * The item opens a list of the Album Artists. A song without an Album Artist uses its Artist.
 * The normal Artists list, Now Playing and the sort indexes of the database do not change.
 * The design comes from osos-lab (RepriseOS) for the iPod Classic. The research is in
 * re/album-artist.md, section "Album Artists menu item".
 *
 * The patch.json section "menu_items" puts copies of the Artists item, with the label LABEL_ID:
 *  - in the Music menu (Menu 24440), after Artists;
 *  - in the main menu (Menu 24094), after Artists. The bit MAIN_MENU_BIT of the main menu mask shows
 *    or hides it. The bit is 0 by default;
 *  - in Settings > Main Menu (Menu 24600), with the label SETTINGS_LABEL_ID and the settings key
 *    0x60007e05. Hooks L and M give its value and change the bit. The key must not be a label
 *    ID: the list asks the value text with the resource lookup ('Str ', key), and hook F answers
 *    the label IDs before the settings object.
 * Each copy opens the Artists screen. When the owner selects a copy, the next browse uses "album
 * artist mode": its browser (aa_browser) builds the Artists list from the Album Artists.
 *
 * Hooks:
 *  - A, the mhod 22 entry of the jump table of the track parser (0xd7ea0): the patch reads the Album
 *    Artist into the artist string pool. A side table keeps its index for each track, but only if
 *    its text is not the text of the Artist;
 *  - B, the call of the track parser in the database loader (0xafc8c): the patch clears the side
 *    table before each load;
 *  - C, the "activate" method of the menu lists (vtable 0x6776f8): a selection of a copy sets
 *    aa_pending, a selection of another item clears aa_pending and aa_browser. Composers, Genres
 *    and Playlists do not run the reset of hook G, thus this clear is necessary;
 *  - G, the first instruction of the browser reset 0x1e7b98 (the start of a browse): after a
 *    selection of a copy, the browser of the browse gets the mode (aa_browser);
 *  - D, the first instruction of the list build 0xd080c: for aa_browser, the patch builds the Artists
 *    list (field 4) from the Album Artists;
 *  - H, the first instruction of the clear of the Artists list 0xa34b8: the patch knows when its
 *    list is freed;
 *  - E, the call of the Artist text in the track filter (0x114354): for aa_browser, the filter
 *    compares the selected name with the Album Artist;
 *  - F, the first instruction of the resource lookup (0x21f254): the labels of the items, and the
 *    title "Album Artists" (Str -30) in album artist mode;
 *  - I and J, the two calls of 0x105a04 (label -> bit of the main menu mask);
 *  - K, the first instruction of 0x19ed58 (show or hide an item of a menu): when the UI script
 *    shows or hides Artists in the main menu, the patch also shows or hides the copy;
 *  - L and M, the "get" and "set" methods of the settings object (vtable 0x66c94c and 0x66c950):
 *    the row in Settings > Main Menu. The firmware knows only its own keys. */

typedef unsigned short u16;

/* Firmware functions (symbols in patch.json). */
int db_read_string(void *reader, int mode, int type, void *pool, unsigned *slot, int flag); /* 0x10db84 */
int parse_tracks(void *reader);                                                    /* 0xd7888 */
void *menu_item_at(void *menu_data, int row);                                      /* 0x2183ec */
void *browser_main(void *browser);                                                 /* 0x9bc6c */
void *browser_db(void *browser);                                                   /* 0x9bb98 */
void browser_clear_artists(void *browser);                                         /* 0xa34b8 */
void *sort_list_entry(void *db, int list, int flags, unsigned n);                  /* 0x9c8e4 */
unsigned track_filter(void *browser, void *entry, int zero);                       /* 0x1142a8 */
void *entry_track(void *entry);                                                    /* 0x9e418 */
void track_artist_text(void *track, const u16 **text, unsigned *units);            /* 0x9f904 */
void pool_text(void *pool, unsigned index, const u16 **text, unsigned *bytes);     /* 0x9efe0 */
int text_compare(void *data, const u16 *a, unsigned a_units, const u16 *b, unsigned b_units); /* 0x91c7c */
void pools_lock(void *track_data);                                                 /* 0xa7200 */
void pools_unlock(void *track_data);                                               /* 0xb9f20 */
void pool_lock(void *pool);                                                        /* 0xa71d8 */
void pool_unlock(void *pool);                                                      /* 0xb9ef4 */
void *list_alloc(unsigned size);                                                   /* 0xa8178 */
void *fw_alloc(unsigned size);                                                     /* 0x25a974 */
void fw_free(void *p);                                                             /* 0x25a8e4 */
unsigned menu_bit(int label);                                                      /* 0x105a04 */
void *settings_object(void);                                                       /* 0x193090 */
int main_menu_visible(void *settings, int label);                                  /* 0x193470 */
void reset_continue(void);                                                         /* 0x1e7b9c */
void clear_continue(void);                                                         /* 0xa34bc */
void visible_continue(void);                                                       /* 0x19ed5c */
void set_main_menu_visible(void *settings, int label, int on);                     /* 0x19351c */
const char *str_lookup(void *table, int id);                                       /* 0x21f418 */
void *str_table(void);                                                             /* 0x21f3b8 */
void mhod_done(void);                                                              /* 0xd821c */
void build_continue(void);                                                         /* 0xd0810 */
void lookup_continue(void);                                                        /* 0x21f258 */
/* Set by the patcher (chain): the previous targets of the hooks. */
void *lookup_next(void *provider, unsigned type, int id);
int activate_next(void *list, int row);
int visible_next(void *screen, int menu, int label, int kind, int visible);
int get_next(void *self, unsigned op, unsigned key, void *out);
int set_next(void *self, unsigned op, unsigned key, void *value);

#define TAG_STR        0x53747220u                     /* 'Str ' */
#define LABEL_ID       0x7e03                          /* the label "Album Artists" */
#define SETTINGS_LABEL_ID 0x7e04                       /* the label in Settings > Main Menu */
#define ROW_KEY        0x7e05                          /* the key of that row (patch.json: 0x60007e05) */
#define OP_TEXT_ID     0x70724944u                     /* 'prID': the ID of the value text */
#define OP_TEXT        0x53747220u                     /* 'Str ': the value text */
#define NOTIFY_BOOL    0x426f6f6cu                     /* 'Bool': the notice after a change */
#define STR_ON         0x602e
#define STR_OFF        0x602f
#define MAIN_MENU_ID   24094
#define ARTISTS_LABEL  0x5f7c                          /* Artists in the main menu */
#define TITLE_ID       (-30)                           /* the title of the Artists screen */
#define MAIN_MENU_BIT  0x40000000u                     /* a free bit of the main menu mask */
#define FIELD_ARTIST   4
#define SORT_ARTIST    7                               /* the sort list in the order of the Artist */
#define FIELD(type, object, offset) (*(type *)((char *)(object) + (offset)))

static const char label[] = "Album Artists";
/* The rows under Music in Settings > Main Menu start with U+2003 and U+2060, as Str -162. */
static const char settings_label[] = "\xe2\x80\x83\xe2\x81\xa0" "Album Artists";

static int aa_pending;         /* 1 after a selection of a copy, until the next browse starts */
static void *aa_browser;       /* the native browser of the browse in album artist mode, or 0 */
static unsigned *aa_list;      /* the list that the patch built (browser + 0xc48), until it is freed */

/* The side table: open addressing, key = track pointer, value = the index of the Album Artist in
 * the artist pool. Only the tracks whose Album Artist is not their Artist have an entry. */
struct entry { void *track; unsigned index; };
static struct entry *table;
static unsigned capacity, used;

static unsigned slot_of(void *track)
{
    unsigned h = (unsigned)track >> 2;
    h ^= h >> 15;
    h *= 0x2c1b3c6du;
    h ^= h >> 12;
    return h & (capacity - 1);
}

static void table_clear(void)
{
    fw_free(table);
    table = 0;
    capacity = used = 0;
}

static int table_grow(void)
{
    struct entry *old = table;
    unsigned old_capacity = capacity, i, n = capacity ? capacity * 2 : 256;
    struct entry *t = fw_alloc(n * sizeof *t);
    if (!t)
        return 0;
    for (i = 0; i < n; i++)
        t[i].track = 0;
    table = t;
    capacity = n;
    for (i = 0; i < old_capacity; i++) {
        if (old[i].track) {
            unsigned s = slot_of(old[i].track);
            while (table[s].track)
                s = (s + 1) & (capacity - 1);
            table[s] = old[i];
        }
    }
    fw_free(old);
    return 1;
}

static unsigned table_get(void *track)
{
    unsigned s;
    if (!capacity)
        return 0;
    for (s = slot_of(track); table[s].track; s = (s + 1) & (capacity - 1))
        if (table[s].track == track)
            return table[s].index;
    return 0;
}

/* 1 if the pool indexes a and b have the same text. Each track has its own index, also for the
 * same text, thus the indexes alone do not tell. */
static int same_text(void *pool, unsigned a, unsigned b)
{
    const u16 *ta, *tb;
    unsigned na = 0, nb = 0, i;
    if (a == b)
        return 1;
    if (!a || !b)
        return 0;
    pool_text(pool, a, &ta, &na);
    pool_text(pool, b, &tb, &nb);
    if (na != nb)
        return 0;
    for (i = 0; i < na / 2 && ta[i] == tb[i]; i++)
        ;
    return i == na / 2;
}

/* Called by hook A after the read of mhod 22. `index` is 0 for an empty text. A track whose Album
 * Artist is its Artist gets no entry. */
void aa_store(void *track, unsigned index)
{
    void *pool = (char *)FIELD(void *, track, 0) + 0xe0;
    unsigned s;
    int same;
    if (!index)
        return;
    pool_lock(pool);
    same = same_text(pool, index, FIELD(unsigned, track, 0x2c));
    pool_unlock(pool);
    if (same)
        return;
    if (used + 1 > capacity / 4 * 3 && !table_grow())
        return;
    for (s = slot_of(track); table[s].track && table[s].track != track; s = (s + 1) & (capacity - 1))
        ;
    if (!table[s].track)
        used++;
    table[s].track = track;
    table[s].index = index;
}

/* Hook A: the mhod 22 entry of the jump table. The registers are as in the Artist case at 0xd7f58:
 * r4 = track, r5 = mhod type, r6 = database, sb = file reader. The read goes into a slot on the
 * stack, not into the track. Then the loop continues at 0xd821c with the result in r5. */
__attribute__((naked)) void hook_mhod22(void)
{
    __asm__ volatile(
        "sub   sp, sp, #16\n"           /* [sp], [sp, #4]: arguments 5 and 6; [sp, #8]: the slot */
        "mov   r0, #0\n"
        "str   r0, [sp, #8]\n"
        "add   r2, sp, #8\n"
        "mov   r3, #1\n"
        "stm   sp, {r2, r3}\n"
        "add   r3, r6, #0xe0\n"         /* the artist pool */
        "mov   r2, r5\n"
        "mov   r1, #1\n"
        "mov   r0, sb\n"
        "bl    db_read_string\n"
        "mov   r5, r0\n"
        "mov   r0, r4\n"
        "ldr   r1, [sp, #8]\n"
        "bl    aa_store\n"
        "add   sp, sp, #16\n"
        "b     mhod_done\n");
}

/* Hook B: replaces "bl parse_tracks" in the loader. A new load makes new tracks and new pools. */
int hook_load_tracks(void *reader)
{
    table_clear();
    aa_list = 0;
    return parse_tracks(reader);
}

/* Hook C: a selection in a menu list. list + 0x144 is the menu data (0 for other lists). */
int hook_activate(void *list, int row)
{
    void *data = FIELD(void *, list, 0x144);
    if (data) {
        void *item = menu_item_at(data, row);
        const char *res = item ? FIELD(const char *, item, 0x10) : 0;
        aa_pending = res && FIELD(short, res, 0x14) == LABEL_ID;
        if (!aa_pending)
            aa_browser = 0;
    }
    return activate_next(list, row);
}

/* The replaced first instruction of 0x1e7b98, then the rest of the function. */
__attribute__((naked)) void reset_original(void *js_browser)
{
    __asm__ volatile("push {r4, lr}\n\tb reset_continue\n");
}

/* Hook G: the start of a browse. The JS browser has the native browser at +0x1c. The main menu item
 * runs the reset two times, thus a reset without a pending selection does not clear the mode.
 * Hook C clears it at the selection of another item. */
void hook_reset(void *js_browser)
{
    if (aa_pending) {
        aa_browser = FIELD(void *, js_browser, 0x1c);
        aa_pending = 0;
    }
    reset_original(js_browser);
}

/* The replaced first instruction of 0xa34b8, then the rest of the function. */
__attribute__((naked)) void clear_original(void *browser)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb clear_continue\n");
}

/* Hook H: the clear of the Artists list. With the build 0xd080c, it is the only code that writes
 * browser + 0xc48. Thus aa_list is exact: it is the list of the patch until this clear frees it. */
void hook_clear(void *browser)
{
    if (aa_list && FIELD(unsigned *, browser, 0xc48) == aa_list)
        aa_list = 0;
    clear_original(browser);
}

/* The index of the name that the Album Artists list uses for a track. */
static unsigned effective_index(void *track)
{
    unsigned index = table_get(track);
    return index ? index : FIELD(unsigned, track, 0x2c);
}

static int compare_index(void *data, void *pool, unsigned a, unsigned b)
{
    const u16 *ta, *tb;
    unsigned na = 0, nb = 0;
    if (a == b)
        return 0;
    pool_text(pool, a, &ta, &na);
    pool_text(pool, b, &tb, &nb);
    return text_compare(data, ta, na >> 1, tb, nb >> 1);
}

static void sift(unsigned *v, unsigned root, unsigned n, void *data, void *pool)
{
    for (;;) {
        unsigned child = root * 2 + 1, t;
        if (child >= n)
            return;
        if (child + 1 < n && compare_index(data, pool, v[child], v[child + 1]) < 0)
            child++;
        if (compare_index(data, pool, v[root], v[child]) >= 0)
            return;
        t = v[root];
        v[root] = v[child];
        v[child] = t;
        root = child;
    }
}

/* A heap sort by the text of the names (the slow compare of the lists). */
static void sort(unsigned *v, unsigned n, void *data, void *pool)
{
    unsigned i, t;
    for (i = n / 2; i > 0; i--)
        sift(v, i - 1, n, data, pool);
    for (i = n; i > 1; i--) {
        t = v[0];
        v[0] = v[i - 1];
        v[i - 1] = t;
        sift(v, 0, i - 1, data, pool);
    }
}

/* FNV-1a of the UTF-16 units of a name. */
static unsigned text_hash(const u16 *t, unsigned units)
{
    unsigned h = 0x811c9dc5u, i;
    for (i = 0; i < units; i++)
        h = (h ^ t[i]) * 0x01000193u;
    return h;
}

/* Keeps one index for each text in v[0 ... m-1] and returns the new count. Each track has its own
 * index in the pool, also for the same text. Thus a sort of all the indexes compares each track:
 * too slow for a large library. A hash of the text finds the exact copies in one pass. */
static unsigned unique_texts(unsigned *v, unsigned m, void *pool)
{
    unsigned size = 16, k = 0, i, *slots, *hashes;
    while (size < m * 2)
        size *= 2;
    slots = fw_alloc(size * 4);
    hashes = fw_alloc(m * 4);
    if (!slots || !hashes) {
        fw_free(slots);
        fw_free(hashes);
        return m;
    }
    for (i = 0; i < size; i++)
        slots[i] = 0;
    for (i = 0; i < m; i++) {
        const u16 *t;
        unsigned units = 0, h, s;
        pool_text(pool, v[i], &t, &units);
        units >>= 1;
        h = text_hash(t, units);
        for (s = h & (size - 1); slots[s]; s = (s + 1) & (size - 1)) {
            unsigned j = slots[s] - 1, other_units = 0, u;
            const u16 *o;
            if (hashes[j] != h)
                continue;
            pool_text(pool, v[j], &o, &other_units);
            if (other_units >> 1 != units)
                continue;
            for (u = 0; u < units && o[u] == t[u]; u++)
                ;
            if (u == units)
                break;
        }
        if (slots[s])
            continue;                   /* the same text is already in v[0 ... k-1] */
        hashes[k] = h;
        v[k] = v[i];
        slots[s] = ++k;
    }
    fw_free(slots);
    fw_free(hashes);
    return k;
}

/* The Artists list in aa_mode: the same result fields as 0xd080c with field 4, but one row for each
 * Album Artist. There is no letter table (+0xc4c = 0), as for a database without mhod 53. */
static int build_album_artists(void *browser)
{
    void *db = browser_db(browser), *main = browser_main(browser), *track_data, *pool, *data;
    char *header;
    unsigned n, i, m = 0, k, *v;
    if (!db || !main)
        return -50;
    header = FIELD(char *, db, 0x28);
    n = FIELD(u16, header, 0x30) + FIELD(u16, header, 0x32);
    if (!n)
        return 0;
    v = list_alloc(n * 4);
    if (!v)
        return -108;
    track_data = FIELD(void *, main, 0xcf8);
    data = FIELD(void *, main, 0xca0);
    pool = (char *)track_data + 0xe0;
    pools_lock(track_data);
    for (i = 0; i < n; i++) {
        void *entry = sort_list_entry(db, SORT_ARTIST, 0, i), *track;
        unsigned index;
        if (!entry || !(track_filter(browser, entry, 0) & 1))
            continue;
        track = entry_track(entry);
        index = track ? effective_index(track) : 0;
        if (index)
            v[m++] = index;
    }
    /* Remove the same texts, then sort by the text, then join the names that compare as equal. */
    k = unique_texts(v, m, pool);
    sort(v, k, data, pool);
    for (i = m = 0; i < k; i++)
        if (!m || compare_index(data, pool, v[m - 1], v[i]))
            v[m++] = v[i];
    pools_unlock(track_data);
    FIELD(unsigned *, browser, 0xc48) = v;
    FIELD(void *, browser, 0xc4c) = 0;
    FIELD(unsigned, browser, 0xc50) = m;
    aa_list = v;
    return 0;
}

/* The replaced first instruction of 0xd080c, then the rest of the function. */
__attribute__((naked)) int build_original(void *browser, int x, unsigned field, unsigned sub)
{
    __asm__ volatile("push {r0, r1, r2, r3, r4, r5, r6, r7, r8, sb, sl, fp, ip, lr}\n\tb build_continue\n");
}

/* Hook D: the list build. The browser keeps one Artists list. A list of the other mode is cleared
 * first (hook H then clears aa_list), so that a change of the mode builds the list again. */
int hook_build(void *browser, int x, unsigned field, unsigned sub)
{
    if (field == FIELD_ARTIST && sub == 0) {
        unsigned *current;
        int mode;
        current = FIELD(unsigned *, browser, 0xc48);
        mode = aa_browser && browser == aa_browser;
        int ours = current && current == aa_list;
        if (current && ours != mode) {
            browser_clear_artists(browser);
            current = 0;
        }
        if (mode)
            return current ? 0 : build_album_artists(browser);
    }
    return build_original(browser, x, field, sub);
}

/* Hook E: replaces "bl track_artist_text" in the filter 0x1142a8. r5 is the browser there. */
__attribute__((naked)) void hook_filter_text(void)
{
    __asm__ volatile("mov r3, r5\n\tb filter_text\n");
}

void filter_text(void *track, const u16 **text, unsigned *units, void *browser)
{
    unsigned index = aa_browser && browser == aa_browser ? table_get(track) : 0;
    if (!index) {
        track_artist_text(track, text, units);
        return;
    }
    pool_text((char *)FIELD(void *, track, 0) + 0xe0, index, text, units);
    *units >>= 1;
}

/* Hooks I and J: the two calls of 0x105a04 (label -> bit of the main menu mask) in 0x193470 (get)
 * and 0x19351c (set). The bit is not used by the firmware, also not by the merge of new defaults
 * at the load (mask 0x1fffffff, 0xaf838). The default mask does not have it: the item is off. */
unsigned hook_menu_bit(int label)
{
    return label == LABEL_ID ? MAIN_MENU_BIT : menu_bit(label);
}

/* The replaced first instruction of the lookup. lookup_next is this function if no other patch
 * hooks the lookup. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

/* Hook F: the labels of the items, and the title of the screen in album artist mode. */
void *hook_lookup(void *provider, unsigned type, int id)
{
    if (type == TAG_STR && (id == LABEL_ID || (aa_browser && (short)id == TITLE_ID)))
        return (void *)label;
    if (type == TAG_STR && id == SETTINGS_LABEL_ID)
        return (void *)settings_label;
    return lookup_next(provider, type, id);
}

/* The replaced first instruction of 0x19ed58, then the rest of the function. visible_next is this
 * function if no other patch hooks 0x19ed58 (version 1.3: usb-audio-out also hooks it). */
__attribute__((naked)) int visible_original(void *screen, int menu, int label, int kind, int visible)
{
    __asm__ volatile("push {r2, r3, r4, lr}\n\tb visible_continue\n");
}

/* Hook K: show or hide an item of a menu. The UI script does this for each Apple item of the main
 * menu, at the start and each time the main menu shows. It does not know the copy, so the patch
 * does it for the copy when the script does it for Artists. */
int hook_set_visible(void *screen, int menu, int label, int kind, int visible)
{
    int result = visible_next(screen, menu, label, kind, visible);
    if (menu == MAIN_MENU_ID && label == ARTISTS_LABEL)
        visible_next(screen, menu, LABEL_ID, kind, main_menu_visible(settings_object(), LABEL_ID) != 0);
    return result;
}

/* Hook L: the row in Settings > Main Menu. The patch gives the value text. For the other questions
 * (for example 'BMap'), the firmware answers as for the Artists row. */
int hook_settings_get(void *self, unsigned op, unsigned key, void *out)
{
    if (key == ROW_KEY) {
        short value = main_menu_visible(self, LABEL_ID) ? STR_ON : STR_OFF;
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = value;
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = str_lookup(str_table(), value);
            return 1;
        }
        key = ARTISTS_LABEL;
    }
    return get_next(self, op, key, out);
}

/* Hook M: a selection of the row switches the bit, as the firmware does for its rows (0x192774):
 * 0x19351c writes the mask, then a 'Bool' notice (method +0x54) shows the new value. */
int hook_settings_set(void *self, unsigned op, unsigned key, void *value)
{
    if (key == ROW_KEY) {
        set_main_menu_visible(self, LABEL_ID, !main_menu_visible(self, LABEL_ID));
        (*(void (**)(void *, unsigned, unsigned))(*(char **)self + 0x54))(self, NOTIFY_BOOL, key);
        return 1;
    }
    return set_next(self, op, key, value);
}
