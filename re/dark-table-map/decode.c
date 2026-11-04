/* Research only: the decoder of the "IFD2" dark switch table (re/dark-table-map/ifd2.py).
 * No patch uses this file. check.py compiles it with the flags of the patches (Patcher.clangFlags)
 * to measure the code size, and for the Mac to compare its result with the Python model.
 *
 * On the iPod, BASE is 0: the address in a record is the osos address. On the Mac (HOST), BASE is the
 * address of a copy of osos (host_main.c). */

#ifdef HOST
extern unsigned char *host_base;
#define BASE host_base
#else
#define BASE 0
#endif

#define MAGIC2   0x32444649u                    /* "IFD2" */
#define MAGIC1   0x4d444649u                    /* "IFDM": the table of dark-mode 1.2 */
#define LIMIT    0x800000u                      /* the end of the OS image */
#define RAW      0
#define MAP      1
#define PAL      2

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

void apply_table2(const unsigned *t)
{
    const unsigned char *p, *end;
    unsigned n, i;
    if (t[0] != MAGIC2)
        return;
    n = t[1];
    p = (const unsigned char *)(t + 3);
    end = (const unsigned char *)t + t[2];
    for (i = 0; i < n && p + 8 <= end; i++) {
        const unsigned *h = (const unsigned *)p;
        unsigned at = h[0], kind = h[1] >> 28, len = h[1] & 0x0fffffffu;
        int ok = at < LIMIT && len <= LIMIT - at;
        unsigned char *dst = (unsigned char *)BASE + at;
        p += 8;
        if (kind == RAW) {
            unsigned k;
            if (ok)
                for (k = 0; k < len; k++)
                    dst[k] = p[k];
            p += (len + 3) & ~3u;
        } else if (kind == MAP) {
            unsigned count = *(const unsigned *)p;
            if (ok && !((at | len) & 1))
                apply_map((unsigned short *)dst, len >> 1, (const unsigned short *)(p + 4), count);
            p += 4 + 4 * count;
        } else if (kind == PAL) {
            unsigned count = ((const unsigned short *)p)[0], bits = ((const unsigned short *)p)[1];
            const unsigned char *index = p + 4 + ((2 * count + 3) & ~3u);
            unsigned bytes = ((len >> 1) * bits + 7) >> 3;
            if (ok && !((at | len) & 1) && (bits == 1 || bits == 2 || bits == 4 || bits == 8))
                apply_pal((unsigned short *)dst, len >> 1, (const unsigned short *)(p + 4), count, index, bits);
            p = index + ((bytes + 3) & ~3u);
        } else {
            return;                             /* an unknown kind: stop */
        }
    }
}

/* The decoder of dark-mode 1.2 (a copy of apply_table in patches/dark-mode/dark_mode.c), for the
 * size compare. */
void apply_table1(const unsigned *t)
{
    unsigned n, i;
    const unsigned char *data;
    if (t[0] != MAGIC1)
        return;
    n = t[1];
    data = (const unsigned char *)t + t[2];
    for (i = 0; i < n; i++) {
        unsigned char *p = (unsigned char *)BASE + t[3 + 2 * i];
        unsigned len = t[4 + 2 * i], k;
        for (k = 0; k < len; k++)
            p[k] ^= data[k];
        data += len;
    }
}
