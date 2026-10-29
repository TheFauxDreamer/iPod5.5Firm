/* Experiment 1: select row 0 (Alpha) -> stay on the screen and show a "folder" of Charlie, Delta. */
int label_original(void *br, int index, void *out);
int count_original(void *br);
void select_continue(void);

static int opened;

__attribute__((naked)) int select_original(void *js, int row)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb select_continue\n");
}

static void notify(void *js, unsigned what, unsigned id)
{
    void (*f)(void *, unsigned, unsigned) = *(void (**)(void *, unsigned, unsigned))(*(char **)js + 0x54);
    f(js, what, id);
}

int hook_select(void *js, int row)
{
    if (!opened && row == 0) {
        opened = 1;
        notify(js, 0x564d6178u, 0x6387);  /* 'VMax' */
        notify(js, 0x53747220u, 0x6387);  /* 'Str ' */
        return 0;
    }
    return select_original(js, opened ? row + 2 : row);
}

int hook_label(void *br, int index, void *out)
{
    return label_original(br, opened ? index + 2 : index, out);
}

int hook_count(void *br)
{
    return opened ? 3 : count_original(br);
}
