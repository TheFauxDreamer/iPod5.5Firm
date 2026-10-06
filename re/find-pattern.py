#!/usr/bin/env python3
"""Finds byte patterns in a raw file (for example osos.bin). Ghidra is not necessary.

Usage: python3 re/find-pattern.py FILE PATTERN [PATTERN ...]

A PATTERN has the same format as for FindBytes.java: hexadecimal bytes in memory order, with or
without spaces, "??" for any byte, or "text:ABC" for ASCII text ("_" is a space). The result is
the file offset of each match, in hexadecimal. With osos, the offset is the CPU address.
The program uses a regular expression on the bytes, so it is fast also for a 7 MB file.
"""
import re
import sys


def compile_pattern(p: str) -> re.Pattern:
    if p.startswith("text:"):
        return re.compile(re.escape(p[5:].replace("_", " ").encode("ascii")))
    h = p.replace(" ", "")
    if len(h) % 2:
        raise SystemExit(f"The pattern has an odd count of hexadecimal digits: {p}")
    parts = []
    for i in range(0, len(h), 2):
        pair = h[i:i + 2]
        parts.append(b"." if pair == "??" else re.escape(bytes([int(pair, 16)])))
    return re.compile(b"".join(parts), re.DOTALL)


def main() -> None:
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    data = open(sys.argv[1], "rb").read()
    for n, p in enumerate(sys.argv[2:], 1):
        rx = compile_pattern(p)
        hits = []
        pos = 0
        while (m := rx.search(data, pos)) is not None:   # also finds matches that overlap
            hits.append(m.start())
            pos = m.start() + 1
        for h in hits:
            print(f"{n}\t0x{h:x}")
        print(f"# pattern {n}: {len(hits)} match(es)")


if __name__ == "__main__":
    main()
