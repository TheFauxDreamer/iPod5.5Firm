# Split home screen: research notes

Status (31 October 2026): research only, on branch `home-screen`. There is no patch. A resource-only split home screen for firmware 1.3 exists. Refer to [The Firebird themes](#the-firebird-themes).

The owner wants the main menu of the iPod classic 6G/7G: the list at the left, and the cover and the current song at the right.

## Known facts

| Need | Status | Evidence |
|---|---|---|
| A narrow list | Probably a small resource edit. Not tested. | The main menu has its own View 24430, in View 24085. Element 0 is the scroll bar: width 11, and it points to the list by the ID -288. Element 1 is the list (View -288, list 24094). The right edge of the list is the left edge of the scroll bar. Thus one value moves the two. Refer to [Edge format](#edge-format-of-a-view-element). Static. |
| Rows that follow the width | Not known. This is the main risk. | Rows use anchors, but the list draws with a template cell, and 0x1bb260 keeps cached text images. |
| The current song | Known | Refer to [song-info.md](song-info.md). |
| The cover | Known | `F1028_N.ithmb` is 100 × 100. It fits a panel of 107 pixels with no scale. |
| Panel draw | Known | The blit 0x210114 (`album-art`) and the label draw 0x244924 (`cover-flow`). |
| Memory | Sufficient | One cover is 20 KB. |

Known problems:

- The first open of the 104 MB `F1028_1.ithmb` takes approximately 0.93 s on the owner's iPod. The load must not stop the wheel.
- The panel gives approximately 99 pixels for text.

## The Firebird themes

The owner supplied a folder of 14 firmware images, 5.5G firmware 1.3, with a guide. The guide says that they come from a theme called Firebird in the iPod firmware archives. The author of the guide is not the first modder. The images are not in this repository, because they contain Apple firmware.

Measured against stock 1.3:

| Item | Result |
|---|---|
| Views changed | 292 of 619 in 12 images, and 619 in the 2 `Contemporary` images. No View changes size. No View has a new ID. |
| Code changed | 42 bytes at 0x131918–0x131b7f in the 2 images that were compared. Their names say "GamePatch", so this is probably the game patch. Not proved. |
| Checksums | `osos` and `rsrc` are correct. `aupd` is wrong. |
| `rsrc` | Different from stock. The difference is not examined. |
| Scanner | `resources.scan` finds no main block in these images. The table at 0x331da0 is the same, so a direct read operates. The cause is not known. |

Main menu layout, from `MLCV2- Normal`:

| View | Change |
|---|---|
| 24430 | Scroll bar: right −160, width 5, top 24, bottom −1. List: bottom −1. |
| -285 | Rewritten in place, same size. It holds a background element, the title (-286), the cover (-356) and the song panel (25532). |
| -356 | Holds 25525, the View of Draw 25543, the cover. Stock has this in Now Playing. |
| 25532 | Rewritten in place. Text at x = 180, y = 47, 78, 110 and 145. |

This gives 3 results:

- The list narrows with the same edit as `home-screen-narrow-list.ipsw`.
- A menu View can hold the Now Playing elements. This confirms the hypothesis in [Now Playing data](#now-playing-data) statically. A code change for the panel is not necessary.
- The method to get more elements is to rewrite an existing View in place. A larger View and an unused View are not necessary.

Emulator results on 31 October 2026, with `MLCV2- Normal`:

| Test | Result |
|---|---|
| The image as supplied | The emulator did not start it (report of the owner). |
| Stock 1.3 with only the `osos` of the image | It starts. The Language menu shows the narrow list and the panel at the right. |

The directory of the image is different from stock. The last field of `osos` and of `rsrc` is 0xffffffff, not 0x187c0008. The ID of `aupd` is 1, not 0. The checksum of `aupd` is wrong. Thus the image is possibly a dump of a real iPod. The test did not isolate the cause: the directory, `rsrc` or `aupd`. The themes do not need the `rsrc` of the image to start.

The guide lists a View for each screen in `Find.txt`. It gives 24430 as the main menu.

The title bar trick: View 24069 makes its child 24506 240 pixels high, not 24. Stock View -285 is the title bar. The themes rewrite it, so the title bar becomes a full-screen backdrop that holds the panel. Thus the panel shows on each menu.

The theme look is separate from the layout. The themes change 29 Type resources (for example the menu text from size 18 to 16), 307 pictures and a left-aligned title. The themes remove 46 pictures with the offset 0xFFFFFFFE. Thus `resources.scan` refuses the images.

The author reports that horizontal scroll does not operate on 1.3, and that the menus respond differently from 1.2.1.

Copy tests on stock 1.3 (Emulator, 31 October 2026):

| Test | Result |
|---|---|
| `home-screen-narrow-list.ipsw` | Correct. Rows, arrows and highlight stop at x = 213. Stock fonts. The right area is white. |
| 5 Views of the theme | The main menu is white. The title bar parents are missing. |
| All 292 changed Views | The list operates, with stock fonts. The title is white on white, and bars show across the title. Not acceptable. |

Decision of the owner: stay as close to stock as possible, with only the layout change. Thus do not copy the theme Views. Write a small set of our own View values.

Caution: the guide says that an edit with no "Fix Checksum" can brick the iPod. iPodFirm calculates the checksum, but use the emulator first.

## The 2007 mod

Status: known from reports only. The fetch tool cannot read reddit.com or web.archive.org, so the mod files were not examined.

A mod of 2007, "iPod Classic to iPod Video 1.0", gave the 5G and the 5.5G split menus, a changed Now Playing and a mini Now Playing on each menu. This proves that the idea can operate on this hardware. It does not prove that the result is good.

| Item | Report | Source |
|---|---|---|
| Authors | bounci.rabbit.123, H3X, vettefan, matthew98, supernatural, saXas, xxDriveNxx | [iClarified](https://www.iclarified.com/109/ipod-classic-to-ipod-video-10-is-finished) |
| Tool | iPodWizard, Windows only. This suggests a resource edit. | [Engadget](https://www.engadget.com/2007-10-15-5g-ipods-hacked-to-run-updated-interface.html) |
| Files | `ClassicFirmwarefor5.5Gv1.0.2.zip` and a 5G file, from driven-design.net | [Applesfera](https://www.applesfera.com/ipod/convierte-la-interfaz-del-ipod-video-en-la-del-ipod-classic) |
| Panel | One report says that the right half shows the current track. | [ifun.de](https://www.ifun.de/ipod-classic-menus-fur-die-5-generation-3764/) |
| List width | The preview version gave the menu approximately 2/3 of the screen. This agrees with our layout. A commenter says that a menu of 1/2 needs much new code. This is not proved. | [ifun.de](https://www.ifun.de/in-arbeit-classic-look-fur-den-5g-3740/) |
| Project page | generaciondealcance.com/drivendesign/classic/. A commenter reported that it did not operate. Not examined. | ifun.de |
| Problems | Bricked iPods, boot loops, jerky transitions, menus that jump | Engadget, ifun.de |
| Cover | The art shows at the side only while a song plays. This is a search summary of a forum page that did not open. | MacRumors thread 368840 |

The [iPoddities firmware archive](https://archive.org/details/ipoddities_firmware_archive) page shows no file of this mod, but the page shows only a part of the contents. The method of the mini Now Playing is not known. Refer to [Now Playing data](#now-playing-data). The forum thread was ipodwizard.net `t=30444`.

## Edge format of a View element

Static: The iPodWizard source file `firmware.h` gives the fields. 0x21a5e4 and 0x21a80c give the meaning. This corrects the note in [firmware-ui.md](firmware-ui.md).

An element has 4 edges in this sequence: top (offset 28), left (40), bottom (52), right (64). Each edge has 3 words: the reference element, the mode and the value.

| Mode | Result |
|---|---|
| 0x100, 0x200, 0x300, 0x400 | Top, left, bottom or right edge of the reference, plus the value. |
| 0x80000002 | The same edge of the parent, plus the value. |
| 0x80000001 | The value. |
| 0x80000004 | Right: own left edge plus the value. Left: own right edge minus the value. Thus the value is a width. |
| 0x80000008 | Bottom: own top edge plus the value. Top: own bottom edge minus the value. Thus the value is a height. |
| Bit 0x10 of a mode | Sets a flag in the element (+0x20, bit 0x10). The meaning of the flag is not known. |
| Bit 0x20 of a mode | Sets a flag in the element (+0x20, bit 0x100). The meaning of the flag is not known. |
| Other positive modes | Reference word × length of the parent / mode, plus the value. Example: word 1 and mode 2 give the centre. |

The data suggests that reference 0 is the previous element. For example, View 24541 uses an ID and View 24545 uses 0 with the same modes. Check this in 0x21a374.

View 24430 in firmware 1.3 (osos offsets):

| Element | Edge | Mode | Value | Offset of the value |
|---|---|---|---|---|
| 0, scroll bar | left | 0x80000014 | 11 | |
| 0, scroll bar | bottom | 0x80000002 | 0 | 0x4dc7f8 |
| 0, scroll bar | right | 0x80000002 | 0 | 0x4dc804 |
| 1, list | right | 0x200, reference 0 | 0 | |
| 1, list | bottom | 0x80000002 | 0 | 0x4dc864 |

## Now Playing data

Static. An element gets its data by its ID. 0x21f254 asks the provider, and then the parents of the provider. 0x1e804c is the property method of the main provider (class 0x670f54) for the music screens.

- Draw 25543 (0x63c7) and Draw 25544 (0x63c8) are the covers of Now Playing, in Views 25525 and 25528.
- 0x1e804c calls 0x1eb2b0 for these IDs. 0x1eb2b0 gets the art formats 7 and 8 with 0x2052f0.
- The cases 0x63bd–0x63bf of 0x1e804c give the texts of the current song.
- 0x2458c4, case 0x558c, calls 0x1eb2b0 on the global object at `*0x245c34`. Thus a patch can also get the cover directly.

**Hypothesis, not tested:** if the parents of the main menu lead to the main provider, a copy of these elements in the main menu shows live data with no code. This can explain the mini Now Playing of 2007. It also agrees with the report that the art shows only while a song plays.

The limit is the size of the View. A new element makes View 24430 larger, and iPodFirm cannot do this now. A possible method needs no larger View: change the child ID 24430 in View 24085 to a larger View that the firmware does not use, and write the new layout there. The Layout editor of iPodWizard 1.3 changes values in place and has no command to add an element. Thus the 2007 mod probably changed values and links only. This is an inference. Any View that we use must be proved unused.

## Test firmware

[home-screen-views.py](home-screen-views.py) makes the two files for the emulator. The files are not in the repository.

| File | Change | Changed bytes |
|---|---|---|
| `home-screen-narrow-list.ipsw` | Right edge of the scroll bar: −107. The scroll bar goes to x = 202–213, and the list ends at 202. | 4 |
| `home-screen-short-list.ipsw` | Bottom edge of the scroll bar and of the list: −64. | 8 |

Status: the owner reported on 31 October 2026 that the last test operated. Measured: the byte counts, and the `osos` checksum is correct in the two files.

The first test on 31 October 2026 gave no result. The files were dragged onto the emulator, so the stock firmware ran. Refer to [emulator.md](emulator.md). Each file now has its own profile and drive: `make-disk`, `fix_osos_length`, `put-files`, then a start with `--cold`.

Examine these items in the emulator:

- Do the rows, the arrows and the highlight follow the narrow width?
- Does a long title stop at the new edge?
- Does the list go back to the full width with no scroll bar, for example with a short menu?
- Is the free area clean after a transition?
- Do the other menus stay correct?

## Feasibility

Result: feasible as a resource-only change, on firmware 1.3. The Firebird themes show this. The panel shows in the emulator. Its live data is not tested yet.

Recommended method: apply our own View values as an iPodFirm theme or as `patch.json` edits. Do not copy the images. Then measure the conflicts with `dark-mode`, `album-art` and `cover-flow`.

## Sources for the layout

**The Apple firmware of the classic.** It has the split home screen, but the program image is encrypted. Refer to [ipod-classic-6g.md](ipod-classic-6g.md).

**RepriseOS.** Its documents have nothing about the home screen. Its addresses are for the Classic. The folders `payload/` and `patching/ui` are not read yet. Use only the ideas (GPL-3.0).

**Rockbox themes.** A theme is a text file that places viewports. It uses the Rockbox draw code. Thus it has no code for RetailOS, but its layouts are useful examples for 320 × 240.

| Theme | Use | Licence |
|---|---|---|
| [Spotish](https://github.com/stylo969/spotish-rockbox) | Made for the 5.5G. A mini player under each menu: cover, title, artist, play state, progress. The coordinates are in `src/gen_spotish.py`. | Scripts MIT, theme files CC BY-SA 4.0 |
| [adwaitapod](https://github.com/D0-0K/adwaitapod) | A modern theme for the 5G to 7G. Its page does not describe the layout. It has a `Screenshots` folder. | GPL-3.0 |
| [Themify](https://github.com/D0-0K/themify) | An adaptive theme for the 5G to 7G. Details are on themify.dook.net. | Not on the page |
| [PodBox](https://github.com/anthonyfletcher/podbox) | Art beside each list. A choice of scroll or cut for long text. | GPL-2.0 |

No search result showed a theme with the exact 6G layout. The Rockbox theme manual page did not open.

## iPodWizard 1.3.5

The [v1.3.5 release](https://github.com/TheMetalWizard/iPodWizard/releases/tag/v1.3.5) is new. Its page has no method to add or to make larger a View element. Its source is not examined yet.

| Item | Use for this research |
|---|---|
| Hover explanations of the layout resources | They can correct the names of the View fields. |
| `PixoNames.txt` and the Commands menu | Readable names for commands. They can give names for functions in our notes. |

iPodWizard is under the GPL, so use its source only for facts. Its post says that a brick is nearly impossible, because the tool does not touch the bootloader. The 2007 reports say that iPods bricked, so the test order does not change: use the emulator first.

## Two layouts

| Layout | Description | Main risk |
|---|---|---|
| Side panel | The list uses the left 2/3 (213 pixels). The panel uses the right 1/3 (107 pixels). | The rows must follow the narrow width. |
| Mini player | The list keeps the full width and has a shorter height. A strip below it shows the cover and the song. This is the fallback. | The list must accept a shorter height. |

## The stock layout

Status: emulator test open, 31 October 2026.

Warning: do not write this file to a real iPod until all tests are complete and the owner agrees.

[home-screen-views.py](home-screen-views.py) makes `home-screen-split.ipsw` from stock 1.3. The panel is only in the main menu, as on the classic. The title layers, all other lists and all shared Views stay stock.

| Change | Bytes | Measured |
|---|---|---|
| The table entry of View 24430 points to 0x735c00 and has size 704. | Up to 8 | Table at 0x337424 |
| The new main menu at 0x735c00, in the patch area: the stock scroll bar (right edge −107), the stock list, the cover View -356, and the song, artist, album and count. | 704 | 279 bytes of `osos` change in total, and none outside these two places. `rsrc` and `aupd` are stock. The zero area at 0x6ca452 is the same. The `osos` checksum is correct. |

The text lines are at y = 116, 138, 160 and 188 in the content area, each 22 pixels high.

The old data of View 24430 stays in the firmware, unused. A final patch must get this space from the patch area, because other patches also use that area.

Emulator results of earlier designs:

- The cover and the live song text show with no code. This confirms that a menu element reaches the main provider. The owner saw this on 31 October 2026, with the FolderLibrary.
- A panel in the title layer shows behind Now Playing. Thus the panel must not be in the title layer.
- A text element with a bottom edge at the parent centres itself in the whole height. Thus each line needs a fixed height.

Next does nothing in the emulator with stock 1.3 and with this file (report of the owner). The emulator does not play the music. Thus the emulator cannot test a song change with Next.

Rejected designs: commit 3b250ed rewrote Views -285, -286 and 25532, which other screens use. Commit 704f76d put the panel behind all screens. Do not change a shared View.

Rejected space: commit 8561c18 used the space of View -515. No View, resource or code refers to the ID, and no View has it as a child. But code handles its element IDs 0x6fbb–0x6fc0 (0x1db294 and 0x155320). Thus it is a real layout, and its use is not known. Do not use it. The hit of −516 at 0x4f89ec is not a reference, because that address is outside the resources. Views 13957 and 30208 have no parent, but code uses their IDs.

## Game patch

The themes contain the same patch as the DRM research of this project. The research is in the history before commit ca0da76. The patch changes 6 conditional branches to `nop` in 0x131874, the DRM check of a game. Each branch goes to the failure address 0x131b84. The layout does not need the patch. The file of this research does not contain it.

## Next steps

1. The owner tests the main menu in the emulator: the cover, the text, Now Playing, and the wheel speed.
2. Test long titles in the scrolling song line.
3. Test the main menu with no song, and with a song that has no art.
4. Test a main menu with more rows than the screen, for the scroll bar.
5. Change the place of the View to a location that `patcher.py` allocates.
6. Test the conflicts with `dark-mode`, `album-art` and `cover-flow`. Theme import reads Views by table offset.
