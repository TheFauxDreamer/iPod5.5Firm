"""Read the iTunes tags and the cover art of an MP4/M4A file (read only).

Reads the atoms moov/mvhd (duration) and moov/udta/meta/ilst (tags). No other library is needed.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field


@dataclass
class Tags:
    title: str = ""
    artist: str = ""
    album_artist: str = ""
    album: str = ""
    genre: str = ""
    year: int = 0
    track: int = 0
    tracks: int = 0
    disc: int = 0
    length_ms: int = 0
    cover: bytes | None = field(default=None, repr=False)


CONTAINERS = {b"moov", b"udta", b"trak", b"mdia", b"minf", b"stbl"}


def _atoms(f, start: int, end: int):
    pos = start
    while pos + 8 <= end:
        f.seek(pos)
        head = f.read(8)
        if len(head) < 8:
            return
        size, kind = struct.unpack(">I4s", head)
        hlen = 8
        if size == 1:
            size = struct.unpack(">Q", f.read(8))[0]
            hlen = 16
        elif size == 0:
            size = end - pos
        if size < hlen:
            return
        yield kind, pos + hlen, pos + size
        pos += size


def _find(f, start: int, end: int, path: list[bytes]):
    for kind, body, stop in _atoms(f, start, end):
        if kind == path[0]:
            if len(path) == 1:
                return body, stop
            inner = body + 4 if kind == b"meta" else body      # "meta" has a version/flags word
            r = _find(f, inner, stop, path[1:])
            if r:
                return r
    return None


def read(path: str) -> Tags:
    t = Tags()
    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        mvhd = _find(f, 0, size, [b"moov", b"mvhd"])
        if mvhd:
            f.seek(mvhd[0])
            v = f.read(1)[0]
            f.seek(mvhd[0] + (12 if v == 0 else 20))           # after version, flags and the two dates
            scale, dur = struct.unpack(">II", f.read(8)) if v == 0 else struct.unpack(">IQ", f.read(12))
            if scale:
                t.length_ms = int(dur * 1000 / scale)
        ilst = _find(f, 0, size, [b"moov", b"udta", b"meta", b"ilst"])
        if not ilst:
            return t
        for kind, body, stop in _atoms(f, *ilst):
            data = _find(f, body, stop, [b"data"])
            if not data:
                continue
            f.seek(data[0] + 8)                                    # skip type and locale
            value = f.read(data[1] - data[0] - 8)
            text = lambda: value.decode("utf-8", "replace")
            if kind == b"\xa9nam":
                t.title = text()
            elif kind == b"\xa9ART":
                t.artist = text()
            elif kind == b"aART":
                t.album_artist = text()
            elif kind == b"\xa9alb":
                t.album = text()
            elif kind == b"\xa9gen":
                t.genre = text()
            elif kind == b"\xa9day":
                t.year = int(text()[:4]) if text()[:4].isdigit() else 0
            elif kind == b"trkn" and len(value) >= 6:
                t.track, t.tracks = struct.unpack(">HH", value[2:6])
            elif kind == b"disk" and len(value) >= 4:
                t.disc = struct.unpack(">H", value[2:4])[0]
            elif kind == b"covr" and t.cover is None:
                t.cover = value
    return t
