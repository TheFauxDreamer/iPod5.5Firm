# Customising the stock iPod 5.5G firmware: feasibility

*Researched October 2026. Target: iPod Video 5.5G (PortalPlayer PP5022), Apple firmware 1.3, modified hardware, macOS (Apple Silicon) host.*

## Summary

| Goal | Feasibility | Notes |
|---|---|---|
| **Themes**: pictures, colours, text | **High.** Working now in `ipodfw` | The firmware is unencrypted and unsigned; only a byte-sum checksum protects it. |
| **Album artwork next to each album in the Albums list** | **Medium-low.** A real reverse-engineering project | The list row is drawn by code, not by resources. This needs ARM code patches. |
| **Faster Play → Now Playing** (currently 2–3 s) | **Uncertain** | The cause isn't known yet. It must be measured before it can be fixed (see Phase B). |
| **Installing like iPodWizard** (customised OS replaces stock) | **Yes** | `ipodfw flash` writes the modified OS directly in place of Apple's. No bootloader or Rockbox involved. |
| **Recoverable if something goes wrong** | **Yes** | Disk mode lives in the boot flash, not on the disk. See *Recovery*. |

## How the firmware is stored

The iPod's disk has a hidden **firmware partition** (MBR type 0 on Windows-formatted iPods, `Apple_MDFW` on Mac-formatted ones). Apple's `iPod_25.1.3.ipsw` contains a byte-for-byte image of it (`Firmware-25.6.3`, 13.9 MB). The details below are confirmed against that file:

- Offset `0x000`: Apple "STOP" banner. Offset `0x100`: `]ih[` magic. Offset `0x104`: directory offset − 0x200. Offset `0x10a`: format version 3.
- The directory at `0x4200` holds 40-byte entries. Image data starts at `2048 + devOffset`.

| Image | Size | What it is | Checksum |
|---|---|---|---|
| `osos` | 7.2 MB | RetailOS: ARM code (RTXC kernel), loaded at `0x10000000`. Also holds all UI resources. | plain byte sum ✔ |
| `rsrc` | 5.0 MB | Firmware and fonts for the Broadcom BCM2722 video chip | plain byte sum ✔ |
| `aupd` | 1.0 MB | Encrypted **boot-flash updater** | does not verify as a plain sum; never touched |

**There is no signature check.** Apple's boot loader in the NOR flash only checks the sum. This is why iPodWizard (2006) and Rockbox's `ipodpatcher` can write to the partition freely.

### Resources inside osos (what themes edit)

`osos` contains 25 resource blocks (format from iPodWizard, confirmed against 1.3):

- **One main block:** 403 pictures (`BMap`), 991 strings, 619 layout `View` records, 40 `Menu` definitions, 158 `Type` (font/colour) records, plus `TCmd` command tables.
- **24 language blocks**, holding the translated strings.

Picture formats: RGB565 (251), ARGB4444 with transparency (117), and 4-bit (21) or 2-bit (14) greyscale. Strings are UTF-8, NUL-terminated and 4-byte aligned. They can grow only into the existing alignment slack, which is the same limit iPodWizard had.

## Recovery: can you get back to stock?

Yes, and several independent ways:

1. **Disk mode can't be broken by `ipodfw`.** The boot loader, disk mode and diagnostics are in the NOR flash chip, not on the disk. To reach disk mode: reset (hold Menu+Select), then hold Select+Play as the Apple logo appears.
2. **`ipodfw restore`** writes your pre-flash backup back byte for byte. `flash` refuses to run until a backup exists.
3. **Rescue restore.** An interrupted write can damage the firmware header or directory. Then the normal restore cannot compare the backup with the iPod. The rescue restore compares the backup with the first backup ("Original") instead. It still does not write the `aupd` area. In iPodFirm, "Restore…" starts the rescue automatically. In the tool, use `ipodfw restore --rescue`.
4. **Finder → Restore iPod** rewrites the entire firmware partition with stock 1.3. It also repairs a damaged partition table. This is the same safety net iPodWizard users relied on.

The one way to genuinely brick a 5.5G is a bad write to the NOR flash. Only the `aupd` image does that. `ipodfw` never modifies `aupd`. It refuses to flash if `aupd` would differ in any way, and it refuses any write that overlaps it.

## Existing projects (references)

| Project | What it gives us |
|---|---|
| [iPodWizard](https://sourceforge.net/projects/ipodwizard/) ([git mirror](https://github.com/DavidBuchanan314/iPodWizard-mirror), [revival](https://github.com/Stehfyn/iPodWizard-stable)), GPLv2, Windows | The resource format specification (`firmware.cpp`, `Picture.cpp`, `firmware.h`). Ported in `ipodfw`. |
| [Rockbox `ipodpatcher`](https://github.com/Rockbox/rockbox/tree/master/utils/ipodpatcher), GPLv2 | Firmware partition directory, checksum and MBR/APM parsing. Ported in `ipodfw`. Also the reference docs for the PP5022 hardware. |
| [siggifly/ipod-emulator](https://github.com/siggifly/ipod-emulator), GPL-3 | **Boots unmodified retail 5.5G firmware.** Patches can be tested without flashing, and it has a headless Ghidra workflow. No audio, ~¼ speed. |
| [lgreitis/osos-lab (RepriseOS)](https://github.com/lgreitis/osos-lab), GPL-3 | A modern framework for patching Apple OSOS code (Ghidra plus ARM GCC "recipes"; adds an EQ and "play next"). It targets the Classic 7G, but it is the template for our code patches. |
| [BrandonDedolph/ipod-core](https://github.com/BrandonDedolph/ipod-core) | A clean-room 5.5G OS with hardware notes (BCM framebuffer, ATA). |
| [CUB3D/ipod_sun](https://github.com/CUB3D/ipod_sun), [nfzerox/ipod_theme](https://github.com/nfzerox/ipod_theme) | A modern stock-firmware theming pipeline (Nano 6/7) to compare against. |
| bghack / "split view" (2007–08, [iLounge](https://www.ilounge.com/index.php/news/comments/firmware-hack-brings-new-interface-to-ipod-5g)) | Code-level UI changes on 5G firmware 1.2.1: custom backgrounds and a Classic-style split view. No source survives, but the binaries can be diffed against stock. |
| [Rockbox](https://www.rockbox.org) / [rockpod](https://github.com/nuxcodes/rockpod) | The non-stock alternative. It already shows album art in lists and has no database RAM limit. |

## Your three goals in detail

### 1. Themes: doable today
`ipodfw unpack` gives you every picture as a PNG and every string as JSON. You edit them and run `ipodfw repack`. The result is checked against the real 1.3 firmware: an unchanged round-trip is byte-identical, and edits re-verify.

Current limits:
- Pictures must keep their size.
- Strings can only grow into the existing slack.
- Fonts (bitmap fonts in osos, OpenType fonts in rsrc) and `View` layouts aren't exposed yet. iPodWizard's `Font.cpp` and `LayoutDialog.cpp` are the references for adding them.

Many old themes were built for **1.2.1**. They are iPodWizard firmware dumps, not portable theme packs, so 1.3 themes have to be built from PNGs.

### 2. Artwork next to album names: a code patch
Nothing in the resources draws a thumbnail per list row. The list widget's code would have to:
1. look up each album's artwork (ArtworkDB / `.ithmb` thumbnails, which the Now Playing screen already reads);
2. draw it at a fixed position in the row, with the text shifted right.

**Approach:**
1. Diff the split-view firmware against stock 1.2.1 to see how it hooked UI drawing.
2. In Ghidra, find the list-row draw routine (start from the `View` resources and string IDs such as "Albums") and the Now Playing artwork routine.
3. Write the patch in C, compile it with `arm-none-eabi-gcc` for ARM7TDMI, and place it in free space in osos with a branch hook. This is the osos-lab pattern.
4. Test in the emulator.

**Risks:**
- Scrolling performance: decoding a thumbnail per row on a 75 MHz ARM7.
- RAM: whole-library databases on large flash mods already push 32/64 MB.

Expect weeks of reverse engineering, not days.

### 3. The 2–3 s delay when pressing Play: measure first
Plausible causes, roughly in order:
- **Drive power-up / spin-up waits.** Stock firmware powers the "hard drive" down and waits a fixed time for it on wake, which is pointless on an iFlash/SD adapter.
- **A large pre-buffer** filled before Now Playing is shown.
- **Now Playing artwork decode** of large embedded art. Quick check: sync smaller (≤ 300 px) artwork and see if the delay shrinks.
- **Database lookups** with very large libraries.

The emulator can trace ATA commands and time each one between the click and the screen change. If the delay is a fixed timeout or a buffer-size constant, the patch can be a single value. That would be the cheapest win of the three goals.

**Result (2026-10-03):** the cause is the drive power-off approximately 1 s after the last access. The firmware's own wait at power-on is only 14 ms. The rest is the start time of the flash adapter. The `flash-keep-awake` patch keeps the storage on for 2 minutes. Refer to [re/play-latency.md](re/play-latency.md).

## Roadmap

- **Phase A (themes):** `ipodfw` unpack → edit → repack. Test in the emulator (`ipodfw pack-ipsw`), then `backup` → `flash`. **Ready now.**
- **Phase B (latency):** trace in the emulator, find the waits in Ghidra, try a constant patch. Needs a "binary patch" command in `ipodfw` (planned: patch files with address, expected old bytes and new bytes).
- **Phase C (list artwork):** reverse-engineer list rendering and the art lookup, then write a C patch. Needs an ARM toolchain and a patch linker.

Phases B and C need the same new pieces in `ipodfw`: an ARM patch format, and somewhere to put new code.

Space is tight. In 1.3, only 2 KB separates the end of osos from rsrc. The options are:
- Reuse a language string block you'll never select (~10 KB each). This is risky if that language is ever chosen.
- Move `rsrc` past `aupd`. The partition on the device is much larger than the 13.9 MB in use, and this leaves `aupd` untouched.

Both still need to be validated in the emulator.

**Status:** The firmware tooling is tested on Apple's real 1.3 file. The `backup`/`flash`/`restore` device commands are implemented with the safety checks above, but they have **not yet been run against a physical iPod**. Use `--dry-run` first.
