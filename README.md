# iPodFirm

iPodFirm is a Mac app that adds new features to the iPod Video (5th generation and 5.5th generation). Examples are Dark Mode, small album artwork in the lists, Cover Flow, an Album Artists menu, Playlist Folders, Up Next, Search on the iPod 5G, and PoC USB-C headphone support. The app can also change the pictures and the text of the firmware, and copy your purchased iPod games to the iPod.

iPodFirm changes the Apple operating system of the iPod ("RetailOS", firmware 1.3). It does not replace it, like Rockbox does. The iPod keeps its menus, its music library and its sync with Finder or iTunes.

Each feature is a **patch**. You can switch each patch on or off in the app. When you switch off all the patches, the iPod has the original Apple firmware again.

**Download:** [GitHub Releases](https://github.com/TheFauxDreamer/iPod5.5Firm/releases)

## Before you start

WARNING: A change to the firmware can damage your iPod. The app makes a backup and has a recovery procedure, but this is not a guarantee. Use the app at your own risk. I am not responsible if your iPod stops.

At the first launch, the app shows these terms. You must accept them before you can use the app. To read them again, select Help > Show Disclaimer.

- This is a personal project. The author does not give technical support to each person.
- You can open an issue or a pull request on GitHub. The author can add large corrections or well-tested changes.
- For other iPod models or other firmware versions, make a fork of the project. Refer to [Other iPod models](#other-ipod-models).

## What you need

- A Mac with Apple silicon (M1 or later) and macOS 14 or later. The app does not operate on an Intel Mac or on Windows.
- An iPod Video (5th generation or 5.5th generation) with the Apple firmware 1.3.
- An iPod that is formatted for Mac. The author did not test an iPod that is formatted for Windows.
- A charged battery. An iPod with an empty battery cannot show disk mode for a recovery.

The author tested iPodFirm on an iPod 5.5th generation (64 MB of RAM) with 1 TB of flash storage. The 5th generation uses the same firmware, thus the patches should also operate on it. This is not tested.

## Install the app

1. Download the ZIP file from [GitHub Releases](https://github.com/TheFauxDreamer/iPod5.5Firm/releases).
2. Unzip the file.
3. Move `iPodFirm.app` to `/Applications`.
4. Hold Control and click `iPodFirm.app`.
5. Click **Open**. Then click **Open** again.

If macOS does not show **Open**, open System Settings > Privacy & Security. Then click **Open Anyway**.

The app must read and write the disk of the iPod directly. Thus it needs Full Disk Access:

1. Open System Settings > Privacy & Security > Full Disk Access.
2. Turn on iPodFirm.

Turn on Full Disk Access again after each update of the app. The app asks for your administrator password before it writes to the iPod.

## Change your iPod

1. Connect the iPod to the Mac.
2. In iPodFirm, open the **iPod** pane. The app finds the iPod.
3. Click **Back Up Now**. The app keeps the first backup as "Original (first backup)".
4. Open the Apple firmware. Select File > Download Apple Firmware 1.3, or click **Edit a Copy** on a backup.
5. Open the **Patches** pane.
6. Switch on the patches that you want.
7. Open the **iPod** pane.
8. Click **Flash Edited Firmware…**.
9. Read the list of changes. Then confirm.
10. Click **Eject**. Then disconnect the iPod.

To remove the changes, switch off all the patches. Then flash the firmware again.

You can also try the changed firmware in the **Emulator** pane before you flash it. The emulator has no sound and no USB.

## The patches

The **Patches** pane shows the patches. Select a patch to see what it does, what it needs and its size on the iPod.

When an iPod is connected, the app reads the patches on the iPod. A line at the top of the list tells you if the switches agree with the iPod. Each row also has a mark:

- **On iPod**: the iPod has the patch.
- **Not flashed**: the switch is on, but the iPod does not have the patch.
- **Will be removed**: the switch is off, but the iPod has the patch.
- **iPod has 1.1**: the iPod has an older version.
- **Not known**: the app cannot see the patch. The firmware on the iPod is older than this feature.

If you did not change a switch after the last flash, the switches go to the patches on the iPod. If you changed a switch, the switches stay. Click **Match iPod** to set the switches to the iPod. Click **Flash…** to put the switches on the iPod. With the Touch ID helper, the app reads the iPod automatically. Without it, click **Read iPod**. A read writes nothing to the iPod.

Each build adds a small iPodFirm list of the patches to the firmware (approximately 110 bytes, plus 45 bytes for each patch). The iPod does not use the list. The list is only for the app. A build with no extended patch and no theme does not get the list.

Each patch has a letter. If you switch on "Add a letter for each switched-on patch" in **Software Version**, the About screen of the iPod shows the letters, for example "1.3abkw". Give this version when you report a problem.

### Appearance and version

| Item | Function | Tested on a real iPod |
|---|---|---|
| iPod Appearance | Light, Dark, or Switch on iPod. "Switch on iPod" adds a "Dark Mode" item to Settings on the iPod. You can also import a custom theme from iPodWizard. | Yes |
| Software Version | Shows a different version on the About screen, for example 1.3.1. Finder and iTunes continue to see version 1.3. | Yes |

### Built-in patches

The table shows the status that the test notes record. For the full test record, refer to [docs/safety.md](docs/safety.md#test-status).

| Patch | Letter | Function | Tested on a real iPod |
|---|---|---|---|
| Album Artwork | a | Shows a small album cover at the left of each album and each playlist in the lists. | Yes (version 3.2) |
| Album Artists | l | Adds an Album Artists item to the Music menu. All the songs of a compilation are under one entry. You can also put the item in the main menu. | Yes (version 1.3) |
| Cover Flow | c | Hold Select in the Albums list to see the album covers in 3D. This is a new version for the iPod Video, not the Apple version from the iPod Classic. It replaces "hold Select to add an album to On-The-Go". With Up Next, Settings > Hold Select decides if the hold opens Cover Flow. | Yes (version 0.6.8) |
| 60-Second Backlight | b | The Backlight Timer menu has 60 Seconds in place of 2 Seconds. | Yes |
| SSD Mode | k | For flash storage. Keeps the storage on for 30 minutes after each access, not for 1 second. Songs start faster. | Yes |
| Wake Storage on Input | w | For flash storage. Starts the storage when you push a button, so that the first song starts sooner after a long pause. | Yes |
| Sleep Now | s | The Sleep item puts the iPod to sleep immediately. Use it with SSD Mode. | Yes |
| Instant Save | i | Saves each change in Settings > Main Menu immediately. Without it, the iPod saves the change only when it sleeps. | Yes |
| No EU Volume Limit | v | Removes the volume limit of iPods for the EU. | No. The test needs an iPod for the EU. |
| Search on the 5G | e | Shows the Search menu on the iPod 5G. Firmware 1.3 shows it only on the 5.5G. On a 5.5G, the patch changes nothing. | No. RetroCux tested the same byte on a 5G. |
| Click Only on the Speaker | p | The click of the click wheel plays only from the speaker in the iPod, not in the headphones. | Yes |
| Shuffle Fixes | f | Corrects four errors in the shuffle. The most important: with more than 32767 songs, the shuffle writes outside the list and the order is wrong. | Yes |
| Up Next | n | Hold Select on a song, an album or an artist while music plays: the songs play next (Play Next) or after the last song (Play Last). Settings > Hold Select selects the action: Play Next, Play Last, On-The-Go or Cover Flow (in the Albums list, with the Cover Flow patch). | Yes (version 0.5) |
| Playlist Folders | o | Puts playlists into folders in the Playlists list. You make the folders and their names in the app. Refer to [Playlist Folders](#playlist-folders). | Yes. The folders operate. |
| Album Mix Shuffle | x | Adds Album Mix to Settings > Shuffle: the albums and the songs in each album play in a random order. Settings > Main Menu > Shuffle adds a main menu item that changes the Shuffle value. It needs Shuffle Fixes, and the app turns on Shuffle Fixes with it. | Yes (version 1.2) |
| Something Comforting | m | An example patch. A Settings item plays a short song on the internal speaker of the iPod. | Yes |
| USB-C Audio | u | Plays the music through USB-C headphones. Refer to [USB-C Audio](#usb-c-audio). | Yes (version 1.9) |
| USB Host Probe | h | A test patch for research only. Refer to [USB Host Probe](#usb-host-probe). | Yes (up to version 1.29) |

### The space for patches

RetailOS has a limit of 8 MB for its operating system. The patches and the dark theme must fit in this limit. The space for them is approximately 774 KB. The bar below the list of patches shows the space that you use. The bar is red if the firmware is too large.

CAUTION: Do not try to put more data in the firmware than the space allows. If the firmware is too large, the iPod does not start, and you must restore it.

### Album Artwork

The albums use the artwork that Finder or iTunes put on the iPod. After a sync, the iPod makes the album pictures one time and keeps them in a file. You do not have to do a step for the albums. A playlist shows a collage of the covers of its first four albums. The iPod makes the collage itself.

A custom playlist image needs a thumbnail file:

1. In the **Patches** pane, select "Album Artwork".
2. To use your own image, click **Choose Image…** or drag an image onto the playlist.
3. Click **Write Thumbnails to iPod**.

Write the file again after each change. The pictures of the file come before the pictures that the iPod makes.

### Playlist Folders

The Playlists list shows the folders and the playlists that are not in a folder. Select a folder to see its playlists. Push Menu to go back.

1. Connect the iPod so that it shows in Finder.
2. In the **Patches** pane, select "Playlist Folders".
3. Click **Add Folder**. Type a name.
4. Open the folder row. Turn on each playlist that goes into the folder.
5. Select the position of the folders: **Folders First** or **Alphabetical**.
6. Click **Write Folders to iPod**.
7. Eject the iPod.

A folder cannot have the name of a playlist. A folder has no colour square at this time.

### Import an iPodWizard theme

CAUTION: Use only a theme for firmware 1.2.1 and import it with iPodFirm. An old theme that you apply directly can damage the firmware.

The app comes with the theme "Dark Gray". The app copies it to `~/Library/Application Support/iPodFirm/Themes/` at the first start. You can also import your own theme:

1. Get the theme file and the Apple firmware 1.2.1 (`iPod_25.1.2.1.ipsw`). The [iPod Wizard Themes](https://archive.org/details/b5ad5489368ba5f0fe19935e983faf2b) collection on the Internet Archive has both.
2. In iPodFirm, select File > Import iPodWizard Theme….
3. Select the theme file.
4. Select `iPod_25.1.2.1.ipsw`.
5. Read the import report.
6. In the **Patches** pane, select "iPod Appearance".
7. Click Dark or Switch on iPod.

The tested theme is "Dark Gray (04_12_20)" for the 5.5G. To change the pictures of a theme, use the **Pictures** pane and click "Dark Theme". A theme file in the folder of the owner holds the old bytes of each change (format 1). The built-in themes hold the hash of the old bytes (format 2) and no byte of the Apple firmware.

### Change the pictures and the text

The **Pictures** pane shows the pictures in the firmware, for example the menu icons and the battery pictures. These are not the photos that you put on the iPod.

1. Select a picture.
2. Click **Replace…** and select a PNG file. The PNG file must have the same size as the picture.
3. To save a picture as a PNG file, click **Export PNG…**.

To change many pictures, click **Export All…**. Change the PNG files in the folder. Then click **Import Folder…**.

The **Text** pane shows the text of each language of the iPod.

1. Select the language.
2. Type the new text in a row. The changed rows show in colour.
3. Click **Apply**. To discard the changes, click **Revert**.

The text cannot use more bytes than the language uses in the Apple firmware. To make one text longer, make other text shorter.

After a change, flash the firmware from the **iPod** pane. For the command-line tool, refer to [The ipodfw tool](#the-ipodfw-tool).

### USB-C Audio

The USB-C Audio patch plays the music of the iPod through USB-C headphones. The inline volume buttons and the play/pause button operate the iPod. Two pushes go to the next song. Three pushes go to the previous song. The click wheel also sets the volume.

WARNING: This patch needs an iPod with a USB-C mod and a USB-C dock with power. The iPod cannot supply 5 V to the headphones.

- The patch is off after each restart. Switch it on in Settings > USB-C Audio on the iPod.
- When the patch is on, the USB-C port cannot sync with a computer. Switch it off to sync.
- When the patch is on, the 3.5 mm headphone jack does not play.
- If you disconnect the dock or the headphones, the music pauses.
- You can put a USB-C Audio switch in the main menu.
- Select the sample rate in the **Patches** pane: 44.1 kHz or 48 kHz. Use the rate of most of your music. A song with a different rate needs a conversion, and the iPod becomes slow.

The author tested the patch with Apple USB-C EarPods and an Anker PowerExpand+ dock (A8346).

A hardware mod can give 5 V to the headphones without a dock. The author did not make this mod. For the design, refer to [docs/usb-c-power-mod.md](docs/usb-c-power-mod.md). Do your own research before you make a hardware change.

The 3.5 mm jack cannot use the buttons of headphones. On the iPod Video, the fourth contact of the jack is for video out.

### USB Host Probe

WARNING: This is a test patch for research only. The iPod can stop in a condition that you cannot repair.

The USB Host Probe puts the iPod in USB host mode. Then a computer cannot connect to the iPod until the iPod restarts. The probe also plays test beeps and a 1 kHz tone at full volume.

- Before you install it, make sure that the click wheel and the Select button operate.
- Make sure that you can put the iPod in disk mode.
- Remove your headphones before the test tone plays.

The app shows the probe only if you switch on iPodFirm > Settings… > Patches > Enable Test Patches. Do not install it together with USB-C Audio.

### Make or install a patch

- To install a patch from another person, double-click the `.ipodpatch` file. You can also drag it onto the list of patches. You can also click **Install Patch…**.
- To make a patch, select File > New Patch…. A patch is C code that you type in the app. You need Xcode to compile it.
- To change a patch that you made or installed, select it and click **Edit Patch…**. You cannot edit a built-in patch.
- To give a patch to another person, select it and click **Export Patch…**. The `.ipodpatch` file has the compiled code, thus the other person does not need Xcode.
- To remove a patch that you made or installed, click **Remove Patch…**. The app moves the patch to the Trash.

For the details, refer to [docs/patch-system.md](docs/patch-system.md).

## Recovery

A firmware write cannot damage disk mode. Disk mode is in the flash chip of the iPod, not on the disk. iPodFirm does not write to the flash chip.

CAUTION: Charge the iPod before a recovery. An iPod with an empty battery does not show disk mode.

If the iPod does not start after a write, do these steps:

1. Push and hold Menu and Select until the iPod restarts.
2. When the Apple logo shows, push and hold Select and Play until the iPod shows disk mode.
3. Connect the iPod to the Mac.
4. In iPodFirm, open the **iPod** pane.
5. Click **Restore…** on a backup.

If iPodFirm cannot restore a backup, use Finder.

CAUTION: A restore with Finder erases the music on the iPod.

1. In the Recovery section of the **iPod** pane, click "Restore with Finder…".
2. In Finder, select the iPod.
3. Push and hold the Option key.
4. Click "Restore iPod".
5. Select the file `iPod_25.1.3.ipsw`.

After that, you can restore a backup in iPodFirm.

### How the app protects the iPod

- The app makes a backup of the firmware partition before each write or restore. It does not overwrite a backup.
- It keeps the first backup as "Original (first backup).bin".
- It does not change the `aupd` image. This image updates the boot flash memory.
- It examines the checksums and the partition layout before it writes.
- It shows the bytes that it will write. You must confirm before the write starts.
- It writes only the blocks that changed. Then it reads each block again to make sure that it is correct.

The app keeps the backups in `~/Library/Application Support/iPodFirm/Backups/`. For more details, refer to [docs/safety.md](docs/safety.md).

## The iPod games

The research of the games is in [re/games.md](re/games.md). This project does not research the protection of the games.

The app does not come with the game files and does not download them. The games are not in the app and are not in the firmware of the iPod. The game files come from the iPod that bought them: iTunes or the Finder on a Mac puts purchased games on the iPod. To copy the games, keep the game folders in a folder on your Mac, or use a backup of the folder `iPod_Control` of an iPod that has the games.

To put the games on an iPod, open the **Games** pane. Go to the section **Install Games**. Click **Select Games Folder...** and choose the folder with the games, or the folder `iPod_Control` of an iPod. The app accepts the name `games_RO` and the name `Games_RO` for the folder of the games. Thus the app works with a Windows iPod and with a macOS iPod. The pane shows each game with a switch. Click **Select All** or **Select None**, or click the switches of the games that you want. Then click **Install Games**. The app copies the selected games to the folder `games_RO` of the connected iPod. The app checks the size of each file of the manifest before the copy. The app skips a game that is not complete. The app never removes a file of the iPod during the copy.

To remove games from an iPod, open the section **Remove Games** in the same pane. Click **Read the Games on the iPod**. The pane lists the GUID of each game in the folder `games_RO`. Select the games and click **Remove Selected Games…**. A sheet asks you to confirm. The removal deletes only the folder of each selected game in `games_RO`. The folders `gamedata_RW` and `gamestats_WO` hold the saves and the scores of the games. The removal does not touch them.

A game runs only on the iPod that bought it, and only if that iPod has the key file `iPod_Control/iTunes/IC-Info.sidb` of the account that bought the game. A restore of the iPod removes this file. The app cannot make the file, and the repository does not supply it. To copy your own key file with the games:

1. Get your file `IC-Info.sidb`, for example from a backup of the folder `iPod_Control/iTunes` of this iPod.
2. In the section **Install Games**, click **Choose Key File…** and select the file.
3. Click **Install Games**.

The app accepts only a file with the name `IC-Info.sidb` that is not empty and not larger than 4 MB. The app copies the file as it is. It does not read, change or make the file. To copy no key file, click **Clear**. The command `install-games --key-file` does the same check and copy.

## The firmware

The note [re/retailos-decompile.md](re/retailos-decompile.md) gives the decompilation of the whole image `osos` of RetailOS 1.3. The research gives 14,411 functions. The research also gives the map of the strings. The map names 380 functions and puts each function into a group. The C code, the index of the functions and the map of the strings are in `~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/`. The script [re/decompile-all.sh](re/decompile-all.sh) does the work again. The script [re/decompile-with-strings.sh](re/decompile-with-strings.sh) does the work with the map of the strings.

The note [re/firmware-coverage.md](re/firmware-coverage.md) gives the index of all the research of the firmware. The note lists every part of the firmware and gives the state of the research for each part. The note also gives the limits of the names. The firmware is not fully reverse engineered. The research covers 7.3% of the functions of the code and 13.3% of the lines.

The note [re/firmware-systems.md](re/firmware-systems.md) gives the systems and the sub-systems of the firmware. The note has the table of the 21 tasks of the firmware, the 49 names of the classes and the 222 tables of the classes.

The note [re/firmware-task-system.md](re/firmware-task-system.md) gives the kernel of the firmware. The kernel is ThreadX, the real-time kernel of Azure RTOS of Microsoft. The note gives the base class of the tasks, the object of a task, the 9 classes of the priority and the scheduler.

The note [re/firmware-camera.md](re/firmware-camera.md) gives the camera of the iPod Video. The iPod Video has no camera. The firmware has the code of the camera of the iPod Photo. The note gives the class drivers of the USB host stack, the task of the camera and the path of the import of the pictures.

The note [re/firmware-usb.md](re/firmware-usb.md) gives the USB of the iPod Video. The note gives the 11 tasks, the mode manager, the stack of the device, the identity of the iPod and the protocol of the accessory.

The note [re/firmware-ui.md](re/firmware-ui.md) gives the user interface of the iPod Video. The screens are not in the code. The screens are in the resources of the image. The note gives the resources, the 19 classes of the screens, the elements of a screen and the registry of the modules.

The note [re/firmware-power.md](re/firmware-power.md) gives the power of the iPod Video. The note gives the 8 tasks, the registers of the power chip, the clock and the manager of the power.

The note [re/firmware-media.md](re/firmware-media.md) gives the music and the video of the iPod Video. The note gives the 7 tasks, the caches, the video processor of Broadcom and the MP4 parser.

The note [re/firmware-storage.md](re/firmware-storage.md) gives the storage of the iPod Video. The note gives the 7 tasks, the bus of the disk, the 4 file systems and the partitions.

The note [re/firmware-filesystems.md](re/firmware-filesystems.md) gives the code of the file systems. The note gives the code of the FAT, the code of the HFS+, the table of the partitions and the 2 signatures of the volume.

The note [re/firmware-modules.md](re/firmware-modules.md) gives the table of the modules of the screen. The note gives the 7 modules, the 418 methods and the layout of each record of the table.

The note [re/firmware-library.md](re/firmware-library.md) gives the library of C of the compiler of Apple. The note gives the functions of the strings, the memory, the arithmetic, the floating point and the heap.

## Other iPod models

The author has only an iPod 5.5G. Thus the author does not add support for other models or for other firmware versions.

To add a model, make a fork of the project. Each model and each firmware version needs new research in Ghidra: the functions, the addresses and the hooks. Use this repository as a reference, and use a real iPod for the tests. For the steps, refer to [docs/porting.md](docs/porting.md).

For the iPod Classic (6th generation and 7th generation), refer to RepriseOS by osos-lab.

## AI disclosure

This project started as a personal project. I used Claude Code for much of the reverse engineering in Ghidra and for solutions when I got stuck on difficult problems. Claude Code also keeps the documents and the code comments up to date with each change and each finding.

## For developers

### Contents of the project

| Part | Location | Language | Function |
|---|---|---|---|
| iPodFirm app | [mac/](mac/) | Swift | The macOS app. It builds and applies the patches and writes the iPod. |
| Patches | [patches/](patches/) | C | The code and the `patch.json` file of each patch. |
| `ipodfw` tool | [src/ipodfw/](src/ipodfw/) | Python | A command-line tool. It uses the same file formats as the app. |
| Ghidra scripts | [re/ghidra-scripts/](re/ghidra-scripts/) | Java | Scripts for the research in Ghidra. |
| Technical reference | [docs/](docs/README.md) | — | The formats, the patches, the Ghidra findings, the app structure and the safety limits. |
| Translations | [docs/translations.md](docs/translations.md) | — | The iPod text that the patches add. Help with a translation into your language. |
| Research notes | [re/](re/) | — | Notes for the emulator and for Ghidra, in the sequence of the work. Also the failed and stopped research. |
| USB-C audio plan | [USB-AUDIO-OUT.md](USB-AUDIO-OUT.md) | — | The plan, the research results and the status of USB-C audio out. |
| Feasibility study | [FEASIBILITY.md](FEASIBILITY.md) | — | The first research, the risks and the plan. |

For each patch, [docs/modifications.md](docs/modifications.md) gives the user interface, the Ghidra results and the limits.

### Build and install the app

1. Open Terminal.
2. Go to the project folder.
3. Enter this command:

   ```sh
   mac/scripts/build-app.sh
   ```

The script increases the version number and the build number. Then it builds the app and installs it in `/Applications/iPodFirm.app`.

A build from your source code can use the Touch ID helper. To set it up, open iPodFirm > Settings…, then click "Set Up Touch ID". Then approve iPodFirm in System Settings > General > Login Items.

The Settings window examines the helper each time it opens. If the helper does not reply, the window shows an orange warning. Click "Repair" to register the helper again.

### Make a release build

1. Enter this command:

   ```sh
   RELEASE=1 mac/scripts/build-app.sh
   ```

2. Upload the file `mac/build/iPodFirm-<version>.zip` to the GitHub release.

The release build has an ad-hoc signature. The script does not install the release build. A release build cannot use the Touch ID helper.

To make the release ZIP and install the app with the same version, use `RELEASE=both` in place of `RELEASE=1`. The installed app keeps the signature of a normal build. Thus Touch ID and Full Disk Access continue to operate.

On the `main` branch, `RELEASE=both` is the default. On other branches, the default is a normal build. To change the default, set `RELEASE=0` or `RELEASE=1`.

### Tests

To do the tests of the app, enter these commands:

```sh
cd mac
swift test
```

Two environment variables add more tests:

- `IPODFW_IPSW=<path to iPod_25.1.3.ipsw>` adds tests with the Apple firmware.
- `IPODFW_DISK_TEST=1` adds a test that writes firmware to a disk image.

### The ipodfw tool

1. Install `uv`.
2. In the project folder, enter `uv sync`.
3. To do the tests, enter `uv run pytest`.

To get the Apple firmware 1.3, use this URL:

`http://appldnld.apple.com.edgesuite.net/content.info.apple.com/iPod/SBML/osx/bundles/061-2967.20080313.Cnvkg/iPod_25.1.3.ipsw`

CAUTION: Do not commit firmware files or backups to Git. The `.gitignore` file excludes them.

CAUTION: The commands that read or write the iPod need administrator rights. Use `sudo` for these commands.

To change the pictures and the text with the tool, do these steps:

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

| Command | Function |
|---|---|
| `extract IPSW` | Copies the firmware partition image from an Apple `.ipsw` file. |
| `info FILE [-r]` | Shows the images, the checksums and the model. `-r` also shows the resource blocks. |
| `verify FILE` | Examines the checksums and the resources. |
| `unpack FILE -o DIR` | Exports the pictures (PNG) and the text (JSON). |
| `repack FILE DIR -o OUT` | Puts the changes into a new file and calculates the checksum. |
| `pack-ipsw IPSW FILE -o OUT` | Puts a changed firmware into a copy of an `.ipsw` file. |
| `make-library -o DIR` | Makes a music library for tests in the emulator. |
| `install-games SOURCE TARGET [--game GUID] [--key-file FILE]` | Copies the games from the folder `SOURCE` to the folder `iPod_Control` of the iPod in the folder `TARGET`. It copies all the games. The option `--game` copies only this game; use the option more than once for more games. The option `--key-file` copies the file `IC-Info.sidb` to the target iPod. |
| `remove-games TARGET [--game GUID]` | Removes games from the folder `iPod_Control` of the iPod in the folder `TARGET`. Without the option, it removes all the games. The option `--game` removes only this game; use the option more than once for more games. It removes only the folder of the game in `games_RO`. |
| `import-theme THEME BASE TARGET -o OUT` | Makes an iPodFirm theme file from an iPodWizard theme. BASE is the Apple firmware of the theme. TARGET is the Apple firmware 1.3. |
| `strip-theme THEME -o OUT` | Writes a theme file in format 2: the hash of the old bytes in place of the old bytes. The file holds no byte of the Apple firmware. |
| `apply-theme FILE THEME -o OUT [--switch]` | Applies an iPodFirm theme file to a firmware image. It moves `rsrc` if necessary. `--switch` makes the light firmware with a "Dark Mode" item in Settings. |
| `devices`, `backup`, `flash`, `restore` | Operate on the iPod. These commands need `sudo`. |
| `restore --rescue [--reference FILE]` | Restores a backup to an iPod that has damaged firmware. This command needs `sudo`. |

### Limits

- Text cannot use more bytes than the language uses in the Apple firmware. To make one text longer, make other text shorter.
- The emulator does not have audio or USB. Thus the iPod in the emulator does not play music.

## Credits

The file formats come from [iPodWizard](https://sourceforge.net/projects/ipodwizard/) and from the Rockbox tool [`ipodpatcher`](https://github.com/Rockbox/rockbox/tree/master/utils/ipodpatcher). Both use the GPLv2 license. Thus this project uses the GPL-2.0-or-later license. The license text is in [LICENSE](LICENSE).

The file [0001-ipodfirm-instrumentation.patch](mac/Resources/emulator-patches/0001-ipodfirm-instrumentation.patch) changes [siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator). It contains lines of that project. Thus this file uses the GPL-3.0 license of the emulator.

The dark theme comes from the iPodWizard community: "5.5G Ultimate Background Hack" by Matthew98, dark mode by Milli5410.

The idea of SSD Mode comes from [rockpod](https://github.com/nuxcodes/rockpod). The idea of the Album Artists menu comes from osos-lab (RepriseOS).

The idea of Search on the 5G and the byte to change come from [RetroCux](https://github.com/RetroCux/Enable-the-Search-function-on-iPod-Video-5th-Gen).

The idea of Playlist Folders comes from the Reddit user [u/Linusssk](https://www.reddit.com/user/Linusssk/).

The user braniak87 found the cause of a crash when the Patches pane opened (GitHub issue 1). braniak87 also gave the fix and tested it.

In the app, select Help > Thanks… to see these people. The newest fixes are at the top. To add a person, add an entry with the release `version` to `Thanks.people` in [Thanks.swift](mac/Sources/IPodFWKit/Thanks.swift) and to this section.

The `something-comforting` patch plays a short part of "Something Comforting" by Porter Robinson. The patch is an example only.

## Legal

- This project is not affiliated with Apple Inc. Apple and iPod are trademarks of Apple Inc.
- The repository does not contain Apple firmware. The app downloads the firmware from Apple, or uses a backup of your iPod.
- Do not commit Apple firmware, `.ipsw` files, theme files or iPod backups.
- The software comes with no warranty. A change to the firmware can make the iPod unusable until you restore it with Finder or reformat the device. Use the software at your own risk.
