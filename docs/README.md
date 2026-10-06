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
| [safety.md](safety.md) | The protections before and during a flash, the backups, the recovery procedure, and the known problems. |
| [../USB-AUDIO-OUT.md](../USB-AUDIO-OUT.md) | The plan and the status of USB-C audio out: the USB host stack, the missing isochronous support, the stages and the gates. |

The research notes in [../re/](../re/) record the experiments in the sequence that they occurred. This reference collects their results. When the two do not agree, the source code is correct.

## Where to start

- To know if a flash is safe, read [safety.md](safety.md) first.
- To write a new patch, read [firmware-format.md](firmware-format.md), then [patch-system.md](patch-system.md), then [firmware-functions.md](firmware-functions.md).
- To search the firmware, to port a patch or to add a model, read [ghidra-guide.md](ghidra-guide.md).
- To know what one patch does, read its section in [modifications.md](modifications.md).
- To know which programs and permissions the app uses, read [app-and-device.md](app-and-device.md).

## Keep the reference current

Each change to the code must update the documents that it affects, in the same commit. A change is not complete until the documents agree with the code. Write all text in ASD-STE100 Simplified Technical English. [CLAUDE.md](../CLAUDE.md) gives the rules.

Use this table to find the documents to update:

| When you change | Update |
|---|---|
| A patch: `patches/*/patch.json` or its C file | [modifications.md](modifications.md) (hooks, size, logic, test status), [patch-system.md](patch-system.md) (free space table), [firmware-format.md](firmware-format.md) (osos memory map), [firmware-functions.md](firmware-functions.md) (new firmware addresses), [safety.md](safety.md) (test status) |
| A new patch | All of the above, and the summary table in [modifications.md](modifications.md). Give it a `version_letter`. |
| `Patcher.swift` or `patcher.py` | [patch-system.md](patch-system.md) |
| `Partition.swift`, `Resources.swift`, `Pictures.swift` or their Python versions | [firmware-format.md](firmware-format.md) |
| `ThemeImport.swift`, `DarkMode.swift`, `FirmwareVersion.swift`, `AlbumArt.swift`, `ArtworkDB.swift`, `MusicImport.swift` | [modifications.md](modifications.md) |
| `Device.swift`, `Operations.swift`, the helper or `Privileged.swift` | [safety.md](safety.md), [app-and-device.md](app-and-device.md) |
| A new external program, system API, network connection, file or `UserDefaults` key | [app-and-device.md](app-and-device.md) |
| A new pane, button or app function | [app-and-device.md](app-and-device.md), [../README.md](../README.md) |
| `build-app.sh`, `install-emulator.sh` or the emulator patch | [app-and-device.md](app-and-device.md), [../re/emulator.md](../re/emulator.md) |
| A new Ghidra or emulator result | The note in [../re/](../re/), then [firmware-functions.md](firmware-functions.md) |
| `re/collect-ipod-info.sh`, `re/collect-ipod-info.ps1` or their page template | Run `python3 re/build-collect-page.py` to build `re/collect-ipod-info.html` again (the test `tests/test_collect_page.py` checks it). Update [../re/ipod-classic-6g.md](../re/ipod-classic-6g.md#data-from-a-real-ipod-classic). |
| A script in `re/ghidra-scripts/` or `re/find-pattern.py` | [ghidra-guide.md](ghidra-guide.md) (section 2 and the recipes), [firmware-functions.md](firmware-functions.md) (the tools table) |
| A hook site of a patch | The appendix of [ghidra-guide.md](ghidra-guide.md): make the signature again with `MakeSignature.java` |
| A test on the real iPod | [safety.md](safety.md) (test status), [modifications.md](modifications.md) (test status), the note in [../re/](../re/) |

To find the size of a compiled patch, build it with `uv run ipodfw` or examine the result of `Patcher.link`. Do not estimate the size.

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
