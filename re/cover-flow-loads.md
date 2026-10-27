# Cover Flow: the cover loads

This note records the research of 27 October 2026 about the cover loads of the `cover-flow` patch. The owner reported two problems:

- The album thumbnails of `album-art` load one time and stay until a restart, but Cover Flow loads a cover again after a long scroll, also inside one session.
- Cover Flow had more covers ready in earlier versions.

This note is research only. No code changed. The short version is also in [cover-flow.md](cover-flow.md), section "Research: why covers load again".

## Summary

1. Cover Flow keeps 11 textures of 128 × 128 (32 KB each). The cache size never changed. A long scroll replaces the far covers, and a scroll back loads them again.
2. The free memory of the firmware is small: 2.67 MB with the Albums list (emulator). All 336 covers (10.8 MB) cannot stay in memory.
3. Rockbox PictureFlow on the iPod Video also keeps only about 12–15 slides. Its loads are cheap (slides scaled before, in a disk cache) and do not stop the wheel (a background thread).
4. The early versions of the patch felt better because each load was cheaper and a frame loaded all visible covers. Since version 0.5, a load reads 4 times more data and scales it. Since version 0.6, a frame loads at most one cover.
5. Recent changes make the loads more visible: the 416 MB artwork file after the restore, the wheel correction of 0.6.7, and the background fill of `album-art` 2.8 and later.

## Why album-art keeps all thumbnails and Cover Flow does not

| | `album-art` | `cover-flow` |
|---|---|---|
| Size of one picture | 20 × 20 RGB565 = 800 bytes | 128 × 128 RGB565 = 32 KB |
| All 336 albums | 270 KB | 10.8 MB |
| Kept in memory | All, until a restart or a USB session | 11 (`CACHE_SLOTS`, about 350 KB) |
| At the close | — | `release()` frees the textures and closes the artwork file |

`cover()` (patches/cover-flow/cover_flow.c) replaces the cover that is farthest from the target. A cover that comes back needs a new load. On the real iPod a load takes approximately 31 ms: the read of 80 KB from `F1029_1.ithmb` takes 16 ms, and the scale 200 → 128 takes 15 ms (log of version 0.6.7). The load runs in the UI task. At each open of Cover Flow, the first load opens the 416 MB `F1029_1.ithmb` again (1.1 s).

## The history of the cover loads

All versions in git (`git log --all -- patches/cover-flow/cover_flow.c`, from 8 October 2026):

| Version | Date | Source of a cover | Cost of one load | Loads in one frame |
|---|---|---|---|---|
| 0.2–0.3 | 8 October | The file `iPodFirmCoverFlow` that iPodFirm wrote (scaled covers, 12.3 MB for 326 albums). One open file. | One read, no scale | No limit: a frame loaded each visible cover |
| 0.4 | 9 October | `F1028_N.ithmb`, 100 × 100, a new open for each cover | A read of 20 KB, no scale | No limit |
| 0.5–0.6 | 9–10 October | `F1029_N.ithmb`, 200 × 200 (sharper covers), scaled to 128 × 128 | A read of 80 KB and a scale (31 ms on the real iPod) | At most 1. A cover that is not loaded shows a grey square and loads in a later frame |
| 0.6.3 | 16 October | The same | The same | The first frame loads 3 covers (`OPEN_LOADS`) |
| 0.6.4 | 21 October | The same | The same | The same |
| After the restore | 27 October | `F1029_1.ithmb` is 416 MB (one image for each of 5201 tracks) | Each load opened the file again (1.1 s) | The same |
| 0.6.6 | 27 October | The file stays open during a session | 31 ms, and 1.1 s at the first load of each open | The same |
| 0.6.7 | 27 October | The same | The same | The same. A wheel event now moves the full count of wheel ticks (before, most ticks were lost) |
| 0.6.8 | 27 October | The same (the debug log removed) | The same | The same |

Values that never changed: `CACHE_SLOTS` 11, `SIDE` 4 (the centre and 4 covers at each side). Since 0.6, `PRELOAD` loads the centre ± 4 when the movement stops. The load and preload code of 0.6.4 and 0.6.8 is the same; only `step(n)` changed.

Thus the early versions did not keep more covers. They had:

1. **Cheaper loads.** 0.2–0.4 read small or scaled covers with no scale at run time.
2. **No grey squares.** Before 0.6, a frame loaded each visible cover before the draw. The animation stopped, but each cover showed. Since 0.6, a frame loads one cover, thus the animation is smooth, and far covers show later.

Two recent changes make the loads easier to see:

- **The wheel correction of 0.6.7.** Before, most wheel ticks were lost, thus the target moved slowly and the loads kept up. Now a fast turn moves many albums.
- **`album-art` 2.8 and later** (refer to "The interaction with album-art").

## How Rockbox PictureFlow does it

Source: the owner's Rockbox fork `rockpod`, `apps/plugins/pictureflow/pictureflow.c`, and `firmware/export/config/ipodvideo.h`.

| Item | PictureFlow | Lines |
|---|---|---|
| The RAM buffer | The plugin buffer if playback is possible (`PF_PLAYBACK_CAPABLE`: `PLUGIN_BUFFER_SIZE` > 0x10000), else the audio buffer. On the iPod Video, `PLUGIN_BUFFER_SIZE` is 0x80000 (512 KB), thus the plugin buffer. The album index uses the same buffer. | 42–44, 4796–4799; ipodvideo.h 95 |
| The slides in RAM | At most 100 entries (`SLIDE_CACHE_SIZE`), but each slide must fit in the buffer (`buflib_alloc`). A square slide is 128 × 128 × 2 = 32 KB (`DISPLAY_WIDTH` = max(240 / 2, 320 × 2 / 5) = 128). Thus approximately 12–15 slides on the iPod Video. | 287–298, 2744–2776 |
| Which slide goes | A window around the centre. `load_new_slide` adds a slide at the side with fewer slides. When the buffer is full, `free_slide_prio` frees the end of the window that is farthest from the centre. The same rule as `cover()`. Thus PictureFlow also loads a slide again after a long scroll. | 2697–2737, 2880–2930 |
| A load | `read_pfraw` reads a ready slide from its own small file (`.pfraw`, the name is a hash of the album and the artist). No scale at run time. | 2744–2805 |
| The disk cache | Made at the first start with a progress bar (`create_albumart_cache`). Later, one album at each idle loop (`incremental_albumart_cache(false)`). | 2316–2426, 5072–5078 |
| The thread | "Picture load thread" (`PRIORITY_BUFFERING`) loads slides while its queue is empty and yields after each slide. The UI shows an empty slide until a slide is ready. | 2461–2530 |

Correction: an earlier line in cover-flow.md said "a RAM cache of 64 slides (LRU)". The cache is a window around the centre, and its size depends on the buffer.

Versions 0.2–0.3 of the patch used the same method as PictureFlow: covers scaled before, in a file. Version 0.4 removed it, so that Cover Flow does not need iPodFirm.

## The free memory of the firmware

`fw_alloc` (0x25a974) calls 0x1ac4ec with `*(0x1081da00)` and the flag 2. The word at 0x1081da00 is the address of the heap object of the general allocator.

| Heap object | Meaning | Evidence |
|---|---|---|
| + 0x00 | The free bytes. 0x1ac4ec subtracts the size of a merged free block from it. | Static (0x1ac4ec), Emulator |
| + 0x04 | The used bytes. + 0x00 and + 0x04 together stayed 55,519,668 bytes (52.9 MB). | Emulator |
| + 0x08 | The count of allocations (it only increases) | Static, Emulator |

Emulator, 27 October 2026: FolderLibrary (1000 tracks, 138 albums), `album-art` 3.2 and `cover-flow` 0.6.8. The heap object was at 0x10870154.

| State | Free | Used |
|---|---|---|
| After the start | 2.92 MB | 50.03 MB |
| The Albums list | 2.67 MB | 50.28 MB |
| Cover Flow open | 1.94 MB | 51.01 MB |
| After a scroll of 60 detents | 1.94 MB | 51.01 MB |
| Cover Flow closed | 2.66 MB | 50.28 MB |

Cover Flow uses 0.73 MB while it shows and gives it back at the close. The firmware uses almost all of its heap (probably the music buffer and its caches). The owner's library (5201 tracks) probably leaves less. Not measured on the real iPod: a test build can read `*(*(unsigned **)0x1081da00)` and write it to the debug log.

`album-art` 3.2 holds approximately 0.9 MB more than 2.7 in the file mode: the thumbnails (270 KB), the cache (270 KB), the table of tracks (12 bytes for each track) and the collages (13 KB). Less free memory can make the caches of the firmware smaller. Not measured.

## The interaction with album-art

- Both patches chain on the event method of the browse list (0x6772c0). The build applies the patches sorted by name, thus `cover-flow` gets each event first.
- While Cover Flow shows, `active_event` keeps the timer, wheel and key events. Other events go to `album-art`, also the list tick (type 0xd, each 3–4 s on the real iPod).
- At a list tick, `album-art` makes one missing thumbnail if its cache is not complete (`prefill_one`). This reads the 104 MB `F1028_1.ithmb`, with an open of 0.93 s if the file is closed. The list under Cover Flow probably stays "visible", thus this can occur while Cover Flow shows.
- In version 2.7 with the file mode, the background fill did not run. Since 2.8, it runs after each sync until the cache of `album-art` is complete.
- Not measured. A possible correction: `active_event` also keeps the list tick while Cover Flow shows (one line in cover_flow.c).

## What can make Cover Flow better

In the recommended order:

1. **Measure on the real iPod**: the free heap, and the load times (the debug log of cover-flow.md, "How to add the debug log again"). Compare with the 0.6.7 log (a load 31 ms: read 16.2 ms, scale 14.8 ms).
2. **Keep the list tick from `album-art` while Cover Flow shows.** One line. Removes the possible disk reads of `album-art` during Cover Flow.
3. **A disk cache of scaled textures (the method of PictureFlow and of 0.2–0.3, without iPodFirm).** A file with one 128 × 128 texture (32 KB) for each album, 10.8 MB for 336 albums, made by the patch as covers load (as the `album-art` cache). A load reads 32 KB with no scale: approximately 7 ms in place of 31 ms (an estimate from 16 ms for 80 KB). Open questions:
   - Does the firmware file system allow a seek past the end of a file, to put a texture at its place?
   - Is the open of an 11 MB file faster than the 1.1 s of the 416 MB `F1029_1.ithmb`? (`ArtworkDB`, 3 MB, opens in a few ms.)
4. **A background task for the loads (the method of PictureFlow).** ThreadX tasks are made with `bl 0x11c808` and a priority (re/usb-host.md, re/firmware-task-system.md). A patch task needs a task class, a stack, and a lock for the cache and the file handle. Needs its own research.
5. **Keep the textures between two opens, or a few more slots.** Only after the measurement of item 1. For example 16 slots (+160 KB).
6. **Optional: load more than one cover in a frame while the wheel is slow.** Version 0.4 loaded all visible covers. A limit of 2–3 loads in a frame when no wheel event waits gives fewer grey squares. With item 3, a load is cheap enough for this.

## Sources

- `patches/cover-flow/cover_flow.c` in each commit: 3180488 (0.2), c6fc89f (0.3), 3a8dbb8 (0.4), c8234d0 (0.6), 65f0438 (0.6.1), 6d4778e (0.6.2), c4c9180 (0.6.3), 573436f (0.6.4), f30c897 (0.6.8).
- [cover-flow.md](cover-flow.md): the logs of 0.6.5–0.6.7 and the times of the real iPod.
- Ghidra (read-only): 0x25a974, 0x11ca20, 0x1ac4ec.
- Emulator: `peek` of the heap object, 27 October 2026.
