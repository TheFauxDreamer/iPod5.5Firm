# Custom EQ: how firmware 1.3 applies the EQ

This note records how the iPod Video 5.5G with RetailOS 1.3 applies an EQ preset. It is research for a possible patch "Custom EQ" (refer to [patch-ideas.md](patch-ideas.md)). No patch exists.

All addresses are osos offsets of firmware 1.3. The research used Ghidra 12.1.4 and the instrumented emulator on 20 October 2026.

## Result

- The EQ is a software EQ. It is not the 5-band hardware EQ of the WM8758 codec.
- A preset is not a list of band gains. It is a list of up to 5 filter numbers. Each number selects one filter in a fixed table. The value 0 means "no filter".
- The 22 Apple presets use 0 to 3 filters each. They use the filter numbers 1 to 54 (Flat uses none). The firmware accepts numbers up to 96.
- The firmware sends the filter numbers to the audio engine in a message (command 0x1f). The research did not find the receiver of the message or the filter table.

## The presets

`FUN_000a6bd0` makes the 22 Apple presets when the music database loads. For each preset it takes:

- the name: the string ID from the table at 0x2a9cc0 (22 words, 24768 "Acoustic" … 24789 "Vocal Booster");
- 10 float values from the table at 0x2a9d18 (0x28 bytes for each preset). It multiplies each value by 100 (0x42c80000 = 100.0) and keeps it as an i16.

The float values are small whole numbers, not gains in dB:

| Preset | Values |
|---|---|
| Acoustic | 1, 2, 3 |
| Bass Booster | 4 |
| Bass Reducer | 5 |
| Classical | 6, 7, 8 |
| Flat | (none) |
| Small Speakers | 46, 47 |
| Spoken Word | 48, 49 |
| Treble Booster | 50 |
| Treble Reducer | 51 |
| Vocal Booster | 52, 53, 54 |

Each number is used only one time. Thus each number selects one filter, and a preset is a chain of filters.

The presets are a list at library + 0xbec, sorted by name (`FUN_000d83d0` adds a node of 0x234 bytes). `FUN_000e07f4` finds a preset by name. A node has the preamp value at + 0x21c and the 10 values at + 0x21e.

## The path to the audio engine

| Address | Function | Evidence |
|---|---|---|
| 0x0a6bd0 | Makes the 22 Apple presets (names and values). | Static |
| 0x0a6d34 | Calls 0xa6bd0, then adds a preset with an empty name. | Static |
| 0x0e07f4 | (library, name): finds a preset in the list at library + 0xbec. | Static |
| 0x09bf6c | (library, name, out): copies the preamp and the 10 values of a preset (11 i16). | Static |
| 0x0e1cf0 | Applies the preset of the current settings. | Static, Emulator |
| 0x0ace48 | (player, values, per track): copies the values to player + 0x214 and calls 0x10191c. | Static, Emulator |
| 0x10191c | (player, 0, values): if the EQ is on (player + 0x235), it divides each value by 100, then calls 0xf4dc0, 0xe6838 and 0x106a9c. If the EQ is off, it calls 0xec450. | Static, Emulator |
| 0x0f4dc0 | Converts the 10 values to 10 bytes and calls 0x1446e8. | Static, Emulator |
| 0x1446e8 | Keeps the first 5 bytes and limits each to 0 … 0x60 (96). It writes command 0x1f at object + 0x24 and the 5 bytes at + 0x34. Then it sends the message. | Static, Emulator |
| 0x14493c | (object, 2, on): command 0x1a, the EQ on or off. 0xe6838 sends "on", 0xec450 sends "off". | Static, Emulator |
| 0x215ec0 | Sends a message object to message queue 2 (`FUN_000a6770` → system call 0x84644). | Static |

The audio object is the word at 0x1081e07c + 0xc. Other commands of the same object are 0x24 (`FUN_0014499c`) and 0x31 (`FUN_00144824`).

## Emulator test

Test: the stock firmware 1.3, the 60-track test library, a song plays. The emulator recorded `IPODFW_MARK_AT` markers and the I²C writes.

| Action | Markers | I²C writes |
|---|---|---|
| Start | 0xace48, 0xe1cf0, 0x10191c (2 times). No 0x1446e8: the EQ is Off. | 52 writes to the codec (address 0x34). |
| Settings > EQ > Bass Booster | 0xace48, 0xe1cf0, 0x10191c, 0x14493c, 0x10191c, 0xf4dc0, 0x1446e8, 0x14493c | No write to the codec. Only the periodic writes to address 0x10. |

Thus the firmware sends the preset to the audio engine and does not change the codec registers. The EQ is a software EQ.

## The receiver (research round 2, 20 October 2026)

| Address | Function | Evidence |
|---|---|---|
| 0x0a6770 | (queue, message, size, …): system call 4 (0x84644 → 0x27f5f0): put a message into a queue. | Static |
| 0x0a66a4, 0x0a661c | System call 5: get a message from a queue (with and without a wait). | Static |
| 0x163c94 | (queue, &message, …): gets a message and returns the byte at message + 0x18: the command. For the EQ messages, this is object + 0x24. | Static |
| 0x20fcf8 | The task of queue 2. A switch (0x20fdac) on the command. Commands 0x1a and 0x1f: it copies 0x1c bytes of the message (+ 0x2c) and passes them to 0x2354cc with the object at (task + 0x3c) + 0x12b0. Command 0x24 calls 0x24b580 directly. | Static |
| 0x2354cc | Puts an item into a ring queue (0x235548) and signals the reader. | Static |
| 0x2355ac | Takes an item from that ring queue and calls the first method of the item. | Static |
| 0x678074 | The vtable of the item of 0x20fcf8. Slot 0: 0x249ab8. | Static |
| 0x249ab8 | Writes the command to state + 0x12f8 and its 0x1c data bytes to state + 0x12fc. | Static |

The 5 filter numbers of an EQ preset thus go to state + 0x12fc. The code that reads this state, and the filter table, are not found yet. The callers of 0x2355ac (0x216460, 0x249390) are the next step. The emulator cannot help with a profile: with music and the profiler, it runs at approximately 0.07× and does not react (refer to [emulator.md](emulator.md#limits)).

## The reader of the EQ state (research round 3, 21 October 2026)

| Address | Function | Evidence |
|---|---|---|
| 0x249390 | The main loop of the task that reads the ring queue at state + 0x12b0 (0x2355ac). After each item, it reads the command byte state + 0x12f8 and acts only on the values 0, 1 and 3. It does not use the commands 0x1a and 0x1f. It calls code in IRAM (0x4001d724). | Static |
| 0x24b544, 0x249fa4, 0x24b338, 0x249f48, 0x249220, 0x24b3c0, 0x24b440 | The other functions of the loop. None reads state + 0x12f8 or + 0x12fc. | Static |

Only 0x249ab8 and 0x249390 use the offset 0x12f8 as a constant. The reader of the filter numbers probably uses another base pointer.

### The IRAM code

The FIQ vector jumps to 0x40000000 and the SWI vector to 0x40000008 (the word at osos 0xec). A dump of IRAM from the emulator after the start (`peek`, 0x30000 bytes) found these copies of osos:

| IRAM | osos |
|---|---|
| 0x40000000–0x40000f00 | 0x71619c–0x71709c |
| 0x40001800–0x40002500 | 0x719af8–0x71a7f8 |
| 0x40008000–0x4000c600 | 0x71a804–0x71ee04 |
| 0x40010000–0x40013a00 | 0x71ee84–0x722884 |
| 0x40018800–0x40019400 | 0x72292c–0x72352c |
| 0x4001c900–0x4001df00 | 0x7326cc–0x733ccc |

The other IRAM areas were zero or data at that time (probably the code of a decoder is loaded there at playback). The 83 jumps `ldr pc, [pc, #-4]` in osos go to these areas. A search of the six areas found no `cmp` with 0x5f–0x61 and no `add` with 0x1200–0x1300. Thus the EQ code is probably in an area that is loaded at playback.

### The hardware EQ of the codec

The WM8758 codec has a 5-band EQ (registers 0x12–0x16: gain −12 to +12 dB, and a choice of 4 frequencies for each band). The I²C log of the emulator showed that the firmware writes only the registers 0x34–0x37, 0x31 and 0x01–0x03 at the start, and nothing at a change of the EQ preset. Thus the hardware EQ stays flat, and a patch can set it.

| Method | Advantages | Disadvantages |
|---|---|---|
| Hardware EQ of the WM8758 | No CPU load. Free frequency and gain for 5 bands. No need for the filter table. The firmware does not write these registers. | Only the headphone and line output, not USB-C audio. A test on the real iPod is necessary for the register values and for the effect on the sound. |
| The software EQ of Apple | Also for USB-C audio (probably). | Needs the filter table. The research found the 3 tables for the filters 32 to 63. The research did not find the table for the filters 1 to 31. |

## The filter table (research round 4, 22 October 2026)

The research found the filter table. The table is in the region of the code of
the audio engine. The region is 0x14c054 to 0x14e984.

### The 3 stages of the filter

The function 0x14cfcc is the dispatcher of the filter. The function has 3
stages. The stage is at the offset +0x75 of the object. The function has 2
more bytes at the offsets +0x76 and +0x77. The function uses the bytes to know
the state of each stage.

The function 0x14cfb8 says that the number of the filter is in the range 0x20
to 0x7f. The function is `return param_1 - 0x20U < 0x60;`. The function
0x14cfbc says that the number is less than 0x60. The function
0x14cfa4 says that the number of the stage is 0x10 or 0x18.

The 5 small functions 0x14d5a4, 0x14d5b8, 0x14dab8, 0x14df80 and 0x14df94
each say that the number of the stage is one of 2 numbers. The pairs are
(0x11, 0x19), (0x12, 0x1a), (0x13, 0x1b), (0x14, 0x1c) and (0x17, 0x1f). The
function 0x14e984 says that the number of the stage is not one of 8 pairs.

### The 3 tables of the coefficients

The 3 stages have each a table of 32 coefficients. The table has 4 bytes for
each coefficient. The value is a number with a fraction. The number has 16 bits
for the whole part and 16 bits for the fraction.

| The stage | The table | The function that reads the table | The range |
|---|---|---|---|
| 1 | 0x14e65c | 0x14e430 | 0x20 to 0x3f |
| 2 | 0x14e3b0 | 0x14e184 | 0x20 to 0x3f |
| 3 | 0x14e948 | 0x14e7a8 | 0x20 to 0x3f |

The function 0x14e430 and the function 0x14e184 have a switch with the cases
0x20 to 0x3f. Each case gives the address of the coefficient. The function
0x14e7a8 has the cases 0x2e, 0x2f and 0x30 to 0x3f. The cases 0x2e and 0x2f
have no coefficient. The function gives 0 and 2 or 6 for the 2 cases.

The function 0x14e7a8 reads the coefficient with the function 0x223148. The
function 0x223148 reads 2 bytes. The function 0x14d438 applies the filter with
the function 0x223884 and the function 0x14c374.

### The values of the table of the stage 2

The table of the stage 2 is at 0x14e3b0.

| The filter | The address | The value |
|---|---|---|
| 0x20 | 0x14e3b0 | 0x000081c3 |
| 0x21 | 0x14e3b4 | 0x000089c3 |
| 0x22 | 0x14e3b8 | 0x000093c3 |
| 0x23 | 0x14e3bc | 0x00009ac3 |
| 0x24 | 0x14e3c0 | 0x00009cc3 |
| 0x25 | 0x14e3c4 | 0x0000bcc3 |
| 0x26 | 0x14e3c8 | 0x009880e2 |
| 0x27 | 0x14e3cc | 0x0000a1c2 |
| 0x28 | 0x14e3d0 | 0x0000002a |
| 0x29 | 0x14e3d4 | 0x00000027 |
| 0x2a | 0x14e3d8 | 0x009480e2 |
| 0x2b | 0x14e3dc | 0x0000a9c2 |
| 0x2c | 0x14e3e0 | 0x00a084e2 |
| 0x2d | 0x14e3e4 | 0x00a280e2 |
| 0x2e | 0x14e3e8 | 0x009c80e2 |
| 0x2f | 0x14e3ec | 0x009d80e2 |

> The research did not find the meaning of the 2 parts of the value. The
> research did not check the values of the tables of the stages 1 and 3. The
> research did not find the frequency and the gain of each filter.

### The number of the filter

The function 0x1446e8 keeps the first 5 bytes of the message and limits each
byte to the range 0 to 0x60. The number 0x60 is 96. The function 0x14cfb8
says that the number of the filter is in the range 0x20 to 0x7f. The 3 tables
have only the numbers 0x20 to 0x3f. The numbers 0x40 to 0x7f have no
coefficient in the 3 tables of the research.

> The research did not find the filter numbers 55 to 96. The tables of the
> research have the numbers 32 to 63. The note of the earlier research has the
> numbers 1 to 54 for the presets of Apple. The presets use the numbers 1 to
> 54. The research did not find the table for the numbers 1 to 31.

### The functions of the audio engine

| The function | The work |
|---|---|
| 0x14cfcc | The dispatcher of the filter. The function has 3 stages. |
| 0x14cfb8 | Says that the number of the filter is in the range 0x20 to 0x7f. |
| 0x14cfbc | Says that the number of the filter is less than 0x60. |
| 0x14cfa4 | Says that the number of the stage is 0x10 or 0x18. |
| 0x14e430 | Reads the coefficient of the stage 1. |
| 0x14e184 | Reads the coefficient of the stage 2. |
| 0x14e7a8 | Reads the coefficient of the stage 3. |
| 0x14d438 | Applies the filter. |
| 0x14d668 | Puts the filter in the state. |
| 0x14d9b8 | Puts the filter in the state. |
| 0x14dbe0 | Puts the filter in the state. |
| 0x14dd30 | Reads the state of the filter. |
| 0x14d5a4 | Says that the number of the stage is 0x14 or 0x1c. |
| 0x14d5b8 | Says that the number of the stage is 0x17 or 0x1f. |
| 0x14df80 | Says that the number of the stage is 0x12 or 0x1a. |
| 0x14df94 | Says that the number of the stage is 0x13 or 0x1b. |
| 0x14dab8 | Says that the number of the stage is 0x11 or 0x19. |
| 0x14e984 | Says that the number of the stage is not a number of the table. The function has 8 pairs of numbers. |
| 0x223148 | Reads 2 bytes. The function reads a coefficient. |
| 0x223884 | Puts a value in a list. |
| 0x14c374 | Puts a filter in the state of the audio engine. |
| 0x26a9e8 | Selects the object of a command of the audio engine. The case 0x1f is the command of the equalizer. |

## The limits of the research

| The limit | The result |
|---|---|
| The filter table | The research found the 3 tables of the coefficients of the filters 0x20 to 0x3f. The research did not find the table for the filters 1 to 31. The research did not find the meaning of the 2 parts of the value. |
| The meaning of the number | The research did not find the frequency and the gain of each filter. The value has 16 bits for the whole part and 16 bits for the fraction. |
| The receiver | The research did not find the function that reads the message with the command 0x1f. The research found the tables and the dispatcher of the filter. The tables are in the region 0x14c054 to 0x14e984. |

## Consequences for a patch

- A custom EQ can be a new preset with up to 5 filter numbers. But only the 54 known filters (and possibly 55–96) exist. This gives no free choice of frequency and gain.
- A true custom EQ (frequency, gain and Q for each band) needs the filter table or the filter code of the audio engine. The research did not find them.
- The emulator has no audio. Thus the emulator cannot test the sound of an EQ. Each test of the sound must be on the real iPod.
- `usb-audio-out`: the EQ is in software, so it probably also changes the USB-C audio. This is not tested.

## Open questions

- Where is the receiver of command 0x1f? The search for a switch with the cases 0x1a, 0x1f, 0x24 and 0x31 found only 0x47ae8 and 0x4af18. These are in the obfuscated code at low addresses, and they are probably not the receiver.
- Where is the filter table? A search for biquad coefficients (int32 and float records) found nothing.
- What do the filter numbers 55–96 do? A test patch can make a preset with these numbers. Only a test on the real iPod can answer.
- Is the EQ applied before the split between the codec and USB (0x1a2d60)?
