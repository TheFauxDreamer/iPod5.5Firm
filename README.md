# iPod5.5Firm

This project allows you to modify the stock Apple firmware of an iPod Video (5th generation and 5.5th generation). Apple Silicon only.

The changed firmware replaces the Apple firmware on the iPod. This is the same process that iPodWizard used.

For the research, the risks and the plan, refer to [FEASIBILITY.md](FEASIBILITY.md).

## Contents of the project

| Part | Location | Function |
|---|---|---|
| iPodFirm app | [mac/](mac/) | A macOS app. It does all the tasks in this project. |
| `ipodfw` tool | [src/ipodfw/](src/ipodfw/) | A command-line tool in Python. It uses the same file formats as the app. |
| Technical reference | [docs/](docs/README.md) | The formats, the patches, the Ghidra findings, the app structure and the safety limits. |
| Research notes | [re/](re/) | Notes for the emulator and for Ghidra, in the sequence of the work. |
| USB-C audio out plan | [USB-AUDIO-OUT.md](USB-AUDIO-OUT.md) | The plan, the research results and the status of USB-C audio out (the iPod as USB host to headphones and USB DACs). |

## The iPodFirm app

### Functions

The app has these functions:

- Open an Apple `.ipsw` file, a firmware file or a backup of the iPod.
- Download the Apple firmware 1.3. The app examines the SHA-256 value of the download.
- Show and replace the pictures in the firmware. Use PNG files that have the same size.
- Show and change the text in the firmware. A gauge shows the bytes that are free in each language.
- Make a backup of the firmware partition of the iPod.
- Eject the iPod, so that you can disconnect it (iPod pane, Patches pane and iPod menu).
- Write the changed firmware to the iPod.
- Export the changed firmware as an `.ipsw` file (File > Export as .ipsw…).
- Restore a backup to the iPod. If the firmware on the iPod is damaged, the app does a rescue restore.
- Show the recovery steps, and get the Apple firmware for a restore with Finder.
- Start the changed firmware in an emulator. The app shows the screen and has a click wheel.
- Install a patch from other people: double-click a `.ipodpatch` file, or drag it onto the list of patches. The app shows the version of each patch. It tells you if a file is an update or an older version. Export a patch as a `.ipodpatch` file with its compiled code, so that other people do not need Xcode. Refer to [docs/patch-system.md](docs/patch-system.md#the-ipodpatch-file).
- Switch code patches on or off (Patches pane). The pane shows a list of the patches at the left. Select a patch to see its description, its compatibility, its size on the iPod and its tools at the right. A bar below the list shows the space that the theme and the patches use. It is red if the firmware is too large. The patches are in [patches/](patches/).
- Write the playlist thumbnail file to the iPod for the `album-art` patch. The albums use the artwork that is on the iPod.
- Set a custom image for each playlist for the `album-art` patch.
- Import an iPodWizard theme for firmware 1.2.1 into firmware 1.3. Select the iPod appearance: Light, Dark, or Switch on iPod (Patches pane). The pane shows the size that each appearance adds to the firmware.
- Show a different version on the About screen of the iPod, for example 1.3.1 (Patches pane). This setting is off by default. iTunes and Finder continue to see version 1.3.
- Set up the Touch ID helper and examine Full Disk Access in the Settings window (iPodFirm > Settings…).

### Build and install the app

1. Open Terminal.
2. Go to the project folder.
3. Enter this command:

   ```sh
   mac/scripts/build-app.sh
   ```

The script increases the version number and the build number. Then it builds the app and installs it in `/Applications/iPodFirm.app`.

To do the tests, enter these commands:

```sh
cd mac
swift test
```

Two environment variables add more tests:

- `IPODFW_IPSW=<path to iPod_25.1.3.ipsw>` adds tests with the Apple firmware.
- `IPODFW_DISK_TEST=1` adds a test that writes firmware to a disk image.

### Permissions

The app must read and write the disk of the iPod directly. Thus, the app needs these permissions:

1. Full Disk Access. Open System Settings > Privacy & Security > Full Disk Access. Then turn on iPodFirm.
2. The Touch ID helper (optional). Open iPodFirm > Settings…, then click "Set Up Touch ID". Then approve iPodFirm in System Settings > General > Login Items.

If you do not set up the Touch ID helper, the app asks for your administrator password.

## Protecting the iPod

The app has the following safety measures in place:

- They make a backup of the firmware partition before each write or restore. They do not overwrite a backup.
- They keep the first backup as "Original (first backup).bin".
- They do not change the `aupd` image. This image updates the boot flash memory. A bad boot flash can make the iPod unrecoverable.
- They do not write the `hibe` image. The iPod writes this image when it goes into deep sleep.
- They examine the checksums and the partition layout before they write.
- They show the bytes that they will write. You must confirm before the write starts.
- They write only the blocks that changed. Then they read each block again to make sure that it is correct.

The app keeps backups in `~/Library/Application Support/iPodFirm/Backups/`.

### Recovery

A firmware write cannot damage disk mode. The boot loader and disk mode are in the NOR flash chip of the iPod, not on the disk. The app and the tool do not write to the NOR flash.

CAUTION: Charge the iPod before a recovery. An iPod with an empty battery does not show disk mode.

If the iPod does not start after a write, do these steps:

1. Push and hold Menu and Select until the iPod restarts.
2. When the Apple logo shows, push and hold Select and Play until the iPod shows disk mode.
3. Connect the iPod to the Mac.
4. In iPodFirm, open the iPod pane and click "Restore…" on a backup.

An interrupted write can damage the firmware on the iPod. Then iPodFirm does a rescue restore. The rescue restore compares the backup with the first backup ("Original"), not with the iPod. It keeps a copy of the damaged firmware as a backup. You cannot restore that copy.

If iPodFirm cannot restore a backup, use Finder:

1. In the Recovery section of the iPod pane, click "Restore with Finder…".
2. In Finder, select the iPod.
3. Push and hold the Option key, then click "Restore iPod".
4. Select the file `iPod_25.1.3.ipsw`.

CAUTION: A restore with Finder erases the music on the iPod.

Finder installs the Apple firmware again and repairs a damaged partition table. After that, you can restore a backup in iPodFirm.

### What is verified for the dark theme

The dark theme makes osos larger and moves `rsrc`. These facts support a safe recovery:

- Disk mode is in the boot loader in the flash memory of the iPod, not on the disk (Rockbox manual). iPodFirm never writes or moves `aupd`, the only image that changes this flash memory.
- RetailOS finds `rsrc` through the directory, by its type and ID (Ghidra, function 0xc60ec). Rockbox `ipodpatcher` also moves `rsrc` when it installs its boot loader.
- In the emulator, the firmware did not write to the RAM of the background picture during a long test.
- On a disk image, a restore of the original backup gives the original partition again, byte for byte.

Tested the dark theme and the move of `rsrc` on a real model iPod 5.5G. For the details, refer to [re/dark-theme.md](re/dark-theme.md).

If the iPod does not show disk mode, charge it for one hour and try again. Diagnostic mode can test the disk: push and hold Menu and Select, then push and hold Select and Previous.

## The ipodfw tool

### Install the tool

1. Install `uv`.
2. In the project folder, enter `uv sync`.
3. To do the tests, enter `uv run pytest`.

To get the Apple firmware 1.3, use this URL:

`http://appldnld.apple.com.edgesuite.net/content.info.apple.com/iPod/SBML/osx/bundles/061-2967.20080313.Cnvkg/iPod_25.1.3.ipsw`

CAUTION: Do not commit firmware files or backups to Git. The `.gitignore` file excludes them.

### Change the firmware with the tool

CAUTION: The commands that read or write the iPod need administrator rights. Use `sudo` for these commands.

1. Make a backup of the firmware partition:

   ```sh
   sudo .venv/bin/ipodfw backup -o backups/firmware-backup.bin
   ```

2. Export the pictures and the text:

   ```sh
   uv run ipodfw unpack backups/firmware-backup.bin -o work
   ```

3. Change the PNG files in `work/pictures/`. Do not change the size of a picture.
4. Change the text in the JSON files in `work/strings/`.
5. Put the changes into a new firmware file:

   ```sh
   uv run ipodfw repack backups/firmware-backup.bin work -o custom.bin
   uv run ipodfw verify custom.bin
   ```

6. Show the blocks that the tool will write. This step does not write to the iPod:

   ```sh
   sudo .venv/bin/ipodfw flash custom.bin --dry-run
   ```

7. Write the firmware to the iPod:

   ```sh
   sudo .venv/bin/ipodfw flash custom.bin
   ```

To restore the backup, enter `sudo .venv/bin/ipodfw restore backups/firmware-backup.bin`.

If the firmware on the iPod is damaged, the normal restore stops. Then use the rescue restore. Use the first backup of the iPod as the reference:

```sh
sudo .venv/bin/ipodfw restore backups/firmware-backup.bin --rescue --reference backups/firmware-backup.bin --dry-run
sudo .venv/bin/ipodfw restore backups/firmware-backup.bin --rescue --reference backups/firmware-backup.bin
```

### Commands

| Command | Function |
|---|---|
| `extract IPSW` | Copies the firmware partition image from an Apple `.ipsw` file. |
| `info FILE [-r]` | Shows the images, the checksums and the model. `-r` also shows the resource blocks. |
| `verify FILE` | Examines the checksums and the resources. |
| `unpack FILE -o DIR` | Exports the pictures (PNG) and the text (JSON). |
| `repack FILE DIR -o OUT` | Puts the changes into a new file and calculates the checksum. |
| `pack-ipsw IPSW FILE -o OUT` | Puts a changed firmware into a copy of an `.ipsw` file. |
| `make-library -o DIR` | Makes a music library for tests in the emulator. |
| `import-theme THEME BASE TARGET -o OUT` | Makes an iPodFirm theme file from an iPodWizard theme. BASE is the Apple firmware of the theme. TARGET is the Apple firmware 1.3. |
| `apply-theme FILE THEME -o OUT [--switch]` | Applies an iPodFirm theme file to a firmware image. It moves `rsrc` if necessary. `--switch` makes the light firmware with a "Dark Mode" item in Settings. |
| `devices`, `backup`, `flash`, `restore` | Operate on the iPod. These commands need `sudo`. |
| `restore --rescue [--reference FILE]` | Restores a backup to an iPod that has damaged firmware. This command needs `sudo`. |

## Dark theme

iPodFirm can import a dark theme from iPodWizard into firmware 1.3. The tested theme is "Dark Gray (04_12_20)" for the 5.5G (by Matthew98 and Milli5410). It is in the [iPod Wizard Themes](https://archive.org/details/b5ad5489368ba5f0fe19935e983faf2b) collection on the Internet Archive.

CAUTION: The theme files contain Apple code. Do not commit them to Git.

### Import the theme

1. Download the theme file from `3. Themes/5.5 gen/1. Tested _ Working/1. Dark Mode (Other Colors Inside)/`.
2. Download the Apple firmware 1.2.1 from `1. iTunes Restore Firmware (recommend first step)/5.5 gen/iPod_25.1.2.1.ipsw`.
3. In iPodFirm, select File > Import iPodWizard Theme.
4. Select the theme file.
5. Select `iPod_25.1.2.1.ipsw`.
6. Read the import report.
7. In the Patches pane, select "iPod Appearance". Then click Dark or Switch on iPod.

iPodFirm applies the theme when you save, flash, export an .ipsw or run the emulator. Your picture and text changes stay as they are.

### How the import operates

- The import compares the theme with Apple firmware 1.2.1. Then it applies the changed pictures, colours and layouts to firmware 1.3.
- The import keeps Apple's progress bar in Now Playing. The theme makes it almost invisible.
- The lists keep Apple's blue highlight bar. The blue bar is easier to see than the grey bar of the theme.
- The import does not apply changes to the program code. The tested theme removes a signature check; iPodFirm does not copy that change.
- The theme has a full-screen background picture. The picture makes osos 38 KB larger. Thus iPodFirm moves the `rsrc` image (fonts and video firmware) to free space in the firmware partition. It does not move or change `aupd` or `hibe`.

### Change the pictures of the dark theme

iPodFirm keeps each imported theme in `~/Library/Application Support/iPodFirm/Themes/` (one `.ipodtheme` file for each theme). The file is a list of byte changes, not pictures. Thus, use the Pictures pane to change it.

1. Open the firmware.
2. In the Pictures pane, click "Dark Theme".
3. Select a picture.
4. Click "Export PNG…" to get the dark picture.
5. Edit the PNG. Keep the same size.
6. Click "Replace…", or drop the PNG on the picture.

The replacement changes only the dark theme. The light picture does not change. To get the picture of the theme again, click "Use Theme Picture".

### Switch on iPod

This allows the user to toggle dark/light mode on the device. The firmware starts light, and Settings on the iPod has a "Dark Mode" item (On/Off).

1. On the iPod, open Settings.
2. Select "Dark Mode".
3. Wait while the iPod restarts to apply the theme.

The iPod saves its settings before it restarts. It keeps the choice in the file `iPod_Control/iTunes/iPodFirmDarkMode` (one byte: `0` light, `1` dark). If the file does not exist, the iPod starts light.

The iPod must restart because RetailOS creates its screens one time, at the start. For the research, refer to [re/dark-theme.md](re/dark-theme.md).

NOTE: In the emulator, the restart operates only with the iPodFirm emulator patch of this version. In the Emulator pane, click "Update Emulator" one time.

## Patches

| Patch | Function | Status |
|---|---|---|
| `album-art` | Shows a 20 × 20 thumbnail at the left of each album and each playlist in the lists. The album thumbnails come from the artwork on the iPod. | Version 1.0: tested in the emulator and on a real iPod. Version 2.0: tested in the emulator with 138 albums. Version 2.1: installed on a real iPod; the Albums list scrolls slowly. Version 2.2 is a measurement build. |
| `flash-keep-awake` | SSD mode for flash storage (iFlash, CompactFlash and SSD adapters). Keeps the storage on for 30 minutes after each access, not for 1 second. Starts the storage at once when the iPod wakes from sleep. Waits 0.5 s before the storage power goes off. On a hard drive, the patch does nothing. |
| `flash-wake-on-input` | For flash storage. Starts the storage at once when you press a button after a long pause. After a start, it does not examine the storage again for 30 minutes. A turn of the wheel does not start the storage. Switch it on if the first song after a long pause starts late. |
| `backlight-60s` | The Backlight Timer menu has a 60 Seconds item in place of 2 Seconds. | Menu tested in the emulator. Not tested on a real iPod. |
| `volume-unlimit` | Removes the volume limit of iPods for the EU. The full position of the volume control gives the full volume, not 84% of it. On other iPods it changes nothing. It is in the Sound group. For the research, refer to [re/volume-limit.md](re/volume-limit.md). | Byte change checked with the iPodWizard search. Not tested on a real iPod. |
| `something-comforting` | An example patch. A Settings item plays approximately 13 seconds of "Something Comforting" by Porter Robinson on the internal speaker of the iPod. It is in the Fun group. | Tested in the emulator (the item and the note calls; the emulator has no audio). Not tested on a real iPod. |
| `usb-host-probe` | A one-shot test of the USB host mode through a USB-C mod, for [USB-AUDIO-OUT.md](USB-AUDIO-OUT.md). Only on the branch `usb-audio-out`. | Host start tested in the emulator. Not tested on a real iPod. |

The `album-art` patch gets the album thumbnails from the artwork that iTunes or Finder put on the iPod (`iPod_Control/Artwork`). The albums do not need a file. The playlists need the file `iPod_Control/iTunes/iPodFirmAlbumArt`. iPodFirm writes this file from the music on the iPod ("Write Thumbnails to iPod"). Write it again after each sync that adds playlists. A restart of the iPod is not necessary. After you disconnect the iPod from the computer, the patch examines the file again when an album list or a playlist list shows.

A playlist gets a thumbnail too. In the Patches pane, select "Album Artwork". The section "Playlist Artwork" shows the playlists of the connected iPod:

- A playlist without a custom image shows a collage of the covers of its first four albums. If the playlist has fewer than four albums, it shows the cover of the first album.
- To set a custom image, click "Choose Image…" or drag an image onto the playlist. iPodFirm uses the centre square of the image.
- To remove the custom image, click "Use Automatic".
- After a change, click "Write Thumbnails to iPod" again.

iPodFirm keeps the custom images on the iPod, in `iPod_Control/iTunes/iPodFirmPlaylistArt/`. Thus they stay with the iPod. A playlist and an album with the same name have different thumbnails.

The patch draws a thumbnail only in the rows of a list. In Now Playing, RetailOS shows its own large artwork from `iPod_Control/Artwork/ArtworkDB`. Finder writes that database when it syncs music with artwork.

The stock firmware switches off the storage power approximately 1 s after the last access. A flash adapter needs some seconds to start again after a power cut. Thus, the first song after idle time starts 3–6 s late. The `flash-keep-awake` patch changes the keep-awake time to 30 minutes. It also asks for the storage when the iPod wakes from sleep, so that the adapter starts while you look for a song. When the iPod goes to sleep, it switches off the storage as usual. The idea of an "SSD mode" comes from [rockpod](https://github.com/nuxcodes/rockpod), a Rockbox version for the iPod Classic. The separate patch `flash-wake-on-input` starts the storage when you press a button and the storage is off. After a start, it does not do this check again for 30 minutes. A turn of the wheel does not do the check. Switch it on only if the first song after a long pause starts late. Before the power cut, the patch waits 0.5 s, so that an iFlash can complete its writes. Use the patch only with flash storage. The Patches pane examines the size of the connected iPod. An original drive has approximately 30, 60 or 80 GB, thus another size shows that the storage is flash. If the size is near an original drive, iPodFirm asks you before you turn the patch on and before you flash. For the research, refer to [re/play-latency.md](re/play-latency.md).

The `backlight-60s` patch changes only data, not code. A script in the firmware (TCmd resource 9088) converts the menu item to seconds. The patch changes the seconds of a hidden item from "10 seconds" to 60 seconds. Then it puts this item in the menu in place of 2 Seconds. If your iPod is set to 2 Seconds before the flash, it keeps 2 seconds, and the menu shows no check mark. Select a new item one time. For the research, refer to [re/backlight-timer.md](re/backlight-timer.md).

The patch tool compiles C code with the Xcode compiler and links it at a fixed address in the free space after the osos image (maximum 3.9 KB in firmware 1.3).

## Limits

- Text cannot use more bytes than the language uses in the Apple firmware. To make one text longer, make other text shorter.
- The emulator does not have audio. Thus, the iPod in the emulator does not play music.

## Status

- The firmware tools have tests with the Apple firmware 1.3.
- A backup of a real iPod was made and examined.
- The write to the iPod has tests on a disk image. The write was not done on a real iPod.
- The rescue restore has tests on a disk image with a damaged firmware partition. It was not done on a real iPod.
- The `album-art` patch has tests in the emulator. It was not done on a real iPod.
- The `flash-keep-awake` and `flash-wake-on-input` patches have tests in the emulator. The SSD mode additions (2026-10-06) were not done on a real iPod.
- The dark theme, with the `album-art` patch, operates on a real iPod 5.5G. This includes the move of `rsrc`.
- The `backlight-60s` patch has tests in the emulator: the menu and the selection. The emulator does not show the backlight time. It was not done on a real iPod.
- The "Dark Mode" item in Settings has tests in the emulator (light, dark and light again, also without the setting file). It was not done on a real iPod.

## Credits

The file formats come from [iPodWizard](https://sourceforge.net/projects/ipodwizard/) and from the Rockbox tool [`ipodpatcher`](https://github.com/Rockbox/rockbox/tree/master/utils/ipodpatcher). Both use the GPLv2 license. Thus, this project uses the GPL-2.0-or-later license.

The dark theme comes from the iPodWizard community: "5.5G Ultimate Background Hack" by Matthew98, dark mode by Milli5410.
