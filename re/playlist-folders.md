# Playlist folders: research (RetailOS 1.3, iPod Video)

A user suggested playlist folders. The Playlists list shows playlists and folders together. A folder opens to show only playlists. A folder cannot contain a folder. The user sets the name and the colour of a folder in the iPodFirm app.

Status (29 October 2026): research complete. The patch `playlist-folders` uses the method of experiment 3. Version 0.1 operates in the emulator and on the real iPod (tests by the owner). On the real iPod, the colour squares did not show. Version 0.2 turns off the colours. Refer to [Folder colours](#folder-colours). Refer to [../docs/modifications.md](../docs/modifications.md#playlist-folders).

## Decisions of the owner

- The folders come from a file that the iPodFirm app writes. The iTunesDB does not change.
- A playlist in a folder shows only in its folder.
- The user picks the colour of a folder in the app. This is stopped at this time (refer to [Folder colours](#folder-colours)).
- The app has a choice for the position of the folders: "Folders first" or "Alphabetical".
- A folder opens on the same screen, with no slide animation (refer to [Experiment 5](#experiment-5-a-second-playlists-screen)).

## The stock firmware and iTunes folders

The parser of the playlists (0xd6de8) reads a 0x6c-byte `mhyp` header. It does not read +0x3c to +0x6b. Thus the firmware ignores the folder fields that iTunes can write. The only nesting in the firmware is the podcast group (`mhip` +0x11, 0x94348, 0x10d228).

## The playlist array

The database load 0xb4a64 makes an array of playlists in the main browser (the library):

| Address | Content |
|---|---|
| main browser + 0xcfc | Array of playlist pointers. Entry 0 is the master playlist. |
| main browser + 0xd00 | The count of entries. |

0xb4a64 does not put these playlists in the array: New Voice Memos (`pl + 0xec & 0x40`), podcast playlists (`pl + 0xed & 0x80`, kept at library + 0xce4) and some empty playlists.

The functions that read the array:

| Address | Function | Caller |
|---|---|---|
| 0x9e008(browser) | The count (+0xd00). | Playlists screen, iAP |
| 0x9cf90(browser, index, out) | The name of entry `index`. `out[0]` is the count of UTF-16 units, then the text (0x9e42c). | Playlists screen (label 0x6425), iAP |
| 0x9cf58(browser, index) | The persistent ID (low word, pl + 0x18) of entry `index`. | iAP |
| 0x9cfe0(browser, index) | The count of songs (root + 0x32). | iAP |
| 0xa39c4(browser, index) | 1 if entry `index` is On-The-Go (library + 0xce0). | 0x254cac |
| 0x9e99c(browser, index) | `pl + 0x16c`. | 0x1eb9fc, 0x1edf54 (all entries) |
| 0x9e2f4() | The index of the current playlist. | iAP |
| 0x914ac / 0xb29b0(browser, index) | Selects entry `index`: browser + 4 = the playlist. | 0x1e7e34 |
| 0xb2d1c(browser, index) | Writes the persistent ID of entry `index` into the settings (+0xb2c/+0xb30). | 0x1935ec |

The functions near 0x165000–0x16f000 are the iPod Accessory Protocol (iAP). A patch that changes only the Playlists screen does not change them.

## The Playlists screen

The screen uses the JS browser object (class with the native browser at +0x1c). The script calls its methods through a table of C++ member pointers at 0x4fcd58–0x4fcf00.

| Address | Function |
|---|---|
| 0x1ea660(js) | Gets the count with 0x9e008 (bl at 0x1ea66c). Stores count − 1 at js + 0xd4 (word 0x35). If the value changed, it sends `vtable+0x54(js, 'VMax', 0x6387)`. |
| 0x1ec614(js, …, element, row, …) | The data of a row. For element 0x6425 (the playlist name), it calls 0x9cf90(browser, row + 1, out) (bl at 0x1ec914). |
| 0x1e7e34(js, row) | Selects a row. Writes js + 0x3ec = row. Calls 0xb29b0(browser, row + 1) (bl at 0x1e7e7c). |
| 0x254cac(js, row) | 1 if the row is On-The-Go. Calls 0xa39c4(browser, row + 1) (bl at 0x254cc4). |
| `vtable+0x54(js, 'Str ', 0x6387)` | Makes the list read its labels again. |

Thus screen row r shows array entry r + 1. The master playlist is not on the screen. The list of the screen is a browse list (vtable 0x677290). Its template cell has a child with element ID 0x6425. The Artists list also uses element ID 0x6387, thus the patch uses the child 0x6425 to find the Playlists list.

All the row numbers of the JS level are screen rows. Only these four call sites change a screen row into an array index: 0x1ea66c, 0x1ec914, 0x1e7e7c and 0x254cc4. A patch that hooks these four calls can show a different list.

## Key events

- The UI handler 0x1d81cc (slot 0x6701f0) gets each key event first. Then the list gets the push (type 4) through its event method (slot 0x6772c0).
- The UI handler alone gets the events after the push: repeat (5), hold (6) and release (7).
- The script acts on a key also after the push. Thus a list hook that uses a push must also stop types 5–7 of that key in the UI handler. On the release it must decrease the byte at UI + 0x44, as 0x1d820c does.
- Cover Flow uses the same method (`swallow_key`). Cover Flow hooks 0x6701f0 without `chain`. A second patch on that slot needs `chain` in both patches.

## Emulator method

The files are in [playlist-folders/](playlist-folders/):

- `harness/emu.py` makes a firmware with patches, a drive and an emulator profile. The test library has 60 songs and six playlists: Alpha, Bravo, Charlie, Delta, Echo and Foxtrot. The work folder is `$PF_WORK` (default `/tmp/pf-work`).
- `harness/srv.sh`, `c.sh`, `w.sh` and `nav.sh` start the headless emulator and send inputs.
- `exp1/` to `exp5/` are the experiment patches.

The tests by the owner used the emulator window (the same drive, `--cold`).

CAUTION: Scripted inputs are not reliable. The highlight moves a different number of rows for the same wheel count, and a screenshot can show an old screen. Use the emulator window for tests of navigation.

The test library of `ITunesDB.build` writes 0 at `mhyp` + 0x2c (the sort order). iTunes writes 1. The owner tested a library with the value 1. All playlists opened as in the stock firmware.

## Experiments (29 October 2026, emulator, tests by the owner)

In all experiments, Alpha (row 0) is a "folder" of the playlists after Bravo.

### Experiment 1: a select that returns 0

A hook on 0x1e7e34 returned 0 for row 0 and changed the rows. Result: the Alpha songs opened. Back in Playlists, the list showed the new rows.

Conclusion: the return value of 0x1e7e34 does not stop the navigation. The list reads its labels again when it shows again.

### Experiment 2: a hook on the list event

The list event hook took Select on row 0. It changed the mode, sent `'VMax'` and `'Str '` and set the selection to row 0. Menu in the folder went back to the top list. Result: the folder list showed, but each Select and Menu acted two times. Select on Alpha opened the folder and then Charlie.

### Experiment 3: experiment 2 and a key swallow (this method operates)

Experiment 2, and a hook on the UI handler that stops types 5–7 of the used key. Result: the folder opens on the same screen. Select opens a playlist of the folder. Menu goes back to the top list. There is no slide animation.

### Experiment 4 and 5: a second Playlists screen

The hook on the menu `activate` slot (0x6776f8) kept the menu row that opened Playlists. Select on a folder ran that row again, to push a second Playlists screen with the slide.

- Experiment 4 kept the row at the first count update. The JS browser of the Playlists screen exists from the start, so the row was empty. The Alpha songs opened.
- Experiment 5 used the last menu activation. Select on Alpha did nothing until the wheel moved.

The owner stopped this work. The patch uses the method of experiment 3.

## Design of the patch

- A file `iPod_Control/iTunes/iPodFirmPlaylistFolders` gives the folders: name, colour and the persistent IDs of the playlists.
- The patch makes the view (the top list or one folder) from the array and the file. It makes the view again when the array pointer or the count changes (a new database).
- Hooks: the four call sites above, the list event (0x6772c0, chain) and the UI handler (0x6701f0, chain).
- The album-art patch draws the square of a row from the hash of the row text. The app writes a colour square for each folder name into `iPodFirmAlbumArt`. Thus the colour needs no firmware code. Version 0.2 turns off this step (refer to [Folder colours](#folder-colours)).
- The album-art patch 3.4 draws one fixed icon on each folder row (refer to [Folder icon](#folder-icon)).

## Folder icon

Status (31 October 2026): made. Not tested in the emulator or on the real iPod.

**The method.** `album-art` 3.4 keeps the icon in the array `folder_px`. It reads the file `iPodFirmPlaylistFolders` one time and keeps the hash of each folder name. The patch reads the file again after a USB session. A playlist row whose hash agrees with a folder name gets the icon. This step comes before the collage step.

**The switch.** The section "Playlist Folders" of the app has the switch "Folder Icons". The default is on. The switch always shows, but it operates only if the connected iPod has folders. If the switch is off, the app sets bit 1 of the flags in the folder file. Then `album-art` keeps no folder names, and a folder row has only text. "Write Folders to iPod" sends the change. A flash is not necessary. The patch `options` list cannot do this, because `album-art` cannot read an option of a different patch.

**Why this method.**

- The icon does not use the thumbnail file. Thus the app writes nothing, and the probable causes of the colour failure do not apply.
- The patch finds a folder from the folder file. The other method, "no playlist has this name", can give an icon to a playlist whose name the patch cannot match.
- `album-art` already moves the row text and draws the thumbnails. A copy of this code in `playlist-folders` needs more hooks.

**The transparent pixels.** The blit 0x210114 copies all pixels. Thus the icon uses `draw_runs`, which skips the value `FOLDER_KEY` (0xf81f). A pixel is solid or transparent. The draw does not blend, so the edge of the icon is not soft.

**The colours.** The firmware has 16 × 16 list icons, BMap 30240 to 30250, in ARGB4444. Measurements of BMap 30244: the gradient goes from 0x3399ee at the top to 0x99ccff at the bottom, with a highlight of 0xddeeff. The folder icon uses these colours. The dark outline (0x1b5fae) is not a stock colour. The outline keeps the icon visible on a highlighted row.

**To change the icon.**

1. Edit [folder-icon.png](playlist-folders/folder-icon.png). The PNG must be 20 × 20 pixels.
2. Run [make-folder-icon.py](playlist-folders/make-folder-icon.py).
3. Put the output into `folder_px` in `album_art.c`.
4. Increase the `version` in `patch.json`.

## Folder colours

Status (29 October 2026): stopped. The code stays in the app as comments, for later work.

**The method.** The firmware does not use the colour. The app makes a 40 × 40 square of the folder colour (`PlaylistFolders.tile`). It writes the square into the thumbnail file `iPodFirmAlbumArt` of the album-art patch. The key is `AlbumArt.playlistKey(folderName)`, the key of a playlist with the folder name. The album-art patch draws the square of a row from the hash of the row text. Thus the folder row gets the square with no firmware code.

**The results.**

- Emulator, version 0.1 with `album-art`: the folder rows showed the correct colours.
- Real iPod, version 0.1: the folders operated, but the colour squares did not show.

**The code that is a comment in version 0.2.**

| File | Code |
|---|---|
| [MusicImport.swift](../mac/Sources/IPodFWKit/MusicImport.swift) | `writeThumbnails` adds `PlaylistFolders.read(volume:).artEntries()` to the entries. |
| [AppModel.swift](../mac/Sources/iPodFirm/AppModel.swift) | `writePlaylistFolders` writes the thumbnail file again if it is on the iPod. |
| [PatchTools.swift](../mac/Sources/iPodFirm/PatchTools.swift) | The `ColorPicker` in `PlaylistFolderRow`. The `colour` binding stays. |

These parts stay active: the colour field in the folder file, `PlaylistFolders.rgb565`, `components`, `tile` and `artEntries`, and the test `testColour`.

**Possible causes (not examined).** The first cause is the most probable.

- The thumbnail file on the iPod did not have the squares. "Write Folders to iPod" writes the thumbnail file again only if the file is already on the iPod.
- The album-art patch on the iPod keeps its own cache (album-art 2.9 and later). A cache entry from before the folder file can hide the new square.
- The album-art patch on the iPod makes a collage on the iPod for a playlist row (album-art 3.2). A folder row has no playlist, so the patch can show no square.

**To continue.**

1. Remove the comment marks from the three items in the table.
2. Copy the thumbnail file from the real iPod. Make sure that it has a square for the key of each folder name.
3. Read the cache logic of `album_art.c` for a row that is not a playlist.
