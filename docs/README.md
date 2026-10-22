# iPodFirm technical reference

This reference tells how the iPodFirm app changes the Apple firmware of the iPod Video (5G and 5.5G). It records the formats, the patches, the firmware functions, the system calls and the safety limits. Use it to examine the work, to repeat it, or to write new patches.

All data is for Apple RetailOS 1.3 (`iPod_25.1.3.ipsw`). Other firmware versions have different addresses. iPodFirm refuses to apply a patch to a different version.

## Documents

| Document | Contents |
|---|---|
| [firmware-format.md](firmware-format.md) | The firmware partition, the image directory, the checksums, the osos memory map and the resource formats. |
| [patch-system.md](patch-system.md) | How iPodFirm compiles, links and installs a C patch. The `patch.json` format. How to write a new patch. |
| [modifications.md](modifications.md) | Each change that iPodFirm can make to the firmware: hooks, data formats, runtime logic and limits. |
| [ghidra-guide.md](ghidra-guide.md) | How to search the firmware with Ghidra: the set-up, the scripts, the search recipes, the procedure for an AI agent, the port to another firmware version and the support of another iPod model. |
| [firmware-functions.md](firmware-functions.md) | The Ghidra findings: the firmware functions, vtables, RAM addresses and resource IDs that are identified. The method and the scripts. |
| [app-and-device.md](app-and-device.md) | The app structure, the detection of the iPod, the privileged helper, and each external process, system API and network call. |
| [ipod-shuffle.md](ipod-shuffle.md) | A specification of the iPod shuffle (Songs and Albums), with code in C and Swift to copy it into a music player. It has no links to other files, so you can share it alone. |
| [porting.md](porting.md) | The parts that work only on macOS, the Swift and Python versions of each module, and a recommended path to a Windows or Linux version. |
| [translations.md](translations.md) | The iPod text that the patches add, and its translations. A guide for volunteer translators. |
| [safety.md](safety.md) | The protections before and during a flash, the backups, the recovery procedure, and the known problems. |
| [usb-c-power-mod.md](usb-c-power-mod.md) | A hardware design (not built) that lets the iPod supply 5 V to USB-C headphones: a USB-C dual-role controller, a 5 V boost converter and a load switch. It has no links to other files, so you can share it alone. |
| [../USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md) | The plan and the status of USB-C audio out: the USB host stack, the missing isochronous support, the stages and the gates. |

The research notes in [../re/](../re/) record the experiments in the sequence that they occurred. This reference collects their results. When the two do not agree, the source code is correct.

The note [../re/games-plans.md](../re/games-plans.md) gives three plans for the iPod games. The note [../re/games-keys.md](../re/games-keys.md) gives the deep research of the file of the keys and the program of the games. The note [../re/games-real-ipod.md](../re/games-real-ipod.md) gives the research with a real iPod: the signature of the manifest, the name of the folder of a game and the file of the keys. The note [../re/games-drm.md](../re/games-drm.md) gives the full research of the check of the DRM in the firmware. The note [../re/games-vm.md](../re/games-vm.md) gives the research of the virtual machine of the community that installs the games on an iPod. The note [../re/retailos-decompile.md](../re/retailos-decompile.md) gives the decompilation of the whole image `osos` of RetailOS 1.3. The note [../re/firmware-coverage.md](../re/firmware-coverage.md) gives the index of all the research. The note gives the state of the research for each part of the firmware and the limits of the names. The note [../re/firmware-systems.md](../re/firmware-systems.md) gives the systems and the sub-systems of the firmware. The note has the 7 systems, the 21 tasks of the firmware and the 222 tables of the classes. The note [../re/firmware-task-system.md](../re/firmware-task-system.md) gives the kernel of the firmware. The kernel is ThreadX. The note gives the base class of the tasks, the object of a task and the scheduler. The note [../re/firmware-camera.md](../re/firmware-camera.md) gives the camera of the iPod Video. The iPod Video has no camera. The firmware has the code of the camera of the iPod Photo. The note gives the class drivers of the USB host stack and the task of the camera. The note [../re/firmware-usb.md](../re/firmware-usb.md) gives the USB of the iPod Video. The note gives the mode manager, the stack of the device, the identity of the iPod and the protocol of the accessory. The note [../re/firmware-ui.md](../re/firmware-ui.md) gives the user interface of the iPod Video. The note gives the resources of the screens, the classes of the screens and the elements of a screen. The note [../re/firmware-power.md](../re/firmware-power.md) gives the power of the iPod Video. The note gives the 8 tasks, the registers of the power chip and the clock. The note [../re/firmware-media.md](../re/firmware-media.md) gives the music and the video of the iPod Video. The note gives the 7 tasks, the caches and the video processor of Broadcom. The note [../re/firmware-storage.md](../re/firmware-storage.md) gives the storage of the iPod Video. The note gives the 7 tasks, the bus of the disk and the 4 file systems. The note [../re/firmware-filesystems.md](../re/firmware-filesystems.md) gives the code of the file systems. The note gives the code of the FAT, the code of the HFS+ and the table of the partitions. The note [../re/firmware-modules.md](../re/firmware-modules.md) gives the table of the modules of the screen. The note [../re/games.md](../re/games.md) gives the research that the plans use.

## Where to start

- To know if a flash is safe, read [safety.md](safety.md) first.
- To write a new patch, read [firmware-format.md](firmware-format.md), then [patch-system.md](patch-system.md), then [firmware-functions.md](firmware-functions.md).
- To search the firmware, to port a patch or to add a model, read [ghidra-guide.md](ghidra-guide.md).
- To know what one patch does, read its section in [modifications.md](modifications.md).
- To know which programs and permissions the app uses, read [app-and-device.md](app-and-device.md).
- To port the app to Windows or Linux, read [porting.md](porting.md).
- To translate the iPod text of the patches, read [translations.md](translations.md).

## Keep the reference current

Each change to the code must update the documents that it affects, in the same commit. A change is not complete until the documents agree with the code. Write all text in ASD-STE100 Simplified Technical English. [CLAUDE.md](../CLAUDE.md) gives the rules.

Use this table to find the documents to update:

| When you change | Update |
|---|---|
| A patch: `patches/*/patch.json` or its C file | Increase the `version` in `patch.json`. Measure the code again and update `size` in `patch.json` (the test `testPatchSizes` gives the value). [modifications.md](modifications.md) (hooks, size, logic, test status), [patch-system.md](patch-system.md) (free space table), [firmware-format.md](firmware-format.md) (osos memory map), [firmware-functions.md](firmware-functions.md) (new firmware addresses), [safety.md](safety.md) (test status) |
| A text that a patch shows on the iPod | [translations.md](translations.md) (the text table, the template and the status table) |
| A new patch | All of the above, and the summary table in [modifications.md](modifications.md). Give it a `version_letter`, a `version` and a `size`. |
| `Patcher.swift` or `patcher.py` | [patch-system.md](patch-system.md) |
| `Partition.swift`, `Resources.swift`, `Pictures.swift` or their Python versions | [firmware-format.md](firmware-format.md) |
| `ThemeImport.swift`, `DarkMode.swift`, `FirmwareVersion.swift`, `AlbumArt.swift`, `ArtworkDB.swift`, `MusicImport.swift` | [modifications.md](modifications.md) |
| `Device.swift`, `Operations.swift`, the helper or `Privileged.swift` | [safety.md](safety.md), [app-and-device.md](app-and-device.md) |
| A new external program, system API, network connection, file or `UserDefaults` key | [app-and-device.md](app-and-device.md). If the item works only on macOS, also [porting.md](porting.md). |
| A new Swift module in `IPodFWKit`, a new Python module, or a module that gets its first version in the other language | [porting.md](porting.md) (section 2) |
| A new pane, button or app function | [app-and-device.md](app-and-device.md), [../README.md](../README.md) |
| `build-app.sh`, `install-emulator.sh` or the emulator patch | [app-and-device.md](app-and-device.md), [../re/emulator.md](../re/emulator.md) |
| A new Ghidra or emulator result | The note in [../re/](../re/), then [firmware-functions.md](firmware-functions.md) |
| `re/collect-ipod-info.sh`, `re/collect-ipod-info.ps1` or their page template | Run `python3 re/build-collect-page.py` to build `re/collect-ipod-info.html` again (the test `tests/test_collect_page.py` checks it). Update [../re/ipod-classic-6g.md](../re/ipod-classic-6g.md#data-from-a-real-ipod-classic). |
| A script in `re/ghidra-scripts/` or `re/find-pattern.py` | [ghidra-guide.md](ghidra-guide.md) (section 2 and the recipes), [firmware-functions.md](firmware-functions.md) (the tools table) |
| A hook site of a patch | The appendix of [ghidra-guide.md](ghidra-guide.md): make the signature again with `MakeSignature.java` |
| A test on the real iPod | [safety.md](safety.md) (test status), [modifications.md](modifications.md) (test status), the note in [../re/](../re/) |

To find the size of a compiled patch, run `swift test --filter testPatchSizes` in `mac/`. A wrong `size` gives a failure with the measured value. Do not estimate the size.

## The address rule

All addresses in this reference are offsets in the osos image, unless the text says something different. The CPU address of the code is the same value. Thus, in Ghidra, load `osos` with the base address 0x0. Then a Ghidra address is equal to the osos offset and to the patch address.

The physical SDRAM address is 0x10000000 + the osos offset. The `addr` field of the osos directory entry gives this value. Use the physical address for the emulator `peek` command. RetailOS also uses it for some RAM pointers above the image, for example 0x1081da18.

## Glossary

| Term | Meaning |
|---|---|
| RetailOS | The Apple operating system of the iPod. It is in the osos image. |
| Firmware partition | The first partition of the iPod disk. It holds the image directory and the firmware images. |
| osos | The image that holds the ARM code of RetailOS and the UI resources. The boot loader loads it into SDRAM. |
| rsrc | The image that holds a FAT16 file system with the fonts and the programs for the Broadcom video processor. |
| aupd | The encrypted boot-flash updater. It can write the NOR flash. iPodFirm never writes it. |
| hibe | The hibernation image. The iPod writes its RAM state to it. iPodFirm never writes it. |
| osbk | A backup copy of osos. The 5.5G with firmware 1.3 does not have it. |
| devOffset | The start of an image, relative to the image base of the partition. |
| Image base | The offset of the image area in the partition. It is 2048 bytes on the 5.5G. |
| Load address | The osos offset where the patch code goes. |
| Hook | A change to one 32-bit word of the firmware that sends the CPU into the patch code. |
| vtable slot | One word in a table of method addresses of a class. A `word` hook replaces it. |
| Resource | An item in a resource block of osos, for example `BMap 24342`. |
| BMap | A picture resource. |
| View | A layout resource. It lists the elements of a screen or a part of a screen. |
| Type | A text style resource: the font, the size and the colours. |
| Menu | A menu resource. Each item has a label ID and a key. |
| TCmd | A resource with the compiled JavaScript of the user interface. |
| Flash | The write of a new firmware partition to the iPod. |
| Backup | A copy of the complete firmware partition of the iPod, in a `.bin` file. |
