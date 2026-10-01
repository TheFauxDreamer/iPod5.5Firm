"""Corrections for drives that the emulator's `ipod-boot make-disk` builds.

`make-disk` moves the osos image start in the directory 0x600 bytes forward, because the
emulator's boot loader assumes 512-byte sectors. It also makes the length 0x600 bytes
shorter, so the last 0x600 bytes of the image are not loaded. Apple's image has zeros there,
but a patched image has code there. `fix_osos_length` sets the full length again and
calculates the checksum again. A real iPod does not need this correction.
"""

from __future__ import annotations

import struct

from .partition import checksum


def _partition_start(f) -> int:
    f.seek(0)
    mbr = f.read(512)
    if mbr[510:512] != b"\x55\xaa":
        raise ValueError("the drive has no MBR")
    return struct.unpack_from("<I", mbr, 0x1BE + 8)[0] * 512


def fix_osos_length(drive_path: str, osos_length: int) -> bool:
    """Return True if the directory was changed."""
    with open(drive_path, "r+b") as f:
        start = _partition_start(f)
        f.seek(start)
        head = bytearray(f.read(0x5000))
        dir_off = struct.unpack_from("<I", head, 0x104)[0] + 0x200
        for k in range(10):
            p = dir_off + 40 * k
            if head[p + 4:p + 8] != b"soso":
                continue
            dev_offset, length = struct.unpack_from("<II", head, p + 12)
            if length >= osos_length:
                return False
            data_at = start + 0x200 + dev_offset          # the emulator boot loader uses 512-byte sectors
            f.seek(data_at)
            data = f.read(osos_length)
            struct.pack_into("<I", head, p + 16, osos_length)
            struct.pack_into("<I", head, p + 28, checksum(data))
            f.seek(start + p)
            f.write(head[p:p + 40])
            return True
    raise ValueError("no osos entry in the drive directory")
