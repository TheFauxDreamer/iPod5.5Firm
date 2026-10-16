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
| 0xf | Wheel (vtable 0x677aec) | +0x0c is +1 or −1 for each step, 0 at the end of a movement. |
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
