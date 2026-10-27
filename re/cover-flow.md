# Cover Flow: research notes

This document records the research for the `cover-flow` patch. The firmware is Apple RetailOS 1.3 for the iPod Video. The research started on 8 October 2026.

## Earlier work

A search of GitHub and the web on 8 October 2026 found no Cover Flow for the stock firmware of the iPod 5G or 5.5G:

- The iPodWizard "Classic interface" hacks (2007–2008) changed the menus and the Now Playing screen. They did not add Cover Flow.
- Rockbox has the plugin PictureFlow (GPLv2). It operates only in Rockbox, not in the Apple firmware. It shows that an ARM7 at 80 MHz can draw the effect without 3D hardware.
- [BrandonDedolph/ipod-core](https://github.com/BrandonDedolph/ipod-core) is a new operating system for the 5.5G. It has no Cover Flow.
- All other "coverflow" repositories are web, iOS or macOS copies of the effect.

The patch uses no code from these projects.

## Tools

- Ghidra with the project `osos13` (refer to [../docs/ghidra-guide.md](../docs/ghidra-guide.md)).
- The instrumented emulator (refer to [emulator.md](emulator.md)), with `IPODFW_REGS_AT`, `peek`, `press`, `hold`, `wheel` and `shot`.
- Probe patches in the extended area. A probe calls an empty function `probe_mark` with values in r0–r11. `IPODFW_REGS_AT` at `probe_mark` records the values. The probes were not kept.

CAUTION: The `regs` buffer holds a limited count of records. Event type 0xd comes many times each second. Do not record it, or the buffer is full before the test starts.

## The screen

### How RetailOS sends a frame to the LCD

The emulator research ([research/12 of siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator)) describes the display path. The Ghidra results for the patch:

| Address | Function |
|---|---|
| 0x1647c0 | Returns the display server (RAM 0x10882c3c). |
| 0x164610 | Returns layer N: server + 0x110 + N × 0x90, for N < 11. |
| 0x164878 | Binds layer N (server, N). It waits while server + 0x6c4 is not 0, then sets server + 0x6c4 to the layer. |
| 0x164d0c | A task. After each flush, it sends the update to the BCM and sets server + 0x6c4 to 0. |
| 0x1650f8 | Flush (server, N). If layer N is bound, it calls the present 0x164f44 with the layer and server + 0x6b0. |
| 0x164f44 | Present. Sends the dirty rows of the CPU framebuffer to the BCM surface. |
| 0x17ef98 | Damage callback (unused, rect, 0). Sets the dirty flag and the dirty rows. If the byte at 0x1081ec54 is not 0, it binds the layer first. |
| 0x169718 | An example of the full sequence: bind, set the update, flush. |
| 0x0c9a84, 0x0c9b58 | Lock and unlock (the mutex at server + 0x6c8). |

The layer index is the word at RAM 0x1081e0d4. Its value is 0 in the emulator.

The layer has these fields:

| Offset | Content |
|---|---|
| +0x00 | Byte: 1 if the layer is valid |
| +0x04 | The CPU framebuffer, RGB565, 320 × 240 |
| +0x0c | The BCM surface. Surface + 0x10 is the stride in bytes (0x280 = 640). |

The update at server + 0x6b0 has these fields:

| Offset | Content |
|---|---|
| +0x0e (server + 0x6be) | Byte: 1 = send the dirty rows |
| +0x10 (server + 0x6c0) | u16: the first dirty row |
| +0x12 (server + 0x6c2) | u16: the end of the dirty rows |

Emulator results:

- Between two frames, server + 0x6c4 is 0. The present gets the layer 0x10882d4c (server + 0x110).
- The patch binds the layer, sets the three fields under the lock, and calls the flush. The frame shows.
- A call of the damage function after the bind stopped the UI task. The flag at 0x1081ec54 was set, so the damage function called the bind again, and the bind waited for its own layer.

### The damage callback

The display registers 0x17ef98 at the start (0x17eeb0 loads it from the literal 0x17ef8c). A word hook on the literal replaces the callback. While Cover Flow shows, the hook ignores the damage of the firmware. The firmware continues to draw into the framebuffer, but it does not send the drawing to the LCD. The patch draws the full frame before each flush, so these drawings do not show.

If the Albums list is not visible (a new screen, for example Now Playing), the hook closes Cover Flow and calls the original. The new screen then shows.

## Input

### The dispatcher

0x13d524 (event, target) sends each event to the UI objects:

1. It gives the event to each object in a filter list (the object of 0x101800, + 0x2c), with vtable slot +0x34.
2. With a target, it gives the event to the target (slot +0x30).
3. Without a target, it starts at the focused object (0x101800 + 0x28) and gives the event to each object and its parents (slot +0x1c gives the parent), with slot +0x30, until an object returns not 0.
4. At the end, it deletes the event (event vtable slot +4).

A probe at the call `bx r2` at 0x13d628 recorded the chain in the Albums list:

| Object | Class (vtable) | Event method |
|---|---|---|
| The Albums list | 0x677290 | 0x23b704 |
| (parent) | 0x66a938 | 0x16cabc |
| (parent) | 0x66846c | 0x17e974 |
| The application | 0x66a510 | 0x1d3348 |

0x1d3348 sends the events of some types to handlers in maps. One of them is 0x1d81cc (vtable slot 0x6701f0). Its first argument is a different object (0x13e358a4 in the emulator), not the application object at RAM 0x1081da80. The idle function 0x1d813c needs the first argument of 0x1d81cc.

### The events

An event has 20 bytes (vtable 0x676974 for a key event):

| Offset | Content |
|---|---|
| +0x00 | Vtable. Slot +4 (0x222da8) deletes the event. Slot +0x14 (0x222d68) is the type check. |
| +0x04 | Type |
| +0x08, +0x0c | Data |
| +0x10 | Key events: bits 16–23 are the key code. Wheel events: bit 30 set, and the speed in the low bits. |

Event types (emulator). Measure the time with `USEC_TIMER` (0x60005010), not with the instruction count: the count stops while the iPod is idle, so an early probe gave "7 ms" for type 6.

| Type | Meaning | Notes |
|---|---|---|
| 4 | Key push | Goes through the chain from the focused list. |
| 5 | Key repeat | In menus, while a key is held. |
| 6 | Key held | 0.5 s after the push (emulated `USEC_TIMER`). Goes to the UI handler 0x1d81cc, not to the list. |
| 7 | Key release | Goes to the UI handler, not to the list. |
| 9 | Timer of the list | About every 0.1 s while a key is held. |
| 0xd | Frequent event to all lists | Approximately each 240 ms, also while the wheel does not move (emulator, 10 October 2026). `album-art` 2.5 uses it as a tick. Not used by Cover Flow. |
| 0xf | Wheel (vtable 0x677aec) | +0x0c is the count of wheel ticks since the last event (+ or −), 0 at the end of a movement. In the emulator it was always +1 or −1. On the real iPod, the firmware adds the ticks while the UI task is busy (refer to [Version 0.6.7](#version-067-the-wheel-ticks-and-a-faster-frame-27-october-2026)). |
| 0x10 | Wheel scroll in a menu | In the menu lists, not in the Albums list. |
| 0x19 | Property change | +0x08 is the tag. "LstS" (0x4c737453): the list +0x0c has the selected row +0x14. |
| 0x1b | Screen change | |

Key codes (bits 16–23 of +0x10):

| Key | Code |
|---|---|
| Select | 0x6f |
| Menu | 0x6e |
| Play/Pause | 0x10 |

The table in [../docs/firmware-functions.md](../docs/firmware-functions.md) says that 0x1d8570 is the timer of key 0x6e, "a long push of Play". The emulator gives 0x6e for the button `menu`. This is an open question: either the emulator names the buttons differently, or the note on 0x1d8570 is not correct. A test on the real iPod can answer it.

### The browse list class 0x677290

| Slot | Address | Function |
|---|---|---|
| +0x30 (0x6772c0) | 0x23b704 | Event method |
| +0x138 (0x6773c8) | 0x23a04c | Sets the selection and posts "LstS" |
| +0x14c (0x6773dc) | 0x23a064 | Sets the selection (list, row, tag, animate) |

Fields of a list object (word index):

| Index | Content |
|---|---|
| [8] | View flags. (flags & 0x1800) == 0x800 if the list is visible. |
| u16 at +0x1c | The element ID of the list. Albums: 0x6382. Artists: 0x6387. |
| [0x29] | An object. Its word at +0x14 is the selected row. |
| [0x2d] | The first row (0) |
| [0x2e] | The number of rows. The Albums list has "All" and one row for each album. |

The firmware makes all the browse lists at the start. The emulator recorded lists with the element IDs 0x6381 to 0x6399.

### The firmware acts at the push

The firmware opens the album at the push of Select (type 4), not at the release. The UI handler 0x1d81cc gets each push first, then the focused list gets it. Thus the patch keeps the push of Select in the Albums list:

- When the UI handler gets the hold event (type 6, after 0.5 s), the patch opens Cover Flow.
- If the list gets an event 0.7 s after the push (usually the type-9 timer) and no type 6 came, the patch also opens Cover Flow.
- If the release comes first, the patch sends a copy of the push with the dispatcher. The copy has its own vtable, a copy of 0x676974 with an empty slot +4, so the dispatcher does not delete it. The UI handler had the original push, so the hook skips the copy there. Then the release goes to the UI handler as usual.
- While the patch sends a copy, its hooks do not keep the copy again.

The firmware acts on Menu at type 6 or 7 in the UI handler. After Cover Flow uses a push (Select to open, Menu to close), the patch takes the types 5, 6 and 7 of that key at its hook on 0x1d81cc until the release. At the release, it decreases the count of keys down (UI object + 0x44), as 0x1d820c does.

In the emulator, the command `press` holds a button for 120 ms of host time. This is more than 0.5 s of emulated time, so the iPod gets a held key. A held Menu goes to the main menu. Use `hold NAME 10` for a short push.

## The album order

The Albums list of RetailOS 1.3 is in the order of the album name ([album-artist.md](album-artist.md)). With a database from iTunes, Finder or libgpod, the firmware probably uses the sorted track list of mhod 52 (album, sort type 4) in the master playlist. The app makes the order in the same way:

1. If the master playlist has mhod 52 with sort type 4 and an entry for each track, the albums come in the sequence of their first track in that list.
2. If not, the album names are sorted alphabetically, with no difference for case and accents.

A track without an album name is not in the order. This is not tested on a real iPod.

## Emulator tests (8 October 2026)

The test library has 6 albums, "Test Album 1" to "Test Album 6". The first test file had one coloured cover for each album. The later tests used the file that `MusicImport.writeCoverFlow` made from the test library (`testWriteCoverFlow` with `IPODFW_COVERFLOW_VOLUME`).

| Test | Result |
|---|---|
| Hold Select on "Test Album 2" | After 0.72 s (emulated `USEC_TIMER`), Cover Flow opened with the green cover (album 2) at the centre. |
| Wheel, one gesture | Moved two covers (two wheel events of +1). |
| Wheel to the start and past the end | Stopped at album 1 and at album 6. |
| Draw | Slanted side covers, reflections and the caption bars showed. |
| Menu, before the fix | Closed Cover Flow, but the type-6 event of the same push then went back two levels. |
| Menu, after the fix | Closed Cover Flow. The Albums list stayed. |
| Menu, close with the framebuffer copy only | The list showed no highlighted row. With the new draw of the top view (0x21ac04), the highlight is correct. |
| Hold of Select, with type 6 | Cover Flow opened at the type-6 event, 0.506 s after the push. |
| Short push of Select (`hold select 10`) | Released after 0.3 s. The copy of the push opened "All Songs", as without the patch. |
| Short push of Menu (`hold menu 10`) | Went back one level, as without the patch. |
| Cover file from `MusicImport.writeCoverFlow` | The 6 placeholder covers and the captions ("Test Album 1", "Test Artist 1") showed. |

## Real iPod test (8 October 2026)

The owner flashed version 0.1 with the dark theme, the Dark Mode switch, `album-art` and `flash-wake-on-input`. The cover file had 326 albums (12.3 MB). A hold of Select opened Cover Flow, the wheel moved the covers, and Menu went back to the Albums list. Cover Flow also operated with Dark Mode on. Thus the display path (bind, update, flush) and the key codes are the same on the real hardware.

## Version 0.2

- Select opens the centre album. The patch sets the selected row with the list method +0x138 (0x23a04c), closes Cover Flow and gives the push to the original list method.
- The background follows the theme. The patch examines the left margin of the list rows in the copy of the screen.

The emulator runs at approximately ¼ of the real speed. Each frame takes a long time there.

## Version 0.3: the click

In the stock Albums list, each row of scroll called the piezo tone `0xcd430(0x55, 3000)` from 0x1b91fc (emulator, `IPODFW_REGS_AT=0xcd430`: two rows, two calls). The click function of the firmware is 0xa69dc (no arguments):

- It reads the Clicker setting at RAM 0x1081d9c4.
- If the setting has bit 1 (speaker) only, it sends a piezo message to the queue 0x15 (0xa6770).
- If the setting has bit 2 (headphones), it continues at 0x1b9168, which plays the click on the audio path. If the byte at 0x10882440 + 0x3e has bit 0, it also plays the piezo tone.
- If the setting is off, it does nothing.

Cover Flow calls 0xa69dc once for each cover step. Emulator: two steps, two calls. The emulator has no audio.

## Research: the built-in artwork (8 October 2026)

The aim is to show the covers that iTunes or Finder put on the iPod (`iPod_Control/Artwork/ArtworkDB`, `F1028_1.ithmb` 100 × 100, `F1029_1.ithmb` 200 × 200), without the file `iPodFirmCoverFlow`.

| Address | Finding | Evidence |
|---|---|---|
| 0xa1ff0 | Opens `iPod_Control\Artwork\ArtworkDB` (strings at 0xa2108, 0xa211c, 0xa2124). Called by the music database load 0xb4a64. Keeps the open file at db + 0xd2c and db + 0xd14. | Static |
| 0x205cfc | Starts the task `ArtworkLoadTask` (string 0x2aa7fc). The task function is 0x205db4. | Static |
| 0x205db4 | The artwork load task. It takes requests from a queue (task + 0x50), keeps an image cache (task + 0x8c), and makes reference-counted image objects. | Static |
| 0x88094 | Writes `Thumbs\F%d_%d.ithmb`. This is the Photos database, not the music artwork. | Static |
| 0xd7888 | Track parser. It stores the dbid of the track (mhit + 0x70) at track + 0x108 and + 0x10c, and the byte mhit + 0xa5 in bit 1 of track + 0x8b. It does not use mhit + 0x160. Correction: mhit + 0xa5 is not the artwork flag. The artwork flag is mhit + 0xa4 (libgpod), and the emulator library sets only that byte. The patch therefore does not use track + 0x8b. | Static, Emulator |

Conclusions:

- The firmware finds the artwork of a track by its dbid. Each mhii in ArtworkDB has the dbid of its song at + 0x14.
- The firmware loader is asynchronous (a task, a queue, a cache). A patch cannot call it in the time of one frame.
- A patch can read ArtworkDB and `F1028_1.ithmb` itself with the file functions. It needs the dbid of one track of each album from the RAM database.

### The RAM database (emulator, FolderLibrary: 1000 tracks, 138 albums, no mhod 52)

| Item | Finding | Evidence |
|---|---|---|
| Provider | RAM 0x1081da18 points to the main provider (class 0x670f54). Provider + 0x1c is the library object (0x13e27a78 in the emulator). Its event method 0x1e804c answers the properties of the music screens. | Emulator, Static |
| Library | 0x9bc6c resolves a library reference (byte 1: itself; byte 2: + 0xc9c). Library + 0xcf0 is the list of all tracks. Library + 0xcf8 is the database. | Static (0x9cb7c) |
| Database | + 0x1c: track count (1000). + 0x20: the track array (each 0x110 bytes; track + 0 is the database, track + 4 the next track). | Emulator |
| String pools | A pool (tag `strc`, for example db + 0x138 for the albums) has a handle at + 0x08 to 8-byte entries {offset, length}, a handle at + 0x10 to the text, and the count at + 0x14. The text is UTF-16. The album pool has one entry for each track, so each track has its own album string. | Static (0x885ec, 0x9eff8), Emulator |
| String copy | 0x9eff8(pool, index, buffer, &length, maximum) copies the UTF-16 text of an entry. The index starts at 1. | Static |
| Sorted tracks | 0x9c838(track list, sort, 0, i) gives the item at sorted position i. Item + 0x20 is the track. The track list keeps the sorted arrays at + 0x2fc + 4 × slot and builds a missing one with 0x1120bc. The count is u16 at (track list + 0x28) + 0x32. 0xeae38 converts some sort values. The slot for the album is 6 (0x10a15c(4)). | Static |
| Counts | The provider keeps the row count of each browse list at + 0xc0 … + 0xdc (0x254bcc …). For the Albums list (0x6382) it gives `VMax` from provider + 0xc4. | Static |
| Albums order | The firmware order is not a plain sort: "(III)", "<I°_°I>", "1:15 - Single", "10,000 gecs", "2019", "A Brief …". Punctuation comes before digits. The order of `CoverFlowFile.albumOrder` is different for such names. | Emulator (screen) |

### Text

The label draw 0x244924 calls 0x2438bc(view, gc = view + 0x74, …, text, …, colour, …). That function measures the text with 0x2115a4(gc, text, width) and draws it with 0x2106ec or 0x2113c0(gc, text, …, rect, …). The text is UTF-8. The font comes from the graphics context, and 0x21a27c sets the origin and the clip of the context for one view.

### The album list of the library (version 0.4)

The library object has the list that the Albums screen shows. 0x9c9fc gives the name of row i: `0x9eff8(db + 0x138, (library + 0xc60)[i], …)`, with the count at library + 0xc6c. Emulator: library + 0xc60 = 0x13b75e84, library + 0xc6c = 138 for the FolderLibrary. The patch read the first 8 names: "(III)", "<I°_°I>", "1:15 - Single", "10,000 gecs", "2019", "A Brief Inquiry Into On…", "After Laughter", "Ai Need Your Love - Sin…". This is the order of the screen. Thus the patch does not sort. The sorted track lists (0x9c838, slot 6) are not necessary, and library + 0xcf0 was 0 in the Albums screen.

The artist list (library + 0xc48, + 0xc50) and the composer list (+ 0xc54, + 0xc5c) are filled only when their screens open.

### The caption with the firmware font (version 0.4)

The template cell of the Albums list (list word 0x2a, class 0x66b4dc) has two children: the album label (element 0x6421, vtable 0x677920) and the ">" picture (0x5ecc). For each caption line, the patch:

1. attaches the album label to the top view (view + 0x10) and sets its rectangle (view + 0x58) to the line;
2. calls the label draw 0x244924 with the UTF-8 text;
3. puts back the parent, the rectangle, the flags and the byte at + 0x1b8.

Results:

- The text has the font and the colour of the list rows (also with the dark theme, because the colours come from the theme).
- The alignment flags (view + 0x20, bits 0x8000000 and 0x1000000) had no effect in this draw path, and a grey copy of the colour (view + 0xc8 + 8) was not used. The patch therefore moves the text pixels to the centre itself and mixes the artist line halfway to the background.

### Version 0.4 in the emulator

With the FolderLibrary (no cover file): the real covers, the album names and the artists showed, in the order of the Albums list. The first open made the table in 35 ms of emulated time. The read window (32 KB) reduces the count of reads of ArtworkDB on the real disk.

Open items:

1. A test on the real iPod with a database and artwork from Finder (format 1028 must be present).
2. The time of the first open on the real iPod with a large library.

## Version 0.5: the 200 × 200 artwork

The owner saw steps in the covers, but smooth artwork in Now Playing. Version 0.4 read the 100 × 100 image (format 1028) and enlarged it to 128 × 128 with the nearest texel. Now Playing uses the 200 × 200 image (format 1029).

Version 0.5 reads format 1029 (else 1028) and makes a 128 × 128 texture one time, when the cover enters the cache. Emulator times (FolderLibrary, `USEC_TIMER` marks):

| Step | Time |
|---|---|
| Read 80 KB from `F1029_1.ithmb` | 9.3–10.0 ms |
| Bilinear filter 200 → 128 (first version) | 15.7 ms |
| 2 × 2 average in packed RGB565 (`((a ^ b) & 0xf7de) >> 1) + (a & b)`) | 7.1 ms |
| First frame at the open, 5 covers, bilinear | 144 ms |

The frame draw does not change: its time depends on the screen pixels, not on the source size.

## How other Cover Flow programs do it

Rockbox PictureFlow (`apps/plugins/pictureflow/pictureflow.c`, read on 9 October 2026):

- It prepares each slide one time: it scales the album art (with the aspect ratio), adds the reflection, and keeps the result in a disk cache (`.pfraw` files, name from a hash of the album and the artist). It builds the cache at the first start.
- At run time, a background thread loads the slides into a RAM cache of 64 slides (LRU). An empty slide shows while a slide loads, so the wheel never waits.
- The draw is column by column, with a perspective projection in fixed point (`PFREAL_SHIFT` 10), a sine table and a tilt of 70°. Side slides fade with an alpha table. The reflection fades with a table.

Possible next steps for this patch, from this list: load the covers in the background (a firmware task, for example as `ArtworkLoadTask` 0x205cfc does), and show the grey square until a cover is ready.

## Version 0.6: a smooth animation

The owner found the scroll slow. Emulator times of one frame of version 0.5: clear 2 ms, covers 10–15 ms (about 30 ms with a cover load), caption 5.8 ms, send 0.2–1 ms. Each wheel step drew up to 4 frames in the event handler, so the next wheel events waited.

Version 0.6:

- A wheel event only sets the target and clicks. The timer of the list (list + 0xcc, functions 0x151c98, 0x151c24, 0x151694) draws the frames. Its events are type 9 with the timer in event word 2 (0x23b704 compares it with list + 0xcc).
- Each tick moves 5/8 of the remaining distance (at least 20/256 of a cover). The timer starts before the draw, so the frames follow each other.
- The caption is drawn one time for each centre album and copied.
- At most one cover load for each frame. A cover outside the screen is not loaded. When the movement stops, the ticks load the covers at centre ± 4.
- 0x23b704 handles a timer event of its own timer with the count at list + 0xf8 (the blink of the selected row; refer to [album-art-v2.md](album-art-v2.md), "Version 2.6"). With a count of 0 it would count down from 255 and repeat the key action. The patch swallows such an event after the close.

Emulator times of version 0.6: 18–19 ms for each frame without a cover load (about 53 frames each second), about 40 ms with a load. A single step took 5 frames.

## Version 0.6.1: a chain on the list event (10 October 2026)

`album-art` 2.4 also hooks the event method of the browse list (0x6772c0) for its late fill. Two hooks on one word need `chain` ([../docs/patch-system.md](../docs/patch-system.md#hook-chains)). Version 0.6.1 gives its hook `"chain": "list_event"`. The code does not change: the patcher gives the symbol `list_event` the previous target. Without `album-art`, this target is 0x23b704. With `album-art`, it is the hook of `album-art` (the build applies the patches sorted by name).

Emulator test with `album-art` 2.4: a hold of Select opened Cover Flow, the wheel moved the covers, and Menu went back to the Albums list. Refer to [album-art-v2.md](album-art-v2.md), "Version 2.4".

## Version 0.6.2: the stray tick (13 October 2026)

The timer at list + 0xcc is the blink of the selected row, not a key repeat ([album-art-v2.md](album-art-v2.md), "Version 2.6"). `album-art` 2.6 also uses it as its tick. Thus version 0.6.2 takes a timer event of the list only in the first 0.3 s after the close (`STRAY_TICK_US`), and also if the count at list + 0xf8 is not 0. Before, it took each timer event with the count 0, at any time.

Emulator test with `album-art` 2.6: hold of Select, wheel and Menu operated. After Menu, the selected row of the Albums list was "All" (the same as with version 0.6.1).

## Version 0.6.3: the covers at the open (16 October 2026)

The owner reported a problem with version 0.6.2. At the open, the selected album and the covers next to it showed grey squares. The farther covers showed their artwork. The grey squares changed only after a wheel turn.

The code had two causes:

1. Each frame loads at most one new cover. The draw loop goes from the farthest cover to the centre, so the load went to a far cover first.
2. The open drew one frame and did not start the timer. Thus no tick loaded the other covers until a wheel step started the animation.

Version 0.6.3 makes these changes:

1. Before the draw loop, `render` loads the covers in the order of their distance from the centre: the centre, then centre ± 1, ± 2 and so on. Then the draw loop uses the cache.
2. The first frame loads up to 3 covers (`OPEN_LOADS`): the centre and its two neighbours.
3. If a visible cover is not loaded after the first frame, the open starts the animation timer. Each tick loads one more cover. When all the visible covers are loaded, `preload` continues as before.

The code and data are 10888 bytes (`testPatchSizes`). Not tested in the emulator or on the real iPod yet.

## Version 0.6.5: the debug log (27 October 2026)

### The symptom

The owner restored the iPod with iTunes. Then the owner flashed the firmware again with the fix for the missing `hibe` entry ([hibernation-restore.md](hibernation-restore.md)). After this, Cover Flow became very slow:

- The open takes several seconds.
- The frame rate is very low.
- One album step needs approximately two full turns of the click wheel.

The code of Cover Flow did not change between the two states (version 0.6.4). Thus the cause is in the state of the iPod or in the build, not in the patch code.

### Possible causes

| Cause | What the log shows |
|---|---|
| A cover load fails each time (the file open or the read). `cover` then keeps no cover in the cache, and `preload` tries the same cover again at each tick (15 ms). The timer never stops. | `X open failed` or `X read failed` lines. A high `idle` and `preloads` count in the `T` line. `openfail` or `readfail` in the `L` line. |
| The new ArtworkDB from the sync after the restore has no format 1029 or 1028, or other file numbers. | `artdb`, `large`, `small`, `none` and `files` in the `A` line. |
| A larger library after the new sync. The album table takes long. | `albums`, `tracks`, `build` and `art` in the `A` line. |
| The CPU runs slower, or the patch code runs from slow memory. | `cal` in the `M` line and in the `C` line. Compare with the value of an iPod that operates correctly. |
| The display waits for the end of the last update. | `bind` and `snd` in the `F` lines. |
| The wheel events come less often, or with other values. | The `W` lines (raw event words) and the `W` summary. |
| The timer events come late. | `gapmax` and `late` in the `T` line. |

### How the log operates

1. "Start the Cover Flow Log" in the app writes a file of 16384 zero bytes to `iPod_Control/iTunes/iPodFirmCoverFlowLog`.
2. The patch keeps the lines in RAM (16 KB from the allocator, at the first line).
3. At the first push of a button 1 s after the close, `hook_ui_event` writes the full buffer into the file (`log_write`).
4. `log_write` first opens the file with the read-only open 0x8f38c. If the file does not exist, the patch writes nothing. The reason: [firmware-functions.md](../docs/firmware-functions.md) says that 0x8f3f8 makes a missing file.
5. "Show Cover Flow Log" in the app shows the text up to the first zero byte.

The log does not change what Cover Flow does. It adds approximately 10 ms at each open and at each close (`calibrate`).

### The lines of the log

All times are in microseconds (`USEC_TIMER`).

| Line | Content |
|---|---|
| `CF01` | The header: the count of opens, of lost lines and of file writes. |
| `O` | One open: how the open started (`hold`, `release`, `list`), the time from the push of Select, the time of the read of `iPodFirmHoldSelect`, and the result and the time of the last file write (2: no file). |
| `A` | The album table: the albums, the tracks, the time of `build_albums` and of `find_artwork`, `rebuilt` (1: a new table), the result of the ArtworkDB read (0: correct; −1 no track found or no memory, −2 no file, −3 no `mhfd`), the `mhii` count, the count of 32 KB reads, the albums with format 1029 (`large`), with 1028 only (`small`) and with no artwork (`none`), and the bit masks of the `.ithmb` file numbers (1029/1028). |
| `M` | Memory: the address of `render`, of the framebuffer, of the screen copy, of the cover cache and of the log. `copy`: the time of the 153600-byte screen copy. `cal`: the time of 100000 empty loops. |
| `R` | The rows of the list, the selected row, the first target and the time of the full open. |
| `F` | One frame: the time since the last frame, the total, `clr` (clear), `ld` (cover loads), `drw` (draw), `cap` (caption), `snd` (send), `bind` (the wait in 0x164878), `pos` and `tgt`. The first 20 frames of each open, and up to 20 frames that take 60 ms or more. |
| `W` (with a number) | One wheel event: the time since the open, the event words 2, 3 and 4, the target, the position and `animating`. The first 32 events of each open. |
| `X` | A failure: no layer, no memory, a failed file open or read of a cover (the first 4 of each kind). |
| `C` | The close: `why` (1 Menu or Select, 0 a new screen), the duration, the frames, the average and the maximum frame time, the average of each part, and `cal` again. |
| `L` | The cover loads: the count, the failures, the album loads with no artwork, and the average and maximum time of the open, the read and the scale. |
| `T` | The timer ticks: the count, the longest gap, the gaps of 50 ms or more, the ticks with no movement, the preloads and `animating` at the close. |
| `W` (summary) | The wheel events: the count, +1, −1, 0, other values, the steps of the target, the last target and the album count. |
| `E` | The events that the list got while Cover Flow showed, by type. |

The code and data are 15712 bytes (`testPatchSizes`). The owner tested it on the real iPod on 27 October 2026 (the next section).

### The first log from the real iPod (27 October 2026)

The owner sent the log of version 0.6.5: one open, 41 frames, 20 wheel events, 334 albums, 5201 tracks. The values below come from this log.

| Item | Value |
|---|---|
| Open of `F1029_1.ithmb` (`cover`, 25 loads) | 1125530 µs on average, 1138129 µs maximum |
| Read of one 200 × 200 cover (80000 bytes) | 17196 µs on average |
| Scale of one cover | 12090 µs on average |
| `build_albums` (first open) | 573067 µs, of which `find_artwork` 363514 µs (95 reads of 32 KB) |
| The first frame (3 cover loads) | 3581400 µs |
| A frame with no cover load | approximately 69000 µs: clear 6000, draw 44000, caption 3100, send 15800 |
| `cal` (100000 empty loops) | 5048 µs at the open, 5101 µs at the close |
| Wheel events | 20, with word 3 from 1 to 248. 19 events had a value larger than 1. |

The iPod disk is HFS+ (allocation block 16384 bytes). After the restore, the sync wrote one image for each track: `F1029_1.ithmb` is 416080000 bytes (5201 × 80000), and ArtworkDB has 5201 `mhii`. The firmware open of this file takes 1.1 s. The open of the small ArtworkDB is fast. The cause of the slow open in the firmware is not known.

The results:

1. Each cover load opened the file again. Thus each cover load took 1.2 s. During a load, the UI task did not get events.
2. While the UI task was busy, the firmware added the wheel steps into one event: word 3 is the count of steps. The patch moved one album for each event. Thus approximately two turns of the wheel gave one album.
3. `cal` did not change, so the CPU speed is correct. No cover load failed. `preload` did not run without a stop.
4. The hibernation fix did not cause the problem. The new artwork file did.

## Version 0.6.6: the artwork file stays open (27 October 2026)

`art_open` opens the `.ithmb` file at the first cover load and keeps the handle (`art_fh`) while Cover Flow shows. A cover of another file closes the old file and opens the new file. A failed read closes the file, so the next load opens it again. `release` closes the file at the close of Cover Flow. Thus each open of Cover Flow opens the file one time. The `L` line of the log now also gives `files`: the count of file opens.

The wheel code does not change. When the UI task is not busy, each wheel event must have word 3 = ±1. The next log will show if this is correct.

The open of Cover Flow still takes approximately 1.1 s for the first cover, and a frame with no load still takes approximately 69 ms. Possible later improvements: keep the file open between two opens, and make the draw faster.

The code and data are 15920 bytes (`testPatchSizes`). The owner tested it on the real iPod on 27 October 2026 (the next section).

### The log of version 0.6.6 (27 October 2026)

The owner sent the log of version 0.6.6: two opens, 334 albums.

| Item | Value |
|---|---|
| File opens of `F1029_1.ithmb` | 1 for each open of Cover Flow (`files=1`), 1141212–1142027 µs |
| A cover load after the open | approximately 30000 µs: read 16800, scale 12200 |
| The first frame | 1309982 µs and 1318405 µs (the file open is in it) |
| A frame with no cover load | approximately 69000 µs: clear 6000, draw 44000, caption 3100 (a copy), send 15800 |
| A frame that draws a new caption | 15000–33000 µs more |
| Wheel events while the wheel turns | one each 100–130 ms, word 3 from 1 to 21 |

The file stays open, so the long wait is now only at the open. Two problems stay:

1. **Word 3 of the wheel event counts ticks.** The low byte of word 4 increases by about 2.7 for each unit of word 3, for example 0x5a → 0x65 for word 3 = −4 and 0x90 → 0xad for −11. Thus word 3 is the count of wheel ticks since the last event, approximately 96 for each turn. While a frame draws, the firmware adds the ticks into one event. Version 0.6.6 moved one album for each event.
2. **The draw is slow.** The textures were in rows (y × 128 + x), and `draw_cover` reads one column at a time. Thus each read went 256 bytes farther. A texture is 32 KB, and the cache is smaller. The real-iPod test of `usb-host-probe` shows that the 0x1xxxxxxx window is in the cache ([usb-host.md](usb-host.md)), so the memory is not uncached. The cache misses are the probable cause.

## Version 0.6.7: the wheel ticks and a faster frame (27 October 2026)

1. **Wheel.** The patch adds word 3 of each wheel event to `wheel_ticks`. Each `WHEEL_TICKS` (6) ticks give one album step, thus approximately 16 albums for each turn. A change of direction or word 3 = 0 sets the count to 0. `step(n)` moves the target `n` albums and gives one click.
2. **Textures in columns.** `scale_cover` writes the texture as x × 128 + y. `draw_cover` reads a column in sequence.
3. **The caption.** `render` draws a new caption only when the centre album is the target (the covers stopped there). While the covers move, the last caption stays on the screen. The 26880-byte caption copy is not necessary now.
4. **Fewer rows.** After the first frame, `render` clears and sends only the rows `COVER_TOP` (36) to `ALBUM_TOP` (198), and the caption rows only when the caption changes. `send_screen` gives these rows to the display server (server + 0x6c0 and + 0x6c2).

The value 6 for `WHEEL_TICKS` is an estimate. Change it if the owner wants a faster or a slower scroll.

The code and data are 16012 bytes (`testPatchSizes`). The owner tested it on the real iPod on 27 October 2026 (the next section).

### The log of version 0.6.7 (27 October 2026)

The owner tested version 0.6.7 on the real iPod and reported: "it feels great, very fast". The log had two opens.

| Item | Value |
|---|---|
| Wheel | 187 events gave 290 album steps (first open) |
| A frame with a cover load | approximately 80 ms: clear 3600, load 31000 (read 16200, scale 14800), draw 32500, send 11000 |
| A frame with no cover load | approximately 61000–70000 µs |
| Draw (`drw`) | 32000 µs (version 0.6.6: 44000 µs) |
| Send (`snd`) | 10800–13400 µs (version 0.6.6: 15800 µs) |
| The open | 1.3 s (the file open: 1.1 s) |

Open items for a later version, if the owner wants a higher frame rate:

1. **The draw.** The clear writes 4-byte words in sequence at approximately 70 ns each. The draw writes approximately 84000 pixels, one column at a time, at approximately 380 ns each. A draw in strips of 8 columns, row by row, can put the writes in sequence.
2. **The caption.** The caption still changes during a scroll, when the centre album is equal to the target for one frame (12–29 ms). A condition `pos == target * 256` draws it only at a full stop.
3. **The open.** The file open takes 1.1 s at each open of Cover Flow.

## Version 0.6.8: the debug log is removed (27 October 2026)

The owner asked to remove the debug log. Version 0.6.8 has the code of version 0.6.7 without the log:

- The patch does not measure and does not write a file. The firmware functions 0x8f3f8, 0x8f6f4, 0x7b240 and 0x7b114 are not in `symbols` now.
- `patch.json` has no `ui` object now: no "Start the Cover Flow Log" action, no steps and no tool.
- The app does not have the tool `cover-flow-log` now (`PatchSpec.knownTools`, `PatchTools.swift`, `AppModel.readCoverFlowLog`).

The code and data are 11384 bytes (`testPatchSizes`). Not tested on the real iPod yet.

## How to add the debug log again

Use the log to measure Cover Flow on the real iPod, for example after a change of the draw or after a new sync. The log of versions 0.6.5 to 0.6.7 found the slow file open and the wheel ticks. The format of the lines is in [The lines of the log](#the-lines-of-the-log).

CAUTION: Increase the `version` and measure the `size` again after you add the log. The log adds approximately 4.6 KB of code and data, and 16 KB from the allocator.

### Step 1: the code of the log

1. Add the declarations below to the firmware functions at the start of `cover_flow.c`.
2. Put the log section below after `read_at`, before "the albums and their artwork". The section uses `udiv`, `open_path`, `pos`, `target`, `count` and `animating`, so it must come after them.

```c
int file_open_rw(void *path_record, void *fh, unsigned buffer, unsigned mode);
int file_write(void *fh, unsigned *len, const void *buf);
int fw_snprintf(char *buf, unsigned size, const char *fmt, ...);
int fw_vsnprintf(char *buf, unsigned size, const char *fmt, __builtin_va_list args);
```

```c
/* ---------- the debug log ---------- */

#define LOG_PATH       "iPod_Control\\iTunes\\iPodFirmCoverFlowLog"
#define LOG_BYTES      16384              /* the size of the file (PatchTools.swift reads it) */
#define LOG_HEADER     64                 /* the first line: "CF01 ..." */
#define LOG_LINE       160                /* the longest line */
#define LOG_FRAMES     20                 /* the first frames of each open get one line each */
#define LOG_SLOW_US    60000              /* a later frame that takes this long also gets a line */
#define LOG_SLOW_LINES 20
#define LOG_WHEELS     32                 /* the first wheel events of each open get one line each */
#define LOG_WRITE_US   1000000            /* the write comes at the first push this long after the close */
#define LOG_LATE_US    50000              /* a tick of the timer this long after the last one is late */

static char *log_text;
static unsigned log_used, log_lost, log_opens, log_writes, log_write_us;
static int log_result = 1;                /* the result of the last write; 1: no write yet */
static int log_pending;                   /* 1: lines that are not in the file yet */

/* The measurements of one open. All times are in microseconds. */
static struct {
    unsigned start, last_frame, frames, slow_lines, frame_max;
    unsigned sum_frame, sum_clear, sum_load, sum_draw, sum_caption, sum_send, sum_bind;
    unsigned frame_load, frame_bind;      /* the load time and the bind time of this frame */
    unsigned file_opens, loads, open_fail, read_fail, no_art, open_sum, open_max, read_sum, read_max, scale_sum, scale_max;
    unsigned ticks, last_tick, tick_gap_max, late_ticks, idle_ticks, preloads;
    unsigned wheels, wheel_plus, wheel_minus, wheel_zero, wheel_big, steps;
    unsigned events[16], other_events;
} st;

/* The measurements of the album table (build_albums) and of the push (the hooks). */
static unsigned build_us, art_us, rebuilt, mhii_count, db_reads, art_large, art_small, art_none;
static unsigned files_large, files_small; /* bit N: the album table uses F1029_N or F1028_N */
static int art_status;                    /* 0: ArtworkDB read; < 0: the step that failed */
static unsigned hold_us, push_to_open;
static const char *open_how = "?";       /* hold: the hold event; release; list: a later list event */

COLD static int log_ready(void)
{
    if (log_text)
        return 1;
    if (!(log_text = fw_alloc(LOG_BYTES)))
        return 0;
    fw_memset0(log_text, LOG_BYTES);
    log_used = LOG_HEADER;
    return 1;
}

/* Adds one line. A full log loses the line and counts it. */
COLD static void log_printf(const char *fmt, ...)
{
    __builtin_va_list ap;
    int n;
    if (!log_ready() || log_used + LOG_LINE + 1 > LOG_BYTES) {
        log_lost++;
        return;
    }
    __builtin_va_start(ap, fmt);
    n = fw_vsnprintf(log_text + log_used, LOG_LINE, fmt, ap);
    __builtin_va_end(ap);
    if (n < 0)
        n = 0;
    if (n > LOG_LINE - 1)
        n = LOG_LINE - 1;
    log_used += n;
    log_text[log_used++] = '\n';
    log_pending = 1;
}

/* The time of a loop with a fixed count of instructions: it shows the speed of the CPU and of the
 * memory of the patch code. Not small code: the loop must be the same in each version. */
__attribute__((noinline)) static unsigned calibrate(void)
{
    unsigned t = USEC_TIMER, i;
    for (i = 0; i < 100000; i++)
        __asm__ volatile("");
    return USEC_TIMER - t;
}

COLD static unsigned average(unsigned sum, unsigned n)
{
    return n ? udiv(sum, n) : 0;
}

/* Writes the lines into the file LOG_PATH, if the file exists. Only the UI task calls it. */
COLD static void log_write(void)
{
    unsigned path[0x108 / 4], fh[0x30 / 4], len = LOG_BYTES, t = USEC_TIMER;
    int n, err, err2;
    log_pending = 0;
    if (!log_text)
        return;
    n = fw_snprintf(log_text, LOG_HEADER, "CF01 cover-flow 0.6.7 opens=%u lost=%u writes=%u",
                    log_opens, log_lost, log_writes + 1);
    if (n < 0)
        n = 0;
    for (; n < LOG_HEADER - 1; n++)
        log_text[n] = ' ';
    log_text[LOG_HEADER - 1] = '\n';
    /* The reference says that 0x8f3f8 makes a missing file. Thus the read-only open makes sure
       first that the owner started the log. */
    if (open_path(fh, LOG_PATH, 0) != 0) {
        log_result = 2;                   /* 2: no file, the log is off */
        log_write_us = USEC_TIMER - t;
        return;
    }
    file_close(fh);
    fw_memset0(path, sizeof path);
    fw_strcpy((char *)path + 4, LOG_PATH);
    fw_memset0(fh, sizeof fh);
    err = file_open_rw(path, fh, 0x1000, MODE_DATA);
    if (err == 0) {
        err = file_seek(fh, 0, 0);
        if (err == 0)
            err = file_write(fh, &len, log_text);
        err2 = file_close(fh);
        if (err == 0)
            err = err2;
        log_writes++;
    }
    log_result = err;
    log_write_us = USEC_TIMER - t;
}

/* One line for each of the first frames of an open, and for each slow frame after them. */
COLD static void log_frame(unsigned t0, unsigned t1, unsigned t2, unsigned t3, unsigned t4)
{
    unsigned total = t4 - t0, gap = t0 - (st.frames ? st.last_frame : st.start);
    unsigned draw = t2 - t1 - st.frame_load;
    st.frames++;
    st.last_frame = t0;
    st.sum_frame += total;
    st.sum_clear += t1 - t0;
    st.sum_load += st.frame_load;
    st.sum_draw += draw;
    st.sum_caption += t3 - t2;
    st.sum_send += t4 - t3;
    st.sum_bind += st.frame_bind;
    if (total > st.frame_max)
        st.frame_max = total;
    if (st.frames <= LOG_FRAMES || (total >= LOG_SLOW_US && st.slow_lines++ < LOG_SLOW_LINES))
        log_printf("F%u +%u tot=%u clr=%u ld=%u drw=%u cap=%u snd=%u bind=%u pos=%d tgt=%d",
                   st.frames, gap, total, t1 - t0, st.frame_load, draw, t3 - t2, t4 - t3,
                   st.frame_bind, pos, target);
}

/* The summary of one open. `why`: 1 Menu or Select, 0 the firmware showed a new screen. */
COLD static void log_close(int why)
{
    unsigned i, others = st.other_events;
    for (i = 0; i < 16; i++)
        if (i != 4 && i != 5 && i != 6 && i != 7 && i != 9 && i != 0xd && i != 0xf)
            others += st.events[i];
    log_printf("C%u why=%d dur=%u frames=%u avg=%u max=%u clr=%u ld=%u drw=%u cap=%u snd=%u bind=%u cal=%u",
               log_opens, why, USEC_TIMER - st.start, st.frames, average(st.sum_frame, st.frames), st.frame_max,
               average(st.sum_clear, st.frames), average(st.sum_load, st.frames), average(st.sum_draw, st.frames),
               average(st.sum_caption, st.frames), average(st.sum_send, st.frames), average(st.sum_bind, st.frames),
               calibrate());
    log_printf("L loads=%u files=%u openfail=%u readfail=%u noart=%u open=%u/%u read=%u/%u scale=%u/%u",
               st.loads, st.file_opens, st.open_fail, st.read_fail, st.no_art,
               average(st.open_sum, st.loads), st.open_max,
               average(st.read_sum, st.loads - st.open_fail), st.read_max,
               average(st.scale_sum, st.loads - st.open_fail - st.read_fail), st.scale_max);
    log_printf("T ticks=%u gapmax=%u late=%u idle=%u preloads=%u animating=%d",
               st.ticks, st.tick_gap_max, st.late_ticks, st.idle_ticks, st.preloads, animating);
    log_printf("W wheel=%u plus=%u minus=%u zero=%u big=%u steps=%u target=%d count=%u",
               st.wheels, st.wheel_plus, st.wheel_minus, st.wheel_zero, st.wheel_big, st.steps, target, count);
    log_printf("E key4=%u key5=%u key6=%u key7=%u timer9=%u d=%u wheel15=%u others=%u",
               st.events[4], st.events[5], st.events[6], st.events[7], st.events[9], st.events[0xd],
               st.events[0xf], others);
}

```

Notes on this code:

- `log_write` first opens the file with the read-only open. The reason: the reference says that 0x8f3f8 makes a missing file. Without the file, the log stays in RAM.
- The firmware `vsnprintf` 0x7b114 takes the `va_list` of clang for ARM directly. The formats `%u`, `%d`, `%x` and `%s` operate. Do not use `%c`: it is not tested.
- Change the version in the `CF01` header line of `log_write` to the new version.
- Do not use `/` with a variable in the log code. Use `udiv` or `average`. The patch has no division library.
- If `art_open` is in the code, add `unsigned file_opens` to `st` and count each real file open in `art_open`. The `L` line then gives `files=%u`.

### Step 2: the measurement points

Add these lines to the code. `t`, `t0` … `t3` are local `unsigned` values of `USEC_TIMER`.

| Function | What to add |
|---|---|
| `db_read` | `db_reads++` before each read of the window. |
| `find_artwork` | `art_status = -1` at the start, `-2` before the open of ArtworkDB, `-3` before the `mhfd` check, `0` after it. `mhii_count++` for each `mhii`. |
| `build_albums` | `rebuilt = 1` after the check "the same database". Measure `find_artwork` into `art_us` (set the counters to 0 first). After it, count `art_large`, `art_small` and `art_none`, and set the bits of `files_large` and `files_small` from `art_file`. |
| `send_screen` | Measure `display_bind` into `st.frame_bind`. |
| `cover` | `st.no_art++` for an album with no artwork. `st.loads++` for each load. Measure the open, the read and the scale (`open_sum`, `open_max`, `read_sum`, `read_max`, `scale_sum`, `scale_max`) and add the full load time to `st.frame_load`. Count `open_fail` and `read_fail`, and write an `X` line for the first 4 of each. |
| `render` | Set `st.frame_load = st.frame_bind = 0` at the start. Take `t0` before the clear, `t1` after it, `t2` after the draw loop, `t3` after the caption. Call `log_frame(t0, t1, t2, t3, USEC_TIMER)` after `send_screen`. |
| `open_cover_flow` | At the start: `fw_memset0(&st, sizeof st)`, `st.start = USEC_TIMER`, `log_opens++`, `push_to_open = st.start - push_time`, and the `O` line. An `X` line before each `return 0`. Measure `build_albums` into `build_us` (set `rebuilt = 0` first), then the `A` line. Measure the screen copy, call `calibrate`, then the `M` line. The `R` line after the first `render`. |
| `close_cover_flow` | `log_close(send)` before the screen copy goes back. |
| `tick` | `st.idle_ticks++` when the covers do not move. `st.preloads++` when `preload` loads a cover. |
| `step` | Add the count of album steps to `st.steps`. |
| `active_event` | Count each event type in `st.events`. For the tick of the timer: the gap to the last tick (`tick_gap_max`, `late_ticks` from `LOG_LATE_US`). For a wheel event: count +1, −1, 0 and other values, and write a `W` line for the first `LOG_WHEELS` events. |
| `hook_list_event` | Measure `hold_is_cover_flow` into `hold_us`. Set `open_how = "list"` before the open. |
| `hook_ui_event` | Set `open_how = "hold"` or `"release"` before the open. At the start, after `ui_object = ui`: `if (log_pending && !active && type == EV_KEY_DOWN && USEC_TIMER - closed_at >= LOG_WRITE_US) log_write();` |

Do not call `log_write` from `close_cover_flow` or from `hook_display_damage`. The file write must occur in the UI task, at a push of a button.

### Step 3: patch.json

1. Add the four firmware functions to `symbols`: `"file_open_rw": "0x08f3f8"`, `"file_write": "0x08f6f4"`, `"fw_snprintf": "0x07b240"`, `"fw_vsnprintf": "0x07b114"`.
2. Add a `ui` object with the action that makes the empty file, the procedure and the tool:

```json
"ui": {
  "actions": [
    {
      "title": "Start the Cover Flow Log",
      "write": [ { "path": "iPod_Control/iTunes/iPodFirmCoverFlowLog", "zeros": 16384 } ],
      "status": "The log is empty. The iPod writes the log at the first push of a button after Cover Flow closes."
    }
  ],
  "steps_title": "Debug Procedure",
  "steps": [
    "Flash a firmware with this version of Cover Flow.",
    "Click Start the Cover Flow Log.",
    "Click Eject iPod. Then disconnect the iPod.",
    "Go to Music > Albums. Hold the Select button to open Cover Flow.",
    "Turn the click wheel slowly through 5 albums. Then turn it quickly through 20 albums.",
    "Stop for 5 seconds. Then push Menu.",
    "Wait 2 seconds. Then push a button. The iPod writes the log.",
    "Wait 15 seconds, so that the firmware writes the log to the disk.",
    "Connect the iPod to the Mac and click Show Cover Flow Log.",
    "Click Copy Log and give the text to the developer."
  ],
  "tools": [ "cover-flow-log" ]
}
```

### Step 4: the tool in the app

1. Add `"cover-flow-log"` to `PatchSpec.knownTools` in `Patcher.swift`.
2. In `PatchTools.swift`, add `case "cover-flow-log": CoverFlowLogSection()` to `PatchTool`. Make `CoverFlowLogSection` as a copy of `USBLogSection`: a button "Show Cover Flow Log", a button "Copy Log" and a scroll view with the text in a monospaced font.
3. In `AppModel.swift`, add `@Published var coverFlowLog: String?` and `readCoverFlowLog()`. The function reads `iPod_Control/iTunes/iPodFirmCoverFlowLog` from `ipodMusicVolume()`, keeps the bytes up to the first zero byte, and decodes them as UTF-8.
4. In `runPatchAction`, set `coverFlowLog = nil` when an action writes the file of the log.
5. Add the file to the table of the files on the iPod in [app-and-device.md](../docs/app-and-device.md), and add the tool to the `tools` row in [patch-system.md](../docs/patch-system.md).
