"""Write the album thumbnail file for the album-art patch.

File: iPod_Control/iTunes/iPodFirmAlbumArt (format in patches/album-art/album_art.c).
"""

from __future__ import annotations

import struct

from PIL import Image

MAGIC = b"IFAT"
VERSION = 1
DEFAULT_SIZE = 20


def fnv1a(text: str) -> int:
    h = 2166136261
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 16777619) & 0xFFFFFFFF
    return h


def rgb565(img: Image.Image, size: int) -> bytes:
    """Scale an image to a square of `size` pixels and return RGB565 little-endian pixels."""
    img = img.convert("RGB")
    w, h = img.size
    side = min(w, h)                                   # crop to a square at the centre
    img = img.crop(((w - side) // 2, (h - side) // 2, (w - side) // 2 + side, (h - side) // 2 + side))
    img = img.resize((size, size), Image.LANCZOS)
    out = bytearray()
    for r, g, b in img.getdata():
        out += struct.pack("<H", (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3))
    return bytes(out)


def build(albums: dict[str, Image.Image], size: int = DEFAULT_SIZE) -> bytes:
    """`albums` maps the album name (as the iPod shows it) to its artwork."""
    entries = {}
    for name, img in albums.items():
        h = fnv1a(name)
        if h not in entries:                           # the first album wins if two names have the same hash
            entries[h] = rgb565(img, size)
    hashes = sorted(entries)
    data_start = 16 + 8 * len(hashes)
    out = bytearray(MAGIC + struct.pack("<HHII", VERSION, size, len(hashes), 0))
    for i, h in enumerate(hashes):
        out += struct.pack("<II", h, data_start + i * size * size * 2)
    for h in hashes:
        out += entries[h]
    return bytes(out)


def parse(blob: bytes) -> dict[int, bytes]:
    if blob[:4] != MAGIC:
        raise ValueError("not an iPodFirm album art file")
    version, size, count, _ = struct.unpack_from("<HHII", blob, 4)
    out = {}
    for i in range(count):
        h, off = struct.unpack_from("<II", blob, 16 + 8 * i)
        out[h] = blob[off:off + size * size * 2]
    return out
