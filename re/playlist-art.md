# Playlist collages made on the iPod: feasibility research

This note records the research of 27 October 2026. The question: can the `album-art` patch make the 2 × 2 collage of a playlist on the iPod, without the app file `iPodFirmAlbumArt`? The firmware is RetailOS 1.3 for the iPod Video. Addresses are osos offsets. The owner first asked for the research only. Then the owner asked for the implementation: refer to "Version 3.0".

## The answer

Yes. The work is of medium size. Every structure that the patch needs is now known and confirmed in the emulator:

- the list of all playlists;
- the name of each playlist;
- the tracks of each playlist, in the playlist order;
- the album of each track.

The patch already has the album thumbnails in memory (the cache of version 2.8 and later). Thus a collage needs no disk read: four 20 × 20 thumbnails become four 10 × 10 quarters with a 2 × 2 average.

## What the app does now

`MusicImport.playlistArt` and `MusicImport.collage` (mac/Sources/IPodFWKit/MusicImport.swift):

1. A playlist with a custom image uses the custom image.
2. Else the app takes the tracks in the playlist order. It keeps the first 4 different albums that have a cover.
3. With 4 covers, it makes a 2 × 2 collage: the covers 1 and 2 in the top row, 3 and 4 in the bottom row.
4. With 1 to 3 covers, it uses the first cover alone. With no cover, the playlist gets no picture.

The app cannot give On-The-Go a picture, because On-The-Go is not in iTunesDB.

## The structures

The database (db) is library + 0xcf8. The library is `lib_resolve(*(PROVIDER + 0x1c))`, as in `album_art.c`.

| Value | Meaning | Evidence |
|---|---|---|
| db + 0x28 | The count of playlists | Static (0xb6b54), Emulator |
| db + 0x2c | The first playlist. The list is singly linked: playlist + 0x00 is the next playlist, 0 at the end. 0x88ef0 adds a playlist at the end. | Static (0xb6b54, 0x88ef0), Emulator |
| db + 0x30 | The master playlist | Static (0x93ff0), Emulator |
| playlist + 0x0c | The db | Static (0xb6b54), Emulator |
| playlist + 0xb4 | A string pool in the playlist object. 0x1012b8 sets it up with 0x947f8. | Static (0x1012b8) |
| playlist + 0xe0 | The pool index of the name. 0xf4340 stores the mhod-1 string with 0x88a00(playlist + 0xb4, string, playlist + 0xe0). Read the name with 0x9eff8(playlist + 0xb4, index, buffer, &length, maximum). | Static (0xd6de8, 0xf4340, 0x88a00), Emulator |
| playlist + 0x28 | The root node (made by 0xd1df0 in 0x1012b8) | Static, Emulator |
| root + 0x20 | The first item | re/play-next.md, Emulator |
| root + 0x32 (u16) | The count of items | re/play-next.md, Emulator |
| item + 0x08 | The next item (the playlist order) | re/play-next.md, Emulator |
| item + 0x20 | The track | Static (0x88944), Emulator |
| track + 0x00 | The db. A group parent of a podcast playlist has a different value at this position (refer to "Risks"). | Static (0x88944), Emulator |
| track + 0x34 | The album pool index (pool db + 0x138) | album_art.c, Emulator |

The pool has the layout that 0x88a00 and 0x885ec use: + 0x08 is a handle of the entries ({offset, length}, 8 bytes each, index 1 first), + 0x10 is a handle of the UTF-16 data.

## Emulator results (27 October 2026)

The instrumented emulator with album-art 2.9 and a test library from `ipodfw.itunesdb.make_library` (60 tracks, 6 albums of 10 tracks, the playlists "Test Album 1" with every 7th track and "Road Trip" with every 3rd track from the end). A script read the memory with `peek` only.

The list at db + 0x2c had 6 playlists (db + 0x28 = 6):

| Playlist | Name index | Items (root + 0x32) | Shows in Music > Playlists |
|---|---|---|---|
| The master playlist | 3, "iPod" | 60 | No |
| Test Album 1 | 3 | 9 | Yes |
| Road Trip | 3 | 20 | Yes |
| New Voice Memos | 3 | 0 | No |
| (no name) | 0 | 60 | No |
| On-The-Go (= library + 0xce0) | 3 | 0, then 1 after a hold of Select on a song | Yes |

The walk gave the albums in the playlist order:

- Test Album 1: albums 1, 1, 2, 3, 3, 4, 5, 5, 6. The first 4 different albums are 1, 2, 3 and 4. This agrees with the tracks 1, 8, 15, …, 57 of the definition.
- Road Trip: albums 6, 6, 6, 6, 5, 5, 5, 4, 4, … This agrees with the tracks 60, 57, 54, … of the definition.
- On-The-Go after the hold: 1 item, Test Album 1.

Each track had track + 0x00 = db.

The old TestLibrary of the Emulator pane (iTunesDB of 1 October 2026) has no playlists that the firmware loads. Use a library from `make_library` for a playlist test.

## The owner's iPod

The iTunesDB of the owner (read on 27 October 2026, read-only) has 2 playlists: "The Boys (Phoebe Bridgers Extended Unive…" (29 tracks) and "Recently Added" (191 tracks). Neither is a smart playlist or a podcast playlist.

## Risks and limits

- **Podcast playlists.** The parser puts a mhip with a group ID under a group parent (0x10d228, 0x94348). Then the node at root + 0x20 is a group, and node + 0x20 is not a track. The patch can test track + 0x00 == db and go into the group. Not tested: the test library has no podcasts.
- **Smart playlists.** The parser keeps the rules (mhod 50 and 51, 0xb3bc4) and still reads the mhips. Thus the items exist. The iPod can evaluate a live smart playlist again (0xbb28c). Then the items change. Not tested.
- **Changed playlists.** On-The-Go changes while the iPod runs. The patch must make the collage again when the item count (root + 0x32) changes.
- **Names.** The row gives only the name. Two playlists with the same name get the same picture. The app file has the same limit.
- **Hidden playlists.** The master playlist, "New Voice Memos" and the playlist with no name do not show in the list. A match by the row name never finds them.
- **The order with the app file.** For albums, version 2.9 uses the app file first. For playlists, the same order keeps the custom images of the owner.

## Cost

- The walk stops at the 4th different album. Each track needs `album_hash`: two tracks of one album can have different pool indexes (emulator, 27 October 2026), thus a compare of the pool index (track + 0x34) is not enough. A playlist with many tracks of the same album at its start needs a longer walk. Each step reads 2 words.
- A collage needs 4 thumbnails of 20 × 20 from memory and 400 pixel averages. It is 800 bytes.
- The patch can make a collage at the first draw of its row and keep it with the item count.

## Version 3.0: the implementation (27 October 2026)

The owner asked for the implementation on the branch `playlist-art`, with the first 4 albums (not random). `album_art.c`:

- `playlist_collage` keeps 16 slots: the hash of the playlist name, the playlist, its item count and the 20 × 20 collage. It makes a collage at the first draw of the row, and again when the item count changes.
- `find_playlist` reads each name with `pool_hash(playlist + 0xb4, *(playlist + 0xe0), PLAYLIST_BASIS, …)` and compares it with the hash of the row.
- `make_collage` walks the items (it goes into a podcast group) and compares the album hashes. `album_px` gives a thumbnail in the order of the album rows: the file, the cache, the artwork. While the wheel moves, a thumbnail that needs the disk makes the row wait.
- `avg4` makes each pixel of a quarter from 4 pixels (RGB565, the channels spread in one word).
- The order for a playlist row: the file of iPodFirm first, then the collage of the patch.
- After a USB session, `free_collages` frees the slots. A different db pointer also frees them.
- The measurement: record version 6 adds the timer `collage` and the counter `collage_hits`.

The size of version 3.0 was 16400 bytes (version 2.9: 14548 bytes).

A correction found in the test: the first build compared the album pool indexes. "Road Trip" then showed album 6 four times. Two tracks of one album can have different indexes in the album pool. The patch now compares the album hashes.

### Emulator test (27 October 2026)

A library from `make_library` (60 tracks, 6 albums, 2 playlists) with an app file that has only the 6 album covers, in 6 plain colours. Music > Playlists showed:

| Row | Collage | Expected |
|---|---|---|
| Test Album 1 | red, green / blue, yellow (albums 1, 2 / 3, 4) | albums 1, 2, 3, 4 |
| Road Trip | cyan, magenta / yellow, blue (albums 6, 5 / 4, 3) | albums 6, 5, 4, 3 |
| On-The-Go, empty | no picture | no picture |
| On-The-Go after a hold of Select on Test Song 1 | red (album 1 alone) | the first cover alone |

All 81 Python tests and all 123 Swift tests passed. Not tested: the artwork and the cache as the source of a collage (the test library has no artwork), a podcast playlist, a smart playlist, and the real iPod.

### Real iPod, version 3.0 (27 October 2026)

The owner reported: "the albums section isn't preloading artwork, I have to scroll, wait for them to load, scroll and wait again". The stats file (4 records):

| Value | Result |
|---|---|
| The cache load | 1 time, 14 µs: it stopped before a file open. `cache_state` −1 |
| The background fill | `prefills` 0. `cache_written` 1 (the fill was marked as not possible) |
| The covers | 51 fills from the artwork, each at a stop of the wheel; 441 waits |
| The first collage | 1.78 s: `build_art` 0.76 s and the open of `F1028_1.ithmb` 0.93 s |

The cause: the owner opened Playlists before Albums. The collage called `cache_load`. The stamp needed the album list of the library (library + 0xc60), and the library makes that list only at the first open of the Albums list. The emulator confirmed it: before Albums, library + 0xc60 is 0. Then `albums_state` became −1, and `albums_ready` never tried again. Thus the cache was not valid for the session, and the background fill had no album list.

### Version 3.1: the correction (27 October 2026)

1. The stamp uses the album pool of the database (db + 0x138), not the album list of the library. The pool exists from the start. The patch hashes the length and the UTF-16 bytes of each entry. The old cache files have a different stamp, thus the patch makes the cache again one time.
2. `albums_ready` tries again after a failure when the album list of the library exists.
3. If the database is not ready, `cache_load` leaves `cache_state` at 0 and tries again later.

The size is 16552 bytes.

Emulator test (FolderLibrary, 138 albums, `iPodFirmAlbumArt` present; Playlists first, then Albums):

| Start | Result |
|---|---|
| First | At Playlists: the stamp was known (cache load 6.7 ms), no cache file. At Albums: `albums_state` 1, 138 background fills, the cache written (21.5 ms, 0 errors) |
| Second | At Playlists: `cache_state` 1, 138 albums. At Albums, 60 detents fast: no table, no fill, 0 waits |

Real iPod (27 October 2026): the owner flashed 3.1 with "iPodFirm Playlist Art Test" 0.1.162 and reported: "that works well". The stats of this test are not recorded.

## Implementation outline (done in version 3.0)

1. Work on a new branch `playlist-art` in `../iPod5.5Firm-playlist-art`. Use the test app "iPodFirm Playlist Art Test".
2. At a playlist row (element 0x6425): look in the app file first (custom image or app collage). If the row is not there, find the playlist with the same name in the list at db + 0x2c.
3. Walk the items. Keep the first 4 different album pool indexes that have a thumbnail (the cache, the artwork or the app file). Make the collage, or use the first thumbnail alone.
4. Keep a small table: the hash of the name, the item count and the 800-byte collage. Free it after a USB session (`db_loaded`).
5. Give On-The-Go a collage also.
6. Re-use `album_hash`, `cache_find`, `art_find`, `art_thumb`, `pixels` and `draw_thumbnail` from `patches/album-art/album_art.c`.
7. Increase `version` to 3.0, measure `size`, and update the patch.json text, the text of `AlbumArtSections` and the documents in the table of `docs/README.md`.
8. Test in the emulator with a `make_library` library without the app file. Then test on the real iPod.
