# Split home screen: research notes

Status (31 October 2026): research only. There is no patch. The research continues after the battery work.

The owner wants the main menu of the iPod classic 6G/7G: the list at the left, and the cover and the current song at the right.

## Known facts

| Need | Status | Evidence |
|---|---|---|
| A narrow list | Probably a small resource edit. Not tested. | The main menu has its own View 24430, in View 24085. It has an element of width 11 at the right edge (probably the scroll bar) and the list (View -288, list 24094). The layout uses anchors. Static. |
| Rows that follow the width | Not known. This is the main risk. | Rows use anchors, but the list draws with a template cell, and 0x1bb260 keeps cached text images. |
| The current song | Known | Refer to [song-info.md](song-info.md). |
| The cover | Known | `F1028_N.ithmb` is 100 × 100. It fits a panel of 107 pixels with no scale. |
| Panel draw | Known | The blit 0x210114 (`album-art`) and the label draw 0x244924 (`cover-flow`). |
| Memory | Sufficient | One cover is 20 KB. |

Known problems:

- The first open of the 104 MB `F1028_1.ithmb` takes approximately 0.93 s on the owner's iPod. The load must not stop the wheel.
- The panel gives approximately 99 pixels for text.

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

## Two layouts

| Layout | Description | Main risk |
|---|---|---|
| Side panel | The list uses the left 2/3 (213 pixels). The panel uses the right 1/3 (107 pixels). | The rows must follow the narrow width. |
| Mini player | The list keeps the full width and has a shorter height. A strip below it shows the cover and the song. This is the fallback. | The list must accept a shorter height. |

## Next steps

1. Change View 24430 in a test firmware so that the list ends at x = 213. The owner does the test in the emulator.
2. Test a list with a shorter height.
3. Decode the anchor fields. Trace 0x1bb260 and 0x122b28 if the rows do not follow.
4. Find a draw hook for the main menu, and the event of a song change.
5. Find how Now Playing asks `ArtworkLoadTask` (0x205db4) for an image.
6. Read the Spotish coordinates and the adwaitapod screenshots.
