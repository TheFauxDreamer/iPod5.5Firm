# Firmware format

This document describes the data that iPodFirm reads and writes. It covers the firmware partition, the image directory, the osos memory map and the resource formats in osos. The values are for the iPod Video with Apple firmware 1.3.

The formats come from iPodWizard (`firmware.cpp`, `Picture.cpp`) and from Rockbox `ipodpatcher`. The project tests verify them against Apple's 1.3 file. The code is in [Partition.swift](../mac/Sources/IPodFWKit/Partition.swift), [Resources.swift](../mac/Sources/IPodFWKit/Resources.swift) and [Pictures.swift](../mac/Sources/IPodFWKit/Pictures.swift). The Python tool has the same code in [src/ipodfw/](../src/ipodfw/).

## The location of the firmware partition

The firmware partition is the first partition of the iPod disk. iPodFirm finds it with `FirmwareFlasher.locatePartition` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift). It accepts two partition tables:

| Table | Test | Result |
|---|---|---|
| MBR (Windows-formatted iPod) | Bytes 510–511 are `55 AA`. Entry 0 (at 0x1BE) has type 0 and a count larger than 0. Entry 1 has type 0x0B or 0x0C (FAT32). | Start = LBA start of entry 0 × block size. Size = sector count × block size. |
| APM (Mac-formatted iPod) | Sector 0 starts with `ER`. | The code examines each `PM` entry. It selects the entry with the name `Apple_MDFW` at bytes 48–57. Start and size are big-endian values at +8 and +12. |

Any other layout gives the error "Unrecognised partition table." iPodFirm then does not write.

## The partition header

| Offset | Size | Content |
|---|---|---|
| 0x000 | 16 | The Apple STOP banner. It must start with `{{~~  /-----\   `. |
| 0x100 | 4 | The magic `]ih[`. |
| 0x104 | 4 | u32 LE: the directory offset − 0x200. On the 5.5G the directory is at 0x4200. |
| 0x10A | 2 | u16 LE: the partition format version. It is 3 on the iPod Video. |

The directory is at the value at 0x104 + one sector. The iPod Video uses 512-byte sectors, so the directory is at 0x4200. The iPod classic uses 4096-byte sectors, so its directory is at 0x5000. iPodFirm uses the second position only to identify a classic and to refuse it. Refer to [re/ipod-classic-6g.md](../re/ipod-classic-6g.md).

## The image directory

The directory has a maximum of 10 entries of 40 bytes. An entry is valid if it starts with `!ATA` or `DNAN`. All values are u32 little-endian.

| Offset | Field | Content |
|---|---|---|
| +0 | dev | `!ATA` (disk) or `DNAN` (NAND). |
| +4 | type | The image name, byte-reversed. |
| +8 | id | The image ID. |
| +12 | devOffset | The start of the image, relative to the image base. |
| +16 | len | The length of the image in bytes. |
| +20 | addr | The load address in SDRAM. For osos it is 0x10000000. |
| +24 | entryOffset | The entry point. If it is not 0, iPodFirm uses it as the length of Apple's code, so that an added Rockbox boot loader is not included. |
| +28 | chksum | The checksum of the image. |
| +32 | vers | The version. Bits 8 and up identify the model, for example 0xB0 = "Video (5G/5.5G)". |
| +36 | loadAddr | A second load address. |

The type names are byte-reversed:

| Stored | Name | Content |
|---|---|---|
| `soso` | osos | RetailOS code and the UI resources, 7.2 MB. |
| `crsr` | rsrc | A FAT16 file system at offset 0x600 with fonts (`/Resources/Fonts/*.ttf`) and the programs for the Broadcom BCM2722 video processor (`/Resources/VideoCore/`), 5.0 MB. |
| `dpua` | aupd | The encrypted boot-flash updater, 1.0 MB. |
| `ebih` | hibe | The hibernation image. Only an iPod partition has it. A firmware file does not. |
| `kbso` | osbk | A backup of osos. Firmware 1.3 does not have it. |

On firmware 1.3 the osos entry has devOffset 0x4800 and length 0x736000. rsrc starts 0x736800 bytes after osos. Thus the gap after osos is 2 KB.

## The image base

The image base is the partition offset of devOffset 0. iPodFirm does not use a fixed value. It tries 2048, 512, 1024, 4096 and 0, in this sequence. It keeps the first value where the osos checksum is correct. On the 5.5G the image base is 2048. Thus osos starts at partition offset 0x800 + 0x4800.

## The checksum

The checksum is a 32-bit sum of all bytes of the image. The sum wraps at 2^32. There is no signature. The boot loader in the NOR flash examines only this sum.

The checksum of osos and of rsrc is a plain byte sum. The checksum of aupd is not a plain byte sum, because aupd is encrypted. iPodFirm never calculates or changes the aupd checksum.

When iPodFirm replaces an image (`replaceImage`, [Partition.swift](../mac/Sources/IPodFWKit/Partition.swift)), it does these steps:

1. It refuses the name `aupd`.
2. It makes sure that the new image fits before the next image.
3. It writes the new image and fills the remainder of the old image with zeros.
4. It sets the new length and the new byte sum in the directory entry.

## The firmware file (.ipsw)

An `.ipsw` file is a ZIP archive. It holds `manifest.plist` and one `Firmware-*` file. The key `FirmwarePayload.FirmwareName` in the manifest gives the name of the firmware file. The firmware file has the same format as the iPod's firmware partition. It does not have a hibe image, and it has no free space after the last image.

## The osos memory map

The code runs at the same addresses as the offsets in the osos image. The table gives the important areas.

| osos offset | Content |
|---|---|
| 0x000000 | The vector table. The text "portalplayer" is at 0x20. |
| 0x000308 | The reset code compares the end of the image (the value 0x7358c0) with 0x800004. Thus the image can be up to 8 MB. |
| 0x331da0 | The main resource block (BMap, Str, View, Menu, Type, TCmd). |
| 0x4b441c | `TCmd` 9088: the compiled JavaScript of the user interface. |
| 0x6ca452 | A zero area of 310 KB. The firmware needs it to be zero. If data is put there, the iPod stops at start. |
| 0x7358c0 | The end of Apple's code and data. |
| 0x7358c0 | A marker: the bytes `55 AA 55 AA` (the little-endian word 0xAA55AA55). |
| 0x7358d0–0x73658c | The area of the `album-art` patch (3260 bytes). The code uses 3168 bytes. |
| 0x73658c–0x736644 | The `sleep-now` patch (181 bytes). |
| 0x736644–0x736700 | The `flash-keep-awake` patch (188 bytes). |
| 0x736700–0x736784 | The `flash-wake-on-input` patch (132 bytes). |
| 0x736784–0x736800 | Free (124 bytes). |
| 0x736800 | The maximum osos size for patches (`Patcher.maxOSOSSize`). It is the start of rsrc in Apple's layout. |
| 0x736800–0x7E8000 | Theme data and the Dark Mode switch. This area is available only when iPodFirm moves rsrc. |
| 0x7E8000 | `ThemeImport.ososLimit`: the upper limit for theme data and the Dark Mode items. |
| 0x7E8000–0x7F0000 | The extended patch area (`Patcher.extendedArea`). `usb-host-probe` is at 0x7e8000. This area is available only when iPodFirm moves rsrc. |
| 0x7F0000 | The upper limit for all added data. |

The RAM after the image is free. The memory set-up at 0xc90 starts a region at physical address 0x10800000 (8 MB). The allocator pool object is at 0x1081da00, in that region. No code refers to the area between the image end and 8 MB. An emulator test with a write watch found no CPU writes there, other than to the patch variables. This test cannot detect DMA writes.

## Resource blocks

osos has 25 resource blocks. One main block holds 403 pictures (`BMap`), 991 strings, 619 `View` records, 40 `Menu` records, 158 `Type` records and the `TCmd` resources. 24 language blocks hold the translated strings.

The block format is:

```
block header  u32 3, u32 tables_len, u32 num_sections
section[n]    type[4] (byte-reversed, for example "paMB" = BMap), u32 num_items,
              u32 t1, u32 table_start (relative to the block header)
resource[]    i16 id, u16 unk, u32 offset (relative to the block data), u32 size
data          starts at header + tables_len
```

A block is valid if `12 + 16 × num_sections + 12 × total_items == tables_len`. Each resource table entry is 12 bytes. To move a resource, iPodFirm writes a new offset at +4 and a new size at +8 of its entry.

## Pictures (BMap)

A picture has a 28-byte header and then the pixel rows.

| Offset | Field |
|---|---|
| +0 | u16 texture format |
| +2 | u16 (unknown) |
| +4 | u16 bytes per row |
| +6 | u16 bit depth |
| +8 | 8 zero bytes |
| +16 | u32 height |
| +20 | u32 width |
| +24 | u32 data length |

| Format | Depth | Pixels | Count in 1.3 |
|---|---|---|---|
| 0x0565 | 16 | RGB565, little-endian | 251 (with 0x2565) |
| 0x2565 | 16 | RGB565, big-endian | |
| 0x1444 | 16 | ARGB4444, little-endian | 117 |
| any | 4, 2, 1 | Grey levels. 0 is white. The pixel in the most significant bits comes first. | 21 (4-bit), 14 (2-bit) |

iPodFirm accepts a picture only if the width and the height are 1024 or less and the depth is 1, 2, 4 or 16. A replacement picture must have the same size. iPodFirm writes only the pixel bits, so the row padding does not change.

## Strings (Str)

Strings are UTF-8, end with a zero byte, and start on a 4-byte boundary. iPodFirm packs all the strings of one language again inside the same area. It refuses these conditions:

- an unknown string ID
- a resource of a different type in the string area
- strings that need more bytes than the area has

Thus, to make one text longer, make other text in the same language shorter.

## View, Type and Menu

[modifications.md](modifications.md#the-view-format) gives the View element layout and the Menu item layout. These formats come from the dark theme research. iPodFirm changes them only with the theme import and the Dark Mode build.
