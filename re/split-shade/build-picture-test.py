#!/usr/bin/env python3
"""Emulator test: a stock BMap element behind the Split panel. Does a small picture stretch or repeat?

Result (3 November 2026): no. The element draws the picture one time at the top left.
Research only. Refer to re/home-screen.md, section "Panel shade".

Usage: uv run python re/split-shade/build-picture-test.py iPod_25.1.3.ipsw OUTPUT.ipsw
"""
import sys, struct
from pathlib import Path
repo = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(repo / "src"))
from ipodfw.ipsw import extract_firmware, repack_ipsw
from ipodfw.partition import FirmwarePartition
from ipodfw.resources import main_block, scan
from ipodfw.themeimport import Theme, _sha256, apply_theme, half_width, view_elements
ipsw, out = Path(sys.argv[1]), Path(sys.argv[2])
_, data = extract_firmware(ipsw)
fw = FirmwarePartition(data)
osos = bytearray(fw.image("osos"))
stock = bytes(osos)
# a stock BMap element of 88 bytes with picture 24291 (View 24659)
blk = main_block(scan(stock))
src = None
for r in blk.of_type("View"):
    if r.id == 24659:
        d = stock[blk.abs(r):blk.abs(r) + r.size]
        src = next(d[p:p + s] for p, s, t, i in view_elements(d) if t == "BMap" and i == 24291)
menu = next(r for r in blk.of_type("View") if r.id == 24430)
print(apply_theme(half_width(Theme.from_json((repo / "themes/layouts/Split.ipodtheme").read_text())), osos, _sha256(stock)))
at = 0x736800
view = bytes(osos[at:at + 704])
el = bytearray(src)
# rect words start at offset 28: (0, mode, value) x 4 = top, left, bottom, right, all from the parent
for k, v in enumerate((0, 160, 0, 0)):
    struct.pack_into("<III", el, 28 + 12 * k, 0, 0x80000002, v & 0xffffffff)
new = struct.pack("<I", 8) + view[4:208] + bytes(el) + view[208:]
assert view_elements(new) is not None and len(view_elements(new)) == 8
osos[at:at + len(new)] = new
struct.pack_into("<I", osos, menu.table_pos + 8, len(new))
fw.make_room(len(osos)); fw.replace_image("osos", bytes(osos))
repack_ipsw(ipsw, fw.to_bytes(), out)
print("view", len(new), "osos", len(osos), "element", el.hex())
