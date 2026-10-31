#!/usr/bin/env python3
"""Make test firmware files for the split home screen research.

The files go to the emulator only. Do not install them on an iPod.

Usage: uv run python re/home-screen-views.py iPod_25.1.3.ipsw OUTPUT_FOLDER
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from ipodfw.ipsw import extract_firmware, repack_ipsw  # noqa: E402
from ipodfw.partition import FirmwarePartition  # noqa: E402
from ipodfw.resources import main_block, scan  # noqa: E402
from ipodfw.themeimport import view_elements  # noqa: E402

MAIN_MENU = 24430
BOTTOM = 60  # offset of the value of the bottom edge in an element
RIGHT = 72  # offset of the value of the right edge in an element

# (name, [(element index, edge offset, value)])
TESTS = [
    ("narrow-list", [(0, RIGHT, -107)]),  # the list follows the left edge of the scroll bar
    ("short-list", [(0, BOTTOM, -64), (1, BOTTOM, -64)]),
]


def make(fw: FirmwarePartition, edits: list[tuple[int, int, int]]) -> bytes:
    osos = bytearray(fw.image("osos"))
    block = main_block(scan(bytes(osos)))
    res = next(r for r in block.of_type("View") if r.id == MAIN_MENU)
    start = block.abs(res)
    elements = view_elements(bytes(osos[start:start + res.size]))
    if elements is None or len(elements) != 2:
        raise SystemExit("View 24430 is not the known View of firmware 1.3")
    for index, edge, value in edits:
        at = start + elements[index][0] + edge
        if struct.unpack_from("<i", osos, at)[0] != 0:
            raise SystemExit("View 24430 has an unknown value")
        struct.pack_into("<i", osos, at, value)
    fw.replace_image("osos", bytes(osos))
    return fw.to_bytes()


def main() -> None:
    ipsw, out = Path(sys.argv[1]), Path(sys.argv[2])
    _, data = extract_firmware(ipsw)
    for name, edits in TESTS:
        new = make(FirmwarePartition(data), edits)
        repack_ipsw(ipsw, new, out / f"home-screen-{name}.ipsw")
        print(out / f"home-screen-{name}.ipsw")


if __name__ == "__main__":
    main()
