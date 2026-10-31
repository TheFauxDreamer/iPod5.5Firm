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
WIDTH_FROM_RIGHT = 0x80000014
SCROLL_BAR_WIDTH = 11

PANEL_WIDTH = 107
PANEL_X = 320 - PANEL_WIDTH
TITLE_HEIGHT = 24
SCREEN_HEIGHT = 240

SONG_COUNT, SONG_TITLE, SONG_ARTIST, SONG_ALBUM = 0x63c3, 0x63bd, 0x63be, 0x63bf
NOW_PLAYING_TEXT_STYLE = 0x5ea30000
TITLE_ELEMENT_PROPERTY = 0x5fbc  # the same property as the stock title
PANEL_VIEW = -515


def edge(view: bytearray, element: int, offset: int, mode: int | None = None, value: int | None = None,
         reference: int | None = None) -> None:
    at = view_elements(bytes(view))[element][0] + offset
    if reference is not None:
        struct.pack_into("<I", view, at, reference)
    if mode is not None:
        struct.pack_into("<I", view, at + 4, mode)
    if value is not None:
        struct.pack_into("<i", view, at + 8, value)


def rect(top: int, left: int, bottom: int, right: int) -> list[int]:
    return [v for e in (top, left, bottom, right) for v in (0, PARENT, e & 0xffffffff)]


def group(ident: int, r: list[int], tail: tuple = (0, 0, 0)) -> bytes:
    """A 96-byte element that holds a View."""
    words = [0x5c, 0x1100, 0x4e6f6e65, ident & 0xffff, 0xffffffff, 0, 0xa00, *r, 0xffd06428, 0xffe89858, *tail]
    return struct.pack(f"<{len(words)}I", *words)


def text(ident: int, r: list[int]) -> bytes:
    """A text element with its text from a firmware property."""
    words = [0x5c, 0x1580, 0x53747220, ident, 0x2b00, TITLE_ELEMENT_PROPERTY,
             0x1000a00, *r, 0xffd06428, 0xffe89858, NOW_PLAYING_TEXT_STYLE, 0, 0xc]
    return struct.pack(f"<{len(words)}I", *words)


def split_views(views: dict[int, bytes]) -> dict[int, bytes]:
    new = {k: bytearray(v) for k, v in views.items()}
    lists = 0
    for ident, view in new.items():
        for index, (p, _, _, _) in enumerate(view_elements(bytes(view)) or []):
            w = struct.unpack_from("<20I", view, p) if p + 80 <= len(view) else ()
            if w and w[11] == WIDTH_FROM_RIGHT and w[12] == SCROLL_BAR_WIDTH and w[17] == PARENT and w[18] == 0:
                edge(view, index, RIGHT, value=-PANEL_WIDTH)
                lists += 1
    if lists != 85:
        raise SystemExit(f"found {lists} lists, not 85: this is not stock firmware 1.3")

    # The title layer covers the screen. The title strip stays stock.
    edge(new[24069], 0, BOTTOM, value=SCREEN_HEIGHT)

    # The content starts below the title, and does not follow the taller layer.
    content = next(i for i, e in enumerate(view_elements(bytes(new[-277]))) if e[3] == 24085)
    edge(new[-277], content, TOP, mode=PARENT, value=TITLE_HEIGHT, reference=0)

    # View -515 has no parent in stock. It holds the title and the panel.
    # Views -285, -356 and 25532 stay stock, because other screens use them.
    struct.pack_into("<H", new[24506], view_elements(bytes(new[24506]))[1][0] + 12, PANEL_VIEW & 0xffff)
    edge(new[24506], 1, LEFT, value=0)
    edge(new[24506], 1, RIGHT, value=0)
    x, right = PANEL_X + 6, -4
    new[PANEL_VIEW] = bytearray(struct.pack("<I", 6) + b"".join((
        group(-285, rect(0, 40, 0, -40)),
        group(-356, rect(TITLE_HEIGHT, PANEL_X, -96, 0), tail=(0x3e8, 0, 1)),
        text(SONG_TITLE, rect(146, x, 0, right)),
        text(SONG_ARTIST, rect(164, x, 0, right)),
        text(SONG_ALBUM, rect(182, x, 0, right)),
        text(SONG_COUNT, rect(208, x, 0, right)),
    )))
    edge(new[PANEL_VIEW], 0, BOTTOM, mode=HEIGHT, value=TITLE_HEIGHT)
    return {k: bytes(v) for k, v in new.items() if bytes(v) != views[k]}


def apply(fw: FirmwarePartition) -> int:
    osos = bytearray(fw.image("osos"))
    block = main_block(scan(bytes(osos)))
    resources = {r.id: r for r in block.of_type("View")}
    views = {i: bytes(osos[block.abs(r):block.abs(r) + r.size]) for i, r in resources.items()}
    changed = split_views(views)
    for ident, data in changed.items():
        r = resources[ident]
        if len(data) != r.size:
            raise SystemExit(f"View {ident} changed its size")
        osos[block.abs(r):block.abs(r) + r.size] = data
    fw.replace_image("osos", bytes(osos))
    return len(changed)


def main() -> None:
    ipsw, out = Path(sys.argv[1]), Path(sys.argv[2])
    _, data = extract_firmware(ipsw)
    fw = FirmwarePartition(data)
    print("Views changed:", apply(fw))
    repack_ipsw(ipsw, fw.to_bytes(), out / "home-screen-split.ipsw")
    print(out / "home-screen-split.ipsw")


if __name__ == "__main__":
    main()
