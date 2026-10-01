"""Build a small synthetic firmware partition with the same layout as Apple's 1.3 file."""

from __future__ import annotations

import random
import struct

import pytest

from ipodfw.partition import STOP_SIGN_PREFIX, checksum

IMAGE_BASE = 2048


def picture(tf: int, depth: int, w: int, h: int, bpr: int, pixels: bytes) -> bytes:
    assert len(pixels) == bpr * h
    return struct.pack("<4H8s3I", tf, 0, bpr, depth, bytes(8), h, w, len(pixels)) + pixels


def resource_block(sections: list[tuple[bytes, list[tuple[int, bytes, int]]]]) -> bytes:
    """sections: [(raw_type, [(id, payload, offset_in_data)])]."""
    nsec = len(sections)
    total = sum(len(items) for _, items in sections)
    tables_len = 12 + 16 * nsec + 12 * total
    out = bytearray(struct.pack("<3I", 3, tables_len, nsec))
    table_start = 12 + 16 * nsec
    tables = bytearray()
    data = bytearray()
    for raw_type, items in sections:
        out += struct.pack("<4s3I", raw_type, len(items), 0, table_start + len(tables))
        for rid, payload, off in items:
            tables += struct.pack("<hHII", rid, 0, off, len(payload))
            if len(data) < off + len(payload):
                data += bytes(off + len(payload) - len(data))
            data[off:off + len(payload)] = payload
    return bytes(out + tables + data)


def build_osos() -> bytes:
    rgb = picture(0x565, 16, 3, 2, 8, bytes(range(16)))                      # 2 bytes row padding
    argb = picture(0x1444, 16, 2, 2, 4, bytes([0x0F, 0xF0, 0x00, 0xFF, 0x34, 0x12, 0x78, 0x56]))
    grey = picture(0x4, 4, 3, 1, 2, bytes([0x0F, 0x80]))
    pics = [(100, rgb, 0), (101, argb, 48), (102, grey, 96)]
    strs = [(129, b"January\0", 200), (130, b"Feb\0", 208), (131, b"Mar\0", 216)]   # 4 bytes slack after "Feb"
    main = resource_block([(b"paMB", pics), (b" rtS", strs)])
    lang = resource_block([(b" rtS", [(129, b"Janvier\0", 0), (130, b"F\xc3\xa9v\0", 8)])])
    code = b"\xfe\xff\xff\xea" + bytes(60)
    osos = code + main
    osos += bytes(-len(osos) % 4) + lang
    return osos + bytes(-len(osos) % 512)


def build_partition() -> bytes:
    rnd = random.Random(1)
    osos = build_osos()
    rsrc = bytes(rnd.randrange(256) for _ in range(1024))
    aupd = bytes(rnd.randrange(256) for _ in range(1024))
    dev_osos = 0x4800
    dev_rsrc = dev_osos + len(osos) + 512
    dev_aupd = dev_rsrc + len(rsrc) + 512
    size = IMAGE_BASE + dev_aupd + len(aupd) + 4096
    buf = bytearray(size)
    buf[0:len(STOP_SIGN_PREFIX)] = STOP_SIGN_PREFIX
    buf[0x100:0x104] = b"]ih["
    struct.pack_into("<I", buf, 0x104, 0x4000)
    struct.pack_into("<H", buf, 0x10A, 3)
    entries = [(b"soso", dev_osos, osos, 0x10000000), (b"crsr", dev_rsrc, rsrc, 0), (b"dpua", dev_aupd, aupd, 0x10000000)]
    for n, (typ, dev, img, addr) in enumerate(entries):
        struct.pack_into("<4s4s8I", buf, 0x4200 + 40 * n, b"!ATA", typ, 0, dev, len(img), addr, 0,
                         checksum(img) if typ != b"dpua" else 0x12345678, 0xB012, 0x187C0008)
        buf[IMAGE_BASE + dev:IMAGE_BASE + dev + len(img)] = img
    return bytes(buf)


@pytest.fixture
def partition_bytes() -> bytes:
    return build_partition()
