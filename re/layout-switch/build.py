#!/usr/bin/env python3
"""Research prototype: make a firmware with a Split View item in Settings (and a Dark Mode item).

The image has the Split main menu. The layout table changes the table entry of View 24430 back to the
stock View. Refer to re/home-screen.md, section "Layout switch on the iPod".

Usage: uv run python re/layout-switch/build.py iPod_25.1.3.ipsw OUTPUT.ipsw APPEARANCE [THEME] [--half]
APPEARANCE is light, dark or switch. THEME is an .ipodtheme file (for dark and switch).
"""
import json
import struct
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(repo / "src"))

from ipodfw import darkmode, patcher  # noqa: E402
from ipodfw.ipsw import extract_firmware, repack_ipsw  # noqa: E402
from ipodfw.partition import FirmwarePartition  # noqa: E402
from ipodfw.themeimport import (OSOS_LIMIT, Theme, _Image, _sha256, _with_copied_bytes, apply_theme,  # noqa: E402
                                half_width, moved_layout)

PATCH_DIR = Path(__file__).resolve().parent / "patch"
LAYOUT_KEY = 0x60007E15             # the key of the Split View item (patch: LAYOUT_KEY)
LAYOUT_LABEL = 0x7E14               # the label "Split View" (patch: LAYOUT_LABEL)
EMPTY_TABLE = struct.pack("<III", darkmode.MAGIC, 0, 12)


def layout_table(entry_at: int, stock: bytes, split: bytes) -> bytes:
    """One run: the 8 bytes of the table entry (offset and size), stock XOR Split."""
    return struct.pack("<IIIII", darkmode.MAGIC, 1, 20, entry_at, 8) + bytes(a ^ b for a, b in zip(stock, split))


def settings_menu(menu: bytes, dark_item: bool) -> bytes:
    if dark_item:
        menu = darkmode.settings_menu(menu)
    after = darkmode.DARK_KEY if dark_item else darkmode.INSERT_AFTER_KEY
    return patcher.insert_settings_item(menu, LAYOUT_KEY, LAYOUT_LABEL, after, darkmode.TEMPLATE_KEY)


def build(fw: FirmwarePartition, appearance: str, theme: Theme | None, split: Theme) -> tuple[bytes, dict]:
    stock = bytes(fw.image("osos"))
    sha = _sha256(stock)
    out = bytearray(stock)
    end = darkmode.PATCH_AREA_END
    dark_table = EMPTY_TABLE
    if appearance == "switch":
        # The theme data outside osos, the Split View (light form) and the dark switch table.
        for c in theme.with_old_bytes(stock).effective_changes():
            if c.offset + len(c.old) > len(stock):
                out += bytes(max(0, c.offset + len(c.new) - len(out)))
                out[c.offset:c.offset + len(c.new)] = c.new
                end = max(end, c.offset + len(c.new))
        view_at, view, entry, extra = darkmode.layout_parts(theme, split, stock, end)
        dark_table, _ = darkmode.switch_table(theme, stock, extra)
    else:
        if appearance == "dark":
            apply_theme(theme, out, sha)
            end = max(end, len(out))
        moved = moved_layout(split, bytes(darkmode._align(end, 16)), appearance == "dark")
        view_at = moved.changes[0].offset
        view = _with_copied_bytes(moved.changes[0], bytes(out)).new
        entry = moved.changes[1]
    out += bytes(max(0, view_at + len(view) - len(out)))
    out[view_at:view_at + len(view)] = view
    old_entry = bytes(out[entry.offset:entry.offset + 8])
    out[entry.offset:entry.offset + 8] = entry.new
    table = layout_table(entry.offset, old_entry, entry.new)
    end = view_at + len(view)
    dark_at = darkmode._align(end, 16)
    layout_at = darkmode._align(dark_at + len(dark_table), 16)
    image = _Image(fw)
    res, block = image.res[darkmode.SETTINGS_MENU], image.block_of[darkmode.SETTINGS_MENU]
    menu = settings_menu(stock[block.abs(res):block.abs(res) + res.size], appearance == "switch")
    menu_at = darkmode._align(layout_at + len(table), 16)
    patch_at = darkmode._align(menu_at + len(menu), 16)
    patched, report = patcher.apply(bytes(out), PATCH_DIR, OSOS_LIMIT, load_address=patch_at,
                                    symbols={"dark_table": dark_at, "layout_table": layout_at}, original_sha256=sha)
    out = bytearray(patched)
    out[dark_at:dark_at + len(dark_table)] = dark_table
    out[layout_at:layout_at + len(table)] = table
    out[menu_at:menu_at + len(menu)] = menu
    struct.pack_into("<II", out, res.table_pos + 4, menu_at - block.data_start, len(menu))
    code = [int(x, 16) if isinstance(x, str) else x for x in report["code"]]
    info = {"appearance": appearance, "view": [view_at, len(view)], "dark_table": [dark_at, len(dark_table)],
            "layout_table": [layout_at, len(table)], "menu": [menu_at, len(menu)],
            "code": [patch_at, code[1] - code[0]], "end": len(out), "added": len(out) - darkmode.PATCH_AREA_END,
            "stock_entry": old_entry.hex(), "split_entry": entry.new.hex()}
    return bytes(out), info


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--half"]
    ipsw, out_path, appearance = Path(args[0]), Path(args[1]), args[2]
    theme = Theme.from_json(Path(args[3]).read_text()) if len(args) > 3 else None
    split = Theme.from_json((repo / "themes/layouts/Split.ipodtheme").read_text())
    if "--half" in sys.argv:
        split = half_width(split)
    _, data = extract_firmware(ipsw)
    fw = FirmwarePartition(data)
    osos, info = build(fw, appearance, theme, split)
    fw.make_room(len(osos))
    fw.replace_image("osos", osos)
    repack_ipsw(ipsw, fw.to_bytes(), out_path)
    print(json.dumps({k: ([hex(v[0]), v[1]] if isinstance(v, list) else v) for k, v in info.items()}, indent=1))


if __name__ == "__main__":
    main()
