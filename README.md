# iPod5.5Firm

This project changes the stock Apple firmware of an iPod Video (5th generation and 5.5th generation). It operates on a Mac with Apple silicon.

The changed firmware replaces the Apple firmware on the iPod. This is the same procedure that iPodWizard used. You can restore the Apple firmware at any time.

For the research, the risks and the plan, refer to [FEASIBILITY.md](FEASIBILITY.md).

## Contents of the project

| Part | Location | Function |
|---|---|---|
| iPodFirm app | [mac/](mac/) | A macOS app. It does all the tasks in this project. |
| `ipodfw` tool | [src/ipodfw/](src/ipodfw/) | A command-line tool in Python. It uses the same file formats as the app. |
| Research notes | [re/](re/) | Notes for the emulator and for Ghidra. |

## The iPodFirm app

### Functions

The app has these functions:

- Open an Apple `.ipsw` file, a firmware file or a backup of the iPod.
- Download the Apple firmware 1.3. The app examines the SHA-256 value of the download.
- Show and replace the pictures in the firmware. Use PNG files that have the same size.
- Show and change the text in the firmware. A gauge shows the bytes that are free in each language.
- Make a backup of the firmware partition of the iPod.
- Write the changed firmware to the iPod.
- Restore a backup to the iPod. If the firmware on the iPod is damaged, the app does a rescue restore.
- Show the recovery steps, and get the Apple firmware for a restore with Finder.
- Start the changed firmware in an emulator. The app shows the screen and has a click wheel.
- Put a music library on the emulated iPod: a test library, or songs from a folder.
- Switch code patches on or off (Patches pane). The patches are in [patches/](patches/).
- Write the album thumbnail file to the iPod for the `album-art` patch.

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
2. The Touch ID helper (optional). In the iPod pane, click "Set Up Touch ID". Then approve iPodFirm in System Settings > General > Login Items.

If you do not set up the Touch ID helper, the app asks for your administrator password.

## Protection of the iPod

The app and the tool protect the iPod in these ways:

- They make a backup of the firmware partition before each write or restore. They do not overwrite a backup.
- They keep the first backup as "Original (first backup).bin".
- They do not change the `aupd` image. This image updates the boot flash memory. A bad boot flash can make the iPod unserviceable.
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
| `devices`, `backup`, `flash`, `restore` | Operate on the iPod. These commands need `sudo`. |
| `restore --rescue [--reference FILE]` | Restores a backup to an iPod that has damaged firmware. This command needs `sudo`. |

## Patches

| Patch | Function | Status |
|---|---|---|
| `album-art` | Shows a 20 × 20 thumbnail of the album artwork at the left of each album in the lists. | Tested in the emulator with 200 real songs in 28 albums. Not tested on a real iPod. |

The `album-art` patch reads the file `iPod_Control/iTunes/iPodFirmAlbumArt`. iPodFirm writes this file from the music on the iPod ("Write Thumbnails to iPod"). Write it again after each sync that adds albums.

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

## Credits

The file formats come from [iPodWizard](https://sourceforge.net/projects/ipodwizard/) and from the Rockbox tool [`ipodpatcher`](https://github.com/Rockbox/rockbox/tree/master/utils/ipodpatcher). Both use the GPLv2 license. Thus, this project uses the GPL-2.0-or-later license.
