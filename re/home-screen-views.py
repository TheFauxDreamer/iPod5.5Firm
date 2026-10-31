#!/usr/bin/env python3
"""Make test firmware files for the split home screen research.

The files use stock firmware 1.3 and change only View resources. Fonts,
pictures and code stay stock. The files go to the emulator only.

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

TOP, LEFT, BOTTOM, RIGHT = 28, 40, 52, 64  # offsets of the edges in an element
PARENT, HEIGHT = 0x80000002, 0x80000008  # edge modes

MAIN_MENU = 24430
SPARE_VIEW = -515  # no stock View, resource or code refers to it
PANEL_WIDTH = 107
PANEL_X = 320 - PANEL_WIDTH

COVER_VIEW = -356  # stock, shared with Now Playing
SONG_TITLE, SONG_ARTIST = 0x63bd, 0x63be
NOW_PLAYING_TEXT_STYLE = 0x5ea30000
TEXT_PROPERTY = 0x5fbc  # the same property as the stock title


def edge(view: bytearray, element: int, offset: int, mode: int | None = None, value: int | None = None) -> None:
    at = view_elements(bytes(view))[element][0] + offset
    if mode is not None:
        struct.pack_into("<I", view, at + 4, mode)
    if value is not None:
        struct.pack_into("<i", view, at + 8, value)


def rect(top: int, left: int, bottom: int, right: int) -> list[int]:
    return [v for e in (top, left, bottom, right) for v in (0, PARENT, e & 0xffffffff)]


def group(ident: int, r: list[int]) -> bytes:
    """A 96-byte element that holds a View."""
    words = [0x5c, 0x1100, 0x4e6f6e65, ident & 0xffff, 0xffffffff, 0, 0xa00, *r, 0xffd06428, 0xffe89858, 0x3e8, 0, 1]
    return struct.pack(f"<{len(words)}I", *words)


def text(ident: int, r: list[int]) -> bytes:
    """A 96-byte text element with its text from a firmware property."""
    words = [0x5c, 0x1580, 0x53747220, ident, 0x2b00, TEXT_PROPERTY, 0x1000a00, *r,
             0xffd06428, 0xffe89858, NOW_PLAYING_TEXT_STYLE, 0, 0xc]
    return struct.pack(f"<{len(words)}I", *words)


def main_menu_view(stock: bytes) -> bytes:
    """The stock scroll bar and list, then the cover and two lines of text."""
    x, right = PANEL_X + 6, -4
    view = bytearray(struct.pack("<I", 5) + stock[4:] + b"".join((
        group(COVER_VIEW, rect(4, PANEL_X, -106, 0)),
        text(SONG_TITLE, rect(120, x, 0, right)),
        text(SONG_ARTIST, rect(144, x, 0, right)),
    )))
    if view_elements(bytes(view)) is None or len(view_elements(bytes(view))) != 5:
        raise SystemExit("the new View is not valid")
    edge(view, 0, RIGHT, value=-PANEL_WIDTH)
    edge(view, 3, BOTTOM, mode=HEIGHT, value=22)
    edge(view, 4, BOTTOM, mode=HEIGHT, value=22)
    return bytes(view)


def apply(fw: FirmwarePartition) -> int:
    """Put the new View in the space of the spare View. Change only the table entry of the main menu."""
    osos = bytearray(fw.image("osos"))
    block = main_block(scan(bytes(osos)))
    views = {r.id: r for r in block.of_type("View")}
    menu, spare = views[MAIN_MENU], views[SPARE_VIEW]
    stock = bytes(osos[block.abs(menu):block.abs(menu) + menu.size])
    if len(stock) != 208 or spare.size != 580:
        raise SystemExit("this is not stock firmware 1.3")
    new = main_menu_view(stock)
    if len(new) > spare.size:
        raise SystemExit("the new View does not fit")
    osos[block.abs(spare):block.abs(spare) + len(new)] = new
    struct.pack_into("<II", osos, menu.table_pos + 4, spare.offset, len(new))
    fw.replace_image("osos", bytes(osos))
    return len(new)


def main() -> None:
    ipsw, out = Path(sys.argv[1]), Path(sys.argv[2])
    _, data = extract_firmware(ipsw)
    fw = FirmwarePartition(data)
    print("New View bytes:", apply(fw))
    repack_ipsw(ipsw, fw.to_bytes(), out / "home-screen-split.ipsw")
    print(out / "home-screen-split.ipsw")


if __name__ == "__main__":
    main()
