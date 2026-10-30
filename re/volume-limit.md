# EU volume limit

This note records the research for the patch `volume-unlimit`. All addresses are osos offsets for RetailOS 1.3. The Ghidra project is `osos13` (base address 0x0). The research date is 8 October 2026.

## The limit

iPods for the EU have a volume limit because of a French law. The limit is in the firmware. The user setting Settings > Volume Limit is a different function. The patch does not change it.

## The old method of goPod and iPodWizard

goPod removed the limit on the first iPod models. iPodWizard copied the goPod code (`firmware.cpp`, functions `isCapped`, `unCap` and `reCap`; the comment says "Taken from goPod source code"). Source: the iPodWizard mirror at `github.com/DavidBuchanan314/iPodWizard-mirror`.

The method:

1. Find the 8 bytes `08 00 9F E5 38 01 90 E5` (3G, 4G, Color, mini) or `08 00 9F E5 94 00 90 E5` (nano, 5G).
2. Read the 2 bytes after the pattern. If they are not `01 00` or `00 01`, continue the search.
3. `01 00` means "capped". `00 01` means "uncapped".
4. To remove the limit, write `00 01`.

The 8 bytes are `ldr r0, [pc, #8]` and `ldr r0, [r0, #0x94]`. The next instruction is `and r0, r0, #1` (`01 00 00 e2`). The change makes it `and r0, r0, #0` (`00 01 00 e2`). The immediate 0x100 is the value 0 with a rotation, so the result is always 0.

## The two matches in firmware 1.3

| At | Instruction after the pattern | Function | Result |
|---|---|---|---|
| 0x9f0f8 | `and r0, r0, #6` (`06 00 00 e2`) | Returns bits 1–2 of the flags | Not the limit. iPodWizard skips it. |
| 0xa0348 | `and r0, r0, #1` (`01 00 00 e2`) | Returns bit 0 of the flags | The limit. |

An earlier note in [ghidra.md](ghidra.md) examined only the first match. It said that the old patch does not apply to 1.3. That was wrong. The iPodWizard search continues to the second match, and that match is correct.

Both functions read the word +0x94 of the object at 0x108710dc. This research calls it the device information object. The same object has the region code at +0x92 (`0x9e958` returns `+0x92 & 0xff3f`). The research did not find the code that fills the object.

## The users of the limit bit

`0xa0348` has two callers.

**The settings load, `0xaf698`.** At 0xaf6b8 it calls `0xa0348`. At 0xaf6cc it writes the maximum volume to its object at +0xb78:

| Bit 0 | Maximum at +0xb78 |
|---|---|
| 0 | 0x100 (256) |
| 1 | 0xd8 (216) |

**The accessory protocol, `0x1a3254`, case 0x24.** This is the iAP command 0x24. The reply is the command 0x25. If bit 0 is set, the reply has the bit 0x1000000. Thus an accessory can know that the iPod has a limit.

## The volume calculation

`0x88ff8` reads +0xb78. It calculates `level × maximum / 100`, where `level` is the position of the volume control in percent. The division by 100 is inline code. With the limit, the full position gives 216 of 256. This is 84% of the full volume.

## The low end of the volume

The research date is 30 October 2026. The owner reported that the 3.5 mm output is loud at the lowest volume. The step from the lowest volume to silence is large. The result: no patch on main causes this. The cause is the linear volume calculation of the firmware.

The path of the volume in Ghidra:

1. `0x1e9e88` (set the level), `0x1e8d10` (volume up) or `0x1e9c84` (volume down) keeps the level (0–100) at app + 0x758.
2. `0x88ff8` calculates the output volume (0–256).
3. `0xb4078` calls `0x116d84` with the output volume, the balance 0x32 and the flag 1.
4. `0x116d84` limits the output volume to the result of `0x9d99c`. It keeps the output volume at +0x276c and the balance at +0x2774.
5. `0xd1eb0` calculates 2 gains from the output volume and the balance. It returns one gain in the low 16 bits and one gain in the high 16 bits. The balance 0x32 gives 2 equal gains.
6. `0xec4ac` or the second path of `0x116d84` sends the high gain >> 1 to `0x14499c`. `0xec4ac` limits this value to 0x7f.

The low end of the output volume:

| Level | Output volume, maximum 0x100 | Output volume, maximum 0xd8 | Relative to 256 |
|---|---|---|---|
| 0 | 0 | 0 | Silence |
| 1 | 2 | 2 | −42 dB |
| 2 | 5 | 4 | −34 dB, −36 dB |
| 3 | 7 | 6 | −31 dB, −33 dB |

Thus the patch `volume-unlimit` does not change the lowest level. It adds at most 1.5 dB at the full position, and only on an iPod for the EU.

Other results:

- `0xd1eb0` uses a floating-point calculation if +0x2a4 and the output volume are not 0. The calculation reads a 16-bit value of the track (+0x78 of the object at +0x20) if the byte at +0x29d7 is not 0. This is probably Sound Check. The result has the limit 0x200, thus the gain can be 2 times the output volume. The decompiled code of this calculation is not complete.
- The normal path does not use the property 0x607c. `0x1eee50` sends this property only if the byte at app + 0x434 is not 0.
- All calls of `0x2840d8` (one codec register) are in `0x28386c`, `0x2839b8`, `0x283c30` and `0x2840fc`. None of these functions is a volume function.
- On codec type 3, `0x2839b8` mode 4 writes R52–R55 with volume bits 0. Modes 1 and 2 write the same registers with the mute bit. Mode 3 writes no register.
- `0x282f58` (the low I²C write) has 3 other callers: `0x283540`, `0x283634` and `0xe4184`. The research did not examine them.

Open items:

- The research did not read the audio engine after `0x14499c`. The engine can apply a different curve. Thus −42 dB is the value of the output volume, not a measured value.
- A new curve in `0x88ff8` probably cannot make a step below the lowest value of 7 bits. A patch for a lower volume needs a different method.
- The real effect of R52–R55 is not known. The codec writes of `hw-eq-test` gave no audible change. Refer to [custom-eq.md](custom-eq.md).

## The other match, 0x9f0f8

`0x9f0f8` returns `flags & 6`. Its only caller is `0x9bd88`. `0x9bd88` gives a default value for the setting at +0xb3a, from the region code. If the region code has no case and `0x9f0f8` returns 2, the value is 0. Otherwise the value is 1. The research did not identify the setting. Do not change this function.

## The patch

| At | Expect | Value | Instruction after the change |
|---|---|---|---|
| 0xa0350 | `0100` | `0001` | `and r0, r0, #0` (`e2000100`) |

The result:

- `0xa0348` always returns 0.
- The maximum at +0xb78 is always 0x100.
- The iAP reply always says "no limit".
- On an iPod that is not for the EU, bit 0 is already 0. Thus the patch changes nothing on that iPod.
- iPodWizard shows the patched file as "uncapped".

## Tests

- A script applied the byte change to osos 1.3 and ran the iPodWizard search. Before the change, the result was "capped" at 0xa0348. After the change, the result was "uncapped".
- The emulator cannot show the change: its iPod is probably not for the EU, and it has no audio.
- Not tested on a real iPod. The test needs an iPod for the EU. Compare the loudness at the full position of the volume control before and after the patch.
