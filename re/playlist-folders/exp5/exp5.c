/* Experiment 2: Alpha (row 0) is a "folder" of Charlie, Delta, Echo. Select on Alpha changes the
 * list in place. Menu in the folder returns to the top list. */
int label_original(void *br, int index, void *out);
int count_original(void *br);
void select_continue(void);
void vmax_continue(void);
void view_invalidate(void *view);
int list_event(int *list, int *ev, void *a3, int a4);
int ui_event(void *ui, int *ev);
#define EV_KEY_UP 7
#define UI_KEYS_DOWN 0x44
static int swallow_key = -1;

#define EV_KEY_DOWN 4
#define KEY_OF(ev) (((unsigned)(ev)[4] >> 16) & 0xff)
#define KEY_MENU 0x6e
#define KEY_SELECT 0x6f
#define LIST_CELL 0x2a
#define LIST_SELECTION 0x29
#define LIST_SET_SELECTION 0x138
#define VIEW_FLAGS 8
#define VIEW_ELEMENT_ID 0x1c
#define VIEW_CHILD_COUNT 0x7c
#define VIEW_CHILDREN 0x80
#define PLAYLIST_NAME_ID 0x6425

static int opened;
int activate_original(void *list, int row);
static void *last_list, *open_list;
static int last_row, open_row;
static int *open_js;
static int *pf_js;                /* the JS browser of the Playlists screen */

__attribute__((naked)) int select_original(void *js, int row)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb select_continue\n");
}

__attribute__((naked)) void vmax_original(int *js)
{
    __asm__ volatile("push {r4, lr}\n\tb vmax_continue\n");
}

static void notify(void *js, unsigned what, unsigned id)
{
    void (*f)(void *, unsigned, unsigned) = *(void (**)(void *, unsigned, unsigned))(*(char **)js + 0x54);
    f(js, what, id);
}

int hook_select(void *js, int row)
{
    return select_original(js, opened ? row + 2 : row);
}

int hook_label(void *br, int index, void *out)
{
    return label_original(br, opened ? index + 2 : index, out);
}

void hook_vmax(int *js)
{
    if (!opened && js != open_js) {     /* the top Playlists screen: keep the menu row that opened it */
        open_js = js;
        open_list = last_list;
        open_row = last_row;
    }
    pf_js = js;
    vmax_original(js);
}

int hook_count(void *br)
{
    return opened ? 4 : count_original(br);
}

static int is_playlists(int *list)
{
    int *cell = (int *)list[LIST_CELL], k, n;
    int **kids;
    if (!cell || (list[VIEW_FLAGS] & 0x1800) != 0x800)
        return 0;
    n = *(int *)((char *)cell + VIEW_CHILD_COUNT);
    kids = *(int ***)((char *)cell + VIEW_CHILDREN);
    for (k = 0; kids && k < n; k++)
        if (*(unsigned short *)((char *)kids[k] + VIEW_ELEMENT_ID) == PLAYLIST_NAME_ID)
            return 1;
    return 0;
}

__attribute__((unused)) static void change(int *list, int to_open, int row)
{
    opened = to_open;
    if (pf_js) {
        ((int *)pf_js)[0x35] = -2;          /* make hook_vmax see a change */
        vmax_original(pf_js);
        notify(pf_js, 0x53747220u, 0x6387); /* 'Str ' */
    }
    ((void (*)(int *, int))(*(void ***)list)[LIST_SET_SELECTION / 4])(list, row);
    view_invalidate(list);
}

int hook_list_event(int *list, int *ev, void *a3, int a4)
{
    if (ev[1] == EV_KEY_DOWN && is_playlists(list)) {
        int key = KEY_OF(ev);
        int row = *(int *)((char *)list[LIST_SELECTION] + 0x14);
        if (key == KEY_SELECT && !opened && row == 0 && last_list) {
            opened = 1;
            swallow_key = KEY_SELECT;
            activate_original(last_list, last_row);   /* push a second Playlists screen */
            return 1;
        }
        if (key == KEY_MENU && opened) {
            opened = 0;                               /* the firmware pops the screen */
            open_js = 0;
        }
    }
    return list_event(list, ev, a3, a4);
}

/* The UI handler gets each key event before the list, and the events after the push alone. */
int hook_ui_event(void *ui, int *ev)
{
    int type = ev[1];
    if (type > EV_KEY_DOWN && type <= EV_KEY_UP && KEY_OF(ev) == swallow_key) {
        if (type == EV_KEY_UP) {
            unsigned char *down = (unsigned char *)ui + UI_KEYS_DOWN;
            swallow_key = -1;
            if (*down)
                (*down)--;
        }
        return 1;
    }
    return ui_event(ui, ev);
}

int hook_activate(void *list, int row)
{
    last_list = list;
    last_row = row;
    return activate_original(list, row);
}
