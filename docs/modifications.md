# The modifications

This document describes each change that iPodFirm can make to the firmware. For each change, it gives the user interface, the changed bytes, the hooks, the runtime logic, the limits and the test status.

All addresses are osos offsets for Apple firmware 1.3. Refer to [The address rule](README.md#the-address-rule). For the hook kinds and the linker, refer to [patch-system.md](patch-system.md).

## Summary

| Change | Type | Pane in iPodFirm | Hooks or bytes | Tested on a real iPod |
|---|---|---|---|---|
| [Picture replacement](#picture-replacement) | Resource data | Pictures | Pixel bytes of one BMap | Not recorded |
| [Text replacement](#text-replacement) | Resource data | Text | One Str area | Not recorded |
| [Software version](#software-version) | Code | Patches > Software Version | 2 instructions, or 1 function body | No |
| [backlight-60s](#backlight-60s) | Data patch | Patches | 16 byte runs and 21 strings | No |
| [album-art](#album-art) | Code patch (extended) | Patches | 2 vtable words and 1 `bl` | Version 1.0: yes. Version 2.1: installed, the scroll is slow |
| [sleep-now](#sleep-now) | Code patch | Patches | 1 vtable word and 2 `bl` | No |
| [flash-keep-awake](#flash-keep-awake) | Code patch | Patches | 4 `bl` | Partly (an earlier version) |
| [flash-wake-on-input](#flash-wake-on-input) | Code patch | Patches | 1 `bl` | No |
| [volume-unlimit](#volume-unlimit) | Data patch | Patches | 2 bytes | No |
| [something-comforting](#something-comforting) | Code patch (example) | Patches | 1 `b` and 2 vtable words (all with `chain`), a Settings menu | No |
| [album-artists](#album-artists) | Code patch | Patches | 6 `b`, 4 `bl` and 3 vtable words (4 with `chain`), 3 menus | Version 1.1: yes. Version 1.2: no |
| [instant-save](#instant-save) | Code patch | Patches | 1 `b` | No |
| [cover-flow](#cover-flow) | Code patch | Patches | 3 words (2 vtable slots and 1 literal) | No |
| [usb-host-probe](#usb-host-probe) | Code patch (test) | Patches | 8 `bl`, 2 `b` and 18 table words | Yes, as a test (2026-10-08) |
| [usb-audio-out](#usb-audio-out) | Code patch | Patches | 17 `bl`, 2 `b` and 4 words (3 with `chain`), a Settings menu | Yes (2026-10-17) |
| [Dark theme](#dark-theme) | Resource data | Patches > iPod Appearance | BMap, View and Type bytes | Yes |
| [Dark Mode switch](#dark-mode-switch) | Code and data | Patches > iPod Appearance | 1 `b` and 2 vtable words, a table and a menu | No |
| [Move of rsrc](#move-of-rsrc) | Partition layout | Automatic | 1 directory entry | Yes |

## The build sequence

iPodFirm does not change the opened file. It keeps the edits in memory and makes a new firmware partition when you save, flash, export an `.ipsw` or start the emulator. `AppModel.outputOSOS` in [AppModel.swift](../mac/Sources/iPodFirm/AppModel.swift) does these steps in this sequence:

1. Start with the osos of the editor. This osos has the picture and text edits.
2. Apply the appearance:
   - Light: no change.
   - Dark: apply the theme changes (`ImportedTheme.apply`).
   - Switch on iPod: run `DarkMode.build`.
3. Apply the switched-on patches (`Patcher.apply`), sorted by name.
4. Apply the software version (`FirmwareVersion.apply`), if it is not 1.3.

Then `AppModel.outputPartition` moves rsrc if osos is larger (`FirmwarePartition.makeRoom`). Then it replaces osos and calculates the new checksum (`replaceImage`).

Each step examines the bytes before it changes them. A step that finds unexpected bytes stops the build with an error. No partial result goes to the iPod.

## Picture replacement

**User interface.** Pictures pane: "Replace…", "Export PNG…", "Export All…" and "Import Folder…". The "Dark Theme" switch shows the pictures of the selected dark theme.

**Change.** `Picture.encode` in [Pictures.swift](../mac/Sources/IPodFWKit/Pictures.swift) writes new pixel bits into the BMap data. It does not change the 28-byte header or the row padding.

**Limits.**

- The new image must have the same width and height as the old picture.
- The pixel format does not change. iPodFirm converts the image to RGB565, ARGB4444 or grey levels.
- A grey picture (1, 2 or 4 bits) loses colour.

An edit of a dark theme picture goes into the theme file, not into osos. Refer to [Edits of the dark theme](#edits-of-the-dark-theme).

## Text replacement

**User interface.** Text pane. A gauge shows the free bytes of each language.

**Change.** `Resources.writeStrings` in [Resources.swift](../mac/Sources/IPodFWKit/Resources.swift) packs all the strings of one language block again. Each string is UTF-8, ends with a zero byte and starts on a 4-byte boundary. The function writes the new offsets and sizes into the resource table.

**Limits.**

- The strings must fit in the area that the language already has.
- To make one text longer, make other text in the same language shorter.
- The function refuses an unknown string ID.

## Software version

**User interface.** Patches pane > Software Version. The section "Letters" shows the letter of each patch:

- "Show a different version on the About screen", with a text field (for example `1.3.1`).
- "Add a letter for each switched-on patch".

Both settings are off by default.

**Ghidra result.** The firmware does not keep the text "1.3". `FUN_0009ee70` makes a version object. The instruction `mov r1, #1` at 0x9ee90 gives the major number. The instruction `mov r2, #0x30` at 0x9ee94 gives the minor number and the fix number (`minor << 4 | fix`). The version object writes the text. It can add only the stage texts "d", "a", "b" and "fc" (`FUN_00188d94`, table 0x4fc298).

**Change without letters.** `FirmwareVersion.apply` in [FirmwareVersion.swift](../mac/Sources/IPodFWKit/FirmwareVersion.swift) replaces the two `mov` instructions. It first makes sure that they are `0xe3a01001` and `0xe3a02030`.

**Change with letters.** The function writes a new body into `FUN_0009ee70` (0x9ee70–0x9eed8, 104 bytes). First, it makes sure that the 104 bytes are the Apple bytes. The new body does these steps:

1. It copies a fixed C string at 0x9eea0 into a Pascal string (`FUN_00092948`).
2. It copies the Pascal string into the About string (`FUN_000934c4`).

The Apple function also ends with these two calls.

Each patch has one letter (`version_letter` in `patch.json`). The letters are sorted, for example "1.3.1abkw".

**Limits.**

- The major number is 0–255. The minor number and the fix number are 0–15.
- The text has a maximum of 24 characters (`maxTextLength`).
- iTunes and Finder continue to see version 1.3. The VisibleBuildID that the iPod sends to the computer comes from other instructions. iPodFirm does not change them.

## backlight-60s

**User interface.** Patches pane > 60-Second Backlight, letter `b`.

**Effect.** Settings > Backlight Timer shows Off, 5, 10, 15, 20 and 60 Seconds, and Always On. The 2 Seconds item is removed.

**Research.** Refer to [re/backlight-timer.md](../re/backlight-timer.md).

- The menu is Menu −138 (data at 0x4b069c). It has 7 items of 40 bytes.
- The conversion from the item value to seconds is not in ARM code. A script in `TCmd` 9088 does it with a switch at 0x4ba9f9.
- The value 0x6039 has no Apple item. Its case pushes 0xfffe (at 0x4baa76). The idle controller uses 10 seconds for this value.
- The native method 0x1eb65c writes the seconds to the application object at +0x444. The idle controller (0x1d847c, 0x12ec5c) starts its timer with `seconds × 1000` ms.

**Change.** This patch has no C code. It uses the `bytes` and `strings` keys of `patch.json`:

- The case for 0x6039 pushes 60 (`58 00 3c`) in place of 0xfffe.
- Menu items 1–4 get the value and the string ID of the next item (5, 10, 15 and 20 Seconds).
- Menu item 5 gets the value 0x6039 and the string ID −140.
- String −140 becomes "60 Seconds" in each of the 21 languages that have it. Finnish uses "60s", because "60 s" does not fit in the string area.

**Test status.** The emulator showed the new menu, and the selection operated. The emulator does not model the dimmer, so it cannot measure the backlight time.

## album-art

**User interface.** Patches pane > Album Artwork, letter `a`, version 2.6. The section "Album Thumbnail Source" selects the option `source` (refer to [The thumbnails](#album-art)). `"ui": { "tools": ["album-thumbnails"] }` gives the detail these sections:

- "Thumbnails": "Write Thumbnails to iPod" writes the thumbnail file. The albums do not need this file. "Eject iPod" ejects the iPod.
- "Playlist Artwork" sets a custom image for each playlist ("Choose Image…", "Use Automatic", or drag an image).

**Effect.** Each row in an album list and in a playlist list shows a 20 × 20 thumbnail at its left side.

**The thumbnails.**

- An album gets its thumbnail from the artwork that iTunes or Finder put on the iPod: `iPod_Control/Artwork/ArtworkDB` and the 100 × 100 images (format 1028) in `F1028_N.ithmb`. The patch makes a 20 × 20 thumbnail with the average of each 5 × 5 square.
- A playlist gets its thumbnail from the file `iPodFirmAlbumArt`. An album without artwork on the iPod also uses this file, if the file has it.
- The file is optional. Without the file, the albums show their thumbnails and the playlists show none.
- The option `source` sets the order for an album. "iPod Artwork" (0, the default): the artwork first, then the file. "iPodFirm Thumbnail File" (1): the file first, then the artwork. The file is in memory, thus mode 1 reads the disk only for an album that is not in the file. After a sync that adds albums, write the file again.
- The patch makes the album table only at the first album row that needs the artwork. In the file mode, the row "All" does not make it: the patch makes the table only for a name that is in the album list of the library (library + 0xc60, count at + 0xc6c).
- Late fill: while the wheel moves, a row whose thumbnail needs the disk shows a grey square of 20 × 20. The table build also waits. At the end of the movement (wheel event with the step 0), the patch calls `view_invalidate` (0x21ac04) on the list, and the visible rows get their thumbnails. A step that is older than 0.3 s does not count as a movement. The real wheel often sends no end event. Thus the patch also uses the 100 ms timer of the list (list + 0xcc) as a tick: a tick 0.3 s after the last step draws the list again. The list uses this timer for the blink of the selected row. The patch takes only the events of a timer that it started, and does not start it in the first 1 s after a key push.
- Background fill (artwork mode): while the wheel does not move, each tick that comes to the visible list of the last album row makes one thumbnail. It starts near that row and stops when the memory for thumbnails is full.

The research is in [../re/album-art-v2.md](../re/album-art-v2.md).

**Load address.** `extended` (refer to [patch-system.md](patch-system.md#the-extended-area)). The compiled code and data are 12360 bytes. Version 1.0 used the fixed area 0x7358d0–0x73658c (3080 bytes). Thus a build with this patch moves rsrc.

**Hooks.**

| Kind | At | Expect | To | Replaced method |
|---|---|---|---|---|
| `word` | 0x66e470 | 0x001bb260 | `hook_row_label_draw` | Draw method of the list-row label class (type 0x3180) |
| `word` | 0x677a14 | 0x00244924 | `hook_label_draw` | Draw method of the general label class (type 0x1580) |
| `bl` | 0xb4ad4 | 0xeb057c60 | `hook_db_loaded` | The call of `log_event` (event 0xf, "Exit Disk Mode") in the music database load 0xb4a64 |
| `word` | 0x6772c0 | 0x0023b704 | `hook_list_event` (`chain`: `list_event`) | Event method (slot +0x30) of the browse-list class 0x677290. `cover-flow` chains to the same word. |

The list-row label scrolls a long title on the highlighted row from a cached image of the text. Thus the patch wraps the complete method `0x1bb260`, not only its call to `0x244924`.

**Firmware calls.** The patch calls these firmware functions:

| Address | Name in the patch | Function |
|---|---|---|
| 0x244924 | `label_draw` | Original draw of the general label |
| 0x1bb260 | `row_label_draw` | Original draw of the list-row label |
| 0x255ac4 | `view_bounds` | Gets the rectangle of a view |
| 0x21a27c | `gc_prepare` | Sets the origin and the clip of the graphics context for a view |
| 0x2106e4 | `gc_set_color` | Sets the fill colour (R, G, B, A bytes) |
| 0x210290 | `gc_set_mode` | Sets the draw mode |
| 0x211a00 | `gc_fill_rect` | Fills a rectangle (only if the target is not RGB565) |
| 0x210114 | `gc_blit` | Copies the pixels of a source gc into a gc |
| 0x09bc6c | `lib_resolve` | Resolves the library reference of the main provider |
| 0x09eff8 | `pool_copy` | Copies the UTF-16 text of a string pool entry |
| 0x25a974, 0x25a8e4 | `fw_alloc`, `fw_free` | Memory from the pool at 0x1081da00 |
| 0x07ccd0, 0x07cd6c | `fw_memset0`, `fw_strcpy` | Memory and string functions |
| 0x08f38c, 0x08f464, 0x08f5c4, 0x08f184 | `file_open`, `file_read`, `file_seek`, `file_close` | File access on the iPod disk |
| 0x213c5c | `log_event` | Adds an event to the usage log |

**Runtime logic.** For each draw of a label, the wrapper does these steps:

1. If the parent of the label (view + 0x10) does not have the class 0x66b4dc (a list cell), call the original method and stop. This rule applies only to the general label. It prevents a thumbnail in Now Playing.
2. Read the element ID at view + 0x1c. Continue only for 0x6421 (album name) or 0x6425 (playlist name).
3. Make the album table if it is not made. Load the thumbnail file if it is not loaded.
4. Make sure that the label is at the left edge (x ≤ 8).
5. Calculate the FNV-1a hash of the text. For a playlist, start the hash with the byte 0x01.
6. For an album, find the hash in the album table (binary search). If the thumbnail is not in memory, read the 100 × 100 image and make the thumbnail.
7. If there is no thumbnail from the artwork, find the hash in the index of the file.
8. Make sure that the label has the height of a list row.
9. Add 24 pixels to the left edge of the label (view + 0x5c). Call the original method. Subtract the 24 pixels again.
10. Call `gc_prepare`. Then draw the thumbnail with one call of the blit 0x210114.

**The album table.** At the first album or playlist label after a database load, the patch makes the table:

1. For each track in the RAM database (db + 0x20, count at db + 0x1c), it calculates the FNV-1a hash of the UTF-8 form of the album name (pool db + 0x138). This is the same hash as the hash of the label text.
2. It sorts the tracks by their dbid (track + 0x108).
3. It reads ArtworkDB through a 32 KB window. For each image (mhii) of a track with an album, it keeps the hash, the file number N and the offset of the format-1028 image.
4. It sorts the entries by the hash and keeps one entry for each album.

The table has 12 bytes for each album with artwork. While the table is made, the patch also uses 12 bytes for each track and the 32 KB window.

**The draw.** The blit gets a source gc: a 0x44-byte gc with zero origins, with a bitmap descriptor around the thumbnail. The descriptor has the same format word as the target, so the blit copies the pixels and does not convert them. The firmware clips with gc + 0x34 and marks the damaged area. If the target is not 16 bits for each pixel with the format 0x565, the patch draws runs of filled rectangles, as version 1.0 did.

Some draws of a highlighted row pass a structure, not text. The first byte of the structure is less than 0x20. Then the patch uses the thumbnail of the last draw of the same view (32 view slots).

**Draw mode.** The patch uses mode 0, which replaces the pixels. Mode 1 darkens. With mode 1 the thumbnails were not visible on the dark theme.

**Reload after a sync.** The firmware loads the music database at the start and after each USB session. The hook at 0xb4ad4 in this load sets a flag. At the next album label or playlist label, the patch clears the flag, makes the album table again and reads the 16-byte header of the file again. If the header changed, it frees the old data and loads the file again. If there was no file, the patch tries to load it again. Without a USB session, the patch does not read the file again.

**Memory.**

- The artwork: the patch makes each thumbnail at its first draw (one read of 20000 bytes) and keeps it. It keeps a maximum of 1 MB of thumbnails (1310 albums). Above this limit, a new thumbnail replaces the oldest one.
- The file: if all its thumbnails are 1 MB or less, the patch loads all of them. Otherwise it keeps a cache of 64 thumbnails.

A mark of the label for a new draw (`view_invalidate` 0x21ac04) during a draw does not start a new draw. Thus the patch cannot delay a read to a later draw. It reads each thumbnail at its first draw.

### The thumbnail file

iPodFirm writes `iPod_Control/iTunes/iPodFirmAlbumArt` on the mounted iPod volume (`AlbumArt.build` in [AlbumArt.swift](../mac/Sources/IPodFWKit/AlbumArt.swift)). All values are little-endian.

| Offset | Size | Content |
|---|---|---|
| 0x00 | 4 | `IFAT` |
| 0x04 | 2 | Version: 1 |
| 0x06 | 2 | Thumbnail size S in pixels (20) |
| 0x08 | 4 | Count N |
| 0x0C | 4 | Stamp: the FNV-1a hash of all the bytes after the header (the entries and the thumbnails) |
| 0x10 | 8 × N | Entries {u32 hash, u32 file offset of the pixels}, sorted by hash |
| then | 2 × S × S × N | The thumbnails, RGB565, row by row |

The hash of an album is FNV-1a of the UTF-8 album name. The hash of a playlist is FNV-1a of the byte 0x01 and the name.

`MusicImport.writeThumbnails` in [MusicImport.swift](../mac/Sources/IPodFWKit/MusicImport.swift) gets the data from the iPod itself:

1. It reads the tracks of `iPod_Control/iTunes/iTunesDB`.
2. For each album, it reads the cover of one of the first three tracks. It reads MP4 tags first, then AVFoundation metadata.
3. For each playlist, it uses the custom image, or a 2 × 2 collage of the covers of the first four albums.
4. It writes the file with an atomic write.

The custom playlist images are PNG files in `iPod_Control/iTunes/iPodFirmPlaylistArt/<FNV-1a of the name, 8 hex digits>.png`. Each image is a centre square of a maximum of 200 × 200 pixels.

### The Now Playing artwork

The large artwork in Now Playing does not come from the patch. RetailOS reads `iPod_Control/Artwork/ArtworkDB` and the files `F1028_1.ithmb` (100 × 100) and `F1029_1.ithmb` (200 × 200). iPodFirm writes these files only for the emulator library (`ArtworkDB.build` in [ArtworkDB.swift](../mac/Sources/IPodFWKit/ArtworkDB.swift)). The layout follows libgpod. On a real iPod, iTunes or Finder writes them.

**Limits.**

- On-The-Go has no thumbnail, because iTunesDB does not contain it.
- A song row never gets a thumbnail, also if the song has the same name as an album.
- Two names with the same FNV-1a hash share one thumbnail. The second name is ignored.

**Test status.** Version 1.0: tested in the emulator and on a real iPod 5.5G, with the light theme and with the dark theme. Version 2.0: tested in the emulator (refer to [../re/album-art-v2.md](../re/album-art-v2.md)). Version 2.1: installed on a real iPod 5.5G with flash storage. The owner reports that the Albums list scrolls more slowly than without the patch, also on the second pass (9 October 2026). Version 2.2: measured on the same iPod on 9 October 2026. Each new album reads its image from the disk in approximately 22 ms, and the first Albums list stops for approximately 0.8 s. With the thumbnails in memory, the patch adds approximately 4–5 % to each row. Refer to [../re/album-art-v2.md](../re/album-art-v2.md). Version 2.3 with "iPodFirm Thumbnail File": tested on the same iPod on 10 October 2026. The owner reports a much better scroll. The stats show one disk read in approximately 1500 album rows. Version 2.4: tested in the emulator (late fill, the row "All", and with `cover-flow` 0.6.1). On the real iPod with the file mode and `cover-flow` 0.6.1 (10 October 2026): no table build at the first open (the slowest album row was 45.6 ms, 813 ms in version 2.3), no fill from the ithmb file, and Cover Flow operated. The artwork mode on the real iPod with the file present (10 October 2026): no grey squares, 26 fills from the ithmb file, but only 2 end events of the wheel in approximately 28 s. Without the file (10 October 2026): the scroll is smooth, but most rows show a grey square until a stop. 768 waits, 5 end events, 5 redraws, 45 fills. Version 2.5 (background fill with type 0xd): on the real iPod, the covers did not load (type 0xd comes only each 3–4 s there). Version 2.6 (the list timer as the tick): tested in the emulator without type 0xd; 0 waits, all covers loaded. Tested on the real iPod with `cover-flow` 0.6.2 on 14 October 2026: the owner reports that it works well.

**Measurement build (versions 2.2 and 2.3).** The patch times its parts with `USEC_TIMER` (`ALBUM_ART_STATS 1` in `album_art.c`). After each 256 album or playlist row draws, it writes one record to `iPod_Control/iTunes/iPodFirmAlbumArtStats` with `file_open_rw` (0x08f3f8) and `file_write` (0x08f6f4). The script [../re/album-art-stats.py](../re/album-art-stats.py) shows the records. The write can stop the scroll for a short time. Version 2.3 also records the value of `source`. Version 2.4 also records the waits, the end events and the redraws (record version 3). Version 2.5 also records the background fills (record version 4). The measurement is for the test only. Remove it in a later version.

## sleep-now

**User interface.** Patches pane > Sleep Now, letter `s`.

**Effect.** The Sleep item puts the iPod to sleep at once. On a charger, on USB power or during a voice memo, Sleep operates as in the Apple firmware.

**Problem.** In the Apple firmware, the Sleep item (0x1d83fc) turns the backlight off and starts the idle timer (500 ms). The idle timer handler (0x1d8a40) sleeps only if a gate passes (0x1d938c → 0x1d8444 → 0x1d8670, 0x1d8718). The gate can refuse the sleep for a long time, for example after a computer session. Then the screen stays on and the wheel does not respond. Refer to [re/sleep.md](../re/sleep.md).

**Load address.** 0x73658c. The compiled code is 181 bytes.

**Hooks.**

| Kind | At | Expect | To | Function |
|---|---|---|---|---|
| `word` | 0x69fd2c | 0x001d83fc | `hook_sleep_item` | A table entry that points to the Sleep item handler |
| `bl` | 0x1e8ce8 | 0xebffbdc3 | `hook_sleep_item` | App command 7 (0x1e8cd4) calls the Sleep item handler here |
| `bl` | 0x1ee930 | 0xebfff8d5 | `hook_power_test` | The external-power test in 0x1ee8d0 |

**Runtime logic.**

1. `hook_sleep_item` calls the Apple handler 0x1d83fc.
2. If a voice memo records (byte +0x66 of the object from 0x1c1f5c), it stops.
3. It stops the timers at controller + 0x48 and + 0x74 (0x151c98).
4. It calls 0x1d9308, the sleep part of the timer handler 0x1d8cd0. This part saves the settings, writes the cache and calls the sleep function 0xb43dc.
5. During this call, `hook_power_test` reads the power pins directly, not the saved copy:
   - GPIOL bit 0x08 low: FireWire or charger power.
   - GPIOL bit 0x10 high, and 0x265698 does not return 1: USB power.
6. If it finds power, the Apple behaviour stays: the display stays on and the sleep waits.

Outside a forced sleep, `hook_power_test` calls the Apple test 0x1ecc8c.

**Test status.** In the emulator, the hook ran and the firmware wrote the cache to the disk (ATA 0xCA). Then 0xb43dc turned the display off. The emulator does not model the hardware sleep, so the test stops there. The settings were kept after a restart. Not tested on a real iPod.

## flash-keep-awake

**User interface.** Patches pane > SSD Mode, letter `k`. The pane shows a warning if the iPod probably has the original hard drive. Refer to [Storage type](#storage-type).

**Effect ("SSD mode").**

- The storage stays on for 30 minutes after each access, not for approximately 1 second.
- When the iPod wakes from sleep, the iPod starts the storage at once.
- Before the storage power goes off, the iPod waits 0.5 seconds.

**Problem.** A flash adapter needs 3–6 seconds to start its cards after a power cut. The Apple firmware cuts the storage power approximately 1 second after the last access. Thus the first song after a pause starts late. The firmware itself needs only approximately 15 ms for a wake. Refer to [re/play-latency.md](../re/play-latency.md).

**Load address.** 0x736644. The compiled code is 188 bytes. The functions use `__attribute__((minsize))`.

**Hooks.**

| Hook | Kind | At | Expect | To | Original instruction |
|---|---|---|---|---|---|
| 1 | `bl` | 0x284c7c | 0xe5941018 | `hook_keep_awake_time` | `ldr r1, [r4, #0x18]` in the keep-awake task 0x284b0c |
| 2 | `bl` | 0xb45f4 | 0xeb0412c7 | `hook_after_wake` | `bl 0x1b9118`, the last call of the sleep function 0xb43dc |
| 3 | `bl` | 0x1d871c | 0xebfaf172 | `hook_storage_in_use` | `bl 0x94cec` in the sleep gate |
| 5 | `bl` | 0x23344c | 0xeb00ca1d | `hook_drive_power_off` | `bl 0x265cc8` (power off) in the "set power" method 0x233358 |

Hook 4 is in the separate patch [flash-wake-on-input](#flash-wake-on-input).

**Runtime logic.**

- **Hook 1** is a `naked` function. It loads the time of a type-2 keep-awake message, as the original instruction did. If the time is less than 1,800,000 ms, it sets 1,800,000 ms. It does not change 0, 1 or 0xffffffff. It changes only `r1` and `ip`, because the caller uses `r0`, `r2` and `r4` after the hook.
- **Hook 2** calls the original function 0x1b9118. Then it sends "always on" (0x94e6c) and "on for 30 minutes" (0x94d80) for slot 40. No firmware code uses slot 40 as a constant.
- **Hook 3** replaces the "any slot active" test of the sleep gate. It returns 1 only if a slot is active and its time is 0xffffffff (a client that uses the storage now). A timed slot does not stop the sleep.
- **Hook 5** waits 500 ms (task sleep 0x11c9fc). Then it calls 0x265cc8 with 0 (power off). The firmware sends STANDBY IMMEDIATE before this call. The wait gives the flash card time to complete its writes.

**Why hook 3 is necessary.** The first version had only hook 1. On the real iPod, Sleep then did not operate for 30 minutes. The cause:

1. The helper 0x94d80 sends `time + 1`. A client that releases its slot thus sends 1 ms.
2. Hook 1 changed 1 ms to 30 minutes.
3. The sleep gate refuses the sleep while any slot is active (0x94cec).

The fix has two parts: hook 1 does not change 0, 1 or 0xffffffff, and hook 3 ignores timed slots.

**Limits.**

- More battery use while the storage is on.
- The emulator cannot sleep. Thus hook 2 and hook 3 have no full test in the emulator.
- The owner reported slower scroll in lists with this patch. The emulator showed that the patch code does not run during a scroll. The cause is not known.

**Test status.** The 2-minute version of hook 1 was tested on a real iPod (2 October 2026). The current version with hooks 2, 3 and 5 is tested only in the emulator.

## flash-wake-on-input

**User interface.** Patches pane > Wake Storage on Input, letter `w`. The pane shows the same storage warning as for `flash-keep-awake`.

**Effect.** When you push a button after a long pause, the iPod starts the storage at once. A turn of the wheel does not start the storage.

**Load address.** 0x736700. The compiled code is 132 bytes. It ends at 0x736784.

**Hook.**

| Hook | Kind | At | Expect | To | Original instruction |
|---|---|---|---|---|---|
| 4 | `bl` | 0x1d8344 | 0xebffff7c | `hook_user_event` | `bl 0x1d813c` in the UI event handler 0x1d81cc |

0x1d813c starts the idle timer again and turns the display on. The event handler calls it for a button event. It does not call it for the wheel events (codes 0x10 and 0x1c).

**Runtime logic.**

1. Call the original 0x1d813c.
2. Read `USEC_TIMER` (0x60005010). If the time since the last check is less than the check gap, stop.
3. If a keep-awake slot is active (0x94cec), set the check gap to 1 second and stop.
4. Send "always on" and "on for 30 minutes" for slot 40.
5. Set the check gap to 30 minutes.

The unsigned subtraction is correct when the 32-bit counter wraps (each 71.6 minutes).

**Test status.** Emulator: one button push turned on the storage power 0.05 ms later. 60 wheel steps did not run the hook. Not tested on a real iPod.

## cover-flow

**User interface.** Patches pane > Cover Flow, letter `c`, version 0.6.3. The patch needs no file of iPodFirm: it uses the albums, the names and the artwork that the iPod already has. The research is in [../re/cover-flow.md](../re/cover-flow.md).

**Effect.**

1. Hold Select in the Albums list for 0.5 s. Cover Flow opens at the selected album.
2. Turn the click wheel. Each wheel step moves the target one cover and gives the click of the lists, as the Clicker setting gives. A timer moves the covers smoothly to the target: a fast turn catches up quickly, and each stop slows down softly.
3. The centre cover is flat. Four covers at each side are slanted and a little darker. Each cover has a reflection. The album name and the artist (grey) show below the covers, centred, in the font of the list rows.
4. Push Select. The album at the centre opens, as from the list.
5. Push Menu. The Albums list shows again.

The background is white with the light theme and black with the dark theme. On white, the reflections fade to white. The text has the colour of the list rows of the theme.

A short push of Select opens the album as usual. Play/Pause operates as usual. If the iPod shows a new screen (for example Now Playing), Cover Flow closes.

**Load address.** `extended` (refer to [patch-system.md](patch-system.md#the-extended-area)). The compiled code and data are 10888 bytes. The functions that run once for each event or each open have `__attribute__((minsize))`; the pixel loop `draw_cover` stays fast code. The framebuffer copy (153600 bytes), the cover cache (11 covers of 128 × 128, 360448 bytes), the read buffer (80000 bytes), the caption copy (26880 bytes) and the placeholder cover come from the allocator 0x25a974 when Cover Flow opens. They are released when it closes. The album table (about 9 bytes for each album) stays in memory while the database does not change. While the table is made, the patch also uses 12 bytes for each track and a 32 KB read window.

**Hooks.**

| Kind | At | Expect | To | Replaced |
|---|---|---|---|---|
| `word` | 0x6772c0 | 0x0023b704 | `hook_list_event` (`chain`: `list_event`) | Event method (slot +0x30) of the browse-list class 0x677290. `album-art` also hooks this word. Since version 0.6.1, the hook has `chain`, so that the two patches operate together. Since version 0.6.2, the hook takes a timer event of the list only in the first 0.3 s after the close of Cover Flow. |
| `word` | 0x6701f0 | 0x001d81cc | `hook_ui_event` | The UI event handler 0x1d81cc |
| `word` | 0x17ef8c | 0x0017ef98 | `hook_display_damage` | The literal of the damage callback, which the display registers at the start |

**Firmware functions.**

| Address | Name in the patch | Function |
|---|---|---|
| 0x23b704 | `list_event` | Original event method of the browse lists |
| 0x1d81cc | `ui_event` | Original UI event handler |
| 0x17ef98 | `display_damage` | Original damage callback |
| 0x1647c0 | `display_server` | Returns the display server |
| 0x164878 | `display_bind` | Binds a layer of the display |
| 0x1650f8 | `display_flush` | Sends the dirty rows to the LCD |
| 0x0c9a84, 0x0c9b58 | `display_lock`, `display_unlock` | The mutex of the display server |
| 0x21ac04 | `view_invalidate` | Marks a view for a new draw |
| 0x13d524 | `dispatch_event` | Event dispatcher |
| 0x1d813c | `ui_activity` | Starts the idle timer again and turns the display on |
| 0x0a69dc | `ui_click` | The click of the lists (follows the Clicker setting) |
| 0x09bc6c | `lib_resolve` | Resolves the library reference of the main provider |
| 0x09eff8 | `pool_copy` | Copies a UTF-16 string from a string pool of the database |
| 0x244924 | `label_draw` | Draws the text of a label (the caption) |
| 0x25a974, 0x25a8e4 | `fw_alloc`, `fw_free` | Memory from the pool |
| 0x07ccd0, 0x07cd6c | `fw_memset0`, `fw_strcpy` | Memory and string functions |
| 0x08f38c, 0x08f464, 0x08f5c4, 0x08f184 | `file_open`, `file_read`, `file_seek`, `file_close` | File access on the iPod disk |

**Runtime logic.**

1. `hook_ui_event` records its first argument (the UI object). The UI handler gets each key event before the list.
2. A push of Select (type 4, key 0x6f) in the Albums list (element ID 0x6382, visible) goes to `hook_list_event`. The hook keeps a copy of the event and does not give it to the firmware.
3. When the firmware reports the hold (type 6 at `hook_ui_event`, 0.5 s after the push), the patch opens Cover Flow. If no type 6 comes, an event at the list 0.7 s after the push (usually its timer, type 9) also opens it. If the release (type 7) comes first, the hook sends the kept push through the dispatcher 0x13d524. The copy has its own vtable with an empty delete slot. `hook_ui_event` skips the copy of the push, because the UI handler had the original. Then the album opens as usual.
4. To open, the patch makes the album table (only the first time, or after the database changed), allocates the memory and copies the framebuffer. It starts at the selected row − 1 (row 0 is "All") if the list has one row more than the table has albums. Else it starts at the first album.
5. Each frame: clear the framebuffer, load the new covers from the centre outward, draw the covers from the farthest to the centre, draw the caption, then bind the layer, set the dirty rows 0–240 under the lock, and flush. The patch does not call the damage callback, because the callback can bind the layer again and wait for itself.
6. While Cover Flow shows, `hook_display_damage` ignores the damage of the firmware. If the Albums list is not visible, it closes Cover Flow and gives the damage to the firmware.
7. A wheel event (type 0xf) moves the target one cover in its direction (event + 0xc) and calls the click 0xa69dc. It does not draw (only the first frame of a movement), so the event handler returns at once.
8. The animation uses the timer of the list (list word 0x33, 100 ms for the list): stop 0x151c98, set 0x151c24 (15 ms), start 0x151694. Each timer event (type 9, event word 2 = the timer) goes to `hook_list_event`. Each tick starts the timer again first, then moves the position 5/8 of the remaining distance (at least 20/256 of a cover) and draws one frame. When the position is at the target, each tick loads one more cover near the centre (centre ± 4), then the timer stops. Each frame loads at most one new cover, the nearest to the centre first. The first frame at the open loads up to 3 covers: the centre and its two neighbours. A cover that is not loaded yet shows the grey square for that frame. If a cover is missing after the first frame, the open starts the timer, and each tick loads one more cover (since version 0.6.3). The caption is drawn one time for each centre album and copied in the other frames. On close, the patch stops the timer and sets 100 ms again. A timer event that comes after the close is swallowed if the repeat count of the list (byte list + 0xf8) is 0, because the list would count down from 255. The patch takes the wheel events, thus it calls 0x1d813c for each of them, as the UI handler does. Then the backlight and the sleep timer start again. The UI handler gets the key events, so it does this for them itself.
9. Select (type 4, key 0x6f) opens the centre album: the patch calls the method +0x138 of the list (0x23a04c, set the selected row) with the row of the album (the album index + 1, because row 0 is "All"). Then it closes Cover Flow and gives the push to the original list method. The push then goes on through the chain, and the firmware opens the selected album. If the list does not have one row more than the table has albums, Select does nothing.
10. The theme: at the open, the patch examines the left margin of the list rows (x = 2, every 8 rows below y = 40) in the copy of the screen. If most pixels are bright (green ≥ 32 of 63), the background is white. Else it is black.
11. Menu (type 4, key 0x6e) closes Cover Flow: the patch puts the framebuffer copy back, sends it, and marks the top view of the list for a new draw (0x21ac04). The UI handler acts on Menu at type 6 or 7, thus `hook_ui_event` swallows these events of the key and decreases the key count at UI object + 0x44 at the release, as 0x1d820c does.

The draw uses no division instruction (the ARM7TDMI has none). `udiv` is a shift-and-subtract loop. A table gives (S << 16) / h for each cover height.

### The data

The album table:

1. The library is `lib_resolve(*(provider + 0x1c))`, with the main provider at RAM 0x1081da18. Library + 0xcf8 is the database.
2. Library + 0xc60 points to the album list of the firmware: one album pool index for each row of the Albums list without "All", in the order of the list. Library + 0xc6c is the count. Thus the patch has the order of the firmware, also for names that start with punctuation or digits.
3. The album pool (db + 0x138) has one UTF-16 entry for each track. The patch makes an FNV-1a hash of the name of each row, and of the album name of each track (the track list starts at db + 0x20, the count is at db + 0x1c, the next track is at track + 4). A binary search over the hashes of the rows gives the row of each track. The first track of a row gives the artist (pool db + 0xe0, index at track + 0x2c).
4. The patch keeps the dbid (track + 0x108) and the row of each track, sorted by the dbid.

The artwork:

1. The patch reads `iPod_Control/Artwork/ArtworkDB` through a 32 KB window: mhfd, mhsd (type 1), mhli, then each mhii. An mhii has the dbid of its track at + 0x14.
2. If the dbid belongs to an album without a 200 × 200 cover, the patch looks at the children of the mhii: a container mhod (type 2) with an mhni gives the offset in the .ithmb file (mhni + 0x14). The patch takes format 1029 (200 × 200, size 80000, the Now Playing artwork). It takes format 1028 (100 × 100, size 20000) only if the album has no 1029 image. The file name (`:F1029_N.ithmb`, UTF-16, in the mhod after the mhni) gives N.
3. At each new cover, the patch reads the image from `iPod_Control/Artwork/F1029_N.ithmb` (or `F1028_N.ithmb`) into the read buffer. Then it makes a 128 × 128 texture, the size of the centre cover. From 200 × 200: the average of 2 × 2 pixels, in packed RGB565. From 100 × 100: bilinear filtering. Thus the centre cover shows 1:1 without steps. An album without artwork gets a grey square with a lighter frame.

Version 0.4 used the 100 × 100 image and enlarged it without filtering. The covers then had visible steps. Emulator times for each new cover (one for each wheel step): the read of 80 KB takes 9.5 ms, and the 2 × 2 average 7.1 ms (a bilinear filter took 15.7 ms). The first frame at the open (5 covers) took 144 ms with the bilinear filter.

The caption:

1. The patch takes the album label (element 0x6421) of the template cell of the list (list word 0x2a, children at + 0x80, count at + 0x7c).
2. For the draw, it attaches the label to the top view and sets its rectangle (view + 0x58: top, left, bottom, right) to the line below the covers. It calls 0x244924 with the name in UTF-8. Then it puts back the parent, the rectangle, the flags and the byte at + 0x1b8.
3. The label draws at the left. The patch then moves the text pixels of the line to the centre. The background is exactly white or black, so each other pixel is text. For the artist line, it also mixes each text pixel halfway to the background (grey).

Before version 0.4, iPodFirm wrote a cover file (`iPod_Control/iTunes/iPodFirmCoverFlow`, 12 MB for 326 albums). Version 0.4 does not read it. You can delete it from the iPod.

**Limits.**

- In the Albums list, a long push of Select does not add the album to the On-The-Go playlist.
- In the album list of one artist, Cover Flow starts at the first album and shows all the albums.
- In the album list of one artist, Select does nothing.
- If the iPod has no image in format 1029 or 1028 for an album, the album shows the grey square.
- If two album names have the same hash, the second album gets no artwork and no artist.

**Test status.** Emulator (8 October 2026), with the emulator test library (6 albums) and a cover file from `MusicImport.writeCoverFlow`:

- A hold of Select opened Cover Flow at the hold event (0.506 s), at the selected album.
- The wheel moved the covers. The covers stopped at the first and at the last album.
- Menu closed Cover Flow. The Albums list showed again, with the highlight.
- A short push of Select (0.3 s) opened the album as usual. A short push of Menu went back as usual.

Real iPod 5.5G (owner, 8 October 2026, version 0.1, 326 albums): a hold of Select opened Cover Flow, the wheel moved the covers, and Menu went back to the Albums list. It also operated with Dark Mode.

Emulator (8 October 2026), version 0.4, with the FolderLibrary (1000 tracks, 138 albums, ArtworkDB with formats 1028 and 1029, no cover file):

- The first 8 rows of the table were "(III)", "<I°_°I>", "1:15 - Single", "10,000 gecs", "2019", "A Brief Inquiry Into On…", "After Laughter", "Ai Need Your Love - Sin…": the order of the Albums list.
- The real covers showed. The caption showed the album name and the artist in the font of the list rows, centred.
- The first open made the table in 35 ms (emulated time; the emulated disk is fast). The next open took no time.

Not tested: version 0.4 on the real iPod, a pop-up or a new screen while Cover Flow shows, and a database from iTunes or Finder.

## usb-host-probe

**User interface.** Patches pane > USB Host Probe, letter `h`. "Start the Probe at the Next Restart" writes '1' to `iPod_Control/iTunes/iPodFirmUSBProbe` and an empty 32768-byte `iPod_Control/iTunes/iPodFirmUSBLog` on the connected iPod. "Show USB Log" reads and decodes the log (`USBProbeLog` in [USBProbeLog.swift](../mac/Sources/IPodFWKit/USBProbeLog.swift)). The `ui` object of its `patch.json` gives the button, the section "Test Procedure" (the test steps) and the tool `usb-log` (the section "USB Log" with "Show USB Log" and "Copy Log"). This patch is a test for [USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md) (Stage 0). It is on main since 2026-10-08.

**Effect.** One time after the trigger, the iPod plays a demonstration of the signs and a countdown, starts its USB host stack, gives tones, and logs each call of a USB class driver. The next start is normal.

**Load address.** `extended`: the build puts the code after all other data, for example after a theme and the Dark Mode items (refer to [patch-system.md](patch-system.md#the-extended-area)). The compiled code and data are 22248 bytes (version 1.28; version 1.28 changes only a note). The isochronous test takes 8 KB and 32 KB more from 0xad80c when it runs, and the music test 12 KB more. The log buffer (32712 bytes, 511 records) comes from the allocator 0x25a974 when the probe starts. The findings are in [patches/usb-host-probe/FINDINGS.md](../patches/usb-host-probe/FINDINGS.md).

**Hooks.**

| Kind | At | Expect | To | Original |
|---|---|---|---|---|
| `bl` | 0x1d8260 | 0xeb0000c2 | `hook_event` | `bl 0x1d8570` (long-push timer) in the UI event handler 0x1d81cc |
| `bl` | 0x97364 | 0xeb073d0a | `hook_chip_check` | `bl 0x266794` (chip check, 0x598) in the UIM init 0x97300 |
| `bl` | 0x9741c | 0xeb03cd13 | `hook_irq_install` | `bl 0x18a870` (install and enable the USB interrupt handler 0xffd1c) in the UIM init |
| `bl` | 0x10c1d8 | 0xebff1d67 | `hook_add_device` | `bl 0xd377c` ("add device", the driver selection) |
| `word` | 0x6c884c, 0x6c8850 | 0x000974ec, 0x0009762c | `hook_uim_interrupt_endpoint`, `hook_uim_interrupt_transfer` | UIM table: create interrupt endpoint, interrupt transfer (not logged for the root hub address) |
| `b` | 0xcba54 | 0xe92d41f0 | `hook_interrupt_completion` | First instruction (`stmdb sp!, {r4-r8, lr}`) of the interrupt transfer completion callback (request, status, bytes). The wrapper continues at 0xcba58. At most 100 records. |
| `b` | 0xcb118 | 0xe92d40fe | `hook_completion` | First instruction (`stmdb sp!, {r1-r7, lr}`) of the control transfer completion callback. The wrapper runs it and continues at 0xcb11c. |
| `bl` | 0x9761c, 0x96d14 | 0xeb017997, 0xeb017bd9 | `hook_periodic_insert` | `bl 0xf5c80` (periodic insert). Fix of a firmware bug: the wrapper sets r1 = r0 (the new queue head). |
| `bl` | 0x1320fc, 0x13217c | 0xeb046d05, 0xeb046ce5 | `hook_usb_send` | `bl 0x24d518` (send 12 isochronous packets on endpoint 0x81) in the USB audio stream loop 0x132038 |
| `bl` | 0x13218c | 0x0b0468ce | `hook_usb_wait_if_sent` | `bleq 0x24c4cc` (wait for the endpoint). The hook is unconditional; the wrapper waits only if the last send returned 0. |
| `bl` | 0x1321d0 | 0xeb0468bd | `hook_usb_wait` | `bl 0x24c4cc` after the stream loop |
| `bl` | 0x170fc8 | 0xeb0370fd | `hook_device_start` | `bl 0x24d3c4` (the device mode start) in the device task loop 0x170f2c. Version 1.24: returns 1 while host mode runs. |
| `bl` | 0xd399c, 0x10c204, 0xe2be0 | 0xeb0018d2, 0xebff36b8, 0xebffdc41 | `hook_usb_message` | `bl 0xd9cec` (the USB host message to the UI, for example "unsupported device"). Version 1.27: skipped while host mode runs. |
| `bl` | 0x170fe0 | 0xeb03712d | `hook_device_stop` | `bl 0x24d49c` (the device session stop, a controller reset) in the device task loop. Version 1.24: skipped while host mode runs. |
| `word` | 0x6c882c, 0x6c8830 | 0x00096f64, 0x00096ffc | `hook_uim_control_endpoint`, `hook_uim_control_transfer` | UIM table: create control endpoint, control transfer |
| `bl` | 0xd28f0, 0x10e75c | 0xeb005422, 0xebff6487 | `hook_port_status` | `bl 0xe7980` (root port status) in the root hub GET_STATUS 0xd26b0 and in the status-change poll 0x10e6e0 |
| `word` | 0x6c872c, 0x6c8730 | 0x000e7c40, 0x000e7bc4 | `hook_hub_validate`, `hook_hub_init` | Hub driver: validate, initialize device |
| `word` | 0x6c85f0, 0x6c85f4, 0x6c85f8 | 0x00108b6c, 0x00108a24, 0x00110100 | `hook_composite_*` | Composite device driver (two records, one table) |
| `word` | 0x6c8784, 0x6c8788, 0x6c878c | 0x00102194, 0x00102178, 0x0010dd00 | `hook_storage_*` | Storage driver |
| `word` | 0x6c88dc, 0x6c88e0, 0x6c88e4 | 0x00113a78, 0x00118514, 0x001190a4 | `hook_ica_*` | ICA camera driver (Canon) |
| `word` | 0x6c8934, 0x6c8938, 0x6c893c | 0x00110620, 0x001174d8, 0x00118b50 | `hook_ptp_*` | PTP camera driver |

The dispatch tables are RW data. The start code copies them to RAM with the changes.

**Runtime logic.**

1. `hook_event` calls the original 0x1d8570. It acts only on events of type 4, 5 or 7 (button or wheel). Other event types also occur during the start, before the disk is ready.
2. At the first such event, if the trigger file contains '1', it writes '0'. If the write is correct, it plays the demonstration (the hub sign, a pause, the storage sign, a pause), three short beeps and 2 s of silence, then calls the host start 0x2860e8. The pauses come from the task sleep 0x11c9fc, because the tone function 0xcd430 only puts a tone in the queue. The UI does not react for approximately 7 s.
3. Each wrapper is `naked`. It saves r0–r3 and lr, calls `log_call` with the driver and entry number and the saved registers, restores them, and continues in the original function. Thus arguments on the stack stay correct.
4. `log_call` adds a 64-byte record (r0–r3, 20 bytes at r1 and at r2 if they point into RAM) to a buffer of 63 records. It gives the hub sign for "hub: initialize device" and the storage sign for "storage: initialize interface".
5. `hook_port_status` logs each change of the root port status (wPortStatus, wPortChange) with the raw PORTSC register, at most 24 records. The probe also logs the controller registers USBCMD, USBSTS, PORTSC and OTGSC after the host start and before each log write.
6. While the probe runs, `hook_chip_check` returns 0. The UIM init then stores 1 at +0x60 of the controller object and sets PFSC (bit 24) in PORTSC at 0x9746c: the port runs at full speed. Emulator: r1 = 1 at 0x97460.
7. The UIM wrappers log "create control endpoint" (address, endpoint, maximum packet size, speed) and each stage of a control transfer (setup with the 8-byte setup packet at r2, data, status with r2 = 0; the device address is the fifth argument, on the stack), at most 20 records. The queue record gives USBINTR, ASYNCLISTADDR, FRINDEX and 20 bytes of the first queue head and its qTD overlay (token at +0x18). The USB code gives buffer addresses in a window at 0x90000000. The log reads the same RAM through the normal window at 0x10000000 (the address minus 0x80000000), because a read in the 0x90000000 window stopped the probe on the real iPod (version 0.1.62).
8. `hook_irq_install` replaces the install of the host interrupt handler. While the probe runs, it disables source 20, removes the device driver handler 0xcd8e0 (the sequence of 0x18a888: 0x127888, 0x1277d0), installs the host handler with 0x18a83c and enables the source (manager method +0x30). It logs the result of each step. The root hub transfers are not logged (address 0 before its control endpoint, and its own address).
9. `hook_completion` logs each completion of a control transfer stage (request | stage bit, status, bytes, 40 bytes of the request block), at most 40 records, only for the request blocks of the last four logged device transfers (the root hub polls its port all the time, and each poll ends in a completion). 0xe01a0 calls the callback, possibly in the interrupt handler; the wrapper only writes RAM.
10. Before and after the host start, the probe sets the byte at RAM 0x1083e0f8 (+0 of the USB global block) to 2. Then "add device" 0xd377c accepts external hubs. `hook_add_device` logs each call of "add device" with the device descriptor.
11. Before each log write, the probe logs each queue head of the asynchronous list (from ASYNCLISTADDR, following the horizontal links) and each queue head in the periodic frame list (PERIODICLISTBASE 0xC5000154, size from USBCMD bits 3:2), at most 8 of each: endpoint characteristics, capabilities (S-mask, C-mask, hub, port) and the overlay token.
12. With each queue dump, the probe also logs Apple's own periodic table for frames 0–7 (the UIM controller object at RAM 0x1084a778 + 0xc: +0x3c the processor address of the first queue head of each frame, +0x44 the frame list).
13. `hook_periodic_insert` repairs a firmware bug. 0xf5c80 makes the frame list word from (r1 + 0x34) | 2, but both callers give the queue head only in r0 (0x974ec leaves r1 = the UIM controller object, 0x96c44 leaves r1 unset). Thus the frame list pointed to a block of zeros, and no interrupt endpoint was polled. The wrapper copies r0 to r1.
14. Before the host start, the probe changes the second composite driver record (registry entry 0x6bc434, RAM 0x1084a360) from device class 2/0 to EF/02 (bytes at +0x35 and +0x36). It changes them only if they have the stock values. Then "add device" gives a device of class EF/02 (interface association, for example the USB-C EarPods) to the composite driver, and the driver reads the configuration.
14a. Version 1.11: before the host start, the probe sets the storage driver record (registry entry 0x6bc460, RAM 0x1084a49c) +0x12 (interface class) and +0x35 (device class) from 8 to 0xff, if they have the stock values. No storage device gets a driver, thus the iPod does not enter the photo import state (a test for the album art of Now Playing).
15. The probe follows each GET_DESCRIPTOR configuration request of a device (setup, data stage buffer). At the last completion (r0 with the stage bit), it writes the received bytes to the log in records of 40 bytes (tag 44, "Data"), at most 512 bytes. The app decodes the configuration descriptor: interfaces, endpoints, interface associations and the audio class descriptors.
16. After the first log write, `audio_test` runs Stage 2 of [USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md) (version 1.2):
    1. At the completion of each GET_DESCRIPTOR configuration request, `find_audio` reads the received buffer (at most 512 bytes) and finds the first USB Audio Class 2 playback interface: 2 channels, 2-byte samples, an isochronous OUT endpoint of at least 192 bytes, and the clock source of the "USB streaming" input terminal. It keeps the device address of the request. Version 1.2 found it in the log records, which had old cache data (refer to item 21).
    2. It gets memory from 0xad80c (the allocator of the UIM frame list and queue heads): one page for a control queue head, three qTDs, the setup packet and the tone buffer, and 1024 siTDs. It uses the memory only if the addresses are in the window 0x90000000–0x94000000.
    3. It links its own control queue head after the queue head in ASYNCLISTADDR and sends SET_INTERFACE (alternate setting) and SET_CUR (48000 Hz to the clock source). The UI task polls the qTD tokens for at most 200 ms.
    4. It puts one siTD before the old entry of each frame of the frame list (controller object +0x44, type siTD = 4). Each siTD sends 192 bytes (one period of a 1 kHz sine, 48 stereo samples, peak 4000) to the endpoint: OUT, hub 0, port 1, S-mask 0x03, 2 start splits, "begin". Before the siTDs start, the iPod gives one short high beep.
    5. For 5 s, each 4 ms, it counts the executed siTDs (correct or an error) and makes them active again.
    6. It sets the siTDs inactive, puts the old frame list entries back, sends SET_INTERFACE with alternate setting 0, and logs the result (tags 48–51). Then the probe writes the log.
17. After the tone, `music_start` (version 1.4) sends the music of the iPod to the same device:
    1. It sends SET_INTERFACE again and SET_CUR 44100 Hz (48000 Hz if the device refuses 44100).
    2. It sets the USB audio state (RAM 0x108234ec): +1 = 0 (1000 packets each second), +8 = the rate. It sets the output rate of the converter of the USB source (0x1e2f60, the source object at RAM 0x10831964).
    3. Version 1.9: it sends SET_CUR volume −20 dB (control 2, channels 1 and 2) to the unit before the output terminal that is not "USB streaming" (the EarPods: feature unit 2), on the audio control interface.
    4. It puts its 1024 siTDs (inactive) into the frame list again and sets `music_mode`.
    5. It sets the byte at RAM 0x1081dff6 to 1 (again at each send, version 1.5). Without an iAP "Digital Audio" accessory this byte is 0, and then 0x1e2f74 returns 0 and 0x1e3064 gives silence and never takes the decoder buffers (version 1.4: the song stayed at 0:00).
    6. It does the steps of 0x132274 without the device endpoint: state + 2 = 1 (stream on), the event at state + 0x18 (0xd1e70) for USBAudioTask, the audio output object (RAM 0x108236a8) + 0x59 = 1, and 0x1a2fa0(output, 1). Then +0x5a = 1, and 0x1a2d60 gives the PCM buffers of the decoder to the USB source, not to the codec.
    7. USBAudioTask (0xc75cc, 0x132038) takes 12 packets each time from 0x1e3064. `hook_usb_send` copies each packet, 12 dB lower (the digital route has no volume), into one of 64 buffers and arms the siTD of the next frame (one start split up to 188 bytes, else two). If the next frame is behind the controller, it starts 2 frames in front and counts an underrun. `hook_usb_wait` sleeps one time (0x11c9fc) for (frames in front − 24) ms. The emulator profile shows that this sleep blocks (the loop 0xa0be0/0xa69b4 takes less than 1.5 % of the CPU). Versions 1.7 and 1.8 waited on an event from the USB interrupt ("interrupt on complete" on the last siTD of each set); the iPod restarted after the tone in both. Version 1.9 copies whole 32-bit stereo frames, without the −12 dB shift (that loop took 19 % of the CPU in the emulator). Versions 1.5 and 1.6 used the sleep 0x11c9fc (1 ms many times, then one time each 12 ms), and the menus were very slow in both.
    8. When `music_mode` is 0, the three hooks call the original functions. Thus the device mode (USB audio to an accessory) is unchanged. After a music stop, the hooks do nothing (the device functions would wait forever).
    9. `music_stop` (version 1.7): when the root port loses its connection (`hook_port_status`) or after 200 siTD errors in a row, it sets the stream off, sets the siTDs inactive, puts the old frame list entries back, sets each siTD link to "end", gives the route back to the codec (+0x59 = 0, 0x1a2fa0, 0x1a2fa8) and signals the event. It logs tag 56.
    10. Version 1.10: `idle_mark` logs the idle time of the CPU (tag 57) from the statistics of the idle routine 0xded04 (RAM 0x14983040: +0 and +8 the idle microseconds of the two cores, 64 bits). Phases: 1 the demonstration before the host start (the baseline), 2 the host mode until the first log, 3 the tone test, 4 the music start, 5 each music status.
    11. Version 1.12 had a trace of ArtworkLoadTask (14 `bl` hooks in 0x205db4, tags 58–60) and a hook on the two calls of 0x1a3080 (tag 61). Version 1.13 removes them: the trace showed that the request queue of the task stays empty. The app still decodes these tags in old logs. The log writes after the start come at most each 5 s.
    12. Version 1.14: `art_state` reads the gates of the art load (re/usb-host.md) and logs two records. It adds no hook. Tag 62: the art cache 0x1bfb74(0x10882b70, 0), its capacity + 0x74, + 0x78 and the bytes + 0x70 to + 0x72. Tag 63: the library open flag + 0x54, the request count, the photo import state (0x19a51c, 0x197e70) and the play queue (RAM 0x1081d9cc). The probe logs them before the host start, after the host start, in host mode, after the audio test and with each later log write. Version 1.15 adds tag 64: the count of the library queue (+0x14 list), the count of the art cache queue (+0x24 list), the count of the cache entries of the library (iterator 0x1e27e0 on +0x3c) and the byte +8 of the art cache entry. Version 1.16 adds tag 65: the ArtworkDB handle (database + 0xd2c and + 0xd14; the database is the app (RAM 0x1081da18) + 0x1c), the app reload flags + 0x484, + 0x489, + 0x48a and + 0x487, and the USB device state (RAM 0x108711d4 + 0x218). Version 1.17 adds tag 66: the first word of the ArtworkDB object (0x6974696c is correct), the count of its entries (list + 0xc), the byte + 6, the index + 0x620, and a test of the lookup 0x9a0f8 for the first entry (the list path, and the index path only if the index exists). Version 1.18 adds tag 67: the probe calls 0x205e64 (the art add step of the art task) for ArtworkDB entry 0 before the host start, entry 1 in host mode and entry 2 at the first later write, and logs + 0x78 and + 0xc before and after. Version 1.18 also had a third action, "Record the Art State Without USB Host" (trigger '3'): the same records without the host start, as a baseline (removed in 1.21). Version 1.19 does not call 0x19ff0c after a log write.
    12a. Version 1.21 removes the art records (tags 62–67), the art test calls and the action "Record the Art State Without USB Host". The app still decodes the tags in old logs.
    12b. Version 1.21, the volume: `volume_start` reads the UAC2 RANGE of the volume control (tag 68) and sets the volume from the iPod output volume (app + 0x40c, 0–256). `volume_poll` (in each wait of USBAudioTask) sends SET_CUR to channels 1 and 2 when the iPod volume changes, without a wait (`control_arm`, `control_check`; tag 69). The curve is 40·log10(v / 256) dB in version 1.21 (too loud) and −48 · (1 − v/256) dB since version 1.27, clamped to the range; v = 0 gives 0x8000 (silence). Versions 1.9–1.20 used a fixed −20 dB.
    12c. Version 1.21, the buttons: `parse_hid` finds the HID interfaces of the configuration. `hid_start` reads their report descriptors (tag 70), finds the bits of the Consumer page usages (volume +, volume −, play/pause, next, previous) and links one periodic queue head for each interrupt IN endpoint (S-mask 0x04, C-mask 0x70, hub 0, port 1) after the siTD of each 8th frame. `hid_poll` (in each wait) logs each changed report with the decoded buttons (tag 71). `music_stop` unlinks the queue heads.
    12d. Version 1.23, the buttons as iPod controls: at each push and release of a button, `buttons_changed` calls 0x1ac198 (code, down, 0), the key function of the front buttons and of the Simple Remote, with the remote key codes 0x20 (volume up), 0x1f (volume down) and 0x1c (play/pause) (tag 72). The UI task makes the key events, the repeats and the volume bar. Version 1.22 posted key events to the app target with 0x13d6d4; they did not reach the key handler.
    12e. Version 1.24, the device task: before the host start, `device_handover` ends the device session with Apple's own stop (the abort flag at RAM 0x108318ec + 5, a wait of at most 2.5 s). While host mode runs, `hook_device_start` (0x170fc8) returns 1 and `hook_device_stop` (0x170fe0) skips the stop, so that the device mode does not take the controller (tag 74; a short high tone at a blocked start). While the probe runs, a computer does not see the iPod.
    12f. Version 1.25, the reconnection: at each music stop the probe takes its control queue head out of the asynchronous ring (`control_unlink`), clears `audio_found` and resets the volume and button state. The first button press after the new enumeration starts the music route again (`hook_event`, UI task). The middle button of the headphones counts its pushes: one is play/pause (0x1c), two the next track (0x1e), three the previous track (0x1d), after 400 ms without a new push.
    12g. Version 1.26, the stop at a disconnection: `hook_port_status` only sets `stop_request`; USBAudioTask stops the route at its next wait, between two sets of packets. If the player played (0x9ba00 = 1), the probe then sends the remote Pause key (0x3c). Tag 75 records the play state. The records of reports, keys and volume requests are limited to 40, 40 and 30.
    12h. Version 1.27: while host mode runs, `hook_usb_message` does not show the USB host messages (error 0x68c "unsupported device" for the card slot and the billboard of the dock); that screen ended the playback at a reconnection. The volume curve is −48 · (1 − v/256) dB (half volume −24 dB); the test tone uses the iPod volume.
    13. Version 1.12: the action "Start the Probe Without Music" writes '2' to the trigger file. Then the probe does not start the music route; the music stays on the headphone jack (a test for the album art).
    14. `hook_event` returns after the music start, so that the owner can play a song. At a later button event, after 5000 more packets, it logs two records (tag 53: packets, underruns, packets with sound, the flags; tag 54: the decoder buffers for the codec and for USB, the queue indices, the flags 0x1081dff6 and 0x1081dff4, the rates; tag 55: the sleeps, the ms in the copy of the probe, the ms in Apple's packet fill (from the end of a wait to the next send), the ms since the music start; the microsecond timer 0x60005010) and writes the log. While the music test runs, the probe logs no other USB records (version 1.6). While the music test runs, the log writes do not dump the queue heads. Version 1.4 wrote the log at almost each wheel event, and the menus were slow.
18. The probe no longer switches the periodic schedule off for 2 s (the "Experiment" of versions before 1.2).
19. The last 96 records of the log (16 before version 1.8) are kept for the audio and music tests and the register records (version 1.3). In version 1.2 the log was full before the audio test.
20. The limits are 200 UIM records, 200 completion records and 40 port records.
21. The probe reads RAM only at addresses in 0x90000000–0x94000000 (the UIM memory, not in the cache, read directly since version 1.3) and 0x10000000–0x14000000 (the same RAM through the cache). Versions before 1.3 read a 0x9xxxxxxx address through 0x1xxxxxxx and sometimes got old cache lines.
22. 10 s after the host start, `hook_event` writes the buffer to the log file and gives two short low beeps. 20 s later, it writes the log again, with two more beeps. The UI does not react during approximately 37 s. A later button or wheel event writes the log again if it has new records. A button event is not sufficient alone: 0x1d81cc gives each event to the active modal screen first (0x12d890, 0x12ddb8) and returns if the screen takes it, for example the photo import screen. On the real iPod, no log was written for this reason. Versions before 1.19 also called 0x1a0120 and 0x19ff0c after each write. 0x19ff0c is not a disk flush (refer to firmware-functions.md), and version 1.19 does not call it. The disk mode start writes the file data to the disk.

**Test status.** Emulator: the demonstration and the countdown had the correct pauses. The host start ran 0x97300 and 0xd1288. The log had two records for the simulated root hub: hub validate and hub initialize device, device 05AC:8031, class 09, power 0xfa (500 mA). The menus worked after this. Real iPod: the host mode sign came. With the 3-in-1 adapter and a card reader, the photo import screen showed "unsupported device", with and without a card. No storage sign. With the dock, the port log showed VBUS valid, a connection, a correct reset and a high-speed device, but no driver call. The full-speed hook is for this result. Later tests (0.1.72–0.1.79) with the dock: the dock's hub, two storage devices and the USB-C EarPods enumerated. With the class change, the composite driver read the configuration of the EarPods (USB Audio Class 2). Caution: the probe reads DMA buffers through the cache, thus a second dump of the same buffer can show old bytes. Refer to [FINDINGS.md](../patches/usb-host-probe/FINDINGS.md). Version 1.2 (isochronous test), emulator: 0xad80c gave memory at 0x93B53000 and 0x93B4A740, the frame list was at 0x93B59000. The emulator has no asynchronous list, thus the control requests stopped at the guard. The 1024 siTDs were linked for 5 s and removed, and the menus worked after this. Real iPod, version 1.2 (2026-10-09): no tone, no audio record. The log was full (511 records), and the first 16 bytes of the EarPods configuration were old cache data. Version 1.3 corrects both. Real iPod, version 1.3 (2026-10-10): the owner heard the 1 kHz tone in the USB-C EarPods. 5105 frames correct, 0 errors; SET_INTERFACE and SET_CUR correct. Version 1.4 (music), emulator: the route switched to USB (+0x5a = 1), and USBAudioTask sent packets through the hooks. The emulator has no audio (a song stays at 0:00 also without the probe), thus the music data cannot be tested there. Real iPod, version 1.4 (2026-10-10): no music, the song stayed at 0:00, the menus were slow. The route and the stream operated (42 204 packets, 0 underruns), but the packets were silence. Cause: the byte 0x1081dff6 (item 17.4). Version 1.5, emulator: the queue indices move, packets with sound arrive, and the player goes to the next songs. Real iPod, version 1.5 (2026-10-10): **the music played through the USB-C EarPods**; the UI was very slow and the album art in Now Playing did not load. Real iPod, version 1.6: the sleeps were exact (14 924 ms requested, 14 991 ms passed), but the UI was still slow, the album art did not load, only 408 of 15 780 packets had sound, and a disconnection and connection of the dock froze the iPod. Version 1.7 blocks on the interrupt event and stops the music when the dock is disconnected. Emulator: the iPod starts and the menus work; USBAudioTask waits for an interrupt that the emulator does not give. Real iPod, versions 1.7 and 1.8: the iPod restarted (Apple logo) after the tone. Version 1.9 removes the interrupt path, copies 32-bit frames and sets the volume on the device. Real iPod, version 1.9: the UI still lags; the CPU record: probe copy 1.1 %, Apple's packet fill 2.8 % of 152 s; 0 underruns; the disconnection and connection of the dock still froze the iPod. Version 1.10 measures the idle time of the CPU in each phase. Emulator: idle 97.8 % in host mode, 97.6 % with the music route. Real iPod, version 1.10: scrolling is correct; the UI stutters only when the album art of Now Playing must show, and the art does not show (the log was reset by a new trigger, thus no idle records). Version 1.11 gives no driver to storage devices. Real iPod, version 1.11: the art still does not load. Idle of core 0: 96.8 % before the host start, 87.0 % in host mode, 57.0 % with the music route before the song, 26.6 % during the song (core 1 72.4 % later). Version 1.12 traces ArtworkLoadTask. Emulator: the trace records come (the wait, the gate granted, the release; no art in the emulator library), and the menus work. Real iPod, version 1.12: the art also does not load when the probe is installed but not started; it loads without the probe; the margin setting does not change it. Version 1.13 removes the trace hooks (the same hook set as 1.11). Emulator: the probe installed and not started: the iPod starts, Now Playing opens. Real iPod, version 1.13 not started: the Now Playing art loads. With the probe started: the art is missing (the owner, version 1.13). Version 1.14 (2026-10-15): in each record the art cache list is empty (+0x78 = 0, +0xc = 0), also when a song plays; the capacity is 0x100000, the library is open, and the photo import state is 1 also before the host start. Version 1.15 (2026-10-15): both request queues are empty, the art cache entry is enabled, and the task runs; thus the art lookup 0x205e64 finds no art. Version 1.16 (2026-10-15): the ArtworkDB handle stays set (0x13df3670) before and after the host start, and no database reload occurs. Version 1.17 (2026-10-15): the ArtworkDB object is correct (first word 0x6974696c, 5218 entries, index set), and the lookup 0x9a0f8 finds the first entry through the list and the index, before and after the host start. Version 1.18 baseline without the host start (2026-10-15): the art is also missing; the test calls of 0x205e64 add the art formats (+ 0x78 0 → 1 → 2 → 3), but the playing song is not added. Thus the cause is not the host mode. Version 1.19 removes the call of 0x19ff0c after each log write. Real iPod, version 1.19 baseline (2026-10-15): **the Now Playing art loads**; + 0x78 grows from 3 to 6 and 8 while songs play. Thus the calls of 0x19ff0c were the cause. Real iPod, version 1.19 in host mode ("Start the Probe Without Music"): **the art loads**; + 0x78 grows from 3 to 7 and 10. A connection to the Mac while host mode runs froze the iPod. Version 1.20 changes only the test steps: wait 15 s after the last button press, then restart the iPod before the connection to the Mac. Real iPod, version 1.20 with the music route (2026-10-15): **the music plays through the USB-C EarPods and the Now Playing art loads**; 80 436 packets (80 s), 0 underruns; + 0x78 grows to 8; the probe copy 1.0 % and Apple's packet fill 2.7 % of the time. Real iPod, version 1.21 (2026-10-16): **the EarPods volume follows the click wheel**, with no gaps; all SET_CUR requests correct; the button reports decode correctly. Real iPod, version 1.22: the buttons did not operate the iPod (the posts did not reach the key handler). Real iPod, version 1.23 (2026-10-16): **all EarPods buttons operate the iPod as expected** (volume +, volume −, play/pause); 0 underruns. Real iPod, version 1.24 (2026-10-16): **no freeze** at a new connection of the dock or of the Mac; the headphones did not operate after the reconnection (the route started only one time). Real iPod, version 1.25: **the headphones operate again after the reconnection**; two and three pushes operate well; the playback stopped completely at the disconnection. Real iPod, version 1.26: **the song pauses at the disconnection**; the headphones start too loud; at the reconnection "unsupported device" ended the playback. Real iPod, version 1.27 (2026-10-16): **all as expected**: no "unsupported device" at a reconnection, the song continues after Play, and the volume levels are good.

## usb-audio-out

**Effect.** Settings has the item "USB-C Audio" (On/Off) after Clicker. Off is the default after each start: the USB port operates as usual (sync, disk mode, charging). On: the iPod operates as the USB host and plays its music through USB Audio Class 2 headphones (for example the Apple USB-C EarPods) through a USB-C dock or OTG adapter with power. The click wheel sets the volume of the headphones. The buttons of the headphones operate the iPod: volume + and −; the middle button one time is play/pause, two times the next song, three times the previous song. A disconnection pauses the song, and after a new connection the music goes to the headphones again. Off gives the port back to the device mode at once. Since version 1.3, Settings > Main Menu has a USB-C Audio row after Sleep. On puts the item "USB-C Audio: Off" in the main menu, after Settings. The default is Off. A selection of the item switches USB-C Audio On or Off. The item shows the state: Off, On, 44.1 kHz or 48 kHz.

**User interface.** Patches pane > Audio > USB-C Audio, letter `u`. The section "Use USB-C Audio" gives the steps.

**Load address.** `extended`. The compiled code and data are 15924 bytes (version 1.9). The control page (8 KB) and the siTDs (32 KB) come from 0xad80c at the first On, the music buffers (12 KB) at the first route start. After the code, the patcher writes three menus: Settings with the new item, the main menu and Settings > Main Menu.

**Option.** "Sample Rate" (`option_rate`): 44.1 kHz (the default) or 48 kHz (version 1.1). `music_start` sends SET_CUR with the rate of the option first, and the other rate if the headphones refuse it. Apple's converter (0x1e2f60) makes the output rate. At 48 kHz a packet has 192 bytes (two start splits). Version 1.2 sends GET_CUR sampling frequency after SET_CUR. The Settings value shows that rate (see below). Caution (version 1.9, the text of the option): make sure that the Sample Rate matches the music in the library. If the rates are different, Apple's rate converter runs; on the real iPod it used about 12 % of core 0, and the scrolling was less smooth.

**Settings item.** Key 0x600060e8, label ID 0x7e06 ("USB-C Audio"), value text IDs 0x7e07 ("On (44.1 kHz)") and 0x7e08 ("On (48 kHz)"), after Clicker (0x60006088), a copy of Sound Check (`settings_items`). The key 0x600060e8 is not a 32-bit word in osos 1.3. The value is in RAM only, thus each start gives Off. While the music goes to the headphones, the value is "On (44.1 kHz)" or "On (48 kHz)" from GET_CUR (version 1.2). If GET_CUR fails, the value shows the rate that the patch sent. Without a music route, or at a different rate, the value is "On". The text changes when the menu shows again.

**Main menu item (version 1.3).** The method of [album-artists](#album-artists), with these values:

| Menu | Template | New label | Key | Place |
|---|---|---|---|---|
| 24094 (main menu) | Backlight (0x5f93) | 0x7e0a | – | After Settings (0xff84) |
| 24600 (Settings > Main Menu) | Sleep (0xff47) | 0x7e06 | 0x60007e09 | After Sleep |

1. The main menu mask bit is 0x80000000. The firmware does not use it, and it is outside the merge mask 0x1fffffff (0xaf838). `album-artists` uses 0x40000000.
2. `hook_menu_bit` replaces the first instruction of 0x105a04 (label → bit; `sub r0, r0, #0x5c00`) with `chain`. The label 0x7e0a gets the bit. The `bl` hooks of `album-artists` at 0x193488 and 0x19353c call 0x105a04, thus both patches operate together.
3. `hook_set_visible` wraps 0x19ed58 with `chain`. When the UI script sets Artists (0x5f7c) in Menu 24094, the patch also sets 0x7e0a from the bit (0x193470).
4. `hook_activate` (vtable slot 0x6776f8, `chain`) sees a selection of the item 0x7e0a. It switches USB-C Audio, calls 0x239f7c(list, row, 0) to draw the row again, and does not call the Backlight action.
5. `hook_lookup` gives the text of 0x7e0a from the state: "USB-C Audio: Off", "USB-C Audio: On", "USB-C Audio: 44.1 kHz" or "USB-C Audio: 48 kHz".
6. Hooks get and set give the row 0x7e09 its value (On or Off from the bit) and its action (0x19351c, then 'Bool'). For other questions, the patch asks the firmware with the key of Sleep (0x5f94).

A copy of the Settings row (Sound Check) in the main menu is not usable: in the emulator the highlight did not stop on it.

**Hooks.**

| Kind | At | Expect | To | Chain | Function |
|---|---|---|---|---|---|
| `b` | 0x21f254 | 0xe92d40f8 | `hook_lookup` | `lookup_next` | The label "USB-C Audio", the value texts and the main menu text |
| `b` | 0x105a04 | 0xe2400b17 | `hook_menu_bit` | `menu_bit_next` | The main menu bit 0x80000000 for 0x7e0a |
| `b` | 0x19ed58 | 0xe92d401c | `hook_set_visible` | `visible_next` | The main menu item is visible from the bit |
| `word` | 0x6776f8 | 0x0023ca4c | `hook_activate` | `activate_next` | A selection of the main menu item switches On or Off |
| `word` | 0x66c94c | 0x00190b00 | `hook_settings_get` | `get_next` | On or Off (0x602e, 0x602f) |
| `word` | 0x66c950 | 0x001919d8 | `hook_settings_set` | `set_next` | Changes the value, makes the task "USBAudioOut" at the first change, sends 'Bool' |
| `bl` | 0xd399c, 0x10c204, 0xe2be0 | 0xeb0018d2, 0xebff36b8, 0xebffdc41 | `hook_usb_message` | | No USB host message while host mode runs |
| `bl` | 0x170fc8, 0x170fe0 | 0xeb0370fd, 0xeb03712d | `hook_device_start`, `hook_device_stop` | | No device session start or stop while host mode runs |
| `bl` | 0xb9614 | 0x0b032c84 | `hook_mode_stop` | | The USB mode task does not stop host mode at a new VBUS while USB-C Audio is On |
| `bl` | 0xd33b0 | 0xeb0693cf | `hook_host_receive` | | Version 1.4: while the route runs, the USB host task waits at most 8 ticks for a message, not 1 tick |
| `bl` | 0x1320d4, 0x132154 | 0xeb02c3e2, 0xeb02c3c2 | `hook_fill` | | Version 1.9: the fast fill of the packets at equal rates |
| `bl` | 0xd28f0, 0x10e75c | 0xeb005422, 0xebff6487 | `hook_port_status` | | A disconnection stops the route (in USBAudioTask) |
| `bl` | 0x97364 | 0xeb073d0a | `hook_chip_check` | | Full speed while host mode runs |
| `bl` | 0x9741c | 0xeb03cd13 | `hook_irq_install` | | The host interrupt handler while host mode runs; else Apple's 0x18a870 |
| `bl` | 0x9761c, 0x96d14 | 0xeb017997, 0xeb017bd9 | `hook_periodic_insert` | | The periodic insert fix (r1 = r0) |
| `bl` | 0x1320fc, 0x13217c, 0x13218c, 0x1321d0 | as `usb-host-probe` | `hook_usb_send`, `hook_usb_wait_if_sent`, `hook_usb_wait` | | The music route in USBAudioTask |
| `b` | 0xcb118 | 0xe92d40fe | `hook_completion` | | The configuration of a new device (`track_call`) |
| `word` | 0x6c882c, 0x6c8830 | 0x00096f64, 0x00096ffc | `hook_uim_control_endpoint`, `hook_uim_control_transfer` | | The control transfers for `track_call` |

**Logic.**

1. The Settings "set" hook changes `audio_wanted` and returns at once. The task "USBAudioOut" (0x11c808, priority 0x20) does the change.
2. On: the USB mode manager stops the device mode (mode 1; the patch waits at most 2.5 s for Apple's stop of the session while VBUS is present). The patch sets `host_running` and the settings of the host stack (hubs allowed, the composite class EF/02, no storage driver), and the manager starts the host client (mode 2), which starts the host stack.
3. When the headphones are enumerated (`find_audio`, `parse_hid`), the task starts the music route (`music_start`: SET_INTERFACE, the sample rate, the volume, the HID polling, the siTDs, Apple's USB audio source). After a disconnection and a new connection, the route starts again in the same way.
4. The code of the route, the volume, the buttons, the pause at a disconnection and the device hooks is the code of `usb-host-probe` 1.27, without the log, the tones and the test tone.
5. Off: USBAudioTask stops the route (the song pauses), the manager stops the host client (Apple's host stop 0x28608c), the patch restores the settings of the host stack, and the manager starts the device mode if USB power is present.
6. Version 1.4: fewer wakes while the route runs. Apple's USB host task (0xd3390) waits at most 1 tick for a message (0x2782f4), then polls the host stack (0xb9004): about 1000 times each second. `hook_host_receive` gives 8 ticks while `music_mode` is set: about 125 polls each second. A message ends the wait at once. `music_wait` sleeps only above 40 frames in front (`AHEAD_HIGH`), thus USBAudioTask makes two sets of 12 packets in each wake: about 41 wakes each second, not 83.
7. Version 1.9: a fast fill. `bl` hooks at 0x1320d4 and 0x132154, the two calls of Apple's fill 0x1e3064 in the stream loop, go to `hook_fill`. While the route runs, without the test signal (source + 1), and when the input rate (source + 4) equals the output rate (source + 0xc), it does the steps of 0x1e3064 and 0x1e2c90 with word loops: a pool buffer (0xd3e70), the check 0x1e2f74, the frames from the 6-entry queue, the decoder buffer back (0xfed68). Else (the option 48 kHz with a 44.1 kHz song) it calls 0x1e3064, and Apple's rate converter runs. The measurement builds 1.5–1.8 of the branch `usb-audio-speed` (the task "USBMeasure" and the tags 76–78 in iPodFirmUSBLog) are in [re/usb-host.md](../re/usb-host.md#the-slower-scrolling-with-usb-c-audio-on-2026-10-17); version 1.9 does not have them.

**Conflicts.** `usb-host-probe` uses the same hook sites (17 hooks without `chain`). The app does not turn on both (`Patcher.conflicts`; the Patches pane shows "Changes the same place as …"), and a build with both stops at the first shared hook. The test `testUSBAudioOutConflictsWithProbe` keeps this.

**Test status.** Swift and Python tests pass (also with the IPSW). Emulator (2026-10-17): Settings shows "USB-C Audio" Off after Clicker; On and Off change the value; the iPod does not freeze, and the wheel and Now Playing operate after On. After the first Off, the emulator runs at about 0.2× real time: Apple's UIM stop (0x97230) waits with no limit for HCHalted, and the emulator has no USB controller. On the real iPod, Off works. Real iPod, version 1.0 (2026-10-17): **all test steps passed** (the owner: "flawlessly"): Off after the start and a sync; On with the dock and the EarPods, the music without a button press, the volume and the buttons; a pause at a disconnection and Play after a reconnection; Off, then the Mac sees the iPod; On, Off, On again. The iPod charges from the dock while USB-C Audio plays. Version 1.1 with the option 48 kHz: tested on the real iPod (2026-10-17). The owner heard no problems. Version 1.1 kept no log, so the accepted rate was not known. Version 1.2 shows the rate in Settings: not tested yet. Emulator, version 1.3 with `album-artists` 1.3 and `instant-save` (2026-10-17): Settings > Main Menu showed "USB-C Audio" Off after Sleep; On put "USB-C Audio: Off" in the main menu after Settings; a selection changed it to "USB-C Audio: On" at once, and a second selection to Off. Real iPod, version 1.3: not tested yet. Emulator, version 1.4 (a variant with the condition On in place of the route, because the emulator has no USB device): the host poll interval was 8.17 ms (1.02 ms before); the busy instructions with On were 300 M in 30 s (364 M before, 298 M with Off); the menus operated, and Off gave Off. Real iPod, version 1.4 (2026-10-17): still stuttery while USB music plays. The owner's comparison: music through the headphone jack is smooth; On with the music paused is smooth; USB music at 48 kHz and at 44.1 kHz stutters. Emulator, version 1.5: one timing record each second reached the log file. Real iPod, version 1.5 (2026-10-17): the measurement is in [re/usb-host.md](../re/usb-host.md#the-slower-scrolling-with-usb-c-audio-on-2026-10-17). Core 0 idle without scrolling: jack music 58–60 %, USB music 42–44 %, USB route paused 78 %, Off paused 94 %. The longest fill of 12 packets in Apple's code was 1.7–2.6 ms. Emulator, version 1.6: both records each second reached the log (0 USB interrupts, about 980 timeouts of the host task each second without the route). Real iPod, version 1.6 (2026-10-17): 1 USB interrupt each second (the frame list rollover), 0 siTD errors, the host task 90–120 timeouts and no messages each second, and Apple's packet fill about 129 ms in each second (13 % of core 0), with the music playing and paused. Real iPod, version 1.7 (2026-10-17): the sound was correct, the scrolling was not better, and the log had no packet of the fast fill (the fill still about 130 ms each second): `hook_fill` always called Apple's fill. Probable cause: the converter flag. Real iPod, version 1.8 (2026-10-17): the sound correct, the scrolling not better; the option Sample Rate was 48 kHz, thus the converter must run (input 44100 Hz, output 48000 Hz, Apple's fill about 122 ms each second). Real iPod, version 1.8 at 44.1 kHz (2026-10-17): the fast fill made all packets, the fill about 28 ms each second (about 130 ms before), core 0 idle without scrolling 51–55 % (before 42–44 %, the jack 58–60 %); the sound correct; the owner: the scrolling better. Version 1.9 (the fast fill without the measurement), real iPod (2026-10-17): the iPod did not find the headphones and the hub of the dock; after a new connection and On again, the iPod crashed. The cause is not known yet. The versions 1.4–1.8 were not tested with a disconnection and a new connection.

## volume-unlimit

**User interface.** Patches pane > Sound > No EU Volume Limit, letter `v`. The pane shows a caution about hearing damage.

**Effect.** On an iPod for the EU, the full position of the volume control gives the full volume. Without the patch, it gives 84% of the full volume. On other iPods, the patch changes nothing. The setting Settings > Volume Limit continues to operate.

**Research.** Refer to [re/volume-limit.md](../re/volume-limit.md).

- `0xa0348` returns bit 0 of the flags word +0x94 of the device information object (0x108710dc). This bit is the EU limit.
- The settings load `0xaf698` writes the maximum volume to its object at +0xb78: 0xd8 (216) with the limit, 0x100 (256) without it.
- `0x88ff8` calculates the output volume as `level × maximum / 100`.
- The iAP reply 0x25 (`0x1a3254`, case 0x24) tells an accessory if the limit is set.

**Change.** This patch has no C code. It uses the `bytes` key of `patch.json`. It is the same change as goPod and iPodWizard:

| At | Expect | Value | Instruction after the change |
|---|---|---|---|
| 0xa0350 | `0100` | `0001` | `and r0, r0, #0` |

Thus `0xa0348` always returns 0. The other match of the iPodWizard pattern, at 0x9f0f8, is a different function. The patch does not change it.

**Test status.** A script applied the change to osos 1.3 and ran the iPodWizard search: "capped" before, "uncapped" after. The emulator cannot show the effect. Not tested on a real iPod. The test needs an iPod for the EU.

## something-comforting

**User interface.** Patches pane > Fun > Something Comforting, letter `m`. The section "Play the Melody" gives the steps on the iPod. This patch is an example of a patch that adds a Settings item and that shares its hooks with other patches.

**Effect.** Settings has a Something Comforting item after Clicker. Its value text is "Play". When the owner selects the item, the piezo plays a part of "Something Comforting" by Porter Robinson: the synth lead, bars 41–48, approximately 13 s. The UI does not react while the melody plays. The Clicker setting does not stop the melody.

**Load address.** `extended`. The compiled code and data are 692 bytes (alone: 0x736800–0x736ab4). After the code, the patcher writes the Settings menu with 19 items (764 bytes; alone at 0x737000). The osos then ends at 0x737800.

**Settings item.** Key 0x600060e4, label ID 0x7e01, after Clicker (0x60006088), a copy of Sound Check (`settings_items`, refer to [patch-system.md](patch-system.md#settings-items)). The key 0x600060e4 is not a 32-bit word anywhere in osos 1.3. Ghidra found no use of 0x7e01 and 0x7e02.

**Hooks.** All three hooks have `chain`. With "Switch on iPod", they replace the Dark Mode hooks and call them for all other keys and IDs.

| Kind | At | Expect | To | Chain |
|---|---|---|---|---|
| `b` | 0x21f254 | 0xe92d40f8 | `hook_lookup` | `lookup_next`; default `lookup_original` (`push {r3-r7, lr}`, then 0x21f258) |
| `word` | 0x66c94c | 0x00190b00 | `hook_settings_get` | `get_next` |
| `word` | 0x66c950 | 0x001919d8 | `hook_settings_set` | `set_next` |

**Runtime logic.**

1. `hook_lookup` returns "Something Comforting" for 'Str ' 0x7e01 and "Play" for 'Str ' 0x7e02. For all other lookups, it calls `lookup_next`.
2. `hook_settings_get` gives the value text ID 0x7e02 ('prID') or the text "Play" ('Str ') for the key 0x60e4.
3. `hook_settings_set` plays the melody for the key 0x60e4. For each entry of the note table, it calls `tone` (0xcd430) with the period and the duration. Then it waits with the task sleep 0x11c9fc until the start of the next entry. The time comes from `USEC_TIMER` (0x60005010).
4. A rest is only a wait: when a note ends and the queue is empty, the piezo task stops the piezo (refer to [re/piezo.md](../re/piezo.md)).

**Note table.** [re/midi-to-tones.py](../re/midi-to-tones.py) makes the table from a MIDI file: track 6 (Flute), bars 41–48, the highest note at each time. 74 entries (37 notes), 12912 ms. The MIDI file is not in the repository.

**Test status.** Emulator (2026-10-08): the Settings menu showed "Something Comforting" with "Play" after Clicker. Select called the set hook one time and `tone` 37 times for the notes. The times between the notes agreed with the table within approximately 10 ms. The menus worked after the melody. The emulator has no audio. Not tested on a real iPod.

## album-artists

**User interface.** Patches pane > Display > Album Artists, letter `l`. The section "Use the Album Artists List" gives the steps on the iPod. The design comes from osos-lab (RepriseOS) for the iPod Classic. The research is in [re/album-artist.md](../re/album-artist.md#album-artists-menu-item-15-october-2026).

**Effect.** The Music menu has an Album Artists item after Artists. It opens a list with one row for each Album Artist, in alphabetical order. A song without an Album Artist is under its Artist. A row opens the albums and the songs of that Album Artist. The Artists list, Now Playing and the sort indexes of the database do not change. The list has no letters for the fast scroll. Since version 1.2, Settings > Main Menu has an Album Artists row under Music. On puts Album Artists in the main menu. The default is Off.

**Load address.** `extended`. The compiled code and data are 3688 bytes (alone: 0x736800–0x737668). After the code, the patcher writes three menus: the Music menu with 11 items (444 bytes; alone at 0x737800), the main menu with 32 items (1284 bytes; at 0x738000) and Settings > Main Menu with 29 items (1164 bytes; at 0x738800). The osos then ends at 0x739000.

**Menu items** (`menu_items`, refer to [patch-system.md](patch-system.md#menu-items)). The copies open the Artists screen, because the firmware finds the action of an item in the item data.

| Menu | Copy of | New label | Key | Position |
|---|---|---|---|---|
| 24440 (Music) | Artists (0xff82, -126) | 0x7e03 | – | After Artists |
| 24094 (main menu) | Artists (0x5f7c) | 0x7e03 | – | After Artists |
| 24600 (Settings > Main Menu) | Artists (0xff5e, -162) | 0x7e04 | 0x60007e05 | After Artists |

**Hooks.**

| Hook | Kind | At | Expect | To | Chain |
|---|---|---|---|---|---|
| A | `b` | 0xd7ea0 | 0xea0000d1 | `hook_mhod22` | – |
| B | `bl` | 0xafc8c | 0xeb009efd | `hook_load_tracks` | – |
| C | `word` | 0x6776f8 | 0x0023ca4c | `hook_activate` | `activate_next` |
| G | `b` | 0x1e7b98 | 0xe92d4010 | `hook_reset` | – |
| H | `b` | 0xa34b8 | 0xe92d4070 | `hook_clear` | – |
| K | `b` | 0x19ed58 | 0xe92d401c | `hook_set_visible` | `visible_next`; default `visible_original` (version 1.3) |
| D | `b` | 0xd080c | 0xe92d5fff | `hook_build` | – |
| E | `bl` | 0x114354 | 0xebfe2d6a | `hook_filter_text` | – |
| L | `word` | 0x66c94c | 0x00190b00 | `hook_settings_get` | `get_next` |
| M | `word` | 0x66c950 | 0x001919d8 | `hook_settings_set` | `set_next` |
| I | `bl` | 0x193488 | 0xebfdc95d | `hook_menu_bit` | – |
| J | `bl` | 0x19353c | 0xebfdc930 | `hook_menu_bit` | – |
| F | `b` | 0x21f254 | 0xe92d40f8 | `hook_lookup` | `lookup_next`; default `lookup_original` (`push {r3-r7, lr}`, then 0x21f258) |

The `b` hooks G, H, K and D replace the first instruction of a function. Each has a wrapper in the patch that runs the replaced `push` and continues at the next instruction.

**Runtime logic.**

1. Hook A replaces the mhod 22 (Album Artist) entry of the jump table of the track parser. Apple's code skips this string. The patch reads it into the artist string pool (track data + 0xe0) with 0x10db84, into a slot on the stack. If the text is not empty and not the text of the Artist (track + 0x2c), `aa_store` keeps the index in a side table. Each track has its own pool index, also for the same text, thus `aa_store` compares the texts. Then the loop continues at 0xd821c.
2. The side table uses open addressing. The key is the track pointer. It grows at 3/4 full (`fw_alloc` 0x25a974). Hook B clears it before each call of the track parser 0xd7888, thus before each load of the database.
3. Hook C is the `activate` method of the menu lists (vtable 0x6775b8 + 0x140). For a list with menu data (list + 0x144), it gets the item of the row with 0x2183ec. If the label of the item is 0x7e03, `aa_pending` is 1. For all other items, `aa_pending` and `aa_browser` are 0. Composers, Genres and Playlists do not run the reset 0x1e7b98, thus this clear is necessary.
4. Hook G is the browser reset 0x1e7b98 at the start of a browse. If `aa_pending` is 1, the native browser of the browse (JS browser + 0x1c) becomes `aa_browser`, and `aa_pending` becomes 0. A reset without a pending selection does not change `aa_browser`, because the main menu item runs the reset two times. Album artist mode is `browser == aa_browser`.
5. Hook D wraps the list build 0xd080c. For field 4 (Artist) and the browser `aa_browser`, `build_album_artists` collects the tracks of sort list 7 that pass the filter 0x1142a8. It takes the Album Artist index of each track, or the Artist index. It removes the same texts with an FNV-1a hash (one pass), sorts the unique names with the text compare 0x91c7c (a heap sort), and joins the names that compare as equal. It writes the indexes to browser + 0xc48, 0 to + 0xc4c (no letter table) and the count to + 0xc50, and keeps the list in `aa_list`. The native code then shows the names (0x9cabc) and selects a row (0xb2620).
6. The browser keeps one Artists list. If the list is not of the current mode, hook D clears it first (0xa34b8). Hook H wraps 0xa34b8: if it frees `aa_list`, `aa_list` becomes 0. With the build, 0xa34b8 is the only code that writes browser + 0xc48, thus `aa_list` is exactly the list of the patch.
7. Hook E replaces the call of the Artist text in the filter. A wrapper passes r5 (the browser). For `aa_browser`, the filter compares the selected name (browser + 0x228) with the Album Artist of the track. The Albums and Songs levels then show the songs of the Album Artist.
8. Hook F gives "Album Artists" for 'Str ' 0x7e03 (the label), U+2003 U+2060 "Album Artists" for 'Str ' 0x7e04 (the indented Settings row, as Str -162), and "Album Artists" for 'Str ' -30 (the title of the Artists screen) while `aa_browser` is set. For all other lookups it calls `lookup_next`.
9. The main menu mask is at (main browser + 0xca0) + 0xb34. Hooks I and J replace the two calls of 0x105a04 (label → bit): the label 0x7e03 gets bit 0x40000000. The firmware does not use this bit, and the default mask (0x0e180201 in the emulator) does not have it.
10. Hook K wraps 0x19ed58 (show or hide an item of a menu). The UI script calls it for each Apple item of the main menu at the start and each time the main menu shows. When it sets Artists (0x5f7c) in Menu 24094, the patch also sets 0x7e03 from the bit (0x193470). Since version 1.3, hook K has `chain`, because `usb-audio-out` 1.3 also hooks 0x19ed58.
11. Hooks L and M give the Settings row its value and its action. The key 0x7e05 is not a label ID, because the list asks the value text with the resource lookup ('Str ', key), and hook F answers the label IDs first. For 'prID' and 'Str ', hook L gives On (0x602e) or Off (0x602f). For all other questions it asks the firmware with the key of Artists (0x5f7c). Hook M switches the bit with 0x19351c and sends the 'Bool' notice (settings method +0x54), as the firmware does at 0x192774.

**Limits.**

- A sync changes the Album Artists only after the iPod reads the database again (as for all lists).
- "Compilations" in Settings does not hide the compilations in the Album Artists list.
- The list has no letter table. The fast scroll operates as with a database without mhod 53.
- The emulator keeps no settings after a cold start. Thus the save of the Main Menu bit is not tested in the emulator.

**Test status.** Emulator (2026-10-16), the 7-track library of the [emulator test](../re/album-artist.md#emulator-test-6-october-2026):

- Music showed Album Artists after Artists.
- Album Artists showed All, Aardvark, Bravo, Echo and Various Artists, with the title "Album Artists".
- Various Artists showed the 3 songs of Zeta Hits. Aardvark showed Apple One and Apple Two.
- After this, Artists showed the 8 track artists. Mike Moe showed only Comp Two.
- Now Playing showed the track Artist (Zulu feat. Kilo) and "2 of 2".
- Genres > Test showed the 8 track artists.
- With `album-art`, `cover-flow` and `something-comforting`, Album Artists and the Settings item "Something Comforting" operated.

Real iPod (owner, 16 October 2026), version 1.0: the Album Artists item showed, and the list was correct. But the iPod stopped for approximately 6 seconds when Album Artists opened.

Version 1.1 corrects the speed. Emulator (2026-10-16), 4000 tracks: the first open after a start took 0.95 s (0.85 s of it is the firmware sort of the Artist order, as for the native Artists list), and each later open 0.11 s (the native Artists list: 0.12 s). Version 1.0 took 1.6 s for each open. The 7-track library gave the same results as version 1.0. Refer to [re/album-artist.md](../re/album-artist.md#speed-16-october-2026).

Real iPod (owner, 16 October 2026), version 1.1: works well.

Version 1.2, emulator (2026-10-16):

- Settings > Main Menu showed "Album Artists" after Artists, with Off. A selection changed it to On.
- The main menu then showed Album Artists after Videos. Before, it did not show it.
- The main menu item opened the Album Artists list. Various Artists showed the 3 songs of Zeta Hits.
- After this, Music > Artists showed the 8 track artists, Music > Album Artists showed the Album Artists, and Genres > Test showed the 8 track artists.
- 4000 tracks: the first open took 0.95 s, a later open 0.10 s (the same as version 1.1).

Real iPod (owner, 16 October 2026), version 1.2: after Settings > Main Menu > Album Artists = On and a restart with Menu+Select, the item was off again. The Apple row Songs had the same result. The firmware saves the settings only at a sleep or a disk change, not at each change (refer to [re/album-artist.md](../re/album-artist.md#the-save-of-the-settings-real-ipod-16-october-2026)).

## instant-save

**User interface.** Patches pane > Power > Instant Save, letter `i`. The section "Test the Save" gives the steps on the iPod.

**Effect.** The iPod writes its settings at once when the owner changes a row in Settings > Main Menu. This includes the Album Artists row of [album-artists](#album-artists). The other settings (for example Shuffle and Repeat) still save only at a sleep.

**Cause.** The setter 0x19351c changes the main menu mask and sets the byte "changed" (settings data + 0xb74). The firmware writes the settings only at a sleep (0x1ee8d0) or at a save of all data (0xbc094, for example at a disk change). A restart with Menu+Select runs no save. Refer to [re/album-artist.md](../re/album-artist.md#the-save-of-the-settings-real-ipod-16-october-2026).

**Load address.** `extended`. The compiled code is 36 bytes (alone: 0x736800–0x736824). In a build with other patches, it starts directly after the patch before it (16-byte steps), thus it adds approximately 36 bytes.

**Hooks.**

| Kind | At | Expect | To |
|---|---|---|---|
| `b` | 0x19351c | 0xe92d41f0 | `hook_set`; wrapper `set_original` (`push {r4-r8, lr}`, then 0x193520) |

**Runtime logic.**

1. The firmware rows (0x192794) and the Album Artists row of `album-artists` call the setter 0x19351c.
2. `hook_set` runs the original setter, then calls 0xbbf1c with the settings data ((settings + 0x98) + 0xca0).
3. 0xbbf1c writes the settings only if the byte "changed" is set. Thus a selection that changes nothing writes nothing.

**Limits.** Each change writes the settings file. On an iPod with a hard drive, the drive can start.

**Test status.** Emulator (2026-10-16), with `album-artists`: a change of the Songs row and of the Album Artists row each ran 0xbbf1c and the write 0xbbdf8 one time. A change of Playlists gave the ATA commands WRITE DMA (0xca) and READ DMA (0xc8). The emulator keeps no settings after a cold start, thus the result after a restart is not tested. Not tested on a real iPod.

## Storage type

The two flash patches are not for the original hard drive. iPodFirm does not read the storage model. It uses the size of the iPod disk:

- `IPodDisk.likelyOriginalHDD` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift) returns a size if the disk is within 5 GB of 30, 60 or 80 GB.
- Then the Patches pane shows a warning (`hdd_warning`), and asks for a confirmation before it switches on the patch.
- A flash card of a near size (for example 64 GB) also gives the warning. You can then switch on the patch.

An earlier version read the ATA IDENTIFY data in the firmware (a hook at 0x142f94). It was removed on 6 October 2026 to free 205 bytes.

## Dark theme

**User interface.** Patches pane > iPod Appearance:

- "Import iPodWizard Theme…" (also in the File menu).
- The appearance control: Light, Dark or Switch on iPod.
- The "Dark theme" picker, "Show Import Report" and "Delete Theme…". "Delete Theme…" asks for a confirmation.

**Source.** An iPodWizard theme is a complete firmware partition for an older firmware, usually 1.2.1. iPodFirm needs the theme and the Apple firmware that the theme came from ("base"). The target is always the Apple firmware 1.3. Refer to [re/dark-theme.md](../re/dark-theme.md).

**Import.** `ThemeImport.make` in [ThemeImport.swift](../mac/Sources/IPodFWKit/ThemeImport.swift) does these steps:

1. It makes sure that the theme and the base are different, and that 90 % of the resources have the same size. Otherwise the base is not the correct firmware.
2. It records program code changes as "skipped". It never applies them.
3. It maps the resources of the base to the resources of the target (`idMap`):
   - Pass 1: the same ID with the same data, or the only resource within ±8 IDs with the same data.
   - Pass 2: the shift of the nearest mapped resource of the same type.
4. For each changed resource, it makes a list of byte changes (`ThemeChange`: offset, old bytes, new bytes):
   - **BMap** with the same header: the changed pixel runs.
   - **BMap** that the theme made larger: the picture goes into the free area after the end of osos, below 0x7F8000 (`ThemeImport.ososLimit`). If all pixels are grey, iPodFirm stores a 4-bit grey copy. Then the resource table entry gets the new offset and size.
   - **View**: the changed fields of each element. A field changes only if the target has the base value. The import translates the resource IDs in the fields.
   - **Type**: each changed 32-bit word, only if the target has the base value.
   - Other types (for example `TCmd` and `Menu`): skipped.
5. It writes the theme file `~/Library/Application Support/iPodFirm/Themes/<name>.ipodtheme` (JSON, format 1).

**Rules when the theme is applied.**

- Each change is applied only if the bytes are the old bytes. If they are already the new bytes, the change counts as done. Other bytes are an edit of the owner, and the change is left out.
- Pictures 24342 and 24343 (the progress bar in Now Playing) keep the Apple version (`keepApple`). The dark themes make them almost invisible.
- The highlight bar keeps the Apple blue colours `0xFFD06428` and `0xFFE89858` (`appleHighlight`). The grey bar of the theme was difficult to see on the real iPod.

### The View format

A View is a u32 count and a list of elements. Each element has this layout:

| Offset | Content |
|---|---|
| +0 | u32: element size − 4 |
| +4 | u32: flags |
| +8 | Tag, byte-reversed: "BMap", "Str ", "None", "Draw", "Cntl" or "StSt" |
| +12 | i16: resource ID. "BMap" and "Draw" refer to a picture, "Str " to a string, "None" to a sub-View. |
| +60 | u32: height |
| +76, +80 | Colours of the highlight bar (ABGR). Apple 1.3: `0xFFD06428` and `0xFFE89858`. |
| +84 | In a "Str " element: the high i16 is a Type ID (text style). |

Facts from the research:

- View 24069 is the root of the screen. View 24506 is the title bar.
- The theme changes element 0 of View 24506 from `BMap 24379` to `Draw 21997` with a height of 240. Thus the background picture fills the screen behind the list.
- A `Draw` element shows the picture at its own size. It does not stretch or repeat the picture.

### The Menu format

A Menu is a u32 count and items of 40 bytes. +0x18 is the label string ID. +0x1C is the key that the item sends (for example 0x600060b7, Sound Check). [re/backlight-timer.md](../re/backlight-timer.md) gives the full item layout.

### Edits of the dark theme

In the Pictures pane, the "Dark Theme" switch shows the theme pictures. "Replace…" on a theme picture stores the new pixels in the `edits` list of the theme file. An edit replaces each theme change in the same bytes. "Use Theme Picture" removes the edit. The light pictures do not change.

**Limits.**

- 23 Views have fields that do not agree with 1.3. The import report lists them.
- The rating stars in Now Playing stay almost invisible. The source of the star colour is not found.
- The theme 1.2.1 code changes (6 `nop` at (address removed)–(address removed) in 1.3) remove a file key check. They are not a part of the theme, and iPodFirm does not apply them.

**Test status.** Tested on a real iPod 5.5G on 2 October 2026, with and without `album-art`.

## Dark Mode switch

**User interface.** Patches pane > iPod Appearance > Switch on iPod. On the iPod: Settings > Dark Mode.

**Effect.** The firmware starts light. The Dark Mode item changes between light and dark. The iPod saves its settings and restarts.

**Why a restart is necessary.** RetailOS makes its main screens one time, at the start, from the View resources. The views copy the positions, the heights and the colours when the firmware makes them (`FUN_0021a4f4`). A language change does not make the screens again. Thus the patch applies the dark changes at the start, before the first View is read.

**Build.** `DarkMode.build` in [DarkMode.swift](../mac/Sources/IPodFWKit/DarkMode.swift) puts these items after 0x736800, below 0x7F8000:

1. The theme data outside osos (for example the background picture). It is in the image for both modes.
2. The switch table, aligned to 16 bytes.
3. The new Settings menu (Menu 24598), aligned to 16 bytes. The resource table entry points to it.
4. The code of the `dark-mode` patch, aligned to 16 bytes. The build gives the symbol `dark_table` the address of the switch table.

The switch table has this format (little-endian):

| Field | Content |
|---|---|
| u32 | `IFDM` (0x4D444649) |
| u32 | Count N |
| u32 | Offset of the data, from the start of the table |
| N × {u32, u32} | {osos address, length} |
| data | For each change: old XOR new |

The XOR data switches the bytes in both directions. A change that the owner edited is left out.

**Size.** Patches pane > iPod Appearance > Dark Theme shows the new space for each appearance:

- "Size on iPod (Dark)": the theme data after 0x736800 (`ImportedTheme.addedSize`).
- "Size on iPod (Switch on iPod)": items 1 to 4 above, with the alignment (`DarkMode.addedSize`). It needs the open firmware 1.3.

The text below the two values gives the bytes inside osos that the theme changes (`ImportedTheme.changedSize`). These changes use no new space. The measured values for the theme "Dark Gray" are 38,428 bytes (Dark), 738,593 bytes (Switch on iPod) and 660,678 changed bytes. The limit of the area is 792,576 bytes (0x736800–0x7F8000; 759,808 bytes before 9 October 2026). The test `testExtendedPatchAfterSwitchBuild` makes sure that `DarkMode.addedSize` agrees with `DarkMode.build`.

The new Settings menu is a copy of the Apple menu with one more item after Clicker (key 0x60006088). The new item is a copy of the Sound Check item (key 0x600060b7) with the key 0x600060e0 and the label ID 0x7e00.

**Hooks.**

| Kind | At | Expect | To | Function |
|---|---|---|---|---|
| `b` | 0x21f254 | 0xe92d40f8 | `hook_lookup` | First instruction of the general resource lookup |
| `word` | 0x66c94c | 0x00190b00 | `hook_settings_get` | "Get" method of the settings object |
| `word` | 0x66c950 | 0x001919d8 | `hook_settings_set` | "Set" method of the settings object |

**Runtime logic.**

- `hook_lookup`, at the first lookup of a `View`: read `iPod_Control\iTunes\iPodFirmDarkMode`. If the first byte is `1`, apply the switch table.
- `hook_lookup`, for `Str ` with ID 0x7e00: return "Dark Mode".
- `hook_lookup`, all other lookups: run `push {r3-r7, lr}` and continue at 0x21f258.
- `hook_settings_get`, for key 0x60e0: return the string "On" (0x602e) or "Off" (0x602f) for the operations `prID` and `Str `.
- `hook_settings_set`, for key 0x60e0:
  1. Write the other value to the file (open for read and write, 0x08f3f8). The open function makes the file if it does not exist.
  2. Save all settings (0x1ee8b8 with the application object at 0x1081da18).
  3. Prepare a restart (0x094e08).
  4. Restart (0x001630). This writes 4 to `DEV_RS` (0x60006004).

**Test status.** Emulator: the item changed the mode in both directions, and the settings were kept. The same result came without the file on the disk. The Swift build and the Python build give the same osos. Not tested on a real iPod.

## Move of rsrc

**When.** The dark theme and the Dark Mode switch make osos larger than 0x736800. In Apple's layout, rsrc starts there.

**Change.** `FirmwarePartition.makeRoom` in [Partition.swift](../mac/Sources/IPodFWKit/Partition.swift) does this:

- **iPod partition** (it has hibe): copy rsrc to the first free space after the last image, aligned to 0x800. The space must be all zero. aupd and hibe do not move.
- **Firmware file** (no hibe and no free space): move rsrc and all images after it forward by the same aligned value. The file becomes longer.

Then the function writes the new devOffset into the rsrc directory entry. The content of rsrc does not change.

**Flash.** A firmware file has aupd at a different position than the iPod. `FirmwareFlasher.fitLayout` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift) puts the new osos and rsrc into the layout of the iPod. On the iPod, aupd never moves.

**Ghidra result.** RetailOS finds rsrc through the directory, by its type and ID. The code loads the tag `crsr` at 0xaf548 and 0x1afe44. Both call 0xfc3bc, which calls 0xc60ec. 0xc60ec reads the directory and selects the entry by type (+4) and ID (+8), not by its index. Rockbox `ipodpatcher` also moves rsrc.

**Test status.** Tested on a real iPod 5.5G on 2 October 2026.

## row-marker (removed)

The project removed this test patch on 2026-10-08. The last commit with the patch is a87c3fa. To get it back, run `git checkout a87c3fa -- patches/row-marker`.

The patch drew a red bar, 6 pixels wide, at the left of each label. It showed that the compiler, the linker, the hooks and the draw functions operate. It used the load address 0x7358d0, the same address as `album-art`. Its hooks were a `bl` at 0x1bb434 (expect 0xeb02253a) and the vtable word 0x677a14 (expect 0x00244924), both to `hook_label_draw`. The hook called the label draw 0x244924, then filled a red rectangle with 0x255ac4 (bounds), 0x2106e4 (colour), 0x210290 (mode) and 0x211a00 (fill). `build-app.sh` did not copy it into the app. The tests now use `album-art` for the load address test and a copy of `album-art` for the conflict test.

## Proposed: USB audio

This change does not exist yet. The research found a USB Audio Class 1 source in firmware 1.3. The stock firmware enables it only for an iAP accessory with the Digital Audio lingo. Refer to [re/usb-audio.md](../re/usb-audio.md) for the functions and the open items.
