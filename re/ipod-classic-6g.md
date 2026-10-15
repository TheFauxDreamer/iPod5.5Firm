# iPod classic 6G: firmware 1.1.2

This note records the examination of the last Apple firmware for the iPod classic 6th generation. The question was: can iPodFirm and the Ghidra method of this project change this firmware?

## Result

Not with the method of this project. The program image (osos) of the iPod classic is encrypted and signed. The pictures, the texts, the layouts and the code of the user interface are in this image. Ghidra cannot analyze the file, and iPodFirm cannot make a changed image that the iPod accepts.

The RepriseOS projects change the classic 6.5G and 7G firmware with a BootROM exploit and a NOR bootloader. Refer to [RepriseOS](#repriseos-a-working-method-for-later-classic-models). They do not support the original 6G of this file.

| Question | Answer | Evidence |
|---|---|---|
| Is osos plain ARM code? | No | Entropy 7.986–7.998 bits per byte in each 64 KB block. 22 function starts, the same count as random data. |
| Is osos signed? | Yes | An X.509 chain at the end: Apple Root CA → Apple iPod Certification Authority → "S5L8702 Secure Boot". A valid RSA-1024 PKCS#1 signature with SHA-1. |
| Did Apple sign the encrypted bytes? | No | The signed SHA-1 is not the SHA-1 of the encrypted body or of 264 other ranges. Thus Apple signed the decrypted code. |
| Is the decryption key in the file? | No | The S5L8702 header has no key. The RepriseOS documents say that the AES engine of the CPU has the key (GKEY). Refer to [RepriseOS](#repriseos-a-working-method-for-later-classic-models). |
| Do the 1.3 signatures match? | No | 0 matches for the hook signatures and for `text:portalplayer`. The CPU is a Samsung S5L8702, not a PortalPlayer. |
| Can iPodFirm read the directory? | No | `ipodfw info` gives "no osos image in directory". |
| Is anything plain? | Yes, `rsrc` | A FAT16 file system with fonts, games, voices and trainer templates. Its byte-sum checksum is correct. |

The examination used only the public key in the certificate chain. It did not try to break the encryption or the signature.

## The file

| Item | Value |
|---|---|
| File | `iPod_24.1.1.2.ipsw`, 92,930,720 bytes |
| SHA-256 | `e753abfb11aaeaa6fd1d7257e87f4e53b6b5d923b1de0e4c9c63c30e0dac9d1a` |
| Firmware file | `Firmware-24.9.1.2`, 92,930,048 bytes, dated 27 April 2008 |
| `VisibleBuildID` | 17989632 = 0x01128000 (version 1.1.2) |
| `FamilyID`, `UpdaterFamilyID` | 11, 24 |

The file was deleted from the repository after the examination (6 October 2026). It was never committed.

## The partition format

The STOP banner and the `]ih[` header are the same as on the iPod Video. The other parts are different.

| Item | iPod Video 1.3 | iPod classic 1.1.2 |
|---|---|---|
| Directory offset at 0x104 | 0x4000 | 0x4000 |
| Directory position | 0x4000 + 0x200 = 0x4200 | 0x4000 + 0x1000 = 0x5000 |
| Sector size (inferred) | 512 | 4096 |
| Image base | 0x800 | 0x1000 (from the correct rsrc checksum) |
| Images in the directory | osos, rsrc, aupd (and hibe on the iPod) | rsrc, osos, aupd, hash |
| osos checksum | Byte sum | 0 (not used) |
| osos `addr` | 0x10000000 | 0x08000000 |
| osos `vers` | 0xB0xx (model 0xB0) | 0x13000 (model 0x130 if read the same way) |
| FAT16 in rsrc | At 0x600 | At 0xe00 (also in the `entryOffset` field) |

The directory of the classic:

| Image | devOffset | Length | Checksum |
|---|---|---|---|
| rsrc | 0x6000 | 0x4e00000 | 0x319dad9f (byte sum, correct) |
| osos | 0x4e07000 | 0x9773e3 | 0 |
| aupd | 0x5780000 | 0x11c8b3 | 0 |
| hash | 0x589e000 | 0x1000 | 0xff000 (all bytes 0xFF) |

The rule "directory = value + one sector" agrees with RetailOS on the iPod Video (function 0xc60ec). Refer to [dark-theme.md](dark-theme.md#how-retailos-finds-rsrc-ghidra).

## The S5L8702 image header

osos and aupd start with a header of 0x800 bytes at devOffset. The body starts at devOffset + 0x800.

| Offset | osos | aupd | Content |
|---|---|---|---|
| +0x00 | `8702` | `8702` | Magic: the CPU |
| +0x04 | `1.0` | `1.0` | Format version |
| +0x07 | 3 | 3 | Image type. 3 agrees with "encrypted and signed". |
| +0x0c | 0x976f7c | 0x11c444 | Length of the body |
| +0x10 | 0x977be3 | 0x11d0b3 | Length of the body, the signature and the chain |
| +0x14 | 0x977000 | 0x11c4d0 | Offset of the certificate chain from the body start |
| +0x18 | 0xbe3 | 0xbe3 | Length of the chain (1215 + 1013 + 815 = 3043 bytes) |
| +0x40 | 20 bytes | 20 bytes | Probably a header signature (the length of SHA-1). Encrypted. |

After the body:

1. The RSA signature, 128 bytes, directly before the chain.
2. The certificate chain:

| Certificate | Subject | Key | Valid |
|---|---|---|---|
| 0 | Apple Root CA | RSA 2048 | 2006–2035 |
| 1 | Apple iPod Certification Authority | RSA 2048 | 2007–2022 |
| 2 | S5L8702 Secure Boot (OU Apple iPod) | RSA 1024 | 2007–2015 |

The public key of certificate 2 decrypts the signature to a valid PKCS#1 v1.5 block with a SHA-1 DigestInfo:

| Image | Signed SHA-1 | SHA-1 of the encrypted body |
|---|---|---|
| osos | `a0f7f00abecd367146fbfd8b91987cad4d3730e0` | `f4121e9fbe8185f91d38ec02255e01b11e4ff18f` |
| aupd | `88f28b7954b0f1664274dbe0d36b22da4a219eee` | `7ca9f0e80b374907cec2923e2892d051cf3f3892` |

## The tests

| Test | iPod Video 1.3 osos | iPod classic osos body |
|---|---|---|
| Entropy (64 KB blocks) | Below 8 | 7.986–7.998 |
| `push {..., lr}` words | 12,887 (0.68 %) | 22 (random data: 18.9) |
| Repeated 16-byte blocks | — | 0 (not AES-ECB with a fixed key on plain code) |
| Signature 0x284c7c (`flash-keep-awake`) | 1 match | 0 matches |
| Signature 0x1bb260 (`album-art`) | 1 match | 0 matches |
| `text:portalplayer` | 1 match | 0 matches |

No Ghidra import was made. The data has no instructions, so an analysis gives no result.

## The rsrc image

`rsrc` is not encrypted and not signed. No file in it has the certificate chain. It has 857 entries:

| Folder | Files | Size |
|---|---|---|
| `/Resources/Fonts` | 8 | 5.87 MB |
| `/Resources/Games` | 425 | 60.40 MB |
| `/Resources/TrainerTemplates` | 33 | 0.13 MB |
| `/Resources/Voices` | 291 | 13.36 MB |

The fonts are `CJK11.ttf`, `CJK16.ttf`, `Helvetica.ttf`, `HelveticaBold.ttf` and four `MonoHope` `.sbit` fonts. Three game programs (`*.bin` in `Games/games_RO/*/Executables/`) have high entropy, so they are probably encrypted.

It is not known if the iPod accepts a changed `rsrc`. The `hash` image (4096 bytes, all 0xFF in the file) possibly holds a hash that the iPod writes or examines. Only a test on a real iPod classic can answer this. iPodFirm does not support it.

## Detection in iPodFirm (fixed on 6 October 2026)

Before the fix, iPodFirm could not read the classic directory. A flash then stopped with "The firmware on the iPod is damaged. Use the rescue restore." The rescue restore refused, so no write occurred. But the message was wrong.

The fix:

- `FirmwarePartition.samsungImageHeader` (Swift) and `samsung_image_header` (Python) identify the Samsung layout. They need all of these conditions:
  - the STOP banner and `]ih[` are correct;
  - no directory is at the value at 0x104 + 0x200;
  - a directory is at the value at 0x104 + 0x1000, with an osos entry.
- The result is the tag of the osos image header (for example `8702`), or "unknown" if the header is not readable.
- `Operations.checkModel` runs this test first. Backup, flash and rescue restore then stop with the code `unsupported-ipod`. The iPod pane shows "Unsupported iPod" and disables the back-up, flash and restore buttons.
- An opened classic file gives a clear message: "This firmware is for an iPod classic or an iPod nano 3G or later … encrypted and signed". This error has no code. A code would mark the connected iPod as unsupported.
- The Python rescue restore refuses a classic.

The tests use a synthetic partition with the layout above. The real file confirmed the layout before it was deleted.

The detection of the iPod nano 3G and later is not tested. These models also have Samsung CPUs, but their layout was not examined.

## Data from a real iPod classic

The `.ipsw` file does not answer these questions. Only a real iPod classic can answer them:

- The layout of the firmware partition on the disk, and the sector size that macOS reports.
- The content of the `hash` image after the iPod wrote it. In the `.ipsw` file, all bytes are 0xFF.
- A test of the classic detection of iPodFirm with a real partition.
- The USB product ID and the device files (`SysInfoExtended`) of each generation.

[collect-ipod-info.sh](collect-ipod-info.sh) (macOS) and [collect-ipod-info.ps1](collect-ipod-info.ps1) (Windows 10 and 11) collect this data from a connected iPod into one ZIP file. The two scripts collect the same files. They only read the iPod. It copies the firmware partition, the first block of the disk, the files in `iPod_Control/Device`, the folder names in `iPod_Control`, and the `diskutil` and `ioreg` output. With `--library`, it also copies `iPod_Control/iTunes`. It never copies music, photos or videos.

The instructions for iPod owners are one self-contained HTML file: [collect-ipod-info.html](collect-ipod-info.html). It contains a copy of each script, a button that copies each script, and the steps for macOS and for Windows. Send the HTML file to the iPod owner. The file needs no internet connection.

Do not edit the HTML file. Edit a script or [collect-ipod-info.template.html](collect-ipod-info.template.html), then run `python3 re/build-collect-page.py`. The test `tests/test_collect_page.py` fails if the HTML file does not agree with the scripts.

The Windows script opens `\\.\PhysicalDriveN` with `CreateFile` and `GENERIC_READ` only. Windows PowerShell 5.1 (.NET Framework) does not open a `\\.\` path with a normal `FileStream`. The script writes the ZIP entries itself with `/`, because `Compress-Archive` in PowerShell 5.1 writes `\`.

The test of the script (6 October 2026) used disk images in test mode (`IPOD_TEST_IMAGE`):

| Image | Result |
|---|---|
| MBR with the classic layout | The copied partition has the `8702` header. `samsung_image_header` identifies it. |
| APM with the iPod Video layout | The copied partition is byte for byte the same as the original. |
| A volume with music, artwork and a library | The ZIP has only the device files and the folder names. With `--library`, it also has `iTunesDB`. |

Both scripts read Windows-formatted iPods (MBR) and Mac-formatted iPods (APM). On Windows, a Mac-formatted iPod has no drive letter, so the device files are not copied. The firmware partition is copied.

The partition table gives sectors. Some iPods report a block size that is not the unit of their partition table. Thus both scripts (version 2) try the reported block size, then 512, 2048 and 4096 bytes. They use the first unit where the partition starts with the STOP banner, and record it in `info.txt` ("sector unit"). If no unit matches, they use the reported block size and show a warning. A partition that does not start on a block boundary is read in whole blocks and then cut. iPodFirm uses the same unit search for an MBR (`FirmwareFlasher.mbrSectorUnit`). Refer to [firmware-format.md](../docs/firmware-format.md#the-mbr-sector-unit).

Both scripts (version 3) have hard limits for the deletion of their temporary files. They never delete recursively:

| Limit | macOS | Windows |
|---|---|---|
| The temporary folder of the system | Must be an absolute path, not `/`, and must exist. | Must not be empty, a drive root (for example `C:\`) or a network share root. |
| The work folder | New, from `mktemp -d`, with the name pattern `ipod-info.XXXXXXXX`. | New, with a random GUID name. It must not exist before. |
| The user | The script refuses to run as root. It uses `sudo` only for the reads of the raw disk. | Administrator rights are necessary for the raw disk. |
| The files to delete | Each file in `MANIFEST.txt`: a regular file, not a link, with a real folder inside the work folder. | Each file that the script lists itself: no junctions and no links, with a full path inside the work folder. |
| The folders | `rmdir`, which removes only an empty folder. | `Directory.Delete(path, false)`, which removes only an empty folder. |
| Anything else | Stays. The script shows the path. | Stays. The script shows the path. |

The library copy (`--library`) uses the same rule: regular files only, no links and no `._*` files. Windows PowerShell 5.1 can follow a junction in a recursive `Get-ChildItem`, `Copy-Item` or `Remove-Item`. Thus the Windows script uses its own list function (`Get-OwnFiles`) for the copy, the manifest, the ZIP and the deletion.

Tests of version 3 (6 October 2026): a library folder with a link to a file and a link to a folder outside the test. Both scripts copied only the real file, and the files that the links point to did not change. With `TMPDIR=/`, a relative `TMPDIR` or a missing folder, the macOS script stopped before it wrote anything. With `TMPDIR=/`, the Windows script (PowerShell 7 on macOS) also stopped. The refusal to run as root is not tested.

Tests of version 2 (both scripts, 6 October 2026): the MBR values in 512-byte units with a reported block of 512 and of 2048 bytes, the MBR values in 2048-byte units with a reported block of 512 bytes, a partition without the STOP banner, and the APM image. Each run gave the expected partition, and both scripts gave the same bytes. No temporary folder was left. With a temporary folder that does not exist, the macOS script stopped with an error.

The Windows script ran the same tests in PowerShell 7.6 on macOS. Its output files were byte for byte the same as the output of the macOS script. Its C# part compiles, and the script parses without errors.

Not tested: the real path with a connected iPod. On macOS, that is `diskutil` and `sudo`. On Windows, that is `Get-Disk`, `CreateFile`, the administrator check, and Windows PowerShell 5.1. The first result from an iPod owner is that test.

## RepriseOS: a working method for later classic models

Two public projects change the Apple firmware of the iPod classic. This project read their documents on 6 October 2026. It did not run or verify them.

- [lgreitis/osos-lab](https://github.com/lgreitis/osos-lab): the patches, the reverse engineering and the build tools of "RepriseOS". GPL-3.0.
- [lgreitis/repriseos-installer](https://github.com/lgreitis/repriseos-installer): a desktop installer (Tauri). GPL-3.0.

### The method

1. The installer puts the iPod in DFU mode. It uses the BootROM exploit of [wInd3x](https://github.com/freemyipod/wInd3x) (freemyipod) to run its own code.
2. With this code, the CPU decrypts the firmware with its own AES engine (key selector GKEY for osos). The key never leaves the CPU.
3. The installer backs up the NOR flash and SysCfg. Then it writes a patched Rockbox bootloader into the NOR flash.
4. It copies a decrypted, patched osos (`/osos-cfw.bin`) and a companion loader (`/cfw-loader.bin`) to the disk. The disk must be FAT32.
5. At start, the bootloader selects the system: no button = RepriseOS, Menu = Apple firmware, Play/Pause = Rockbox.
6. For RepriseOS, the companion runs Apple's own start code (PreEfi, DXE drivers). It stops before the normal image selection and gives the decrypted osos to the Apple image loader as a file in RAM. Their documents say that the normal boot path does not accept a decrypted image automatically. This step is their solution.

### The facts in their documents

| Item | Value (classic 7G, firmware 2.0.4, unless stated) |
|---|---|
| CPU core | ARM926EJ-S (ARMv5TEJ), not ARM7TDMI |
| NOR | 1 MB. The primary image is at 0x8000, with a 0x800-byte header and an encrypted body of 0x1f800 bytes. The body holds an EFI firmware volume with 40 PE32 drivers. |
| BootROM processing | Mode 1 (NOR): type 1 uses UKEY, type 2 has no AES. Mode 2 (osos): type 3 uses GKEY, type 4 has no AES. The signature check stays in each mode. |
| osos | An IMG1 header of 0x800 bytes. The body runs at 0x08000000 after a relocation. Main code: address = file offset + 0x07ff4928. |
| The CFW payload | 1 MB at 0x08b33000. The patch moves the heap start to 0x08c33000. |
| Resources | osos mounts `rsrc` as volume 4. The fonts are in `Resources/Fonts`. |

The type 3 in this table agrees with the byte 3 at +0x07 of the 1.1.2 header in this note.

### The limits for this project

- **The model.** RepriseOS supports the classic 6.5G (MB562, MB565, firmware 2.0.1) and 7G (MC293, MC297, firmware 2.0.4). The file of this note is for the original 6G (2007, firmware 1.1.2, `UpdaterFamilyID` 24). The 6.5G file has `UpdaterFamilyID` 33. RepriseOS does not support the original 6G.
- **The NOR flash.** The method writes the NOR flash. iPodFirm never writes the NOR flash, because the NOR flash holds the recovery path of the iPod Video. Refer to [docs/safety.md](../docs/safety.md#the-boundaries). For the classic, DFU mode in the BootROM is the recovery path, but this project did not examine it.
- **The license.** Both projects are GPL-3.0. iPodFirm is GPL-2.0-or-later. Code that is copied from them makes the combined work GPL-3.0. Use their documents as references, or ask the owner before you copy code.
- **The architecture.** The classic firmware is a different code base: EFI drivers in the NOR flash, a relocated osos and a different CPU. The addresses, the hooks and the patches of iPodFirm do not apply.

### What can help this project

- Their method to keep the Ghidra analysis in Git without Apple code: they export the annotations as JSON lines (`ghidra/analysis/`) and import them again into a new project. This project keeps its Ghidra project only on the Mac of the owner.
- Their patch list gives ideas for the iPod Video: the EU volume limit, Play Next, a custom EQ and the debug menu. The EU volume limit now has a patch for the iPod Video: refer to [volume-limit.md](volume-limit.md).
- Their approach to a decrypted firmware is a model if the owner wants classic support in the future. That work is a separate project.

## Recommendation

- Do not add iPod classic support to iPodFirm. The classic needs a BootROM exploit and a NOR write, and these are outside the safety limits of iPodFirm.
- For an iPod classic 6.5G or 7G, refer the owner to RepriseOS.
- For the original classic 6G, this project knows of no tool that changes the Apple firmware.
- If the owner wants to examine `rsrc` changes, first find what the `hash` image does. A test of that needs a real iPod classic and a way to recover it.
