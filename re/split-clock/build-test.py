#!/usr/bin/env python3
"""Emulator test of the split-clock patch: the Split layout with the 3 clock lines, and the patch.

Research only. Refer to re/split-clock.md.

Usage: uv run python re/split-clock/build-test.py iPod_25.1.3.ipsw OUTPUT.ipsw [--half] [--dark THEME] [--patch DIR] [--option ID=VALUE]...

--patch uses a test copy of the patch, for example a copy with counters.
--option sets an option of patch.json, for example --option pause_time=30. --option face=1 also adds the
clock face to the layout (the option Analogue).
"""
import json
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "src"))

from ipodfw import darkmode, patcher  # noqa: E402
from ipodfw.ipsw import extract_firmware, repack_ipsw  # noqa: E402
from ipodfw.partition import FirmwarePartition  # noqa: E402
from ipodfw.themeimport import (Theme, _sha256, apply_theme, half_width, moved_layout,  # noqa: E402
                                with_clock)


def main() -> None:
    args = sys.argv[1:]
    ipsw, out_path = Path(args[0]), Path(args[1])
    theme = Theme.from_json(Path(args[args.index("--dark") + 1]).read_text()) if "--dark" in args else None
    patch_dir = Path(args[args.index("--patch") + 1]) if "--patch" in args else repo / "patches/split-clock"
    options = {a.split("=")[0]: int(a.split("=")[1]) for k, a in zip(args, args[1:]) if k == "--option"}
    split = Theme.from_json((repo / "themes/layouts/Split.ipodtheme").read_text())
    if "--half" in args:
        split = half_width(split)
    split = with_clock(split, analogue=options.get("face") == 1)
    _, data = extract_firmware(ipsw)
    fw = FirmwarePartition(data)
    stock = bytes(fw.image("osos"))
    sha = _sha256(stock)
    osos = bytearray(stock)
    if theme:
        apply_theme(theme, osos, sha)
    layout = moved_layout(split, bytes(darkmode._align(max(len(osos), darkmode.PATCH_AREA_END), 16)), theme is not None)
    apply_theme(layout, osos, sha)
    code, report = patcher.apply(bytes(osos), patch_dir, patcher.PATCH_AREA_END,
                                 original_sha256=sha, options=options)
    fw.make_room(len(code))
    fw.replace_image("osos", code)
    repack_ipsw(ipsw, fw.to_bytes(), out_path)
    print(json.dumps({"view": [hex(layout.changes[0].offset), len(layout.changes[0].new)],
                      "code": report["code"], "symbols": report["symbols"], "osos": len(code)}, indent=1))


if __name__ == "__main__":
    main()
