# Play Next and Play Last: the play list in firmware 1.3

This note records how the iPod Video 5.5G with RetailOS 1.3 keeps the list of songs that plays now, and how "Add to On-The-Go" adds songs to it. It is research for a possible patch "Play Next / Play Last" (refer to [patch-ideas.md](patch-ideas.md)). No patch exists.

All addresses are osos offsets of firmware 1.3. The research used Ghidra 12.1.4 and the instrumented emulator on 20 October 2026.

## Result

- One global play list object holds the songs that play now. Its pointer is at 0x1081d9cc. Its vtable is 0x66cad4.
- The play list already has a method that adds songs (vtable + 0x10). It adds one row or all rows of a list, but only at the end.
- "Add to On-The-Go" (0xadbb8) adds the songs to the On-The-Go playlist. If On-The-Go plays now, it also adds them to the play list with the same method.
- Thus "Play Last" can use the firmware method directly. "Play Next" must also move the new songs to the position after the current song.

## The play list object

| Offset | Content | Evidence |
|---|---|---|
| +0x00 | Vtable 0x66cad4 | Static, Emulator |
| +0x04 | The track list. Its header is at + 0x28; the count of songs is the u16 at header + 0x32. | Static, Emulator (count 60) |
| +0x08 | The library | Static |
| +0x14 | The index of the current song (0 = the first song) | Static, Emulator |
| +0x18 | Byte: 1 if the list is On-The-Go | Static, Emulator (0) |
| +0x1c | The lock (0xc9a84 locks, 0xc9b58 unlocks) | Static |

`FUN_00196418` returns the object. It makes the object (0x90 bytes, constructor 0x196de0) at the first call. The Now Playing text "%d of %d" (string 0x63c5, `FUN_001e804c` case 0x63c3) uses + 0x14 + 1 and the count method.

| Vtable slot | Function | Content |
|---|---|---|
| +0x0c | 0x195ef4 | The count of songs |
| +0x10 | 0x19602c | Adds songs: lock, 0x2358fc, unlock |
| +0x14 | 0x195f58 | Removes songs: lock, 0x235858, unlock |
| +0x18 | 0x196584 | Clears the list |

## Functions

| Address | Function | Evidence |
|---|---|---|
| 0x196418 | Returns the play list object (pointer at 0x1081d9cc). | Static, Emulator |
| 0x1960b0 | (play list, browser, list, start row, …): fills the play list from a list and sets the current index (+0x14). | Static |
| 0x0abb98 | (browser, row, …): starts a list at a row. Calls 0x1960b0, then gives the list to the player (0xacd80, 0xac6f4). | Static |
| 0x2358fc | (list object, browser, row, source list, sort, flag): adds one row (0x92bbc) or, with row −1, all rows (0x9388c) at the end of the track list at object + 4. | Static |
| 0x0adbb8 | (browser, row): Add to On-The-Go. Row −1 adds all rows. The limit is 1000 songs. If the play list is On-The-Go (+0x18), it calls the play list + 0x10 with the same rows. | Static |
| 0x1eb5a4 | The script function for Add to On-The-Go. Calls 0xadbb8. | Static |
| 0x0bbf2c | Writes `iPod_Control\iTunes\OTGPlaylistInfo`. | Static |
| 0x0b40c4 | Starts a shuffled play list. Writes the shuffle position of each track item to + 0x24 (refer to [shuffle.md](shuffle.md)). | Static, Emulator |

The On-The-Go playlist is at library + 0xce0.

## Emulator test

Test: the stock firmware 1.3, the 60-track test library, Shuffle Songs.

| Peek | Value |
|---|---|
| 0x1081d9cc | 0x13dd1da0 (the play list object) |
| object + 0x00 | 0x0066cad4 (the vtable) |
| object + 0x14 | 1 (the second song: the emulator has no audio, so the first song failed) |
| object + 0x18 | 0 (not On-The-Go) |
| header + 0x32 (u16) | 0x3c = 60 songs |

## The order of the play list (research round 2)

The track list of the play list (object + 4) is a tree of items. The play order comes from a sorted array of one slot.

| Address | Function | Evidence |
|---|---|---|
| 0x235a54 | (list object, i): the item at play position i. It uses slot 1 if the shuffle bit (track list + 0xec, bit 0) is 0, else slot 2. | Static |
| 0x09c838 | (track list, type, reverse, i): the item at position i of a slot. It builds a missing sorted array with 0x1120bc. | Static |
| 0x0eae38 | Maps a list type to a slot. Track list + 0xb0 is the sort type, + 0xec bit 0 is "shuffle on", + 0xed has the reverse bits. Type 0x33 gives slot 1, or slot 2 with shuffle on. | Static |
| 0x1120bc | Slot 1 is the order of the linked items (0xb79e0). The other slots are slot 1 sorted by 0xddf94 with the compare of 0x1174b4. | Static |
| 0x2aa350 | Data, not code: the sort description of slot 2. Its first key is field 0x1000. | Static |
| 0x0b0d0c | (track list, field): frees the caches of the slot of a field: + 0x174, + 0x238, + 0x2fc, + 0x3c0 and + 0x494 (+ 4 × slot). | Static |
| 0x1137c4 | (track list): frees the caches of all slots (1 … 0x30). | Static |
| 0x093504 | (item, track list, cursor, 0): makes a new item for the same song (0xd1df0) and links it with 0xd6614. | Static |
| 0x0d6614 | (item, cursor, notify): links an item. The cursor is {parent, after}. `after` = −1 or no cursor: at the end. `after` = 0: at the start. Else: after the item `after`. It adds 1 to the count (parent + 0x32). With notify = 1, it calls 0x1137c4. | Static |
| 0x0b40c4 | Shuffle: sets + 0xec bit 1, adds 1 to + 0xe8, writes the position of each item to item + 0x24, then calls 0xb0d0c (list, 0x1000) and sends the change event (0xb2bc4 on list + 0x30). | Static, Emulator |
| 0x09e57c | (item, 0x33, 0): the play position of an item, through the index map at + 0x3c0 + 4 × slot. | Static |
| 0x196d48, 0x1964bc | After a change of the list: keep the current item, change the list, then write 0x9e57c (item, 0x33, 0) to play list + 0x14. 0x1964bc also sends an event to the user interface. | Static |
| 0x1968c0 | (play list, song, flags): the item after the item of a song in the play order (0x9dc54 with type 0x33). Flag 4 also writes its index to + 0x14. | Static |
| 0x0ac4c4 | (player, flags): the "next song" action. The current item is player + 0x2a4. It calls 0x1968c0 (flags + 4) at the time of the change. | Static |

Item layout: + 0x00 the track list, + 0x04 the parent, + 0x08 the next item, + 0x0c the previous item, + 0x20 the song (track object), + 0x24 the shuffle position. Parent (root at track list + 0x28): + 0x20 the first child, + 0x24 the last child, + 0x30 and + 0x32 the counts. Evidence: Static (0xd6614), Emulator (the walk below).

Emulator walk (Shuffle Songs, 60 songs): track list + 0xb0 = 1, + 0xec = 0x43 (shuffle on and done). The first six items in link order had + 0x24 = 0, 2, 3, 4, 5, 6. Their songs had the test values (refer to [song-info.md](song-info.md)). The emulator seed is 0, so the shuffle order is not random (refer to [shuffle.md](shuffle.md)).

The player does not keep a copy of the next song. It asks the play list at the time of the change (0xac4c4 → 0x1968c0). Thus a change of the list before the end of the song is enough.

## The design of a patch

1. Hook the script function of the hold of Select (0x1eb5a4), or 0xadbb8.
2. Show a small menu: Play Next, Play Last, Add to On-The-Go.
3. Lock the play list (+0x1c, 0xc9a84). Keep the current item: 0x235a54 (play list, + 0x14).
4. Play Last: call the play list + 0x10 with the browser and the row (or −1 for an album or an artist). The items go to the end of slot 1.
5. Play Next, shuffle off: for each song, call 0x93504 (item, track list, {root, after}, 0), with `after` = the current item, then the new item. Then call 0x1137c4.
6. Play Next, shuffle on: do step 4. Then give the new items the positions after the current song (+0x24), add the count to each later position, and call 0xb0d0c (track list, 0x1000). The model in [shuffle-model.py](shuffle-model.py) can test this.
7. Write 0x9e57c (current item, 0x33, 0) to + 0x14, as 0x196d48 does. Unlock (0xc9b58).

## Emulator tests of the patch

The patch `up-next` (patches/up-next) uses the method above. Tests with the stock firmware 1.3, the patch and the 60-track test library, 20 and 21 October 2026. The script presses Select for 30 ms (a short push) and for 0.9 s of emulated time (a hold); refer to [emulator.md](emulator.md#limits).

| Test | Result |
|---|---|
| Version 0.1, Shuffle Songs, pause, hold Select on "Test Song 15" in the Songs list | The hook ran (0x1eb5a4, no call of 0xadbb8). The count went from 60 to 61. The new item got position 1 after the current item (position 0); the later positions moved by 1. Now Playing showed "1 of 61". Next: "2 of 61, Test Song 15". Next: "3 of 61, Test Song 2", the old order. |
| The same, from a cold start again | The player had already moved to song 2 (no audio). The hold put Test Song 15 after it: "3 of 61, Test Song 15", then "4 of 61, Test Song 3". |
| Version 0.2, Settings > Hold Select | The item shows after Clicker. Each push: Play Next → Play Last → On-The-Go. After a restart of the emulator, the value was still Play Last; the iPod did not keep its language, thus the file write reached the drive at once. |
| Version 0.4 with `cover-flow` 0.6.4, a new drive (no file), no music | Settings showed "Hold Select: Cover Flow" (the start value, written at the first screen). A hold on Test Album 1 opened Cover Flow; the patch did not run. After one push of the item ("Play Next"), the same hold ran 0x1eb5a4 and 0xadbb8 (no music: On-The-Go), and Cover Flow did not open. |
| Version 0.4, Settings > Hold Select = Play Last, Shuffle Songs, hold on Test Song 15 | 61 songs. The new item got position 257, after the old last position (256); the other positions did not change. "1 of 61", Next: "2 of 61, Test Song 2", Next: "3 of 61, Test Song 3" (the old order). |
| Version 0.4, Play Next, Settings > Shuffle = Albums (the list shuffled again) | Before the hold: "10 of 61, Test Song 1". Next: "11 of 61, Test Song 15". Next: "12 of 61, Test Song 11" (the old order of the albums). |
| A start of the music from the Songs list (shuffle off) | The screen froze in several runs, also without the patch. The cause is the slow emulation of the second core (refer to [emulator.md](emulator.md#limits)), not a hang. The shuffle-off path of the patch is not tested yet. |

## Test on the real iPod (21 October 2026)

The owner tested version 0.4 with `cover-flow` 0.6.4 on the iPod 5.5G.

| Test | Result |
|---|---|
| 1. Settings > Hold Select: the 4 values, the value after a restart (Menu+Select) | Pass |
| 2. Play Next, Shuffle Off: the count is m + 1; at the end of the current song, the new song plays; then the album continues | Pass |
| 3. Play Next, Shuffle Songs | Pass |
| 4. A hold on an album or an artist: all its songs play next | Pass |
| 5. Play Last: the song plays at the end of the list | Pass |
| 6. The value On-The-Go; a hold with no music: the songs go into On-The-Go | Pass |
| 7. Cover Flow in the Albums list with the value Cover Flow; Play Next in the Albums list with the value Play Next | Pass |

Other observations of the owner: the row blinks after a hold, as for On-The-Go. Now Playing shows the new count normally. The artwork is correct (with `album-art`). The iPod did not stop or restart.

Test 2 is the first test of the shuffle-off path (0xd6614 order, `move_after`). Tests 2 and 3 also show that the player takes the next song from the changed list at the natural end of a song, not only after Next.

## The pop-up menu (research, 21 October 2026)

A pop-up menu (Play Next, Play Last, Add to On-The-Go) needs a new screen. The firmware has 40 Menu resources, for example 24441 ("Cancel", "Confirm"). No ARM code refers to a Menu ID directly: the script (`TCmd` 9088) opens the menus through View resources. Native code asks for a screen with 0x1d2ee8 (event type 8 with an ID, through 0x13d6d4). The patcher can add items to a Menu, but it cannot add a Menu or a View. Thus the patch uses the Settings item "Hold Select" for now. The pop-up menu is a later step.

## Collisions

- `cover-flow` uses the hold of Select in the Albums list. The small menu can have a fourth item "Cover Flow" in the Albums list. The owner decides.
- `shuffle-fixes` and `shuffle-album-mix` change the shuffle. Test Play Next with Songs, Albums and Album Mix.
- `album-artists` lists also need the menu.

## Open questions

- The answers of the real iPod test (21 October 2026): Now Playing shows the new count, and the artwork stays correct without a stop of the artwork task. Thus the patch does not need the event of 0x1964bc or a stop of the artwork task.
- Songs in a group (for example audiobook chapters) are not tested. The patch then uses On-The-Go.
