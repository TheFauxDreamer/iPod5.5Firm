/* Dark Mode On/Off and Split View On/Off in the Settings menu of RetailOS 1.3 (iPod Video).
 *
 * The build (ipodfw.darkmode / DarkMode.swift) puts these items in the osos image:
 *  - dark_table: "IFD2" (ipodfw.darktable / DarkTable.swift): records RAW, MAP (a colour map of the
 *    light picture) and PAL (a palette). Or "IFDM" if that is smaller;
 *  - layout_table, and dark_table in the format "IFDM": u32 count N, u32 data offset, N entries
 *    { u32 address, u32 length }, then the data: old XOR new. A table with N = 0 does nothing;
 *  - the Settings menu (Menu 24598) with the Dark Mode item (key DARK_KEY) if the appearance is
 *    "Switch on iPod", and the Split View item (key LAYOUT_KEY) if the layout is "Switch on iPod".
 *
 * RetailOS makes its screens one time, at the start, from the View resources. Thus the patch
 * applies the tables at the start, before the first View is read, at the first lookup of a View:
 *  - dark_table if iPod_Control\iTunes\iPodFirmDarkMode contains '1' (no file: light);
 *  - layout_table if iPod_Control\iTunes\iPodFirmLayout contains '0' (no file: Split). The image has
 *    the Split main menu, and the table changes the table entry of View 24430 back to the stock View.
 * When the owner selects an item, the patch writes the other value, saves the settings of the iPod
 * and restarts it.
 *
 * Hooks:
 *  - the first instruction of the general resource lookup (0x21f254): all resource and string
 *    lookups pass there;
 *  - the "get" and "set" methods of the settings object (vtable 0x66c94c and 0x66c950). */

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
#define MAGIC2       0x32444649u                       /* "IFD2" */
#define LIMIT        0x800000u                         /* the end of the OS image */
#define RAW          0
#define MAP          1
#define PAL          2
#define TAG_VIEW     0x56696577u                       /* 'View' */
#define TAG_STR      0x53747220u                       /* 'Str ' */
#define OP_TEXT_ID   0x70724944u                       /* 'prID': the ID of the value text */
#define OP_TEXT      0x53747220u                       /* 'Str ': the value text */
#define DARK_KEY     0x60e0u                           /* the Dark Mode item */
#define LAYOUT_KEY   0x7e15u                           /* the Split View item (not a firmware key) */
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

/* Each u16 that is a light value in the list becomes the dark value. The pairs are sorted by the
 * light value. The decoder searches again only when the value differs from the value before. */
static void apply_map(unsigned short *px, unsigned n, const unsigned short *pairs, unsigned count)
{
    unsigned i, last = 0x10000, out = 0;
    for (i = 0; i < n; i++) {
        unsigned x = px[i];
        if (x != last) {
            unsigned lo = 0, hi = count;
            last = x;
            out = x;
            while (lo < hi) {
                unsigned mid = (lo + hi) >> 1, key = pairs[2 * mid];
                if (key == x) {
                    out = pairs[2 * mid + 1];
                    break;
                }
                if (key < x)
                    lo = mid + 1;
                else
                    hi = mid;
            }
        }
        px[i] = out;
    }
}

/* Each u16 gets a colour of the palette. The indices have `bits` bits, MSB first. */
static void apply_pal(unsigned short *px, unsigned n, const unsigned short *colours, unsigned count,
                      const unsigned char *index, unsigned bits)
{
    unsigned i, mask = (1u << bits) - 1;
    for (i = 0; i < n; i++) {
        unsigned bit = i * bits;
        unsigned v = (index[bit >> 3] >> (8 - bits - (bit & 7))) & mask;
        if (v < count)
            px[i] = colours[v];
    }
}

/* The IFD2 table. The decoder stops at an unknown kind and at a record that does not fit before the
 * end of the table. It skips a record whose range is not below LIMIT. */
static void apply_table2(const unsigned *t)
{
    const unsigned char *p, *end;
    unsigned n, i;
    if (t[2] < 12)
        return;
    n = t[1];
    p = (const unsigned char *)(t + 3);
    end = (const unsigned char *)t + t[2];
    for (i = 0; i < n && end - p >= 8; i++) {
        const unsigned *h = (const unsigned *)p;
        unsigned at = h[0], kind = h[1] >> 28, len = h[1] & 0x0fffffffu;
        unsigned room, size;                    /* the bytes after the record head, and the data size */
        int ok = at < LIMIT && len <= LIMIT - at;
        unsigned char *dst = (unsigned char *)at;
        p += 8;
        room = (unsigned)(end - p);
        if (kind == RAW) {
            unsigned k;
            if (len > room - (room & 3))
                return;
            if (ok)
                for (k = 0; k < len; k++)
                    dst[k] = p[k];
            size = (len + 3) & ~3u;
        } else if (kind == MAP) {
            unsigned count;
            if (room < 4)
                return;
            count = *(const unsigned *)p;
            if (count > (room - 4) >> 2)
                return;
            if (ok && !((at | len) & 1))
                apply_map((unsigned short *)dst, len >> 1, (const unsigned short *)(p + 4), count);
            size = 4 + 4 * count;
        } else if (kind == PAL) {
            unsigned count, bits, head, bytes;
            if (room < 4)
                return;
            count = ((const unsigned short *)p)[0];
            bits = ((const unsigned short *)p)[1];
            if (bits != 1 && bits != 2 && bits != 4 && bits != 8)
                return;
            head = 4 + ((2 * count + 3) & ~3u);
            bytes = ((len >> 1) * bits + 7) >> 3;
            if (head > room || ((bytes + 3) & ~3u) > room - head)
                return;
            if (ok && !((at | len) & 1))
                apply_pal((unsigned short *)dst, len >> 1, (const unsigned short *)(p + 4), count, p + head, bits);
            size = head + ((bytes + 3) & ~3u);
        } else {
            return;
        }
        p += size;
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

/* The first instruction of the general lookup (0x21f254) is replaced by a branch to
 * hook_lookup. This function runs that instruction and continues in the firmware function. */
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
        if (dark && dark_table[0] == MAGIC2)
            apply_table2(dark_table);
        else if (dark)
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
