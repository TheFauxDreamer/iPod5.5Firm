/* Test patch: draw a bar at the left of each label.
   It shows that the patch tools, the hooks and the drawing functions operate correctly. */

typedef struct { int left, top, right, bottom; } Rect;

void label_draw(void *view, void *a2, void *a3);          /* firmware 0x244924 */
void view_bounds(void *view, Rect *r);                    /* firmware 0x255ac4 */
void gc_set_color(void *gc, const unsigned char *rgba);   /* firmware 0x2106e4 */
void gc_set_mode(void *gc, int mode);                     /* firmware 0x210290 */
void gc_fill_rect(void *gc, Rect *r);                     /* firmware 0x211a00 */

static const unsigned char marker_color[4] = { 0xff, 0x00, 0x00, 0xff };

void hook_label_draw(void *view, void *a2, void *a3)
{
    Rect r;
    void *gc = (char *)view + 0x74;

    label_draw(view, a2, a3);
    view_bounds(view, &r);
    r.right = r.left + 6;
    gc_set_color(gc, marker_color);
    gc_set_mode(gc, 1);
    gc_fill_rect(gc, &r);
}
