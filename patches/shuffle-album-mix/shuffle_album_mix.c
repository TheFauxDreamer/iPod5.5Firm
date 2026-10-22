/* shuffle-album-mix: a 4th value of Settings > Shuffle, "Album Mix" (RetailOS 1.3, iPod Video).
 *
 * The firmware has a hidden shuffle mode: the settings byte +0x93 also shuffles the songs in each
 * album. No menu item sets it. The research is in re/shuffle.md, sections "Who sets +0x93" and
 * "The patch shuffle-album-mix". The mode has Bug 3, thus the patch needs shuffle-fixes.
 *
 * Mode 3 is "Album Mix": +0x20 = 1, +0x92 = 1 and +0x93 = 1. Modes 0, 1 and 2 set +0x93 to 0.
 *
 * Hooks:
 *  - the two calls of 0x9edb0 that load the mode of the Settings controller (0x1929a0, 0x193b9c);
 *  - the call of the setter 0xb3a04 in the Select of the Shuffle item (0x191eb0);
 *  - the "get" method of the settings object (vtable 0x66c94c): the value text of the Shuffle item
 *    (key 0x6057) in mode 3. The firmware text is the string 0x6058 + mode, but 0x605b is the key of
 *    the Repeat item, and the menu shows a string with the key of a row. Thus mode 3 uses MIX_ID;
 *  - the general resource lookup (0x21f254): the text of MIX_ID.
 * The "bytes" of patch.json change the wrap of the mode from "after 2" to "after 3" (0x191e9c).
 *
 * Version 1.2 adds a main menu item "Shuffle: <value>" after Shuffle Songs, with the method of
 * usb-audio-out 1.3. Select goes to the next value, as in Settings > Shuffle. Settings > Main Menu
 * has a Shuffle row that shows or hides the item. The default is Off. More hooks:
 *  - the "activate" method of the menu lists (vtable 0x6776f8): a selection of the item;
 *  - the "set" method of the settings object (vtable 0x66c950): the Settings > Main Menu row;
 *  - the first instruction of 0x105a04 (label -> bit of the main menu mask): the bit of the item;
 *  - the first instruction of 0x19ed58 (show or hide an item of a menu): the item follows its bit. */

int get_mode(void *app);                                                           /* 0x9edb0 */
void set_shuffle(void *app, int mode);                                             /* 0xb3a04 */
void mark_changed(void *settings);                                                 /* 0xa983c */
void refresh_shuffle(void *app);                                                   /* 0x11147c */
const char *str_lookup(void *table, int id);                                       /* 0x21f418 */
void *str_table(void);                                                             /* 0x21f3b8 */
void *settings_object(void);                                                       /* 0x193090 */
int main_menu_visible(void *settings, int label);                                  /* 0x193470 */
void set_main_menu_visible(void *settings, int label, int on);                     /* 0x19351c */
void *menu_item_at(void *menu_data, int row);                                      /* 0x2183ec */
void list_select(void *list, int row, unsigned tag);              /* 0x239f7c: tag 0 = no selection event */
void menu_bit_continue(void);                                                      /* 0x105a08 */
void visible_continue(void);                                                       /* 0x19ed5c */
/* Set by the patcher (chain): the previous targets of the hooks. */
void *lookup_next(void *provider, unsigned type, int id);
int get_next(void *self, unsigned op, unsigned key, void *out);
int set_next(void *self, unsigned op, unsigned key, void *value);
int activate_next(void *list, int row);
unsigned menu_bit_next(int label);
int visible_next(void *screen, int menu, int label, int kind, int visible);

#define TAG_STR    0x53747220u                         /* 'Str ' */
#define OP_TEXT_ID 0x70724944u                         /* 'prID': the ID of the value text */
#define OP_TEXT    0x53747220u                         /* 'Str ': the value text */
#define KEY        0x6057u                             /* the Shuffle item */
#define MIX_ID     0x7e10                              /* the value text "Album Mix" */
#define NOTIFY_BOOL 0x426f6f6cu                        /* 'Bool': the notice after a change */
#define STR_ON     0x602e
#define STR_OFF    0x602f
#define STR_SHUFFLE (-135)                             /* "Shuffle", the label of Settings > Shuffle (0xff79) */
#define STR_MODE_0 0x6058                              /* "Off"; 0x6059 "Songs", 0x605a "Albums" */
#define MAIN_ITEM_ID 0x7e11                            /* the main menu item: "Shuffle: Off" and so on */
#define ROW_LABEL  0x7e12                              /* the text of the Settings > Main Menu row */
#define ROW_KEY    0x7e13                              /* the row in Settings > Main Menu (patch.json: 0x60007e13) */
#define SHUFFLE_SONGS 0x5f9e                           /* Shuffle Songs: the template of the item and of the row */
#define ARTISTS_LABEL 0x5f7c                           /* Artists in the main menu */
#define MAIN_MENU_ID 24094
#define MAIN_MENU_BIT 0x20000000u                      /* a free bit of the main menu mask (outside the merge mask 0x1fffffff) */
#define SETTINGS(app) (*(unsigned char **)((char *)(app) + 0xca0))
#define APP(settings) (*(void **)((char *)(settings) + 0x98))  /* the main browser */

static const char mix_text[] = "Album Mix";
static char item_text[64];                             /* the text of the main menu item */

/* The mode for the Settings controller: 3 if Albums and +0x93 are set. */
int hook_get_mode(void *app)
{
    int mode = get_mode(app);
    if (mode == 2 && SETTINGS(app)[0x93])
        return 3;
    return mode;
}

/* Select of the Shuffle item. The setter knows only the modes 0-2. Between Albums and Album Mix it
 * changes nothing and returns early, thus the hook marks the change and refreshes the shuffle. */
void hook_set_mode(void *app, int mode)
{
    unsigned char *s = SETTINGS(app);
    int mix = mode == 3;
    int was = get_mode(app);
    if (s[0x93] != mix) {
        s[0x93] = mix;
        mark_changed(s);
        if (was == 2 && (mix || mode == 2)) {
            refresh_shuffle(app);
            return;
        }
    }
    set_shuffle(app, mix ? 2 : mode);
}

/* The value text of the Shuffle item in mode 3. The controller keeps the mode at self + 0x1c. */
int hook_settings_get(void *self, unsigned op, unsigned key, void *out)
{
    if (key == KEY && *((unsigned char *)self + 0x1c) == 3) {
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = MIX_ID;
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = mix_text;
            return 1;
        }
    }
    if (key == ROW_KEY) {                              /* Settings > Main Menu > Shuffle */
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
        key = SHUFFLE_SONGS;                           /* the other questions: as for the Shuffle Songs row */
    }
    return get_next(self, op, key, out);
}

/* The first instruction of the general lookup (0x21f254) is replaced by a branch. If no other patch
 * hooks the lookup, lookup_next is this function: it runs that instruction and continues in the firmware. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

/* Copy src to the end of the text in dst. Stop at the end of item_text. */
static char *append(char *dst, const char *src)
{
    char *end = item_text + sizeof item_text - 1;
    while (src && *src && dst < end)
        *dst++ = *src++;
    *dst = 0;
    return dst;
}

/* "Shuffle: " and the value text, in the language of the iPod. "Album Mix" is in English. */
static const char *main_item_text(void)
{
    int mode = hook_get_mode(APP(settings_object()));
    char *p = append(item_text, str_lookup(str_table(), STR_SHUFFLE));
    p = append(p, ": ");
    append(p, mode == 3 ? mix_text : str_lookup(str_table(), STR_MODE_0 + mode));
    return item_text;
}

void *hook_lookup(void *provider, unsigned type, int id)
{
    if (type == TAG_STR && id == MIX_ID)
        return (void *)mix_text;
    if (type == TAG_STR && id == MAIN_ITEM_ID)
        return (void *)main_item_text();
    if (type == TAG_STR && id == ROW_LABEL)
        return (void *)str_lookup(str_table(), STR_SHUFFLE);
    return lookup_next(provider, type, id);
}

/* ---- Version 1.2: the item in the main menu ---------------------------------------------------------- */

/* A selection in a menu list (vtable slot 0x6776f8, chain: album-artists and usb-audio-out also hook it).
 * list + 0x144 is the menu data (0 for other lists), the item + 0x10 its resource, and resource + 0x14
 * the label. */
int hook_activate(void *list, int row)
{
    void *data = *(void **)((char *)list + 0x144);
    void *item = data ? menu_item_at(data, row) : 0;
    const char *res = item ? *(const char **)((char *)item + 0x10) : 0;
    if (res && *(const short *)(res + 0x14) == MAIN_ITEM_ID) {
        unsigned char *settings = settings_object();
        int mode = (hook_get_mode(APP(settings)) + 1) & 3;
        hook_set_mode(APP(settings), mode);
        settings[0x1c] = mode;                         /* the mode that Settings > Shuffle shows */
        list_select(list, row, 0);                     /* the row again, with the new text */
        return 0;                                      /* not the Shuffle Songs action of the template */
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

/* Select of the Settings > Main Menu row, as the firmware does for its rows (0x192774). */
int hook_settings_set(void *self, unsigned op, unsigned key, void *value)
{
    if (key == ROW_KEY) {
        set_main_menu_visible(self, MAIN_ITEM_ID, !main_menu_visible(self, MAIN_ITEM_ID));
        (*(void (**)(void *, unsigned, unsigned))(*(char **)self + 0x54))(self, NOTIFY_BOOL, key);
        return 1;
    }
    return set_next(self, op, key, value);
}
