# The playback path and the patch playback-log

This note records how RetailOS 1.3 goes to the next song, how it starts a song and where the music can stop. It also records the hook sites of the test patch [playback-log](../patches/playback-log/patch.json). The aim of the patch is a log from a real iPod when the music stops, for example after the first song of a shuffle.

All addresses are osos offsets of firmware 1.3. The research used the decompiled osos 1.3, a disassembly of osos 1.3 and Ghidra 12.1.4 on 29 October 2026. Evidence: Static, unless the text says something different.

## The next song

`0xac4c4(player, flags)` is the "next song" action. [play-next.md](play-next.md) found it first. The current item is `player + 0x2a4`.

```text
0xac55c  bl 0x1968c0     ; next = the item after the current song (play list, song, flags | 4)
0xac560  movs r4, r0
0xac564  beq 0xac57c     ; no next item: stop
...
0xac588  bl 0xeb610      ; (player, 0, 0): no song. The player stops.
...
0xac5b4  bl 0xac6f4      ; play the item. 0 or -0x80: done. Else try the next item.
...
0xac5d4  bl 0xeb610      ; set the item (the player does not play). Not 0: try the next item.
0xac5e0  ldr r2, [r7, #0x2a4]
0xac5f8  bleq 0xb2bc4    ; no current song: the event that sends the user interface to the menus
```

- `0x1968c0(play list, song, flags)` gets the next item through `0x9dc54` (type 0x33: slot 1, or slot 2 with shuffle on). `0x9dc54` makes a missing sorted array with `0x1120bc`. With flag 4, it writes the new position to play list + 0x14.
- `0x1968c0` skips an item if `0x235b68` gives 0.
- The loop also stops if it gets the first failed item again.
- Thus the music stops and the menus show if no next item is found, or if no item of the list can play.

## Play a song

`0xac6f4(player, item, flags)` plays an item. It returns 0 if the song plays.

| At | Call | Result |
|---|---|---|
| 0xac750 | `0xeb610(player, item, flags)`: set the song | An error code |
| 0xac7b4 | `0x10b894(player, item, flags, &out, cache)`: probably the open of the decoder | An error code |
| 0xacb08 | `0xd9b70`: the start | 0 calls 0xad004 |

`0xeb610(player, item, flags)` sets the current song. Some error codes:

| Code | Cause |
|---|---|
| −0x32 | The song cannot play: track list + 0xed bit 0x20 is set, or 0xad6b0 does not give 0. |
| −0x6c | No memory: `0xa8dc4` gives 0. |
| Other | The result of `0xfb894` or `0xe17a0`. |

## The memory

| Address | Function |
|---|---|
| 0xa8180 | `(size)`: `mov r1, #4; b 0xc7518`. 29 calls. |
| 0xc7518 | `(size, alignment)`: an allocator. It calls 0xc2e0c and then 0x1ac324 with the heap. 6 calls. |
| 0x25a974 | `(size)`: `mov r1, #2; b 0x11ca20`. 923 calls. Probably `operator new`. |
| 0xa8178 | `(size)`: `mov r1, #4; b 0x11ca20`. 25 calls. |
| 0x11ca20 | `(size, flags)`: an allocator. It calls 0xc2e0c and then 0x1ac9b4 with the heap. 62 calls. |
| 0xc7444 | The free bytes of the heap. |
| 0x9d9d0 | The RAM size: `ldr r0, [SysInfo]; ldr r0, [r0, #0xe0]`. Refer to [ram-limit.md](ram-limit.md). |

## The calls of the shuffle

| Target | Calls |
|---|---|
| 0xb40c4, start a shuffled play list | 0x9dd1c, 0x9e7ec, 0xb0d88, 0xb3748 (`blne`) |
| 0x94440, the shuffle | 0xb4128 (in 0xb40c4), 0xbb440 (smart playlist) |

Refer to [shuffle.md](shuffle.md#checks-of-the-shuffle-patches-with-a-large-library).

## The patch

The patch is a test patch (category `test`). It has 13 hooks. No other patch on main uses these sites, except 0x1d8260 (`usb-host-probe`).

| At | Kind | Hook | Record |
|---|---|---|---|
| 0xb40c4 | `b` (`chain`) | `hook_start` | The caller, the count, the current song, `+0x92`, `+0x93` |
| 0xb4128 | `bl` | `hook_shuffle` | The time, the random state before and after, the seed flag, the count, empty positions, repeated songs, the first 3 songs |
| 0xbb440 | `bl` | `hook_smart_shuffle` | The count and the time |
| 0xac4c4 | `b` (`chain`) | `hook_next` | The caller, the flags, the position before and after |
| 0xac55c | `bl` | `hook_next_item` | The next item, its song and track, the position |
| 0xac588 | `bl` | `hook_stop` | "stop: no next song" and the position |
| 0xac5d4, 0xac750 | `bl` | `hook_set` | A failed set of the song and its code |
| 0xac6f4 | `b` (`chain`) | `hook_play` | The caller, the item, the result |
| 0xac7b4 | `bl` | `hook_open` | A failed open of the decoder and its code |
| 0xc7518, 0x11ca20 | `b` (`chain`) | `hook_alloc`, `hook_new` | Each failed allocation: the size, the caller, the free heap |
| 0x1d8260 | `bl` | `hook_event` | Writes the file after a button or wheel event, at most one time each 5 s |

The patcher writes only an unconditional `bl`. Thus the patch does not hook the `blne` at 0xb3748. It hooks the first instruction of 0xb40c4 instead.

The check of repeated songs: 0xb40c4 writes the position i to `item + 0x24` of each item of the result. The hook does this write first. Then it reads each item again. An item that occurs two times keeps only its last position. Thus the count of the differences is the count of repeated songs.

### The information block

The first 2048 bytes of the log have:

- the RAM size (0x9d9d0), the free heap, the lowest free heap and the count of failed allocations;
- the counts of the lines;
- the iPodFirm list of the build (`list <JSON>`). The patch finds the text `iPodFirmManifest1` on a 16-byte step from 0x736800 to 0x7f8000. osos is in RAM, so the list is in RAM too. Refer to [patch-system.md](../docs/patch-system.md#the-ipodfirm-list). The app shows the patches with their letters.

The patch keeps the text of the magic with each byte XOR 0x55. Thus the search does not find the text in the patch itself.

### Tests

- Swift: `PlaybackLogTests`, `testPatchSizes` (38025 bytes), `testPatchMetadata`.
- Python: `test_playback_log_hooks` with the Apple firmware 1.3. Each hook word is correct, and the chain wrapper of 0xb40c4 runs `push {r3-r5, lr}` and continues at 0xb40c8.
- A build of the 17 patches that are not `test` or `internal`, together with `playback-log`, links with no conflict (29 October 2026).
- Not tested in the emulator or on the real iPod yet. The emulator has no audio, thus each song fails there. This is a good test of the records of a failed song.
