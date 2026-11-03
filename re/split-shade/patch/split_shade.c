/* split-shade (test): the Split panel has a label element with the ID SHADE_ID (the count, which always
 * has a text) behind the cover and the text. The firmware does not draw a label that has no data.
 * The hook finds the panel label by its height and fills its rectangle with one colour. All other
 * labels go to the previous target of the hook. */

typedef struct { int top, left, bottom, right; } Rect;

void view_bounds(void *view, Rect *r);
void gc_prepare(void *view, void *gc);
void gc_set_color(void *gc, const unsigned char *rgba);
void gc_set_mode(void *gc, int mode);
void gc_fill_rect(void *gc, Rect *r);
void label_next(void *view, const char *text, void *a3);   /* set by the patcher (chain) */

#define VIEW_GC         0x74   /* the graphics context in a view */
#define VIEW_ELEMENT_ID 0x1c   /* u16: the layout element of a view */
#define SHADE_ID        0x63c3   /* the count, "1 of 12" */
#define SHADE_MIN_HEIGHT 100     /* the count line is 22 pixels high */

static const unsigned char shade[4] = { 0xf0, 0xf0, 0xf0, 0xff };

/* Test counters: all label draws, draws of SHADE_ID, and the first 32 element IDs. */
unsigned dbg[4 + 32] = { 0x53484144 };

void hook_label_draw(void *view, const char *text, void *a3)
{
    Rect r;
    void *gc = (char *)view + VIEW_GC;
    unsigned id = *(unsigned short *)((char *)view + VIEW_ELEMENT_ID), k;
    dbg[1]++;
    for (k = 0; k < 32 && dbg[4 + k] && dbg[4 + k] != id; k++)
        ;
    if (k < 32 && !dbg[4 + k])
        dbg[4 + k] = id;
    if (id == SHADE_ID) {
        view_bounds(view, &r);
        dbg[2]++;
        dbg[3] = (r.left & 0xffff) << 16 | (r.top & 0xffff);
    }
    if (id != SHADE_ID || r.bottom - r.top < SHADE_MIN_HEIGHT) {
        label_next(view, text, a3);
        return;
    }
    gc_prepare(view, gc);
    gc_set_mode(gc, 0);
    gc_set_color(gc, shade);
    gc_fill_rect(gc, &r);
}
