# The app and the device

This document describes the structure of the iPodFirm app. It tells how the app finds the iPod and how it gets the rights to write the disk. It lists each external program, system API, network connection and file that the app uses.

## The parts

The Swift package is in [mac/](../mac/). [Package.swift](../mac/Package.swift) has four targets:

| Target | Type | Function |
|---|---|---|
| `IPodFWKit` | Library | The firmware formats, the patcher, the theme import, the disk access and the safety checks. It has no user interface. |
| `iPodFirm` | App | The SwiftUI user interface. |
| `ipodfw-helper` | Command-line program | The privileged helper. It reads and writes the raw disk. |
| `IPodFWKitTests` | Tests | `swift test`. |

The Python package in [src/ipodfw/](../src/ipodfw/) has the same formats. The two implementations must give the same bytes. When you change a format in one package, change the other package too.

The app needs macOS 14 or later and an Apple silicon Mac (`--arch arm64`).

## The panes

| Pane | Functions | Main code |
|---|---|---|
| Firmware | The images, the checksums and the model of the open file. | [OverviewView.swift](../mac/Sources/iPodFirm/OverviewView.swift) |
| Pictures | Show, export and replace pictures. Show the dark theme pictures. | [PicturesView.swift](../mac/Sources/iPodFirm/PicturesView.swift) |
| Text | Change the strings of each language. | [StringsView.swift](../mac/Sources/iPodFirm/StringsView.swift) |
| Patches | A list at the left: iPod Appearance, Software Version and the patches (grouped by `category`: Display, Power and Storage, Fun, Tests). Below the list: **+** (install a patch), **−** (remove a user patch) and **⋯** (New Patch…, Install Patch…, Edit Patch…, Export Patch…, Remove Patch…, Show Patches Folder). New Patch… and Edit Patch… open `PatchEditorSheet` ([PatchEditor.swift](../mac/Sources/iPodFirm/PatchEditor.swift)). The sheet writes the text of `patch.json`. Refer to [patch-system.md](patch-system.md#make-and-share-a-patch). The context menu of a user patch also has Edit Patch…. The detail of a user patch has a Code section with the C code, the firmware functions, the hooks, the byte changes, Check Code and Save ([PatchCodeView.swift](../mac/Sources/iPodFirm/PatchCodeView.swift); refer to [patch-system.md](patch-system.md#the-code-section)). The list accepts a dropped `.ipodpatch` file or patch folder. Below the buttons, a bar shows the space after Apple's image (0x736800 to 0x7F8000) that the theme, the Dark Mode items and the extended patches use. The app measures it again 0.3 s after each change of a patch switch or of the appearance (`AppModel.refreshSpaceUse`: a build of the appearance, plus the code size of each switched-on patch, `Patcher.codeSize` and `Patcher.spaceUse`). If the firmware is too large, the bar is red and the text gives the excess. Each patch row has an SF Symbol, the title, the summary, the letter, the version, the size on the iPod and a switch. The detail at the right shows the selected row: the caution, the sections "What It Does", "You Need" and "Good to Know", the compatibility, the conflicts, the version, the size on the iPod (`size` in `patch.json`; the install, the export and the app start record the measured size), the source and the controls from the `ui` object of `patch.json`. | [PatchesView.swift](../mac/Sources/iPodFirm/PatchesView.swift) |
| iPod | Find the iPod, back up, flash, restore, eject and the recovery steps. A row shows the permission status and opens the Settings window. | [IPodView.swift](../mac/Sources/iPodFirm/IPodView.swift) |
| Emulator | Install the emulator, start the firmware, show the screen and send button pushes. | [EmulatorView.swift](../mac/Sources/iPodFirm/EmulatorView.swift) |

[AppModel.swift](../mac/Sources/iPodFirm/AppModel.swift) holds the state and the actions of all panes.

The Settings window (iPodFirm > Settings…, `SettingsView` in [App.swift](../mac/Sources/iPodFirm/App.swift)) has two tabs. Permissions: the Touch ID helper, `requireTouchID` and Full Disk Access. Layout: the empty margin below 8 MB (`ososMargin`, `ThemeImport.OSOSMargin`): 32 KB (the limit 0x7F8000, the default), 16 KB (the limit 0x7FC000, more space for patches) or 64 KB (the limit 0x7F0000, the value before 9 October 2026). The setting applies to the next build and to the space bar of the Patches pane.

The menus ([App.swift](../mac/Sources/iPodFirm/App.swift)):

| Menu | Commands |
|---|---|
| File | Open Firmware… (⌘O), Download Apple Firmware 1.3, Save Firmware As… (⇧⌘S), Export as .ipsw…, Export Pictures & Text…, Import Pictures & Text…, Import iPodWizard Theme…, New Patch…, Install Patch… |
| iPod | Flash to iPod… (⇧⌘F), Back Up iPod, Eject iPod (⌘E), Run in Emulator (⌘R) |

The Emulator pane shows the iPod at a fixed size (370 × 620 points) in the centre of its column. In a tall column, the iPod is larger, to a maximum of 1.4 times. The settings column has a maximum width of 520 points.

## The build of the app

`mac/scripts/build-app.sh` does these steps:

1. It increases the version and the build number in [mac/version.env](../mac/version.env).
2. It runs `swift build -c release --arch arm64`.
3. It makes `iPodFirm.app` with the app, the helper, the launchd property list, the emulator files and the patches.
4. It writes `Info.plist`. The bundle identifier is `com.thefauxdreamer.ipodfirm`.
5. It signs the helper with the identifier `com.thefauxdreamer.ipodfirm.helper`, then the app. It uses the first "Apple Development" or "Developer ID Application" identity, or `CODESIGN_IDENTITY`.
6. It writes the new numbers to `version.env` only after a successful build.
7. It quits iPodFirm with `osascript` if iPodFirm is open. Then it installs the app in `/Applications`.

The variable `APP_NAME` changes the name of the app (the default is `iPodFirm`). Use it to install a test build next to the normal app, for example `APP_NAME="iPodFirm USB-C Test" mac/scripts/build-app.sh`. The two apps have the same bundle identifier and the same helper. Do not open the two apps at the same time.

A stable signature is necessary. macOS connects Full Disk Access to the signature. An ad-hoc signature changes with each build, and the permission is lost.

### The release build

`RELEASE=1 mac/scripts/build-app.sh` makes a build for a GitHub release:

1. It increases the version and the build number, as a normal build does.
2. It signs the helper and the app with an ad-hoc signature (`codesign --sign -`). It ignores `CODESIGN_IDENTITY`.
3. It stops if `codesign -dvv` shows an `Authority=` line.
4. It makes `build/iPodFirm-<version>.zip` with `ditto -c -k --keepParent`.
5. It does not install the app in `/Applications`.

A developer certificate contains the e-mail address or the name of the owner. Any person can read it with `codesign -dvv`. An ad-hoc signature contains no name and no e-mail address.

An ad-hoc build has these limits:

- Gatekeeper blocks the app at the first start. The user must open it with Control-click and **Open**.
- The build has no team identifier. The daemon refuses to start, so the Touch ID helper is not available. `HelperRow` shows this and does not show "Set Up Touch ID". The app uses the password prompt.
- macOS loses Full Disk Access after each update, because the signature changes. The user must turn on the permission again.

## The detection of the iPod

`Device.findIPods` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift) does these steps:

1. Run `diskutil list -plist external physical`.
2. For each disk, run `diskutil info -plist <disk>`.
3. Keep a disk if its `MediaName` or `IORegistryEntryName` contains "ipod" (any case).
4. Record the block size, the size and the volume name.

The app reads the disk size to identify a probable original hard drive. Refer to [modifications.md](modifications.md#storage-type).

`FirmwareFlasher.locatePartition` then finds the firmware partition in the MBR or in the Apple partition map. Refer to [firmware-format.md](firmware-format.md#the-location-of-the-firmware-partition).

The helper refuses an iPod that is not an iPod Video. It returns the code `unsupported-ipod`, and the iPod pane disables the back-up, flash and restore buttons. It does two tests:

1. It identifies an iPod with a Samsung CPU (iPod classic). Its directory is at the value at 0x104 + 0x1000, because it uses 4096-byte sectors (`FirmwarePartition.samsungImageHeader`). Refer to [re/ipod-classic-6g.md](../re/ipod-classic-6g.md).
2. It reads the model code in the osos directory entry (`vers >> 8`). The iPod Video has 0xB0.

## Privileged access

The raw disk `/dev/rdiskN` needs root rights. The app itself never opens the raw disk for a write. The helper `ipodfw-helper` does all raw reads and writes. The app starts the helper in one of two modes.

### Mode 1: the launchd daemon (Touch ID)

1. The owner clicks "Set Up Touch ID" in the Settings window (Permissions).
2. The app registers the daemon with `SMAppService.daemon(plistName: "com.thefauxdreamer.ipodfirm.helper.plist")`.
3. macOS asks the owner to approve the daemon in System Settings > General > Login Items.
4. launchd starts `ipodfw-helper --daemon` when the app connects to the Mach service `com.thefauxdreamer.ipodfirm.helper`.
5. Before each write, the app asks for Touch ID (`LAContext.evaluatePolicy(.deviceOwnerAuthentication)`). The owner can switch this off (`requireTouchID`).
6. The daemon stops after 60 seconds without a request.

Both sides of the XPC connection examine the code signature:

- The daemon accepts only the code `identifier "com.thefauxdreamer.ipodfirm"`, signed by the same team (`setCodeSigningRequirement`).
- The app accepts only the helper `identifier "com.thefauxdreamer.ipodfirm.helper"`, signed by the same team.
- The daemon refuses to start if it has no team identifier (an ad-hoc signature).

The XPC protocol is `HelperXPCProtocol` in [HelperXPC.swift](../mac/Sources/IPodFWKit/HelperXPC.swift). The protocol version is 2.

| Method | Arguments | Result |
|---|---|---|
| `status` | — | `HelperStatus`: version, Full Disk Access |
| `backup` | disk, backup folder | `HelperResult` |
| `flash` | disk, image, backup folder, reason, dry run | `HelperResult` |
| `rescueRestore` | disk, image, backup folder, dry run | `HelperResult` |

The results are JSON data. The daemon writes backups only inside `~/Library/Application Support/iPodFirm/` of the user that called it (`checkedBackupDir`). It sets the owner of each backup file to that user.

### Mode 2: the password prompt

If the daemon is not enabled, the app runs the helper with AppleScript:

```applescript
do shell script "'<app>/Contents/MacOS/ipodfw-helper' 'flash' '--disk' 'disk4' ..." with administrator privileges
```

macOS asks for an administrator password. The helper writes one `HelperResult` JSON object to standard output and always exits with 0. Thus AppleScript returns the output also for an error. [Privileged.swift](../mac/Sources/iPodFirm/Privileged.swift) puts each argument in single quotes.

The helper commands are:

```sh
ipodfw-helper backup --disk diskN --backup-dir DIR [--owner UID]
ipodfw-helper flash  --disk diskN --image FILE --backup-dir DIR --reason TEXT [--dry-run] [--owner UID]
ipodfw-helper rescue --disk diskN --image FILE --backup-dir DIR [--dry-run] [--owner UID]
```

The helper refuses to run if it is not root.

### Full Disk Access

macOS blocks raw disk access without Full Disk Access. The app tests the permission: it tries to open `/Library/Application Support/com.apple.TCC/TCC.db` for read. With the daemon, the daemon does the same test, because its permission is the permission that counts. If `open` returns `EPERM`, the helper returns the code `full-disk-access`, and the app shows the steps to allow the permission.

## The flash sequence

1. "Flash Edited Firmware…" builds the partition (refer to [modifications.md](modifications.md#the-build-sequence)) and writes it to `~/Library/Application Support/iPodFirm/Staging/flash.bin`.
2. The app makes sure that MiMusic does not write to the iPod (refer to [safety.md](safety.md#the-checks-before-a-flash)).
3. The app runs the helper with `--dry-run`. The helper does all the checks and returns the block ranges that it will write. It writes nothing.
4. If the iPod firmware is damaged and the action is a restore, the app tries the rescue restore with `--dry-run`.
5. The app shows the ranges and the byte count. If MiMusic is open, it also shows a warning. The owner must confirm.
6. The app does the MiMusic check again. Then it asks for Touch ID (daemon mode) or the password (password mode).
7. The helper runs again without `--dry-run`. It saves a backup, unmounts the disk, writes the changed blocks, reads them again and compares them.

[safety.md](safety.md) gives each check.

## External programs

| Program | Caller | Arguments | Purpose |
|---|---|---|---|
| `/usr/sbin/diskutil` | `Device` (app and helper) | `list -plist external physical`, `info -plist DISK` | Find the iPod. |
| `/usr/sbin/diskutil` | Helper | `unmountDisk DISK` | Unmount the iPod before a write. |
| `/usr/sbin/diskutil` | App | `eject DISK` | Eject the iPod. |
| `/usr/bin/xcrun clang` | `Patcher.compile` | Refer to [patch-system.md](patch-system.md#the-compiler) | Compile a patch. |
| `/usr/bin/xcrun` | `PatchLibrary.hasCompiler` (the install and `PatchEditorSheet`) | `--find clang` | Find out if the Mac can compile a patch. |
| `/usr/bin/ditto` | `IPSW.unpack` | `-x -k IPSW DIR` | Extract an `.ipsw` file. |
| `/usr/bin/ditto` | `PatchLibrary.inspect`, `PatchLibrary.export` | `-x -k FILE DIR`, `-c -k --keepParent DIR FILE` | Open and make a `.ipodpatch` file. |
| `/usr/bin/zip` | `IPSW.repack` | `-q -X -r OUT .` | Make an `.ipsw` file. |
| `/bin/bash` | `EmulatorManager.install` | `install-emulator.sh` | Install the emulator. |
| `ipod-boot` | `EmulatorManager` | `make-disk IPSW DRIVE`, `put-files DRIVE DIR /iPod_Control` | Make the emulator drive. |
| `ipod-emulator` | `EmulatorSession` | `--headless=… --control=/tmp/ipodfirm-UID.sock` | Run the emulator without a window. |
| `ipod-emulator.app` | `EmulatorManager.openWindow` | `--cold` | Open the emulator window. |

`install-emulator.sh` runs these programs: `curl` (rustup, only if Rust is not installed), `git clone` or `git pull`, `git apply` (the iPodFirm patches), `cargo build --release -p ipod-gui -p ipod-machine` and `ditto`.

## System APIs

| API | Use |
|---|---|
| `open`, `pread`, `pwrite`, `fsync` | Raw disk access in the helper (`RawDisk`). Reads use chunks of 4 MB. Writes must be aligned to the block size. |
| `chown` | The helper gives the backup files to the user. |
| `SMAppService` | Register and unregister the daemon. Open Login Items. |
| `NSXPCConnection`, `NSXPCListener` | The connection between the app and the daemon. |
| `SecCodeCopySelf`, `SecCodeCopySigningInformation` | Read the team identifier for the signature requirement. |
| `LAContext` | Touch ID before a write. |
| `NSAppleScript` | The password mode. |
| `URLSession` | Download the Apple firmware. |
| `CryptoKit.SHA256` | Hashes of the firmware, the osos and the backups. |
| `CGImageSource`, `CGContext` | Read and scale the cover images and the PNG files. |
| `AVURLAsset` | Read the cover of a non-MP4 music file. |
| `NSWorkspace` | Open Finder, System Settings and the emulator app. |
| `NSRunningApplication` | Find out if MiMusic (`com.thefauxdreamer.MiMusic`) is open before a flash. |
| Unix domain socket | Send commands to the emulator (`shot`, `press`, `wheel`). |
| `UserDefaults` | The settings of the app (refer to [Settings of the app](#settings-of-the-app)). |

## Network connections

| URL | When | Check |
|---|---|---|
| `http://appldnld.apple.com.edgesuite.net/content.info.apple.com/iPod/SBML/osx/bundles/061-2967.20080313.Cnvkg/iPod_25.1.3.ipsw` | "Download Apple Firmware 1.3", and each action that needs the Apple file if no correct copy is cached. | SHA-256 must be `840b2480ad5b692c098cb772c3d2bf8f58bf37557788782b596ac01c27ecdc32`. Apple serves this file only over HTTP, so `Info.plist` has an App Transport Security exception for this domain. |
| `https://sh.rustup.rs` | "Install Emulator", only if `~/.cargo/bin/cargo` does not exist. | TLS 1.2 or later. |
| `https://github.com/siggifly/ipod-emulator.git` | "Install Emulator". | Git over HTTPS. |
| crates.io (through `cargo`) | "Install Emulator". | Cargo lock file of the emulator. |

The app makes no other network connections. It sends no data about the owner or the iPod.

## Files

### Files on the Mac

All paths are in `~/Library/Application Support/iPodFirm/`.

| Path | Content |
|---|---|
| `Backups/*.bin`, `Backups/*.bin.json` | The firmware partition backups and their metadata. |
| `Backups/Original (first backup).bin` | The first backup. The app never replaces it. |
| `Firmware/iPod_25.1.3.ipsw` | The cached Apple firmware. |
| `Themes/*.ipodtheme` | The imported themes (JSON). |
| `Patches/<name>/` | The patches that the owner installed or made with New Patch…. At the start, the app writes the measured `size` into a `patch.json` that has no size. |
| `Staging/flash.bin` | The partition that the helper writes. |
| `Staging/patch-<UUID>/` | A `.ipodpatch` file during the install or the export, or a copy of the code during Check Code. The app deletes it after use. |
| `Emulator/` | The emulator work folder: the custom `.ipsw` and the music libraries. |
| `EmulatorProfile/` | The private emulator profile (`IPOD_EMULATOR_DATA`): the drive and `settings.txt`. |
| `emulator-src/` | The emulator source and its build. |
| `tools/`, `re/` | Ghidra, the JDK and the Ghidra project. Only for research. The app does not use them. |

Temporary files: the object file of each patch, the extracted `.ipsw` folder and the emulator screen shot are in the temporary folder. The emulator socket is `/tmp/ipodfirm-<uid>.sock`.

### Files on the iPod volume

The app writes these files on the mounted iPod volume. A patch can also write files below `iPod_Control/` with the `actions` and `toggles` of its `ui` object (refer to [patch-system.md](patch-system.md#the-ui-object)). The app does not change any other file.

| Path | Writer | Reader |
|---|---|---|
| `iPod_Control/iTunes/iPodFirmAlbumArt` | "Write Thumbnails to iPod" | `album-art` patch |
| `iPod_Control/iTunes/iPodFirmPlaylistArt/*.png` | "Choose Image…" in Playlist Artwork | iPodFirm (the next thumbnail file) |
| `iPod_Control/iTunes/iPodFirmDarkMode` | The `dark-mode` patch on the iPod | `dark-mode` patch |
| `iPod_Control/iTunes/iPodFirmUSBProbe`, `iPod_Control/iTunes/iPodFirmUSBLog` | "Start the Probe at the Next Restart" (`ui.actions` of `usb-host-probe`) | `usb-host-probe` patch, "Show USB Log" |

The app reads `iPod_Control/iTunes/iTunesDB` and the music files. It does not change them. Before a flash, the app looks for the MiMusic temporary files `iTunesDB.tmp`, `ArtworkDB.tmp` and `iPodFirmAlbumArt.tmp`.

### Settings of the app

| `UserDefaults` key | Content |
|---|---|
| `enabledPatches` | The names of the switched-on patches. |
| `patchOptions` | The selected choice of each patch option: patch name → option `id` → value (refer to [patch-system.md](patch-system.md#options)). |
| `appearance` | `light`, `dark` or `switch`. |
| `darkTheme` | The name of the selected theme. |
| `customVersionOn`, `customVersion` | The custom version. |
| `versionLettersOn` | The patch letters on the About screen. |
| `requireTouchID` | Touch ID before a write (daemon mode). |
| `ososMargin` | The empty margin below 8 MB: `current` (32 KB, limit 0x7F8000), `compact` (16 KB, limit 0x7FC000) or `previous` (64 KB, limit 0x7F0000). |
| `emulatorLibrary`, `emulatorMusicFolder`, `emulatorSongCount` | The music library on the emulator drive. |

## The emulator

The Emulator pane uses [siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator), built from source. iPodFirm adds the patch [0001-ipodfirm-instrumentation.patch](../mac/Resources/emulator-patches/0001-ipodfirm-instrumentation.patch) before the build. Refer to [re/emulator.md](../re/emulator.md).

"Run in Emulator" does these steps:

1. Build the osos (the same build as a flash).
2. Put it into the Apple firmware 1.3 (`IPSW.firmware`). rsrc and aupd move forward if osos is larger.
3. Make the `.ipsw` and run `ipod-boot make-disk`.
4. Correct the osos length in the drive. `make-disk` makes it 0x600 bytes too short (`EmulatorDrive.fixOSOSLength`).
5. Copy a music library to the drive (`put-files`): none, a test library of 60 tracks, or songs from a folder.
6. Write the profile: a synthetic 5.5G (NOR model A444, seed `5500550055005500`).
7. Start the emulator without a window. `IPODFW_RESET_AFTER=1000000000` lets the Dark Mode item restart the emulated iPod.
8. Read the screen with the `shot` command and show it. Send `press` and `wheel` commands for the controls.

The emulator has no audio and no USB. It does not model the hardware sleep. It runs at approximately one quarter of the real speed.
