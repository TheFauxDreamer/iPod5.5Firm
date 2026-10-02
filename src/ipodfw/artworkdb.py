"""Write the album artwork database of the iPod Video (ArtworkDB and .ithmb files).

RetailOS shows the artwork in Now Playing from these files. Finder writes them when it syncs.
iPodFirm writes them for the music library of the emulator.

The layout follows libgpod (db-artwork-writer.c, db-itunes-parser.h, itdb_device.c):

    ArtworkDB    mhfd → mhsd 1 → mhli → mhii (one for each track with artwork)
                                          → mhod type 2 → mhni (one for each format)
                                                            → mhod type 3 (file name)
                      mhsd 2 → mhla (no albums)
                      mhsd 3 → mhlf → mhif (one for each format)
    F1028_1.ithmb  100 × 100 RGB565 little-endian pictures
    F1029_1.ithmb  200 × 200 RGB565 little-endian pictures

A track points to its picture: mhit +0x7c artwork count, +0x80 artwork size, +0xa4 has
artwork (1), +0x160 image ID. The mhii has the image ID and the dbid of the track.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

from PIL import Image

from .albumart import rgb565

FORMATS = ((1028, 100, 100), (1029, 200, 200))   # (format ID, width, height): iPod Video cover art
FIRST_ID = 100                                    # libgpod starts the image IDs at 0x64


@dataclass
class Artwork:
    track_dbid: int
    image: Image.Image
    original_size: int      # bytes of the artwork in the music file
    image_id: int = 0       # set by build()


def ithmb_name(format_id: int) -> str:
    return f"F{format_id}_1.ithmb"


def _header(tag: bytes, length: int) -> bytearray:
    h = bytearray(length)
    h[0:4] = tag
    struct.pack_into("<I", h, 4, length)
    return h


def _total(buf: bytearray) -> bytearray:
    struct.pack_into("<I", buf, 8, len(buf))
    return buf


def _string_mhod(text: str) -> bytes:
    body = text.encode("utf-16-le")
    padding = -(0x24 + len(body)) % 4
    h = _header(b"mhod", 0x24)
    struct.pack_into("<I", h, 4, 0x18)               # iTunes puts the length of the short header here
    struct.pack_into("<H", h, 0x0C, 3)               # type 3: file name
    h[0x0F] = padding
    struct.pack_into("<I", h, 0x18, len(body))
    h[0x1C] = 2                                       # UTF-16
    return bytes(_total(h + body + bytes(padding)))


def _mhni(format_id: int, width: int, height: int, offset: int) -> bytes:
    h = _header(b"mhni", 0x4C)
    struct.pack_into("<IIII", h, 0x0C, 1, format_id, offset, width * height * 2)
    struct.pack_into("<hhHH", h, 0x1C, 0, 0, height, width)
    return bytes(_total(h + _string_mhod(":" + ithmb_name(format_id))))


def _container_mhod(child: bytes) -> bytes:
    h = _header(b"mhod", 0x18)
    struct.pack_into("<H", h, 0x0C, 2)               # type 2: location of a thumbnail
    return bytes(_total(h + child))


def build(items: list[Artwork]) -> tuple[bytes, dict[str, bytes]]:
    """Return the ArtworkDB file and the .ithmb files (name -> data). Sets image_id of each item."""
    ithmb = {f: bytearray() for f, _w, _h in FORMATS}
    mhii_list = bytearray()
    for n, a in enumerate(items):
        a.image_id = FIRST_ID + n
        mhods = bytearray()
        for f, w, h in FORMATS:
            offset = len(ithmb[f])
            ithmb[f] += rgb565(a.image, w)
            mhods += _container_mhod(_mhni(f, w, h, offset))
        mhii = _header(b"mhii", 0x98)
        struct.pack_into("<IIQ", mhii, 0x0C, len(FORMATS), a.image_id, a.track_dbid)
        struct.pack_into("<I", mhii, 0x30, a.original_size)
        mhii_list += _total(mhii + mhods)

    mhli = _header(b"mhli", 0x5C)
    struct.pack_into("<I", mhli, 8, len(items))
    mhla = _header(b"mhla", 0x5C)
    mhlf = _header(b"mhlf", 0x5C)
    struct.pack_into("<I", mhlf, 8, len(FORMATS))
    mhifs = bytearray()
    for f, w, h in FORMATS:
        mhif = _header(b"mhif", 0x7C)
        struct.pack_into("<I", mhif, 8, 0x7C)
        struct.pack_into("<II", mhif, 0x10, f, w * h * 2)
        mhifs += mhif

    def mhsd(index: int, body: bytes) -> bytes:
        h = _header(b"mhsd", 0x60)
        struct.pack_into("<H", h, 0x0C, index)
        return bytes(_total(h + body))

    sections = mhsd(1, bytes(mhli + mhii_list)) + mhsd(2, bytes(mhla)) + mhsd(3, bytes(mhlf + mhifs))
    mhfd = _header(b"mhfd", 0x84)
    struct.pack_into("<IIII", mhfd, 0x10, 2, 3, 0, FIRST_ID + len(items))   # unknown2, children, -, next ID
    mhfd[0x30] = 2
    db = _total(mhfd + sections)
    return bytes(db), {ithmb_name(f): bytes(data) for f, data in ithmb.items()}


def parse(db: bytes) -> list[dict]:
    """The images in an ArtworkDB: image ID, track dbid and the thumbnails (for tests)."""
    out = []
    p = struct.unpack_from("<I", db, 4)[0]
    while p < len(db):
        tag, hl, tl = db[p:p + 4], *struct.unpack_from("<II", db, p + 4)
        if tag == b"mhsd":
            p += hl
            continue
        if tag in (b"mhli", b"mhla", b"mhlf", b"mhif"):
            p += hl
            continue
        if tag == b"mhii":
            n, image_id, dbid = struct.unpack_from("<IIQ", db, p + 0x0C)
            thumbs = []
            q = p + hl
            for _ in range(n):
                ni = q + struct.unpack_from("<I", db, q + 4)[0]
                fmt, off, size = struct.unpack_from("<III", db, ni + 0x10)
                height, width = struct.unpack_from("<HH", db, ni + 0x20)
                s = ni + struct.unpack_from("<I", db, ni + 4)[0]
                name = db[s + 0x24:s + 0x24 + struct.unpack_from("<I", db, s + 0x18)[0]].decode("utf-16-le")
                thumbs.append({"format": fmt, "offset": off, "size": size, "width": width, "height": height, "file": name})
                q += struct.unpack_from("<I", db, q + 8)[0]
            out.append({"image_id": image_id, "dbid": dbid, "thumbs": thumbs})
            p += tl
            continue
        raise ValueError(f"unexpected chunk {tag!r} at 0x{p:x}")
    return out
