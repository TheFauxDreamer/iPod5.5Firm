# Dark Mode switch table: compression

## Goal

The appearance "Switch on iPod" puts a switch table after the end of osos. With a large theme, the table uses most of the space below 0x7F0000 (`ThemeImport.ososLimit`). Then little space stays for extended patches. This note measures how much a compressed table can save. It is research only. No code uses compression.

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

RAW records after a MAP record correct the pixels that the map does not give. The decoder skips a record whose range is not below 0x800000, and it stops at an unknown kind.

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
| `apply_table2` (RAW, MAP and PAL) | 612 |

`apply_table2` calls no function. It has one `mul r0, r8, r4` (`e0000498`). The rule "Rd is not Rm" of the ARM7TDMI is satisfied. `llvm-objdump` shows this instruction as `<unknown>` for ARMv4T, and as `mul` for ARMv6.

With the highlight rule on, RAW + MAP + PAL saves 616,769 bytes of table against the XOR table now. The decoder needs 480 more bytes of code. Thus the net saving is 616,289 bytes. The free space below 0x7F8000 after a "Switch on iPod" build with Dark Gray then increases from 69,632 bytes to approximately 686,000 bytes.

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
- An error in the decoder can write wrong bytes into the resources. To recover, set the iPod to disk mode and delete `iPod_Control/iTunes/iPodFirmDarkMode`. Then the iPod starts light. The C decoder and the Python model gave the same result on the Mac. The ARM code is not tested.

## Open items

- Measure the start time in the emulator (`IPODFW_MARK_AT` at the start and the end of the apply) for the XOR decoder and the IFD2 decoder.
- Apply the IFD2 table in the emulator. Read the covered ranges with `peek`, and compare them with the dark osos. This tests the ARM code.
- A faster search, if the start time is too long: for example a small hash table on the stack for each picture.
- Find the result for other themes.
- Old results (9 October 2026): the dark bytes compress better than the XOR data, and deflate gives approximately 6×. A table from the light pictures gives a smaller result than deflate (65,084 bytes against 117,227 bytes) and needs no RAM for a window.
