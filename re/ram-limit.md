# The track limit of the 32 MB iPod Video

This document is a feasibility study. A user asked how Rockbox avoids the RAM limit on an iPod Video with 32 MB of RAM. The owner asked if iPodFirm can do the same. The solution must operate completely on the iPod. A computer tool must not change iTunesDB or prepare files.

Status: research only (29 October 2026). There is no patch. The owner stopped the emulator limit tests before they gave a result. The values in this document come from Ghidra, from the Rockbox source and from emulator tests with 1,000 and 5,000 tracks.

## Summary

- The limit is a RAM limit. RetailOS keeps the whole music database in RAM. Other people who researched the limit agree.
- Rockbox has no special RAM method. It does not use iTunesDB. Its database is a set of files on the disk, and it reads each entry from the disk.
- RetailOS already finds the RAM size itself. Thus the Rockbox RAM test gives nothing to RetailOS.
- RetailOS already keeps one copy of each equal string on a 32 MB iPod (option E). It turns this off only on a 64 MB iPod. Thus option E gives no more tracks on a 32 MB iPod.
- An on-iPod patch can increase the limit a little, but it cannot remove it. The remaining option is to skip strings that the iPod does not show (option B). The gain is small, and the risk is not zero.
- Tracks on the disk, as in Rockbox, are not practical in RetailOS.

## What Rockbox does

Source: [Rockbox/rockbox](https://github.com/Rockbox/rockbox), master, read on 29 October 2026.

| Item | File | What it does |
|---|---|---|
| One build for 32 MB and 64 MB | `tools/configure` | `memory=64 # always. This is reduced at runtime if needed`. |
| The RAM test | `firmware/target/arm/pp/crt0-pp.S` | Writes 64 to 0x11FFFFFF, then 32 to 0x13FFFFFF. On a 32 MB iPod both addresses are the same cell, so the cell holds 32. |
| The result | `firmware/target/arm/pp/system-pp502x.c` | Reads the byte at 0x01ffffff into `probed_ramsize`. |
| The smaller buffer | `firmware/core_alloc.c` | On a 32 MB iPod, `audiobufend` becomes 32 MB lower. |
| The database | `apps/tagcache.c` | A set of files on the disk. The copy in RAM (`tc_stat.ramcache`) is optional. |

The RAM test only makes one build operate on both boards. Rockbox has no track limit because its database stays on the disk. It does not read iTunesDB.

## What other people found

These results come from user reports. We did not verify them.

- [iFixit: Highest possible capacity for a 30gb iPod 5th gen](https://www.ifixit.com/Answers/View/50726/Highest+possible+capacity+for+a+30gb+iPod+5th+gen):
  - A 32 MB board: about 17,000 to 20,000 tracks. Some reports give 25,000 to 30,000. The limit changes with the length of the metadata.
  - A 64 MB board: about 40,000 to 50,000 tracks.
  - Past the limit, the Apple logo shows again and again, the iPod starts only in disk mode, or the iPod shows no songs. A restore repairs it.
- [iFixit: Which gen 5.5 iPod board has 64MB](https://ts.ifixit.com/Answers/View/118149/Which+gen+5.5+iPod+board+has+64MB): users report 32 MB for the 30 GB models and 64 MB for the 60 GB and 80 GB models. Refer to [Which iPod has 32 MB](#which-ipod-has-32-mb).
- [iFlash compatibility](https://www.iflash.xyz/store/iflash-compatibility/): 10,000 to 30,000 tracks for the 30 GB model. The limit is "a function of the iTunes database size and the RAM".
- Apple gives "7,500 songs" for the 30 GB model. This is a storage estimate (4 minutes at 128 kbit/s), not a limit.

## Which iPod has 32 MB

In this repository, "a 32 MB iPod" means an iPod with 32 MB of RAM. It does not mean a specific drive size. The size of the drive does not prove the size of the RAM.

The sources do not agree about the 30 GB model. We did not verify them on a real 30 GB iPod.

- [EveryMac](https://everymac.com/systems/apple/ipod/specs/ipod_5thgen.html) and the iFixit answers give 32 MB for the 30 GB model.
- The [iPodWiki](https://ipodwiki.com/wiki/IPod_video) table gives 32 MB for the 30 GB model. Its text about the September 2006 revision gives "32MB of additional RAM". Thus the two parts of that page possibly do not agree.
- The iFixit answers say that one board part number has the two RAM sizes: 820-1763-A on the 5G and 820-1975-A on the 5.5G.
- A board replacement can also change the RAM of an iPod.

To find the RAM size of an iPod, use one of these methods:

- Read the value `ram=` in the first lines of the log from `playback-log` or `diagnostic-log`.
- Run `SDRAMQuickTest` in the diagnostic mode of the iPod. The path is NTF, then AutoTest. This path comes from iFixit users. We did not test it.

## Question 1: how RetailOS finds the RAM size

RetailOS does not test the RAM. The boot loader gives the size in the SysInfo block. Evidence: Static.

| Address | What it does |
|---|---|
| 0x13bc | The start code. It finds the SysInfo block in IRAM: the tag 'SysI' (0x53797349) at 0x4001ff18, and a pointer after the tag. |
| 0x13e8 | `ldr r3, [r0, #0xe0]` (bytes `e0 30 90 e5`): reads the SDRAM size from SysInfo + 0xe0. |
| 0xe6c | Converts the size to a code (nibble 2 of a configuration word). It uses the size table at 0x16d8: 0, 0x80000, 0x100000, 0x200000, 0x400000, 0x800000, 0x1000000, 0x2000000, 0x4000000, 0x8000000. |
| 0xdf8 | Adds the sizes of the four banks and writes the RAM top to struct + 0x20. |
| 0xc90 | Sets the image region (8 MB, from the image end 0x7358c0) and the data region (from 0x10800000, length 0x20e294). |
| 0x1658 | Copies the struct (0x90 bytes) from IRAM 0x40006000 to 0x14983060. |

Thus one osos image operates on both boards. The Rockbox RAM test does the same work in a different way.

## Question 2: what uses the heap

The heap setup:

1. 0xc2bbc calls 0xa07b4. That function calculates the start (struct + 0x28 AND 0xfbffffff) and the size ((struct + 0x20 − struct + 0x24) AND 0x3ffffff). It writes them to 0x10883614 + 0x1b4 and + 0x1b8.
2. 0x10b190 calls 0xdf0c0. That function rounds the end down to 1 MB and subtracts 1 MB for the MMAP window at 0x18000000.
3. 0xd2e2c adds the region to the heap through 0x1ac448. A heap has a maximum of 10 regions.

The heap object is at 0x10870154. The pointer to it is at 0x1081da00. 0xc2e0c makes it when the firmware first needs it (0x1aca4c, then 0x1ac944). 0xc7444 gives the free bytes. Evidence: Static.

Emulator results with stock 1.3 and test libraries (about 1,250 bytes for each track in iTunesDB):

| RAM | Tracks | Heap total | Used | Free |
|---|---|---|---|---|
| 64 MB | 1,000 | 55,519,024 | 52,237,660 | 3,281,364 |
| 64 MB | 5,000 | 55,519,740 | 52,410,584 | 3,109,156 |
| 32 MB (test patch) | 1,000 | 21,964,832 | 18,679,080 | 3,285,752 |

The heap of the 32 MB copy is 33,554,192 bytes smaller: 240 bytes less than 32 MB. The heap total also changes by some hundred bytes between two runs. The free memory stays at about 3 MB for all library sizes. Thus a large buffer becomes smaller when the library becomes larger. It is probably the music buffer, but we did not find the function that sets its size.

During a load of 20,000 tracks, the free memory was 4.59 MB on 32 MB and 4.58 MB on 64 MB. Thus the free value alone does not show how near the iPod is to the limit.

## Question 3: how much RAM each track uses

Evidence: Emulator, 64 MB with 5,000 tracks. The database object was at 0x13e2ea60.

| Item | Bytes | Bytes for each track |
|---|---|---|
| Track object (slab at db + 0x38: 272 bytes, 100 for each chunk) | 1,360,000 | 272 |
| String pools (index, reference counts and text) | 1,047,936 | 210 |
| Path, sorted lists and playlist items | Not measured | — |

Each used pool had 5,000 entries and an index of 40,000 bytes (8 bytes for each track). The text sizes were: title 138,752; artist and composer 146,944; artist sort 196,096; album 138,752; genre 40,448; file type 146,944.

The test library has short strings. A real library has longer titles and paths, so it uses more RAM for each track. With about 1 KB for each track, a 32 MB iPod reaches its limit at about 18,000 tracks. This agrees approximately with the community results.

## Question 4: what fails at the limit

- The track parser 0xd7888 gets each track object from the block allocator 0xa96c0 (then 0xa8e8c). A chunk is count × size + 0x24 bytes and comes from 0xa8178.
- If the allocation fails, 0xd7888 returns −0x6c (−108, memFullErr).
- The load 0xb4a64 then tries `System\Control\iTunes\iTunesDB`. If that also fails, it makes an empty database (0xa9348). This agrees with the report "the iPod shows no songs".
- 0xb4a64 measures the free heap before and after each load. It writes the usage-log events 0x16 "Music Database Size", 0x17 "Photo Database Size" and 0x18 "Artwork Database Size".

Evidence: Static. We did not find the cause of the restart loop. Probably a different allocation fails after the load, when the music buffer or a list needs memory.

## Question 5: where the code reads the track data

The strings are in string pools. A pool has these fields:

| Offset | Content |
|---|---|
| + 0x04 | Flags. Bit 0 = share: search for an equal string before the add, and keep a reference count for each entry. |
| + 0x08 | Handle of the index (8 bytes for each entry: offset and length). |
| + 0x0c | Handle of the reference counts. |
| + 0x10 | Handle of the text. |
| + 0x14 | The count of entries. |

The data uses relocatable handles. The pool functions are 0x885ec (add), 0x9eff8 (get: copies the UTF-16 text), 0xa71d8 (lock), 0xb9ef4 (unlock), 0xe1cc8, 0x95a80, 0x95ad0, 0x10a650, 0x10ed14 and 0xb3e0c. Evidence: Static.

- 0x9eff8 has 6 calls in 4 functions: 0x9f0c4, 0xb5828, 0x9c288 and 0x21c1e0.
- 0x885ec has 7 callers.
- The track objects are used in many more places: the lists, the play list, shuffle, On-The-Go, the artwork and the patches.

### The share flag depends on the RAM size

0x105cb8 makes the pools of the database with 0x947f8 (pool, flags). Evidence: Static.

| Pool | Flags | Pool | Flags |
|---|---|---|---|
| db + 0xb4 title | 0 | db + 0x1e8 EQ | 1 |
| db + 0xe0 artist, composer | 1 | db + 0x214 comment | 0 |
| db + 0x10c artist sort | 1 | db + 0x240 category | 0 |
| db + 0x138 album | 1 | db + 0x424 description | 0 |
| db + 0x164 grouping | 1 | db + 0x450 | 0 |
| db + 0x190 genre | 1 | db + 0x47c type 19 | 1 |
| db + 0x1bc file type | 1 | db + 0x4a8 type 20 | 0 |

0x947f8 then clears bit 0 if `FUN_1009d9d0()` is more than 0x3ffffff. 0x9d9d0 returns SysInfo + 0xe0, the RAM size. Thus:

- On a 32 MB iPod (0x2000000), the shared pools keep one copy of each equal string.
- On a 64 MB iPod (0x4000000), no pool shares. Each track has its own copy.

The search in 0x885ec is linear: it compares the new string with each entry of the pool. Thus on a 32 MB iPod, the load time increases with the tracks × the different strings. Apple probably turned the share off on 64 MB to make the start faster.

The emulator results in this document come from 64 MB, or from the 32 MB copy below. That copy did not change SysInfo + 0xe0, so its pools also did not share.

### Remove and replace

- 0x95ad0 (pool, index) removes one entry. If bit 0 is set, it decreases the reference count and frees the entry only at 0. It has 22 calls.
- 0xb3e0c (pool, text, length, &index) replaces an entry: 0x95ad0, then an add.
- 0xffaf4 removes all strings of one track. Only 0xfb288 calls it, from the message handler 0xb6930. It does nothing if db + 0x19 bit 1 is set.

### The readers of the unshared strings

Each text has a read function: comment 0x9f988 and 0x9f99c, category 0x9f93c and 0x9f950, grouping 0x9fbd8 and 0x9fbec, description 0x9fa3c. Their callers are:

- 0x91d44: compares two tracks, field by field.
- 0x92c74 and 0xbadac: copy the strings of a track to a different record.
- 0x21de3c, 0x21ded4, 0x21e054, 0x21c1e0, 0x21c094 and 0x21c148: methods of the general track interface. The vtables are at 0x66bfd8 and 0x6765f8.

The track interface gives each field to other parts of the firmware. Static analysis cannot show that the iPod never uses these fields. Possible users are the podcast screens, accessories (iAP) and smart playlists that update on the iPod.

The jump table of the mhod types is at 0xd7e48. The parser keeps these types:

| Type | Content | Code | Pool |
|---|---|---|---|
| 1 | Title | 0xd7ee4 | db + 0xb4 |
| 2 | Path | 0xd7ec8 | 0x1179bc |
| 3 | Album | 0xd7f14 | db + 0x138 |
| 4 | Artist | 0xd7f58 | db + 0xe0 |
| 5 | Genre | 0xd7fa0 | db + 0x190 |
| 6 | File type | 0xd7fd0 | db + 0x1bc |
| 7 | EQ setting | 0xd7fe4 | db + 0x1e8 |
| 8 | Comment | 0xd8078 | db + 0x214 |
| 9 | Category | 0xd808c | db + 0x240 |
| 12 | Composer | 0xd7f88 | db + 0xe0 |
| 13 | Grouping | 0xd7f44 | db + 0x164 |
| 14 | Description | 0xd80a0 | db + 0x424 |
| 16, 17 | Podcast data | — | — |
| 19 | — | 0xd8194 | db + 0x47c |
| 20 | — | 0xd81b8 | db + 0x4a8 |

The code at 0xd81ec skips the types 10, 15, 18, 21, 22, 24, 25 and 27 to 31. The code at 0xd8204 handles the types 0, 11, 23 and 26.

## Options

All options operate on the iPod. "Tracks added" is an estimate for a 32 MB iPod with a typical library.

| Option | What it does | Tracks added | Work | Risk |
|---|---|---|---|---|
| A. Smaller music buffer | Use a smaller music buffer on a 32 MB iPod. | Unknown | Medium | Medium. We did not find the buffer size. A flash iPod reads more frequently, which costs little. |
| B. Skip unused strings | The parser skips comment (8), category (9) and grouping (13). | Small: 0 to 100 bytes for each track, it depends on the library | Low | Medium. A hook in the jump table at 0xd7e48. The menus do not show these fields, but the track interface gives them to other code. A smart playlist with a rule on these fields can change. Keep the description (14), because the podcast screens can show it. |
| C. Strings on the disk | At the load, the iPod writes the strings to its own file and keeps only an offset in RAM. A small cache serves the lists. | Large (about 200 bytes for each track or more) | Very high | High. All pool functions must change. The lists read many strings at each scroll. |
| D. Tracks on the disk (full Rockbox method) | Keep the track objects on the disk. | Very large | Not practical | Very high. Too many functions use the track objects directly. |
| E. One copy of each equal string | RetailOS already does this on a 32 MB iPod. A patch can do it also on a 64 MB iPod, with a hash table in front of the slow search. | None on 32 MB. Medium on 64 MB. | Medium | Medium. The reference counts make a remove safe. |
| F. A fast share search | A hash table in front of the linear search in 0x885ec. | None | Medium | Medium. It makes the start of a 32 MB iPod with a large library faster. It does not add tracks. |

On a 64 MB iPod, the file type text alone used 147 KB for 5,000 tracks. A 32 MB iPod keeps only one copy of each file type.

## Recommendation

1. Do not port the Rockbox RAM test. RetailOS already gets the size from SysInfo.
2. The full Rockbox method (option D) is not practical.
3. Option E gives no tracks on a 32 MB iPod, because RetailOS already shares strings there.
4. Option B gives a small gain. It is useful only if the library has many comments. Test smart playlists and accessories before a release.
5. Option A is the only option that can give a large gain on 32 MB without the Rockbox method. It needs more research: find the function that sets the size of the music buffer.
6. Options E and F can help a 64 MB iPod with a very large library, and the start of a 32 MB iPod. They do not help the 32 MB limit.

Each patch must have a user interface in the iPodFirm app, a `version_letter`, a `version` and a measured `size`.

## Status and next decision

Status on 29 October 2026:

- The research is complete. There is no patch.
- The branch `string-share` (worktree `../iPod5.5Firm-string-share`) exists for a possible patch. It has no patch code.

The owner must select one of these steps:

1. Research option A: find the function that sets the size of the music buffer. This is the only option that can give a large gain on a 32 MB iPod.
2. Make a patch for options E, F and B: more tracks on a 64 MB iPod, a faster start on a 32 MB iPod, and a small gain from the skipped strings.
3. Make a patch for option B only: a small patch with a small gain.
4. Stop and keep the research.

## How to copy a 32 MB iPod in the emulator

The owner has only a 64 MB iPod. To copy a 32 MB iPod, change osos at 0x13e8:

| | Bytes | Instruction |
|---|---|---|
| Original | `e0 30 90 e5` | `ldr r3, [r0, #0xe0]` |
| 32 MB | `02 34 a0 e3` | `mov r3, #0x2000000` |

The heap total then becomes approximately 32 MB smaller (33,554,192 bytes in the test). This copy is not complete: 0x9d9d0 reads SysInfo + 0xe0 directly, so the pools do not share as on a real 32 MB iPod. The emulator option `trace --sysinfo=SIZE` also sets the size, but `ipod-gui` (`emu.rs`) always uses 0x04000000.

CAUTION: Do not set `IPODFW_RESET_AFTER` with a large library. The start takes more than 10⁹ instructions, and a start check then restarts the emulated iPod again and again. Refer to [shuffle.md](shuffle.md).

The emulator is slow with a large library (about 2 million instructions each second). A start with 20,000 tracks takes more than one hour.

## Open questions

- Which allocation fails first at the limit, and why the iPod restarts.
- Which function sets the size of the music buffer.
- How much RAM the path pool, the sorted lists and the playlist items use.
- Where the usage log is on the disk. It records "Music Database Size" on the real iPod.
- Which code uses the comment, category and grouping through the track interface.
- How long a 32 MB iPod with a large library takes to start, because of the linear search.
