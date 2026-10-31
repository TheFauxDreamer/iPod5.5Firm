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
| The removal of a game deletes only the folder of the game in `games_RO`, and only a name of hexadecimal characters. The owner confirms each removal. | The saves and the scores of the games are in the folders `gamedata_RW` and `gamestats_WO`. A mistake can delete the music or the files of the DRM. | `GameRemover.remove` refuses every other name. The sheet `RemoveGamesSheet` asks the owner for the confirmation. |
| Do not start a second iPod operation while the app is busy. | An eject during a backup or during the check before a flash stops the operation. | `AppModel.busy`, `AppModel.canFlash`. The commands are off, and `ejectIPod`, `backupNow`, `prepareFlash` and `flashEdited` stop. |
| Do not lose unsaved work at a quit or at a close of the window. | The app keeps the edits only in memory. | `AppModel.confirmQuit`, `WindowGuard`. Cancel is the default button. |
| Do not turn on two patches that change the same place. | The build fails, or one patch breaks the other. | `Patcher.conflicts`, `AppModel.setPatch`. |
| Keep osos below 0x7F8000. | The reset code stops if the image end is after 8 MB (0x800004). The 32 KB below 8 MB are a margin. No code uses the RAM there (static search and an emulator write watch), but a DMA write cannot be excluded. Real iPod (2026-10-15): with the USB Host Probe the album art of Now Playing did not load. The cause was a call of 0x19ff0c in the probe, not the image end (usb-host-probe 1.19). The setting "Layout" can select the limit 0x7FC000 (a margin of 16 KB, more space) or 0x7F0000 (64 KB). | `ThemeImport.ososLimit` (`ThemeImport.OSOSMargin`), `maxSize` in `Patcher.apply` (also for extended patches). |
| Keep the patch code below 0x736800, or make it an extended patch. | rsrc starts at 0x736800 in Apple's layout. An extended patch goes after all other data and makes the build move rsrc. | `Patcher.maxOSOSSize`, `Patcher.extendedBase`. |
| Do not put data in the zero area at 0x6ca452. | The firmware stops at start if this area is not zero. | The theme import uses only the area after osos. |
| Read the iPod without a write. | The app reads the patches on the iPod each time an iPod connects. | The helper command `read` (`Operations.readOSOS`) only reads the partition. It writes the osos to a file in `~/Library/Application Support/iPodFirm/`. Automatic only with the Touch ID daemon. |
| Never change the opened file or a backup. | A backup must stay correct. | "Save Firmware As…" refuses the Backups folder. Backups get a new name each time. |
| Never apply program code changes from a theme. | The import cannot verify them. | `ThemeImport.make` records them as "skipped". |

## The checks before a flash

The app does one check before it runs the helper. It does the check again before the write, after the owner confirms. A firmware write unmounts the iPod volume and stops a MiMusic sync.

- If a MiMusic temporary file is on the iPod volume, the app stops. The files are `iTunesDB.tmp`, `ArtworkDB.tmp` and `iPodFirmAlbumArt.tmp` (`MusicAppCheck` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift)).
- If MiMusic is open, the confirmation sheet shows a warning. The owner can quit MiMusic or continue.

Before the write, while the volume is still mounted, the app also does this step. The step applies if the image has no `shuffle-album-mix` (the word at osos 0x191e9c is not `cmp r0, #3`). The step also needs Album Mix on in `iPod_Control/Device/Preferences` (byte 0x8b, file version 0x39). The app then sets the byte to 0. Without this step, the firmware still loads the setting and shuffles the songs in each album, and no menu item can stop it. Settings > Shuffle then shows Albums. The result message tells the owner (`IPodPreferences` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift), `AppModel.clearAlbumMixIfNeeded`, the tests `testClearAlbumMix` and `testHasAlbumMix`). The command-line tool `ipodfw flash` does not do this step.

The helper does these checks in `Operations.flash` ([Operations.swift](../mac/Sources/IPodFWKit/Operations.swift)). Any failed check stops the flash before a write.

1. Find the iPod again by its disk name. It must still be connected.
2. Find the firmware partition (MBR or APM).
3. Read the complete partition.
4. Identify an iPod with a Samsung CPU (iPod classic): the directory is at +0x1000, not at +0x200. Stop with the code `unsupported-ipod`. Refer to [re/ipod-classic-6g.md](../re/ipod-classic-6g.md#detection-in-ipodfirm-fixed-on-6-october-2026).
5. Read the model code. Stop if the iPod is not an iPod Video.
6. Read the partition as a firmware partition. If this fails, stop with the code `firmware-unreadable`. The app then offers the rescue restore.
7. Make sure that the new image is not larger than the partition.
8. Put the new osos and rsrc into the layout of the iPod (`fitLayout`). When the file has a `hibe` image and the iPod has none, the result follows the iPod and has no `hibe` image.
9. Copy the `hibe` entry and data of the iPod into the new image (`preserveHibernation`). This step does nothing when the iPod has no `hibe` entry.
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

If a check stops the flash, the helper returns the message and `HelperResult.detail`. The detail has the file and the line of the failed check, and the last steps of the helper. The app writes the detail to its log, and a fault report contains it (refer to [app-and-device.md](app-and-device.md#the-log-and-the-fault-report)).

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
| Dark theme and moved rsrc | Yes | Yes (2 October 2026). The empty-area scan on a partition without the `hibe` entry (25 October 2026): two flashes, both started the iPod; the hibernation area stayed untouched. Refer to [../re/hibernation-restore.md](../re/hibernation-restore.md). |
| The patches on the iPod: the read, the iPodFirm list and the mirror of the switches | A firmware with the list starts (22 October 2026) | Yes (22 October 2026): the owner flashed, connected the iPod again, and the switches agreed with the iPod. A changed switch showed in the banner |
| `album-art` | Versions 2.2–2.4: yes (9 and 10 October 2026). Version 2.8 (27 October 2026): the first start writes the cache with one file open; the second start uses the cache with no fill; a changed `ArtworkDB` gives a new cache. Version 3.0 (27 October 2026): the collages of 2 playlists and of On-The-Go are correct | Version 1.0: yes. Version 2.1: installed, the scroll is slow (9 October 2026). Version 2.2: measured (9 October 2026). Version 2.3, file mode: the scroll is much better (10 October 2026). Version 2.4, file mode with `cover-flow` 0.6.1: yes (10 October 2026); artwork mode with the file present: yes (10 October 2026); artwork mode without the file: yes, most rows are grey until a stop (10 October 2026). Version 2.5: the covers did not load (10 October 2026). Version 2.6: yes (14 October 2026). Version 2.8 (27 October 2026): the cache operates: rows from the cache are as fast as the original draw; a sync makes a new cache; the open of the 104 MB `F1028_1.ithmb` takes 0.93 s, and the 2 s close gives 7 more opens during a fill. Version 2.9 (the file first, the close after 30 s): works great (27 October 2026). Version 3.0 (the playlist collages): the collages showed, but the Albums list loaded the covers only after each stop (27 October 2026). Version 3.1: works well (27 October 2026). Version 3.2 (the measurement off): operates (28 October 2026) |
| `backlight-60s` | Menu only | Version 1.1: yes (28 October 2026). Version 1.2 (selected time, new load address): starts and plays with the default time (30 October 2026). A short time and Sleep are not tested |
| `sleep-now` | Up to the hardware sleep | Version 1.2: yes (28 October 2026) |
| `flash-keep-awake` | Yes, without a sleep | The 2-minute version (2 October 2026). Version 1.1: yes (28 October 2026). Version 1.2 (selected time, new load address): starts and plays with the default time (30 October 2026). A short time and Sleep are not tested |
| `flash-wake-on-input` | Yes | Version 1.2: yes (28 October 2026). Version 1.3 (selected time): starts and plays with the default time (30 October 2026). A short time is not tested |
| `volume-unlimit` | Byte check only (the emulator has no EU limit and no audio) | No |
| `search-5g` | Byte check only (the emulator profile has `HwVr` 0x000b0010, refer to [re/search-5g.md](../re/search-5g.md#test-status)) | Not tested with iPodFirm. RetroCux tested the same byte on a 5G |
| `no-now-playing-timer` | Version 0.1 with the Split themes: the owner reported that it works well (31 October 2026) | No |
| `click-speaker-only` | Byte check only (the emulator has no audio) | Yes, version 1.0: the click plays only from the piezo (2026-10-27) |
| `shuffle-album-mix` | Yes (20 October 2026): the 4 values, the settings bytes and the order of Album Mix; also with all 13 patches that are not `internal` or `test`. Version 1.2 (22 October 2026): the main menu item and its Settings > Main Menu row, alone and with `album-artists` and `usb-audio-out` | Version 1.1 (20 October 2026): Album Mix shuffled the songs of one album. With Repeat All, the album plays with no end and stays shuffled. Version 1.2: operates (28 October 2026) |
| `shuffle-fixes` | Yes (20 October 2026): version 1.0 with 60 and 40000 tracks; version 2.0 with 60 tracks: the seed fix, the stock order with a fixed seed and the inner album shuffle (no audio in the emulator) | Version 2.1: yes (28 October 2026), with Next. Version 2.2 (30 October 2026, 5202 songs): a song plays to its end and the next song starts. Not tested: a song that plays to its end with a library near the limit of a 32 MB iPod; refer to [../re/shuffle.md](../re/shuffle.md#checks-of-the-shuffle-patches-with-a-large-library) |
| `something-comforting` | Yes: the Settings item and the `tone` calls (no audio in the emulator) | Version 1.1: yes (28 October 2026). Version 1.2 (selected time, new load address): starts and plays with the default time (30 October 2026). A short time and Sleep are not tested |
| `album-artists` | Yes (16 October 2026): the list, the albums and songs of an Album Artist, Artists and Genres after it, Now Playing; also with `album-art`, `cover-flow` and `something-comforting`. Version 1.1: the speed with 4000 tracks. Version 1.2: the Main Menu row and the main menu item (the emulator keeps no settings after a cold start) | Version 1.0 (16 October 2026): the list is correct, but the iPod stops for approximately 6 s when the list opens. Version 1.1 (16 October 2026): works well. Version 1.2 (16 October 2026): the Main Menu setting is lost at a restart with Menu+Select, as for the Apple rows (the firmware saves the settings only at a sleep or a disk change). Version 1.3: operates (28 October 2026) |
| `instant-save` | Yes (16 October 2026): the save runs at each change of a row, and the drive gets the write. The emulator keeps no settings after a restart | Version 1.0: yes (28 October 2026) |
| `cover-flow` | Yes: hold, wheel, Select, Menu, short push; version 0.4 with 138 albums and built-in artwork; version 0.6.1 with `album-art` 2.4 and version 0.6.2 with `album-art` 2.6 (open, wheel, Menu); version 0.6.4 with `up-next` 0.4: the hold follows Settings > Hold Select (21 October 2026) | Yes, version 0.1: hold, wheel, Menu, Dark Mode (2026-10-08). Version 0.6.2 with `album-art` 2.6 (2026-10-14). Version 0.6.4 with `up-next` 0.4: the hold follows Settings > Hold Select (2026-10-21). Version 0.6.4 after a restore with iTunes: very slow (2026-10-27). Version 0.6.5 (debug log): the log shows 1.1 s for each open of the artwork file (2026-10-27). Version 0.6.6: the file opens one time, frames of 69 ms, wheel steps lost (2026-10-27). Version 0.6.7: very fast, the wheel operates (2026-10-27). Version 0.6.8 (no debug log): operates (2026-10-28) |
| `up-next` | Yes (21 October 2026): Play Next with Shuffle on ("1 of 61", Next plays the new song, then the old order); the Settings item (the 3 values, the value after a restart). Version 0.4 with `cover-flow` 0.6.4: with no file, the start value Cover Flow; a hold on an album opens Cover Flow; after the change to Play Next, the same hold goes to Up Next and Cover Flow does not open. Play Last with Shuffle Songs, and Play Next with Shuffle Albums: the new songs play at the expected position. Refer to [../re/play-next.md](../re/play-next.md#emulator-tests-of-the-patch) | Yes, version 0.4 with `cover-flow` 0.6.4 (21 October 2026): the Settings item (the 4 values, the value after a restart); Play Next with Shuffle Off and with Shuffle Songs (the song plays next at the end of the current song, then the list continues); an album or an artist plays next; Play Last; Cover Flow and Play Next in the Albums list; the value On-The-Go; a hold with no music adds the songs to On-The-Go. Version 0.4 has a bug: its settings key is also the key of Daylight Saving Time. Version 0.5 (new key 0x60007e0f) corrects it: with 0.4 the row showed "Play Next"; with 0.5 it shows On or Off (real iPod, 21 October 2026). Version 0.5: operates (28 October 2026) |
| `custom-eq` | Version 0.1 (31 October 2026): the start, and the preset list in memory | Version 0.1: the owner reports that the patch operates. Version 0.2 and later (precut optional, named EQs), 5 active bands, filters above 59 on the real iPod and USB-C audio are not tested. |
| `playlist-folders` | Version 0.1 (29 October 2026, the owner in the emulator window): Folders First and Alphabetical, Select on a folder, a playlist in a folder, Menu back to the folder and to the top list, the next open of Playlists, the colour squares with `album-art` | Version 0.1 (29 October 2026, the owner): the folders operate. The colour squares did not show. Version 0.2 turns off the colours. |
| `usb-audio-out` | Yes: the Settings item, On and Off without a freeze (2026-10-17; no USB in the emulator); version 1.3: the Main Menu row and the main menu item On and Off, with `album-artists` 1.3; version 1.4: the host poll each 8 ms (a variant), On and Off | Yes (2026-10-17): all test steps passed (sync with Off, music, volume, buttons, disconnection and reconnection, Off back to the device mode, On/Off/On); the iPod charges during the music; version 1.1 (48 kHz): no problems heard (2026-10-17); version 1.2 (the rate in Settings): not tested yet; version 1.3 (the main menu item): not tested yet; version 1.4 (fewer wakes): still stuttery during USB music; version 1.5 (measurement): done (2026-10-17), USB music uses about 15 % more of core 0 than jack music; version 1.6 (more counts): Apple's fill takes 13 % of core 0; version 1.7 (fast fill): the sound correct, the fast fill did not run; version 1.8: tested at 48 kHz (the converter runs, about 12 % of core 0); at 44.1 kHz the fast fill operates, the sound correct, the scrolling better (2026-10-17); version 1.9: **failed** (2026-10-17): the headphones and the hub not found; a crash after a new connection and On again; cause not known. Version 1.9 again (2026-10-27): works well (the owner: "works great") |
| `playback-log` | No (29 October 2026: Swift and Python tests only) | Version 1.0 (owner, 30 October 2026, 64 MB, 5202 songs, 17 patches): the log operates. Version 1.1 removes the value `track`, which was not correct, and adds the settings. Versions 1.1 and 1.2 are not tested. Refer to [../re/playback-log.md](../re/playback-log.md#first-log-from-a-real-ipod) |
| `diagnostic-log` | No (31 October 2026: Swift and Python tests only) | Not tested on a real iPod. It has the 13 hooks of `playback-log` and 8 new hooks. Refer to [../re/diagnostic-log.md](../re/diagnostic-log.md) |
| `usb-host-probe` | Host start; version 1.2: the siTD link and removal (no USB in the emulator) | Yes, as a test: dock hub, storage and the USB-C EarPods enumerate (2026-10-08). The tone test: version 1.3 played the tone in the USB-C EarPods (2026-10-10). The music test: versions 1.5 and 1.6 played the music; the UI was very slow; a reconnection of the dock froze the iPod. Version 1.7 restarted the iPod after the tone; version 1.8 also restarted; version 1.9 played without a restart, the UI lags, a reconnection of the dock freezes the iPod; version 1.10: the Now Playing art is missing; version 1.11: the art still missing; version 1.12: the art is missing also when the probe is installed but not started; version 1.13 installed and not started: the art loads; started ("Start the Probe Without Music"): the art is missing; version 1.14: the art cache list stays empty in host mode; version 1.15: the request queues are empty, the art lookup finds no art; version 1.16: the ArtworkDB handle stays set, no database reload; version 1.17: the ArtworkDB and its lookup are correct in host mode; version 1.18 baseline without the host start: the art is also missing, thus the cause is not the host mode; version 1.19 (no call of 0x19ff0c after a log write), baseline: **the art loads**, thus 0x19ff0c was the cause; version 1.19 in host mode: **the art loads**; a connection to the Mac while host mode runs froze the iPod; version 1.20 with the music route: **the music plays through the USB-C EarPods and the art loads**; version 1.21: **the EarPods volume follows the click wheel**, no gaps; version 1.22: the buttons did not operate the iPod; version 1.23: **all EarPods buttons operate the iPod** (volume ±, play/pause); version 1.24: **no freeze** at a new connection of the dock or the Mac; version 1.25: **the headphones operate again after a reconnection**, two and three pushes operate; the playback stopped at the disconnection; version 1.26: **the song pauses at the disconnection**; "unsupported device" at the reconnection ended the playback; version 1.27: **all as expected** (no message at a reconnection, a pause and Play continue, good volume levels). Version 1.29: operates (28 October 2026) |
| Split layout | Yes (31 October 2026). The owner reported that all items operate as expected. The cover sometimes takes approximately 1 s to show, most often after Previous. |
| Split Dark | No. Emulator only (31 October 2026). |
| Split with Switch on iPod | No. Emulator start only (31 October 2026). |
| Dark Mode switch | Yes | Version 1.1: yes (28 October 2026). The three appearances Light, Dark and Switch on iPod operate. |
| Software version | Not recorded | Yes (28 October 2026) |
| The copy of the games (`games_RO`) | Not applicable (the emulator has no games) | Not recorded. The copy was tested on a copy of the folder `iPod_Control`: the 7 complete games were copied byte for byte, 226,577,300 bytes. The 2 games that are not complete were skipped. Real iPod (27 October 2026, test app "iPodFirm Game Key Test" 0.1.164): the copy of the games with the owner's own key file `IC-Info.sidb` (**Choose Key File…**) works; the owner reports "that works perfectly". |
| The removal of the games (`remove-games`, **Remove Games**) | Not applicable (the emulator has no games) | Not recorded. The removal was tested on copies of the folder `iPod_Control`: the removal deleted the folder of the selected game only. The saves, the scores and the other files stayed. The removal on the real iPod is not done. |

## Known problems

- The start code of the iPod can remove the `hibe` entry from the directory. The old 64 MB hibernation area then stays in the partition ([re/hibernation-restore.md](../re/hibernation-restore.md)). Without the entry, the iPod does not hibernate. iPodFirm does not repair the hibernation: the research did not read the dump header or the start code of the NOR flash yet (open item). The rsrc move writes around the hibernation area, never into it.
- The owner reported slower scroll in lists with `flash-keep-awake`. The emulator shows that the patch code does not run during a scroll. The cause is not known.
- In the dark theme, the rating stars in Now Playing are almost invisible.
- After a computer session, the stock firmware defers Sleep for approximately 1 minute. `sleep-now` works around this. The cause is not known.
- The first screen after a start with the dark theme shows "Press Center to dismiss" in the title bar. The original theme on 1.2.1 has the same problem.
- The flash patches use more battery. The battery life with these patches is not measured.
