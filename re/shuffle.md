# Shuffle in RetailOS 1.3

This note records how the iPod Video 5.5G with RetailOS 1.3 makes a shuffled play order. It gives the functions, the random number generator, the seed, the algorithm for Songs and for Albums, the emulator tests and the known bugs. The aim is an exact copy of the algorithm in other programs. [docs/ipod-shuffle.md](../docs/ipod-shuffle.md) is a document to share, with code in C and Swift. MiMusic has such a copy (`Packages/MiMusicKit/Sources/PlayerKit/IPodShuffle.swift`).

All addresses are osos offsets of firmware 1.3. The research used Ghidra 12.1.4 and the instrumented emulator on 15–16 October 2026.

## Summary

- The music shuffle is `FUN_00094440`. It uses a Fisher–Yates shuffle. The loop goes from the end of the list to the start.
- The random index comes from `FUN_000e5978`. This is a Park–Miller "minimal standard" generator (16807, modulus 2³¹ − 1). It converts the result to a single-precision float.
- The generator gets its seed one time after each start of the iPod, at the first shuffle. The seed comes from the free-running counter at 0x60006038.
- Songs mode shuffles the tracks in database order. Then the current track goes to the start.
- Albums mode shuffles the albums of the album-sorted list. The tracks of an album stay in their order. The album of the current track goes to the start.
- The C `rand()` of the firmware (0x11ac38) is not used for music. The photo slideshow, the games and the visual effects use it.

## The settings

`FUN_000b3a04(app, mode)` is the setter of Settings → Shuffle. The Settings controller 0x1919d8 calls it.

| `mode` | Menu text | `+0x20` (shuffle on) | `+0x92` (albums) |
|---|---|---|---|
| 0 | Off | 0 | 0 |
| 1 | Songs | 1 | 0 |
| 2 | Albums | 1 | 1 |

The bytes are in the playback settings object at `*(app + 0xca0)`. After a change, the setter calls 0xa983c and refreshes the Now Playing state.

The byte `+0x93` is a second flag: "shuffle the tracks in each album too". The Settings menu does not set it. In the emulator, the settings word at `+0x90` was 0x00010000 in Albums mode, thus `+0x92` = 1 and `+0x93` = 0. Refer to [Bug 3](#bug-3-the-inner-album-shuffle-uses-the-wrong-index).

## The call path

```text
Settings → Shuffle            0x1919d8 → 0xb3a04 (sets +0x20, +0x92)
Shuffle Songs / a list with shuffle on
  └ 0xb40c4  start a shuffled play list
      └ 0x94440(list, current, settings+0x92, settings+0x93)
          ├ 0x1120bc(list, 1 or 6)   get the source track list
          ├ 0x10eb2c                 copy the list
          └ 0xe5978(n)               random index in 0 … n−1
Smart playlist, "limit … selected by random"
  └ 0xbb28c (selection type 2)
      └ 0x94440(list, 0, settings+0x92, settings+0x93)
```

| Address | Function | Evidence |
|---|---|---|
| 0x0b3a04 | Shuffle setter: mode 0 = Off, 1 = Songs, 2 = Albums. | Static |
| 0x0b40c4 | Starts a shuffled play list. It calls 0x94440 with the settings bytes +0x92 and +0x93. Then it writes the new position of each track to the track item `+0x24`. | Static, Emulator |
| 0x094440 | The music shuffle (Songs and Albums). | Static, Emulator |
| 0x0e5978 | Random index in 0 … n − 1 (Park–Miller and float). Lazy seed. | Static, Emulator |
| 0x00055c | Seed source: reads 0x60006038 two times. | Static, Emulator |
| 0x1120bc | Gets a cached track list of a list object. Slot 1 = database order, slot 6 = album order. | Static, Emulator |
| 0x0ddf94 | Sorts a track list for a slot. It makes slot 6 if the database has no album index. | Static |
| 0x0bb28c | Smart playlist evaluation. Selection type 2 ("random") uses 0x94440. | Static |
| 0x0a7f34 | Compares two byte strings. Returns 1 if they are equal. | Static |

Registers at the call 0xb4128: r4 = the list object, r5 = the current track item (0 for Shuffle Songs from the main menu), r2 = settings +0x92, r3 = settings +0x93. At the return 0xb412c, r0 = the new list.

## The random number generator

### The seed

`FUN_0000055c` reads the register 0x60006038 two times:

```text
ldr r1,[r0,#0x38]      ; A = first read
ldr r0,[r0,#0x38]      ; B = second read
eor r0,r1,r0,lsl #16   ; seed = A XOR (B << 16)
```

0x60006038 is not in the Rockbox `pp5020.h`. The emulator research (`emulator-src/research/08-differential-register-map.md`) measured it on a real iPod: a 16-bit counter that changes at each read. Thus the seed is almost random at each start.

`FUN_000e5978` sets the seed only one time. A C++ static guard at 0x1081e044 (functions 0x25ab48 and 0x25ab64) protects it. The state is the word at 0x1081e048. The state stays in RAM until the next start of the iPod. Thus all shuffles after a start use one sequence of random numbers.

### The generator

```text
state = 16807 × (state mod 127773) − 2836 × (state div 127773)
if state < 1: state = state + 0x7fffffff
```

This is the Schrage form of Park–Miller "minimal standard" (Park and Miller, 1988). The constants are at 0xaf520 (127773) and 0xaf524 (16807), and the immediate 0xb14 (2836). The division is signed (0x7d024), and it truncates toward zero.

### The index

```text
u = float32(state) × 2^−31        (0x2a89e8, then 0x2a9310 with −31)
p = float32(n) × u                (0x2a8ac4)
index = int16(truncate(p))        (0x2a8860, then a 16-bit sign extension)
```

All the arithmetic is IEEE single precision with round to nearest, ties to even. `n` is a 16-bit signed argument. The result is also a 16-bit value.

`FUN_000af4b4` is the same generator with the state as an argument. Only `FUN_0012d494` (state at 0x1083e0ac, own guard) uses it. This is the deck shuffle of a card game (seven columns, 0x16ada0). It does not change the music shuffle.

## The algorithm

### Songs mode (`+0x92` = 0)

1. Get the track list of slot 1 (database order) and make a copy.
2. Shuffle the copy:

   ```text
   i = n
   while i − 1 ≠ 0:
       j = index(i)            ; 0 … i − 1
       swap a[j], a[i − 1]
       i = i − 1
   ```

3. If there is a current track, find it in the copy. Move each track before it one position later. Then put the current track at position 0.

### Albums mode (`+0x92` ≠ 0)

1. Get the track list of slot 6 (album order) and make a copy.
2. Divide the list into groups. A group is a run of tracks with the same album name.
   - The compare uses the UTF-16 bytes and is case-sensitive.
   - The firmware keeps a maximum of 255 characters of each name.
   - A track with an empty album name is a group of its own.
   - The name of a group is the name of its first track.
3. Each group has a start, an end and a flag. The flag is set if the group has the current track.
4. Shuffle the groups with the same loop as in Songs mode. `n` is the number of groups.
5. If there is a current track, swap the group with the flag and group 0. This is a swap, not a move.
6. Copy the tracks of each group in the new group order. The tracks of a group stay in their order.
7. If `+0x93` is 0, stop here. The current track stays at its place in its album.
8. If `+0x93` is not 0, shuffle the tracks in each group (refer to Bug 3). Then move the current track to position 0, as in Songs mode.

### After the shuffle

0xb40c4 writes the new position of each track to the track item `+0x24`. Then it frees the copy and sends the update events (0xb0d0c, 0xb2bc4).

## Emulator tests

The emulator answers 0 for 0x60006038. Thus the seed in the emulator is 0, and the generator stays at 0x7fffffff (refer to Bug 2). For a correct test, a test firmware for the emulator only changed `FUN_0000055c`:

| Offset | Stock | Test firmware |
|---|---|---|
| 0x55c | `ldr r0,[0x570]` | the same |
| 0x560 | `ldr r1,[r0,#0x38]` | `bx lr` |
| 0x570 | 0x60006000 | the seed, 0x12345678 |

Do not install this firmware on a real iPod. The test library was the iPodFirm test library (60 tracks, 6 albums of 10 tracks, track IDs 197–256). Each run started cold (`--cold`) from a new copy of the drive.

| Test | Result |
|---|---|
| Shuffle Songs, stock firmware, seed 0 | The state after the shuffle was 0x7fffffff, as the model gives. |
| Shuffle Songs, seed 0x12345678 | The state after the shuffle was 0x6c572db3. The model gives the same value after 59 calls. |
| The same run: undo the swaps of the model on the result | The input is 197, 198, … 256. Thus the model and the firmware make the same order. |
| The same run: the first tracks | 224, 207, 248, 232, 238, 246, 243, 203, … Now Playing showed track 224 (Test Song 28) as "1 of 60". |
| Settings → Shuffle → Albums, then Shuffle Songs, seed 0x12345678 | The album order was 5, 1, 6, 4, 3, 2. The tracks of each album stayed in order. The state was 0x1f0e9102. The model gives the same order and the same state. |
| Settings word +0x90 in Albums mode | 0x00010000 (`+0x92` = 1, `+0x93` = 0). |
| A song from the Songs list with Shuffle = Songs | No result. The song does not start in the emulator, because the emulator has no audio. |

Notes:

- In the first session after a cold start, Now Playing sometimes showed "2 of 60" or "3 of 60", with the second or third track of the shuffled list. The emulator has no audio, so the first tracks fail and the player goes to the next track. After a restore point, the same list showed "1 of 60".
- The emulator keeps a restore point in the profile. Without `--cold`, a run continues from the old state.
- The Songs menu lists the tracks by title (1, 10, 11, …). Shuffle Songs uses slot 1, the database order (197 … 256).

The reference model is [shuffle-model.py](shuffle-model.py). Run it to repeat the checks:

```sh
python3 re/shuffle-model.py
```

## Known bugs in the firmware

### Bug 1: an index equal to n

The float32 of a state from 0x7fffffc0 to 0x7ffffffe is 2³¹. Then u = 1.0 and the index is `n`, not a value from 0 to n − 1. The swap then uses the word after the end of the list. The probability is 63 / (2³¹ − 2), approximately 1 in 34 million, for each random index.

### Bug 2: seeds that stop the generator

The seeds 0, 0x7fffffff and 0x80000001 give the state 0x7fffffff. The generator then stays at this value. Each index is then `n` (Bug 1). The probability of these seeds is 3 in 2³² for each start. The emulator always has this case, because it answers 0 for 0x60006038.

### Bug 3: the inner album shuffle uses the wrong index

With `+0x93` set, the firmware shuffles the tracks of each group at 0x946d0:

```text
for k = end down to start + 1:
    j = index(k − start + 1)       ; 0 … k − start
    swap work[k], work[j]          ; j is not offset by start
```

`j` must be `start + j`. Thus a track can change places with a track of the first groups of the source list. The code copies each group when it gets to it. Thus a track can occur two times in the result, and another track can be lost. The stock Settings menu does not set `+0x93`, so this bug is not visible on a stock iPod. The patch [shuffle-album-mix](#the-patch-shuffle-album-mix) sets `+0x93`, thus it needs `shuffle-fixes`.

### Bug 4: lists with more than 32767 tracks

The argument of `FUN_000e5978` is 16-bit. With more than 32767 tracks, `n` becomes negative. The index is then negative.

The 3 callers in 0x94440 give a full 32-bit `n` (`add r0, r5, #1` at 0x94754, and the same at 0x94608 and 0x946d4). They use r0 as a 32-bit index. The cuts to 16 bits are in the index function:

```text
0xe59b0  e1a01805  mov r1, r5, lsl #16     ; r5 = n
0xe59b4  e8bd4070  pop {r4-r6, lr}
0xe59b8  e59f0008  ldr r0, [0xe59c8]       ; 0x1081e048, the state
0xe59bc  e1a01841  mov r1, r1, asr #16     ; n = int16(n)
0xe59c0  eaff26bb  b 0xaf4b4               ; the generator, (state pointer, n)
...
0xaf4b8  e1a07001  mov r7, r1              ; n stays in r7
...
0xaf510  eb07e4d2  bl 0x2a8860             ; float to int
0xaf514  e1a00800  mov r0, r0, lsl #16
0xaf518  e1a00840  mov r0, r0, asr #16     ; index = int16(index)
0xaf51c  e8bd81f0  pop {r4-r8, pc}
```

For each step `i` > 32767 of the loop, the index is from −(65536 − i) to 0. The swap then reads and writes up to approximately 128 KB before the list. The heap can become damaged.

0xb40c4 writes the new position to the track item `+0x24` with a 32-bit store. Thus the positions do not have a 16-bit limit.

## Who sets +0x93

The aim: to find if the firmware can switch on the inner album shuffle (`+0x93`). Research on 20 October 2026 with Ghidra and a raw search of osos 1.3.

### The Shuffle setter

`0xb3a04(app, mode)` writes only `+0x20` (`mode != 0`) and `+0x92` (`mode == 2`) of `*(app + 0xca0)`. It never writes `+0x93`. It has 4 callers: 0x1919d8 (the Settings controller), 0x268d84, 0x1f4b70 and 0xf5904. All callers go through the same two writes.

### A raw search for writes at offset 0x93

The search looked for `strb rX, [rY, #0x93]` and for `strh rX, [rY, #0x92]`, which also writes byte 0x93.

| At | Instruction | Function | Result |
|---|---|---|---|
| 0x00048c | `strh r0, [sp, #0x92]` | — | A stack variable. Not the settings. |
| 0x0cd728 | `strh r1, [r0, #0x92]` | — | Offset 0xa92 of a different object (refer to below). |
| 0x15dbcc | `strb r8, [r0, #0x93]` | 0x15d9bc | A constructor. Refer to below. |
| 0x2002c4 | `strh r0, [r12, #0x92]` | 0x2001e8 | A stack variable (refer to below). |
| 0x20b6b8 | `strh r8, [r5, #0x92]` | 0x20b39c | A list object (refer to below). |

The reads with offset 0x93, or with a halfword at 0x92: 0xb4120 and 0xbb430 (the two callers of the shuffle), 0x9da30 (0x9da18, a global object; the iAP handler 0x1a3254 calls it), 0x9e95c (0x9e958, a global object) and 0x113798.

The search cannot find a block copy, for example a load of the settings file that copies `+0x90` as a word.

### The constructor 0x15d9bc

- It writes `+0x90` … `+0x96`, `+0x98` … `+0x9e` and `+0xa8` of a part of the object. Then it returns the address of this part − 0x6c.
- `+0x92` and `+0x93` come from its 2nd and 3rd arguments.
- Ghidra finds no caller, because the analysis did not include the caller. A raw search found one `bl` at 0x25df0c, in 0x25de24.
- 0x25de24 is a C++ static constructor. It constructs several global objects at the base 0x149dd438 and registers each one with 0x25aa40.
- It calls `0x15d9bc(base + 0x200, 2, 2, 1, 0)`. Thus this object gets `+0x92` = 2, `+0x93` = 2, `+0x90` = 1 and `+0x91` = 0.
- The objects at base + 0x90 (0x15bbb8) and base + 0x11c (0x15f8a0) get the same arguments `(2, 2, 1, 0)`.

An emulator test showed that this object is not the playback settings (refer to below).

### The settings pointer

- `0xa2310(settings, …)` stores its first argument at `app + 0xca0` (the `str` at 0xa234c). It is the only store to offset 0xca0 in a heap object; the other three are stack stores.
- `0x1ebe9c` calls 0xa2310 with its own second argument. `0x1d9430` calls 0x1ebe9c. The static trace stops here.

### Emulator test of the setter

Stock firmware with the fixed seed, 60 tracks, `IPODFW_REGS_AT=0xb3a04,4`. Settings > Shuffle, Select two times (Off → Songs → Albums):

| Item | Value |
|---|---|
| Calls of 0xb3a04 | 2: r0 = app 0x13e27a78, r1 = 1, then r1 = 2 |
| `*(app + 0xca0)`, the playback settings | 0x13e34c74 (heap) |
| Settings `+0x20` | 1 |
| Settings word `+0x90` | 0x00010000: `+0x92` = 1, `+0x93` = 0 |
| The object of 0x15d9bc, word at 0x149dd638 | 0x00669b18, the method table that 0x15d9bc writes |
| Its word at `+0x6c + 0x90` (0x149dd734) | 0x02020001, the values of 0x25de24 |

Thus the playback settings and the object of 0x15d9bc are different objects. The `+0x93` of 0x15d9bc is a field of a different class.

### The other writes at offset 0x92

| At | Base | Result |
|---|---|---|
| 0x0cd728 | `add r0, r4, #0xa00`, then `strh r1, [r0, #0x92]` | Offset 0xa92 of a different object. |
| 0x2002c4 | `add r12, sp, #0x300` | A stack variable. |
| 0x20b6b8 | `r5` = object + 0x100 in 0x20b39c | `+0x190` and `+0x192` of a list object (it also reads `+0x1c6`). |

None of these writes the playback settings.

### The accessory and remote commands

The 3 other callers of the setter, 0x268d84 (from 0x12e58c), 0x1f4b70 (from 0x1f3c18 and 0x1f5138) and 0xf5904 (from 0x24e074), give only a mode number to 0xb3a04. The setter writes `+0x20` = (mode ≠ 0) and `+0x92` = (mode = 2) for each value. Thus no command can set `+0x93`. These callers are probably the accessory (iAP) and remote commands. They were not identified in detail.

### The settings file

The playback settings are the settings data of the iPod. The block from `settings + 8` (0xb6c bytes) is the file `/iPod_Control/Device/Preferences`:

- Save 0xbbf1c: copies the block (0xa8098) and writes it to the file.
- Defaults 0xf3dc0: clears the block (0xb6c bytes), then sets some fields. It does not set `+0x93`. The version word at `+8` is 0x39.
- Load 0xe1b64: clears the block, then reads the file from offset 0 into `settings + 8`, a maximum of 0xb6c bytes. There is no check of the content.
- 0xaf698 calls the defaults and the load. Then it updates old versions. It clears `+0x92` only for a version below 6. It does not change `+0x93`.

Thus the file offset of a field is (field − 8):

| Field | File offset | Meaning |
|---|---|---|
| `+0x20` | 0x18 | Shuffle on |
| `+0x92` | 0x8a | Albums |
| `+0x93` | 0x8b | Shuffle the songs in each album too |

### Emulator test of the settings file

1. Stock firmware with the fixed seed, 60 tracks. At the main menu, the settings block was copied from memory (0x13e34c7c, 0xb6c bytes). The version was 0x39.
2. The copy got 1 at the file offsets 0x18, 0x8a and 0x8b. It went on a new drive as `/iPod_Control/Device/Preferences`.
3. Cold start. The iPod showed no Language screen, because the file has a language.
4. The settings word `+0x90` was 0x01010000: `+0x92` = 1 and `+0x93` = 1. `+0x20` was 1.
5. Shuffle Songs: Now Playing showed "1 of 60", Test Song 41. The state was 0x6c572db3. This is the result of the inner album shuffle with Bug 3, the same as the test firmware gave.

A write watch on the settings word (`IPODFW_WATCH_RANGE=0x13e34d04:4`) counted 16 writes during a start with no file. The emulator does not give the code address of each write.

### Result

- The firmware has no menu item and no command that sets `+0x93`.
- The only way to set `+0x93` is the Preferences file, at file offset 0x8b. The emulator test shows that a changed file switches the mode on in the stock firmware.
- The inner shuffle has Bug 3, which loses and repeats tracks.
- Thus the inner album shuffle is an unfinished feature: the back end and the saved setting exist, but no user interface sets it. It is not known if iTunes or another Apple program ever wrote this byte.

## The patch shuffle-fixes

[patches/shuffle-fixes](../patches/shuffle-fixes/patch.json) corrects Bugs 1–4. Version 1.0 had the name `shuffle-large-library` and corrected only Bugs 1 and 4.

Real iPod 5.5G (owner, 28 October 2026, version 2.1): the patch operates.

### Bugs 1 and 4: 4 changed words

| At | Stock | Patched |
|---|---|---|
| 0xe59b0 | `mov r1, r5, lsl #16` | `mov r1, r5` |
| 0xe59bc | `mov r1, r1, asr #16` | `mov r0, r0` (no operation) |
| 0xaf514 | `mov r0, r0, lsl #16` | `cmp r0, r7` |
| 0xaf518 | `mov r0, r0, asr #16` | `subge r0, r7, #1` |

- `n` and the index are 32-bit. float32(n) is exact for n < 2²⁴.
- An index of `n` (Bug 1) becomes n − 1. With 50000 tracks, the stock probability of Bug 1 is approximately 0.15 % for each shuffle.
- For n ≤ 32767, the index is the same as the stock index, except at the 63 states of Bug 1. Thus the order does not change.
- The card game 0x12d494 calls 0xaf4b4 with `(short)n`, and n is a maximum of 52. The patch does not change the card game.

### Bug 2: a hook on the seed

0xe5978 reads the seed only at one place:

```text
0xe59a0  ebfefd9d  bl 0xa501c              ; 0xa501c: b 0x55c, the seed
0xe59a4  e5840008  str r0, [r4, #8]        ; the state
```

The patch changes this `bl` to `hook_seed`. The hook calls 0x55c. If the seed is 0, 0x7fffffff or 0x80000001, the hook uses `seed ^ 1`. The results 1, 0x7ffffffe and 0x80000000 do not stop the generator. For example, the first step from 0x80000000 gives 0x7fffbe58. All other seeds do not change.

The card game 0x12d494 has its own call of 0x55c. The patch does not change it. In the emulator, the seed is now 1, not 0. Thus the shuffle in the emulator is not degenerate.

### Bug 3: a hook on the inner album index

```text
0x946d0  e0470008  sub r0, r7, r8          ; k − start (r7 = k, r8 = start)
0x946d4  e2800001  add r0, r0, #1
0x946d8  eb0144a6  bl 0xe5978              ; j = 0 … k − start
0x946dc  e0862107  add r2, r6, r7, lsl #2  ; &work[k]
0x946e4  e0861100  add r1, r6, r0, lsl #2  ; &work[j], must be &work[start + j]
```

The patch changes the `bl` at 0x946d8 to `hook_album_index`: `push {r4, lr}; bl 0xe5978; add r0, r0, r8; pop {r4, pc}`. 0xe5978 and 0xaf4b4 keep r8, thus r8 is still `start`. The hook runs only when `+0x93` is set.

The code of the two hooks is 64 bytes after osos (`load_address` "extended").

### The model

`Random(seed, patched=True)` and `shuffle_albums(..., inner=True)` in [shuffle-model.py](shuffle-model.py) are the model of the patch. With the seed 0x12345678 and `+0x93`, the stock model keeps only 51 different tracks of 60. The patched model gives 60.

### Emulator tests of the patch

Emulator tests of version 1.0 with the fixed seed 0x12345678 (refer to [Emulator tests](#emulator-tests)), 20 October 2026:

| Test | Result |
|---|---|
| Patched, 60 tracks, Shuffle Songs | Now Playing showed "1 of 60", Test Song 28. The state was 0x6c572db3. This is the same as the stock firmware. |
| Patched, 40000 tracks (`make_library(total_tracks=40000)`), Shuffle Songs | The shuffle completed. The state was 0x4a615aa7. The patched model gives the same state after 39999 calls. Nothing played after the shuffle, because the emulator has no audio. |

Emulator tests of version 2.0, 60 tracks, 20 October 2026. The variants `inner-*` use a test firmware for the emulator only: `ldrb r2/r3, [r0, #0x92/#0x93]` at 0xb411c and 0xb4120 become `mov r2, #1` and `mov r3, #1`. Thus Shuffle Songs runs the Albums mode with the inner shuffle.

| Test | Result |
|---|---|
| Patch, the seed of the emulator (0) | The hook changed the seed to 1. The state was 0x7460ee5a, as `Random(0, patched=True)` gives after 59 calls. Now Playing showed "3 of 60", Test Song 6, the third track of the model order. The first two tracks failed, because the emulator has no audio. |
| Patch, fixed seed 0x12345678 | The state was 0x6c572db3, Test Song 28 first. This is the same as the stock firmware. |
| Inner album shuffle, stock, fixed seed | Now Playing showed "1 of 60", Test Song 41 (track 237). The state was 0x6c572db3. The stock model gives the same first track. This model order has only 51 different tracks (Bug 3). |
| Inner album shuffle, patch, fixed seed | Now Playing showed "2 of 60", Test Song 46 (track 242). The patched model order starts 239, 242. The first track failed, because the emulator has no audio. The model order has 60 different tracks. |

The emulator tests read only the state and the first tracks, not the full lists.

Notes on the test with 40000 tracks:

- The emulator ran at approximately 0.19 × the real speed while the firmware loaded the library. The load took approximately 25 minutes.
- Do not set `IPODFW_RESET_AFTER` for a large library. The start takes more than 10⁹ instructions, and a start check then restarts the emulated iPod.
- The stock firmware with 40000 tracks was not tested. Its shuffle writes outside the list.

## The patch shuffle-album-mix

[patches/shuffle-album-mix](../patches/shuffle-album-mix/patch.json) adds a 4th value to Settings > Shuffle: "Album Mix" (mode 3, `+0x93` = 1). It needs `shuffle-fixes` because of Bug 3.

### The Shuffle item of the Settings menu

- The key of the item is 0x6057. The Settings controller keeps the mode in the byte `controller + 0x1c`.
- 0x192994 and 0x193b90 load the mode with 0x9edb0: `+0x20` ? (`+0x92` ? 2 : 1) : 0.
- The value text (get method 0x190b00) is the string `0x6058 + mode`: 0x6058 Off, 0x6059 Songs, 0x605a Albums. The string 0x605b exists in no language, but it is the key of the Repeat item. The Repeat values start at 0x605c.
- Select (set method 0x1919d8):

```text
0x191e90  e5d4001c  ldrb r0, [r4, #0x1c]
0x191e94  e2800001  add r0, r0, #1
0x191e98  e20000ff  and r0, r0, #0xff
0x191e9c  e3500002  cmp r0, #2             ; the patch: cmp r0, #3
0x191ea0  e5c4001c  strb r0, [r4, #0x1c]
0x191ea4  85c4801c  strbhi r8, [r4, #0x1c] ; r8 = 0: wrap to Off
0x191ea8  e5d4101c  ldrb r1, [r4, #0x1c]
0x191eac  e5940098  ldr r0, [r4, #0x98]    ; app
0x191eb0  ebfc86d3  bl 0xb3a04             ; the setter
```

- The setter 0xb3a04 returns early if `+0x20` and `+0x92` do not change. Else it writes them, calls 0xa983c (`+0xb74` = 1, "changed") and ends with a tail call to the refresh 0x11147c(app).

### The hooks

| At | Hook | Function |
|---|---|---|
| 0x1929a0, 0x193b9c | `hook_get_mode` | 3 if 0x9edb0 gives 2 and `+0x93` is set |
| 0x191eb0 | `hook_set_mode` | Writes `+0x93` = (mode = 3). If it changes, calls 0xa983c. Between Albums and Album Mix, calls 0x11147c. Else calls the setter with mode 2 for Album Mix. |
| 0x66c94c (`chain`) | `hook_settings_get` | For the Shuffle item (key 0x6057) in mode 3: the text ID 0x7e10 and the text "Album Mix" |
| 0x21f254 (`chain`) | `hook_lookup` | The string 0x7e10 is "Album Mix" |

The other callers of 0x9edb0 (the accessory commands) do not change. Thus an accessory sees Album Mix as Albums.

The iPod keeps `+0x93` in its settings file. A firmware without the patch still loads it. Thus the app sets the file byte 0x8b to 0 before it writes a firmware without the patch (`IPodPreferences.clearAlbumMix`).

### Emulator test

With `shuffle-fixes`, the fixed seed 0x12345678 and 60 tracks, 20 October 2026:

| Step | `+0x20` | `+0x92` | `+0x93` | Value text |
|---|---|---|---|---|
| Start | 0 | 0 | 0 | Off |
| Select 1 | 1 | 0 | 0 | Songs |
| Select 2 | 1 | 1 | 0 | Albums |
| Select 3 | 1 | 1 | 1 | Album Mix |
| Select 4 | 0 | 0 | 0 | Off |

In Album Mix, Shuffle Songs gave "1 of 60", Test Song 43, state 0x6c572db3. `shuffle_albums(..., inner=True)` with the patched model gives the same first track (239) and state.

A first version gave the text with the string 0x605b. Then the Repeat row also showed "Album Mix": 0x605b is the key of the Repeat item (0x602f + 0x2c), and the menu shows a string with the key of a row if the string exists. Version 1.0 thus hooks the "get" method and uses the string 0x7e10.

### The main menu item (version 1.2)

The owner asked for the 4 Shuffle values in the main menu (22 October 2026). Shuffle Songs stays. A second item "Shuffle: <value>" goes after it. The method is the method of the main menu item of `usb-audio-out` 1.3.

| Result | Evidence |
|---|---|
| Menu 24094 (main menu): Shuffle Songs is item 27, label 0x5f9e. It is an action item: +0x04 = 0x20, +0x0c = its script 0x3f8a. | Static (the menu data) |
| Menu 24600 (Settings > Main Menu): the Shuffle Songs row is item 24, label 0xff49, key 0x60005f9e. | Static (the menu data) |
| Menu 24598 (Settings): the Shuffle item has the label −135 (0xff79) and the key 0x60006057. The string 0x6057 does not exist: a lookup gave an empty text. Use −135 for "Shuffle". | Static, Emulator |
| `settings_object()` (0x193090) is the Settings controller. Its byte +0x1c is the cached mode of the Shuffle item, and +0x98 is the main browser (the `app` of 0x9edb0 and 0xb3a04). | Static, Emulator |

The hooks of version 1.2:

| At | Hook | Function |
|---|---|---|
| 0x6776f8 (`chain`) | `hook_activate` | Select on the item 0x7e11: the next mode (after Album Mix: Off) with `hook_set_mode`. Also writes the mode to `controller + 0x1c`. Then draws the row again with 0x239f7c. |
| 0x105a04 (`chain`) | `hook_menu_bit` | The item 0x7e11 has the bit 0x20000000 of the main menu mask. |
| 0x19ed58 (`chain`) | `hook_set_visible` | When the UI script sets Artists, the patch shows or hides the item from its bit. |
| 0x66c94c (`chain`) | `hook_settings_get` | The row 0x7e13 shows On or Off. Other questions use the key of Shuffle Songs. |
| 0x66c950 (`chain`) | `hook_settings_set` | Select on the row 0x7e13 toggles the bit and sends 'Bool'. |
| 0x21f254 (`chain`) | `hook_lookup` | 0x7e11: "Shuffle: " and the value text 0x6058 + mode ("Album Mix" for mode 3). 0x7e12: the string −135. |

Emulator test, 22 October 2026, fixed seed, 60 tracks. Run 1 with `shuffle-fixes`, `shuffle-album-mix`, `album-artists` and `usb-audio-out`; run 2 with only the two shuffle patches:

1. The main menu did not show the item at the start (default Off).
2. Settings > Main Menu had the row after Shuffle Songs, with the value Off. Select changed it to On.
3. The main menu then showed "Shuffle: Off" after Shuffle Songs. The highlight stopped on it.
4. Four Select pushes gave "Shuffle: Songs", "Shuffle: Albums", "Shuffle: Album Mix" and "Shuffle: Off".
5. With Album Mix in the main menu, Settings > Shuffle showed Album Mix. One Select there gave Off, and the main menu item then showed "Shuffle: Off".
6. Shuffle Songs started the music with the shuffle icon ("2 of 60"; the first song fails because the emulator has no audio).

In run 1, the row had no name, because the patch used the string 0x6057. Run 2 used −135 and showed "Shuffle".

Real iPod 5.5G (owner, 28 October 2026): version 1.2 operates.

## Checks of the shuffle patches with a large library

The aim: to find a fault in the shuffle patches with a large library below 32767 songs, at the end of a song.

### Static checks of the shuffle patches

The checks used the decompiled osos 1.3 and a scan of all `b` and `bl` instructions of osos 1.3 (29 October 2026).

| Target | Calls (at) | Result |
|---|---|---|
| 0xe5978, the random index | 0x9460c, 0x946d8, 0x94758 | All 3 calls are in 0x94440. Thus the 4 changed words of `shuffle-fixes` do not change other code. |
| 0xaf4b4, the generator | 0xe59c0 (`b`), 0x12d4e0 | The music shuffle and the card game (n ≤ 52). |
| 0x94440, the shuffle | 0xb4128, 0xbb440 | 0xb40c4 and the smart playlist evaluation. |
| 0xb40c4, start a shuffled play list | 0x9dd1c, 0x9e7ec, 0xb0d88, 0xb3748 | The 4 callers of the open question below. |
| 0xa501c, the jump to the seed | 0xe59a0, 0xae080, 0x12d4bc, 0x16b124 | Only 0xe59a0 has the hook of `shuffle-fixes`. |

| Item | Result |
|---|---|
| Counts, indexes and positions in 0x94440 and 0xb40c4 | 32-bit. 0xb40c4 writes the position to `item + 0x24` with a 32-bit store. |
| The track count of the list | The halfword at root `+0x32`. The maximum is 65535. |
| `shuffle-fixes` with n ≤ 32767 | The order is the stock order (refer to [Bugs 1 and 4](#bugs-1-and-4-4-changed-words)). |
| The hook of Bug 3 (0x946d8) | It runs only with `+0x93` (Album Mix). Shuffle Songs does not use it. |
| `up-next` | It changes the play list only in `hook_add`, at a hold of Select. Its other hooks give texts and the Settings item. It does nothing at the end of a song. Its count is a halfword and its positions are 32-bit. |
| `shuffle-album-mix` | It changes only the Settings item, the main menu item and `+0x93`. It does nothing at the end of a song. |

Result: the static checks found no fault in the shuffle patches for a library below 32767 songs.

### A possible cause of a stop at the end of a song: the RAM

- A 32 MB iPod (30 GB model) reaches its track limit at about 17,000 to 20,000 tracks (refer to [ram-limit.md](ram-limit.md)). A library of more than 15,000 tracks is near this limit.
- The free heap stays at about 3 MB for all library sizes. A large buffer becomes smaller when the library becomes larger. It is probably the music buffer.
- At the end of a song, the player loads the next song. If the load fails, playback stops.
- A shuffle also uses heap: a copy of the list (4 bytes for each track) and the sorted arrays of slot 2. Patches such as `album-artists`, `album-art` and `cover-flow` also use heap.

This cause is not proved. If a stop occurs, a test with the stock firmware on the same iPod must find if a patch is the cause.

### A gap in the tests

The real iPod test of `shuffle-fixes` 2.1 (28 October 2026, 50000 songs) used Next. The test steps in `patch.json` also used Next. No test let a song play to its end with a large library and shuffle on. Version 2.2 of `patch.json` adds this step.

## How to copy the algorithm exactly

1. Use a 32-bit state and the Schrage form above. Use signed division that truncates toward zero.
2. Use single-precision floats for u and p, in the same order: first `float32(state) × 2^−31`, then `float32(n) × u`.
3. Truncate p toward zero.
4. For Songs mode, shuffle the full list, current track included. Then move the current track to the start.
5. For Albums mode, sort the tracks by album first, as the album index does. Then use the groups, the group shuffle and the swap of the current group.
6. For a new seed, take two random 16-bit values A and B and use `A XOR (B << 16)`.

A copy for normal use must not copy Bugs 1–4. The patch `shuffle-fixes` corrects Bugs 1–4 on the iPod. MiMusic limits the index to n − 1 and does not use a seed that stops the generator.

## The copy in MiMusic

MiMusic (`~/Documents/GitHub/MiMusic`) has the algorithm in `Packages/MiMusicKit/Sources/PlayerKit/IPodShuffle.swift`:

- `IPodRandom` is the generator and the float32 index. Swift `Float` uses the same rounding as the firmware.
- `IPodShuffle.songs` and `IPodShuffle.albums` are the two modes. They return a permutation of the positions.
- `PlayQueue` uses them. The shuffle button and Controls → Shuffle step through Off, Songs and Albums.
- If Shuffle is on and nothing is queued, Play shuffles the whole library with no current song (`PlayQueue.loadShuffled`). This is the same as Shuffle Songs in the iPod main menu.
- `IPodShuffleTests.swift` checks the emulator results of this note.

The differences from the firmware:

| Item | Firmware | MiMusic |
|---|---|---|
| Index equal to n (Bug 1) | Uses the word after the list. | Uses n − 1. |
| Seeds that stop the generator (Bug 2) | Possible. | `randomSeed()` does not give them. |
| More than 32767 tracks (Bug 4) | Negative index. | Correct index. |
| Inner album shuffle (Bug 3) | Possible with `+0x93`. | Not available. |
| Album order | The album index of the database (slot 6). | Album name (no case, no accents), disc, track number, title. |
| Seed time | At the first shuffle after a start. | When the queue is made. |

## Other users of random numbers

| Address | User | Generator |
|---|---|---|
| 0x143660 | Photo slideshow, "Shuffle Photos". It shuffles only the window of loaded photos with `swap(a[i], a[rand() % n])`. The slideshow settings: +2 = shuffle, +3 = repeat (0x16d174). | `rand()` 0x11ac38 |
| 0x16bb44 | Picks 5 different random items (a quiz with 5 answers). | `rand()` |
| 0x150158, 0x150464, 0x14f680 | Particle effects of a game. | `rand()` |
| 0x1903bc, 0x19044c | Random changes of a colour and of a value. | `rand()` |
| 0x12d494 | Deck shuffle of a card game. | Park–Miller, own state |
| 0x0c4c50 | `x = 1664525 x + 1013904223` (state 0x4000c2cc). 0xd3e30 makes a buffer of noise values from it. | Numerical Recipes LCG |

`rand()` (0x11ac38) is `state = 1103515245 × state + 12345`, return `(state >> 16) & 0x7fff`. `srand()` (0x11bb18) writes the state at 0x1081dae4. Only 0x16b114 calls `srand()`.

## Open questions

- Does the list of slot 1 contain the tracks with "skip when shuffling" (mhit byte 0xa5)? No code was found that reads this byte from the track data.
- With Repeat All, does the firmware shuffle again at the end of the list? Real iPod (20 October 2026): one album with Album Mix and Repeat All plays with no end, and the songs stay shuffled. Not known: does each pass have a new order or the same order?
- When Shuffle changes during playback, which caller of 0xb40c4 runs (0xb36b8, 0x9dc54, 0x9e710 or 0xb0d40)?
- Does a 32 MB iPod near its track limit stop playback at the end of a song with shuffle on? Refer to [Checks of the shuffle patches with a large library](#checks-of-the-shuffle-patches-with-a-large-library).
- A test on the real iPod with a large library: let a song play to its end with Shuffle Songs. Does the second song start?
- The sort of 0xddf94 for slot 6 when the database has no album index (0x1174b4 gives the compare).
- A test on the real iPod: the same library on two starts must give two different orders.
- Done: a Shuffle value that sets `+0x93` (shuffle the songs in each album too). The patch [shuffle-album-mix](#the-patch-shuffle-album-mix) adds the value "Album Mix". The notes below are the research before the patch.
  - Start points: the setter 0xb3a04 and the Settings controller 0x1919d8. They set only `+0x20` and `+0x92`.
  - The firmware saves `+0x93` at offset 0x8b of `/iPod_Control/Device/Preferences`, and loads it with no check (refer to [Who sets +0x93](#who-sets-0x93)). Thus the iPodFirm app can switch on the mode with a change of this file, with no new menu item in the firmware.
  - A menu item in the firmware needs a new string and research of the Settings menu.
  - Without `shuffle-fixes`, the mode has Bug 3. Thus a menu item for the mode needs `shuffle-fixes`.
