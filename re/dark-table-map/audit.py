"""Research only: do the steps after DarkMode.build write into a range of the dark switch table?

Usage: python3 re/dark-table-map/audit.py <iPod_25.1.3.ipsw>

The app makes the firmware in this sequence (AppModel.outputOSOS): DarkMode.build (the theme, the
layout, the switch tables and the dark-mode patch), then the other patches and the iPodFirm list,
then the firmware version. The switch table is made before the later steps. If a later step writes
a byte that the table also writes, the iPod shows a wrong result in dark mode:
  - IFDM (XOR): the byte becomes (patch byte) XOR (light byte) XOR (dark byte).
  - IFD2 RAW or PAL: the dark byte replaces the patch byte. IFD2 MAP: the map changes the patch byte
    if it is a light colour of the map.
The script makes the build with Dark Gray and the Split layout with both switches. It then applies
each patch alone, and all patches together, and compares the changed bytes with the ranges of both
tables. The firmware version writes only 0x9ee70..0x9eed8 (FirmwareVersion.swift). The iPodFirm list
goes after the last patch.
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "src"))
sys.path.insert(0, str(HERE))
import check                                                       # noqa: E402
import ifd2                                                        # noqa: E402
from ipodfw import darkmode, patcher, themeimport                  # noqa: E402

VERSION_RANGE = (0x9EE70, 0x9EED8)
# Only one patch of each set can be on at a time (Patcher.conflicts: the same hook address).
ONE_OF = ({"diagnostic-log", "playback-log"}, {"usb-audio-out", "usb-host-probe"})


def changed_ranges(a: bytes, b: bytes) -> list[tuple[int, int]]:
    out, i, n = [], 0, min(len(a), len(b))
    while i < n:
        if a[i] == b[i]:
            i += 1
            continue
        j = i
        while j < n and a[j] != b[j]:
            j += 1
        out.append((i, j))
        i = j
    return out


def hits(changes, ranges) -> list[tuple[int, int]]:
    ranges = sorted(ranges)
    out = []
    for s, t in changes:
        for a, e in ranges:
            if a < t and e > s:
                out.append((max(a, s), min(e, t)))
    return out


def patch_dirs() -> dict[str, Path]:
    out = {}
    for p in sorted((REPO / "patches").glob("*/patch.json")):
        spec = json.loads(p.read_text())
        if spec["name"] != "dark-mode":
            out[spec["name"]] = p.parent
    return out


def apply_list(osos: bytes, names: list[str], dirs: dict[str, Path], sha: str, limit: int = themeimport.OSOS_LIMIT) -> bytes:
    out = osos
    for name in names:
        out, _ = patcher.apply(out, dirs[name], limit, original_sha256=sha, pad=False)
    return out


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    fw, _ = themeimport.load_firmware(sys.argv[1])
    image = themeimport._Image(fw)
    osos, sha = bytes(image.osos), darkmode.stock_sha256(fw)
    theme = themeimport.Theme.from_json((REPO / "themes/Dark Gray.ipodtheme").read_text())
    layout = themeimport.Theme.from_json((REPO / "themes/layouts/Split.ipodtheme").read_text())
    built, info = darkmode.build(fw, osos, theme, REPO / "patches/dark-mode", sha, layout=layout, layout_switch=True)
    at, n = info["table"]
    lat, ln = info["layout_table"]
    ifdm = built[at:at + n]
    dark = bytearray(built)
    darkmode.apply_switch_table(dark, ifdm)
    table, _ = ifd2.encode(built, bytes(dark), check.picture_ranges(image))
    ranges = {"IFDM": ifd2.covered_ranges(ifdm) + ifd2.covered_ranges(built[lat:lat + ln]),
              "IFD2": ifd2.covered_ranges(table) + ifd2.covered_ranges(built[lat:lat + ln])}
    for name, r in ranges.items():
        print(f"{name}: {len(r)} ranges, {sum(e - a for a, e in r):,} bytes, 0x{min(a for a, _ in r):x}..0x{max(e for _, e in r):x}")
    print(f"Firmware version range 0x{VERSION_RANGE[0]:x}..0x{VERSION_RANGE[1]:x}: "
          + ", ".join(f"{k} {len(hits([VERSION_RANGE], r))} hits" for k, r in ranges.items()))
    dirs = patch_dirs()
    bad = 0
    for name, d in dirs.items():
        spec = json.loads((d / "patch.json").read_text())
        names = [*spec.get("needs", []), name]
        try:
            out = apply_list(built, names, dirs, sha)
        except patcher.PatchError as e:
            print(f"  {name:22} not applied: {e}")
            continue
        ch = changed_ranges(built, out)
        h = {k: hits(ch, r) for k, r in ranges.items()}
        bad += sum(map(len, h.values()))
        print(f"  {name:22} {len(ch):4} changed runs ({sum(t - s for s, t in ch):,} bytes): "
              + ", ".join(f"{k} {len(v)} hits" for k, v in h.items()))
    together = [n for n in dirs if not any(n in g and n != sorted(g)[0] for g in ONE_OF)]
    order = sorted(together, key=lambda n: (n not in {"shuffle-fixes"}, n))
    # With the IFDM table, all patches together do not fit below OSOS_LIMIT. The hooks and the byte
    # changes have fixed addresses, so a larger limit (0x900000, only here) does not change them.
    keep = patcher.OSOS_LIMIT
    patcher.OSOS_LIMIT = 0x900000
    try:
        out = apply_list(built, order, dirs, sha, 0x900000)
    finally:
        patcher.OSOS_LIMIT = keep
    ch = changed_ranges(built, out)
    h = {k: hits(ch, r) for k, r in ranges.items()}
    bad += sum(map(len, h.values()))
    print(f"  all {len(order)} together        {len(ch):4} changed runs: "
          + ", ".join(f"{k} {len(v)} hits" for k, v in h.items()))
    print(f"  end of the image with all patches: 0x{len(out):x} (limit 0x{themeimport.OSOS_LIMIT:x})")
    print("Result:", "no step after DarkMode.build writes into a table range." if bad == 0 else f"{bad} hits")


if __name__ == "__main__":
    main()
