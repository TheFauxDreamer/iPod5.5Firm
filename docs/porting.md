# Port to Windows and Linux

This document tells which parts of iPodFirm work only on macOS. It also gives a recommended path to a Windows or Linux version. No port work has started. This document is research only.

## 1. Languages and sizes

The table gives the number of lines in the files that git tracks on `main` (commit of 2026-10-16). To measure the values again in a clean worktree, use `git ls-files "<folder>/*.<ext>" | xargs cat | wc -l`.

| Part | Folder | Language | Lines | Runs on Windows or Linux |
|---|---|---|---|---|
| App user interface | `mac/Sources/iPodFirm` | Swift (SwiftUI, AppKit) | 3733 | No. SwiftUI and AppKit are for Apple systems only. |
| Privileged helper | `mac/Sources/ipodfw-helper` | Swift (XPC, launchd) | 161 | No. |
| Core library | `mac/Sources/IPodFWKit` | Swift | 4564 | Partly. Swift runs on Windows and Linux, but the library uses Apple frameworks (section 3). |
| Swift tests | `mac/Tests` | Swift | 1540 | Partly, the same as the core library. |
| `ipodfw` command-line tool | `src/ipodfw` | Python | 3239 | Mostly. The device code is for macOS only (section 3). |
| Python tests | `tests` | Python | 932 | Yes. |
| Patches | `patches/*/*.c` | C | 4841 | Yes. The code runs on the iPod. The compiler (clang) runs on all three systems. |
| Ghidra scripts | `re/ghidra-scripts` | Java | 523 | Yes. |

Thus, about 8,500 lines of the app are in Swift. The UI and the helper (about 3,900 lines) must be written again for a different system. Most of the logic in the core library also has a Python version.

## 2. Swift modules and their Python versions

| Swift module (`IPodFWKit`) | Python module (`src/ipodfw`) |
|---|---|
| `Partition.swift` | `partition.py` |
| `Resources.swift` | `resources.py`, `fat16.py` |
| `Pictures.swift` | `pictures.py` |
| `Editor.swift` | `theme.py` (`ipodfw unpack` and `ipodfw repack`) |
| `DarkMode.swift` | `darkmode.py` |
| `ThemeImport.swift` | `themeimport.py` |
| `Patcher.swift` (C compiler call and ELF linker) | `patcher.py` |
| `IPSW.swift` | `ipsw.py` |
| `ITunesDB.swift` | `itunesdb.py` |
| `ArtworkDB.swift` | `artworkdb.py` |
| `AlbumArt.swift` | `albumart.py` |
| `MusicImport.swift` | `libimport.py`, `mp4tags.py` |
| `Device.swift`, `Operations.swift` | `device.py`, `cli.py` (`devices`, `backup`, `flash`, `restore`) |
| `FirmwareVersion.swift` | None |
| `PatchLibrary.swift` (install and export of a `.ipodpatch` file) | None |
| `USBProbeLog.swift` | None |
| `VideoLog.swift` | None |
| `HelperXPC.swift` | None. The Python tool runs with `sudo`. |

The Python tool also has modules that the app does not have: `emucontrol.py` and `emudrive.py` for the emulator.

The Swift and Python versions of a module are two copies of the same logic. A change to one copy can make the two copies different. Shared test vectors (the same input file and the same expected output for the two test suites) can find this problem.

## 3. Dependencies on macOS

| Item | Where | Use | Replacement on Windows or Linux |
|---|---|---|---|
| `/usr/sbin/diskutil` and `/dev/rdiskN` | `Device.swift`, `device.py` | Find the iPod. Unmount and eject it. Read and write the firmware partition. | Linux: `/sys/block`, `lsblk`, `/dev/sdX`, `udisksctl`. Windows: `\\.\PhysicalDriveN`, the SetupAPI or WMI to find the disk, and a volume lock before the write. |
| Privileged helper: XPC, launchd, `SMAppService`, Security, LocalAuthentication | `HelperXPC.swift`, `mac/Sources/ipodfw-helper`, `HelperClient.swift`, `Privileged.swift` | Get root access to the raw disk. | Linux: polkit (`pkexec`) or a udev rule. Windows: a UAC elevation (the app runs as administrator). |
| `/usr/bin/ditto`, `/usr/bin/zip` | `IPSW.swift`, `PatchLibrary.swift` | Unpack an `.ipsw` file. Unpack and make a `.ipodpatch` file. | A zip library. `ipsw.py` already uses `zipfile`. |
| `/usr/bin/xcrun clang` | `Patcher.swift`, `PatchLibrary.swift` | Compile the C file of a patch. | `clang` from LLVM. `patcher.py` already calls `clang` without `xcrun`. An exported `.ipodpatch` file has a precompiled `patch.o`, so the user does not need a compiler for it. |
| `/usr/bin/afconvert` | `ITunesDB.swift`, `itunesdb.py` | Make the test audio file for an emulated library. | `ffmpeg`, or a short WAV or AAC file in the repository. |
| CoreGraphics, ImageIO, UniformTypeIdentifiers | `Pictures.swift`, `AlbumArt.swift`, `ArtworkDB.swift`, `ITunesDB.swift`, `MusicImport.swift` | Decode, resize and encode images. | Pillow. The Python modules already use it. |
| AVFoundation | `MusicImport.swift` | Read the cover art of an MP3 file and of other formats. | A tag library, for example `mutagen`. `mp4tags.py` reads only MP4 tags. |
| CryptoKit | `Patcher.swift`, `Editor.swift`, `Operations.swift`, `ThemeImport.swift` | SHA-256 values. | `hashlib`. For Swift: `swift-crypto`. |
| SwiftUI, AppKit | `mac/Sources/iPodFirm` | The full user interface. | A new UI (section 4). |

## 4. Recommended path

Use the Python package as the shared engine for Windows and Linux. It already has most of the format logic, the patcher and tests. A port of the Swift library must replace the same frameworks, and it still needs a new UI.

Do these tasks in this sequence:

1. Add the Python versions of the modules that only Swift has: `FirmwareVersion`, `PatchLibrary`, `USBProbeLog` and `VideoLog`.
2. Add cover art for MP3 files and other formats to `libimport.py`.
3. Add device code for Linux and for Windows to `device.py`. Keep the checks in [The checks before a flash](safety.md#the-checks-before-a-flash).
4. Write a UI that runs on the three systems, for example with PySide6 (Qt). Each feature must have a UI. A command-line tool alone is not sufficient.
5. Add shared test vectors, so that the Swift and Python versions give the same output.

CAUTION: A write to the wrong disk can destroy data on the computer. On each new system, test the detection of the iPod with a read-only command before a flash.

Test a flash on Windows or Linux with a backup first. Use the procedure in [Recovery](safety.md#recovery) if the iPod does not start.
