"""Locate and edit the resource blocks embedded in the osos image.

Format ported from iPodWizard (firmware.h / firmware.cpp, GPLv2) and
verified against Apple's 1.3 Video firmware:

    block header  u32 3, u32 tables_len, u32 num_sections
    section[n]    type[4] (byte-reversed, e.g. "paMB" = BMap), u32 num_items,
                  u32 t1, u32 table_start (relative to block header)
    resource[]    i16 id, u16 unk, u32 offset (relative to block data), u32 size
    data          starts at header + tables_len

The 1.3 osos has one main block (BMap, Str, View, Menu, Type, TCmd, ...) and
one string-only block per language.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field

HEADER_FMT = "<3I"
SECTION_FMT = "<4s3I"
RESOURCE_FMT = "<hHII"
HEADER_SIZE, SECTION_SIZE, RESOURCE_SIZE = 12, 16, 12

KNOWN_TYPES = (b" rtS", b"paMB", b"uneM", b"epyT", b"weiV", b"dmCT", b"enoN", b"mTDL", b"stiB")


class ResourceError(Exception):
    pass


def type_name(raw: bytes) -> str:
    return raw[::-1].decode("latin1")


@dataclass
class Resource:
    type: str        # readable, e.g. "BMap", "Str "
    id: int
    unk: int
    offset: int      # relative to block data start
    size: int
    table_pos: int   # absolute position of this 12-byte entry in osos


@dataclass
class ResourceBlock:
    index: int
    start: int
    tables_len: int
    sections: list[tuple[str, int, int, int]]
    resources: list[Resource] = field(default_factory=list)

    @property
    def data_start(self) -> int:
        return self.start + self.tables_len

    def of_type(self, t: str) -> list[Resource]:
        return [r for r in self.resources if r.type == t]

    def abs(self, r: Resource) -> int:
        return self.data_start + r.offset


def _try_block(osos: bytes, i: int) -> ResourceBlock | None:
    z1, tables_len, nsec = struct.unpack_from(HEADER_FMT, osos, i)
    if z1 != 3 or not 0 < tables_len < 0xFFFF or not 0 < nsec < 50:
        return None
    if i + HEADER_SIZE + nsec * SECTION_SIZE > len(osos):
        return None
    sections = [struct.unpack_from(SECTION_FMT, osos, i + HEADER_SIZE + k * SECTION_SIZE) for k in range(nsec)]
    if any(s[0] not in KNOWN_TYPES for s in sections):
        return None
    total = sum(s[1] for s in sections)
    if HEADER_SIZE + nsec * SECTION_SIZE + total * RESOURCE_SIZE != tables_len:
        return None
    block = ResourceBlock(0, i, tables_len, [(type_name(s[0]), s[1], s[2], s[3]) for s in sections])
    for raw_type, num, _t1, table_start in sections:
        for x in range(num):
            pos = i + table_start + x * RESOURCE_SIZE
            rid, unk, off, size = struct.unpack_from(RESOURCE_FMT, osos, pos)
            block.resources.append(Resource(type_name(raw_type), rid, unk, off, size, pos))
    if any(block.data_start + r.offset + r.size > len(osos) for r in block.resources):
        return None
    return block


def scan(osos: bytes) -> list[ResourceBlock]:
    """Find every resource block in an osos image."""
    candidates = set()
    for tag in KNOWN_TYPES:
        pos = osos.find(tag)
        while pos != -1:
            i = pos - HEADER_SIZE
            if i >= 0 and i % 4 == 0:
                candidates.add(i)
            pos = osos.find(tag, pos + 1)
    blocks: list[ResourceBlock] = []
    next_free = 0
    for i in sorted(candidates):
        if i < next_free:
            continue
        b = _try_block(osos, i)
        if b:
            b.index = len(blocks)
            blocks.append(b)
            next_free = b.data_start
    return blocks


def main_block(blocks: list[ResourceBlock]) -> ResourceBlock:
    for b in blocks:
        if b.of_type("BMap"):
            return b
    raise ResourceError("no picture (BMap) resource block found")


# -- strings ---------------------------------------------------------------

def string_key(block: ResourceBlock) -> list[tuple[str, Resource]]:
    """Stable JSON keys for a block's strings: the id, or id#n for repeats."""
    seen: dict[int, int] = {}
    out = []
    for r in block.of_type("Str "):
        n = seen.get(r.id, 0)
        seen[r.id] = n + 1
        out.append((str(r.id) if n == 0 else f"{r.id}#{n}", r))
    return out


def read_strings(osos: bytes, block: ResourceBlock) -> dict[str, str]:
    out = {}
    for key, r in string_key(block):
        raw = osos[block.abs(r):block.abs(r) + r.size]
        out[key] = raw.rstrip(b"\0").decode("utf-8", errors="surrogateescape")
    return out


def write_strings(osos: bytearray, block: ResourceBlock, new: dict[str, str]) -> bool:
    """Re-pack a block's strings inside the span they already occupy.

    Like iPodWizard, the total can grow only into the alignment padding that
    already exists between strings; otherwise ResourceError is raised.
    Returns True if anything changed.
    """
    keyed = string_key(block)
    current = read_strings(osos, block)
    unknown = set(new) - set(current)
    if unknown:
        raise ResourceError(f"unknown string ids in block {block.index}: {sorted(unknown)[:5]}")
    merged = {k: new.get(k, current[k]) for k, _ in keyed}
    if merged == current:
        return False

    strs = [r for _, r in keyed]
    span_start = min(r.offset for r in strs)
    span_end = max(r.offset + r.size for r in strs)
    for r in block.resources:
        if r.type != "Str " and r.offset < span_end and r.offset + r.size > span_start:
            raise ResourceError(f"{r.type} resource {r.id} overlaps the string area; refusing to re-pack")

    # Keep the original on-disk order so unchanged strings stay put where possible.
    layout = []
    cursor = span_start
    for key, r in sorted(keyed, key=lambda kr: kr[1].offset):
        raw = merged[key].encode("utf-8", errors="surrogateescape") + b"\0"
        layout.append((r, cursor, raw))
        cursor = (cursor + len(raw) + 3) & ~3
    used_end = layout[-1][1] + len(layout[-1][2])
    if used_end > span_end:
        raise ResourceError(
            f"strings in block {block.index} need {used_end - span_start} bytes but only "
            f"{span_end - span_start} are available ({used_end - span_end} too many)")

    base = block.data_start
    osos[base + span_start:base + span_end] = bytes(span_end - span_start)
    for r, off, raw in layout:
        osos[base + off:base + off + len(raw)] = raw
        struct.pack_into("<II", osos, r.table_pos + 4, off, len(raw))
        r.offset, r.size = off, len(raw)
    return True
