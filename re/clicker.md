# The Clicker setting and the click in the headphones

This note records the research for the patch `click-speaker-only`. All addresses are osos offsets for RetailOS 1.3. The Ghidra project is `osos13` (base address 0x0). The results come from `DecompileAt.java`, `DumpCode.java`, `FindConstant.java` and `FindXrefs.java` on 27 October 2026.

## The request

The owner hears each click two times: in the headphones and from the piezo speaker. The owner wants the click only from the piezo.

## The Clicker word

RAM 0x1081d9c4 holds the Clicker setting as a word. Two bits have a meaning:

| Bit | Value | Meaning |
|---|---|---|
| 0 | 1 | The speaker (the piezo). |
| 1 | 2 | The headphones (the audio path). |

The functions that use the word (`FindConstant.java 0x1081d9c4`):

| Function | What it does with the word |
|---|---|
| 0xf3dc0 | The default settings: it writes 3 (the speaker and the headphones). |
| 0xe1b64 | The settings load: it copies the word from the settings object + 0xafc. |
| 0x95f0c | Keeps the word at + 0x10 of another object, then clears bit 1. Thus the firmware itself can stop the click in the headphones for a time. |
| 0x99098 | Puts the kept word back. |
| 0xa69dc | The click (below). |

## The click 0xa69dc

The instructions at 0xa6a84–0xa6aec:

| Address | Instruction | Meaning |
|---|---|---|
| 0xa6a8c | `ldr r0, [r0]` | The Clicker word. |
| 0xa6a90 | `tst r0, #0x2` | Bit 1: the headphones. |
| 0xa6a94 | `and r0, r0, #0x1` | Bit 0: the speaker. |
| 0xa6a98 | `beq 0xa6ad8` | Without the headphones bit: go to the speaker test. |
| 0xa6a9c–0xa6abc | | With the headphones bit. Without the speaker bit, the byte + 0x3e of the click object is 0. With the speaker bit, `0x246158(0x24672c(), 0)` decides: not 0 gives the piezo only (0xa6ae0), 0 sets + 0x3e to 1. |
| 0xa6ac0–0xa6ad4 | `b 0x1b9168` | Plays the click on the audio path. |
| 0xa6ad8 | `cmp r0, #0` | No speaker bit: return. |
| 0xa6ae0–0xa6aec | `b 0xcd430` | The piezo tone `tone(0x55, …)`. |

0x1b9168 plays a sound on the audio path. If the byte + 0x3e of its object has bit 0, it also plays the piezo tone at 0x1b91fc. 0x1b9168 has two more callers (0x88aec and 0x26a560). Thus it is a general sound function, and a patch must not change it.

The meaning of 0x246158 is not known.

## The patch

`click-speaker-only` changes one instruction:

| At | Expect | Value | Instruction after the change |
|---|---|---|---|
| 0xa6a90 | `020010e3` | `000010e3` | `tst r0, #0x0` |

`tst r0, #0` always sets the Z flag. Thus the branch at 0xa6a98 always goes to the speaker test:

| Clicker word | Without the patch | With the patch |
|---|---|---|
| 0 | No click | No click |
| 1 | Piezo | Piezo |
| 2 | Headphones | No click |
| 3 (the default) | Headphones and piezo | Piezo |

The patch changes only the click of 0xa69dc. The other sounds of 0x1b9168 do not change. The Clicker setting continues to turn the click on and off.

Not tested in the emulator (it has no audio).

## Test on the real iPod (27 October 2026)

The owner flashed version 1.0 and reported: "works great". The click plays from the piezo speaker, and not in the headphones.
