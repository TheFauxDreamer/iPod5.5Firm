/* custom-eq: adds the preset "Custom" to Settings > EQ (RetailOS 1.3, iPod Video).
 *
 * The research is in re/custom-eq.md. A preset is a list of up to 5 filter numbers. Each number
 * selects a record in a table of 55 records. This patch adds the numbers 55 to 59. The app
 * calculates the records and writes custom_eq_records and custom_eq_mask at the build.
 *
 * The "bytes" of patch.json change the count function 0xf90fc to 60.
 *
 * Hook 1: the call of 0xa6bd0 at 0xa6d68 in 0xa6d34. The hook adds the node after the Apple presets.
 * Hook 2: the entry of 0xdbd84. The hook gives the record of a filter number. */

#define FIRST_FILTER  55
#define BANDS         5
#define APPLE_COUNT   55
#define APPLE_TABLE   ((const int *)0x1082375c)
#define TABLE_POINTER (*(const int *const *)0x10823758)

typedef struct {
    unsigned short pad;
    unsigned short name_length;
    unsigned short name[0xff];
    short preamp;
    short values[10];
} preset;

_Static_assert(sizeof(preset) == 0x218, "the buffer of 0xd83d0 has 0x218 bytes");

void presets_add(int library, int add);                                            /* 0xa6bd0 */
void *preset_find(int library, const unsigned short *name);                        /* 0xe07f4 */
void *preset_insert(int library, preset *p);                                       /* 0xd83d0 */
void fw_memset0(void *to, int size);                                               /* 0xa7ed0 */

/* 5 records: b0 b1 b2 a1 a2 for 44100 Hz, then for 48000 Hz (Q24). The first value is not zero,
 * so that the variable is in the file and not after it. */
int custom_eq_records[BANDS * 10] = { 1 << 24 };
/* Bit n: band n is on. */
unsigned custom_eq_mask = 1;

static const unsigned short custom_name[] = { 6, 'C', 'u', 's', 't', 'o', 'm' };

/* The first half-word in the array is the count of the name. */
void hook_presets(int library, int add)
{
    preset p;
    presets_add(library, add);
    if (preset_find(library, custom_name))
        return;
    fw_memset0(&p, sizeof p);
    p.name_length = custom_name[0];
    for (int i = 0; i < 6; i++)
        p.name[i] = custom_name[i + 1];
    for (int i = 0; i < BANDS; i++)
        if (custom_eq_mask >> i & 1)
            p.values[i] = (short)((FIRST_FILTER + i) * 100);
    preset_insert(library, &p);
}

const int *hook_filter(int n)
{
    if (n >= FIRST_FILTER && n < FIRST_FILTER + BANDS)
        return custom_eq_records + (n - FIRST_FILTER) * 10;
    return n < APPLE_COUNT ? TABLE_POINTER + n * 10 : APPLE_TABLE;
}
