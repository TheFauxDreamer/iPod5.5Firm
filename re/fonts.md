# The fonts of RetailOS 1.3

This note records the research of 6 November 2026 about the fonts. A user in Korea applied Korean bitmap fonts with iPodWizard. A flash with iPodFirm replaced them with the Apple fonts.

## Summary

1. The fonts are 8 TrueType files in the FAT volume of rsrc, in `/Resources/Fonts/`.
2. Each font has one strike of 4-bit bitmaps (`EBLC`/`EBDT`). iPodWizard changes these bitmaps.
3. RetailOS opens each font by its file name and reads it through a small block cache. Thus a larger font does not use its full size in RAM.
4. The FAT volume is FAT12, although its label says "FAT16". It has 632,832 free bytes.
5. A flash writes the rsrc of the open file. Thus a flash of the Apple file replaces fonts from iPodWizard.

iPodFirm now keeps custom fonts in the app and puts them into rsrc at each build (branch `custom-fonts`).

## The FAT volume in rsrc

The rsrc image of the Apple file is 0x500800 bytes. The FAT volume starts at the entryOffset of rsrc (0x600). RetailOS mounts it there: refer to [ipod-5g-512.md](ipod-5g-512.md#rsrc).

| Item | Value |
|---|---|
| Label | `IPODRESOURC`, type text `FAT16` |
| Sectors | 10240 of 512 bytes (0x500000 bytes) |
| Cluster | 4 sectors (2048 bytes) |
| FATs | 2, of 10 sectors each, from sector 1 |
| Root directory | 512 entries |
| Clusters | 2546. Fewer than 4085, thus FAT12. The FAT has packed 12-bit entries (`f0 ff ff ...`). |
| Free | 309 clusters (632,832 bytes) |

`src/ipodfw/fat16.py` selected the type from the label. Thus it read FAT12 entries as FAT16 entries and gave only the first clusters of a file. The type now comes from the cluster count.

`fsck_msdos -n` on the Apple volume gives two warnings: "Invalid long filename entry for volume label" and "Found 1 orphaned clusters". These warnings are in Apple's file. A volume that iPodFirm changes gives the same two warnings and no other warning (`ResourceVolumeTests.testMacOSAcceptsTheChangedVolume`). `fsck_msdos` does not compare the two FAT copies. The test of iPodFirm compares them.

## The files

All files are contiguous.

| File | Bytes | Glyphs | Strike |
|---|---|---|---|
| `/Resources/Fonts/CJK.ttf` | 3,446,748 | 17,082 | 18 ppem, 4 bit |
| `/Resources/Fonts/Helvetica_17.ttf` | 56,816 | 534 | 17 ppem, 4 bit |
| `/Resources/Fonts/Helvetica_23.ttf` | 81,440 | 534 | 23 ppem, 4 bit |
| `/Resources/Fonts/MonoHope_15_Italic.ttf` | 22,772 | 231 | 15 ppem, 4 bit |
| `/Resources/Fonts/MonoHope_15_Plain.ttf` | 21,612 | 230 | 15 ppem, 4 bit |
| `/Resources/Fonts/MonoHope_20_Italic.ttf` | 40,348 | 230 | 25 ppem, 4 bit |
| `/Resources/Fonts/MonoHope_20_Plain.ttf` | 37,592 | 230 | 25 ppem, 4 bit |
| `/Resources/Fonts/PodiumSans18.ttf` | 126,524 | 1,167 | 18 ppem, 4 bit |
| `/Resources/VideoCore/Boot/RenderServer.bin` | 104,540 | | |
| `/Resources/VideoCore/Boot/vmcs.bin` | 201,376 | | |
| `/Resources/VideoCore/Library/*.vll` (6 files) | 460,944 | | |

Each font has the tables `EBDT`, `EBLC`, `EBSC`, `LTSH`, `OS/2`, `cmap`, `gasp`, `glyf`, `hdmx`, `head`, `hhea`, `hmtx`, `loca`, `maxp`, `name` and `post`. The Korean characters are in `CJK.ttf`.

## How RetailOS loads a font (Ghidra)

| Address | Result | Evidence |
|---|---|---|
| 0x242e50 | Opens the font of a font object. It joins `Resources/Fonts` (0x242f44) and the name at object + 0x58. It calls 0x226000 with `(object, path, 1, 4, 0x2000, 3, 0)` and keeps the result at object + 0x8c. Object + 0x90 is 1 when the open is correct. | Static |
| 0x226000 | Makes a file object with a block cache: the arguments 4 and 0x2000 are probably 4 blocks of 8 KB. The disk channel "FontFileAccess" (0x2122a4) is for these reads. | Static |
| 0x58edce, 0x5cbf72 … 0x5cc0bc, 0x63a4a2 | The 8 file names in osos. | Static (string search) |

Thus RetailOS reads the glyphs from the file when it needs them. The size of a font changes the use of the disk, not the use of RAM. Not measured in the emulator.

## The change in iPodFirm

- `ResourceVolume` (`mac/Sources/IPodFWKit/ResourceVolume.swift`) reads and changes the FAT volume. A change keeps the boot sector, the geometry, the label and the directories. It frees the clusters of the file, writes zeros into them, and writes the new content into the first free area that fits it. If no area fits, all files go again in their order. The two FATs stay equal.
- `IPodFonts.check` accepts a font only with one of the 8 names, and with the same strikes as the Apple font.
- With no custom fonts, rsrc stays byte for byte the Apple rsrc.

The tests are in `mac/Tests/IPodFWKitTests/ResourceVolumeTests.swift`.

## Open

- Test in the emulator: a changed `CJK.ttf` must show on the screen.
- Test on a real iPod with the fonts of the reporter.
- The fonts of iPodWizard: the reporter can import them from an iPodFirm backup of the time before the flash (**Import from File…**). A backup has the rsrc of the iPod.
