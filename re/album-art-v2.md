# Album artwork version 2: research notes

This document records the research for version 2.0 of the `album-art` patch. The firmware is Apple RetailOS 1.3 for the iPod Video. The work started on 9 October 2026.

Version 1.0 had two problems:

- It drew each thumbnail with one `gc_set_color` call and one `gc_fill_rect` call for each run of pixels with the same colour. A cover has runs of approximately 1 pixel, thus a 20 × 20 thumbnail needed up to 400 pairs of calls.
- It needed the file `iPodFirmAlbumArt`. The user had to write it with iPodFirm after each sync.

Version 2.0 gets the album covers from the artwork of the iPod, and draws each thumbnail with one call of the firmware blit. The `cover-flow` patch found how to read the artwork (refer to the `cover-flow` branch, `re/cover-flow.md`, "Research: the built-in artwork").

## Tools

- Ghidra with the project `osos13` (refer to [../docs/ghidra-guide.md](../docs/ghidra-guide.md)), `DecompileAt.java`.
- The instrumented emulator (refer to [emulator.md](emulator.md)), with `IPODFW_MARK_AT`, `evlog`, `peek`, `hold`, `wheel` and `shot`.
- A debug copy of the patch, which kept a record of each label draw in a global array. `peek` read the array. The debug copy was not kept.

## The graphics context and the bitmap

Static results (Ghidra):

| Address | Finding |
|---|---|
| 0x211a00 | `gc_fill_rect(gc, rect)` adds the origin (gc + 0x30 to top and bottom, gc + 0x2c to left and right) and calls 0xc01a4(gc + 0x1c → bitmap + 4, rect, gc + 0x11, mode at gc + 0x10). |
| 0xc01a4 | Fills a rectangle in a bitmap. It clips with the bounds of the bitmap (0xc1e68), calls the draw listeners (0xe442c), fills, and adds the rectangle to the damaged area (0xe944c). |
| 0x210114 | The blit (gc, source gc, source rect, target rect). It adds the origins of the two gcs and calls 0x1216a0(source bitmap + 4, target bitmap + 4, source rect, target rect, gc + 0x11, gc + 0x15, mode, gc + 0x34). The source is a gc, not a picture object. |
| 0x1216a0 | The blit core. It clips the target rectangle with gc + 0x34, then clips both rectangles with the bounds of the two bitmaps. If the two format words agree (mask 0xdfff) and the mode is 0, it copies the pixels. It calls 0xe442c and 0xe944c for the target. |
| 0x210638 | Sets a new gc to its start values: 0x44 bytes. |
| 0x211a70 | (gc, bitmap): gc + 0x1c = bitmap; the clip gc + 0x34 = the bounds at bitmap + 0x98. |
| 0x1bb260 | The list-row label draws its cached text images with 0x210114. Each image is a gc of 0x6c bytes in the label (label + (0x7b + 0x1b × i) × 4). |

The bitmap descriptor starts at bitmap + 4:

| Offset | Content |
|---|---|
| +0x00 | Pixel pointer |
| +0x04 | Stride in bytes |
| +0x08 | Bits for each pixel (16) |
| +0x0c | Shift: x << shift is the bit offset of a pixel (4 for 16 bits) |
| +0x10 | u16: the format. 0xc62b4 knows 0x555, 0x565, 0x1444 and 0x1888. Bit 0x2000 swaps the bytes. |
| +0x14, +0x18, +0x1c, +0x20 | Bounds: top, left, bottom, right |
| +0x24 | The draw listeners. Only the target of a draw uses them. |

The blit core addresses the rows in 32-bit words. Thus the pixel pointer and the stride of a source must be multiples of 4.

### The patch draw

The patch makes a source gc on the stack: 0x44 bytes of zeros, with gc + 0x1c pointing to a bitmap of 10 words around the thumbnail. The format word is a copy of the format word of the target. Thus the blit copies the pixels and does not convert them. The firmware clips the blit and marks the damaged area.

The patch draws runs of rectangles, as version 1.0 did, if one of these conditions is true:

- The target is not 16 bits for each pixel.
- The target format is not 0x565.
- The thumbnail pointer is not a multiple of 4.
- The thumbnail size is odd.

In the emulator, the list rows used the blit. The screens of version 1.0 and version 2.0 agree, also for the highlighted row.

## The album covers

The patch makes a table of the albums with artwork at the first album or playlist label after a database load:

1. For each track (database + 0x20, count at + 0x1c), it copies the album name from the album pool (database + 0x138) with 0x9eff8. It calculates the FNV-1a hash of the UTF-8 form of the name. The firmware gives the same UTF-8 text to the label, thus the hash of the label text agrees.
2. It sorts the tracks by their dbid (track + 0x108).
3. It reads `iPod_Control\Artwork\ArtworkDB` through a 32 KB window. For each image (mhii) of a known track, it keeps the hash, the number N of `F1028_N.ithmb` and the offset of the 100 × 100 image.
4. It sorts the entries by the hash and keeps one entry for each album.

At the first draw of an album row, the patch reads the 100 × 100 image (20000 bytes) and makes a 20 × 20 thumbnail with the average of each 5 × 5 square. `(sum × 2621 + 32768) >> 16` divides by 25. It keeps a maximum of 1 MB of thumbnails.

## A delayed read does not operate

The first test had a read budget: a maximum of one thumbnail in 30 ms. A row over the budget got the space of its thumbnail, and the patch called `view_invalidate` (0x21ac04) on the label to get a later draw. Results in the emulator:

- The firmware did not draw the labels again. After 450 ms, the label hooks did not run again. Thus `view_invalidate` during a draw does not start a new draw.
- The Albums list draws all its rows with the same label view (0x13c1b7fc in the emulator). Each row is a new draw of this view with a different text.
- The rows after a row without a thumbnail had no space. The patch returned before `gc_prepare`, thus the gc origin stayed at the shifted position. The left-edge test (x ≤ 8) of the next row then failed.

Thus version 2.0 has no read budget. It makes each thumbnail at its first draw, and it calls `gc_prepare` after each shifted draw.

## Times in the emulator (9 October 2026)

The library is the FolderLibrary of the Emulator pane: 1000 tracks, 138 albums, with ArtworkDB and `F1028_1.ithmb`. The drives had the database and the artwork, but no music files. The "old" drive also had the file `iPodFirmAlbumArt` (20 × 20).

Markers (`IPODFW_MARK_AT`): the original label draws 0x1bb260 and 0x244924, and the LCD present 0x164f44. A paint is the time from the first label draw to the first present after the last label draw. The times are emulated ms (`USEC_TIMER`).

| Case | No patch | Version 1.0 | Version 2.0 |
|---|---|---|---|
| Open Albums the first time | 365.35 | 412.56 | 457.11 |
| Move the highlight one row (four tests) | 1.63, 2.09, 3.13, 3.45 | 3.82, 6.11, 7.19, 8.08 | 1.71, 2.33, 3.32, 3.67 |

A second test split the time into single paints:

| Case | No patch | Version 1.0 | Version 2.0 |
|---|---|---|---|
| Open Albums the first time: the paint of the list | 16.38 | 31.84 | 54.48 |
| Scroll 10 rows: the paints that move the list (new rows show) | 12.68–19.76 | 33.04–39.70 | 18.22–29.20 |
| Scroll 10 rows: all paints together | 118.58 | 170.69 | 130.43 |
| Open Albums again: the paint of the list | 32.04 | 50.44 | 33.37 |

- With the thumbnails in memory, version 2.0 needs 4–11 % more time than no patch. Version 1.0 needs 1.6–2.9 times the time of no patch.
- A paint that shows a new row adds approximately 6–10 ms for one disk read and the 5 × 5 average. It is still faster than version 1.0.
- The first paint of the Albums list makes the table (1000 tracks and ArtworkDB) and 8 thumbnails. It takes 38 ms more than no patch, one time after each database load.

The emulator disk has no seek time. On a hard disk, each new thumbnail adds a seek. This is not measured.

## Open items

1. A test on the real iPod with a library from Finder or iTunes. Is format 1028 on the iPod? (The same open item as Cover Flow v0.4.)
2. The time of the first open and of a long scroll on a hard disk.
3. A name with a character outside the Basic Multilingual Plane: the patch makes 4-byte UTF-8. The firmware form of such a label text is not examined.

## The slow scroll on the real iPod (version 2.2)

On 9 October 2026, the owner reported that the Albums list scrolls much more smoothly without the patch. The iPod has flash storage. The library has approximately 377 albums and 5123 tracks. The second pass through the list is also slow. All thumbnails fit in the 1 MB memory (1310 slots), so a second pass must not read the disk.

Version 2.2 is a measurement build. With `ALBUM_ART_STATS 1`, the patch times its parts with `USEC_TIMER`. After each 256 album or playlist row draws, it writes one record of 208 bytes to `iPod_Control\iTunes\iPodFirmAlbumArtStats`. Record N is at offset N × 208. Each start of the iPod writes from record 0 again. [album-art-stats.py](album-art-stats.py) shows the change between two records.

The measurement records these items:

- the time of each album or playlist row, of the original draw (with a thumbnail and without), of `build_art`, of `load`, of `check_for_new_file`, of a fill from `F1028_N.ithmb`, of a read from `iPodFirmAlbumArt`, of the blit and of `draw_runs`;
- the hits in memory, the failed artwork reads, the calls of `hook_db_loaded` and a bit for each failed allocation;
- the state: `art_state`, `art_count`, `art_slots` and the state of the thumbnail file.

### Results in the emulator

Emulator test on 9 October 2026 with the FolderLibrary (138 albums). The script opened Albums and scrolled 300 detents down, 300 up, 300 down and 300 up. Three builds were measured. The variants were temporary and are not in the repository.

| Build | Original draw of an album row | All of the album row |
|---|---|---|
| Version 2.2 | 1733–2343 µs | 1478–2845 µs |
| The left edge does not move (the thumbnail covers the text) | 1779–2401 µs | 1508–2831 µs |
| No thumbnail (`px = 0`) | 1542–2259 µs | 1641–2529 µs |

The values are the mean of each record of 256 rows. Record 0 is not in the table, because it includes `build_art` and the first fills. Other values of version 2.2:

| Part | Time | When |
|---|---|---|
| A different list row (the Music menu), original draw | Approximately 650 µs | Each draw |
| The blit of a thumbnail | Approximately 115 µs | Each album row |
| A fill from `F1028_1.ithmb` (open, read 20000 bytes, 5 × 5 average) | 4.8–5.3 ms, a maximum of 20 ms | Each new album |
| `build_art` | Approximately 52 ms | One time after a database load |
| `load` of `iPodFirmAlbumArt` | Approximately 5 ms | One time |

Conclusions:

1. The firmware draw of an album row takes approximately 2 ms, also without a thumbnail. The patch does not make it slower.
2. The moved left edge does not make the draw slower. Possible cause 4 (the label draws its text again) is not correct.
3. With the thumbnails in memory, the patch adds approximately 120 µs for each row. This is approximately 6 %.
4. The second pass had no fills, no `build_art` and no failed allocation. The emulator does not show the slow second pass. The cause is on the real iPod only.

### Possible causes on the real iPod

The stats file from the real iPod shows which cause is correct:

1. A failed allocation (`alloc_failed`). Then the thumbnails are not in memory.
2. ArtworkDB has no format 1028 image (`art_count` is 0 or `art_failed` increases). Then each album reads the file `iPodFirmAlbumArt`.
3. `build_art` or `hook_db_loaded` more than one time.
4. `draw_runs` instead of the blit.

## Next steps for speed (not done)

The owner asked for more speed on 9 October 2026. This section keeps the plan for later. No code is changed for it yet. Do the measurement on the real iPod first (refer to the section above).

### Where the time goes

Emulator test on 9 October 2026, with the FolderLibrary (1000 tracks, 138 albums). The markers were on the file functions, on `pool_copy` (0x9eff8), on the hook and on the present (0x164f44).

| Part | Emulated time | When |
|---|---|---|
| The album hash of each track (1000 calls of `pool_copy`) | Approximately 10 ms | The first Albums paint after a start or a sync |
| The ArtworkDB parse (23 reads of 32 KB, a byte copy from the window) | 37.6 ms | The same |
| A thumbnail fill: open, seek, read 20000 bytes, close | Approximately 3.2 ms | Each new row |
| The 5 × 5 average, the blit and the label draw | Approximately 2.3 ms | Each new row |

### Step 1: make the table in the database task (research first)

The hook `hook_db_loaded` (the `bl` at 0xb4ad4) runs in the task that loads the music database. If this task makes the table, the UI task does not wait for it.

1. In Ghidra, decompile 0xb4a64 after 0xb4ad4. Also decompile 0xa2310 and 0x1edb9c. Find out if the track array (database + 0x20) and the library of the main provider (RAM 0x1081da18 + 0x1c) are complete when 0xb4ad4 runs.
2. In the emulator, set `IPODFW_REGS_AT` at 0xb4ad4. Then `peek` these values at the start and after a reload.
3. If both values are complete, call `build_art` from `hook_db_loaded`:
   - Make the table in local variables. Set `art_state = 1` only at the end.
   - Set a variable `art_busy` during the build. The draw hook does not draw album thumbnails while `art_busy` is 1.
4. If a value is not complete, keep the build in the draw hook. Record the result here.

### Step 2: a faster ArtworkDB parse

1. Change `db_read` so that it returns a pointer into the window. Do not copy the bytes.
2. Stop the parse when each album with tracks has an image.
3. The target is less than half of 37.6 ms.

### Step 3: a faster 5 × 5 average

1. Spread each pixel with `(c | c << 16) & 0x07E0F81F`. Blue goes to bits 0–4, red to bits 11–15 and green to bits 21–26.
2. Add the 25 pixels in one register. The sums do not overlap: blue is a maximum of 775 (bits 0–9), red is a maximum of 775 (bits 11–20) and green is a maximum of 1575 (bits 21–31).
3. Divide each channel with `(x × 2621 + 32768) >> 16`.
4. Make sure with a host test in C that the result agrees, pixel for pixel, with the current `shrink`.

### Step 4: fewer file opens (only if the measurement supports it)

Measure the parts of the 3.2 ms: open, seek, read and close. If the open uses more than half, keep the `F1028_N.ithmb` handle open between fills.

CAUTION: The patch has no hook at the start of a USB session. An open file during disk mode is a risk. Do this step only if you find a safe point to close the file.

### Verification

1. Run `uv run pytest` and `swift test` with `IPODFW_IPSW`.
2. Make sure that the emulator screenshots agree with version 2.0.
3. Record the first open, a scroll of 10 rows and the second open, for no patch, version 2.0 and version 2.1.
4. Do a reload test with a new library.

### Documents for that change

Update this note, `docs/modifications.md`, `docs/patch-system.md` and `docs/firmware-functions.md`. Set `version` to 2.1 in `patch.json`. Build the app with `mac/scripts/build-app.sh`.
