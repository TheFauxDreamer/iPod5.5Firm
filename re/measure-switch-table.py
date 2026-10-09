"""Measure how well the Dark Mode switch table compresses.

Usage: python3 re/measure-switch-table.py <iPod_25.1.3.ipsw> <theme.ipodtheme>

The script builds "Switch on iPod" as src/ipodfw/darkmode.py does. Then it compresses the change
data with a set of methods. It writes no file. The results are in re/dark-mode-compression.md.
"""

import bz2
import lzma
import struct
import sys
import zlib
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "src"))
from ipodfw import darkmode                                        # noqa: E402
from ipodfw.themeimport import OSOS_LIMIT, Theme, load_firmware    # noqa: E402


def lz4_compress(src: bytes) -> bytes:
    """LZ4 block format. A simple greedy compressor: a hash of 4 bytes and a 64 KB window."""
    out, h, i, anchor, n = bytearray(), {}, 0, 0, len(src)

    def length(r: int) -> None:
        while r >= 255:
            out.append(255)
            r -= 255
        out.append(r)

    def emit(lit: bytes, mlen: int | None, off: int) -> None:
        ml = None if mlen is None else mlen - 4
        out.append((min(len(lit), 15) << 4) | (0 if ml is None else min(ml, 15)))
        if len(lit) >= 15:
            length(len(lit) - 15)
        out.extend(lit)
        if ml is not None:
            out.extend(struct.pack("<H", off))
            if ml >= 15:
                length(ml - 15)

    while i + 12 <= n:
        k = src[i:i + 4]
        c = h.get(k)
        h[k] = i
        if c is not None and i - c < 65536:
            m = 4
            while i + m < n - 5 and src[c + m] == src[i + m]:
                m += 1
            emit(src[anchor:i], m, i - c)
            for j in range(i + 1, i + m):
                h[src[j:j + 4]] = j
            i += m
            anchor = i
        else:
            i += 1
    emit(src[anchor:], None, 0)
    return bytes(out)


def lz4_decompress(src: bytes) -> bytes:
    """The decoder, to make sure that the compressor is correct."""
    out, i = bytearray(), 0

    def length(v: int) -> int:
        nonlocal i
        while True:
            b = src[i]
            i += 1
            v += b
            if b != 255:
                return v

    while i < len(src):
        tok = src[i]
        i += 1
        ll = tok >> 4
        if ll == 15:
            ll = length(ll)
        out += src[i:i + ll]
        i += ll
        if i >= len(src):
            break
        off = src[i] | src[i + 1] << 8
        i += 2
        ml = tok & 15
        if ml == 15:
            ml = length(ml)
        for _ in range(ml + 4):
            out.append(out[-off])
    return bytes(out)


def rle_zero(src: bytes) -> int:
    """The size with a zero-run RLE: 00 and a count for a run of zeros, other bytes unchanged."""
    size, i = 0, 0
    while i < len(src):
        if src[i] == 0:
            j = i
            while j < len(src) and src[j] == 0 and j - i < 255:
                j += 1
            size, i = size + 2, j
        else:
            size, i = size + 1, i + 1
    return size


def packbits(src: bytes) -> int:
    """The size with a PackBits RLE: runs of one byte value, other bytes as literals."""
    size, i, lit = 0, 0, 0
    while i < len(src):
        j = i
        while j < len(src) and src[j] == src[i] and j - i < 128:
            j += 1
        if j - i >= 3:
            if lit:
                size, lit = size + 1 + lit, 0
            size, i = size + 2, j
        else:
            lit, i = lit + 1, i + 1
            if lit == 128:
                size, lit = size + 1 + lit, 0
    return size + (1 + lit if lit else 0)


def index_varint(index: bytes) -> bytes:
    """The index with the distance from the end of the previous change, as varints."""
    out, prev = bytearray(), 0
    for k in range(0, len(index), 8):
        at, ln = struct.unpack_from("<II", index, k)
        for v in ((at - prev) & 0xFFFFFFFF, ln):
            while v >= 0x80:
                out.append(v & 0x7F | 0x80)
                v >>= 7
            out.append(v)
        prev = at + ln
    return bytes(out)


def size(x: int) -> str:
    return f"{x:>9,} bytes ({x / 1024:6.1f} KB)"


def methods(name: str, data: bytes) -> None:
    lz = lz4_compress(data)
    if lz4_decompress(lz) != data:
        raise SystemExit("The LZ4 round trip failed.")
    print(f"{name}: {size(len(data))}, zero bytes {data.count(0) / len(data):.1%}")
    rows = [("zero-run RLE", rle_zero(data)), ("PackBits RLE", packbits(data)), ("LZ4 (greedy)", len(lz)),
            ("deflate -9", len(zlib.compress(data, 9))), ("bzip2 -9", len(bz2.compress(data, 9))),
            ("LZMA -9e", len(lzma.compress(data, preset=9 | lzma.PRESET_EXTREME)))]
    for label, n in rows:
        print(f"  {label:13} {size(n)}  {len(data) / n:5.2f}x")
    print()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    fw, _ = load_firmware(sys.argv[1])
    osos = fw.image("osos")
    theme = Theme.from_json(Path(sys.argv[2]).read_text())
    _, info = darkmode.build(fw, osos, theme, REPO / "patches/dark-mode", darkmode.stock_sha256(fw))
    table, _ = darkmode.switch_table(theme, osos)
    _, n, data_at = struct.unpack_from("<III", table, 0)
    index, xor = table[12:data_at], table[data_at:]

    # The dark bytes, in the same sequence as the XOR data (the rules of switch_table).
    dark, work, kinds, kind_bytes = bytearray(), bytearray(osos), Counter(), Counter()
    for c in theme.effective_changes():
        if c.offset + len(c.old) > len(osos) or bytes(work[c.offset:c.offset + len(c.old)]) != c.old:
            continue
        work[c.offset:c.offset + len(c.new)] = c.new
        dark += c.new
        kinds[c.resource.split()[0]] += 1
        kind_bytes[c.resource.split()[0]] += len(c.new)

    print(f"Theme: {theme.name}, changes in the table: {n}, changes left out: {info['changes_left_out']}")
    print(f"Table at {info['table'][0]:#x}, menu at {info['menu'][0]:#x}, "
          f"patch code {info['patch'][0]}-{info['patch'][1]}, end {info['end']:#x}")
    print(f"Free space after the build: {size(OSOS_LIMIT - info['end'])} (limit {OSOS_LIMIT:#x})")
    print()
    print("Resource types in the table:")
    for k, v in kind_bytes.most_common():
        print(f"  {k:6} {kinds[k]:5} changes {size(v)}")
    print()
    print(f"Table: {size(len(table))} (index {len(index):,}, data {len(xor):,})")
    print()
    methods("XOR data", xor)
    methods("Dark bytes", bytes(dark))
    iv = index_varint(index)
    print(f"Index: {size(len(index))}, varint {size(len(iv))}, varint + deflate {size(len(zlib.compress(iv, 9)))}")
    print()
    for label, d in (("XOR + LZ4", len(lz4_compress(xor))), ("XOR + deflate", len(zlib.compress(xor, 9))),
                     ("dark + LZ4", len(lz4_compress(bytes(dark)))), ("dark + deflate", len(zlib.compress(bytes(dark), 9)))):
        total = 12 + len(iv) + d
        print(f"Table with {label:14}: {size(total)}, free space {size(OSOS_LIMIT - info['end'] + len(table) - total)}")


if __name__ == "__main__":
    main()
