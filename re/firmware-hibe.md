# The hibernation area and the lost entry of the directory

This note gives the result of the research of the image `hibe` of the firmware
partition of the iPod. This is the second research of the image. The first
research found the data after the last image and made a repair. The research
of this note compared **all** the backups of the iPod, byte for byte, and
corrected the first research.

The research answers five questions.

1. What did the flash of 23 October 2026 write?
2. Who removed the entry of the image `hibe` from the directory?
3. What is the data after the last image?
4. Why does the app refuse to flash a patch?
5. How does the app repair the partition?

The result is in the first section of each part. The research gives the
evidence. The reference [../docs/firmware-functions.md](../docs/firmware-functions.md)
gives the short form.

The note continues the research of [games-keyfile.md](games-keyfile.md) and
[firmware-hibernation.md](firmware-hibernation.md). The note
[firmware-hibernation.md](firmware-hibernation.md) gives the format of the
image and the code of the hibernation.

## The result in short

| The question | The answer |
|---|---|
| What did the flash of 23 October write? | The flash wrote the backup **Original (first backup)**. The proof is in four changes: the gap block at 0x00d43000 became the copy of the Original backup; the moved copy of `rsrc` at 0x04d44800 was cleared; the image `osos` became the stock image; the image `rsrc` returned to 0x0073b000. The flash wrote the entry of the image `hibe` in the directory. The flash did not write the hibernation area. |
| Who removed the entry? | **The iPod itself.** The comparison of the backup of 21:23 with the backup of 21:12 of 23 October shows the flash wrote the entry. The backup of 21:23, taken ten minutes after the flash, has 36 zero bytes in the entry and the value `10000000` in the entry of `aupd`. The iPod did this at its start after the flash. The code is in the NOR flash. The research could not read it. |
| What is the data? | The hibernation area of the iPod, at its fixed place. The header of the snapshot is valid: the version 1, the page size 0x20000, 64 pages. The area holds the memory of the iPod of the sleep before the flash of 23 October. A block of 0x1000 bytes sits before the area, at 0x00d43000. The block is a copy of the first page of the image `osos` in the memory. The block changes at each flash. |
| Why does the app refuse to flash? | The function `makeRoom` moves the image `rsrc` to the space after the last image. Without the entry, the last image is `aupd`, and the space holds the hibernation area. The function saw the data of the area and refused to write `rsrc` over it. The refusal was correct: the data is the memory of the iPod. |
| How does the app repair the partition? | The function `makeRoom` now finds the hibernation area by the header of the snapshot and parks `rsrc` after the area. A patch flashes with or without the entry. The optional repair writes the 40-byte entry back into the directory and changes no data. |

> CAUTION: The first research of this note was wrong in three claims. The
> flash of 23 October did not remove the entry; the iPod removed the entry
> after the flash. The data after the last image is not "a copy of a patched
> `osos` and a later image of the memory"; it is the hibernation area at its
> fixed place, plus one block that changes at each flash. The restore with
> iTunes did not change the partition: the backup of 24 October is byte for
> byte the same as the backup of 21:23 of 23 October.

## Part 1: the evidence from all the backups

### The method

The research read the nine backups of the folder Backups, the staging file of
the app, the file `custom-firmware.bin`, the custom `.ipsw` of 1 October, and
the firmware file of Apple. The research read the directory of each file, the
gaps between the images, and the data after the last image. The research then
compared the backup before the flash of 23 October with the backup after the
flash, block by block, with a block size of 0x800 bytes.

### The directory of every backup

| The file | The osos | The place of rsrc | The entry of hibe | aupd loadAddr |
|---|---|---|---|---|
| Original, 1 Oct | stock, 0x736000 | 0x0073b000 | present | ffffffff |
| 6 Oct, before flash | patched, 0x7eb000 | 0x04d44000 | present | ffffffff |
| 6 Oct, before flash | patched, 0x7eb000 | 0x04d44000 | present | ffffffff |
| 22 Oct, before flash | patched, 0x7f9800 | 0x04d44000 | present | ffffffff |
| 23 Oct 21:12, before flash | patched, 0x7f9800 | 0x04d44000 | present | ffffffff |
| 23 Oct 21:23, after flash | stock, 0x736000 | 0x0073b000 | 36 zero bytes | 10000000 |
| 24 Oct, manual | stock, 0x736000 | 0x0073b000 | 36 zero bytes | 10000000 |
| 24 Oct, manual | stock, 0x736000 | 0x0073b000 | 36 zero bytes | 10000000 |

The healthy patched backups all have `rsrc` at **0x04d44000**, after the
hibernation area. The layout was stable for three weeks.

> The place of the image `rsrc` proves the old approach worked: the flash of a
> patched `osos` parked `rsrc` after the area, and the next flash found it
> there.

### The comparison of 21:12 and 21:23 of 23 October

The research compared the two backups block by block. The result has 95
ranges of different blocks. Every range is one event: the write of the backup
**Original (first backup)** over the partition.

| The range | The change |
|---|---|
| 0x00004000 (2 KB) | The directory block. The entry of `osos` and `rsrc` became the stock entries, the entry of `hibe` was written **present**, the field of `aupd` kept `ffffffff` at that moment. |
| 0x00099000 .. 0x006cd800 (about 70 ranges) | The image `osos`: the patched bytes went back to the stock bytes. |
| 0x0073b000 .. 0x007fe800 (782 KB) | The image `rsrc` was written back at its stock place 0x0073b000. |
| 0x00d43800 (2 KB) | The gap block at 0x00d43000 became the copy of the Original backup. |
| 0x04d44800 .. 0x05244800 (about 4 MB in 14 ranges) | The moved copy of `rsrc` was cleared to zero. |

The checksum of the `osos` of the backup of 21:23 is `2c7c48f3`, the checksum
of the stock image. The flash wrote the complete partition of the Original
backup, with the entry of `hibe` present.

> The flash of 23 October was **correct**. The app wrote the entry of the
> image `hibe`. The removal of the entry came after the flash.

### The change that the iPod made

The backup of 21:23 differs from the result of the flash in two fields of the
directory only:

| The field | The value |
|---|---|
| The entry of `hibe`, the first 36 bytes | zero |
| The entry of `aupd`, the last 4 bytes (loadAddr) | `10000000` for `ffffffff` |

The last 4 bytes of the entry of `hibe` kept `ffffffff`. The iPod cleared the
36 first bytes of the entry and wrote the load address of the memory into the
entry of `aupd`. The two backups of 24 October, after the restore with iTunes,
are byte for byte the same as the backup of 21:23.

> The iPod wrote the directory at its start after the flash. The code that did
> this is in the NOR flash. The research could not read the code: the copy of
> the NOR flash of the iPod is not on the machine of the owner. The research of
> [firmware-hibernation.md](firmware-hibernation.md) found that the setup of
> the image `hibe` reads the entry through the bootloader and writes the entry
> back after a check. The iPod writes the directory entry itself.

### The trigger

The research of [firmware-hibernation.md](firmware-hibernation.md) gives the
settings of the hibernation. The restore with iTunes removed the files
`iPod_Control/Device/_hibe_sleep` and `_disable_hibe` from the iPod. The
folder `iPod_Control/Device/` of the mounted iPod holds no `_hibe_sleep` file
at the date of this note.

> The iPod cannot bring the entry back by itself. The setup of the image
> `hibe` writes the entry only when the lookup of the image finds it. Without
> the entry there is no write, and without a sleep there is no snapshot. Only
> the app can write the entry.

## Part 2: the data after the last image

### The result

The data after the last image is the hibernation area of the iPod, at its
fixed place. The area is **not** lost and does not need a backup.

| The place in the file | The size | The content |
|---|---|---|
| 0x00d43000 .. 0x00d44000 | 0x1000 | The gap block. A copy of the first page of the `osos` in the memory, with a block of data at +0x808 that changes at each flash. |
| 0x00d44000 .. 0x00d44800 | 0x800 | The header of the snapshot: the version 1, the page size 0x20000, 64 pages, the mask 0x88888888888fffff. |
| 0x00d44800 .. 0x04d44800 | 0x4000000 | The memory of the iPod, 64 MB. |

The header is the same in the three broken backups and in the backup of
21:12: the mask `0x88888888888fffff`, the pattern `0x88`. The area holds the
memory of the iPod of the sleep before the flash of 23 October. The iPod did
not write a new snapshot after the flash: the restore removed the setting
`_hibe_sleep`, thus the iPod sleeps without the hibernation.

> The first research read the data as "a copy of a patched `osos` and a later
> image of the memory". The copy of the `osos` is the payload of the snapshot:
> the memory of the iPod holds the `osos` at its place in the memory, 0x1000.
> The research compared the payload with the `osos` of the partition and found
> the same bytes at the same places. The data is the snapshot, at the correct
> fixed place.

### The gap block

The block at 0x00d43000 is 0x1000 bytes between the end of `aupd` and the
header of the snapshot. The block is a copy of the first page of the `osos` in
the memory: the strings `booting!`, `hotstuff`, `battislo` are at the same
places as in the `osos` at 0x1000.

The block is not the same in every backup:

| The backup | The block |
|---|---|
| Original, 1 Oct | G1: the code of the stock `osos` |
| 6 Oct 09:42 | different from G1 in 2034 bytes |
| 6 Oct 13:11 | G1 again |
| 22 Oct | G1 |
| 23 Oct 21:12 | G2: the code of the patched `osos` of that day |
| 23 Oct 21:23 and later | G1 |

The block changes at each flash and follows the `osos` of the partition. The
block holds a field of 32 bytes at +0x808 that changes at each flash. The
research could not identify the field: it is not a hash of the `osos` (the
research tried SHA-256, SHA-1 and MD5 of several forms).

> The block is the first page of the memory of the iPod, 0x1000, written
> before the header of the snapshot. The header of the snapshot is at
> 0x00d44000, and the payload starts at 0x00d44800. The page at 0x1000 of the
> memory is the `osos`, because the boot loader loads the `osos` at the place
> 0x1000 of the memory.

### The size of the area

The area is 0x4000800 bytes: the header of 0x800 bytes and the memory of
64 MB. The header gives 64 pages of 0x20000 bytes. The memory is one megabyte
for each page: 64 pages give 64 MB. The research of
[firmware-hibernation.md](firmware-hibernation.md) proved the number: the code
shifts the size of the RAM by 0x14, and the RAM of the iPod Video is 64 MB.

> The function `makeRoom` uses this rule: the area is the header of 0x800
> bytes plus one megabyte for each page of the header.

## Part 3: the repair

### The result

The repair is minimal and optional.

- **A patch flashes with or without the entry.** The function `makeRoom` finds
  the hibernation area by the header of the snapshot and parks the image
  `rsrc` after the area, at 0x04d44000. No flash depends on the entry any
  more.
- **The repair writes the 40-byte entry only**, when the area is intact. The
  data of the area does not change: the area holds the memory of the iPod, and
  the memory is newer than any backup. The fields of the entry come from the
  healthy partitions: the id 1, the load address 0x10000000, the second load
  address 0xffffffff, the checksum 0.
- **The repair clears the area and writes a snapshot from a backup** only
  when the area has no valid header. The function refuses to clear data that
  it cannot identify.

### The code

| The part | The file | The work |
|---|---|---|
| The place of the area | `src/ipodfw/partition.py`, `mac/Sources/IPodFWKit/Partition.swift` | The function `hibe_area`. The entry of `hibe` when the directory has it, or the header of the snapshot at the fixed place after `aupd`. |
| The entry of the image | The same files | The function `add_hibe_entry`. The function writes the entry into the first free slot of the directory and changes no data. |
| The parking of `rsrc` | The same files | The function `make_room`. The function parks `rsrc` after the area and refuses data that is not a hibernation area. |
| The flash layout | `src/ipodfw/device.py`, `mac/Sources/IPodFWKit/Device.swift` | The function `fit_layout`. The function builds the layout from the iPod, parks `rsrc` after the area, and adds the entry of the file when the iPod lost it. The data of the area of the iPod always stays. |
| The compatibility check | The same files | The function `check_compatible`. The check allows one extra image `hibe` at the place of the area, and refuses a `rsrc` over the area. |
| The repair | `src/ipodfw/hibe.py`, `mac/Sources/IPodFWKit/Hibe.swift` | The function `restore_hibe`. The entry only, or the snapshot from a backup when the area has no valid header. |
| The pane of the app | `mac/Sources/iPodFirm/IPodView.swift` | The section **Hibernation Image**. The button **Check the Hibernation Image** backs up the iPod and gives the state. The button **Repair the Hibernation Image** writes the entry through the normal flash path. |
| The tests | `tests/test_hibe.py`, `mac/Tests/IPodFWKitTests/IPodFWKitTests.swift` | The tests of the area, the parking, the entry, the flash and the check. |
| The tests with the real backups | `mac/Tests/IPodFWKitTests/FlashHibe.swift`, `mac/Tests/IPodFWKitTests/HibeAgree.swift` | The tests use the broken partition of the iPod of the owner. The tests build their own firmware files from the backup, thus the tests do not depend on the staging file of the app. |

### The check of the hibernation area

The check reads the header at the fixed place:

| The field | The value |
|---|---|
| The version | 1 |
| The page size | 0x20000 |
| The pages | 1 .. 128 |
| The end of the area | the header of 0x800 plus one megabyte for each page |

The place is `aupd` + the length of `aupd` + 0x1000. A header that does not
fit the rules means the data is unknown: the app refuses to write `rsrc` there
and asks for the repair with a backup or a restore with Finder.

### The repair in the app

The repair of the app writes the entry into the partition of the iPod:

1. The app backs up the iPod. The backup is the source of the bytes.
2. The app writes the entry into the bytes of that backup.
3. The app stages the result and flashes it with the reason `repair`.
4. The helper backs up the iPod again, then writes only the blocks that
   differ: the directory block of 2 KB.

The user interface shows the truth: a patch flashes with or without the entry.
The entry brings back the fast start, when the iPod accepts it. If the iPod
clears the entry again, nothing breaks: no flash depends on the entry.

## Part 4: the first research and the errors in it

The first research of this note, and the code that came from it, had three
errors.

| The claim of the first research | The evidence of this research |
|---|---|
| The flash of 23 October removed the entry of `hibe`, because the function `fitLayout` returned the file unchanged. | The flash wrote the Original backup with the entry present. The removal is in the backup of 21:23, taken after the flash. The old `fitLayout` could not return the file unchanged: the file had the entry, and the flash wrote it. The iPod removed the entry after the flash. |
| The data after the last image is a copy of a patched `osos` and a later image of the memory, 4,160,769 bytes. | The data is the hibernation area at its fixed place: a gap block of 0x1000 bytes, then the header and the memory of 64 MB. The count 4,160,769 is the count of the bytes that are not zero in the first 0x500800 bytes of the area. The area holds the memory of the iPod. The repair must not clear it. |
| The repair must write the image `hibe` from a backup and clear the data. | The area is intact. The repair writes the 40-byte entry only. A repair that clears the area destroys the memory of the iPod and puts an old snapshot in its place. |

The first research also said that the function `fitLayout` must refuse a
partition without the image `hibe`, and that the flash was not possible
before the repair. This research removed the refusal: the flash is possible,
and the layout of the iPod keeps the area.

## Part 5: what iPodWizard does

The project took the formats from iPodWizard. The research read the source of
the mirror at `github.com/DavidBuchanan314/iPodWizard-mirror`.

iPodWizard knows the image `hibe`: the function `CFirmware::SetFirmware`
reads the type `ebih` and sets no flag for it. The image `hibe` is never
edited. iPodWizard **never moves a partition and never changes the length of
a partition**: the function `CanWrite` accepts a write only inside an image
that the app may change. Thus iPodWizard never needs the space after the last
image, because it never makes the image `osos` larger.

The project makes the image `osos` larger, because the patches add code. The
project must move the image `rsrc`, and the hibernation area holds the space.

> The research of [dark-theme.md](dark-theme.md) gives the other project:
> Rockbox `ipodpatcher` moves all the images after the `osos` forward with
> the function `diskmove`. The project cannot do this, because the iPod
> expects the image `aupd` at its place and the hibernation area at its fixed
> place.

## The work that is left

1. ~~Test the repair and the flash on the real iPod of the owner.~~ **Done
   (25 October 2026).** The owner flashed the patches with the test build
   0.1.154. The flash worked on the partition without the entry of `hibe`.
2. Get the copy of the NOR flash of the iPod. The research needs it to find
   the code that clears the entry of `hibe` and writes the load address into
   the entry of `aupd`.
3. Find the meaning of the 32 bytes at +0x808 of the gap block. The bytes
   change at each flash.
4. Watch the entry of `hibe` after the repair. The iPod cleared the entry
   once, after a flash that wrote the entry. The research does not know if the
   iPod accepts a repaired entry.
5. Test the hibernation itself after the flash: put a byte 1 into the file
   `iPod_Control/Device/_hibe_sleep`, make the iPod sleep, and read the
   partition again. The research expects a new snapshot and a mask that
   changes. The entry of `hibe` and the layout must not change.
