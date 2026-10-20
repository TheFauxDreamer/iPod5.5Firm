# Song Info: the song data in firmware 1.3

This note records where the iPod Video 5.5G with RetailOS 1.3 keeps the data of a song in RAM, and how a patch can show it. It is research for a possible patch "Song Info" (refer to [patch-ideas.md](patch-ideas.md)). No patch exists.

All addresses are osos offsets of firmware 1.3. The research used Ghidra 12.1.4 on 20 October 2026.

## Result

- `FUN_000d7888` reads each mhit record of iTunesDB into a track object of 0x110 bytes. Most fields that a Song Info screen needs are in this object.
- Now Playing gets the current track through the provider at + 0x28. The track object is at (provider + 0x28) + 4.
- Settings > Main Menu shows rows with a label at the left and a value at the right. The patches already supply the value text through the "get" method (0x66c94c). A Song Info list can use the same type of row.

## The fields of the track object

The loader reads 0x1b4 bytes of the mhit into a buffer. The table gives the mhit offset (from libgpod) and the offset in the track object. The evidence of each line is Static (0xd7888), except where the table says more.

| mhit | Content | Track object |
|---|---|---|
| +0x10 | Unique ID | +0x20 (u32) |
| +0x1f | Rating (stars × 20) | +0x7a (u8) |
| +0x20 | Date modified | +0x68 (u32) |
| +0x24 | File size in bytes | +0x6c (u32), if the field at mhit + 0x12c is 0 |
| +0x28 | Length in ms | +0x58 (u32). Static, also 0x21e004: Now Playing divides it by 1000. |
| +0x2c, +0x30 | Track number, track count | +0x80, +0x82 (u16) |
| +0x34 | Year | +0x76 (u16) |
| +0x38 | Bit rate in kbps | +0x74 (u16) |
| +0x3c | Sample rate × 65536 | +0x70 (float), if the float at mhit + 0x88 is 0 |
| +0x40 | Volume adjustment | +0x78 (u16) |
| +0x44, +0x48 | Start time, stop time | +0x5c, +0x60 |
| +0x4c | Sound Check | +0x7e (u16) |
| +0x50 | Play count | +0x8c, copied to +0x98 |
| +0x58 | Last played | +0x94 |
| +0x5c, +0x60 | Disc number, disc count | +0x84, +0x86 (u16) |
| +0x68 | Date added | an argument of the constructor 0xa96c0 |
| +0x6c | Bookmark time | +0x64 |
| +0x70 | dbid (64 bits) | +0x108, +0x10c (refer to [docs/firmware-functions.md](../docs/firmware-functions.md)) |
| +0x7a | BPM | +0x88 (u16) |

Emulator test (20 October 2026, stock 1.3, the test library of `ITunesDB.makeLibrary`): the songs of the play list had + 0x58 = 30000, + 0x6c = the file size (for example 379687), + 0x70 = 44100.0, + 0x74 = 128, + 0x76 = 2006, + 0x80/+0x82 = 1/10 … 6/10, + 0x8c = 0. These are the values that the test library writes. Thus these offsets have the evidence Static and Emulator.

The text fields (title, artist, album, composer, genre) are pool indexes at + 0x28 … + 0x40 (already in `docs/firmware-functions.md`). The `album-artists` patch reads the Album Artist text. The file path (mhod type 2) and the file type need more research.

## The current song

| Address | Function | Evidence |
|---|---|---|
| 0x1e804c | The property method of the main provider. Case 0x63c3 makes "%d of %d" from the play list (provider + 0x20). The cases 0x63bd–0x63bf get the texts of the current song from the object at provider + 0x28 (method + 0x48). | Static |
| 0x21e004 | (provider + 0x28): if a song is there (method + 0), it returns (object + 4) + 0x58 divided by 1000: the length in seconds. | Static |
| 0x09bb30 | (library): the position in the song: player + 0x2998 or + 0x2778. The player is (library + 0xca0) + 4. | Static |

## The design of a patch

1. Add an item "Song Info" to the main menu or to the Music menu (`menu_items`).
2. The item opens a list of rows. Each row has a label (for example "Bit Rate") and a value (for example "256 kbps").
3. The hook on the "get" method (0x66c94c, with `chain`) gives the value text from the track object of the current song.
4. Without a current song, each value is "—".

The patcher can add items to an existing menu, but it cannot add a new Menu resource. A Song Info list needs a new Menu resource, or a change to the patcher.

## Open questions

- Which Menu resource can open a list with values, as Settings > Main Menu (Menu 24600) does?
- Where is the file type (mhit + 0x18) in the track object? The loader copies mhit + 0x90 through 0x10eb78 to + 0x7c.
