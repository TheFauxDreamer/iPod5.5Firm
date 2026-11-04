# Dark Mode switch table: compression

## Goal

The appearance "Switch on iPod" puts a switch table after the end of osos. With a large theme, the table uses most of the space below 0x7F0000 (`ThemeImport.ososLimit`). Then little space stays for extended patches. This note measures how much a compressed table can save. Since `dark-mode` 1.3 (4 November 2026, branch `dark-table-ifd2`), the app uses the IFD2 table of the section [A table from the light pictures](#a-table-from-the-light-pictures-3-november-2026).

## Method

The script [measure-switch-table.py](measure-switch-table.py) builds "Switch on iPod" with `src/ipodfw/darkmode.py`. Then it compresses the change data with each method. It writes no file.

```
.venv/bin/python re/measure-switch-table.py iPod_25.1.3.ipsw "Dark Gray.ipodtheme"
```

The test of 9 October 2026 used firmware 1.3 and the "Dark Gray" theme of the owner.

- LZ4 is a simple greedy compressor in the script. The script decodes the output again and compares it with the input. A real LZ4 HC compressor gives a smaller result.
- deflate, bzip2 and LZMA come from the Python standard library.

## The table without compression

| Item | Value |
|---|---|
| Changes in the table | 4720 (0 left out) |
| Table | 0x73fe20, 698,443 bytes |
| – index ({address, length} for each change) | 37,760 bytes |
| – data (old XOR new) | 660,671 bytes |
| Settings menu | 0x7ea670 |
| Patch code | 0x7ea970–0x7ead21 |
| End of osos | 0x7eb000 |
| Free space below 0x7F0000 | 20,480 bytes |

The theme pictures that do not fit in their old places come before the table (0x736800–0x73fe20).

| Resource type | Changes | Bytes |
|---|---|---|
| BMap | 3148 | 645,624 |
| View | 1551 | 14,963 |
| Type | 21 | 84 |

The pictures are 98% of the data.

## Results

Two kinds of data were compressed:

- **XOR data**: the data of the table now (old XOR new).
- **Dark bytes**: the new bytes of the theme.

| Method | XOR data | Dark bytes |
|---|---|---|
| None | 660,671 | 660,671 |
| Zero-run RLE | 644,808 (1.02×) | 656,903 (1.01×) |
| PackBits RLE | 641,992 (1.03×) | 619,204 (1.07×) |
| LZ4 (greedy) | 227,107 (2.91×) | 190,677 (3.46×) |
| deflate -9 | 126,410 (5.23×) | 106,647 (6.19×) |
| bzip2 -9 | 118,556 (5.57×) | 91,758 (7.20×) |
| LZMA -9e | 93,180 (7.09×) | 74,968 (8.81×) |

The index gets smaller if each address is the distance from the end of the previous change, written as a varint. Then the index is 10,574 bytes (4,053 bytes with deflate).

The complete table (header, varint index and compressed data):

| Table | Size | Free space below 0x7F0000 |
|---|---|---|
| Now | 698,443 | 20,480 |
| XOR data + LZ4 | 237,693 | 481,230 |
| XOR data + deflate | 136,996 | 581,927 |
| Dark bytes + LZ4 | 201,263 | 517,660 |
| Dark bytes + deflate | 117,233 | 601,690 |

The free space values do not include the 16-byte alignment of the menu and the patch code.

## Conclusions

- RLE does not help. Only approximately 6% of the bytes are zero. Light XOR dark of a picture is not mostly zero.
- The dark bytes compress better than the XOR data, by 15–20%.
- deflate gives approximately 6× with the dark bytes. A small inflate decoder is approximately 1–2 KB of code and needs a 32 KB window.
- LZ4 gives approximately 3.5×. The decoder is a few hundred bytes and is simple.
- bzip2 and LZMA compress more, but their decoders are large and need much RAM.

## The dark bytes are sufficient

`hook_lookup` in [dark_mode.c](../patches/dark-mode/dark_mode.c) applies the table one time, at the first View lookup (the `decided` flag). The firmware loads the light osos from the flash at each start. Thus the table only changes light to dark. A table of dark bytes is sufficient. The XOR format of the table is not necessary for the patch.

## Test on the real iPod

Real iPod 5.5G (owner, 28 October 2026, `dark-mode` version 1.1): the three appearances Light, Dark and Switch on iPod operate.

## A table from the light pictures (3 November 2026)

### The idea

A compressor uses only the dark bytes. But the light pictures are already in RAM when the patch applies the table. Each start loads the light osos from the disk, and the patch applies the table one time. Thus the table can describe the dark picture with the light picture as the source.

Research of the Dark Gray pictures (firmware 1.3):

- 251 pictures change. 248 are RGB565, 2 are 4-bit grey and 1 is ARGB4444.
- 168 dark pictures (481,755 bytes of changes) are exact colour maps of their light pictures. Each light colour always becomes the same dark colour. Example: picture 24399 (142 × 142) has 70 light colours. Its colour map is 280 bytes, and its XOR data is 32,744 bytes.
- The other dark pictures have few colours. For example, picture 25561 (100 × 100) has 2 colours.
- The pixel data of each picture starts on a 4-byte boundary. Thus the decoder can use 16-bit loads and stores.

### The table format "IFD2" (research only)

No app code uses this format. All values are little-endian, and each record starts on a 4-byte boundary.

| Field | Content |
|---|---|
| u32 | `IFD2` (0x32444649) |
| u32 | Number of records |
| u32 | Size of the table in bytes |
| records | One after the other |

Each record starts with u32 address and u32 (kind << 28 \| length in bytes).

| Kind | Data | What the decoder does |
|---|---|---|
| RAW (0) | The new bytes, then zeros to a 4-byte boundary | Copies the bytes. |
| MAP (1) | u32 N, then N × {u16 light, u16 dark}, sorted by light | For each u16 of the range, finds the light value and writes the dark value. Another value does not change. The decoder searches again only when the value is different from the value before. |
| PAL (2) | u16 number of colours, u16 bits (1, 2, 4 or 8), the colours, zeros to a 4-byte boundary, the indices (MSB first), zeros to a 4-byte boundary | Writes each u16 of the range from the palette. An index past the palette does not change the pixel. |

RAW records after a MAP record correct the pixels that the map does not give. The decoder skips a record whose range is not below 0x800000. It stops at an unknown kind and at a record that does not fit before the end of the table (the size in the header).

The encoder ([dark-table-map/ifd2.py](dark-table-map/ifd2.py)):

1. It compares the light osos with the dark osos of `apply_theme`.
2. For each 16-bit picture that changes, it makes three records: RAW runs, MAP with RAW corrections, and PAL. It uses the smallest. If two have the same size, it uses RAW, then MAP, then PAL.
3. The colour map takes, for each light value, the most frequent dark value. If two values have the same count, it takes the smaller value.
4. All other differences become RAW runs. Two runs join if fewer than 8 bytes separate them.

### Method

The script [dark-table-map/check.py](dark-table-map/check.py) does these steps:

1. It makes the dark osos with `apply_theme`, with and without the highlight rule for a part word (refer to [dark-theme.md](dark-theme.md#the-fault-in-the-80-colour-3-november-2026)).
2. It makes the XOR table of dark-mode 1.2 and the IFD2 table with RAW only, RAW + MAP, and RAW + MAP + PAL.
3. It applies each IFD2 table with the Python model of the decoder and with [dark-table-map/decode.c](dark-table-map/decode.c), compiled for the Mac with [dark-table-map/host_main.c](dark-table-map/host_main.c). Each result must be the same as the dark osos, byte for byte.
4. It compiles `decode.c` with the flags of the patches (`Patcher.clangFlags`) and gives the code size.

```
.venv/bin/python re/dark-table-map/check.py iPod_25.1.3.ipsw "Dark Gray.ipodtheme"
```

### Results

Firmware 1.3, theme Dark Gray, 3 November 2026. In all 6 tests, the Python model and the C decoder gave the dark osos exactly.

| Table | Highlight rule off | Highlight rule on |
|---|---|---|
| dark-mode 1.2 (XOR) | 698,443 | 681,853 |
| IFD2, RAW only | 691,804 | 678,404 |
| IFD2, RAW + MAP | 99,212 | 85,812 |
| IFD2, RAW + MAP + PAL | 78,484 | 65,084 |

The values are in bytes. The highlight rule is on in the app since the commit "Keep the Apple blue highlight in a part word".

The records of RAW + MAP + PAL with the highlight rule on (1,480 records):

| Part | Records or pictures | Bytes |
|---|---|---|
| Pictures as MAP | 185 | 41,532 |
| Pictures as PAL | 62 | 15,936 |
| Pictures as RAW | 1 | 496 |
| Other RAW records (Views, Types and the 3 pictures that are not RGB565) | 483 | 7,108 |

The code size (ARM, `-O2`, the flags of the patches):

| Decoder | Bytes |
|---|---|
| `apply_table1` (XOR, dark-mode 1.2) | 132 |
| `apply_table2` (RAW, MAP and PAL), 3 November 2026 | 612 |
| `apply_table2` + `apply_pal`, with the bounds checks of 4 November 2026 | 624 + 92 = 716 |

`apply_table2` calls no firmware function. It has one `mul r0, r8, r4` (`e0000498`). The rule "Rd is not Rm" of the ARM7TDMI is satisfied. `llvm-objdump` shows this instruction as `<unknown>` for ARMv4T, and as `mul` for ARMv6.

With the highlight rule on, RAW + MAP + PAL saves 616,769 bytes of table against the XOR table now. Refer to [the measured free space](#the-free-space-4-november-2026) for the result with the code of the patch.

### The work at the start

The decoder runs one time at the start, before the first View is read. The counts come from `check.py`. The instructions for each step come from the disassembly of `decode.c`.

| Decoder | Work | Instructions (estimate) |
|---|---|---|
| XOR (now) | 652,929 bytes × 6 | 3.9 million |
| IFD2 MAP | 438,430 pixels × 13, and 713,795 search steps × 11 (141,966 searches) | 13.6 million |
| IFD2 PAL | 42,046 pixels × 13 | 0.5 million |
| IFD2 RAW | 9,314 bytes × 4 | 0.04 million |

Thus the IFD2 decoder needs approximately 3.8 times the instructions of the XOR loop. Most of the work is the binary search. The clock of the CPU at this time is not known. Thus only a measurement in the emulator or on the iPod gives the time.

### Risks

- A MAP record is not idempotent. If the decoder runs two times on the same RAM, the colours are wrong. The patch applies the table one time (`decided`). A hibernation wake restores all of the RAM, together with `decided`. Two XOR passes also give a wrong result (the light theme).
- A MAP record reads the light pixels at the start. If a later step of the build (a patch or the firmware version) writes into a covered range, the result is wrong. The XOR table has the same risk. On 3 November 2026, no hook and no byte change of a patch was in a covered range. An implementation must check this after the build: apply the table to the final osos and compare the covered ranges with the dark osos.
- An error in the decoder can write wrong bytes into the resources. To recover, set the iPod to disk mode and delete `iPod_Control/iTunes/iPodFirmDarkMode`. Then the iPod starts light. The ARM code passed the emulator test of 4 November 2026 (refer to below).

## The full research (4 November 2026)

The owner asked for a full research of RAW + MAP + PAL, with overwhelming confidence. The work is on the branch `dark-table-ifd2`. The app, the Swift code and `patches/dark-mode` did not change.

### Faults in the first encoder and decoder

A review of `ifd2.py` and `decode.c` found four faults. None of them changes the result for Dark Gray. A different theme or an edit of the owner can cause them.

| Fault | Result | Correction |
|---|---|---|
| A run outside the pictures that crosses the edge of a picture was skipped completely. | The bytes outside the picture stay light. | The encoder clips each run to the parts outside the pictures (`_outside`). |
| Two pictures with overlapping pixel ranges get two MAP records. | MAP is not idempotent, so the colours are wrong. | The encoder refuses overlapping ranges. Firmware 1.3 has 402 BMap pictures, and no two pixel ranges overlap or share bytes. |
| The decoder did not check that a record is inside the table. | A wrong count reads past the table. | `decode.c` and the Python model stop at a record that does not fit before the end of the table. |
| A table of RAW records can be larger than the IFDM table. | No saving for such a theme. | `choose` uses the smaller table. The decoder of an implementation must then accept both magic values. |

`decode.c` also used `(unsigned char *)0 + at`, which is not defined in C. It now casts the integer address, as `dark_mode.c` does.

### Tests on the Mac

The file [dark-table-map/test_ifd2.py](dark-table-map/test_ifd2.py) has 505 tests. All passed on 4 November 2026. The C decoder runs with AddressSanitizer and UndefinedBehaviorSanitizer. The table is in a buffer of its exact size, so a read past the table stops the test.

| Test | Count | Result |
|---|---|---|
| Synthetic themes: colour maps, maps with errors, few colours, noise, adjacent pictures, runs across the edges, odd addresses. Each with RAW, RAW + MAP and RAW + MAP + PAL. | 300 themes, 900 tables | The Python model and the C decoder give the dark image exactly. `choose` is never larger than IFDM. |
| Corrupted tables: cut, changed bytes, wrong count, wrong size | 200 | No read past the size in the header. No undefined behaviour. |
| Dark Gray from the complete build, with and without Split Switch | 2 | Exact. The table is 65,084 bytes (65,132 bytes with Split Switch). |
| Run across a picture edge, overlapping pictures, firmware pictures | 3 | Passed. |

### Audit of the build order

The app makes the switch table first. Then it applies the other patches, the iPodFirm list and the firmware version (`AppModel.outputOSOS`). If a later step writes a byte that the table also writes, dark mode shows a wrong result. The script [dark-table-map/audit.py](dark-table-map/audit.py) makes the build with Dark Gray and the Split layout with both switches. It then applies each patch, and all patches together.

| Table | Ranges | Bytes that the decoder can write |
|---|---|---|
| IFDM | 3,619 | 652,941 |
| IFD2 (MAP and PAL write the full picture) | 1,485 | 970,278 |

Results:

- Each of the 24 other patches alone: 0 bytes in a range of either table.
- All 22 patches that can be on together (not `playback-log` with `diagnostic-log`, and not `usb-host-probe` with `usb-audio-out`): 0 bytes.
- The firmware version (0x9ee70–0x9eed8): 0 bytes.
- With the IFDM table, these 22 patches together end at 0x803c2c. That is past the limit 0x7F8000. With IFD2, they fit.

An implementation must keep this check: apply the table to the final osos, and compare the result with the expected dark image.

### The emulator test

The script [dark-table-map/proto/make_drives.py](dark-table-map/proto/make_drives.py) makes a research copy of `dark-mode` 1.2. The copy has three additions: `mark_start()` and `mark_done()` around the apply of the dark table, and an FNV-1a hash of 0x3324c0–0x7400d8 after both tables. That range contains each byte that a table can change (4,250,648 bytes). The script [dark-table-map/proto/measure.py](dark-table-map/proto/measure.py) starts each drive without a window. It reads the hash with `peek` and the markers with `evlog`.

Build: Dark Gray, Split layout, both switches. The IFD2 table comes from the complete image in RAM.

| Drive | Files on the drive | Hash | Instructions of the apply | Emulated time |
|---|---|---|---|---|
| IFDM, dark | `iPodFirmDarkMode` = 1 | Same as expected | 4,027,809 | 53.7 ms |
| IFD2, dark | `iPodFirmDarkMode` = 1 | Same as expected | 13,886,510 | 185.2 ms |
| IFD2, dark, stock layout | also `iPodFirmLayout` = 0 | Same as expected | 13,886,089 | 185.1 ms |
| IFD2, light | no file | Same as expected | 9 (no apply) | 0 ms |

The hash was the same 20 emulated seconds later. Thus the ARM decoder gives each byte of the dark image exactly. It works with the layout table after it. A light start does not change a byte.

The IFD2 apply needs 3.4 times the instructions of the XOR apply. It adds approximately 131 ms of emulated time, and only to a dark start. The emulator runs 75 million instructions each second. The real CPU clock at this time is not known.

A faster search was examined in Python. A cache of 64 entries in front of the binary search removes 476,159 of 713,795 search steps (approximately 5 million instructions). It needs 256 bytes of stack. The hook runs on the stack of the thread that reads the first View, and the size of that stack is not known. Thus the decoder keeps the binary search.

### The free space (4 November 2026)

Measured with Dark Gray and "Switch on iPod" (no Split layout). The IFD2 patch is `dark-mode` 1.2 with `apply_table2` and the text of `decode.c`.

| Table | Table bytes | Patch code | End of the patch | Free below 0x7F8000 |
|---|---|---|---|---|
| IFDM (now) | 681,853 | 1,299 | 0x7e6dc3 | 70,205 |
| IFD2 | 65,084 | 2,015 | 0x75074f | 686,257 |

The patch code of IFD2 contains `apply_table1` (132 bytes), which only the size compare uses. The patch keeps `apply_table` for the layout table. The saving is 616,052 bytes.

### What is proved, and what is not

Proved:

- The encoder and the decoder give the dark image exactly: Dark Gray, Split Switch, and 300 synthetic themes, in Python, in C on the Mac, and on the emulated ARM CPU.
- The decoder reads no byte past the size of the table, also with a corrupted table.
- No patch, no set of patches and no firmware version writes into a range of the table.
- A light start does not change a byte.

Not proved:

- The start time on the real iPod. The emulator gives 185 ms against 54 ms. Only a test on the real iPod gives the real time.
- A different theme from a real person. The synthetic tests cover the cases of the format, and `choose` keeps the IFDM table if IFD2 is not smaller.

### The steps of an implementation

1. Put `apply_table2` in `patches/dark-mode/dark_mode.c`. Keep `apply_table` for IFDM tables and for the layout table. Increase the `version`, and measure the `size`.
2. In `DarkMode.swift` and `darkmode.py`: make the IFDM table, and then the IFD2 table from the complete image. Use the smaller table.
3. After the build of all patches: apply the table to the final osos, and compare the result with the expected dark image. Stop the build if they are not the same.
4. Port `ifd2.encode` to Swift, and compare the Swift tables with the Python tables in a test.
5. Test in the emulator, and then on the real iPod with a stopwatch for the start time.

## The implementation (4 November 2026)

The owner asked for a version to test on a real iPod. The implementation follows the steps above:

- `patches/dark-mode/dark_mode.c` 1.3 has `apply_table2`. It selects the decoder by the magic value. The code is 2,003 bytes.
- `DarkTable.swift` and `src/ipodfw/darktable.py` make the IFD2 table. The Swift table and the Python table are the same (`testDarkGrayTableAgreesWithPython`).
- `DarkTable.check` compares the result of both tables on the final firmware, in `DarkMode.build` and again in `AppModel.outputOSOS` after all patches.
- With Dark Gray and Switch on iPod, the added size is 106,307 bytes (722,371 bytes with `dark-mode` 1.2).
- Emulator: with the build of version 1.3, 201 words of the table ranges, read with `peek`, were the same as the expected dark image.

Real iPod 5.5G (owner, 4 November 2026, app 0.1.261, Dark Gray, stopwatch): the restart from light to dark took 54 s. The restart from dark to light took 54 s. The light start does not apply the table. Thus the IFD2 apply (185 ms in the emulator) adds no time that a stopwatch can measure.

The owner reported that all screens in dark mode are correct.

## Open items

- Merge the branch `dark-table-ifd2` into `main`, only if the owner asks.
- Old results (9 October 2026): the dark bytes compress better than the XOR data, and deflate gives approximately 6×. A table from the light pictures gives a smaller result than deflate (65,084 bytes against 117,227 bytes) and needs no RAM for a window.
