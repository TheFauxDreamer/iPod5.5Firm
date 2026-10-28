# Album Artist: research notes

This document records the research for an `album-artist` patch. The firmware is Apple RetailOS 1.3 for the iPod Video.

**Status (6 October 2026): research only.** The owner decided not to add the patch to `patches/` now. This document keeps all the data to make it later: the hooks, the code, the `patch.json` and the test results. The emulator test used a test build of Hook 1. The sort-index correction is not tested.

**Status (16 October 2026): a different method, now a patch.** The owner selected an "Album Artists" item in the Music menu, as in osos-lab. The normal Artists list does not change. Refer to [Album Artists menu item](#album-artists-menu-item-15-october-2026). The patch is [patches/album-artists/](../patches/album-artists/). The sections before it describe the first method ("replace the Artist").

The owner asked for two changes:

1. Sort the Albums list by the Album Artist.
2. Show the Album Artists in the Artists list.

## Facts

### The firmware reads iTunesDB itself

The emulator iTunesDB from `ITunesDB.build` has no mhod 52 or mhod 53 sort indexes. The Artists, Albums and Songs lists still operate in the emulator. Thus RetailOS sorts the lists itself.

### The track parser

`FindConstant.java` found the tag `mhit` (0x7469686d) only in the function 0xd7888. The loader 0xaf930 calls it. The function reads each track (mhit, 0x1b4 bytes of header), then each string (mhod) of the track.

A jump table selects the code for each mhod type:

| Address | Content |
|---|---|
| 0xd7e3c | `cmp r5, #0x1f` (r5 = mhod type) |
| 0xd7e40 | `addls pc, pc, r5, lsl #2` |
| 0xd7e48 + 4 × type | One `b` instruction for each type 0 to 31 |
| 0xd7e44 | `b 0xd8204` for a type above 31 |

The registers in the mhod loop:

| Register | Content |
|---|---|
| r4 | The track object |
| r5 | The mhod type, then the result of the read |
| r6 | The database object |
| sb | The file reader |

The code for the types that the parser keeps:

| Type | iTunesDB field | Code | String pool | Slot in the track |
|---|---|---|---|---|
| 1 | Title | 0xd7ee4 | db + 0xb4 | track + 0x28 |
| 3 | Album | 0xd7f14 | db + 0x138 | track + 0x34 |
| 4 | Artist | 0xd7f58 | db + 0xe0 | track + 0x2c |
| 5 | Genre | 0xd7fa0 | db + 0x190 | track + 0x40 |
| 12 | Composer | 0xd7f88 | db + 0xe0 | track + 0x3c |

Type 22 (Album Artist) goes to 0xd81ec. This code skips the string (0xdc6a8). The types 23 and 27 to 31 (the sort strings) are also skipped. Thus RetailOS 1.3 does not use the Album Artist.

### The code for type 4 (Artist)

```
0d7f58  mov r3, #1
0d7f5c  add r2, r4, #0x2c
0d7f60  stm sp, {r2, r3}         ; arguments 5 and 6: slot, 1
0d7f64  add r3, r6, #0xe0        ; the string pool
0d7f68  mov r2, r5               ; the mhod type
0d7f6c  mov r1, #1
0d7f70  mov r0, sb               ; the reader
0d7f74  bl  0x10db84             ; read the string into the pool
0d7f78  mov r5, r0
0d7f7c  mov r0, r4
0d7f80  bl  0x907f4              ; update the artist data of the track
0d7f84  b   0xd821c              ; the next mhod
```

### The string functions

| Address | Function |
|---|---|
| 0x10db84 | Calls 0xf4340 with argument 4 = 0. |
| 0xf4340 | Reads the mhod string header and the text. It compares the type only with 2 (path). Then it stores the text in the pool with 0x885ec. |
| 0x885ec | Stores a string in a pool (pool, text, length, slot). It writes 0 to the slot first. An empty text gives the index 0. Correction (16 October 2026): each track gets its own index, also for the same text. The emulator test with 4000 tracks showed it. |
| 0x907f4 | Reads the artist of the track (slot + 0x2c), sets bit 4 of byte +0x15, and calls 0x1114dc. |
| 0x1114dc | Makes the sort key of the artist (pool db + 0x10c, slot + 0x30). |
| 0xdc6a8 | Skips bytes in the file. |

The function 0xd6de8 also reads mhod strings, but only the playlist names.

## The proposed hook

The hook replaces the jump table entry for type 22 (0xd7ea0) with a `b` to `hook_album_artist`. The hook does the same steps as the code for type 4. The Album Artist then replaces the Artist of the track. If the Album Artist is empty, the hook puts back the old Artist.

A second store to the Artist slot keeps one extra entry in the pool. The memory use is small. The Artists list does not show these names, because the list comes from the tracks, not from the pool. The emulator test confirms this.

The Composer uses the same pool (db + 0xe0). This also shows that the Artists list does not come from the pool.

## Emulator test (6 October 2026)

The test library had 7 tracks:

| Title | Artist | Album | Album Artist |
|---|---|---|---|
| Comp One, Two, Three | Alpha Band, Mike Moe, Zed Zeppo | Zeta Hits | Various Artists |
| Apple One, Two | Zulu, Zulu feat. Kilo | Apple Album | Aardvark |
| Middle One | Bravo | Middle Album | (none: mhod 22 has the Artist) |
| Blank One | Echo | Blank AA Album | (an empty mhod 22) |

Results:

| Screen | Apple firmware | With the patch |
|---|---|---|
| Artists | All, Alpha Band, Bravo, Echo, Mike Moe, Zed Zeppo, Zulu, Zulu feat. Kilo | All, Aardvark, Bravo, Echo, Various Artists |
| Albums | All, Apple Album, Blank AA Album, Middle Album, Zeta Hits | The same |
| Artists > Various Artists | – | The 3 songs of Zeta Hits |
| Now Playing (Shuffle Songs) | – | Comp One, Various Artists, Zeta Hits |

The Albums list of RetailOS 1.3 is in the order of the album name. It does not use the Artist. Thus the patch does not change the order of the Albums list. The patch changes the albums of each entry in the Artists list.


## The browse indexes (mhod 52 and 53)

The emulator test library has no browse indexes. iTunes and libgpod write them in the master playlist. libgpod sorts the artist index (type 0x05) by the Artist (mhod 4, or mhod 23 if present), then by the album.

The playlist parser 0xd6de8 uses them:

1. In the first pass over the mhods of a playlist, type 52 (0x34) and type 53 (0x35) set a flag. The parser skips their content.
2. If a flag is set, the parser goes back in the file (0x8f5c4) and reads the mhods again.
3. Type 52 goes to 0xf426c. If the count of entries is equal to the count of tracks, 0xf426c keeps the sorted list of tracks at db + 0x2fc + 4 × (sort type). 0x10a15c converts the sort type.
4. Type 53 (the jump table: letter, start, count) goes to db + 0x494 + 4 × (sort type).

Thus with an iTunesDB from libgpod, the firmware probably uses the sort order of libgpod, not its own sort. The patch does not change the indexes. The Artists list can then be out of order, or one Album Artist can show more than once. This is not tested yet.

Possible correction: make the parser ignore the indexes when the patch is on. Then the firmware sorts the lists itself, as in the emulator test. The cost is a longer database load at every start of the iPod.

## Other programs that write iTunesDB (source read on 6 October 2026)

| Program | Order of mhod 4 and 22 | Empty Album Artist | mhod 52 Artist index sorted by | Effect of the patch |
|---|---|---|---|---|
| libgpod (`itdb_itunesdb.c`) | 4, then 22 | Not written | Sort Artist, else Artist (track) | Album Artist used. Index order possibly wrong. |
| MiMusic | 4, then 22 | Not written | Sort Artist (mhod 23), else Artist | The same as libgpod |
| rPod (`dbwrite.rs`) | 4, then 22 | Not written | Artist (track) | The same as libgpod |
| iOpenPod (`mhod_writer.py`, `mhod52_writer.py`) | 4, then 22 | Not written | Sort Artist, else Artist | The same as libgpod |
| GNUpod (`Mktunes.pm`) | 22, then 4 (alphabetical order of the field names) | Not written | No mhod 52 | No effect: the Artist replaces the Album Artist again |
| zytunes `ipod-db` (`itunesdb_write.rs`) | Writes the Album Artist as mhod 14, not 22 | – | Artist (track) | No effect |

zytunes and iOpenPod also write an Album Artist index (sort type 29 or 0x23) for newer iPods. RetailOS 1.3 converts the sort type with 0x10a15c. It is not known if it uses these types.

No program sorts the Artist index by the Album Artist for the 5.5G. Thus with a program that writes indexes, the patched Artists list can be out of order.

## Limits

- The patch uses the Album Artist only if mhod 22 comes after mhod 4 in the track. If the order is different, the track keeps its Artist. The iPodFirm test library writes mhod 22 after mhod 4. The order that Finder writes is not verified. The test on the real iPod verifies it.
- Now Playing shows the Album Artist.
- The patch does not use the sort strings (mhod 23 and 27 to 31).

## Hook site signature

The hook site is in a table, so `MakeSignature.java` cannot make a signature for 0xd7ea0 (3573 matches). The signature of the dispatch at 0xd7e40 (`MakeSignature.java OUT 0xd7e40 8 2`) has 1 match. The hook site is the dispatch + 8 + 4 × 22.

## Proposal: the hooks with the sort-index correction

This section gives the full patch with the correction for the sort indexes. Other people can use it to do their own test. To make the patch in iPodFirm, put the two files below in `patches/album-artist/`. Then update the documents in the table "Keep the reference current" in [docs/README.md](../docs/README.md). The free area 0x736784–0x7367d4 was free on 6 October 2026. Examine it again before you use it. The correction (the two flag changes) has no emulator test. The bytes below were applied to osos 1.3 with `patcher.apply` on 6 October 2026, and all `expect` values agreed.

### Hook 1: use the Album Artist

The track parser 0xd7888 jumps on the mhod type:

```
0d7e3c  cmp   r5, #0x1f
0d7e40  addls pc, pc, r5, lsl #2     ; table at 0xd7e48 + 4 × type
0d7ea0  b     0xd81ec                ; type 22 (Album Artist): skip the string
```

A `b` hook at 0xd7ea0 (expect 0xea0000d1) goes to `hook_album_artist` at 0x736784. At the hook, r4 = track, r5 = mhod type, r6 = database and sb = file reader. The hook does the same work as the Artist case at 0xd7f58:

1. Keep the old Artist index (track + 0x2c) on the stack.
2. Call 0x10db84(reader, 1, type, db + 0xe0, track + 0x2c, 1). This reads the string into the artist pool.
3. If the new index is 0 (an empty string), put back the old index.
4. Call 0x907f4(track). This makes the artist sort key again.
5. Jump to 0xd821c, the end of the loop body. It reads the result in r5.

### The flag code: ignore the sort indexes

The playlist parser 0xd6de8 reads the master playlist in two passes. Pass 1 sets two flags and skips the data:

```
0d711c  cmp   r0, #0x34              ; mhod 52 (sorted track list)
0d7120  moveq r0, #1
0d7124  streq r0, [sp, #0x9c]        ; flag A
0d7128  beq   0xd7184                ; skip the data
...
0d717c  cmp   r0, #0x35              ; mhod 53 (letter table)
0d7180  moveq fp, #1                 ; flag B
0d7184  ...                          ; skip the data (0xbfab0)
```

Pass 2 runs only if flag A or flag B is not zero. It reads mhod 52 with 0xf426c (call at 0xd776c) and mhod 53 at 0xd7700.

The correction writes 0 in place of 1 in the two flag instructions:

| At | Old bytes | Old instruction | New bytes | New instruction |
|---|---|---|---|---|
| 0xd7120 | `01 00 a0 03` | `moveq r0, #1` | `00 00 a0 03` | `moveq r0, #0` |
| 0xd7180 | `01 b0 a0 03` | `moveq fp, #1` | `00 b0 a0 03` | `moveq fp, #0` |

Pass 1 still skips the data of mhod 52 and 53, and pass 2 does not run. The firmware then operates as with a database that has no indexes, and it sorts the lists itself. The emulator test without indexes gave correct lists. The time to sort a large library at start is not measured.

### patch.json

```json
{
  "name": "album-artist",
  "version_letter": "l",
  "description": "The iPod uses the Album Artist of each song in place of the Artist. The Artists list shows the Album Artists. All the songs of a compilation are under one artist. Now Playing also shows the Album Artist. A song without an Album Artist keeps its Artist. The iPod reads the Album Artist when it reads the music database: at the start and after a sync.",
  "osos_sha256": "784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251",
  "load_address": "0x736784",
  "symbols": {
    "db_read_string": "0x10db84",
    "track_artist_changed": "0x907f4",
    "mhod_done": "0xd821c"
  },
  "hooks": [
    { "kind": "b", "at": "0xd7ea0", "expect": "0xea0000d1", "to": "hook_album_artist" }
  ],
  "bytes": [
    { "at": "0xd7120", "expect": "0100a003", "value": "0000a003" },
    { "at": "0xd7180", "expect": "01b0a003", "value": "00b0a003" }
  ]
}
```

### album_artist.c

Compile with clang: `--target=armv4t-none-eabi -mcpu=arm7tdmi -marm -mfloat-abi=soft -O2`. Refer to [docs/patch-system.md](../docs/patch-system.md) for the link step.

```c
void db_read_string(void *reader, int mode, int type, void *pool, int *slot, int flag);   /* 0x10db84 */
void track_artist_changed(void *track);                                                     /* 0x907f4 */
void mhod_done(void);                                                                       /* 0xd821c */

__attribute__((naked)) void hook_album_artist(void)
{
    __asm__ volatile(
        "sub   sp, sp, #16\n"           /* [sp] and [sp, #4]: arguments 5 and 6; [sp, #8]: the old Artist */
        "ldr   r0, [r4, #0x2c]\n"
        "str   r0, [sp, #8]\n"
        "mov   r3, #1\n"
        "add   r2, r4, #0x2c\n"
        "stm   sp, {r2, r3}\n"
        "add   r3, r6, #0xe0\n"
        "mov   r2, r5\n"
        "mov   r1, #1\n"
        "mov   r0, sb\n"
        "bl    db_read_string\n"
        "mov   r5, r0\n"
        "ldr   r0, [r4, #0x2c]\n"
        "cmp   r0, #0\n"
        "ldreq r0, [sp, #8]\n"
        "streq r0, [r4, #0x2c]\n"
        "add   sp, sp, #16\n"
        "mov   r0, r4\n"
        "bl    track_artist_changed\n"
        "b     mhod_done\n");
}
```

### The changes as bytes (without iPodFirm)

All offsets are in the osos image of firmware 1.3. Make sure that the SHA-256 of the osos image is `784ae3d5540fd2f89e8c947b93629e97f62a06dc311d9745aab143e4db6bb251` before you start.

| At | Old bytes | New bytes | Content |
|---|---|---|---|
| 0xd7120 | `01 00 a0 03` | `00 00 a0 03` | Flag A (mhod 52) |
| 0xd7180 | `01 b0 a0 03` | `00 b0 a0 03` | Flag B (mhod 53) |
| 0xd7ea0 | `d1 00 00 ea` | `37 7a 19 ea` | `b 0x736784` (Hook 1) |
| 0x736784 | zeros | 80 bytes, below | `hook_album_artist` |

```
736784: 10 d0 4d e2 2c 00 94 e5 08 00 8d e5 01 30 a0 e3
736794: 2c 20 84 e2 0c 00 8d e8 e0 30 86 e2 05 20 a0 e1
7367a4: 01 10 a0 e3 09 00 a0 e1 f4 5c e7 eb 00 50 a0 e1
7367b4: 2c 00 94 e5 00 00 50 e3 08 00 9d 05 2c 00 84 05
7367c4: 10 d0 8d e2 04 00 a0 e1 08 68 e5 eb 91 86 e6 ea
```

The code is after the end of Apple's osos image (0x736000). Do these steps:

1. Extend the osos image with zeros to 0x736800 bytes (7,563,264 bytes).
2. Write the bytes in the table.
3. In the firmware directory, set the length of the osos entry to the new size.
4. Calculate the checksum of the osos entry again: the sum of all bytes as a 32-bit value.

[docs/firmware-format.md](../docs/firmware-format.md) describes the directory. On firmware 1.3, rsrc starts 0x736800 bytes after the start of osos. Thus the new size fits in the 2 KB gap, and rsrc does not move. iPodFirm does these steps itself.

CAUTION: Test in the emulator before you flash a real iPod. A wrong byte can stop the iPod at start. Then put the iPod in disk mode (hold Select and Play) and flash the Apple firmware again.

### Correction B: ignore only the lists that use the Artist

Use this only if the full sort at start is too slow. It is not written and not tested.

| Hook | Kind | At | Expect | Function |
|---|---|---|---|---|
| 2 | `bl` | 0xd776c | 0xeb0072be | Wrapper of 0xf426c |
| 3 | `bytes` | 0xd7700 | `35 00 50 e3` (`cmp r0, #0x35`) | `ff 00 50 e3` (`cmp r0, #0xff`): all mhod 53 go to the skip path 0xd784c |

Hook 2 calls 0xf426c(reader, db, buffer, length), then reads the sort type (the first word of the buffer). For the types 0x05 (Artist) and 0x07 (Genre), it gets the slot with 0x10a15c(type). Then it frees the list at db + 0x2fc + 4 × slot with 0x964ec and writes 0. The risks:

- The firmware possibly does not accept a mix of lists from the index and lists that it sorts itself.
- Without the letter tables, the letters of the fast scroll possibly do not operate.
- The code needs approximately 60 bytes. Only 44 bytes are free after Hook 1 (0x7367d4–0x736800).

## Album Artists menu item (15 October 2026)

This section records the research for a second method. A new item "Album Artists" in the Music menu opens a list of the Album Artists. A song without an Album Artist uses its Artist. The normal Artists list, Now Playing and the sort indexes do not change.

### The osos-lab design (iPod Classic, firmware 2.0.5)

[osos-lab](https://github.com/lgreitis/osos-lab) (RepriseOS) has this function for the iPod Classic 6G and 7G. The files are in `payload/`. The source was read on 15 October 2026.

| Part | File | Function |
|---|---|---|
| Read the tag | `album_artist.c`, `album_artist.S` | A hook in the track parser reads mhod 22 into the native artist string pool. A side hash table keeps the index for each track (key: the persistent ID). The table is cleared when the library loads again. |
| Build the list | `album_artists.c` | The patch makes its own browser. For this browser only, it replaces the native "build artists" function. It collects the tracks that pass the native filter, sorts them by the Album Artist (or the Artist) with the native text compare, and makes the groups and the letter table. |
| Filter | `album_artists.S` | A hook in the native filter compares the Album Artist of the track with the selected row. The Albums and Songs levels then come from the native code. |
| Menu item | `album_artists.ui`, `album_artists_menu.c` | A new Music menu item after Artists. Settings items show or hide it in the Main Menu and the Music menu. |

The user interface of firmware 2.0.5 is different from RetailOS 1.3. Thus osos-lab gives the design, not the addresses.

### Method of the research

- Ghidra (project `osos13`) and the scripts in `re/ghidra-scripts/`.
- The instrumented emulator with the stock firmware 1.3 and the 7-track library of the [emulator test](#emulator-test-6-october-2026).
- `IPODFW_PROFILE=1`: a comparison of the code that runs when Artists opens and when Albums opens.
- `IPODFW_REGS_AT`: the registers at the bytecode loop (0x135b84), at the native call of the script engine (0x120bec), at the activate jump (0x19e69c) and at the resource lookup (0x21f254).

### The Music menu

The Music menu is Menu 24440 (data at 0x4af348). It has 10 items of 40 bytes: Playlists, Artists, Albums, Compilations, Songs, Podcasts, Radio, Genres, Composers and Audiobooks. The menu hides the items that have no content. Menu 24094 (31 items) is the main menu. Correction (16 October 2026): before, this note said that it is the list in Settings > Main Menu. That list is Menu 24600.

| Item offset | Content | Artists item |
|---|---|---|
| +0x08 | u32 | 0x3eb2 |
| +0x0c | u32: an ID of the target | 0x41a2 |
| +0x18 | i16: the label string ID | -126 ("Artists") |
| +0x1a | u8: the position (8, 9, ...) | 9 |
| +0x1b | u8 | 3 |
| +0x1c | u32 | 0x7a010000 |
| +0x20 | i16: the label string ID again | -126 |

The value at +0x0c is not a resource ID. It also occurs as a literal at 0x23db88 and in the script (0x4bf856), but its function is not known.

### Test: a copy of the Artists item (emulator)

A test firmware had a copy of the Artists item after Artists, with the label 24476 ("Cancel"). The new menu went after the end of osos (0x736800), as the patcher does for the Settings menu. Results:

| Action | Result |
|---|---|
| Open the Music menu | Playlists, Artists, Cancel, Albums, Songs, Podcasts, Genres, Composers, Audiobooks |
| Select Cancel | The Artists list (title "Artists") |
| Select Albums | The Albums list |
| Select Composers | The Composers list |

Thus the firmware finds the action of an item from the item data, not from the position of the item. A new item that is a copy of Artists opens the Artists list. The other items continue to operate.

### The selection of a menu item

| Address | Function |
|---|---|
| 0x6775b8 | The vtable of the menu list class. |
| 0x6776f8 | Vtable slot +0x140: `activate(list, row)` = 0x23ca4c. A `word` hook here sees each menu selection. |
| 0x23ca4c | Calls 0x239f7c(list, row, tag). This sends the selection event. |
| 0x19e644 | The script calls this method. It calls `activate` for the selected row. |
| list + 0x1c | i16: the Menu resource ID (24440 for the Music menu). |
| list + 0x144 | The menu data object. |
| 0x2183ec(menu data, row) | Returns the item object of a visible row. It skips the hidden items. |
| item + 0x10 | A pointer to the resource item + 4. The label ID is the i16 at this pointer + 0x14. |
| 0x21845c(menu data) | Returns the count of visible items. |
| 0x253fe4(item) | Returns 0 if the item is hidden. |

### The script of the Artists screen

The user interface script (`TCmd` 9088, SpiderMonkey 1.5 bytecode) has one function for each Music item. The Artists function starts near 0x4ba58e. The Albums function starts near 0x4b9fc2. When Artists opens, the script calls these native functions in this sequence:

| Native | Arguments | Function |
|---|---|---|
| 0x19e644 | menu screen | Activates the selected row. |
| 0x1e7b98 | JS browser | Resets the browser: 0xb29b0(br, 0), 0xb2894(br, 1, 3). |
| 0x1e77e8 | JS browser | Updates the list. Calls 0x9dec4 (the artist count). |
| 0x1e97bc | JS browser | Calls 0x9dec4. |
| 0x1e7628 | JS browser, 1 | Calls 0xb4038(br, 1). |
| 0x19e790, 0x19e524 | screen, 0x5fba / 0x5fa6 | View 24506 (the title bar) and View 24486 (the Artists screen). |

The JS browser object has the native browser at +0x1c. The title of the Artists screen is `Str -30` ("Artists"). The resource lookup 0x21f254 gets it when the screen opens.

### The native browser

| Offset | Content |
|---|---|
| +0x00 | u8: the type. 1 = a main browser; 2 = a browser that uses the main browser at +0xc9c. |
| +0x10 | The selected artist row (-1 = none). |
| +0x28 | The selected genre (u16 length, then UTF-16 text). |
| +0x228 | The selected artist (u16 length, then UTF-16 text). |
| +0x428 | The selected composer. |
| +0x628 | The selected album. |
| +0xc3c, +0xc40, +0xc44 | Genres: string indexes, letter table, count. |
| +0xc48, +0xc4c, +0xc50 | Artists: string indexes, letter table, count. |
| +0xc54, +0xc58, +0xc5c | Composers: string indexes, letter table, count. |
| +0xc60 to +0xc6c | Albums. |

| Address | Function |
|---|---|
| 0x9bc6c(browser) | Returns the main browser. |
| 0x9bb98(browser) | Returns the track database (the lists). |
| main browser + 0xcf8 | The track data. The artist string pool is at track data + 0xe0. |
| main browser + 0xca0 | The settings and the text compare data. Byte +0xb50 is "Compilations" in Settings. |
| 0xd080c(browser, x, field, sub) | Builds the list of a field. Field 4 = Artist (sort list 7), 2 = Album (6), 0x40 = Genre (9), 0x4000000 = Composer (0x18). If the result is already there (for Artist: +0xc48 is not 0), it does nothing. |
| 0x9dec4(browser) | Builds the Artists list (0xd080c with field 4) and returns the count. |
| 0x9cabc(browser, row, out) | Copies the name of a row from the pool (track data + 0xe0) to `out`. |
| 0x9cb10(browser, row, out) | Gives the letter of a row for the fast scroll. |
| 0xb2620(browser, row) | Selects a row: +0x10 = row, the name goes to +0x228. |
| 0xa34b8(browser) | Clears the Artists list. |
| 0x9c8e4(db, list, 0, n) | Returns entry n of a sort list. |
| 0x9e418(entry) | Returns the track of an entry. |
| 0x1142a8(browser, entry, 0) | The filter. Bit 0 of the result is 1 if the track agrees with the selections. Entry byte +0x1c keeps the result (1 = yes, 2 = no). |
| 0x9f904(track, &text, &units) | The Artist text of a track (pool track data + 0xe0, index at track + 0x2c). |
| 0x9efe0(pool, index, &text, &bytes) | A view of a pool string. |
| 0x91c7c(data, a, a units, b, b units) | The text compare. |
| 0x91d44 | Compares two tracks by one field. |

How 0xd080c builds the Artists list:

1. It goes through sort list 7 (the tracks in the order of the Artist).
2. It keeps the tracks that pass the filter 0x1142a8.
3. It compares the Artist text of each track with the text of the previous track (0x91c7c). A different text starts a new row. The row gets the string index at track + 0x2c.
4. If the database has a letter table for sort list 7 (mhod 53, at db + 0x494 + 4 × 7), it makes the letter table. Without mhod 53, +0xc4c stays 0.
5. If "Compilations" is on, it skips the tracks of compilations (track + 0x15, bit 1).

The rows of the list are string indexes in the artist pool. Thus a list of Album Artist indexes in the same pool operates with the native name, letter and select functions.

The filter compares the selected artist (+0x228) with the Artist text of the track. It gets that text with `bl 0x9f904` at 0x114354.

### The track object

The parser 0xd7888 makes each track with 0xa96c0 (a slab of the database, db + 0x38). Track + 0x10 points to an extension object. 0x88bc0 makes the extension when the track needs one. No free field was found in the track. The loader 0xaf930 calls the parser one time for each load of the database (`bl 0xd7888` at 0xafc8c).

### Proposed hooks

| Hook | Kind | At | Expect | Function |
|---|---|---|---|---|
| A | `b` | 0xd7ea0 | 0xea0000d1 | mhod 22: read the Album Artist into the artist pool (0x10db84). Keep the index in a side table, keyed by the track pointer, only if it is different from the Artist index. Do not change track + 0x2c. |
| B | `bl` | 0xafc8c | 0xeb009efd | Clear the side table, then call the parser 0xd7888. |
| C | `word` | 0x6776f8 | 0x0023ca4c | Menu selection: in a menu list, set "album artist mode" if the selected item has the new label. Clear it for all other items. |
| D | `b` | 0xd080c | 0xe92d5fff | In album artist mode, for field 4: build the list from the Album Artist indexes. Sort with 0x91c7c and make one row for each name. Write +0xc48, +0xc4c (0) and +0xc50. |
| E | `bl` | 0x114354 | 0xebfe2d6a | In album artist mode: give the Album Artist text (or the Artist text) of the track. |
| F | `b` + `chain` | 0x21f254 | 0xe92d40f8 | The lookup: the text of the new label, and "Album Artists" for `Str -30` in album artist mode. |

A `menu_items` key in `patch.json` adds the copy of the Artists item to Menu 24440. It is a general form of `settings_items`.

Answers from the emulator (16 October 2026), with the patch `album-artists` 1.0:

- The browser of the Music menu is a main browser (byte +0 = 1, at 0x13e27a78 in the emulator). Thus 0x9cb10 uses the letter table of the patch, which is 0.
- It is not known if the reset 0x1e7b98 clears the Artists list. Thus hook D clears a list of the other mode itself (0xa34b8). Artists after Album Artists showed the 8 track artists. Album Artists after Artists showed the Album Artists.
- The filter results in the entries did not give old results after a change of the mode: Mike Moe (Artists) showed only Comp Two, and Aardvark (Album Artists) showed Apple One and Apple Two.
- A selection of Genres cleared the mode: Genres > Test showed the 8 track artists.
- The copy of the item needs no change of the position byte (+0x1a). The Music menu with 11 items operated.

### Speed (16 October 2026)

On the real iPod, version 1.0 stopped the iPod for approximately 6 seconds when Album Artists opened. The emulator test with 4000 tracks (400 albums, 320 Album Artists and "Various Artists") found the cause:

| Part of the build (version 1.0) | Calls | Time |
|---|---|---|
| The entries of sort list 7 (the first read also sorts the list) | 4000 | 0.85 s |
| The text sort | 83 000 compares | 0.66 s |
| The join of the equal names | 3999 compares | 0.06 s |

Version 1.0 removed the equal indexes before the text sort. But each track has its own index, also for the same text. Thus the sort compared all 4000 tracks, not the unique names. One compare (0x91c7c) costs approximately 8 µs. The time grows as n × log n with the count of tracks.

Version 1.1 removes the equal texts with an FNV-1a hash of the text in one pass. Then only the unique names go to the text sort. `aa_store` also compares the texts, not the indexes, thus a track whose Album Artist is its Artist gets no entry in the side table.

| Open, 4000 tracks | Version 1.0 | Version 1.1 |
|---|---|---|
| Album Artists, first open after the start | 1.6 s | 0.95 s |
| Album Artists, second open | 1.6 s | 0.11 s |
| Artists (native), for comparison | – | 0.12 s |

Of the first open, approximately 0.85 s is the firmware: the first read of sort list 7 sorts the tracks by Artist. The native Artists list has the same cost if it opens first after a start.

The full test status is in [docs/modifications.md](../docs/modifications.md#album-artists).

## Version 1.2 (16 October 2026)

The owner tested version 1.1 on the real iPod: it works well. The owner then asked for two changes: improve the mode and the list check, and put Album Artists in Settings > Main Menu.

### The mode follows the browse

In version 1.1, `aa_mode` was one global value. Version 1.2 gives the mode to one browser:

- Hook C (menu `activate`) sets `aa_pending` for the new item, and clears `aa_pending` and `aa_browser` for all other items.
- Hook G wraps the browser reset 0x1e7b98 (first instruction `push {r4, lr}`). If `aa_pending` is 1, the native browser (JS browser + 0x1c) becomes `aa_browser`.
- Hooks D and E use `browser == aa_browser`. Hook E is a wrapper that passes r5 (the browser in the filter 0x1142a8 at 0x114354).

Emulator results with `IPODFW_MARK_AT=0x1e7b98`:

| Selection | Runs of 0x1e7b98 |
|---|---|
| Music > Album Artists, Artists, Albums, Songs | 1 at the open, none in the levels below |
| Main menu > Album Artists | 2 |
| Music > Composers, Genres, Playlists | 0 |

Thus a reset without a pending selection must not clear the mode (the second reset of the main-menu item cleared it in a first build). And the clear in hook C is necessary, because some browses do not run the reset.

### The exact list check

FindConstant 0xc48 shows that only 0xd080c (the build) and 0xa34b8 (the clear) write browser + 0xc48. Hook H wraps 0xa34b8 (first instruction `push {r4, r5, r6, lr}`): if the clear frees `aa_list`, `aa_list` becomes 0. Hook D then compares only the pointer. Version 1.1 also compared the count, because it did not know when the firmware freed the list.

### Album Artists in the main menu

| Fact | Evidence |
|---|---|
| The main menu is Menu 24094. Each item has its label as the key, for example 0x5f7c = Artists. | Static, Emulator |
| 0x105a04 maps a label to one bit of the main menu mask. 0x193470 (visible) and 0x19351c (set) are its only callers. | Static |
| The mask is at (main browser + 0xca0) + 0xb34. Emulator default: 0x0e180201. Bits 0x4000, 0x20000000, 0x40000000 and 0x80000000 are not used. | Static, Emulator |
| The load of old preference versions merges new default bits with the mask 0x1fffffff (0xaf838). The bits 0x40000000 and 0x80000000 are outside this merge. | Static |
| The UI script shows or hides each Apple item of the main menu with 0x19ed58 (screen, menu, label, 3, visible): two times at the start, and each time the main menu shows. A change in Settings > Main Menu does not call it. | Emulator |
| A copy of the Artists item in Menu 24094 showed in the main menu also when its bit was 0, because the script does not know its label. | Emulator |
| Settings > Main Menu is Menu 24600 (28 rows). Each row has the settings key 0x6000 + the label of its item, for example 0x60005f7c. | Static, Emulator |
| The firmware settings get (0x190b00) knows only its own keys. For an unknown key the row showed no value. 0x5f90 (a label with no bit and no string) also gave no value. | Emulator |
| The list asks the value text of a row with the resource lookup ('Str ', key). With the key 0x7e03, the lookup hook of the patch answered with the label text before the settings object. | Emulator |

The method in version 1.2:

1. `menu_items` puts a copy of the Artists item into Menu 24094 (label 0x7e03), and a copy of the Artists row into Menu 24600 (label 0x7e04, key 0x60007e05).
2. Hooks I and J (the `bl` at 0x193488 and 0x19353c) map 0x7e03 to bit 0x40000000.
3. Hook K wraps 0x19ed58. When the script sets Artists (0x5f7c) in Menu 24094, the patch also sets 0x7e03 from the bit.
4. Hooks L and M (settings get and set, with `chain`) handle the key 0x7e05: On or Off, and the change of the bit with 0x19351c and the 'Bool' notice. For other questions, hook L asks the firmware with the key 0x5f7c.

Emulator result: the row showed Off, a selection changed it to On, and the main menu then showed Album Artists after Videos. The main menu item opened the Album Artists list. The emulator keeps no settings after a cold start (the Language screen showed again), thus the save of the bit is not tested.

### The save of the settings (real iPod, 16 October 2026)

The owner tested version 1.2 on the real iPod. After Settings > Main Menu > Album Artists = On, a restart with Menu+Select removed the item again. The owner also set Songs to On (an Apple row): it also did not stay. Thus the cause is the save of the settings, not the patch.

Ghidra:

| Address | Function |
|---|---|
| 0xbbf1c | (settings): if the byte "changed" (+0xb74) is not 0, it writes the settings (0xbbdf8). 0x19351c sets this byte at each change of the main menu mask. |
| 0xbc094 | (app + 0x1c): saves all: the database, the settings (0xbbf1c) and other data. |
| Callers of 0xbbf1c | 0xbc094, and the sleep sequence 0x1ee8d0 (from the timer handler 0x1d8cd0). |
| Callers of 0xbc094 | `save_all` 0x1ee8b8 (from the application event 0x1eccdc, for example a disk change), 0xb4fe4 (from 0x1ec2c8) and 0x248440. The triggers of the last two are not examined. |

Menu+Select restarts the iPod at once. It runs none of these functions. Thus each change of a setting since the last sleep is lost. The settings stay if the iPod sleeps (hold Play) or connects to a computer before the restart.

The owner then asked for a separate patch, [instant-save](../patches/instant-save/). It hooks the first instruction of the setter 0x19351c and calls 0xbbf1c after each change. A trial link on 16 October 2026 measured: inside `album-artists` 40 bytes more (no change of the image end); as a separate patch 36 bytes, but the image grows by 2 KB, because each extended patch starts at the next 0x800 step. The owner selected the separate patch. Emulator: each change ran 0xbbf1c and the write 0xbbdf8 one time, and the drive got WRITE DMA commands.

Real iPod 5.5G (owner, 28 October 2026, `instant-save` version 1.0): the patch operates.

Real iPod 5.5G (owner, 28 October 2026): `album-artists` version 1.3 operates.
