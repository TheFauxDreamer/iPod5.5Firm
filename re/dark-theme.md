# Dark theme: research notes

This document records the research for the dark theme. The target is Apple RetailOS 1.3 for the iPod Video. The source is an iPodWizard theme for firmware 1.2.1.

## The source theme

The Internet Archive has a collection of iPodWizard themes: [iPod Wizard Themes](https://archive.org/details/b5ad5489368ba5f0fe19935e983faf2b). The tests used this theme:

`3. Themes/5.5 gen/1. Tested _ Working/1. Dark Mode (Other Colors Inside)/Dark Gray (04_12_20)`

- Authors: "5.5G Ultimate Background Hack" by Matthew98. Dark mode by Milli5410.
- The file is a complete firmware partition (13,899,776 bytes) from an iPod. It is not a theme pack.
- The theme is for Apple firmware 1.2.1. Its base is `1. iTunes Restore Firmware (recommend first step)/5.5 gen/iPod_25.1.2.1.ipsw` in the same collection.
- The `rsrc` image is at a different position than in Apple's file (0x739800, not 0x72c800). To start the theme in the emulator, put its osos into Apple's 1.2.1 file.

CAUTION: The theme files contain Apple code. Do not commit them.

## What the theme changes (compared with 1.2.1)

| Part | Changes |
|---|---|
| BMap | 253 pictures. Picture 21997 becomes a 320 × 240 background (rows 0–23 are (16,16,16), the other rows are black). |
| View | 617 layouts. |
| Type | 22 records (text colours and sizes). |
| Program code | 17 bytes at (address removed)–(address removed). |
| Other data | The 153 KB of picture 21997 overwrite bitmap font data at 0x502df4. |

### The program code changes

The theme changes 6 conditional branches to `nop` (`e1a00000`). In 1.3 the same code is at (address removed), (address removed), (address removed), (address removed), (address removed) and (address removed), in function 0x131874. This function reads a file of at most 16 KB and verifies it with a key (0x11574, 0x102b0). The `nop` changes remove this verification. They are not a part of the dark theme. The import does not apply them.

## The View format

A View is a u32 count and then a list of elements. An element has this layout:

| Offset | Content |
|---|---|
| +0 | u32: element size − 4 |
| +4 | u32: flags |
| +8 | tag, byte-reversed ("BMap", "Str ", "None", "Draw", "Cntl", "StSt") |
| +12 | i16: resource ID. "BMap" and "Draw" refer to a picture, "Str " to a string, "None" to a sub-View. |
| +60 | u32: height (for example 0x18 = 24) |
| +76, +80 | RGBA colours of the highlight bar (1.3: `2864d0ff` and `5898e8ff`, blue) |
| +84 | In "Str " elements: the high i16 is a Type ID (text style). |

Facts:

- View 24069 is the root of the screen. Its elements are the title bar views (24506 and others). The theme sets their height from 24 to 240.
- View 24506 is the title bar. The theme changes element 0 from `BMap 24379` (the title bar picture) to `Draw 21997` with a height of 240. Thus the background picture fills the screen behind the list.
- A `Draw` element with a picture ID shows the picture at its own size. It does not stretch or repeat the picture.
- A `Draw` element with ID 0x5fe9 draws the brushed-metal texture of the screen lock. It ignores the two colours.
- The negative resource IDs moved between the versions. For most Views and Types, 1.2.1 ID −n is 1.3 ID −n+2 (for example −279 and −277). The IDs in the element fields move too.

## Free space for the background

The background picture needs space in osos. These results came from the emulator:

| Location | Result |
|---|---|
| Gaps between resources in 1.3 | 29 KB in total, but no gap is larger than 256 bytes. |
| The zero area at 0x6ca452 (310 KB) | The firmware stops at start ("Lost" after 10 million instructions). The firmware needs this area to be zero. |
| After the end of osos (0x736800), with rsrc moved | Correct. |

The reset code compares the end of the image (0x7358c0, at 0x308) with 0x800004. Thus the image can be up to 8 MB. The import puts the picture after the patch area, below 0x7F0000.

The background has only grey pixels. The import stores it as a 4-bit grey picture (38,428 bytes, not 153,628 bytes). The `Draw` element shows the 4-bit picture correctly.

## Moving rsrc

The OS finds `rsrc` through the directory. The theme dump from an iPod and the emulator tests show this. Rockbox `ipodpatcher` also moves images on the disk to make room.

- In an iPod partition, `rsrc` moves to the first free space after the last image (`hibe`). The 192 MB partition of the test iPod has 32 MB of zeros at 0x4d44000. After that there is old data (a FAT boot sector at 0x6db2400). `make_room` writes only into an area that is all zero.
- In a firmware file, `rsrc` and `aupd` move forward together. The content does not change. This keeps the file below 16 MB, which is the limit of the emulator's `make-disk`.
- On the iPod, `aupd` never moves. The flash puts the osos and `rsrc` of a file into the iPod's layout (`fit_layout`).

## Results in the emulator (1.3)

| Test | Result |
|---|---|
| The theme on 1.2.1 | Black lists, white text, dark grey highlight. This is the reference. |
| Whole Views copied byte for byte | Blank screen or empty lists. |
| Highlight colours only (+76, +80) | Dark grey highlight, white list. |
| All element fields, IDs translated, background picture after osos | The same look as the reference. Menus, Albums, Now Playing, Videos and Settings are correct. |
| The same, with the `album-art` patch | Correct. The thumbnails show. |

## Verification before a flash to a real iPod

### How RetailOS finds rsrc (Ghidra)

The code loads the `crsr` tag at 0xaf548 and 0x1afe44. Both call 0xfc3bc, which calls 0xc60ec. Function 0xc60ec does these steps:

1. It reads the first sector of the firmware partition and examines `]ih[` at +0x100.
2. It reads the directory at the offset in +0x104, plus 0x200.
3. It examines a maximum of 10 entries that start with `!ATA`. It selects the entry by its type tag (+4) and its ID (+8), not by its index.
4. It takes the start from devOffset (+0x0c) plus one sector, and the length from +0x10. Both must be a multiple of the sector size.

Thus RetailOS does not use a fixed rsrc position. iPodFirm keeps the order of the entries, the alignment (0x800) and the length of rsrc.

### Rockbox ipodpatcher

`diskmove()` in `utils/ipodpatcher/ipodpatcher.c` moves all images after osos (rsrc, aupd, hibe) forward and adds the same value to each devOffset. `add_bootloader()` calls it when the bootloader does not fit after osos. On a 5G/5.5G with firmware 1.3 the gap after osos is 2 KB, so a Rockbox dual-boot install moves rsrc. RetailOS still starts in dual-boot mode. iPodFirm uses a different layout: aupd and hibe stay in place, and rsrc goes after hibe.

### The RAM after the image

- The memory setup at 0xc90 describes a region from 0x10800000 (8 MB). The allocator pool object is at 0x1081da00, in that region.
- No code refers to the area between the image end (0x7358c0) and 8 MB.
- Emulator test with a write watch (`IPODFW_WATCH_RANGE=0x00700000:0x100000`, a local emulator patch): boot, lists, 60 seconds of playback, Videos, Photos, Extras and Settings. The CPU wrote 10 words in this range, all in the variables of the album-art patch (0x735900–0x7362c0). It wrote nothing to the background picture (0x736800–0x73fe00) or above it.
- Limit: the watch records CPU writes. It does not prove that no DMA transfer writes there.

### Disk mode

The Rockbox manual for the iPod Video: "The Ipod bootloader is the program that tells your player how to load and start the firmware from disk. It is also responsible for the disk mode on your player. This bootloader is stored in special flash memory in your Ipod." iPodFirm never writes or moves aupd, the only image that changes this flash memory.

## The artwork under the dark background

- The album-art patch drew the thumbnails with `gc_set_mode(gc, 1)`. The mode goes to the video chip. Mode 1 darkens: the thumbnail shows on white, it is not visible on black, and it is faint on the grey highlight.
- Apple's code uses the modes 0, 1, 8, 32, 33 and 34. With mode 0 the thumbnails show on the dark background.
- The general label class is also used in Now Playing. The patch drew a thumbnail next to the album name there. The parent of a label (view + 0x10) has the class 0x66b4dc in a list row, and 0x66b298 (a plain view) in Now Playing. The patch now draws only when the parent is a list row.
- Apple's large artwork in Now Playing comes from `iPod_Control/Artwork/ArtworkDB` and the files `F1028_1.ithmb` (100 × 100) and `F1029_1.ithmb` (200 × 200). The emulator library had no ArtworkDB. iPodFirm now writes it (`ipodfw.artworkdb`, `ArtworkDB.swift`). In the emulator, RetailOS shows the artwork from it.
- Open: in two runs of the unchanged Apple firmware, Now Playing showed an empty artwork frame. The firmware with the theme or with the patch showed the artwork. The cause is not known.

## Real iPod test (2 October 2026)

The owner flashed the light firmware with album-art, and then the dark theme with album-art, to a real iPod 5.5G. Both started and operated. Thus RetailOS on the hardware found the moved rsrc.

Two problems were found and corrected:

- The progress bar in Now Playing was almost invisible. The theme makes pictures 24342 and 24343 dark grey (16,16,16 and 33,36,33), also on 1.2.1. The import now keeps the Apple progress bar (`KEEP_APPLE`).
- The time labels in Now Playing were black on black. Apple also moved positive IDs: Type 14034–14036 in 1.2.1 are 14037–14039 in 1.3, and 14039–14040 are 14042–14043. The ID map translated only negative IDs. It now maps all resources by their contents, and uses the shift of the nearest mapped resource for a changed resource.

## Thumbnails after a sync

The album-art patch loaded the thumbnail file one time. New albums showed only after a restart of the iPod (found on the real iPod).

- iPodFirm writes a stamp at +0x0C of the file: the FNV-1a hash of the entry table.
- After 100 list labels without a thumbnail, the patch reads the 16-byte header again. If the header changed, it frees the old data with `fw_free` (0x25a8e4, the same pool 0x1081da00 as `fw_alloc`) and loads the file again.
- Emulator test (threshold 3): 52 header checks without a change caused no reload. After the file was replaced in the drive image, the patch reloaded it, and the Albums list showed the thumbnails of the new file. The UI continued to operate.

## Open items

- Test on a real iPod. The emulator makes its own boot ROM, and it does not test `aupd`.
- 23 Views have some fields that do not agree with 1.3. The import report lists them.
- Timed appearance: find the function that gives the current time. Then write a patch that changes between the light and the dark resources in RAM.

## The Dark Mode item in Settings

### Why the iPod must restart

- The theme can switch in RAM: osos runs at the same addresses as in the file, and a table of "old XOR new" switches it in both directions. Pictures and text colours (`Type`) change at once.
- The screens do not change. RetailOS makes its main screens one time at the start. The views copy the positions, the heights and the highlight colours of their elements when the firmware makes them (`FUN_0021a4f4`, children from `FUN_0017def4`).
- Method 0xd0 of a view applies a layout again, but only the text styles (`FUN_002445d4` → `FUN_00243f60`).
- A language change does not make the screens again. The event `FUN_001d32e0(0x60000005)` after a language change does not do it either.
- Thus the patch applies the table at the start, before the first View is read, and the item restarts the iPod.

### Functions (firmware 1.3)

| Address | Function |
|---|---|
| 0x21f254 | General resource lookup (provider, type, id). All resource and string lookups pass here, also virtual calls. The patch replaces its first instruction (`push {r3-r7, lr}`) with a branch. |
| 0x21f3dc, 0x21f408, 0x21f418 | Lookups of a type (any, 'BMap', 'Str '). They continue in 0x21f254. |
| 0x190b00, 0x1919d8 | Get and set a property of the settings object (vtable 0x66c94c, 0x66c950). Operations are four-character codes: 'prID' (the ID of the value text), 'Str ', 'Ui32'. |
| 0x08f3f8 | Open a file for reading and writing (access 3). It makes the file if it does not exist. |
| 0x08f6f4 | Write to a file. 0x08f184 (close) writes the buffer to the disk. |
| 0x1ee8b8 | Save the settings and the database (as before a sleep). The application object is at 0x1081da18. |
| 0x094e08, 0x001630 | Prepare a restart; restart (writes 4 to DEV_RS, 0x60006004). |

### Settings menu

- Menu 24598: a u32 count and items of 40 bytes. +0x18: the label ID; +0x1c: the key (for example 0x600060b7, Sound Check).
- The build adds an item after Clicker: a copy of the Sound Check item with the key 0x600060e0 and the label ID 0x7e00. The patch returns "Dark Mode" for this label ID, and "On" (0x602e) or "Off" (0x602f) for the key.

### Results in the emulator

- Light at the start; select the item: the iPod restarts dark; select it again: light. The iPod did not ask for the language after the restart (the settings were saved).
- The same result without the file `iPodFirmDarkMode` on the iPod: the open function makes it.
- The Swift and the Python builds give the same osos.

### Open items

- Test on a real iPod.
- The Settings list keeps a blue highlight in dark mode. The built-in dark theme has the same problem, so it is a limit of the theme import (the layouts of the Settings list).
- The first screen after a start shows "Press Center to dismiss" in the title bar. This comes from the theme: the original theme on 1.2.1 has it too.
