# Notes music links (RetailOS 1.3, iPod Video)

A user shared the app Folders4Playlist by u/Linusssk. The app makes playlist folders with the stock Notes reader. It writes a tree of `index.linx` files into `/Notes`. Each playlist is a link `ipod:music?playlist=NAME`. The problem of the author: the selection of a playlist starts playback at once, and the user cannot scroll the songs.

Status (5 November 2026): the parser of the links is known (Ghidra). The owner tested the links in the emulator with the stock firmware. A list of songs with the keys `playlist` and `song` gives the best result. Not tested on the real iPod.

## Comparison with Playlist Folders

| Item | Folders4Playlist | `playlist-folders` 0.8 |
|---|---|---|
| Method | Stock Notes links | Firmware patch on the Playlists screen |
| iPod | All iPods with Notes | 5G and 5.5G, firmware 1.3 |
| Select a playlist | Playback starts | The songs of the playlist show (stock) |
| Folder depth | Any depth | One level. A nested folder goes into its top-level folder. |
| Source of the folders | The Music app (AppleScript) | `iTunes Library.itl`, the Music app, or the editor |
| Playlist match | Name only | Persistent ID, then name |
| Existing notes | The app deletes all of `/Notes` | Not changed |

The app "Import from Music" of iPodFirm comes from this comparison. Refer to [playlist-folders.md](playlist-folders.md#itunes-folders).

## The data

The start code copies a data block from osos 0x6a1170 to RAM 0x10822ecc (difference 0x10181d5c). Thus Ghidra finds no reference to the file address of the strings. The code loads the RAM address of a table base. Search for the RAM address.

| osos | RAM | Content |
|---|---|---|
| 0x6a1178 | 0x10822ed4 | The file names: `Preferences`, `Preferences.txt`, `Main.linx`, `index.linx`, `.link` |
| 0x6a12a8 | 0x10823004 | The base of the link strings. Each entry is a pointer to a string. |

The link strings, as offsets from the base 0x6a12a8:

| Offset | String | Offset | String |
|---|---|---|---|
| +0x04 | `ENCODING="` | +0x30 | `song` |
| +0x08 | `"` | +0x34 | `video` |
| +0x0c | `file://` | +0x38 | `nowplaying` |
| +0x10 | `ipod:` | +0x3c | `true` |
| +0x14 | `music?` | +0x40 | `false` |
| +0x18 | `video?` | +0x44 | `=` |
| +0x1c | `artist` | +0x48 | `nopush` |
| +0x20 | `album` | +0x4c | `popall` |
| +0x24 | `genre` | +0x50 | `href="` |
| +0x28 | `composer` | +0x54 | `name="` |
| +0x2c | `playlist` | | |

## The functions

| Address | Function |
|---|---|
| 0x1953f8 | Reads an `<A` tag. It finds `href="` or `name="` and the text up to the next `"`. After the text, it finds the attributes `nopush` and `popall`. |
| 0x19514c | Reads the type of a link: `ipod:` with `music?` (2) or `video?` (3), or a link to a file (1). |
| 0x195338 | Makes the table of the link keys one time: 0 `playlist`, 1 `genre`, 2 `artist`, 3 `composer`, 4 `album`, 5 `song`, 6 `video`, 7 `nowplaying`. |
| 0x195540 | (link, key index, text, out): finds the key, then `=`, then the value. The value stops at the first `&` (0x26) or at the end. Spaces and tabs before the value are skipped (0x1950ec). |
| 0x195624 | Decodes `%XX` hexadecimal escapes in a value. |
| 0x1952a4 | Reads `nowplaying`: 1 for `true`, 0 for `false`, 2 if the key is not in the link. |
| 0x13e540, 0x13f6fc | Read a `<META NAME="…" CONTENT="…">` tag. |

Thus:

- `nopush` and `popall` are attributes of the tag, for example `<a href="Next.linx" nopush>`. They are not keys of a music link.
- `nowplaying=false` is a key of the music link.
- A raw `&` in a name stops the value. Write `&` as `%26` and `%` as `%25`. The form `&amp;` is not correct. Not tested: whether the tag reader decodes `&amp;` before the link reader.
- No key opens the song list of a playlist. A music link always starts playback.

## Emulator test

The script [notes-links/make_test.py](notes-links/make_test.py) makes a drive with the stock firmware, the six test playlists, a playlist `R&B` and a `/Notes` folder. The owner tested the links in the emulator window on 5 November 2026.

The note "11 Alpha songs" (`Alpha.linx`) gave the best result. It lists each song of the playlist as `ipod:music?playlist=Alpha&song=Test Song N`. The user scrolls the songs and selects one. Then the Now Playing screen shows, as in the stock song list. The note "12 Alpha songs, no Now Playing" (`AlphaNP.linx`) adds `nowplaying=false`, and the owner preferred note 11. The other cases were not recorded one by one.

Tests 05 and 06 used `nopush` and `popall` as link keys. This form is not correct (refer to 0x1953f8).

Not tested:

- whether the next song after a selection is the next song of the playlist;
- `%26` and `&amp;` in a playlist name (tests 08 and 09 were not recorded);
- the limits of the size of a note and of the count of notes;
- the real iPod.

## The song-list version on a real iPod (5 November 2026)

The owner gave a song-list version of Folders4Playlist to the user. It writes `p_<ID>.linx` and the pages `p_<ID>_N.linx` next to the `index.linx` of the folder. It did not operate on the user's real iPod with the Korean menu language.

Emulator, 65 real playlists, 266 note files in one directory: the Notes menu showed each file as an item. Each page had the title of the playlist, so one playlist showed 39 times. The playlists were not in their folders. The fix: one directory for each playlist, with only one `index.linx`, and one subdirectory for each page.

## The note reader (Ghidra, 5 November 2026)

| Address | Function |
|---|---|
| 0x23d748 | Finds the file of a link. A link to a directory opens its `index.linx`. |
| 0x12fc4c | Opens a note. It reads at most 0x1000 bytes. |
| 0x13fe28 | Records "Note too long, truncated. (7)" if the file is larger than 0x1000 bytes. |
| 0xe4be8 | Reads the byte order mark: `EF BB BF` gives UTF-8 (3), `FF FE` gives 5, `FE FF` or a first byte 0 gives 4 (UTF-16). Else 10. |
| 0x10f0c0, 0x1705dc | With no byte order mark, the encoding comes from the language (0x192ca8): 0x606d gives 6 (Japanese), 0x606e gives 9 (Korean), 0x6074 gives 8, 0x6075 gives 7 (Chinese). Other languages give 1 (Latin-1) or 2 (Mac Roman). |
| 0x13f33c | Reads `ENCODING="…"` in the `<?XML` tag. The names are in the table at 0x6a11ac (RAM 0x10822f08). An unknown name gives "Bad meta data, unknown encoding. (17)". The reader then reads the note again. |
| 0x12f600 | Runs a music link. It compares the `playlist` value with each playlist name, selects the first equal playlist, and then compares the `song` value with the titles of that playlist. No equal name gives "No match for %s. (101)". |
| 0x223354 | Compares two names. It decodes UTF-8 with 1 to 3 bytes (0x2234dc). A 4-byte character gives 0 and ends the name. Characters below U+0100 go through the table 0x22428c. It does no Unicode normalization. |

Thus a note with Korean text and no byte order mark is probably read as EUC-KR on a Korean iPod. That the language 0x606e is Korean is a conclusion from its encoding. Not tested on a real iPod.

A file for the author, with a check script, is not in the repository. The owner shares it.
