/* custom-eq: adds the EQs of the user to Settings > EQ (RetailOS 1.3, iPod Video).
 *
 * The research is in re/custom-eq.md. A preset is a list of up to 5 filter numbers. Each number
 * selects a record in a table of 55 records. This patch adds the numbers 55 to 79: 5 bands
 * for each of 5 EQs. 0x1446e8 accepts numbers to 96. The app calculates custom_eq_records and custom_eq_list at the build.
 *
 * The "bytes" of patch.json change the count function 0xf90fc to 80.
 *
 * Hook 1: the call of 0xa6bd0 at 0xa6d68 in 0xa6d34. The hook adds the nodes after the Apple presets.
 * Hook 2: the entry of 0xdbd84. The hook gives the record of a filter number. */

#define FIRST_FILTER  55
#define EQS           5
#define BANDS         5
#define FILTERS       (EQS * BANDS)
#define NAME_LENGTH   31
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

/* The name is a u16 count, then UTF-16, the format that 0xe07f4 reads. A count of 0: no EQ. */
typedef struct {
    unsigned short name_length;
    unsigned short name[NAME_LENGTH];
    unsigned char filters[BANDS];
    unsigned char pad;
} custom_eq;

_Static_assert(sizeof(custom_eq) == 70, "CustomEQ.library writes entries of 70 bytes");

void presets_add(int library, int add);                                            /* 0xa6bd0 */
void *preset_find(int library, const unsigned short *name);                        /* 0xe07f4 */
void *preset_insert(int library, preset *p);                                       /* 0xd83d0 */
void fw_memset0(void *to, int size);                                               /* 0xa7ed0 */

/* Records: b0 b1 b2 a1 a2 for 44100 Hz, then for 48000 Hz (Q24). The first values are not zero,
 * so that the variables are in the file and not after it. */
int custom_eq_records[FILTERS * 10] = { 1 << 24 };
custom_eq custom_eq_list[EQS] = { { 6, { 'C', 'u', 's', 't', 'o', 'm' }, { 0 }, 0 } };

void hook_presets(int library, int add)
{
    preset p;
    presets_add(library, add);
    for (int e = 0; e < EQS; e++) {
        const custom_eq *eq = &custom_eq_list[e];
        if (eq->name_length == 0 || preset_find(library, &eq->name_length))
            continue;
        fw_memset0(&p, sizeof p);
        p.name_length = eq->name_length;
        for (int i = 0; i < eq->name_length; i++)
            p.name[i] = eq->name[i];
        for (int i = 0; i < BANDS; i++)
            p.values[i] = (short)(eq->filters[i] * 100);
        preset_insert(library, &p);
    }
}

const int *hook_filter(int n)
{
    if (n >= FIRST_FILTER && n < FIRST_FILTER + FILTERS)
        return custom_eq_records + (n - FIRST_FILTER) * 10;
    return n < APPLE_COUNT ? TABLE_POINTER + n * 10 : APPLE_TABLE;
}
