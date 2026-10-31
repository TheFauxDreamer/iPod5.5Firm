# Custom EQ: how firmware 1.3 applies the EQ

This note records how the iPod Video 5.5G with RetailOS 1.3 applies an EQ preset. It is the research for the patch `custom-eq`. Refer to [docs/modifications.md](../docs/modifications.md).

All addresses are osos offsets of firmware 1.3, unless the text says RAM or IRAM. The research used Ghidra 12.1.4, the whole decompilation and the instrumented emulator.

## Result

- The EQ is a software EQ. It is a chain of up to 5 biquad filters. It is not the 5-band hardware EQ of the WM8758 codec.
- A preset is a list of up to 5 filter numbers. Each number selects one record in a fixed table. The value 0 means "no filter".
- The table has 55 records (0 to 54). Each record has one biquad for 44100 Hz and one biquad for 48000 Hz.
- The EQ operates in the decoder step, on 16-bit audio at 44100 Hz or 48000 Hz only.

A patch can thus add a preset with its own filters.

CAUTION: Round 4 of this research (22 October 2026) gave "3 tables of coefficients" at 0x14e3b0, 0x14e65c and 0x14e948. That result was wrong. The values are UTF-8 byte pairs (`c3 83`) and ASCII characters (`{`, `}`, `\`). These tables are a character conversion and have no relation to the EQ. This version of the note removes the result.

## The path from the preset to the sample

| Step | Address | Work | Evidence |
|---|---|---|---|
| 1 | 0xa6d34 | At each load of the library: clears the list head (library + 0xbec), calls 0xa6bd0 at 0xa6d68, then adds a preset with an empty name. | Static, Emulator |
| 2 | 0xa6bd0 | Makes the 22 Apple presets. The names are string IDs at 0x2a9cc0. The values are 10 floats for each preset at 0x2a9d18, multiplied by 100, as i16. | Static |
| 3 | 0xd83d0 | (library, buffer): adds a node of 0x234 bytes, sorted by name. The buffer has 0x218 bytes. | Static |
| 4 | 0x9df8c, 0x9cd84, 0x9b930 | The menu model: the count of nodes with a name, the name at an index, and the index of the selection. There is no fixed count of 22. | Static |
| 5 | 0xb274c, 0xace48, 0x10191c | Select a preset. Keep the values at player + 0x214. Divide each value by 100. | Static, Emulator |
| 6 | 0xf4dc0, 0x1446e8 | Converts the values to bytes, keeps 5 and limits each to 0 to 0x60. Sends command 0x1f to message queue 2. | Static, Emulator |
| 7 | 0x20fcf8, 0x2354cc | The task of queue 2 puts the command into the ring queue at state + 0x12b0. | Static |
| 8 | 0x249ab8, 0x24addc | Writes the command to state + 0x12f8 and the data to state + 0x12fc. 0x24addc has a switch on the command. Case 0x1f calls 0x23f274. Case 0x1a calls 0x23fe24. | Static |
| 9 | 0x23f274 | Copies the 5 numbers to object + 0x650. The object is state + 0x2e5c. | Static |
| 10 | 0x23fe24 | Sets or clears bit 1 of object + 0xcc (the EQ on or off). | Static |
| 11 | 0x23fe3c | Loads the IRAM block. Refer to [The IRAM block](#the-iram-block). | Static |
| 12 | 0x24ab48 → 0x2403c4 | The decoder step. If the rate is 32000 Hz or more, it calls the EQ for each block of 0x100 frames. | Static |
| 13 | 0x71706c (IRAM 0x40000ed0) | The EQ. Refer to [The EQ function](#the-eq-function). | Static |

The buffer of 0xd83d0:

| Offset | Size | Content |
|---|---|---|
| +2 | 2 + 0x1fe | The name: a u16 count, then UTF-16 text. |
| +0x202 | 2 | The preamp. Apple presets have 0. The EQ does not use it. |
| +0x204 | 20 | 10 i16 values: the filter number × 100. Only the first 5 reach the EQ. |

## The filter table

The table is in the data of osos. The start code copies it to RAM.

| Item | osos | RAM | Evidence |
|---|---|---|---|
| The count (0x37 = 55) | 0x6a19f8 | 0x10823754 | Static, Emulator |
| The table pointer | 0x6a19fc | 0x10823758 | Static, Emulator |
| The table of codec type 3 | 0x6a1a00 | 0x1082375c | Static, Emulator |
| The table of codec type 2 | 0x6a2298 | 0x1082375c + 0x898 | Static |

0xcfe9c sets the pointer. 0x265460 selects the table: codec type 2 uses the second table. The second table has records with the first word 0x7fffffff or 0x7ffffffe. These records give a bass value or a treble value for the codec, for example 0x84. The emulator has the hardware ID of type 3, and the pointer is 0x1082375c. Record 1 has b0 = 0x0100fad0 in RAM and in osos.

0xf90fc returns the count. 0xdbd84 (number) returns the address of a record.

### The record

A record has 40 bytes: 5 int32 values for 44100 Hz, then 5 int32 values for 48000 Hz. The order is b0, b1, b2, a1, a2. The format is Q24 (0x01000000 = 1.0). The transfer function is:

```text
H(z) = (b0 + b1 z⁻¹ + b2 z⁻²) / (1 + a1 z⁻¹ + a2 z⁻²)
```

A calculation with these records gives these gains for the Apple presets at 44100 Hz:

| Preset | Filters | 32 Hz | 125 Hz | 500 Hz | 2 kHz | 8 kHz | 16 kHz |
|---|---|---|---|---|---|---|---|
| Acoustic | 1, 2, 3 | +4.8 | +3.5 | +2.3 | +2.7 | +3.6 | +1.0 |
| Bass Booster | 4 | +5.8 | +4.0 | +0.7 | +0.1 | 0.0 | 0.0 |
| Bass Reducer | 5 | −7.4 | −6.2 | −1.9 | −0.2 | 0.0 | 0.0 |
| Flat | (none) | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 | 0.0 |
| Pop | 37, 38, 39 | −2.7 | +0.1 | +4.6 | +2.3 | −1.3 | −2.9 |
| Treble Booster | 50 | 0.0 | 0.0 | +0.2 | +2.2 | +5.7 | +6.0 |
| Treble Reducer | 51 | 0.0 | 0.0 | −0.2 | −3.3 | −6.8 | −7.0 |

The 22 presets use a maximum of 3 filters. Filter 18 has no preset.

## The IRAM block

0x23fe3c writes the block at IRAM 0x40000fe4 (literal at 0x23ffbc).

| Offset | Size | Content |
|---|---|---|
| +0x00 | 1 | The lock. 0x23fe3c waits while it is not 0. The EQ function sets it while it operates. |
| +0x01 | 1 | The EQ is ready. |
| +0x02 | 5 | One flag for each stage. |
| +0x08 | 5 × 20 | The coefficients for 44100 Hz. |
| +0x6c | 5 × 20 | The coefficients for 48000 Hz. |
| +0xd0 | 5 × 32 | The state of each stage: 4 words for the left channel, 4 words for the right channel. |

For each stage, 0x23fe3c reads the number. It skips the stage if the number is 0, or if the number is not less than the count. It negates a1 and a2 in the block, and clears the state of the stage.

## The EQ function

The IRAM function 0x71706c (registers r0 object, r1 flags, r2 buffer, r3 frames, then the sample size on the stack) returns with no change if one of these conditions is true:

- Bit 1 of the flags is 0.
- There are more than 0x100 frames.
- The sample size is not 16.
- The rate at object + 0x84 is not 44100 or 48000.
- The byte +0x01 of the block is 0.

Else it does these steps:

1. 0x7164c8 copies the samples to the work buffer IRAM 0x40001154. Each sample is `sample << 9`.
2. 0x7163b0 applies one stage to the left channel, then to the right channel. It operates on each stage with a flag.
3. 0x7164e8 writes the samples back. Each sample is `value >> 9`, limited to the int16 range.

The filter of 0x7163b0 is Direct Form I, with `smull` and `smlal`:

```text
y = (b0·x + b1·x1 + b2·x2 + A1·y1 + A2·y2) >> 24      (A1 = −a1, A2 = −a2)
```

Thus:

- The work buffer has 7 bits of headroom. A stage does not overflow at normal gains.
- Apple has no precut. A boost clips at the int16 limit in 0x7164e8.
- The `>> 24` rounds down, inside the feedback path. Thus a low filter keeps a small negative DC value, approximately 0.5 / (1 + a1 + a2) in the units of the work buffer. A simulation of the loop gave −2 PCM counts for Bass Booster (calculated), −37 for a low shelf at 60 Hz +6 dB, and −481 for a low shelf at 20 Hz +12 dB (approximately −37 dBFS). The value does not oscillate. The patch cannot change it without a change to the IRAM code.
- The EQ has no effect on 8-bit audio, or on a rate other than 44100 Hz or 48000 Hz.
- The EQ changes the decoded buffer before 0xfed68 and 0x1a2d60. Thus USB-C audio from `usb-audio-out` probably has the EQ. This is not tested.

## The Apple presets as bands

The script [fit-apple-presets.py](fit-apple-presets.py) reads the filter records from your own osos image. It finds the band of the Custom EQ editor (low shelf, peak or high shelf) that is nearest to each filter at 44100 Hz. The app table `CustomEQ.applePresets` is the output. It has measured numbers only, and no Apple record.

The error is the largest difference from the Apple curve from 20 Hz to 20 kHz, with all the filters of the preset.

| Preset | Filters | Bands | Error |
|---|---|---|---|
| Acoustic | 1, 2, 3 | 3 | 0.18 dB |
| Bass Booster | 4 | 1 | 0.06 dB |
| Bass Reducer | 5 | 1 | 0.48 dB |
| Classical | 6, 7, 8 | 3 | 0.49 dB |
| Dance | 9, 10, 11 | 3 | 0.29 dB |
| Deep | 12, 13, 14 | 3 | 0.39 dB |
| Electronic | 15, 16, 17 | 3 | 0.09 dB |
| Flat | (none) | 0 | 0.00 dB |
| Hip Hop | 19, 20, 21 | 3 | 0.41 dB |
| Jazz | 22, 23, 24 | 3 | 0.03 dB |
| Latin | 25, 26, 27 | 3 | 0.38 dB |
| Loudness | 28, 29, 30 | 3 | 0.14 dB |
| Lounge | 31, 32, 33 | 3 | 0.11 dB |
| Piano | 34, 35, 36 | 3 | 0.05 dB |
| Pop | 37, 38, 39 | 3 | 0.18 dB |
| R & B | 40, 41, 42 | 3 | 0.40 dB |
| Rock | 43, 44, 45 | 3 | 0.39 dB |
| Small Speakers | 46, 47 | 2 | 0.05 dB |
| Spoken Word | 48, 49 | 2 | 0.78 dB |
| Treble Booster | 50 | 1 | 0.05 dB |
| Treble Reducer | 51 | 1 | 0.07 dB |
| Vocal Booster | 52, 53, 54 | 3 | 0.11 dB |

Apple possibly designed the filters with other formulas. Thus some errors stay.

## The hardware EQ of the codec

The WM8758 has a 5-band EQ (R18 to R22). The firmware does not use it. The test patch `hw-eq-test` is on the branch `hw-eq`. It wrote these registers and gave no audible change on the real iPod. The owner shelved the test on 22 October 2026. The patch `custom-eq` does not need the hardware EQ.

| Address | Function | Evidence |
|---|---|---|
| 0x265e54 | (mode): sets the state of the codec. Calls 0x28386c (type 1), 0x283c30 (type 2) or 0x2839b8 (type 3, the WM8758). | Static, Emulator |
| 0x2653a4 | The codec type from the hardware ID (0x265164, bits 16–31): 0xb gives 3; 5, 6, 8, 9 give 2; 0xc gives 2 or 1. | Static |
| 0x2840d8 | (bytes): writes one codec register through I²C address 0x1a. | Static, Emulator |
| 0x282f58 | (7-bit address, count, bytes): the low I²C write. | Static, Emulator |

## Consequences for a patch

- The patch adds a preset with the filter numbers 55 to 59. It gives 5 free biquads.
- The menu needs no change.
- If the patch is removed, the saved name "Custom" has no preset. 0x9421c then clears the name.
- The app calculates the coefficients. The iPod needs no floating-point code.
- The emulator has no audio. Each test of the sound must be on the real iPod.

## Open questions

- Is the CPU sufficient for 5 stages? Apple presets use a maximum of 3.
- Does USB-C audio have the EQ? Only a test on the real iPod can answer.
