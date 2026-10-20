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

`j` must be `start + j`. Thus a track can change places with a track of the first groups of the source list. The code copies each group when it gets to it. Thus a track can occur two times in the result, and another track can be lost. The Settings menu does not set `+0x93`, so this bug is not visible in normal use.

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

## The patch shuffle-fixes

[patches/shuffle-fixes](../patches/shuffle-fixes/patch.json) corrects Bugs 1–4. Version 1.0 had the name `shuffle-large-library` and corrected only Bugs 1 and 4.

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
- With Repeat All, does the firmware shuffle again at the end of the list?
- When Shuffle changes during playback, which caller of 0xb40c4 runs (0xb36b8, 0x9dc54, 0x9e710 or 0xb0d40)?
- The sort of 0xddf94 for slot 6 when the database has no album index (0x1174b4 gives the compare).
- A test on the real iPod: the same library on two starts must give two different orders.
- Future work: a Shuffle value that sets `+0x93` (shuffle the songs in each album too). The patch `shuffle-fixes` corrects Bug 3, but this is only half of the work: no menu item sets `+0x93`.
  - Start points: the setter 0xb3a04 and the Settings controller 0x1919d8. They set only `+0x20` and `+0x92`.
  - Research is necessary: where the firmware saves `+0x93` in the settings file, and a menu item with its string.
  - Without `shuffle-fixes`, the mode has Bug 3. Thus a menu item for the mode needs `shuffle-fixes`.
