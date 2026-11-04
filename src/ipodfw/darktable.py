"""The "IFD2" dark switch table: a smaller table that the patch dark-mode 1.3 applies at a dark start.

The IFDM table of dark-mode 1.2 holds "old XOR new" for each byte of the theme. But the light pictures
are already in RAM when the patch applies the table. Thus IFD2 gives most dark pictures as a colour
map of the light picture, or as a palette. With Dark Gray, the table is 65,084 bytes, not 681,853.
The research is in re/dark-mode-compression.md and re/dark-table-map/. Swift: DarkTable.swift.

The table (little-endian, each record on a 4-byte boundary):
    u32 "IFD2" (0x32444649), u32 number of records, u32 size of the table in bytes, records.
Each record: u32 address, u32 (kind << 28 | length in bytes), then the data of the kind:
    RAW (0): the new bytes, then zeros to a 4-byte boundary. The decoder copies the bytes.
    MAP (1): u32 N, N x {u16 light, u16 dark}, sorted by light. For each u16 of the range, the
             decoder finds the light value and writes the dark value. Other values do not change.
    PAL (2): u16 number of colours, u16 bits (1, 2, 4 or 8), the colours (u16), zeros to a 4-byte
             boundary, the indices (MSB first), zeros to a 4-byte boundary. The decoder writes each
             u16 of the range from the palette.
RAW records after a MAP record correct the pixels that the map does not give.
The decoder stops at an unknown kind and at a record that does not fit in the table. It skips a
record whose range is not below 0x800000.

A MAP record reads the light pixels. Thus the table is correct only on the image that it was made
from. The build checks this after all patches (check_table).
"""

from __future__ import annotations

import struct
from collections import Counter, defaultdict

from . import pictures as _pictures

MAGIC = 0x32444649          # "IFD2"
IFDM = 0x4D444649           # "IFDM": the XOR table (darkmode.MAGIC)
RAW, MAP, PAL = 0, 1, 2
GAP = 8                     # join two RAW runs if fewer bytes than this separate them
LIMIT = 0x800000            # the decoder writes only below this address


class DarkTableError(Exception):
    pass


def _pad(b: bytes) -> bytes:
    return b + bytes(-len(b) % 4)


def _runs(light: bytes, dark: bytes, lo: int, hi: int) -> list[tuple[int, int]]:
    """The ranges in lo..hi where light and dark differ, joined across gaps below GAP."""
    out, i = [], lo
    while i < hi:
        if light[i] == dark[i]:
            i += 1
            continue
        start, end = i, i + 1
        i += 1
        while i < hi and i - end < GAP:
            if light[i] != dark[i]:
                end = i + 1
            i += 1
        out.append((start, end))
    return out


def _outside(s: int, t: int, covered: list[tuple[int, int]]):
    """The parts of s..t that are not in a covered range."""
    for a, e in covered:
        if a < t and e > s:
            if a > s:
                yield from _outside(s, a, covered)
            if e < t:
                yield from _outside(e, t, covered)
            return
    yield s, t


def _raw(at: int, end: int, dark: bytes) -> bytes:
    return struct.pack("<II", at, (RAW << 28) | (end - at)) + _pad(dark[at:end])


def picture_ranges(osos: bytes, positions) -> list[tuple[int, int]]:
    """The pixel data (start, end) of each 16-bit picture. `positions` are the BMap resource positions."""
    out = set()
    for pos in positions:
        pic = _pictures.parse(osos, pos)
        if pic and pic.depth == 16:
            out.add((pic.data_pos, pic.data_pos + pic.bytes_per_row * pic.height))
    return sorted(out)


def encode(light: bytes, dark: bytes, pictures: list[tuple[int, int]]) -> bytes:
    """The IFD2 table that changes `light` into `dark`. `pictures` are the pixel ranges of the 16-bit
    pictures. For each picture, the smallest record is used (RAW, then MAP, then PAL if the sizes are
    the same). All other differences become RAW records."""
    if len(light) != len(dark) or len(light) > LIMIT:
        raise DarkTableError("The light image and the dark image do not have the same size.")
    records: list[bytes] = []
    covered = []
    pictures = sorted(set(pictures))
    for (a, e), (b, _) in zip(pictures, pictures[1:]):
        if b < e:      # a second MAP on the same pixels gives wrong colours (MAP is not idempotent)
            raise DarkTableError(f"The pixel ranges 0x{a:x} and 0x{b:x} overlap.")
    for a, e in pictures:
        if a % 2 or e % 2 or e > len(light) or light[a:e] == dark[a:e]:
            continue
        covered.append((a, e))
        lx = struct.unpack_from(f"<{(e - a) // 2}H", light, a)
        dx = struct.unpack_from(f"<{(e - a) // 2}H", dark, a)
        raw = [_raw(s, t, dark) for s, t in _runs(light, dark, a, e)]
        options = [(sum(map(len, raw)), RAW, raw)]
        pairs: dict[int, Counter] = defaultdict(Counter)
        for x, y in zip(lx, dx):
            pairs[x][y] += 1
        # the most frequent dark value; with the same count, the smaller value
        best = {x: min(c.items(), key=lambda kv: (-kv[1], kv[0]))[0] for x, c in pairs.items()}
        table = sorted((x, y) for x, y in best.items() if x != y)
        mapped = bytearray(light[a:e])
        struct.pack_into(f"<{len(lx)}H", mapped, 0, *(best[x] for x in lx))
        whole = light[:a] + bytes(mapped) + light[e:]
        rec = [struct.pack("<III", a, (MAP << 28) | (e - a), len(table))
               + b"".join(struct.pack("<HH", x, y) for x, y in table)]
        rec += [_raw(s, t, dark) for s, t in _runs(whole, dark, a, e)]
        options.append((sum(map(len, rec)), MAP, rec))
        colours = sorted(set(dx))
        if len(colours) <= 256:
            bits = next(b for b in (1, 2, 4, 8) if (1 << b) >= len(colours))
            index = {c: i for i, c in enumerate(colours)}
            buf = bytearray(-(-len(dx) * bits // 8))
            for i, y in enumerate(dx):
                bit = i * bits
                buf[bit // 8] |= index[y] << (8 - bits - bit % 8)
            rec = [struct.pack("<IIHH", a, (PAL << 28) | (e - a), len(colours), bits)
                   + _pad(struct.pack(f"<{len(colours)}H", *colours)) + _pad(bytes(buf))]
            options.append((len(rec[0]), PAL, rec))
        records += min(options, key=lambda o: (o[0], o[1]))[2]
    # all other differences: the parts of each run outside the pictures (the records above did those)
    for s, t in _runs(light, dark, 0, len(light)):
        records += [_raw(s2, t2, dark) for s2, t2 in _outside(s, t, covered)]
    body = b"".join(records)
    return struct.pack("<III", MAGIC, len(records), 12 + len(body)) + body


def _fits(table: bytes, p: int, end: int) -> int | None:
    """The size of the record at p, or None if the decoder stops at it."""
    if end - p < 8:
        return None
    _, ck = struct.unpack_from("<II", table, p)
    kind, n = ck >> 28, ck & 0x0FFFFFFF
    room = end - p - 8
    if kind == RAW:
        return 8 + n + (-n % 4) if n <= room - (room & 3) else None
    if kind == MAP:
        if room < 4:
            return None
        cnt = struct.unpack_from("<I", table, p + 8)[0]
        return 12 + 4 * cnt if cnt <= (room - 4) >> 2 else None
    if kind == PAL:
        if room < 4:
            return None
        nc, bits = struct.unpack_from("<HH", table, p + 8)
        if bits not in (1, 2, 4, 8):
            return None
        head = 4 + ((2 * nc + 3) & ~3)
        nb = ((n >> 1) * bits + 7) >> 3
        return 8 + head + ((nb + 3) & ~3) if head <= room and ((nb + 3) & ~3) <= room - head else None
    return None


def apply_table2(work: bytearray, table: bytes) -> None:
    """What the patch (apply_table2 in dark_mode.c) does with an IFD2 table. `work` is the osos."""
    magic, count, size = struct.unpack_from("<III", table, 0)
    if magic != MAGIC or size < 12:
        return
    end = min(size, len(table))
    p = 12
    for _ in range(count):
        rs = _fits(table, p, end)
        if rs is None:
            return
        at, ck = struct.unpack_from("<II", table, p)
        kind, n = ck >> 28, ck & 0x0FFFFFFF
        if not (at < LIMIT and n <= LIMIT - at) or (kind != RAW and (at | n) & 1):
            p += rs
            continue
        if at + n > len(work):
            raise DarkTableError(f"The table writes at 0x{at:x}, after the end of the image.")
        if kind == RAW:
            work[at:at + n] = table[p + 8:p + 8 + n]
        elif kind == MAP:
            cnt = struct.unpack_from("<I", table, p + 8)[0]
            pairs = dict(struct.unpack_from("<HH", table, p + 12 + 4 * j) for j in range(cnt))
            px = struct.unpack_from(f"<{n // 2}H", work, at)
            struct.pack_into(f"<{n // 2}H", work, at, *(pairs.get(x, x) for x in px))
        else:
            nc, bits = struct.unpack_from("<HH", table, p + 8)
            cols = struct.unpack_from(f"<{nc}H", table, p + 12)
            idx = p + 12 + 2 * nc + (-(2 * nc) % 4)
            mask = (1 << bits) - 1
            for j in range(n // 2):
                bit = j * bits
                v = (table[idx + bit // 8] >> (8 - bits - bit % 8)) & mask
                if v < nc:
                    struct.pack_into("<H", work, at + 2 * j, cols[v])
        p += rs


def check_table(osos: bytes, ifdm: bytes, table: bytes) -> None:
    """Make sure that `table` (IFD2) gives on `osos` the same dark image as the IFDM table. Do this on
    the final osos, after all patches: a patch that writes into a range of the table makes it wrong."""
    if table == ifdm:
        return
    from .darkmode import apply_switch_table
    want = bytearray(osos)
    apply_switch_table(want, ifdm)
    got = bytearray(osos)
    apply_table2(got, table)
    if got != want:
        at = next(i for i, (a, b) in enumerate(zip(got, want)) if a != b)
        raise DarkTableError(f"The dark switch table does not give the dark theme at 0x{at:x}. "
                             "A patch can write into the dark theme. The firmware is not made.")
