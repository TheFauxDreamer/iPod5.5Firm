#!/usr/bin/env python3
"""Emulator test of the panel shade: Split 1/2, a label behind the panel, and the test patch in patch/.

The label has the element ID of the count (0x63c3), so that the firmware draws it. The patch fills it.
Research only. Refer to re/home-screen.md, section "Panel shade".

Usage: uv run python re/split-shade/build-code-test.py iPod_25.1.3.ipsw OUTPUT.ipsw
"""
import sys, struct
from pathlib import Path
repo = Path(__file__).resolve().parents[2]; sys.path.insert(0, str(repo / "src"))
from ipodfw.ipsw import extract_firmware, repack_ipsw
from ipodfw.partition import FirmwarePartition
from ipodfw.resources import main_block, scan
from ipodfw.themeimport import Theme, _sha256, apply_theme, half_width, view_elements
from ipodfw import patcher
ipsw, out = Path(sys.argv[1]), Path(sys.argv[2])
patch_dir = Path(__file__).resolve().parent / "patch"
_, data = extract_firmware(ipsw)
fw = FirmwarePartition(data)
osos = bytearray(fw.image("osos"))
stock = bytes(osos); stock_sha = _sha256(stock)
blk = main_block(scan(stock))
menu = next(r for r in blk.of_type("View") if r.id == 24430)
print("layout", apply_theme(half_width(Theme.from_json((repo / "themes/layouts/Split.ipodtheme").read_text())), osos, stock_sha))
at = 0x736800
view = bytes(osos[at:at + 704])
el = bytearray(view[608:704])           # the count line: a general label (0x1580)
assert struct.unpack_from("<I", el, 4)[0] == 0x1580
struct.pack_into("<I", el, 12, 0x63c3)  # the element ID: the count
for k, v in enumerate((0, 160, 0, 0)):  # top, left, bottom, right from the parent
    struct.pack_into("<III", el, 28 + 12 * k, 0, 0x80000002, v & 0xffffffff)
new = struct.pack("<I", 8) + view[4:208] + bytes(el) + view[208:]
assert len(view_elements(new)) == 8
osos[at:at + len(new)] = new
struct.pack_into("<I", osos, menu.table_pos + 8, len(new))
code, report = patcher.apply(bytes(osos), patch_dir, patcher.PATCH_AREA_END, original_sha256=stock_sha)
print("report", {k: (hex(v) if isinstance(v, int) else v) for k, v in report.items()})
fw.make_room(len(code)); fw.replace_image("osos", code)
repack_ipsw(ipsw, fw.to_bytes(), out)
print("osos", len(code))
