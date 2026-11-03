"""Research only: the "IFD2" dark switch table with RAW, MAP and PAL records.

No app code uses this format. The results are in re/dark-mode-compression.md.

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
"""

from __future__ import annotations

import struct
from collections import Counter, defaultdict
from dataclasses import dataclass, field

MAGIC = 0x32444649          # "IFD2"
RAW, MAP, PAL = 0, 1, 2
GAP = 8                     # join two RAW runs if fewer bytes than this separate them


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


def _raw(at: int, end: int, dark: bytes) -> bytes:
    return struct.pack("<II", at, (RAW << 28) | (end - at)) + _pad(dark[at:end])


@dataclass
class Stats:
    pictures: Counter = field(default_factory=Counter)       # kind -> pictures
    picture_bytes: Counter = field(default_factory=Counter)  # kind -> bytes of the records
    other_runs: int = 0
    other_bytes: int = 0
    map_pixels: int = 0          # u16 values that MAP records examine
    map_misses: int = 0          # values that are not the same as the value before (a search)
    map_steps: int = 0           # binary-search steps
    pal_pixels: int = 0
    raw_bytes: int = 0           # bytes that RAW records copy


def encode(light: bytes, dark: bytes, pictures: list[tuple[int, int]], kinds=(RAW, MAP, PAL)) -> tuple[bytes, Stats]:
    """The table that changes `light` into `dark`. `pictures` are the pixel ranges (start, end) of the
    16-bit pictures. For each picture, the smallest record of `kinds` is used (RAW, then MAP, then PAL
    if the sizes are the same). All other differences become RAW records."""
    assert len(light) == len(dark)
    records: list[bytes] = []
    stats = Stats()
    covered = []
    for a, e in sorted(pictures):
        if a % 2 or e % 2 or light[a:e] == dark[a:e]:
            continue
        covered.append((a, e))
        lx = struct.unpack_from(f"<{(e - a) // 2}H", light, a)
        dx = struct.unpack_from(f"<{(e - a) // 2}H", dark, a)
        options = []
        raw = [_raw(s, t, dark) for s, t in _runs(light, dark, a, e)]
        options.append((sum(map(len, raw)), RAW, raw))
        if MAP in kinds:
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
        if PAL in kinds and len(colours) <= 256:
            bits = next(b for b in (1, 2, 4, 8) if (1 << b) >= len(colours))
            index = {c: i for i, c in enumerate(colours)}
            buf = bytearray(-(-len(dx) * bits // 8))
            for i, y in enumerate(dx):
                bit = i * bits
                buf[bit // 8] |= index[y] << (8 - bits - bit % 8)
            rec = [struct.pack("<IIHH", a, (PAL << 28) | (e - a), len(colours), bits)
                   + _pad(struct.pack(f"<{len(colours)}H", *colours)) + _pad(bytes(buf))]
            options.append((len(rec[0]), PAL, rec))
        size, kind, rec = min(options, key=lambda o: (o[0], o[1]))
        records += rec
        stats.pictures[kind] += 1
        stats.picture_bytes[kind] += size
        if kind == MAP:
            stats.map_pixels += len(lx)
            stats.map_misses += sum(1 for i, x in enumerate(lx) if i == 0 or x != lx[i - 1])
            stats.map_steps += search_steps(lx, [x for x, _ in table])
        elif kind == PAL:
            stats.pal_pixels += len(dx)
    # all other differences
    edges = sorted(covered)
    k = 0
    for s, t in _runs(light, dark, 0, len(light)):
        while k < len(edges) and edges[k][1] <= s:
            k += 1
        if k < len(edges) and edges[k][0] < t:     # inside a picture: done above
            continue
        records.append(_raw(s, t, dark))
        stats.other_runs += 1
        stats.other_bytes += 8 + len(_pad(dark[s:t]))
    body = b"".join(records)
    offsets = list(_record_offsets(body))
    count = len(offsets)
    for p in offsets:
        at, ck = struct.unpack_from("<II", body, p)
        if ck >> 28 == RAW:
            stats.raw_bytes += ck & 0x0FFFFFFF
    return struct.pack("<III", MAGIC, count, 12 + len(body)) + body, stats


def search_steps(values, keys: list[int]) -> int:
    """The loop iterations of the binary search in the C decoder. The decoder searches only for a
    value that differs from the value before."""
    steps = 0
    for i, x in enumerate(values):
        if i and x == values[i - 1]:
            continue
        lo, hi = 0, len(keys)
        while lo < hi:
            steps += 1
            mid = (lo + hi) // 2
            if keys[mid] == x:
                break
            if keys[mid] < x:
                lo = mid + 1
            else:
                hi = mid
    return steps


def _record_size(t: bytes, p: int) -> int:
    _, ck = struct.unpack_from("<II", t, p)
    kind, n = ck >> 28, ck & 0x0FFFFFFF
    if kind == RAW:
        return 8 + n + (-n % 4)
    if kind == MAP:
        return 12 + 4 * struct.unpack_from("<I", t, p + 8)[0]
    if kind == PAL:
        nc, bits = struct.unpack_from("<HH", t, p + 8)
        nb = -(-(n // 2) * bits // 8)
        return 12 + 2 * nc + (-(2 * nc) % 4) + nb + (-nb % 4)
    raise ValueError(f"unknown kind {kind}")


def _record_offsets(body: bytes):
    p = 0
    while p < len(body):
        yield p
        p += _record_size(body, p)


def decode(work: bytearray, table: bytes, base: int = 0) -> None:
    """A model of the C decoder (re/dark-table-map/decode.c). `base` is the address of work[0]."""
    magic, count, size = struct.unpack_from("<III", table, 0)
    assert magic == MAGIC and size == len(table)
    p = 12
    for _ in range(count):
        at, ck = struct.unpack_from("<II", table, p)
        kind, n = ck >> 28, ck & 0x0FFFFFFF
        a = at - base
        if kind == RAW:
            work[a:a + n] = table[p + 8:p + 8 + n]
        elif kind == MAP:
            cnt = struct.unpack_from("<I", table, p + 8)[0]
            pairs = dict(struct.unpack_from("<HH", table, p + 12 + 4 * j) for j in range(cnt))
            px = list(struct.unpack_from(f"<{n // 2}H", work, a))
            struct.pack_into(f"<{n // 2}H", work, a, *(pairs.get(x, x) for x in px))
        elif kind == PAL:
            nc, bits = struct.unpack_from("<HH", table, p + 8)
            cols = struct.unpack_from(f"<{nc}H", table, p + 12)
            idx = p + 12 + 2 * nc + (-(2 * nc) % 4)
            mask = (1 << bits) - 1
            for j in range(n // 2):
                bit = j * bits
                v = (table[idx + bit // 8] >> (8 - bits - bit % 8)) & mask
                if v < nc:
                    struct.pack_into("<H", work, a + 2 * j, cols[v])
        else:
            raise ValueError(f"unknown kind {kind}")
        p += _record_size(table, p)
    assert p == len(table)
