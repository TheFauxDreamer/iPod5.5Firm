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
| [album-art](#album-art) | Code patch | Patches | 2 vtable words | Yes |
| [sleep-now](#sleep-now) | Code patch | Patches | 1 vtable word and 2 `bl` | No |
| [flash-keep-awake](#flash-keep-awake) | Code patch | Patches | 4 `bl` | Partly (an earlier version) |
| [flash-wake-on-input](#flash-wake-on-input) | Code patch | Patches | 1 `bl` | No |
| [something-comforting](#something-comforting) | Code patch (example) | Patches | 1 `b` and 2 vtable words (all with `chain`), a Settings menu | No |
| [usb-host-probe](#usb-host-probe) | Code patch (test) | Patches | 8 `bl`, 2 `b` and 18 table words | Yes, as a test (2026-10-08) |
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

**User interface.** Patches pane > Album Artwork, letter `a`. `"ui": { "tools": ["album-thumbnails"] }` gives the detail these sections:

- "Thumbnails": "Write Thumbnails to iPod" writes the thumbnail file. "Eject iPod" ejects the iPod.
- "Playlist Artwork" sets a custom image for each playlist ("Choose Image…", "Use Automatic", or drag an image).

**Effect.** Each row in an album list and in a playlist list shows a 20 × 20 thumbnail at its left side.

**Load address.** 0x7358d0. The compiled code is 3080 bytes. Its area ends at 0x73658c.

**Hooks.**

| Kind | At | Expect | To | Replaced method |
|---|---|---|---|---|
| `word` | 0x66e470 | 0x001bb260 | `hook_row_label_draw` | Draw method of the list-row label class (type 0x3180) |
| `word` | 0x677a14 | 0x00244924 | `hook_label_draw` | Draw method of the general label class (type 0x1580) |
| `bl` | 0xb4ad4 | 0xeb057c60 | `hook_db_loaded` | The call of `log_event` (event 0xf, "Exit Disk Mode") in the music database load 0xb4a64 |

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
| 0x211a00 | `gc_fill_rect` | Fills a rectangle |
| 0x25a974, 0x25a8e4 | `fw_alloc`, `fw_free` | Memory from the pool at 0x1081da00 |
| 0x07ccd0, 0x07cd6c | `fw_memset0`, `fw_strcpy` | Memory and string functions |
| 0x08f38c, 0x08f464, 0x08f5c4, 0x08f184 | `file_open`, `file_read`, `file_seek`, `file_close` | File access on the iPod disk |
| 0x213c5c | `log_event` | Adds an event to the usage log |

**Runtime logic.** For each draw of a label, the wrapper does these steps:

1. If the parent of the label (view + 0x10) does not have the class 0x66b4dc (a list cell), call the original method and stop. This rule applies only to the general label. It prevents a thumbnail in Now Playing.
2. Load the thumbnail file if it is not loaded.
3. Read the element ID at view + 0x1c. Continue only for 0x6421 (album name) or 0x6425 (playlist name).
4. Make sure that the label is at the left edge (x ≤ 8) and has the height of a list row.
5. Calculate the FNV-1a hash of the text. For a playlist, start the hash with the byte 0x01.
6. Find the hash in the sorted index (binary search).
7. Add 24 pixels to the left edge of the label (view + 0x5c). Call the original method. Subtract the 24 pixels again.
8. Call `gc_prepare`. Then draw the thumbnail as runs of filled rectangles, one run for each group of pixels with the same colour.

Some draws of a highlighted row pass a structure, not text. The first byte of the structure is less than 0x20. Then the patch uses the thumbnail of the last draw of the same view (32 view slots).

**Draw mode.** The patch uses mode 0, which replaces the pixels. Mode 1 darkens. With mode 1 the thumbnails were not visible on the dark theme.

**Reload after a sync.** The firmware loads the music database at the start and after each USB session. The hook at 0xb4ad4 in this load sets a flag. At the next album label or playlist label, the patch clears the flag and reads the 16-byte header again. If the header changed, it frees the old data and loads the file again. If there was no file, the patch tries to load it again. Without a USB session, the patch does not read the file again.

**Memory.** If all the thumbnails are 1 MB or less, the patch loads all of them. Otherwise it keeps a cache of 64 thumbnails. It reads a thumbnail from the disk when the cache does not have it.

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

**Test status.** Tested in the emulator and on a real iPod 5.5G, with the light theme and with the dark theme.

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

## usb-host-probe

**User interface.** Patches pane > USB Host Probe, letter `h`. "Start the Probe at the Next Restart" writes '1' to `iPod_Control/iTunes/iPodFirmUSBProbe` and an empty 32768-byte `iPod_Control/iTunes/iPodFirmUSBLog` on the connected iPod. "Show USB Log" reads and decodes the log (`USBProbeLog` in [USBProbeLog.swift](../mac/Sources/IPodFWKit/USBProbeLog.swift)). The `ui` object of its `patch.json` gives the button, the section "Test Procedure" (the test steps) and the tool `usb-log` (the section "USB Log" with "Show USB Log" and "Copy Log"). This patch is a test for [USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md) (Stage 0). It is on main since 2026-10-08.

**Effect.** One time after the trigger, the iPod plays a demonstration of the signs and a countdown, starts its USB host stack, gives tones, and logs each call of a USB class driver. The next start is normal.

**Load address.** `extended`: the build puts the code after all other data, for example after a theme and the Dark Mode items (refer to [patch-system.md](patch-system.md#the-extended-area)). The compiled code and data are 8740 bytes. The log buffer (32712 bytes, 511 records) comes from the allocator 0x25a974 when the probe starts. The findings are in [patches/usb-host-probe/FINDINGS.md](../patches/usb-host-probe/FINDINGS.md).

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
12. With each queue dump, the probe also logs Apple's own periodic table for frames 0–7 (the UIM controller object at RAM 0x1084a778 + 0xc: +0x3c the processor address of the first queue head of each frame, +0x44 the frame list). After the first log write, it switches the periodic schedule off for 2 s (USBCMD bit 4), logs the queues again ("Experiment"), and switches it on again.
13. `hook_periodic_insert` repairs a firmware bug. 0xf5c80 makes the frame list word from (r1 + 0x34) | 2, but both callers give the queue head only in r0 (0x974ec leaves r1 = the UIM controller object, 0x96c44 leaves r1 unset). Thus the frame list pointed to a block of zeros, and no interrupt endpoint was polled. The wrapper copies r0 to r1.
14. Before the host start, the probe changes the second composite driver record (registry entry 0x6bc434, RAM 0x1084a360) from device class 2/0 to EF/02 (bytes at +0x35 and +0x36). It changes them only if they have the stock values. Then "add device" gives a device of class EF/02 (interface association, for example the USB-C EarPods) to the composite driver, and the driver reads the configuration.
15. The probe follows each GET_DESCRIPTOR configuration request of a device (setup, data stage buffer). At the last completion (r0 with the stage bit), it writes the received bytes to the log in records of 40 bytes (tag 44, "Data"), at most 512 bytes. The app decodes the configuration descriptor: interfaces, endpoints, interface associations and the audio class descriptors.
16. The limits are 200 UIM records, 200 completion records and 40 port records.
17. 10 s after the host start, `hook_event` writes the buffer to the log file, flushes the disk cache (0x1a0120, then 0x19ff0c, as the sleep sequence does) and gives two short low beeps. 20 s later, it writes the log again, with two more beeps. The UI does not react during approximately 37 s. A later button or wheel event writes the log again if it has new records. A button event is not sufficient alone: 0x1d81cc gives each event to the active modal screen first (0x12d890, 0x12ddb8) and returns if the screen takes it, for example the photo import screen. On the real iPod, no log was written for this reason.

**Test status.** Emulator: the demonstration and the countdown had the correct pauses. The host start ran 0x97300 and 0xd1288. The log had two records for the simulated root hub: hub validate and hub initialize device, device 05AC:8031, class 09, power 0xfa (500 mA). The menus worked after this. Real iPod: the host mode sign came. With the 3-in-1 adapter and a card reader, the photo import screen showed "unsupported device", with and without a card. No storage sign. With the dock, the port log showed VBUS valid, a connection, a correct reset and a high-speed device, but no driver call. The full-speed hook is for this result. Later tests (0.1.72–0.1.79) with the dock: the dock's hub, two storage devices and the USB-C EarPods enumerated. With the class change, the composite driver read the configuration of the EarPods (USB Audio Class 2). Caution: the probe reads DMA buffers through the cache, thus a second dump of the same buffer can show old bytes. Refer to [FINDINGS.md](../patches/usb-host-probe/FINDINGS.md).

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
   - **BMap** that the theme made larger: the picture goes into the free area after the end of osos, below 0x7F0000 (`ThemeImport.ososLimit`). If all pixels are grey, iPodFirm stores a 4-bit grey copy. Then the resource table entry gets the new offset and size.
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

**Build.** `DarkMode.build` in [DarkMode.swift](../mac/Sources/IPodFWKit/DarkMode.swift) puts these items after 0x736800, below 0x7F0000:

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
