"""Read-only FAT12/FAT16 reader for the file system in the rsrc image.

The rsrc image of the iPod Video has a FAT16 file system at offset 0x600
(the `entryOffset` of the rsrc directory entry).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass


@dataclass
class Entry:
    path: str
    size: int
    cluster: int
    is_dir: bool


class Fat16:
    def __init__(self, data: bytes):
        self.d = data
        bps, spc, reserved, nfats, root_entries, total16, _media, spf = struct.unpack_from("<HBHBHHBH", data, 11)
        if data[0x36:0x3B] not in (b"FAT16", b"FAT12"):
            raise ValueError("no FAT12/FAT16 boot sector")
        self.fat12 = data[0x36:0x3B] == b"FAT12"
        self.bps, self.spc = bps, spc
        self.fat_off = reserved * bps
        self.root_off = self.fat_off + nfats * spf * bps
        self.root_entries = root_entries
        self.data_off = self.root_off + root_entries * 32
        self.cluster_size = bps * spc

    def _next(self, c: int) -> int:
        if self.fat12:
            v = struct.unpack_from("<H", self.d, self.fat_off + c * 3 // 2)[0]
            return v >> 4 if c & 1 else v & 0xFFF
        return struct.unpack_from("<H", self.d, self.fat_off + c * 2)[0]

    def _chain(self, c: int) -> list[int]:
        end = 0xFF8 if self.fat12 else 0xFFF8
        out = []
        while 2 <= c < end and len(out) < 1 << 20:
            out.append(c)
            c = self._next(c)
        return out

    def _read_clusters(self, first: int) -> bytes:
        return b"".join(self.d[self.data_off + (c - 2) * self.cluster_size:
                               self.data_off + (c - 1) * self.cluster_size] for c in self._chain(first))

    def _entries(self, raw: bytes, parent: str) -> list[Entry]:
        out, lfn = [], []
        for i in range(0, len(raw) - 31, 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5:
                lfn = []
                continue
            if e[11] == 0x0F:                       # long file name part
                part = e[1:11] + e[14:26] + e[28:32]
                lfn.insert(0, part.decode("utf-16-le", "ignore").split("\x00")[0].replace("￿", ""))
                continue
            if e[11] & 0x08:                        # volume label
                lfn = []
                continue
            short = e[0:8].decode("latin1").rstrip() + ("." + e[8:11].decode("latin1").rstrip() if e[8:11].strip() else "")
            name = "".join(lfn) or short
            lfn = []
            if name in (".", ".."):
                continue
            cluster = struct.unpack_from("<H", e, 26)[0]
            size = struct.unpack_from("<I", e, 28)[0]
            out.append(Entry(f"{parent}/{name}", size, cluster, bool(e[11] & 0x10)))
        return out

    def walk(self) -> list[Entry]:
        todo = self._entries(self.d[self.root_off:self.data_off], "")
        out = []
        while todo:
            e = todo.pop(0)
            out.append(e)
            if e.is_dir:
                todo += self._entries(self._read_clusters(e.cluster), e.path)
        return out

    def read(self, e: Entry) -> bytes:
        return self._read_clusters(e.cluster)[:e.size]
