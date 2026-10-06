# Album Artist: research notes

This document records the research for an `album-artist` patch. The firmware is Apple RetailOS 1.3 for the iPod Video.

**Status (6 October 2026): research only.** The owner decided not to add the patch to `patches/` now. This document keeps all the data to make it later: the hooks, the code, the `patch.json` and the test results. The emulator test used a test build of Hook 1. The sort-index correction is not tested.

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
| 0x885ec | Stores a string in a pool (pool, text, length, slot). It writes 0 to the slot first. If the pool has the same text, it adds 1 to the reference count and writes that index. An empty text gives the index 0. |
| 0x907f4 | Reads the artist of the track (slot + 0x2c), sets bit 4 of byte +0x15, and calls 0x1114dc. |
| 0x1114dc | Makes the sort key of the artist (pool db + 0x10c, slot + 0x30). |
| 0xdc6a8 | Skips bytes in the file. |

The function 0xd6de8 also reads mhod strings, but only the playlist names.

## The proposed hook

The hook replaces the jump table entry for type 22 (0xd7ea0) with a `b` to `hook_album_artist`. The hook does the same steps as the code for type 4. The Album Artist then replaces the Artist of the track. If the Album Artist is empty, the hook puts back the old Artist.

A second store to the Artist slot keeps one extra reference to the old Artist in the pool. The memory use is small. The Artists list does not show these names, because the list comes from the tracks, not from the pool. The emulator test confirms this.

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
