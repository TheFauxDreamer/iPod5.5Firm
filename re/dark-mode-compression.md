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

## Open items

- Measure the time to decode on the iPod or in the emulator.
- Measure the size of the decoder code.
- Find the RAM for the decoder window. The allocator can possibly supply it, as for the log buffer of `usb-host-probe`.
- Find the result for other themes.
- A bug in the decoder writes wrong bytes into the resources. Find out if the owner can then recover: set the iPod to disk mode and delete `iPod_Control/iTunes/iPodFirmDarkMode`.
