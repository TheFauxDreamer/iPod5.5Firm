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
    _flash(args.backup, args.backup, args.disk, args.dry_run, "Restored")


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

    s = sub.add_parser("devices", help="list connected iPods")
    s.set_defaults(func=cmd_devices)

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
    s.set_defaults(func=cmd_restore)

    args = p.parse_args(argv)
    try:
        args.func(args)
    except (FirmwareError, resources.ResourceError, PictureError) as e:
        sys.exit(f"error: {e}")


if __name__ == "__main__":
    main()
