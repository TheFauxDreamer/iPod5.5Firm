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
