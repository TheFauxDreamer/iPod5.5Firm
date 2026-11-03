/* Research prototype: Dark Mode On/Off and Split View On/Off in the Settings menu of RetailOS 1.3.
 * It is a copy of patches/dark-mode with a second switch table and a second item.
 *
 * The build (re/layout-switch/build.py) puts these items in the osos image:
 *  - dark_table and layout_table: "IFDM", u32 count N, u32 data offset, N entries
 *    { u32 address, u32 length }, then the data: old XOR new. A table with N = 0 does nothing;
 *  - the Settings menu (Menu 24598) with the items of the 2 keys, if the table of the key is not empty.
 *
 * RetailOS makes its screens one time, at the start. Thus the patch applies the 2 tables at the first
 * lookup of a View:
 *  - dark_table if iPod_Control\iTunes\iPodFirmDarkMode contains '1' (no file: light);
 *  - layout_table if iPod_Control\iTunes\iPodFirmLayout contains '0' (no file: Split). The image has
 *    the Split main menu, and the table changes the table entry of View 24430 back to the stock View.
 * When the owner selects an item, the patch writes the other value, saves the settings and restarts.
 *
 * Hooks: the general resource lookup (0x21f254), and the "get" and "set" methods of the settings
 * object (vtable 0x66c94c and 0x66c950). */

const char *str_lookup(void *table, int id);                                       /* 0x21f418 */
void *str_table(void);                                                             /* 0x21f3b8 */
int settings_get(void *self, unsigned op, unsigned key, void *out);                /* 0x190b00 */
int settings_set(void *self, unsigned op, unsigned key, void *value);              /* 0x1919d8 */
void fw_memset0(void *p, unsigned size);
void fw_strcpy(char *dst, const char *src);
int file_open(void *path_record, void *fh, int zero, unsigned mode);
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_read(void *fh, unsigned *len, void *buf);
int file_write(void *fh, unsigned *len, const void *buf);
int file_seek(void *fh, int unused, unsigned long long position);
int file_close(void *fh);
void save_all(void *app);                                                          /* 0x1ee8b8 */
void prepare_restart(void);                                                        /* 0x94e08 */
void restart(void);                                                                /* 0x1630 */
extern const unsigned dark_table[];                                                /* set by the build */
extern const unsigned layout_table[];                                              /* set by the build */

#define MAGIC        0x4d444649u                       /* "IFDM" */
#define TAG_VIEW     0x56696577u                       /* 'View' */
#define TAG_STR      0x53747220u                       /* 'Str ' */
#define OP_TEXT_ID   0x70724944u                       /* 'prID': the ID of the value text */
#define OP_TEXT      0x53747220u                       /* 'Str ': the value text */
#define DARK_KEY     0x60e0u                           /* the Dark Mode item */
#define LAYOUT_KEY   0x60ecu                           /* the Split View item */
#define DARK_LABEL   0x7e00                            /* the label "Dark Mode" */
#define LAYOUT_LABEL 0x7e14                            /* the label "Split View" */
#define STR_ON       0x602e
#define STR_OFF      0x602f
#define APP          (*(void **)0x1081da18)            /* the application object */
#define DARK_FILE    "iPod_Control\\iTunes\\iPodFirmDarkMode"
#define LAYOUT_FILE  "iPod_Control\\iTunes\\iPodFirmLayout"
#define MODE_DATA    0x64617461u                       /* 'data' */

static const char dark_label[] = "Dark Mode";
static const char layout_label[] = "Split View";
static int dark;                                       /* the modes since the start */
static int split;
static int decided;

static void apply_table(const unsigned *t)
{
    unsigned n, i;
    const unsigned char *data;
    if (t[0] != MAGIC)
        return;
    n = t[1];
    data = (const unsigned char *)t + t[2];
    for (i = 0; i < n; i++) {
        unsigned char *p = (unsigned char *)t[3 + 2 * i];
        unsigned len = t[4 + 2 * i], k;
        for (k = 0; k < len; k++)
            p[k] ^= data[k];
        data += len;
    }
}

static void make_path(unsigned *path, const char *name)
{
    fw_memset0(path, 0x108);
    fw_strcpy((char *)path + 4, name);
}

/* The first byte of the file, or 0 if there is no file or an error. */
static unsigned char read_setting(const char *name)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], got = 1;
    unsigned char c = 0;
    int err;
    make_path(path, name);
    fw_memset0(fh, sizeof fh);
    if (file_open(path, fh, 0, MODE_DATA) != 0)
        return 0;
    err = file_read(fh, &got, &c);
    file_close(fh);
    return err == 0 && got == 1 ? c : 0;
}

/* Writes '1' or '0' at the start of the file. The open function makes the file if it is missing. */
static int write_setting(const char *name, int on)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = 1;
    unsigned char c = on ? '1' : '0';
    int err, err2;
    make_path(path, name);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err != 0)
        return err;
    err = file_seek(fh, 0, 0);
    if (err == 0)
        err = file_write(fh, &len, &c);
    err2 = file_close(fh);
    return err != 0 ? err : err2;
}

__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

void *hook_lookup(void *provider, unsigned type, int id)
{
    if (!decided && type == TAG_VIEW) {
        decided = 1;
        dark = read_setting(DARK_FILE) == '1';
        split = read_setting(LAYOUT_FILE) != '0';
        if (dark)
            apply_table(dark_table);
        if (!split)
            apply_table(layout_table);
    }
    if (type == TAG_STR && id == DARK_LABEL)
        return (void *)dark_label;
    if (type == TAG_STR && id == LAYOUT_LABEL)
        return (void *)layout_label;
    return lookup_original(provider, type, id);
}

int hook_settings_get(void *self, unsigned op, unsigned key, void *out)
{
    if (key == DARK_KEY || key == LAYOUT_KEY) {
        short value = (key == DARK_KEY ? dark : split) ? STR_ON : STR_OFF;
        if (op == OP_TEXT_ID) {
            *(short *)((char *)self + 0x88) = value;
            *(void **)out = (char *)self + 0x88;
            return 1;
        }
        if (op == OP_TEXT) {
            *(const char **)out = str_lookup(str_table(), value);
            return 1;
        }
        return 0;
    }
    return settings_get(self, op, key, out);
}

int hook_settings_set(void *self, unsigned op, unsigned key, void *value)
{
    if (key == DARK_KEY || key == LAYOUT_KEY) {
        int err = key == DARK_KEY ? write_setting(DARK_FILE, !dark) : write_setting(LAYOUT_FILE, !split);
        if (err == 0) {
            if (APP)
                save_all(APP);              /* the settings of the iPod, as before a sleep */
            prepare_restart();
            restart();
        }
        return 1;
    }
    return settings_set(self, op, key, value);
}
