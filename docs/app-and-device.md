# The app and the device

This document describes the structure of the iPodFirm app. It tells how the app finds the iPod and how it gets the rights to write the disk. It lists each external program, system API, network connection and file that the app uses.

## The parts

The Swift package is in [mac/](../mac/). [Package.swift](../mac/Package.swift) has three targets:

| Target | Type | Function |
|---|---|---|
| `IPodFWKit` | Library | The firmware formats, the patcher, the theme import, the disk access and the safety checks. It has no user interface. |
| `iPodFirm` | App | The SwiftUI user interface. |
| `IPodFWKitTests` | Tests | `swift test`. |

The Python package in [src/ipodfw/](../src/ipodfw/) has the same formats. The two implementations must give the same bytes. When you change a format in one package, change the other package too.

The app needs macOS 14 or later and an Apple silicon Mac (`--arch arm64`).

## The panes

The sidebar has two sections. The section "Device" has only the iPod row. The row has one line. The line shows the name that iTunes set for the iPod, "Not Connected" or "Not Supported" (`AppModel.currentIPodStatus`). The app reads the name from the master playlist of the `iTunesDB` (`ITunesDB.readLibraryName`). If the iPod has no name, the row shows the volume name. The icon is green only for a connected, supported iPod. The section "Tools" has the other panes (`Pane.tools`). The footer shows the app version.

| Pane | Functions | Main code |
|---|---|---|
| Firmware | The images, the checksums and the model of the open file. | [OverviewView.swift](../mac/Sources/iPodFirm/OverviewView.swift) |
| Pictures | Show, export and replace pictures. Show the dark theme pictures. | [PicturesView.swift](../mac/Sources/iPodFirm/PicturesView.swift) |
| Text | Change the strings of each language. | [StringsView.swift](../mac/Sources/iPodFirm/StringsView.swift) |
| Patches | The patch `custom-eq` shows the section "Custom EQ" (`CustomEQView`): a list of named EQs (Add, Rename, Delete), a curve, and a Simple view (sliders) or an Advanced view (bands). The default is 3 bands. Use All 5 Bands and Go Beyond Apple's Limits need the agreement of the user. Start From Apple Preset sets the bands close to an Apple preset. Settings > Patches > Colourful EQ Curve mixes one colour for each band in the curve. This is only visual. The values are options of the patch. Export EQ… and Import EQ… write and read a `.ipodeq` file (`SharedEQ` in [CustomEQ.swift](../mac/Sources/IPodFWKit/CustomEQ.swift)). A double-click on the file in Finder also imports it. Each row of the list has one line for the title and one line for the summary. Settings > Patches > Show Descriptions in the Patch List turns off the summary line. The tooltip of the row always shows the summary. The detail of a patch has the warnings at the top, then What It Does, You Need, the options, the controls and Information. Good to Know is folded. A list at the left: iPod Appearance, Software Version and the patches (grouped by `category`: Display, Power and Storage, Sound, Playback, Fun, Tests, and Community for each installed patch and for a patch with no known `category`). Below the list: **+** (install a patch), **−** (remove a user patch) and **⋯** (New Patch…, Install Patch…, Edit Patch…, Export Patch…, Remove Patch…, Show Patches Folder). New Patch… and Edit Patch… open `PatchEditorSheet` ([PatchEditor.swift](../mac/Sources/iPodFirm/PatchEditor.swift)). The sheet writes the text of `patch.json`. Refer to [patch-system.md](patch-system.md#make-and-share-a-patch). The context menu of a user patch also has Edit Patch…. The detail of a user patch has a Code section with the C code, the firmware functions, the hooks, the byte changes, Check Code and Save ([PatchCodeView.swift](../mac/Sources/iPodFirm/PatchCodeView.swift); refer to [patch-system.md](patch-system.md#the-code-section)). The list accepts a dropped `.ipodpatch` file or patch folder. Below the buttons, a bar shows the space after Apple's image (0x736800 to 0x7F8000) that the theme, the Dark Mode items and the extended patches use. The app measures it again 0.3 s after each change of a patch switch or of the appearance (`AppModel.refreshSpaceUse`: a build of the appearance, plus the code size of each switched-on patch, `Patcher.codeSize` and `Patcher.spaceUse`). If the firmware is too large, the bar is red and the text gives the excess. Each patch row has an SF Symbol, the title, the summary, the letter, the version, the size on the iPod and a switch. A switch also turns on the patches that the patch needs (`needs` in `patch.json`), and turns off the patches that need a patch that the owner turns off (`AppModel.setPatch`). The detail at the right shows the selected row: the caution, the sections "What It Does", "You Need" and "Good to Know", the compatibility, the conflicts, the version, the size on the iPod (`size` in `patch.json`; the install, the export and the app start record the measured size), the source and the controls from the `ui` object of `patch.json`. When an iPod is connected, a banner at the top of the list compares the switches with the patches on the iPod (refer to [The patches on the iPod](#the-patches-on-the-ipod)). | [PatchesView.swift](../mac/Sources/iPodFirm/PatchesView.swift) |
| Games | The pane starts with an explainer: the app does not come with the game files and does not download them; the game files come from the iPod that bought them. The section **Install Games** copies the games to the iPod. The button **Select Games Folder…** chooses the folder of the games, or the folder `iPod_Control` of an iPod (`AppModel.chooseGamesFolder`). The app accepts the names `games_RO` and `Games_RO` (`GameLibrary.gamesDirectory`). The pane shows each game with a switch, a button **Select All** and a button **Select None**. All games are selected after the choice of a folder. An empty selection installs no game, and **Install Games** is then off. The button **Install Games** copies the selected games to the folder `games_RO` of the connected iPod (`AppModel.installGames`, `GameInstaller` in [Games.swift](../mac/Sources/IPodFWKit/Games.swift)). The app checks the size of each file of the array `Files` of the manifest before the copy. The app skips a game that is not complete. The app never changes the file `Manifest.plist` or the file `Manifest.plist.p7b`. The optional button **Choose Key File…** selects the owner's file `IC-Info.sidb` (`AppModel.chooseGameKeyFile`). `GameInstaller.checkKeyFile` accepts only that name, a size above 0 and a maximum of 4 MB; it does not read the bytes. **Install Games** then copies the file one time, after the games, to `iPod_Control/iTunes/IC-Info.sidb` (`GameInstaller.copyKey`). **Clear** removes the choice. The section **Remove Games** lists the games of the folder `games_RO` of the iPod (`AppModel.readIPodGames`). The button **Remove Selected Games…** opens a confirmation dialog, with Cancel as the default button, and removes the folder of each selected game (`AppModel.removeGames`, `GameRemover` in [Games.swift](../mac/Sources/IPodFWKit/Games.swift)). The removal deletes only the folder of the game. The folders `gamedata_RW` and `gamestats_WO` stay. Refer to [re/games.md](../re/games.md). | [GamesView.swift](../mac/Sources/iPodFirm/GamesView.swift) |
| iPod | When the flash buttons are off, their tooltip gives the reason (`AppModel.flashBlockReason`). If the iPod is ready but no firmware is open, the status line `FlashHint` shows, with Download Apple Firmware 1.3 and Open Firmware…. These commands keep the current pane. The Patches pane shows `FlashHint` in the banner when the switches differ from the iPod. Two columns. The left column starts with the name of the connected iPod, in large text. It then has the commands, the patches on the iPod and the logs on the iPod. The right column has the backups, the recovery steps and the protections. A row shows the permission status and opens the Settings window. The section "Patches on This iPod" shows the patches, the versions and the appearance on the iPod, and has a Read iPod button. The section "Logs on This iPod" shows each log file that has data, also if the patch is off in the app (`AppModel.refreshIPodLogs`). **Show Log** opens the log in `IPodLogSheet`. | [IPodView.swift](../mac/Sources/iPodFirm/IPodView.swift) |
| Emulator | Install the emulator, start the firmware, show the screen and send button pushes. | [EmulatorView.swift](../mac/Sources/iPodFirm/EmulatorView.swift) |

[AppModel.swift](../mac/Sources/iPodFirm/AppModel.swift) holds the state and the actions of all panes.

The Settings window (iPodFirm > Settings…, `SettingsView` in [App.swift](../mac/Sources/iPodFirm/App.swift)) has three tabs. Layout: the empty margin below 8 MB (`ososMargin`, `ThemeImport.OSOSMargin`). The default is 32 KB (the limit 0x7F8000). The value 16 KB (the limit 0x7FC000) gives more space for patches. The value 64 KB (the limit 0x7F0000) is the value before 9 October 2026. The setting applies to the next build and to the space bar of the Patches pane. Patches: "Enable Test Patches" (`showTestPatches`, Off by default) and "Show Descriptions in the Patch List" (`showPatchSummaries`, On by default). Off: the Patches pane does not show the patches of the category `test` (`PatchSpec.visible`). A build does not include them, also if they are switched on. On: the pane shows them, with a red warning at the top of the details (`TestPatchWarning`). Updates: "Check for a new version at launch" (`checkForUpdates`, On by default). Refer to [The update check](#the-update-check).

The menus ([App.swift](../mac/Sources/iPodFirm/App.swift)):

| Menu | Commands |
|---|---|
| File | Open Firmware… (⌘O), Download Apple Firmware 1.3, Save Firmware (⌘S), Save Firmware As… (⇧⌘S), Export as .ipsw…, Export Pictures & Text…, Import Pictures & Text…, Import iPodWizard Theme…, New Patch…, Install Patch… |
| iPod | Flash to iPod… (⇧⌘F), Back Up iPod, Eject iPod (⌘E), Run in Emulator (⌘R) |
| View | Show Sidebar, and a command for each pane: iPod (⌘1), Firmware (⌘2), Pictures (⌘3), Text (⌘4), Patches (⌘5), Games (⌘6), Emulator (⌘7) |
| Help | iPodFirm Documentation, Show Disclaimer, Thanks…, Open Log, Save Log…, Report a Problem on GitHub… |

While the app downloads the Apple firmware, the busy overlay shows a progress bar and a Cancel button. A flash has no Cancel button. The app menu has Check for Updates…. Save Firmware writes to the file of the last Save As. The first save shows the panel, because the app never overwrites the file that it opened.

At the first launch, the app shows the disclaimer sheet (`DisclaimerSheet` in [DisclaimerSheet.swift](../mac/Sources/iPodFirm/DisclaimerSheet.swift)). The sheet gives the risk of a flash, the absence of a warranty and the Apple trademark notice. The user cannot close the sheet with Esc. The **Agree** button is available only after the user turns on the checkbox. **Agree** records `Disclaimer.version` in `acceptedDisclaimerVersion`. **Quit** stops the app. A `.ipodpatch` file that Finder opens waits until the user accepts the disclaimer. After a large change to the text, increase `Disclaimer.version`. Then each user must accept the disclaimer again. Help > Show Disclaimer shows the sheet again with only a **Close** button.

Help > Thanks… shows the Thanks sheet (`ThanksSheet` in [ThanksSheet.swift](../mac/Sources/iPodFirm/ThanksSheet.swift)). The sheet lists the people who reported problems, supplied fixes or gave ideas. Each entry has a name, a reason, an optional link and an optional `version`. The `version` is the first app version that has the fix. `Thanks.sorted` shows the newest version first. The entries with no version come last. The link opens in the browser only when the user clicks it. The list `Thanks.people` and the sort are in [Thanks.swift](../mac/Sources/IPodFWKit/Thanks.swift). To add a person, add an entry to `Thanks.people` with the `version` of the release. The position in the list is not important. Also add the person to the Credits section of the README. The tests `testThanksSortNewestFirst` and `testThanksEntries` check the sort and each entry.

#### The update check

The app does not download or install an update. It only tells the user about a newer release on GitHub. [UpdateCheck.swift](../mac/Sources/IPodFWKit/UpdateCheck.swift) gets the release, and [UpdateNotifier.swift](../mac/Sources/iPodFirm/UpdateNotifier.swift) shows the notification.

1. At the launch, `AppModel.checkForUpdate(manual: false)` starts if `checkForUpdates` is on and the user accepted the disclaimer. At the first launch, the check starts after the acceptance.
2. `UpdateCheck.fetchLatest` gets the newest release from the GitHub API (refer to [Network connections](#network-connections)). GitHub does not give drafts or pre-releases.
3. `UpdateCheck.isNewer` compares the numbers of the tag (without the `v`) with `CFBundleShortVersionString`. A missing number counts as 0. A version that is not a number, for example `dev`, gives no update.
4. If the release is newer and it is not `skippedUpdateVersion`, the app posts a macOS notification. macOS asks the user one time to allow notifications.
5. A click on the notification or on **Open GitHub** opens the release page in the browser. **Skip This Version** writes the version into `skippedUpdateVersion`.

If the user does not allow notifications, the app shows an alert with the same buttons and **Later**. At the launch, a network error gives no message. iPodFirm > Check for Updates… does the same check, but it ignores `skippedUpdateVersion`. It also shows an alert if the app is up to date or if the check fails. The tests `testUpdateVersionCompare` and `testUpdateReleaseParse` check the comparison and the JSON decode.

#### The log and the fault report

The app keeps a log. [AppLog.swift](../mac/Sources/IPodFWKit/AppLog.swift) writes each line to `~/Library/Logs/iPodFirm/iPodFirm.log` and to the unified log of macOS. Console.app shows the lines with the subsystem `com.thefauxdreamer.ipodfirm`. At 1 MB, the file becomes `iPodFirm.1.log`, and a new file starts. The app keeps only these two files.

The log records these items:

1. The launch: the app version, the macOS version and the Mac model.
2. The iPods that the app finds.
3. The steps of each operation (`AppLog.step`). Examples are each `work` label, each patch that the build applies, and the read, write and verify of a flash.
4. The result of each operation on the iPod. On a fault, the log also gets the full error.
5. Each fault, and each error that the app shows only as a status text.

The fault report and Save Log… also give the path and the signature of the app, and the state of the app folder (`appFolderReport`). For the parent folder, `iPodFirm`, `Staging` and `Backups`, the state is the owner, the mode, the flags and the ACL state. For the last three, the app also makes and deletes a small test file (`writeTest`). The report also gives the user ID of the app. A failed test with the system error shows the real cause of a write fault.

The fault report and Save Log… also give model data of the iPod. The data comes from `iPod_Control/Device/SysInfo` on the mounted volume (`IPodDisk.sysInfoReport`). The app shows only the keys `ModelNumStr`, `visibleBuildID` and `BoardHwName`, thus no serial number and no FireWire GUID. The report also tells if the size agrees with an original drive.

Each read of the partition records the layout of the iPod (`Operations.layoutReport`). The layout has the name, position, length, version, checksum result and SHA-256 of each image, and the map of the areas with data and the zero areas. `hibe` has no hash. The layout has no image data, so a user can send it. A user must not send a backup: it holds Apple firmware and, in `hibe`, the RAM of the iPod with the music library. The file `.bin.json` of a backup holds the iPod name. After a read, the app writes the layout to its log. On a fault, the steps of the operation hold it. If `makeRoom` finds no area for rsrc, a step gives the size of the largest empty area.

The log has no home folder path and no user name. `AppLog.redact` changes `/Users/<name>` to `~` and the short user name to `<user>`. The log has no serial number and no volume name. Only the app writes the log file. The tests and the operation write only to the unified log.

Each error has more data than its message. `FirmwareError` and `PatchError` record the file, the line and the function of the throw. A `FirmwareError` can also have `context` (the steps of the callers, from `adding(_:)`) and `cause` (the full description of the error that caused it). `AppLog.describe` writes all of this data. It also writes the domain, the code and the underlying errors of an `NSError`.

All faults go through `AppModel.fail`. It writes the error, the last 15 steps and the state of the app (`diagnosticSnapshot`) to the log. The state has the open file name, the iPod model and the iPod size. It also has the patches on the iPod and in the app, with their versions and options. It also has the appearance and the Full Disk Access status. The alert shows the message and the last step of the last two minutes. The alert of a fault has three buttons:

- **Report on GitHub…** saves the log as a text file. Then it opens a new issue on GitHub in the browser (refer to [Network connections](#network-connections)). The issue starts with the instruction to attach the file. It holds only the fault, a short summary of the app and the iPod, the first lines of the error and the last three steps (`AppModel.issueSummary`, `AppLog.faultExcerpt`). The user drags the file into the issue. The file has all other data.
- **Save Log…** saves the state of the app and the two log files as one text file, for example `iPodFirm Log 2026-10-29 1405.txt`. Finder then shows the file.
- **OK** closes the alert.

Help > Save Log… and Help > Report a Problem on GitHub… do the same with no fault. Help > Open Log opens the most recent log, `iPodFirm.log`, in the default app for a `.log` file. On a Mac with no change to this setting, this app is Console. If no app opens the file, Finder shows it. The tests in `AppLogTests` check the file, the rotation, the redaction, the steps, the error data, `HelperResult.detail` and the issue address.

The Emulator pane shows the iPod at a fixed size (370 × 620 points) in the centre of its column. In a tall column, the iPod is larger, to a maximum of 1.4 times. The settings column has a maximum width of 520 points.

## The build of the app

`mac/scripts/build-app.sh` does these steps:

1. It increases the version and the build number in [mac/version.env](../mac/version.env).
2. It runs `swift build -c release --arch arm64` with the option `-file-prefix-map <project folder>=.`. The compiler then writes `./mac/Sources/...` in place of the full path of each source file. Thus the build does not change with the location of the project folder.
3. It makes `iPodFirm.app` with the app, the plist of the old daemon, the emulator files and the patches.
4. It runs `strip -S` on the app. This removes the debug map of the linker. The app does not use it.
5. It writes `Info.plist`. The bundle identifier is `com.thefauxdreamer.ipodfirm`.
6. It signs the app. It uses the first "Apple Development" or "Developer ID Application" identity, or `CODESIGN_IDENTITY`. It turns on the hardened runtime (`--options runtime`) for the two programs.
7. It writes the new numbers to `version.env` only after a successful build.
8. It waits if iPodFirm is open, and it stops with an error if the app stays open. It does not quit the app. Then it installs the app in `/Applications`.

The variable `APP_NAME` changes the name of the app (the default is `iPodFirm`). Use it to install a test build next to the normal app, for example `APP_NAME="iPodFirm USB-C Test" mac/scripts/build-app.sh`. The two apps have the same bundle identifier and the same helper. Do not open the two apps at the same time.

The app does not need a stable signature, because it does not need Full Disk Access.

### The release build

`RELEASE=1 mac/scripts/build-app.sh` makes a build for a GitHub release:

1. It increases the version and the build number, as a normal build does.
2. It signs the app with an ad-hoc signature (`codesign --options runtime --sign -`). It ignores `CODESIGN_IDENTITY`.
3. It stops if a file in the app contains a path of the build Mac or the Git e-mail address. The script does not examine an address that ends in `@users.noreply.github.com`. The check occurs before the script writes the new numbers to `version.env`.
4. It stops if `codesign -dvv` shows an `Authority=` line.
5. It makes `build/iPodFirm-<version>.zip` with `ditto -c -k --keepParent`.
6. It does not install the app in `/Applications`.

`RELEASE=both mac/scripts/build-app.sh` makes the release ZIP and installs the app from one build. The two copies have the same version and build number:

1. It increases the version and the build number one time.
2. Before the signature, it copies the app to `build/release/<APP_NAME>.app`.
3. It signs `build/<APP_NAME>.app` with the identity of a normal build. It signs the copy with an ad-hoc signature.
4. It makes the ZIP from the copy, as `RELEASE=1` does.
5. It installs `build/<APP_NAME>.app` in `/Applications`, as a normal build does.

The script refuses a value of `RELEASE` that is not `0`, `1` or `both`. If `RELEASE` is not set, the script uses `both` on the `main` branch (`git rev-parse --abbrev-ref HEAD`) and `0` on other branches.

A developer certificate contains the e-mail address or the name of the owner. Any person can read it with `codesign -dvv`. An ad-hoc signature contains no name and no e-mail address.

An ad-hoc build has these limits:

- The script does not notarize the app. Gatekeeper blocks the app at the first start. The user must open it with Control-click and **Open**.

## The detection of the iPod

`Device.findIPods` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift) does these steps:

1. Run `diskutil list -plist external physical`.
2. For each disk, run `diskutil info -plist <disk>`.
3. Keep a disk if its `MediaName` or `IORegistryEntryName` contains "ipod" (any case).
4. Record the block size, the size and the volume name.

The app reads the disk size to identify a probable original hard drive. Refer to [modifications.md](modifications.md#storage-type).

`FirmwareFlasher.locatePartition` then finds the firmware partition in the MBR or in the Apple partition map. Refer to [firmware-format.md](firmware-format.md#the-location-of-the-firmware-partition).

`Operations` refuses an iPod that is not an iPod Video. It returns the code `unsupported-ipod`, and the iPod pane disables the back-up, flash and restore buttons. It does two tests:

1. It identifies an iPod with a Samsung CPU (iPod classic). Its directory is at the value at 0x104 + 0x1000, because it uses 4096-byte sectors (`FirmwarePartition.samsungImageHeader`). Refer to [re/ipod-classic-6g.md](../re/ipod-classic-6g.md).
2. It reads the model code in the osos directory entry (`vers >> 8`). The iPod Video has 0xB0.

## Privileged access

The raw disk `/dev/rdiskN` has the owner root and the mode 640. No code of iPodFirm runs as root. The app gets an open disk from the Apple program `/usr/libexec/authopen`, and the app does all the work with the user's rights. The measurements are in [re/privilege-analysis.md](../re/privilege-analysis.md).

`AuthOpen` in [AuthOpen.swift](../mac/Sources/IPodFWKit/AuthOpen.swift) does these steps:

1. `open` starts `authopen -stdoutpipe -o <flags> <path>`.
2. `authopen` asks for the right `sys.openfile.readonly.<path>` or `sys.openfile.readwrite.<path>`. `authopen` is signed by Apple, so macOS offers Touch ID. If Touch ID is not available, macOS asks for the name and the password of an administrator.
3. `authopen` sends the file descriptor (`SCM_RIGHTS`) on a socket. On a fault, it sends two bytes. The last byte is the `errno` value. Cancel gives `ECANCELED`.
4. macOS asks at each open, so `AuthOpen` keeps the descriptors. `read` keeps the read descriptor for 60 seconds. `prepareWrite` opens the firmware slice before the unmount, and `takeWrite` gives it to the write.

The app closes the read descriptor before an unmount and an eject. It examines a kept descriptor before each use, so a different iPod on the same path does not get the old descriptor.

`DiskAccess` in [Device.swift](../mac/Sources/IPodFWKit/Device.swift) gives the disk to `Operations`. The app uses `DiskAccess.authOpen()`. The tests use `DiskAccess.direct` with a disk image.

| Access | Path | Note |
|---|---|---|
| Read | `/dev/rdiskN` | The volume can stay mounted. |
| Write, with an `Apple_MDFW` slice | The slice | `Device.firmwareSlice` compares `PartitionMapPartitionOffset` with the partition map. A different value stops the write. `RawDisk.origin` keeps the offsets as positions on the whole disk. |
| Write, with no slice | `/dev/rdiskN` | The write comes after the unmount. A read-write open of the whole disk gives `EBUSY` while a volume is mounted. |

`DiskAccess.openForWrite` has one fallback: if the open of the slice fails, it opens the whole disk. `authorizeWrite` asks for both paths, so the fallback opens no second prompt. A slice at the wrong position does not use the fallback.

The app has no fallback to a root process. Refer to [re/privilege-analysis.md](../re/privilege-analysis.md).

The operations run in the app, so the app must not stop during a write. Refer to [safety.md](safety.md).

### The old daemon

Versions before this one could register a root daemon. At each launch, `OldDaemon.removeIfRegistered` removes a registration with `SMAppService.unregister`. It opens no prompt. A fault goes to the log and does not stop the launch.

macOS needs the plist in `Contents/Library/LaunchDaemons` of the calling app, so the app keeps [the plist](../mac/Resources/com.thefauxdreamer.ipodfirm.helper.plist). The app never calls `register`, and it has no helper program.

### Full Disk Access

The app does not need Full Disk Access. A real flash through `authopen` passed with the permission off (refer to [re/privilege-analysis.md](../re/privilege-analysis.md)). The fault report still records the permission (`AppModel.checkFullDiskAccess`), for a Mac where the result is different. If macOS gives `EPERM`, the error tells the user to turn on the permission.

## The flash sequence

1. "Flash to iPod…" builds the partition (refer to [modifications.md](modifications.md#the-build-sequence)) and writes it to `~/Library/Caches/iPodFirm/Staging/flash.bin`.
2. The app makes sure that MiMusic does not write to the iPod (refer to [safety.md](safety.md#the-checks-before-a-flash)).
3. The app runs `Operations.flash` with `dryRun`. The operation does all the checks and returns the block ranges that it will write. It writes nothing.
4. If the iPod firmware is damaged and the action is a restore, the app tries the rescue restore with `dryRun`.
5. The app shows the ranges and the byte count. If MiMusic is open, it also shows a warning. The owner must confirm.
6. The app does the MiMusic check again.
7. The operation runs again without `dryRun`. macOS asks for Touch ID or a password for the write, before the unmount. If the iPod has no firmware slice, this prompt comes after the unmount. It saves a backup, unmounts the disk, writes the changed blocks, reads them again and compares them. If the user clicks Cancel at the prompt, the iPod stays mounted and the app takes no backup. If the open fails after the unmount, no byte changed, and the app mounts the iPod again and shows the fault.

[safety.md](safety.md) gives each check.

## The patches on the iPod

The patch switches are settings of the app. The owner can change a switch and not flash. Thus the app compares the switches with the firmware on the iPod.

1. A build writes the iPodFirm list into osos (`FirmwareManifest`, refer to [patch-system.md](patch-system.md#the-ipodfirm-list)). The list has the patches, their versions and options, the appearance and the theme.
2. A read of the iPod opens a macOS prompt, so the app does not read when an iPod connects. The owner clicks Read iPod (`AppModel.readIPodPatches`, `Operations.readOSOS`).
3. `Patcher.detect` gives the state of each patch: installed (with the version from the list), absent, or not known. Without a list, the result comes from the changed words, and the versions are not known.
4. After a flash or a restore, the app uses the image that it wrote (`recordWrittenImage`). It does not read the iPod again.

The mirror rule uses `switchesChangedSinceSync`. This value shows a change to a switch, an option or the appearance after the last flash, restore or read. If there is no change, a new state sets the switches to the iPod (`AppModel.matchIPod`). Else the switches stay. A patch with the state "not known" keeps its switch. A patch on the iPod that the app does not have stays off.

The Patches pane shows the result:

- A banner at the top of the list: "The switches agree with the iPod", or the count of patches to add, to remove and to update, with the buttons Match iPod and Flash…. If no state is known, the banner has a Read iPod button.
- A mark in each row: On iPod (green), Not flashed, Will be removed, iPod has *version* (orange), or Not known.
- In the detail: "On the iPod" with the version, "No" or "Not known".

## External programs

| Program | Caller | Arguments | Purpose |
|---|---|---|---|
| `/usr/sbin/diskutil` | `Device` | `list -plist external physical`, `list -plist DISK`, `info -plist DISK` | Find the iPod and the firmware slice. |
| `/usr/sbin/diskutil` | `Operations` | `mountDisk DISK` | Mount the iPod again after an open that failed. |
| `/usr/libexec/authopen` | `AuthOpen` | `-stdoutpipe -extauth -o FLAGS PATH` | Open the raw disk. |
| `/usr/sbin/diskutil` | `Operations` | `unmountDisk DISK` | Unmount the iPod before a write. If macOS uses the volume, the app tries again, as for the eject. |
| `/usr/sbin/diskutil` | App | `eject DISK` | Eject the iPod. If macOS uses the volume ("dissented", "could not be unmounted" or "busy"), the app tries again. It tries a maximum of 5 times, 2 seconds apart (`Device.retryWhileBusy`). Then the alert "The iPod did not eject" says: "macOS is still accessing your iPod. Try again in a second." |
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
| `open`, `pread`, `pwrite`, `fsync` | Raw disk access in the app (`RawDisk`). `AuthOpen` gives the descriptor. Reads use chunks of 4 MB. Writes must be aligned to the block size. |
| `NSXPCConnection`, `NSXPCListener` | The connection between the app and the daemon. |
| `SecCodeCopySelf`, `SecCodeCopySigningInformation` | Read the team identifier for the signature requirement. |
| `SMAppService` | Remove the registration of the old daemon. |
| `URLSession` | Download the Apple firmware. Get the number of the newest iPodFirm release from GitHub (`UpdateCheck.swift`). |
| `os.Logger` | The unified log of macOS (`AppLog.swift`). |
| `sysctlbyname("hw.model")` | The Mac model for the log and the fault report. |
| `UNUserNotificationCenter` | Tell the user about a newer release (`UpdateNotifier.swift`). If the user does not allow notifications, the app shows an alert. |
| `CryptoKit.SHA256` | Hashes of the firmware, the osos and the backups. |
| `CCCrypt` (CommonCrypto), `compression_decode_buffer` (Compression) | Decrypt and inflate `iTunes Library.itl` (`ITunesLibrary.swift`). |
| `CGImageSource`, `CGContext` | Read and scale the cover images and the PNG files. |
| `AVURLAsset` | Read the cover of a non-MP4 music file. |
| `NSWorkspace` | Open Finder, System Settings, the emulator app and the GitHub issue page. |
| `NSRunningApplication` | Find out if MiMusic (`com.thefauxdreamer.MiMusic`) is open before a flash. |
| Unix domain socket | Send commands to the emulator (`shot`, `press`, `wheel`). |
| `UserDefaults` | The settings of the app (refer to [Settings of the app](#settings-of-the-app)). |

## Network connections

| URL | When | Check |
|---|---|---|
| `http://appldnld.apple.com.edgesuite.net/content.info.apple.com/iPod/SBML/osx/bundles/061-2967.20080313.Cnvkg/iPod_25.1.3.ipsw` | "Download Apple Firmware 1.3", and each action that needs the Apple file if no correct copy is cached. | SHA-256 must be `840b2480ad5b692c098cb772c3d2bf8f58bf37557788782b596ac01c27ecdc32`. Apple serves this file only over HTTP, so `Info.plist` has an App Transport Security exception for this domain. |
| `https://api.github.com/repos/TheFauxDreamer/iPod5.5Firm/releases/latest` | At each launch if Settings > Updates > "Check for a new version at launch" is on. iPodFirm > Check for Updates…. | TLS 1.2 or later. HTTP status 200 and JSON with `tag_name` and `html_url`. The app compares `tag_name` (without the `v`) with `CFBundleShortVersionString`. If the release is newer, the notification opens `html_url` in the browser. The app does not download the update. |
| `https://github.com/TheFauxDreamer/iPod5.5Firm/issues/new?title=…&body=…` | "Report on GitHub…" in the alert of a fault. Help > Report a Problem on GitHub…. | The app does not connect. It opens the address in the browser (`NSWorkspace.open`). The body starts with the instruction to attach the log. Then it has the fault, a short summary of the app and the iPod, the first lines of the error and the last three steps (`AppLog.issueURL`). It has a maximum of 1500 characters. The app cuts the end of a longer text. The user must sign in to GitHub and attach the saved log file. |
| `https://github.com/TheFauxDreamer/iPod5.5Firm/issues/new?title=…&body=…` | Patches > Playback Log or Diagnostic Log > "Report on GitHub…". | The app does not connect. It opens the address in the browser (`NSWorkspace.open`). The body has the app version and the information lines of the playback log: the RAM, the free memory and the patches. It has a maximum of 1500 characters. The owner of the log must sign in to GitHub and attach the text file. |
| `https://sh.rustup.rs` | "Install Emulator", only if `~/.cargo/bin/cargo` does not exist. | TLS 1.2 or later. |
| `https://github.com/siggifly/ipod-emulator.git` | "Install Emulator". | Git over HTTPS. |
| crates.io (through `cargo`) | "Install Emulator". | Cargo lock file of the emulator. |

The app makes no other network connections. It sends no data about the owner or the iPod. "Report on GitHub…" only opens a web page. The user decides to send it. The update check sends only a GET request with the default `User-Agent` of `URLSession`.

## Files

### Files on the Mac

The paths in this table are in `~/Library/Application Support/iPodFirm/`, unless the table gives a different folder.

The one exception is `iTunes Library.itl`. The user selects this file for "Import from iTunes…" in Playlist Folders. The app only reads it.

| Path | Content |
|---|---|
| `Backups/*.bin`, `Backups/*.bin.json` | The firmware partition backups and their metadata. |
| `Backups/Original (first backup).bin` | The first backup. The app never replaces it. |
| `Firmware/iPod_25.1.3.ipsw` | The cached Apple firmware. |
| `Themes/*.ipodtheme` | The themes of the owner (JSON). A file in format 1 holds the old bytes of each change. A file in format 2 holds the hash of the old bytes and no byte of the Apple firmware. The app makes the folder and copies the built-in themes into it at the first start. |
| `Patches/<name>/` | The patches that the owner installed or made with New Patch…. At the start, the app writes the measured `size` into a `patch.json` that has no size. |
| `~/Library/Caches/iPodFirm/Staging/flash.bin` | The partition that the app writes to the iPod. |
| `~/Library/Caches/iPodFirm/Staging/patch-<UUID>/` | A `.ipodpatch` file during the install or the export, or a copy of the code during Check Code. The app deletes it after use. |
| `Staging/`, `Staging old <UUID>/` | Old folders of older versions. The app does not use them and does not delete them. |
| `Emulator/` | The emulator work folder: the custom `.ipsw` and the music libraries. |
| `EmulatorProfile/` | The private emulator profile (`IPOD_EMULATOR_DATA`): the drive and `settings.txt`. |
| `emulator-src/` | The emulator source and its build. |
| `tools/`, `re/` | Ghidra, the JDK and the Ghidra project. Only for research. The app does not use them. |

The log is in `~/Library/Logs/iPodFirm/`: `iPodFirm.log` and the older `iPodFirm.1.log` (refer to [The log and the fault report](#the-log-and-the-fault-report)).

Temporary files: the object file of each patch, the extracted `.ipsw` folder and the emulator screen shot are in the temporary folder. The emulator socket is `/tmp/ipodfirm-<uid>.sock`.

### Files on the iPod volume

The app writes these files on the mounted iPod volume. A patch can also write files below `iPod_Control/` with the `actions` and `toggles` of its `ui` object (refer to [patch-system.md](patch-system.md#the-ui-object)). The app does not change any other file.

| Path | Writer | Reader |
|---|---|---|
| `iPod_Control/iTunes/iPodFirmAlbumArt` | "Write Thumbnails to iPod" | `album-art` patch |
| `iPod_Control/iTunes/IC-Info.sidb` | **Install Games** with a key file that the owner chose (a copy of the owner's own file; the app never makes it) | The iPod firmware (the games) |
| `iPod_Control/iTunes/iPodFirmAlbumCache` | The `album-art` patch on the iPod (version 2.8 and later), after it has all album covers in memory | `album-art` patch |
| `iPod_Control/iTunes/iPodFirmAlbumArtStats` | The `album-art` patch on the iPod, only in a measurement build (`ALBUM_ART_STATS` 1; off since version 3.2) | `re/album-art-stats.py` |
| `iPod_Control/Device/SysInfo` | iTunes or Finder. The app does not write it. | iPodFirm: three keys for a report (`IPodDisk.sysInfoReport`) |
| `iPod_Control/Device/Preferences` (only byte 0x8b) | A flash or restore of a firmware without `shuffle-album-mix`: Album Mix off. Refer to [safety.md](safety.md). | The iPod firmware (its settings) |
| `iPod_Control/iTunes/iPodFirmPlaylistArt/*.png` | "Choose Image…" in Playlist Artwork | iPodFirm (the next thumbnail file) |
| `iPod_Control/iTunes/iPodFirmDarkMode` | The `dark-mode` patch on the iPod | `dark-mode` patch |
| `iPod_Control/iTunes/iPodFirmLayout` | The `dark-mode` patch on the iPod (Settings > Split View, version 1.2 and later) | `dark-mode` patch. No file: Split |
| `iPod_Control/iTunes/iPodFirmPlaylistFolders` | "Write Folders to iPod" in Playlist Folders. The app removes the file if there are no folders and no custom order. | `playlist-folders` patch, the Playlist Folders section of the app |
| `iPod_Control/iTunes/iPodFirmHoldSelect` | The `up-next` patch on the iPod (Settings > Hold Select) | `up-next` and `cover-flow` patches |
| `iPod_Control/iTunes/iPodFirmPlaybackLog` | "Clear the Playback Log" (`ui.actions` of `playback-log`) | `playback-log` patch, "Show Playback Log", **Show Log** in the iPod pane |
| `iPod_Control/iTunes/iPodFirmDiagnosticLog` | "Clear the Diagnostic Log" (`ui.actions` of `diagnostic-log`) | `diagnostic-log` patch, "Show Diagnostic Log" |
| `iPod_Control/iTunes/iPodFirmUSBProbe`, `iPod_Control/iTunes/iPodFirmUSBLog` | "Start the Probe at the Next Restart" (`ui.actions` of `usb-host-probe`) | `usb-host-probe` patch, "Show USB Log", **Show Log** in the iPod pane |

The app reads `iPod_Control/iTunes/iTunesDB` and the music files. It does not change them. Before a flash, the app looks for the MiMusic temporary files `iTunesDB.tmp`, `ArtworkDB.tmp` and `iPodFirmAlbumArt.tmp`.

### Settings of the app

| `UserDefaults` key | Content |
|---|---|
| `acceptedDisclaimerVersion` | The version of the disclaimer that the user accepted. 0 or a value less than `Disclaimer.version` shows the disclaimer at the launch. |
| `enabledPatches` | The names of the switched-on patches. |
| `switchesChangedSinceSync` | True if the owner changed a switch, an option or the appearance after the last flash, restore or read of the iPod. Then a read does not change the switches. |
| `showTestPatches` | Settings > Patches > Enable Test Patches: true shows the test patches (category `test`). |
| `showPatchSummaries` | Settings > Patches > Show Descriptions in the Patch List: true shows the summary line of each patch row. The default is true. |
| `colourfulEQCurve` | Settings > Patches > Colourful EQ Curve. |
| `customEQs` | The named EQs of the patch `custom-eq`, as JSON. |
| `patchOptions` | The selected choice of each patch option: patch name → option `id` → value (refer to [patch-system.md](patch-system.md#options)). |
| `appearance` | `light`, `dark` or `switch`. |
| `darkTheme` | The name of the selected theme. |
| `customVersionOn`, `customVersion` | The custom version. |
| `versionLettersOn` | The patch letters on the About screen. |
| `checkForUpdates` | Settings > Updates > "Check for a new version at launch". The default is true. |
| `skippedUpdateVersion` | The release version that the user skipped with **Skip This Version**. The check at launch shows no notification for this version. iPodFirm > Check for Updates… ignores it. |
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
