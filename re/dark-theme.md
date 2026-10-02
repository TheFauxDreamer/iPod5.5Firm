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

## Open items

- Test on a real iPod. The emulator makes its own boot ROM, and it does not test `aupd`.
- 23 Views have some fields that do not agree with 1.3. The import report lists them.
- Timed appearance: find the function that gives the current time. Then write a patch that changes between the light and the dark resources in RAM.
