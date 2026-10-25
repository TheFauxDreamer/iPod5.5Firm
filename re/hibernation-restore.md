# The lost hibernation entry, the stale snapshot, and the moved rsrc

## The symptom

After the owner restored the iPod with iTunes (RetailOS 1.3, macOS), the app refused each patch with this error:

> The space after the last image is not empty; rsrc cannot move there.

The iPod ran an iPodFirm build before the restore. The research below shows that the start code of the iPod had removed the entry of the image `hibe` before the restore. The restore changed nothing. The error came from `make_room` in `partition.py` (and `makeRoom` in `Partition.swift`): without the entry, the space after the last image is the hibernation area, and the function refused to write `rsrc` over its data. The refusal was correct.

## What the restore did, measured

The owner's backups live in `~/Library/Application Support/iPodFirm/Backups/`. Each value below comes from a comparison of these backups.

| Backup | Date | osos | rsrc | aupd | hibe |
|---|---|---|---|---|---|
| Original | 1 October | dev 0x4800, 0x736000 bytes | dev 0x73b000, 0x500800 bytes | dev 0xc3c000, 0x106800 bytes | slot 3, dev 0xd43800, 0x4000800 bytes |
| Modified | 6–23 October | grown to 0x7f9800 bytes | moved to dev 0x4d44000 | unchanged | unchanged |
| Before the flash | 23 October, 21:12 | 0x7f9800 bytes | dev 0x4d44000 | loadAddr 0xffffffff | **entry present** |
| After the flash | 23 October, 21:23 | Apple 1.3 (0x736000 bytes) | Apple 1.3 (dev 0x73b000) | loadAddr 0x10000000 | **entry cleared: 36 zeros and the value 0xffffffff** |

The flash of 23 October 2026 wrote a restore of the Original backup. The backup of 21:12, before the flash, has the entry of `hibe`. The backup of 21:23, ten minutes after the flash, has 36 zero bytes in slot 3 and the value `ffffffff` in the last word. The entry of `aupd` changed at the same time: its loadAddr became 0x10000000. This is the work of the start code of the iPod in the NOR flash, not of the flash and not of the restore. The iTunes restore changed nothing: the backup of the next morning is byte for byte the same as the backup of 21:23.

The hibernation area stayed where it was, at partition offsets 0xd43000–0x4d44800. The area holds a valid header of a snapshot. The iPod does not write the area without the directory entry.

## The structure of the stale dump

- 4 KB at 0xd43000–0xd44000: the `booting!`/`hotstuff`/`battislo` boot page.
- 0x800 bytes at 0xd44000: the dump header. The first word is 1.
- 64 MB at 0xd44800: the RAM image. The first 0x800 bytes equal the osos vector table.

The iPod does not write the area without the directory entry. The area occupies exactly the place where `make_room` puts rsrc when the iPod has no `hibe` entry.

## The hibernation code in the boot block

Offsets are osos file offsets.

1. The literals at 0x534 and 0x538 hold `!ATA` and `ebih`. This is the only `ebih` in osos.
2. The handler at 0x388 scans the firmware directory through boot-ROM services (0x350 → 0x40003828, reads 0x40003260, header write 0x40003400, dump write 0x40001a34).
3. At 0x468 the handler compares the entry length with the value + 0x800. The dump length is 0x4000800 bytes: 64 MB of RAM plus the 0x800-byte header.
4. At 0x490 the handler compares the entry id. If no `ebih` entry exists, the handler writes nothing.
5. Nothing in the boot block or in the rest of osos creates a new `ebih` entry. The start code in the NOR flash removed the entry of this iPod. That code is not in the repository; the research did not read it.

## The safety decision

The fix must not write the stale dump area while the iPod has no `hibe` entry. But it must not try to repair the hibernation, either. Do not create a new `hibe` entry:

- The first word of the dump header is 1. We do not know what this word means. It may be a resume flag. A resume into stale RAM is a risk.
- The boot code writes a dump only when an entry exists. Without an entry, the iPod does not write a dump.
- The start code of the iPod removed the entry of this iPod at its start after a flash. An entry that the app writes back may not survive the next start. The document [safety.md](../docs/safety.md) records the loss of the hibernation as a known problem.

Open item: read the 0x800-byte dump header word by word, and read the start code of the NOR flash. This work must come before any future "repair the hibernation" feature.

## The fix

`make_room` finds the first all-zero area that fits rsrc, not only the area right after the last image. `fit_layout` also rebuilds the layout when the file and the iPod differ in the `hibe` entry. Refer to [dark-theme.md](dark-theme.md) for the earlier rsrc move.

On this iPod, the fix puts rsrc at dev 0x4d44000 (partition 0x4d44800): the same position that the old modified firmware used for many weeks. The hibernation area stays where it is. The iPod does not use it without the entry.

## Test on the real iPod (25 October 2026)

The owner flashed two builds on the iPod with the fixed app (0.1.148, build 149).

| Step | osos | rsrc | Result |
|---|---|---|---|
| Before the first flash (10:38) | 0x736000 bytes | dev 0x73b000 | The Apple layout, 3 images, the hibernation area present. |
| First flash | 0x744000 bytes | **dev 0x4d44000** | The scan put rsrc past the hibernation area and wrote nothing into it. The iPod started. |
| Second flash (10:58) | 0x7f9800 bytes | dev 0x4d44000 | `fit_layout` rebuilt the file layout into the iPod's layout. The iPod started and mounted. |

The hibernation area kept its content after each flash (the `booting!` block at partition 0xd43000 did not change). The backups of 10:38 and 10:58 record these states.