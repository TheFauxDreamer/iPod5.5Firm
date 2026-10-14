# Safety

This document describes the limits that iPodFirm obeys, the checks before and during a flash, the backups and the recovery. It also lists the known problems and the parts that are not tested.

WARNING: A firmware change can stop the iPod at start. Read the [Recovery](#recovery) section before the first flash. Make sure that the battery is charged.

## The boundaries

iPodFirm obeys these limits. The code enforces each limit. The "Where" column gives the code.

| Limit | Reason | Where |
|---|---|---|
| Never write the NOR flash. | The boot loader and disk mode are in the NOR flash. Disk mode is the recovery path. | No code can write it. |
| Never change, move or write `aupd`. | `aupd` is the only image that writes the NOR flash. | `replaceImage` refuses `aupd`. `checkCompatible` refuses a different `aupd`. `planWrites` refuses a write that overlaps `aupd`. |
| Never write `hibe`. | The iPod writes its RAM state there. An old copy is incorrect. | `preserveHibernation` copies the current `hibe` entry and data into the new image. |
| Write only the firmware partition. | The music partition belongs to the owner. | The helper writes only inside the partition that `locatePartition` found. |
| Support only the iPod Video (model code 0xB0). | The formats and the addresses are for this model. The iPod classic firmware is encrypted and signed. | `checkModel` (first the Samsung layout; also before a backup), `Backups.save`, `isVideo` checks. |
| Apply a patch only to Apple osos 1.3. | The addresses are for this version. | `osos_sha256` in each `patch.json`, theme and version check. |
| Examine a user patch before the install. Let a patch write files only below `iPod_Control/` on the iPod. | A user patch comes from another person. | `PatchLibrary.validate`, `PatchUI.isSafePath`, `PatchUI.maxWrite`. The install sheet tells the owner to install only patches from people that the owner trusts. |
| Do not turn on two patches that change the same place. | The build fails, or one patch breaks the other. | `Patcher.conflicts`, `AppModel.setPatch`. |
| Keep osos below 0x7F8000. | The reset code stops if the image end is after 8 MB (0x800004). The 32 KB below 8 MB are a margin. No code uses the RAM there (static search and an emulator write watch), but a DMA write cannot be excluded. Not tested on a real iPod with an image end above 0x7F0000. | `ThemeImport.ososLimit`, `maxSize` in `Patcher.apply` (also for extended patches). |
| Keep the patch code below 0x736800, or make it an extended patch. | rsrc starts at 0x736800 in Apple's layout. An extended patch goes after all other data and makes the build move rsrc. | `Patcher.maxOSOSSize`, `Patcher.extendedBase`. |
| Do not put data in the zero area at 0x6ca452. | The firmware stops at start if this area is not zero. | The theme import uses only the area after osos. |
| Never change the opened file or a backup. | A backup must stay correct. | "Save Firmware As…" refuses the Backups folder. Backups get a new name each time. |
| Never apply program code changes from a theme. | The import cannot verify them. | `ThemeImport.make` records them as "skipped". |

## The checks before a flash

The helper does these checks in `Operations.flash` ([Operations.swift](../mac/Sources/IPodFWKit/Operations.swift)). Any failed check stops the flash before a write.

1. Find the iPod again by its disk name. It must still be connected.
2. Find the firmware partition (MBR or APM).
3. Read the complete partition.
4. Identify an iPod with a Samsung CPU (iPod classic): the directory is at +0x1000, not at +0x200. Stop with the code `unsupported-ipod`. Refer to [re/ipod-classic-6g.md](../re/ipod-classic-6g.md#detection-in-ipodfirm-fixed-on-6-october-2026).
5. Read the model code. Stop if the iPod is not an iPod Video.
6. Read the partition as a firmware partition. If this fails, stop with the code `firmware-unreadable`. The app then offers the rescue restore.
7. Make sure that the new image is not larger than the partition.
8. Put the new osos and rsrc into the layout of the iPod (`fitLayout`).
9. Copy the `hibe` entry and data of the iPod into the new image (`preserveHibernation`).
10. Make sure that the new image is for the iPod Video.
11. Compare the new image with the iPod (`checkCompatible`):
    - The same image base and directory offset.
    - The same count of images.
    - Each image has the same type and position. Only rsrc can move.
    - Each directory entry other than osos, rsrc and hibe is the same.
    - rsrc does not overlap osos, aupd or hibe, and it ends inside the image.
    - The osos and rsrc checksums are correct.
    - aupd is the same, byte for byte.
12. Make a list of the blocks that are different (`planWrites`). Stop if a block overlaps aupd.

With `--dry-run`, the helper stops here and returns the list.

## The write

1. Save a backup of the current partition (refer to [Backups](#backups)). The backup must read back correctly.
2. Unmount the iPod disk (`diskutil unmountDisk`).
3. Write each changed block range.
4. Call `fsync`.
5. Read each range again and compare it with the new data. If a range is different, stop with the name of the backup to restore.

iPodFirm writes only the blocks that changed.

## Backups

`Backups.save` in [Operations.swift](../mac/Sources/IPodFWKit/Operations.swift) does these steps:

1. Make sure that the data is a firmware partition of an iPod Video. A damaged partition is saved too, but with the model `damaged`.
2. Write `<date> <reason>.bin` in `~/Library/Application Support/iPodFirm/Backups/`.
3. If `Original (first backup).bin` does not exist, write it too. A damaged partition never becomes the original.
4. Read each file again and compare it with the data.
5. Write the metadata `<name>.bin.json`: date, reason, model, media name, size, SHA-256, disk size.

The helper saves a backup before each flash, each restore and each rescue restore. iPodFirm never deletes or overwrites a backup.

CAUTION: The backups contain Apple code and the state of your iPod. Do not commit them to Git and do not share them.

## The rescue restore

An interrupted write can leave a firmware partition that does not parse. A normal restore cannot compare the backup with such a partition. The rescue restore (`Operations.rescueRestore`) uses `Original (first backup).bin` as the reference. It does these checks:

1. The partition on the iPod is really damaged.
2. The original backup exists and is from an iPod Video.
3. The original backup has the same size as the partition on the iPod.
4. The media name and the disk size in the metadata of the original backup agree with the iPod.
5. The selected backup parses and is for the iPod Video.
6. The selected backup agrees with the original (`checkCompatible`), with the same aupd.
7. No planned write overlaps aupd. If the damage includes aupd, stop and tell the owner to use Finder.

Before the write, the helper saves the damaged partition as a backup with the model `damaged`. The app cannot restore this backup.

## Recovery

CAUTION: Charge the iPod before a recovery. An iPod with an empty battery does not show disk mode.

A firmware write cannot damage disk mode. Disk mode is in the boot loader in the NOR flash.

If the iPod does not start after a flash, do these steps:

1. Push and hold Menu and Select until the iPod restarts.
2. When the Apple logo shows, push and hold Select and Play until the iPod shows disk mode.
3. Connect the iPod to the Mac.
4. In the iPod pane, click "Restore…" on a backup.

If iPodFirm cannot restore a backup, do these steps:

1. In the Recovery section of the iPod pane, click "Restore with Finder…".
2. In Finder, select the iPod.
3. Push and hold the Option key, then click "Restore iPod".
4. Select `iPod_25.1.3.ipsw`.

CAUTION: A restore with Finder erases the music on the iPod.

Diagnostic mode can test the disk. Push and hold Menu and Select. Then push and hold Select and Previous.

## The test evidence for a moved rsrc

The dark theme makes osos larger and moves rsrc. These facts support a safe recovery:

- Disk mode is in the boot loader in the NOR flash (Rockbox manual). iPodFirm never writes or moves aupd.
- RetailOS finds rsrc through the directory, by its type and ID (Ghidra, function 0xc60ec).
- Rockbox `ipodpatcher` also moves rsrc when it installs its boot loader.
- In the emulator, the firmware did not write to the RAM of the background picture during a long test.
- On a disk image, a restore of the original backup gives the original partition again, byte for byte.
- On a real iPod 5.5G (2 October 2026), the firmware with the moved rsrc started and operated.

## The limits of the emulator tests

A test in the emulator is strong evidence, but not proof:

- The emulator makes its own boot ROM unless you give it a NOR dump.
- It does not test aupd.
- It has no audio and no USB.
- It does not model the hardware sleep or the backlight dimmer.
- Its drive is ready at once. It does not model the start time of a flash adapter.
- The write watch records CPU writes. It cannot record DMA writes.

## Test status

"Not recorded" means that the research notes do not record a test. Update this table after each test on the real iPod.

| Item | Emulator | Real iPod |
|---|---|---|
| Picture and text edits | Yes | Not recorded |
| Flash and backup | No (no USB) | Yes |
| Restore of a backup | No (no USB) | Not recorded. Tested on a disk image (`IPODFW_DISK_TEST=1`). |
| Rescue restore | No | Not recorded |
| Dark theme and moved rsrc | Yes | Yes (2 October 2026) |
| `album-art` | Versions 2.2–2.4: yes (9 and 10 October 2026) | Version 1.0: yes. Version 2.1: installed, the scroll is slow (9 October 2026). Version 2.2: measured (9 October 2026). Version 2.3, file mode: the scroll is much better (10 October 2026). Version 2.4, file mode with `cover-flow` 0.6.1: yes (10 October 2026); artwork mode with the file present: yes (10 October 2026); artwork mode without the file: yes, most rows are grey until a stop (10 October 2026). Version 2.5: the covers did not load (10 October 2026). Version 2.6: yes (14 October 2026) |
| `backlight-60s` | Menu only | No |
| `sleep-now` | Up to the hardware sleep | No |
| `flash-keep-awake` | Yes, without a sleep | 2-minute version only |
| `flash-wake-on-input` | Yes | No |
| `volume-unlimit` | Byte check only (the emulator has no EU limit and no audio) | No |
| `something-comforting` | Yes: the Settings item and the `tone` calls (no audio in the emulator) | No |
| `cover-flow` | Yes: hold, wheel, Select, Menu, short push; version 0.4 with 138 albums and built-in artwork; version 0.6.1 with `album-art` 2.4 and version 0.6.2 with `album-art` 2.6 (open, wheel, Menu) | Yes, version 0.1: hold, wheel, Menu, Dark Mode (2026-10-08). Version 0.6.2 with `album-art` 2.6 (2026-10-14) |
| `usb-host-probe` | Host start; version 1.2: the siTD link and removal (no USB in the emulator) | Yes, as a test: dock hub, storage and the USB-C EarPods enumerate (2026-10-08). The tone test: version 1.3 played the tone in the USB-C EarPods (2026-10-10). The music test: versions 1.5 and 1.6 played the music; the UI was very slow; a reconnection of the dock froze the iPod. Version 1.7 restarted the iPod after the tone; version 1.8 also restarted; version 1.9 not tested yet |
| Dark Mode switch | Yes | No |
| Software version | Not recorded | No |

## Known problems

- The owner reported slower scroll in lists with `flash-keep-awake`. The emulator shows that the patch code does not run during a scroll. The cause is not known.
- In the dark theme, the rating stars in Now Playing are almost invisible.
- After a computer session, the stock firmware defers Sleep for approximately 1 minute. `sleep-now` works around this. The cause is not known.
- The first screen after a start with the dark theme shows "Press Center to dismiss" in the title bar. The original theme on 1.2.1 has the same problem.
- The flash patches use more battery. The battery life with these patches is not measured.
