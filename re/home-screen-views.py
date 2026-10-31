#!/usr/bin/env python3
"""Make the Split layout: an iPodFirm theme for stock firmware 1.3.

The theme changes only the main menu. It adds a new View after the end of
osos, and the table entry of View 24430 points to it. All stock Views, fonts,
pictures and code stay stock.

Usage: uv run python re/home-screen-views.py iPod_25.1.3.ipsw THEME_FILE [TEST_IPSW]
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from ipodfw.ipsw import extract_firmware, repack_ipsw  # noqa: E402
from ipodfw.partition import FirmwarePartition  # noqa: E402
from ipodfw.resources import main_block, scan  # noqa: E402
from ipodfw.themeimport import Change, Theme, _sha256, apply_theme, view_elements  # noqa: E402

TOP, LEFT, BOTTOM, RIGHT = 28, 40, 52, 64  # offsets of the edges in an element
PARENT, HEIGHT = 0x80000002, 0x80000008  # edge modes

MAIN_MENU = 24430
VIEW_AT = 0x736800  # the start of rsrc in stock: the first address after the patch area
STOCK_RANGES = ((4, 72), (80, 128))  # in View 24430, around the value of the right edge of the scroll bar
PANEL_WIDTH = 107
PANEL_X = 320 - PANEL_WIDTH

COVER_VIEW = -356  # stock, shared with Now Playing
SONG_TITLE, SONG_ARTIST, SONG_ALBUM, SONG_COUNT = 0x63bd, 0x63be, 0x63bf, 0x63c3
LINE_HEIGHT = 22
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


def text(ident: int, r: list[int], scrolls: bool = False) -> bytes:
    """A text element with its text from a firmware property. A long text scrolls if `scrolls` is set."""
    extra = [0x8c, 0x1388, 4, 0x19] if scrolls else []
    words = [0x6c if scrolls else 0x5c, 0x3180 if scrolls else 0x1580, 0x53747220, ident, 0x2b00, TEXT_PROPERTY,
             0x1000a00, *r, 0xffd06428, 0xffe89858, NOW_PLAYING_TEXT_STYLE, 0, 0xc, *extra]
    return struct.pack(f"<{len(words)}I", *words)


def main_menu_view(stock: bytes) -> bytes:
    """The stock scroll bar and list, then the cover and four lines of text."""
    x, right = PANEL_X + 6, -4
    lines = ((SONG_TITLE, 116, True), (SONG_ARTIST, 138, False), (SONG_ALBUM, 160, False), (SONG_COUNT, 188, False))
    view = bytearray(struct.pack("<I", 7) + stock[4:] + group(COVER_VIEW, rect(4, PANEL_X, -106, 0))
                     + b"".join(text(i, rect(y, x, 0, right), s) for i, y, s in lines))
    elements = view_elements(bytes(view))
    if elements is None or len(elements) != 7:
        raise SystemExit("the new View is not valid")
    edge(view, 0, RIGHT, value=-PANEL_WIDTH)
    for element in range(3, 7):
        edge(view, element, BOTTOM, mode=HEIGHT, value=LINE_HEIGHT)
    return bytes(view)


def split_theme(fw: FirmwarePartition) -> Theme:
    osos = fw.image("osos")
    block = main_block(scan(osos))
    menu = next(r for r in block.of_type("View") if r.id == MAIN_MENU)
    stock = bytes(osos[block.abs(menu):block.abs(menu) + menu.size])
    if len(stock) != 208:
        raise SystemExit("this is not stock firmware 1.3")
    new = bytearray(main_menu_view(stock))
    # The stock elements come from the firmware at the build. The list width stays in the file.
    at = block.abs(menu)
    copy = [{"at": a, "length": n, "source": at + a, "sha256": _sha256(stock[a:a + n])} for a, n in STOCK_RANGES]
    if any(bytes(new[a:a + n]) != stock[a:a + n] for a, n in STOCK_RANGES):
        raise SystemExit("the stock ranges are not correct")
    for a, n in STOCK_RANGES:
        new[a:a + n] = bytes(n)
    entry = bytes(osos[menu.table_pos + 4:menu.table_pos + 12])
    new_entry = struct.pack("<II", VIEW_AT - block.data_start, len(new))
    digest = _sha256(osos)
    label = f"View {MAIN_MENU}"
    return Theme("Split", digest, digest, [
        Change(label, VIEW_AT, b"", bytes(new), copy=copy),
        Change(label, menu.table_pos + 4, entry, new_entry, _sha256(entry)),
    ], imported=[label])


def main() -> None:
    ipsw, out = Path(sys.argv[1]), Path(sys.argv[2])
    _, data = extract_firmware(ipsw)
    fw = FirmwarePartition(data)
    theme = split_theme(fw)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(theme.to_json(stripped=True))
    print(out, out.stat().st_size, "bytes")
    if len(sys.argv) > 3:
        osos = bytearray(fw.image("osos"))
        print("applied, conflicts:", apply_theme(Theme.from_json(out.read_text()), osos, theme.osos_sha256))
        fw.make_room(len(osos))
        fw.replace_image("osos", bytes(osos))
        repack_ipsw(ipsw, fw.to_bytes(), sys.argv[3])


if __name__ == "__main__":
    main()
