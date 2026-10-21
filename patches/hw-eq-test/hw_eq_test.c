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
 * The codec write takes 2 bytes: (register << 1) | bit 8 of the value, then bits 0-7 of the value.
 *
 * WM8758 EQ registers (datasheet):
 *  - R18 (EQ1, low shelf): bit 8 EQ3DMODE, bits 6-5 the cut-off frequency (0 = 80 Hz, 1 = 105 Hz,
 *    2 = 135 Hz, 3 = 175 Hz), bits 4-0 the gain.
 *  - R19-R21 (EQ2-EQ4, peaks): bit 8 the bandwidth, bits 6-5 the centre frequency, bits 4-0 the gain.
 *  - R22 (EQ5, high shelf): bits 6-5 the cut-off frequency (0 = 5.3 kHz … 3 = 11.7 kHz), bits 4-0 the gain.
 * Gain: 0 = +12 dB, 12 = 0 dB, 24 = -12 dB (1 dB steps). */

int codec_type(void);                                                     /* 0x2653a4 */
void state_continue(void);                                                /* 0x265e58 */
void write_continue(void);                                                /* 0x2840dc */

/* The options in the app. eq_test: 0 flat, 1 bass +12 dB, 2 treble +12 dB, 3 bass -12 dB.
 * eq_path: bit 8 of R18 (1 = DAC, 0 = ADC). */
unsigned eq_test = 3;
unsigned eq_path = 1;

#define GAIN(db) ((unsigned)(12 - (db)))                                  /* +12 dB -> 0, -12 dB -> 24 */

static int busy;                                                          /* 1 while the patch writes */

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
    if (codec_type() == 3)
        write_eq();
    return result;
}
