#!/usr/bin/env python3
"""Change folder-icon.png into the C array `folder_px` of patches/album-art/album_art.c.

The iPod does not read a PNG. Run this script after a change to the PNG, and put the output into
album_art.c. A pixel with an alpha of 128 or more is solid. Each other pixel is transparent.

  python3 re/playlist-folders/make-folder-icon.py [preview.png]

The optional preview shows the icon at 8 x on the three row backgrounds. Refer to
re/playlist-folders.md, "Folder icon".
"""
import sys
from pathlib import Path

from PIL import Image

SIZE = 20                       # TH in album_art.c
KEY = 0xf81f                    # FOLDER_KEY in album_art.c
BACKGROUNDS = [(255, 255, 255), (0, 0, 0), (0x1a, 0x6f, 0xe0)]   # light, dark, highlighted row


def rgb565(r: int, g: int, b: int) -> int:
    return (r >> 3) << 11 | (g >> 2) << 5 | b >> 3


def main() -> int:
    img = Image.open(Path(__file__).resolve().parent / "folder-icon.png").convert("RGBA")
    if img.size != (SIZE, SIZE):
        print(f"The PNG must be {SIZE} x {SIZE} pixels. This PNG is {img.width} x {img.height}.", file=sys.stderr)
        return 1
    px = [rgb565(*p[:3]) if p[3] >= 128 else KEY for p in img.getdata()]
    if sum(p == KEY and img.getpixel((i % SIZE, i // SIZE))[3] >= 128 for i, p in enumerate(px)):
        print("A solid pixel has the transparent colour. Change the colour of the pixel.", file=sys.stderr)
        return 1
    print("static const unsigned short folder_px[TH * TH] __attribute__((aligned(4))) = {")
    for y in range(SIZE):
        print("    " + ", ".join(f"0x{v:04x}" for v in px[y * SIZE:(y + 1) * SIZE]) + ",")
    print("};")
    if len(sys.argv) > 1:
        scale = 8
        sheet = Image.new("RGB", (len(BACKGROUNDS) * 32 * scale, 32 * scale))
        for i, colour in enumerate(BACKGROUNDS):
            tile = Image.new("RGB", (32, 32), colour)
            mask = Image.new("L", (SIZE, SIZE))
            mask.putdata([0 if p == KEY else 255 for p in px])
            tile.paste(img.convert("RGB"), (6, 6), mask)
            sheet.paste(tile.resize((32 * scale, 32 * scale), Image.NEAREST), (i * 32 * scale, 0))
        sheet.save(sys.argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main())
