"""ipodfw command line."""

from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import os
import sys
from pathlib import Path

from . import device, resources, theme
from .ipsw import extract_firmware, repack_ipsw
from .partition import FirmwareError, FirmwarePartition
from .pictures import PictureError


def load(path: str) -> FirmwarePartition:
    return FirmwarePartition(Path(path).read_bytes())


def cmd_extract(args) -> None:
    name, data = extract_firmware(args.ipsw)
    FirmwarePartition(data)  # validate
    Path(args.output).write_bytes(data)
    print(f"Extracted {name} ({len(data)} bytes) -> {args.output}")


def cmd_pack_ipsw(args) -> None:
    data = Path(args.firmware).read_bytes()
    FirmwarePartition(data)  # validate
    name = repack_ipsw(args.ipsw, data, args.output)
    print(f"Wrote {args.output} ({name} replaced with {args.firmware})")


def cmd_make_library(args) -> None:
    from .itunesdb import make_library
    r = make_library(args.output, songs=args.songs, total_tracks=args.tracks)
    print(f"Wrote {r['tracks']} tracks ({r['songs']} audio files) under {r['path']}/iPod_Control")


def cmd_info(args) -> None:
    fw = load(args.firmware)
    print(f"Model:            {fw.model}")
    print(f"Format version:   {fw.format_version}")
    print(f"Directory offset: 0x{fw.dir_offset:x}")
    print(f"Image base:       {fw.image_base} bytes")
    print()
    print(f"{'image':6} {'devOffset':>10} {'length':>10} {'addr':>10} {'entryOff':>9} {'chksum':>10} {'vers':>6}  checksum")
    for e in fw.entries:
        if e.name == "aupd":
            state = "not checked (encrypted; never modified)"
        elif e.name == "hibe":
            state = "not checked (iPod's own hibernation snapshot; left untouched)"
        else:
            state = "OK" if fw.checksum_ok(e.name) else "BAD"
        print(f"{e.name:6} {e.dev_offset:#10x} {e.length:#10x} {e.addr:#10x} {e.entry_offset:#9x} "
              f"{e.chksum:#10x} {e.vers:#6x}  {state}")
    if fw.entry("osos").entry_offset:
        print("\nNote: osos has a third-party (Rockbox) bootloader appended; it is preserved.")
    if args.resources:
        osos = fw.image("osos")[:fw.apple_os_length()]
        print()
        for b in resources.scan(osos):
            secs = ", ".join(f"{t.strip()}x{n}" for t, n, _t1, _s in b.sections)
            print(f"resource block {b.index:2d} @0x{b.start:x}: {secs}")


def cmd_unpack(args) -> None:
    fw = load(args.firmware)
    out = Path(args.output)
    manifest = theme.unpack(fw, out)
    print(f"Unpacked {len(manifest['pictures'])} pictures and "
          f"{len(manifest['string_blocks'])} string blocks -> {out}/")
    print("Edit the PNGs (keep the same size) or the strings JSON, then run 'ipodfw repack'.")


def cmd_repack(args) -> None:
    fw = load(args.firmware)
    report = theme.repack(fw, Path(args.workdir), force=args.force)
    for f in report.pictures_changed:
        print(f"  picture  {f}")
    for f in report.string_blocks_changed:
        print(f"  strings  {f}")
    if not report.changed:
        print("No changes found; nothing written.")
        return
    Path(args.output).write_bytes(fw.to_bytes())
    print(f"Wrote {args.output} (osos checksum updated: 0x{fw.entry('osos').chksum:08x})")


def cmd_import_theme(args) -> None:
    from . import themeimport
    theme_fw, sha = themeimport.load_firmware(args.theme)
    base_fw, _ = themeimport.load_firmware(args.base)
    target_fw, _ = themeimport.load_firmware(args.target)
    th = themeimport.make_theme(theme_fw, base_fw, target_fw, args.name or Path(args.theme).stem, sha)
    Path(args.output).write_text(th.to_json())
    print(f"Imported {len(th.imported)} resources ({len(th.changes)} changes) -> {args.output}")
    for r, why in th.skipped:
        print(f"  not imported: {r}: {why}")


def cmd_strip_theme(args) -> None:
    from . import themeimport
    th = themeimport.Theme.from_json(Path(args.theme).read_text())
    Path(args.output).write_text(th.to_json(stripped=True))
    print(f"Wrote {args.output} in format 2 ({len(th.changes)} changes, no bytes of the Apple firmware)")


def cmd_apply_theme(args) -> None:
    from . import themeimport
    fw = load(args.firmware)
    th = themeimport.Theme.from_json(Path(args.theme).read_text())
    original = hashlib.sha256(fw.image("osos")).hexdigest()
    if args.switch:
        from . import darkmode
        osos, info = darkmode.build(fw, fw.image("osos"), th, Path(__file__).resolve().parents[2] / "patches" / "dark-mode",
                                    original)
        fw.make_room(len(osos))
        fw.replace_image("osos", osos)
        Path(args.output).write_bytes(fw.to_bytes())
        print(f"Light firmware with the Dark Mode item in Settings -> {args.output}")
        print(f"  switch table at 0x{info['table'][0]:x} ({info['table'][1]} bytes), menu at 0x{info['menu'][0]:x}, "
              f"patch {info['patch'][0]}-{info['patch'][1]}, {info['changes_left_out']} changes left out")
        print(f"  The iPod needs the file {darkmode.SETTING_FILE} (one byte, '0' or '1').")
        return
    osos = bytearray(fw.image("osos"))
    done, conflicts = themeimport.apply_theme(th, osos, original)
    fw.make_room(len(osos))
    fw.replace_image("osos", bytes(osos))
    Path(args.output).write_bytes(fw.to_bytes())
    print(f"Applied {done} changes, {conflicts} not applied -> {args.output}")


def cmd_verify(args) -> None:
    fw = load(args.firmware)
    bad = [e.name for e in fw.entries if e.name in ("osos", "rsrc") and not fw.checksum_ok(e.name)]
    if bad:
        sys.exit(f"Checksum FAILED for: {', '.join(bad)}")
    resources.main_block(resources.scan(fw.image("osos")[:fw.apple_os_length()]))
    print(f"{args.firmware}: OK ({fw.model})")


def require_root() -> None:
    if os.geteuid() != 0:
        sys.exit("Raw disk access needs root. Re-run with sudo, e.g.  sudo .venv/bin/ipodfw ...")


def cmd_devices(args) -> None:
    ipods = device.find_ipods()
    if not ipods:
        print("No iPod found.")
    for i in ipods:
        print(f"/dev/{i.disk}: {i.media_name}, {i.size / 1e9:.1f} GB, {i.block_size}-byte blocks")


def cmd_install_games(args) -> None:
    from . import games
    source = Path(args.source)
    # The source can be the folder with the games, or the folder iPod_Control of an iPod.
    games_dir = games.games_directory(source)
    if games_dir is None:
        games_dir = source
    library = games.load_library(games_dir)
    if not library:
        sys.exit(f"The folder {games_dir} has no game with a file Manifest.plist.")
    print(f"Games in {games_dir}: {len(library)}")
    for g in library:
        problems = games.check_game(g)
        state = "complete" if not problems else f"INCOMPLETE: {problems[0]}"
        print(f"    {g.folder:<10} {g.name:<20} {state}")

    # The option --game selects the games. Without the option, the app copies all the games.
    if args.game:
        wanted = [g for g in library if g.folder in args.game]
        missing = [name for name in args.game if name not in {g.folder for g in library}]
        if missing:
            sys.exit("The folder has no game with the name " + ", ".join(missing) + ".")
    else:
        wanted = library
    if args.key_file:
        problem = games.check_key_file(args.key_file)
        if problem:
            sys.exit(problem)
    print()
    print(f"Copying {len(wanted)} game(s).")
    report = games.install_library(wanted, args.target,
                                   copy_key_file=bool(args.key_file),
                                   key_file_source=args.key_file)
    print(f"Copied {len(report.installed)} game(s), {report.bytes_copied} bytes -> {Path(args.target) / 'games_RO'}")
    for folder in report.installed:
        print(f"    {folder}")
    for warning in report.warnings:
        print(f"    skipped: {warning}")
    if report.key_file_copied:
        print(f"    copied the file {games.KEY_FILE_NAME}")


def cmd_remove_games(args) -> None:
    from . import games
    target = Path(args.target)
    # The target can be the folder iPod_Control of an iPod, or a copy of it.
    games_dir = games.games_directory(target)
    if games_dir is None:
        sys.exit(f"The folder {target} has no folder of the games.")
    on_ipod = games.removable_folders(games_dir)
    if args.game:
        wanted = [g for g in args.game if g in on_ipod]
        missing = [g for g in args.game if g not in on_ipod]
        if missing:
            sys.exit("The iPod has no game with the GUID " + ", ".join(missing) + ".")
    else:
        wanted = on_ipod
    if not wanted:
        sys.exit("The folder has no game.")
    print(f"Removing {len(wanted)} game(s) from {games_dir}.")
    report = games.remove_games(target, wanted)
    print(f"Removed {len(report.removed)} game(s).")
    for guid in report.removed:
        print(f"    {guid}")
    for guid, why in zip(report.missing, report.warnings):
        print(f"    refused: {guid}: {why}")


def cmd_backup(args) -> None:
    require_root()
    ipod = device.pick_ipod(args.disk)
    with device.RawDisk(ipod) as disk:
        data = device.read_partition(disk)
    fw = FirmwarePartition(data)
    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(data)
    meta = {
        "disk": ipod.disk, "media_name": ipod.media_name, "block_size": ipod.block_size,
        "model": fw.model, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
        "created": datetime.datetime.now().isoformat(timespec="seconds"),
    }
    Path(str(out) + ".json").write_text(json.dumps(meta, indent=1) + "\n")
    print(f"Backed up {len(data)} bytes of firmware partition ({fw.model}) -> {out}")
    print("Keep this file safe: 'ipodfw restore' puts it back byte for byte.")


def _flash(image_path: str, backup_path: str, disk: str | None, dry_run: bool, what: str) -> None:
    require_root()
    if not Path(backup_path).exists():
        sys.exit(f"Backup {backup_path} not found. Run 'ipodfw backup' first.")
    ipod = device.pick_ipod(disk)
    ranges = device.flash(ipod, Path(image_path).read_bytes(), Path(backup_path).read_bytes(), dry_run)
    total = sum(n for _o, n in ranges)
    if not ranges:
        print("The iPod already has this firmware; nothing to write.")
    elif dry_run:
        print(f"Dry run: would write {total} bytes in {len(ranges)} range(s) to /dev/{ipod.disk}:")
        for off, n in ranges[:20]:
            print(f"  partition offset 0x{off:08x}  {n} bytes")
    else:
        print(f"{what}: wrote and verified {total} bytes in {len(ranges)} range(s).")
        print("Eject the iPod. If it fails to boot: reset (Menu+Select), hold Select+Play for disk mode, "
              "then run 'ipodfw restore'.")


def cmd_flash(args) -> None:
    _flash(args.firmware, args.backup, args.disk, args.dry_run, "Flashed")


def cmd_restore(args) -> None:
    if args.rescue:
        _rescue(args)
    else:
        _flash(args.backup, args.backup, args.disk, args.dry_run, "Restored")


def _rescue(args) -> None:
    """Restore onto a firmware partition that no longer parses; the reference backup replaces the iPod's firmware in the checks."""
    require_root()
    reference = args.reference or args.backup
    for path in (args.backup, reference):
        if not Path(path).exists():
            sys.exit(f"Backup {path} not found.")
    ipod = device.pick_ipod(args.disk)
    ranges, damaged = device.rescue_restore(ipod, Path(args.backup).read_bytes(), Path(reference).read_bytes(), args.dry_run)
    total = sum(n for _o, n in ranges)
    if not ranges:
        print("The iPod already has this firmware; nothing to write.")
    elif args.dry_run:
        print(f"Dry run: rescue would write {total} bytes in {len(ranges)} range(s) to /dev/{ipod.disk}.")
    else:
        keep = Path(args.backup).with_name(f"damaged-{datetime.datetime.now():%Y%m%d-%H%M%S}.bin")
        keep.write_bytes(damaged)
        print(f"Rescued: wrote and verified {total} bytes in {len(ranges)} range(s).")
        print(f"The damaged partition is in {keep}. Do not restore that file.")


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(prog="ipodfw", description="Customise Apple's stock iPod Video (5G/5.5G) firmware.")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("extract", help="pull the firmware partition image out of an Apple .ipsw")
    s.add_argument("ipsw")
    s.add_argument("-o", "--output", default="firmware.bin")
    s.set_defaults(func=cmd_extract)

    s = sub.add_parser("pack-ipsw", help="wrap a customised firmware back into an .ipsw (e.g. for the emulator)")
    s.add_argument("ipsw", help="the original Apple .ipsw")
    s.add_argument("firmware")
    s.add_argument("-o", "--output", required=True)
    s.set_defaults(func=cmd_pack_ipsw)

    s = sub.add_parser("make-library", help="write a test music library (iPod_Control) for an emulated iPod")
    s.add_argument("-o", "--output", required=True)
    s.add_argument("--songs", type=int, default=6, help="distinct audio files")
    s.add_argument("--tracks", type=int, help="total tracks (simulate a big library)")
    s.set_defaults(func=cmd_make_library)

    s = sub.add_parser("info", help="show the firmware directory and checksums")
    s.add_argument("firmware")
    s.add_argument("-r", "--resources", action="store_true", help="also list resource blocks in osos")
    s.set_defaults(func=cmd_info)

    s = sub.add_parser("verify", help="check image checksums and that resources parse")
    s.add_argument("firmware")
    s.set_defaults(func=cmd_verify)

    s = sub.add_parser("unpack", help="export pictures (PNG) and strings (JSON) for editing")
    s.add_argument("firmware")
    s.add_argument("-o", "--output", default="work")
    s.set_defaults(func=cmd_unpack)

    s = sub.add_parser("repack", help="apply edited PNGs/strings to a firmware image")
    s.add_argument("firmware", help="the same file the folder was unpacked from")
    s.add_argument("workdir")
    s.add_argument("-o", "--output", required=True)
    s.add_argument("--force", action="store_true", help="allow a folder unpacked from a different firmware")
    s.set_defaults(func=cmd_repack)

    s = sub.add_parser("import-theme", help="make an iPodFirm theme from an iPodWizard theme (e.g. a 1.2.1 theme for 1.3)")
    s.add_argument("theme", help="the iPodWizard theme: a firmware partition image or .ipsw")
    s.add_argument("base", help="the Apple firmware that the theme came from (.ipsw or image)")
    s.add_argument("target", help="the Apple firmware to make the theme for (.ipsw or image)")
    s.add_argument("-o", "--output", required=True, help="theme file to write (JSON)")
    s.add_argument("--name", help="name of the theme")
    s.set_defaults(func=cmd_import_theme)

    s = sub.add_parser("strip-theme", help="write a theme in format 2: hashes in place of the Apple bytes")
    s.add_argument("theme", help="the theme file to read (JSON)")
    s.add_argument("-o", "--output", required=True, help="theme file to write (JSON)")
    s.set_defaults(func=cmd_strip_theme)

    s = sub.add_parser("apply-theme", help="apply an iPodFirm theme to a firmware image")
    s.add_argument("firmware")
    s.add_argument("theme")
    s.add_argument("-o", "--output", required=True)
    s.add_argument("--switch", action="store_true",
                   help="light firmware with a Dark Mode item in Settings (the iPod switches at a restart)")
    s.set_defaults(func=cmd_apply_theme)

    s = sub.add_parser("devices", help="list connected iPods")
    s.set_defaults(func=cmd_devices)

    s = sub.add_parser("install-games", help="copy the games to the iPod_Control folder of an iPod")
    s.add_argument("source", help="the folder with the games, or the folder iPod_Control of an iPod")
    s.add_argument("target", help="the folder iPod_Control of the target iPod")
    s.add_argument("--game", action="append", default=[], metavar="GUID",
                   help="copy only this game; use the option more than once for more games")
    s.add_argument("--all", action="store_true", help="copy all the games (the default)")
    s.add_argument("--key-file", help="the file IC-Info.sidb to copy to the target iPod")
    s.set_defaults(func=cmd_install_games)

    s = sub.add_parser("remove-games", help="remove games from the iPod_Control folder of an iPod")
    s.add_argument("target", help="the folder iPod_Control of the iPod, or a copy of it")
    s.add_argument("--game", action="append", default=[], metavar="GUID",
                   help="remove only this game; use the option more than once for more games")
    s.add_argument("--all", action="store_true", help="remove all the games")
    s.set_defaults(func=cmd_remove_games)

    s = sub.add_parser("backup", help="dump the iPod's whole firmware partition (sudo)")
    s.add_argument("-o", "--output", default="backups/firmware-backup.bin")
    s.add_argument("--disk")
    s.set_defaults(func=cmd_backup)

    s = sub.add_parser("flash", help="write a customised firmware image to the iPod (sudo)")
    s.add_argument("firmware")
    s.add_argument("--backup", default="backups/firmware-backup.bin")
    s.add_argument("--disk")
    s.add_argument("--dry-run", action="store_true")
    s.set_defaults(func=cmd_flash)

    s = sub.add_parser("restore", help="write a backup back to the iPod (sudo)")
    s.add_argument("backup", nargs="?", default="backups/firmware-backup.bin")
    s.add_argument("--disk")
    s.add_argument("--dry-run", action="store_true")
    s.add_argument("--rescue", action="store_true",
                   help="the firmware on the iPod is damaged: compare the backup with --reference instead")
    s.add_argument("--reference", help="first backup of this iPod (default: the backup itself)")
    s.set_defaults(func=cmd_restore)

    args = p.parse_args(argv)
    try:
        args.func(args)
    except (FirmwareError, resources.ResourceError, PictureError) as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
