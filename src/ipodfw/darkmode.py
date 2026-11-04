"""Build the firmware with switches on the iPod. With the appearance "Switch on iPod", it is light
at the start and has a Dark Mode item in Settings. With the layout "Switch on iPod", it has the
Split main menu and a Split View item in Settings.

RetailOS makes its screens one time, at the start, from the View resources. Thus the dark theme
cannot change while the iPod runs. The patch patches/dark-mode applies a switch table at the
start, before the first View is read, if the file iPod_Control/iTunes/iPodFirmDarkMode contains
'1'. The Settings item writes that file and restarts the iPod.

The build puts these items after the end of osos (below OSOS_LIMIT):
    the theme data that is outside osos (for example the background picture: in both modes)
    the Split View, if the layout is Split
    the dark switch table: "IFD2" (darktable.py: colour maps and palettes of the light pictures), or
                      "IFDM" if that is smaller: u32 count N, u32 data offset, N x {u32 address,
                      u32 length}, data (old XOR new for each change)
    the layout switch table, in the same format (one run: the table entry of View 24430)
    the Settings menu with the items (the resource table entry points to it)
    the code of the patch (its symbols dark_table and layout_table are the addresses of the tables)
A switch that is off has a table with no changes.
"""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path

from . import darktable, patcher
from .themeimport import OSOS_LIMIT, Change, Theme, _Image, _with_copied_bytes, apply_theme, moved_layout
from .partition import FirmwarePartition

MAGIC = 0x4D444649                  # "IFDM"
SETTINGS_MENU = ("main", "Menu", 24598)
TEMPLATE_KEY = 0x600060B7           # the Sound Check item: an On/Off item
INSERT_AFTER_KEY = 0x60006088       # the Clicker item
DARK_KEY = 0x600060E0               # the key of the Dark Mode item (patch: KEY)
LABEL_ID = 0x7E00                   # the label "Dark Mode" (patch: DARK_LABEL)
LAYOUT_KEY = 0x60007E15             # the key of the Split View item (patch: LAYOUT_KEY)
LAYOUT_LABEL_ID = 0x7E14            # the label "Split View" (patch: LAYOUT_LABEL)
PATCH_AREA_END = 0x736800           # the other patches use the area before this address
SETTING_FILE = "iPod_Control/iTunes/iPodFirmDarkMode"
LAYOUT_SETTING_FILE = "iPod_Control/iTunes/iPodFirmLayout"   # '0' stock, '1' Split; no file: Split
EMPTY_TABLE = struct.pack("<III", MAGIC, 0, 12)          # a switch that is off


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


def smaller_table(light: bytes, ifdm: bytes, image: _Image) -> bytes:
    """The IFD2 table for `light` (the image before the patch), or `ifdm` if IFD2 is not smaller."""
    dark = bytearray(light)
    apply_switch_table(dark, ifdm)
    pictures = darktable.picture_ranges(light, [image.pos(k) for k in image.res if k[1] == "BMap"])
    table = darktable.encode(light, bytes(dark), pictures)
    return table if len(table) < len(ifdm) else ifdm


def apply_dark_table(osos: bytearray, table: bytes) -> None:
    """What the patch does with the dark table at a dark start: IFD2 or IFDM (for tests)."""
    if struct.unpack_from("<I", table, 0)[0] == darktable.MAGIC:
        darktable.apply_table2(osos, table)
    else:
        apply_switch_table(osos, table)


def apply_switch_table(osos: bytearray, table: bytes) -> None:
    """What the patch does at the start (for tests)."""
    magic, n, data_at = struct.unpack_from("<III", table, 0)
    assert magic == MAGIC
    for i in range(n):
        at, length = struct.unpack_from("<II", table, 12 + 8 * i)
        for k in range(length):
            osos[at + k] ^= table[data_at + k]
        data_at += length


def settings_menu(menu: bytes, dark: bool = True, layout: bool = False) -> bytes:
    """Menu 24598 with a Dark Mode item after Clicker (a copy of the Sound Check item) if `dark`, and a
    Split View item after it if `layout`."""
    count = struct.unpack_from("<I", menu, 0)[0]
    keys = [struct.unpack_from("<I", menu, 4 + 40 * i + 0x1C)[0] for i in range(count)]
    if DARK_KEY in keys or LAYOUT_KEY in keys:
        raise DarkModeError("The Settings menu already has the Dark Mode item or the Split View item.")
    if TEMPLATE_KEY not in keys or INSERT_AFTER_KEY not in keys:
        raise DarkModeError("The Settings menu is not the menu of firmware 1.3.")
    if dark:
        menu = patcher.insert_settings_item(menu, DARK_KEY, LABEL_ID, INSERT_AFTER_KEY, TEMPLATE_KEY)
    if layout:
        menu = patcher.insert_settings_item(menu, LAYOUT_KEY, LAYOUT_LABEL_ID,
                                            DARK_KEY if dark else INSERT_AFTER_KEY, TEMPLATE_KEY)
    return menu


def layout_table(entry_at: int, stock: bytes, split: bytes, extra=()) -> bytes:
    """The runs, in address order: the 8 bytes (offset and size) of the table entry of View 24430,
    stock XOR Split, and one run for each (address, stock bytes, Split bytes) of `extra`."""
    runs = sorted([(entry_at, bytes(stock), bytes(split)), *((a, bytes(s), bytes(p)) for a, s, p in extra)])
    head = 12 + 8 * len(runs)
    out = struct.pack("<III", MAGIC, len(runs), head) + b"".join(struct.pack("<II", a, len(s)) for a, s, _ in runs)
    return out + b"".join(bytes(x ^ y for x, y in zip(s, p)) for _, s, p in runs)


def split_only_bytes(specs) -> list[tuple[int, bytes, bytes]]:
    """The "bytes" of each patch spec with "split_only": (address, "expect", "value"). With Split View
    Off, the layout table changes them back to "expect"."""
    return [(int(e["at"], 16), bytes.fromhex(e["expect"]), bytes.fromhex(e["value"]))
            for spec in specs if spec.get("split_only") for e in spec.get("bytes", [])]


def build(fw: FirmwarePartition, osos: bytes, theme: Theme | None, patch_dir: str | Path,
          original_sha256: str, layout: Theme | None = None, dark_switch: bool = True,
          layout_switch: bool = False, layout_bytes=()) -> tuple[bytes, dict]:
    """The osos with the switches. `osos` can have edits of the owner; `fw` gives its resources.
    `dark_switch`: light at the start, with a Dark Mode item (needs `theme`). `theme` without
    `dark_switch`: always dark. No `theme`: always light. With `layout`, the main menu is Split.
    With `layout_switch` also, a Split View item changes it back to stock, and the layout table
    also changes `layout_bytes` (refer to split_only_bytes) back to stock."""
    if theme is not None and original_sha256 != theme.osos_sha256:
        raise DarkModeError(f"The theme \"{theme.name}\" is for a different firmware.")
    if dark_switch and theme is None:
        raise DarkModeError("Dark Mode on the iPod needs a dark theme.")
    out = bytearray(osos)
    end = PATCH_AREA_END
    extra = []
    if dark_switch:
        # 1. theme data outside osos: in both modes
        for c in theme.with_old_bytes(osos).effective_changes():
            if c.offset + len(c.old) > len(osos):
                if len(out) < c.offset + len(c.new):
                    out += bytes(c.offset + len(c.new) - len(out))
                out[c.offset:c.offset + len(c.new)] = c.new
                end = max(end, c.offset + len(c.new))
    elif theme is not None:
        apply_theme(theme, out, original_sha256)
        end = max(end, len(out))
    # The layout: in both modes. The dark table changes only its colours and text styles.
    ltable = EMPTY_TABLE
    if layout:
        if dark_switch:
            view_at, view, entry, extra = layout_parts(theme, layout, osos, end)
        else:
            moved = moved_layout(layout, bytes(end), theme is not None)
            view_at, view, entry = moved.changes[0].offset, _with_copied_bytes(moved.changes[0], bytes(out)).new, moved.changes[1]
        out += bytes(max(0, view_at + len(view) - len(out)))
        out[view_at:view_at + len(view)] = view
        stock_entry = bytes(out[entry.offset:entry.offset + len(entry.new)])
        out[entry.offset:entry.offset + len(entry.new)] = entry.new
        end = view_at + len(view)
        if layout_switch:
            ltable = layout_table(entry.offset, stock_entry, entry.new, layout_bytes)
    # 2. the switch tables. The IFD2 table comes from the light image in RAM at the start.
    image = _Image(fw)
    dtable, skipped = switch_table(theme, osos, extra) if dark_switch else (EMPTY_TABLE, 0)
    ifdm = dtable
    if dark_switch:
        dtable = smaller_table(bytes(out), ifdm, image)
    dark_at = _align(end, 16)
    layout_at = _align(dark_at + len(dtable), 16)
    # 3. the Settings menu
    if SETTINGS_MENU not in image.res:
        raise DarkModeError("The firmware has no Settings menu (Menu 24598).")
    res, block = image.res[SETTINGS_MENU], image.block_of[SETTINGS_MENU]
    menu = settings_menu(bytes(osos[block.abs(res):block.abs(res) + res.size]), dark_switch,
                         layout_switch and layout is not None)
    menu_at = _align(layout_at + len(ltable), 16)
    patch_at = _align(menu_at + len(menu), 16)
    # 4. the patch, then the tables and the menu
    patched, report = patcher.apply(bytes(out), patch_dir, OSOS_LIMIT, load_address=patch_at,
                                    symbols={"dark_table": dark_at, "layout_table": layout_at},
                                    original_sha256=original_sha256)
    out = bytearray(patched)
    if any(out[dark_at:patch_at]):
        raise DarkModeError("The space for the switch table is not empty.")
    out[dark_at:dark_at + len(dtable)] = dtable
    out[layout_at:layout_at + len(ltable)] = ltable
    out[menu_at:menu_at + len(menu)] = menu
    struct.pack_into("<II", out, res.table_pos + 4, menu_at - block.data_start, len(menu))
    darktable.check_table(bytes(out), ifdm, dtable)
    # "ifdm": the XOR table. A later step (other patches) must check its result with darktable.check_table.
    info = {"table": [dark_at, len(dtable)], "format": "IFD2" if dtable is not ifdm else "IFDM", "ifdm": ifdm,
            "layout_table": [layout_at, len(ltable)], "menu": [menu_at, len(menu)],
            "patch": report["code"], "changes_left_out": skipped, "end": len(out)}
    return bytes(out), info


def stock_sha256(fw: FirmwarePartition) -> str:
    return hashlib.sha256(fw.image("osos")).hexdigest()
