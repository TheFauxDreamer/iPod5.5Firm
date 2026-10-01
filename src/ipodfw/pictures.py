"""Decode/encode the BMap picture resources to and from PIL images.

Ported from iPodWizard Picture.cpp (header "type 2", used on the Video):

    u16 texture_format, u16 d5, u16 bytes_per_row, u16 bit_depth,
    8 zero bytes, u32 height, u32 width, u32 block_len, then pixel rows.

Formats seen in the 1.3 firmware:
    0x0565  16 bpp RGB565, little-endian            -> PNG RGB
    0x2565  16 bpp RGB565, big-endian               -> PNG RGB
    0x1444  16 bpp ARGB4444, little-endian          -> PNG RGBA
    0x0004 / 0x0002 / bpp 1   4/2/1-bit grey, 0 = white, MSB pixel first -> PNG L

Encoding writes only pixel bits, so row padding is preserved and an
unchanged PNG re-encodes to byte-identical data.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

from PIL import Image

HEADER_FMT = "<4H8s3I"
HEADER_SIZE = struct.calcsize(HEADER_FMT)  # 28


class PictureError(Exception):
    pass


@dataclass
class Picture:
    pos: int            # absolute position of the header in osos
    texture_format: int
    bytes_per_row: int
    depth: int
    width: int
    height: int
    block_len: int

    @property
    def data_pos(self) -> int:
        return self.pos + HEADER_SIZE

    @property
    def mode(self) -> str:
        if self.depth == 16:
            return "RGBA" if self.texture_format == 0x1444 else "RGB"
        return "L"

    @property
    def format_name(self) -> str:
        if self.depth == 16:
            return {0x1444: "ARGB4444", 0x2565: "RGB565-BE"}.get(self.texture_format, "RGB565")
        return f"grey{self.depth}"


def parse(osos: bytes, pos: int) -> Picture | None:
    if pos + HEADER_SIZE > len(osos):
        return None
    tf, _d5, bpr, depth, zeros, h, w, block_len = struct.unpack_from(HEADER_FMT, osos, pos)
    if (tf == 0 or zeros != bytes(8) or not 0 < w <= 1024 or not 0 < h <= 1024
            or depth not in (1, 2, 4, 16) or bpr * 8 < w * depth or block_len < bpr * h
            or pos + HEADER_SIZE + block_len > len(osos)):
        return None
    return Picture(pos, tf, bpr, depth, w, h, block_len)


def decode(osos: bytes, pic: Picture) -> Image.Image:
    img = Image.new(pic.mode, (pic.width, pic.height))
    px = img.load()
    for y in range(pic.height):
        row = pic.data_pos + y * pic.bytes_per_row
        for x in range(pic.width):
            px[x, y] = _get(osos, row, x, pic)
    return img


def encode(osos: bytearray, pic: Picture, img: Image.Image) -> bool:
    """Write img into the picture's pixel data. Returns True if bytes changed."""
    if img.size != (pic.width, pic.height):
        raise PictureError(f"image is {img.size[0]}x{img.size[1]}, firmware picture is {pic.width}x{pic.height}")
    img = img.convert(pic.mode)
    px = img.load()
    start, end = pic.data_pos, pic.data_pos + pic.bytes_per_row * pic.height
    before = bytes(osos[start:end])
    for y in range(pic.height):
        row = pic.data_pos + y * pic.bytes_per_row
        for x in range(pic.width):
            _set(osos, row, x, pic, px[x, y])
    return bytes(osos[start:end]) != before


def _get(buf, row, x, pic):
    d = pic.depth
    if d == 16:
        v = struct.unpack_from(">H" if pic.texture_format == 0x2565 else "<H", buf, row + 2 * x)[0]
        if pic.texture_format == 0x1444:
            a, r, g, b = (v >> 12) & 15, (v >> 8) & 15, (v >> 4) & 15, v & 15
            return (r * 17, g * 17, b * 17, a * 17)
        r, g, b = (v >> 11) & 31, (v >> 5) & 63, v & 31
        return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))
    per_byte = 8 // d
    shift = (per_byte - 1 - x % per_byte) * d
    level = (buf[row + x // per_byte] >> shift) & ((1 << d) - 1)
    maxv = (1 << d) - 1
    return (maxv - level) * 255 // maxv


def _set(buf, row, x, pic, value):
    d = pic.depth
    if d == 16:
        if pic.texture_format == 0x1444:
            r, g, b, a = value
            v = ((a >> 4) << 12) | ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
        else:
            r, g, b = value
            v = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
        struct.pack_into(">H" if pic.texture_format == 0x2565 else "<H", buf, row + 2 * x, v)
        return
    per_byte = 8 // d
    shift = (per_byte - 1 - x % per_byte) * d
    maxv = (1 << d) - 1
    level = maxv - (value * maxv + 127) // 255
    i = row + x // per_byte
    buf[i] = (buf[i] & ~(maxv << shift) & 0xFF) | (level << shift)
