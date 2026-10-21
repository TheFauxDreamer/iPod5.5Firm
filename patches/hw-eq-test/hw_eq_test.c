/* hw-eq-test: a test of the hardware EQ of the WM8758 codec (RetailOS 1.3, iPod Video).
 *
 * The firmware applies its EQ presets in software and never writes the EQ registers of the codec
 * (R18-R22). Thus the hardware EQ stays flat. This test patch writes a fixed setting into these
 * registers, so that the owner can hear if the hardware EQ operates. The research is in
 * re/custom-eq.md, section "The hardware EQ of the codec".
 *
 * Version 0.1 wrote the registers only after 0x265e54. On the real iPod the sound did not change.
 * Version 0.2 tests the two possible causes:
 *  - the option eq_path gives bit 8 of R18 (EQ3DMODE): 1 = DAC path, 0 = ADC path;
 *  - the patch also writes the registers after each codec write of the firmware (for example at
 *    each change of the volume), in case the firmware sets up the codec again at playback.
 *
 * Hooks:
 *  - the first instruction of 0x265e54, the function that sets the state of the codec. The patch
 *    writes the registers after it, if the codec type (0x2653a4) is 3 (WM8758);
 *  - the first instruction of the codec write 0x2840d8. After each write of the firmware, the patch
 *    writes the EQ registers again (not for its own writes).
 *
 * Version 0.3 (diagnostic): on the real iPod, versions 0.1 and 0.2 gave no change. The patch also
 * writes a log at a string lookup (a change of screen, in the UI task, not in the codec code):
 * iPod_Control\iTunes\iPodFirmEQLog, one text line with the hardware ID (0x265164), the codec
 * type (0x2653a4), the calls of the two hooks and the count of EQ writes.
 *
 * The codec write takes 2 bytes: (register << 1) | bit 8 of the value, then bits 0-7 of the value.
 *
 * WM8758 EQ registers (datasheet):
 *  - R18 (EQ1, low shelf): bit 8 EQ3DMODE, bits 6-5 the cut-off frequency (0 = 80 Hz, 1 = 105 Hz,
 *    2 = 135 Hz, 3 = 175 Hz), bits 4-0 the gain.
 *  - R19-R21 (EQ2-EQ4, peaks): bit 8 the bandwidth, bits 6-5 the centre frequency, bits 4-0 the gain.
 *  - R22 (EQ5, high shelf): bits 6-5 the cut-off frequency (0 = 5.3 kHz … 3 = 11.7 kHz), bits 4-0 the gain.
 * Gain: 0 = +12 dB, 12 = 0 dB, 24 = -12 dB (1 dB steps). */

int codec_type(void);                                                     /* 0x2653a4 */
unsigned hardware_id(void);                                               /* 0x265164 */
void fw_memset0(void *p, unsigned size);                                  /* 0x7ccd0 */
void fw_strcpy(char *dst, const char *src);                               /* 0x7cd6c */
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode); /* 0x8f3f8 */
int file_write(void *fh, unsigned *len, const void *buf);                 /* 0x8f6f4 */
int file_close(void *fh);                                                 /* 0x8f184 */
void file_create(void *path_record, unsigned type, const char *folder, const char *name); /* 0xe468c */
void *lookup_next(void *provider, unsigned type, int id);
void lookup_continue(void);                                               /* 0x21f258 */
void state_continue(void);                                                /* 0x265e58 */
void write_continue(void);                                                /* 0x2840dc */

/* The options in the app. eq_test: 0 flat, 1 bass +12 dB, 2 treble +12 dB, 3 bass -12 dB.
 * eq_path: bit 8 of R18 (1 = DAC, 0 = ADC). */
unsigned eq_test = 3;
unsigned eq_path = 1;

#define GAIN(db) ((unsigned)(12 - (db)))                                  /* +12 dB -> 0, -12 dB -> 24 */

static int busy;                                                          /* 1 while the patch writes */
static unsigned state_calls, write_calls, eq_writes, logged = 0xffffffff;

/* The replaced first instruction of 0x2840d8, then the rest of the function. */
__attribute__((naked)) int write_original(const unsigned char *bytes)
{
    __asm__ volatile("push {r4, lr}\n\tb write_continue\n");
}

static void write_reg(unsigned reg, unsigned value)
{
    unsigned char b[2];
    b[0] = (unsigned char)((reg << 1) | ((value >> 8) & 1));
    b[1] = (unsigned char)value;
    write_original(b);
}

static void write_eq(void)
{
    int bass = eq_test == 1 ? 12 : eq_test == 3 ? -12 : 0;
    int treble = eq_test == 2 ? 12 : 0;
    busy = 1;
    eq_writes++;
    write_reg(18, (eq_path ? 0x100 : 0) | (1 << 5) | GAIN(bass));    /* EQ1: 105 Hz low shelf */
    write_reg(19, GAIN(0));
    write_reg(20, GAIN(0));
    write_reg(21, GAIN(0));
    write_reg(22, (1 << 5) | GAIN(treble));                          /* EQ5: 6.9 kHz high shelf */
    busy = 0;
}

/* Each codec write of the firmware: the write, then the EQ registers again. The register of the
 * write is bits 1-7 of the first byte; a write of R18-R22 by the firmware is also followed by the
 * EQ of the patch. */
int hook_write(const unsigned char *bytes)
{
    int result = write_original(bytes);
    if (!busy)
        write_calls++;
    if (!busy && codec_type() == 3)
        write_eq();
    return result;
}

/* The replaced first instruction of 0x265e54, then the rest of the function. */
__attribute__((naked)) int state_original(unsigned mode)
{
    __asm__ volatile("push {r4, r5, r6, lr}\n\tb state_continue\n");
}

int hook_state(unsigned mode)
{
    int result = state_original(mode);
    state_calls++;
    if (codec_type() == 3)
        write_eq();
    return result;
}

/* ---- The log (version 0.3) ------------------------------------------------------------------- */

#define TAG_STR   0x53747220u                                             /* 'Str ' */
#define MODE_DATA 0x64617461u                                             /* 'data' */
#define TYPE_ITUN 0x6974756eu                                             /* 'itun' */

static const char folder[] = "iPod_Control\\iTunes\\";
static const char name[] = "iPodFirmEQLog";

static char *put_hex(char *p, unsigned v)
{
    int i;
    for (i = 28; i >= 0; i -= 4)
        *p++ = "0123456789abcdef"[(v >> i) & 15];
    return p;
}

static char *put_text(char *p, const char *t)
{
    while (*t)
        *p++ = *t++;
    return p;
}

static void write_log(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len;
    char line[128], *p = line;
    p = put_text(p, "hwid=");   p = put_hex(p, hardware_id());
    p = put_text(p, " type=");  p = put_hex(p, (unsigned)codec_type());
    p = put_text(p, " state="); p = put_hex(p, state_calls);
    p = put_text(p, " write="); p = put_hex(p, write_calls);
    p = put_text(p, " eq=");    p = put_hex(p, eq_writes);
    p = put_text(p, " test=");  p = put_hex(p, eq_test);
    p = put_text(p, " path=");  p = put_hex(p, eq_path);
    *p++ = '\n';
    len = (unsigned)(p - line);
    file_create(path, TYPE_ITUN, folder, name);
    fw_memset0(path, sizeof path);
    fw_strcpy((char *)path + 4, folder);
    fw_strcpy((char *)path + 4 + sizeof folder - 1, name);
    fw_memset0(fh, sizeof fh);
    if (file_open_rw(path, fh, 0x1000, MODE_DATA) == 0) {
        file_write(fh, &len, line);
        file_close(fh);
    }
}

/* The first instruction of the general lookup (0x21f254) is replaced by a branch. If no other patch
 * hooks the lookup, lookup_next is this function: it runs that instruction and continues in the firmware. */
__attribute__((naked)) void *lookup_original(void *provider, unsigned type, int id)
{
    __asm__ volatile("push {r3, r4, r5, r6, r7, lr}\n\tb lookup_continue\n");
}

/* At a string lookup (each screen shows its labels), write the log if a counter changed. */
void *hook_lookup(void *provider, unsigned type, int id)
{
    if (type == TAG_STR && !busy) {
        unsigned now = state_calls * 7 + write_calls * 3 + eq_writes;
        if (now != logged) {
            logged = now;
            write_log();
        }
    }
    return lookup_next(provider, type, id);
}
