# Split home screen: research notes

Status (31 October 2026): research only, on branch `home-screen`. There is no patch. The narrow list and the short list wait for the emulator test.

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

Status: Not tested. Measured: the byte counts, and the `osos` checksum is correct in the two files.

Examine these items in the emulator:

- Do the rows, the arrows and the highlight follow the narrow width?
- Does a long title stop at the new edge?
- Does the list go back to the full width with no scroll bar, for example with a short menu?
- Is the free area clean after a transition?
- Do the other menus stay correct?

## Feasibility

Status: a provisional decision. It depends on the emulator tests.

| Result of the tests | Method |
|---|---|
| The rows follow, and a menu element gets live data | A resource-only theme, with no code. |
| The rows follow, and a menu element gets no data | A View edit and a small patch that draws the panel with the firmware cover source. |
| The rows do not follow, and the short list operates | The mini player. |

The 2007 reports do not remove the main risk, because the rows of a list can still fail. They do show the items to test: the transitions, the jumps and the restart.

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

## Next steps

1. The owner tests the two files in the emulator.
2. If the rows do not follow, trace 0x1bb260 and 0x122b28.
3. Find a draw hook for the main menu, and the event of a song change, if the third test file gives no data.
4. Find a View that the firmware does not use. Make a third test file with a Draw 25544 element and the song text elements in the main menu.
5. Read the mod files if the owner can supply them. Ask in the iPoddities Discord, or look in the "MEGA iPod Archive".
6. Read `PixoNames.txt` and the View notes in the source of iPodWizard 1.3.5.
7. Read the Spotish coordinates and the adwaitapod screenshots.
