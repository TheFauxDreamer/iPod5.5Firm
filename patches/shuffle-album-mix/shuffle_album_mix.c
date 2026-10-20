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
 * The "bytes" of patch.json change the wrap of the mode from "after 2" to "after 3" (0x191e9c). */

int get_mode(void *app);                                                           /* 0x9edb0 */
void set_shuffle(void *app, int mode);                                             /* 0xb3a04 */
void mark_changed(void *settings);                                                 /* 0xa983c */
void refresh_shuffle(void *app);                                                   /* 0x11147c */
/* Set by the patcher (chain): the previous targets of the hooks. */
void *lookup_next(void *provider, unsigned type, int id);
int get_next(void *self, unsigned op, unsigned key, void *out);

#define TAG_STR    0x53747220u                         /* 'Str ' */
#define OP_TEXT_ID 0x70724944u                         /* 'prID': the ID of the value text */
#define OP_TEXT    0x53747220u                         /* 'Str ': the value text */
#define KEY        0x6057u                             /* the Shuffle item */
#define MIX_ID     0x7e10                              /* the value text "Album Mix" */
#define SETTINGS(app) (*(unsigned char **)((char *)(app) + 0xca0))

static const char mix_text[] = "Album Mix";

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
    return get_next(self, op, key, out);
}

/* The first instruction of the general lookup (0x21f254) is replaced by a branch. If no other patch
 * hooks the lookup, lookup_next is this function: it runs that instruction and continues in the firmware. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

void *hook_lookup(void *provider, unsigned type, int id)
{
    if (type == TAG_STR && id == MIX_ID)
        return (void *)mix_text;
    return lookup_next(provider, type, id);
}
