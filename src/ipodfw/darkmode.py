"""Build the firmware for the appearance "Switch on iPod": light at the start, with a Dark Mode
item in Settings.

RetailOS makes its screens one time, at the start, from the View resources. Thus the dark theme
cannot change while the iPod runs. The patch patches/dark-mode applies a switch table at the
start, before the first View is read, if the file iPod_Control/iTunes/iPodFirmDarkMode contains
'1'. The Settings item writes that file and restarts the iPod.

The build puts these items after the end of osos (below OSOS_LIMIT):
    the theme data that is outside osos (for example the background picture: in both modes)
    the switch table: "IFDM", u32 count N, u32 data offset, N x {u32 address, u32 length}, data
                      (old XOR new for each change, so the same table switches in both directions)
    the Settings menu with the Dark Mode item (the resource table entry points to it)
    the code of the patch (its symbol dark_table is the address of the table)
"""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path

from . import patcher
from .themeimport import OSOS_LIMIT, Change, Theme, _Image, _with_copied_bytes, apply_theme, moved_layout
from .partition import FirmwarePartition

MAGIC = 0x4D444649                  # "IFDM"
SETTINGS_MENU = ("main", "Menu", 24598)
TEMPLATE_KEY = 0x600060B7           # the Sound Check item: an On/Off item
INSERT_AFTER_KEY = 0x60006088       # the Clicker item
DARK_KEY = 0x600060E0               # the key of the Dark Mode item (patch: KEY)
LABEL_ID = 0x7E00                   # the label "Dark Mode" (patch: LABEL_ID)
PATCH_AREA_END = 0x736800           # the other patches use the area before this address
SETTING_FILE = "iPod_Control/iTunes/iPodFirmDarkMode"


class DarkModeError(Exception):
    pass


def _align(n: int, a: int) -> int:
    return (n + a - 1) // a * a


def layout_parts(theme: Theme, layout: Theme, osos: bytes, end: int) -> tuple[int, bytes, Change, list]:
    """The Split layout for "Switch on iPod", with its View at `end`: (address, light View, table
    entry change, list of (address, light bytes, dark bytes) for the switch table)."""
    at = _align(end, 16)
    place = bytes(at)
    light = _with_copied_bytes(moved_layout(layout, place).changes[0], osos).new
    themed = bytearray(osos)
    apply_theme(theme, themed, theme.osos_sha256)
    dark = _with_copied_bytes(moved_layout(layout, place, dark=True).changes[0], bytes(themed)).new
    extra, i = [], 0
    while i < len(light):
        j = i
        while j < len(light) and light[j] != dark[j]:
            j += 1
        if j > i:
            extra.append((at + i, light[i:j], dark[i:j]))
        i = max(j, i + 1)
    return at, light, moved_layout(layout, place).changes[1], extra


def switch_table(theme: Theme, osos: bytes, extra: tuple | list = ()) -> tuple[bytes, int]:
    """The switch table for the changes inside osos, with the rules of apply_theme: a change is
    applied if the bytes are the old bytes, and left out if they are already the new bytes (the
    same change two times) or other bytes (an edit by the owner). `extra` adds runs of the layout.
    Returns (table, number of changes left out because of an edit)."""
    runs, data, skipped = [], bytearray(), 0
    work = bytearray(osos)
    for c in theme.with_old_bytes(osos).effective_changes():
        if c.offset + len(c.old) > len(osos):
            continue
        cur = bytes(work[c.offset:c.offset + len(c.old)])
        if cur != c.old:
            if cur != c.new:
                skipped += 1
            continue
        work[c.offset:c.offset + len(c.new)] = c.new
        runs.append(struct.pack("<II", c.offset, len(c.new)))
        data += bytes(a ^ b for a, b in zip(c.old, c.new))
    for at, old, new in extra:
        runs.append(struct.pack("<II", at, len(new)))
        data += bytes(a ^ b for a, b in zip(old, new))
    head = struct.pack("<III", MAGIC, len(runs), 12 + 8 * len(runs))
    return head + b"".join(runs) + bytes(data), skipped


def apply_switch_table(osos: bytearray, table: bytes) -> None:
    """What the patch does at the start (for tests)."""
    magic, n, data_at = struct.unpack_from("<III", table, 0)
    assert magic == MAGIC
    for i in range(n):
        at, length = struct.unpack_from("<II", table, 12 + 8 * i)
        for k in range(length):
            osos[at + k] ^= table[data_at + k]
        data_at += length


def settings_menu(menu: bytes) -> bytes:
    """Menu 24598 with a Dark Mode item after Clicker (a copy of the Sound Check item)."""
    count = struct.unpack_from("<I", menu, 0)[0]
    keys = [struct.unpack_from("<I", menu, 4 + 40 * i + 0x1C)[0] for i in range(count)]
    if DARK_KEY in keys:
        raise DarkModeError("The Settings menu already has the Dark Mode item.")
    if TEMPLATE_KEY not in keys or INSERT_AFTER_KEY not in keys:
        raise DarkModeError("The Settings menu is not the menu of firmware 1.3.")
    return patcher.insert_settings_item(menu, DARK_KEY, LABEL_ID, INSERT_AFTER_KEY, TEMPLATE_KEY)


def build(fw: FirmwarePartition, osos: bytes, theme: Theme, patch_dir: str | Path,
          original_sha256: str, layout: Theme | None = None) -> tuple[bytes, dict]:
    """The osos for "Switch on iPod". `osos` can have edits of the owner; `fw` gives its resources.
    With `layout`, both modes have the Split main menu."""
    if original_sha256 != theme.osos_sha256:
        raise DarkModeError(f"The theme \"{theme.name}\" is for a different firmware.")
    out = bytearray(osos)
    # 1. theme data outside osos: in both modes
    end = PATCH_AREA_END
    for c in theme.with_old_bytes(osos).effective_changes():
        if c.offset + len(c.old) > len(osos):
            if len(out) < c.offset + len(c.new):
                out += bytes(c.offset + len(c.new) - len(out))
            out[c.offset:c.offset + len(c.new)] = c.new
            end = max(end, c.offset + len(c.new))
    # The layout: in both modes. The switch table changes only its colours and text styles.
    extra = []
    if layout:
        view_at, view, entry, extra = layout_parts(theme, layout, osos, end)
        out += bytes(max(0, view_at + len(view) - len(out)))
        out[view_at:view_at + len(view)] = view
        out[entry.offset:entry.offset + len(entry.new)] = entry.new
        end = view_at + len(view)
    # 2. the switch table
    table, skipped = switch_table(theme, osos, extra)
    table_at = _align(end, 16)
    # 3. the Settings menu
    image = _Image(fw)
    if SETTINGS_MENU not in image.res:
        raise DarkModeError("The firmware has no Settings menu (Menu 24598).")
    res, block = image.res[SETTINGS_MENU], image.block_of[SETTINGS_MENU]
    menu = settings_menu(bytes(osos[block.abs(res):block.abs(res) + res.size]))
    menu_at = _align(table_at + len(table), 16)
    patch_at = _align(menu_at + len(menu), 16)
    # 4. the patch, then the table and the menu
    patched, report = patcher.apply(bytes(out), patch_dir, OSOS_LIMIT, load_address=patch_at,
                                    symbols={"dark_table": table_at}, original_sha256=original_sha256)
    out = bytearray(patched)
    if any(out[table_at:patch_at]):
        raise DarkModeError("The space for the switch table is not empty.")
    out[table_at:table_at + len(table)] = table
    out[menu_at:menu_at + len(menu)] = menu
    struct.pack_into("<II", out, res.table_pos + 4, menu_at - block.data_start, len(menu))
    info = {"table": [table_at, len(table)], "menu": [menu_at, len(menu)], "patch": report["code"],
            "changes_left_out": skipped, "end": len(out)}
    return bytes(out), info


def stock_sha256(fw: FirmwarePartition) -> str:
    return hashlib.sha256(fw.image("osos")).hexdigest()
