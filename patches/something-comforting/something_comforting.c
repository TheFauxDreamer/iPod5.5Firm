/* something-comforting: an example patch. A Settings item plays a part of "Something Comforting"
 * (Porter Robinson) on the piezo of the iPod.
 *
 * The patch is an example of a patch that adds a Settings item, and that can share its hooks with
 * other patches. The patch.json section "settings_items" adds an On/Off item with the key KEY and the
 * label LABEL_ID after Clicker. All three hooks have "chain": if an earlier patch (for example Dark
 * Mode) hooks the same place, this patch calls that hook for all other keys and IDs.
 *
 * Hooks:
 *  - the first instruction of the general resource lookup (0x21f254): the texts of LABEL_ID and
 *    PLAY_ID;
 *  - the "get" method of the settings object (vtable 0x66c94c): the value text "Play" for KEY;
 *  - the "set" method of the settings object (vtable 0x66c950): the melody for KEY.
 *
 * The piezo (re/piezo.md): tone() (0xcd430) puts one note in the queue of the piezo task. The value
 * is a period: Hz = 91225 / value. When a note ends and the queue is empty, the piezo task stops the
 * piezo. Thus a rest is only a wait. The patch sends one note, then waits with a task sleep until the
 * start of the next entry. The time comes from USEC_TIMER, so that the errors of the sleeps do not add.
 * The UI task does not react while the melody plays (approximately 13 s).
 *
 * The note table comes from re/midi-to-tones.py (track 6, bars 41-48: the synth lead).
 * Track 6, bars 41-48, octave shift 0 (74 entries, 12912 ms).
 * Command: python3 re/midi-to-tones.py "Porter Robinson - Something Comforting.mid" 6 41 48 */

int tone(int value, int microseconds);                                             /* 0xcd430 */
void task_sleep(int ms);                                                           /* 0x11c9fc */
/* Set by the patcher (chain): the previous targets of the hooks. */
void *lookup_next(void *provider, unsigned type, int id);
int get_next(void *self, unsigned op, unsigned key, void *out);
int set_next(void *self, unsigned op, unsigned key, void *value);

#define TAG_STR    0x53747220u                         /* 'Str ' */
#define OP_TEXT_ID 0x70724944u                         /* 'prID': the ID of the value text */
#define OP_TEXT    0x53747220u                         /* 'Str ': the value text */
#define KEY        0x60e4u                             /* the item (patch.json: 0x600060e4) */
#define LABEL_ID   0x7e01                              /* the label "Something Comforting" */
#define PLAY_ID    0x7e02                              /* the value text "Play" */
#define USEC_TIMER (*(volatile unsigned *)0x60005010)

static const char label[] = "Something Comforting";
static const char play[] = "Play";

/* {value, ms}: value 0 is a rest. */
static const unsigned short melody[][2] = {
    {   73,    84 },  /* D#6 (1245 Hz) */
    {    0,    20 },  /* gap */
    {   65,    84 },  /* F6 (1397 Hz) */
    {    0,    20 },  /* gap */
    {   73,   188 },  /* D#6 (1245 Hz) */
    {    0,   437 },  /* rest */
    {   98,    84 },  /* A#5 (932 Hz) */
    {    0,    20 },  /* gap */
    {   87,    84 },  /* C6 (1047 Hz) */
    {    0,    20 },  /* gap */
    {   98,   188 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {  131,    84 },  /* F5 (698 Hz) */
    {    0,    20 },  /* gap */
    {  116,    84 },  /* G5 (784 Hz) */
    {    0,    20 },  /* gap */
    {  131,   188 },  /* F5 (698 Hz) */
    {    0,   228 },  /* rest */
    {  147,   188 },  /* D#5 (622 Hz) */
    {    0,   228 },  /* rest */
    {   98,   188 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {   73,    84 },  /* D#6 (1245 Hz) */
    {    0,    20 },  /* gap */
    {   65,    84 },  /* F6 (1397 Hz) */
    {    0,    20 },  /* gap */
    {   73,   188 },  /* D#6 (1245 Hz) */
    {    0,   437 },  /* rest */
    {   98,    84 },  /* A#5 (932 Hz) */
    {    0,    20 },  /* gap */
    {   87,    84 },  /* C6 (1047 Hz) */
    {    0,    20 },  /* gap */
    {   98,   188 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {  131,    84 },  /* F5 (698 Hz) */
    {    0,    20 },  /* gap */
    {  116,    84 },  /* G5 (784 Hz) */
    {    0,    20 },  /* gap */
    {  131,   188 },  /* F5 (698 Hz) */
    {    0,   228 },  /* rest */
    {  147,   188 },  /* D#5 (622 Hz) */
    {    0,   228 },  /* rest */
    {   98,   188 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {   73,    84 },  /* D#6 (1245 Hz) */
    {    0,    20 },  /* gap */
    {   65,    84 },  /* F6 (1397 Hz) */
    {    0,    20 },  /* gap */
    {   73,   188 },  /* D#6 (1245 Hz) */
    {    0,   437 },  /* rest */
    {   98,    84 },  /* A#5 (932 Hz) */
    {    0,    20 },  /* gap */
    {   87,    84 },  /* C6 (1047 Hz) */
    {    0,    20 },  /* gap */
    {   98,   188 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {  131,    84 },  /* F5 (698 Hz) */
    {    0,    20 },  /* gap */
    {  116,    84 },  /* G5 (784 Hz) */
    {    0,    20 },  /* gap */
    {  131,   188 },  /* F5 (698 Hz) */
    {    0,   228 },  /* rest */
    {  147,   188 },  /* D#5 (622 Hz) */
    {    0,   228 },  /* rest */
    {   98,   188 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {   73,   397 },  /* D#6 (1245 Hz) */
    {    0,   437 },  /* rest */
    {   98,   397 },  /* A#5 (932 Hz) */
    {    0,   437 },  /* rest */
    {   73,   397 },  /* D#6 (1245 Hz) */
    {    0,   437 },  /* rest */
    {   65,   397 },  /* F6 (1397 Hz) */
    {    0,    20 },  /* gap */
};

static void play_melody(void)
{
    unsigned start = USEC_TIMER, at = 0, i;
    for (i = 0; i < sizeof melody / sizeof melody[0]; i++) {
        int wait;
        if (melody[i][0] != 0)
            tone(melody[i][0], melody[i][1] * 1000);
        at += melody[i][1] * 1000u;
        wait = (int)(at - (USEC_TIMER - start)) / 1000;
        if (wait > 0)
            task_sleep(wait);
    }
}

/* The first instruction of the general lookup (0x21f254) is replaced by a branch. If no other patch
 * hooks the lookup, lookup_next is this function: it runs that instruction and continues in the firmware. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

void *hook_lookup(void *provider, unsigned type, int id)
{
    if (type == TAG_STR && id == LABEL_ID)
        return (void *)label;
    if (type == TAG_STR && id == PLAY_ID)
        return (void *)play;
    return lookup_next(provider, type, id);
}

int hook_settings_get(void *self, unsigned op, unsigned key, void *out)
{
    if (key == KEY) {
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = PLAY_ID;
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = play;
            return 1;
        }
        return 0;
    }
    return get_next(self, op, key, out);
}

int hook_settings_set(void *self, unsigned op, unsigned key, void *value)
{
    if (key == KEY) {
        play_melody();
        return 1;
    }
    return set_next(self, op, key, value);
}
