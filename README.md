# iPod5.5Firm

Customise **Apple's stock firmware** on an iPod Video 5G/5.5G from a Mac, like iPodWizard did. The customised OS replaces the stock one in place, and you can always restore.

The research, risks and roadmap (themes → faster Play → album art in lists) are in **[FEASIBILITY.md](FEASIBILITY.md)**.

## The app: iPodFirm

A native SwiftUI app in [mac/](mac/) covers everything. Open or download firmware, edit pictures (drag in PNGs) and text (with a live space budget), back up, flash and restore the iPod, and export an `.ipsw` for the emulator. Raw disk access goes through a bundled helper, using the standard macOS administrator prompt.

```sh
mac/scripts/build-app.sh      # bumps version + build number, builds, installs /Applications/iPodFirm.app
cd mac && swift test          # IPODFW_IPSW=… adds real-firmware tests; IPODFW_DISK_TEST=1 adds a flash test on a disk image
```

Backups go to `~/Library/Application Support/iPodFirm/Backups/`. One is taken automatically before every flash or restore, and the first is kept permanently as "Original (first backup).bin".

The Python `ipodfw` CLI below uses the same formats, and its exported folders can be imported in the app.

## CLI setup (macOS, Apple Silicon)

```sh
uv sync                     # Python 3.12 + Pillow into .venv
uv run pytest               # optional: IPODFW_IPSW=path/to/iPod_25.1.3.ipsw also tests Apple's real file
```

Get Apple's firmware 1.3 for the Video:
`http://appldnld.apple.com.edgesuite.net/content.info.apple.com/iPod/SBML/osx/bundles/061-2967.20080313.Cnvkg/iPod_25.1.3.ipsw`

Firmware files and dumps are git-ignored. Don't commit them.

## Workflow

```sh
# 1. Back up the iPod's firmware partition (raw disk access needs sudo)
sudo .venv/bin/ipodfw devices
sudo .venv/bin/ipodfw backup -o backups/firmware-backup.bin

# 2. Unpack, edit, repack
uv run ipodfw unpack backups/firmware-backup.bin -o work
#    edit work/pictures/*.png (same size) and work/strings/*.json
uv run ipodfw repack backups/firmware-backup.bin work -o custom.bin
uv run ipodfw verify custom.bin

# 3. (optional) try it in the emulator first
uv run ipodfw pack-ipsw iPod_25.1.3.ipsw custom.bin -o custom.ipsw   # see re/emulator.md

# 4. Flash: only changed blocks are written, then read back and verified
sudo .venv/bin/ipodfw flash custom.bin --dry-run
sudo .venv/bin/ipodfw flash custom.bin

# Undo
sudo .venv/bin/ipodfw restore backups/firmware-backup.bin
```

If your iPod runs stock 1.3, the osos in your backup is identical to the one in the `.ipsw`. That means a single `work/` folder can be repacked onto either file.

## Commands

| Command | What it does |
|---|---|
| `extract IPSW` | Pull the firmware partition image out of an Apple `.ipsw` |
| `info FILE [-r]` | Directory, image checksums, model; `-r` lists resource blocks |
| `verify FILE` | Check checksums and that resources parse |
| `unpack FILE -o DIR` | Export pictures (PNG) and strings (JSON per language block) |
| `repack FILE DIR -o OUT` | Apply edits and fix the checksum |
| `pack-ipsw IPSW FILE -o OUT` | Wrap a customised firmware back into an `.ipsw` |
| `devices` / `backup` / `flash` / `restore` | Device side (sudo) |

## Safety rules built into `flash`

- It needs a backup, and refuses unless the backup and the new image have the same layout as the iPod's current partition.
- **`aupd` (the boot-flash updater) is never modified.** Flashing is refused if `aupd` would differ, or if any write would overlap it.
- Only changed blocks are written, then each one is read back and verified.
- If the iPod won't boot afterwards: reset (Menu+Select), hold Select+Play for disk mode, then run `ipodfw restore`. Restoring in Finder also returns it to stock.

> **Status:** the firmware-file tooling is tested against Apple's real 1.3 firmware. The device commands have not yet been run on a physical iPod, so start with `--dry-run`.

## Credits

Formats ported from [iPodWizard](https://sourceforge.net/projects/ipodwizard/) and Rockbox [`ipodpatcher`](https://github.com/Rockbox/rockbox/tree/master/utils/ipodpatcher), both GPLv2. This project is therefore GPL-2.0-or-later.
