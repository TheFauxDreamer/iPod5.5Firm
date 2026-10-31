# The diagnostic log and the playback path

This note records how RetailOS 1.3 goes to the next song, how it starts a song and where the music can stop. It also records the hook sites of the test patch [diagnostic-log](../patches/diagnostic-log/patch.json). The name of this patch was `playback-log` before version 2.0. The older sections use the old name. The aim of the patch is a log from a real iPod when the music stops, for example after the first song of a shuffle.

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

The patch is a test patch (category `test`). Version 1.3 had the 13 hooks in this table. Version 2.0 adds 8 hooks (refer to [The areas of version 2.0](#the-areas-of-version-20)). No other patch on main uses these sites, except 0x1d8260 (`usb-host-probe`).

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

### The areas of version 2.0

Research: Ghidra 12.1.4, osos 1.3, 30 October 2026. Evidence: Static. The patch has not run in the emulator or on a real iPod yet.

Each area has one option in `patch.json`, with a global variable. An area that is off writes no lines. The hooks stay, because the patcher writes option values after the link. The information block has the line `areas ...`.

| Area | Variable | Site | Result |
|---|---|---|---|
| Playback | `log_playback` | The current hook at 0x1d8260 | The hook gets the event. Type 4 is a key push and type 7 is a release. The key code is bits 16-23 of event + 0x10 (0x2564b0). No new hook is necessary. |
| Memory | `log_memory` | The current hooks | A sample adds a line after a change of 64 KB or more in the free heap. |
| Power and Storage | `log_power` | `bl` at 0x1d9344 | The only call of the sleep sequence 0x1ee8d0. The sequence writes the settings file itself (0xbbf1c), thus a file write is safe here. |
| Power and Storage | `log_power` | `bl` at 0x1dfe18 | The only call of the sleep function 0xb43dc. The function returns after the wake. This hook does not use 0xb45f4, which `flash-keep-awake` uses. |
| Power and Storage | `log_power` | `b` at 0x265cc8 | The storage power. The first instruction is `push {r3-r11, lr}`. The hook also sees the call through `flash-keep-awake` at 0x23344c. |
| Power and Storage | `log_power` | 0x265164, in a sample | The raw value: the channel in the high 16 bits, the measurement in the low 16 bits. This is not a battery percentage. The function only reads RAM. |
| Artwork and Files | `log_artwork` | `bl` at 0x2055dc, `bl` at 0x205854 | The artwork lookup 0x1f161c and the image load 0x2258a4 in ArtworkLoadTask. |
| Artwork and Files | `log_artwork` | `b` at 0x8f38c, `b` at 0x8f464 | The file open and the file read. The hooks also time the reads of `album-art` and `cover-flow`, because these patches call the same functions. |
| Performance | `log_performance` | Word at 0x6701f0 | The event method 0x1d81cc. `cover-flow` uses the same word with no chain. The name `cover-flow` sorts first, thus this hook chains to it. |
| Performance | `log_performance` | RAM 0x14983040, in a sample | The idle time of each core, as in `usb-host-probe`. |

Limits:

- A sample runs at most each 30 s, and only at a button or wheel event. A time with no event has no sample. Do not sample more often, because each new line causes a disk write at the next event.
- `ui=` is the longest time in 0x1d81cc. This method does not include each draw of a list.
- The key codes of the click wheel buttons are not proved. The Simple Remote codes are in [firmware-functions.md](../docs/firmware-functions.md). The first log from a real iPod gives the wheel codes.
- A sleep function that does not return loses the lines after the last file write. The file write before the sleep has the line `sleep start`.

### The information block

The first 2048 bytes of the log have:

- the header `PL02 diagnostic-log 2.0` (`PL01` in version 1.x);
- the RAM size (0x9d9d0), the free heap, the lowest free heap and the count of failed allocations;
- the counts of the lines;
- the area switches (version 2.0);
- the settings (version 1.1): Shuffle, Repeat and the Hold Select value of `up-next`;
- the iPodFirm list of the build (`list <JSON>`). The patch finds the text `iPodFirmManifest1` on a 16-byte step from 0x736800 to 0x7f8000. osos is in RAM, so the list is in RAM too. Refer to [patch-system.md](../docs/patch-system.md#the-ipodfirm-list). The app shows the patches with their letters.

The patch keeps the text of the magic with each byte XOR 0x55. Thus the search does not find the text in the patch itself.

### The settings (version 1.1)

| Value | Source | Result |
|---|---|---|
| Shuffle | `0x9edb0(app)`, and `+0x93` for Album Mix | Off, Songs, Albums, Album Mix |
| Repeat | `0x9e96c(app)`: settings `+0x1c`, 1 → 2 and 2 → 1 | 0, 1 or 2. The controller keeps it at `+0x1d`, next to Shuffle. Off and All are proved on a real iPod (fourth log). One is not proved yet. |
| Hold Select | The first character of `iPod_Control\iTunes\iPodFirmHoldSelect` | On-The-Go, Play Next, Play Last, Cover Flow. No file: "not known". |

The app is `settings_object() + 0x98`, the method of `shuffle-album-mix`. Only the UI task reads the settings. Shuffle and Repeat come from RAM at a button or wheel event, at most one time each 5 s. The patch reads the file of `up-next` only before a file write, so that a wheel event does not start the disk. A changed value gives a line `settings ...`. Thus the time of a change in Hold Select is the time of the next file write, not the time of the change.

The app also shows the options of each patch from the iPodFirm list, for example `up-next 0.5 hold=3`. This is the value of the build. The file on the iPod has the value that is in use.

### The song (version 1.1)

In version 1.3, `song=` is the low 32 bits of the dbid: item + 0x20 is the track object, and track + 0x108 is mhit + 0x70 (refer to [song-info.md](song-info.md)). `album-art` and `cover-flow` read the same field on the real iPod. Version 1.2 used track + 0x20: the loader 0xd7888 writes mhit + 0x10 there (0xd7a30), but each line of a log from the real iPod had `song=0` (30 October 2026). The cause of the 0 is not known. The iTunesDB of the same iPod has 5205 tracks and 5205 different dbids, none 0. The patch stores no text on the iPod, because a read of the string pools in the task of the player needs locks. The value 0 means no track.

"Show Playback Log" reads `iPod_Control/iTunes/iTunesDB` of the connected iPod (`ITunesDB.readTrackInfo`). A line with one `song=` gets the title and the artist. A list at the end has the title, the artist, the album and the file of each song in the log. A sync can change the IDs or remove a song. Thus show the log before a sync. For an ID that it does not find, the list and the line write "ID <value> is not in the iTunesDB". The saved file has the names of the songs, but the body of the GitHub issue does not.

### Tests

- Swift: `PlaybackLogTests`, `testPatchSizes` (41768 bytes in version 2.0), `testPatchMetadata`.
- Python: `test_playback_log_hooks` with the Apple firmware 1.3. Each hook word is correct, and the chain wrapper of 0xb40c4 runs `push {r3-r5, lr}` and continues at 0xb40c8.
- A build of the 17 patches that are not `test` or `internal`, together with `playback-log`, links with no conflict (29 October 2026).
- Not tested in the emulator. The emulator has no audio, thus each song fails there. This is a good test of the records of a failed song.

## First log from a real iPod

The owner ran version 1.0 on the iPod 5.5G (64 MB, 5202 songs) with 17 patches on 30 October 2026. The music did not stop. The log had 116 lines, no dropped line and no failed allocation.

### The results

| Item | Result |
|---|---|
| The information block | RAM 64 MB. The list of patches is correct. |
| The free heap | 2,618,056 bytes at the first shuffle, approximately 2.0 MB after the first minutes. The lowest value was 1,979,132 bytes. |
| The end of a song | `next from=ac22c flags=10`. The player then calls 0xac6f4 from 0xac5b4 (`play from=ac5b8`). Each of the 3 ends gave `play end result=0`. |
| The Next button | `next from=a9800 flags=0`. The position changes, but `play` does not run at each push. `play from=a1484` runs later, after the pushes stop. |
| A change of the Shuffle value during playback | `shuffle start from=b0d8c`, the call at 0xb0d88 in 0xb0d40. The current song goes to position 1. |
| Shuffle Songs | `shuffle start from=b374c`, the `blne` at 0xb3748 in 0xb36b8. |
| Shuffle Songs, 5202 songs | 28 ms and 38 ms. |
| The first shuffle with Albums | 4041 ms. The cause is probably the sort of slot 6, because the next shuffle with Album Mix took 153 ms. |
| The check of the result | `empty=0 repeated=0` for Songs, Albums and Album Mix. |
| Album Mix | The first album played 14 different songs in a random order, the current song first. Then the next album started. |

Thus the Next button and the end of a song use two different paths. A test with Next does not test the end of a song.

### The second log

The owner ran a build of version 1.1 on the same iPod on 30 October 2026 (app 0.1.185). That build had the settings, but `song=` was still item + 0x10. The later code in version 1.1 and version 1.2 records the track ID. The music did not stop.

| Item | Result |
|---|---|
| The settings | Shuffle and Hold Select show correctly, and a change gives a timed line. Only `repeat=Off` occurred. |
| The end of a song | 3 more ends, all with `play end result=0`: Album Mix, Songs and Songs. |
| The first shuffle with Album Mix after a start | 2735 ms. Songs took 28 ms and 30 ms. |
| The lowest free heap | 1,935,588 bytes. No failed allocation. |
| A new start of Shuffle Songs | The items get new `song=` values (0x4135 … became 0x5aed … 0x6910). This agrees with a counter. |
| Shuffle changes to Off | One more shuffle runs (30 ms, `albums=0 mix=0`). Then the position is the place of the song in the list that is not shuffled, for example 99 of 5202. |

The patch does not record the Previous button. In the log, the position goes back (`at=101`, then `at=100`) with no line that shows why.

### The third log

Version 1.2 on the same iPod, 30 October 2026 (app 0.1.187). The music did not stop. 2 more ends of a song gave `play end result=0`. Each `song=` was 0. Version 1.3 corrects this (refer to [The song](#the-song-version-11)).

### The fourth log

Version 1.3 on the same iPod, 30 October 2026 (app 0.1.189, 17 patches, with `flash-keep-awake` 1.2 and `flash-wake-on-input` 1.3). The music did not stop. The log had 48 lines, no dropped line and no failed allocation.

| Item | Result |
|---|---|
| `song=` | The values are correct. Each value agrees with a track of the iTunesDB, thus version 1.3 corrects the fault of the third log. |
| Shuffle Songs, 5202 songs | 28 ms, `empty=0 repeated=0`. |
| The lowest free heap | 2,019,040 bytes. |
| `repeat=All` | The owner confirmed that the iPod had Repeat All. |
| The first end of a song (position 2) | `next from=ac22c` 296.4 s after `play`. The file is 296.35 s. This is a correct end of a song. |
| Two other ends (positions 1 and 8) | `next from=ac22c` 33.4 s and 20.9 s after `play`. The files are 165.4 s and 198.6 s. |

The owner fast-forwarded some songs to the end to test the change to the next song. This explains the two short times, and it shows that a fast-forward to the end uses the path of the end of a song. The patch does not record a seek. Thus the log cannot show which songs the owner fast-forwarded.

### A fault in the log

Each line has `track=46494c45`. This is the text `FILE`, not a track ID. Track + 0x0c is a type word, and 0xb7858 compares it. Version 1.1 removes the value `track`.

The value `song` of version 1.0 (item + 0x10) is also not a track ID. It comes from a counter: 0xd1df0 writes the result of 0xa01e8 to item + 0x10. The iTunesDB of the same iPod has the IDs 0x22cd5 to 0x2557a, and it does not have the value 0x449f of the log.
