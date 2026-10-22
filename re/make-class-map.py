#!/usr/bin/env python3
"""Make the map of the classes of the firmware.

The firmware of Apple uses a table for each class. The table has the address
of the method of each slot. The address in the table is the offset into the
image.

The constructor of a class sets the first word of the object to the address of
the table of the class. The compiler puts the address of the table in a word
of a literal pool. The decompiler shows the word as `DAT_`.

The script reads the decompiled code. The script finds each constructor. The
script reads the address of the table from the pool of the constructor. The
script then reads the methods of the table from the image.

The script also reads the names of the tasks and the classes from the strings
of the image.

The script writes 2 files.

The first file is a TSV file. Each row has the address of a table, the number
of the slots, the address of the constructor and the addresses of the methods.

The second file is a TSV file. Each row has the name of a task or a class and
the address of the string that has the name.

Usage: make-class-map.py CODE IMAGE [OUTDIR]
"""

from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

# The base address of the osos image in the memory of the iPod.
BASE = 0x10000000

# The header of a block of the decompiled code.
BLOCK_HEADER = re.compile(r"^/\* ==== ([0-9a-f]{8}) (\S+) ==== \*/$", re.M)

# The constructor of a class sets the first word of the object to the address
# of the table of the class. The pattern has the name of the pool word.
CONSTRUCTOR = re.compile(r"\*\s*\w+\s*=\s*DAT_([0-9a-f]{8})\s*;")

# The name of a task or a class. The name starts with a capital letter. The
# name has no space.
NAME = re.compile(
    r"([A-Z][A-Za-z0-9]*(?:Task|Thread|Mgr|Manager|Service|Driver|Handler))"
)

# The smallest number of the slots of a table.
MIN_SLOTS = 6


def read_blocks(code: Path) -> list[tuple[int, str, str]]:
    """Read the decompiled code. The result has the address, the name and the
    body of every function."""
    text = code.read_text(encoding="utf-8", errors="surrogateescape")
    marks = list(BLOCK_HEADER.finditer(text))
    out = []
    for index, mark in enumerate(marks):
        start = mark.end()
        end = marks[index + 1].start() if index + 1 < len(marks) else len(text)
        out.append((int(mark.group(1), 16), mark.group(2), text[start:end]))
    return out


def read_strings(data: bytes) -> list[tuple[int, str]]:
    """Read the strings of the image. The result has the address and the text
    of each string."""
    out: list[tuple[int, str]] = []
    index = 0
    size = len(data)
    while index < size:
        if 32 <= data[index] < 127:
            end = index
            while end < size and 32 <= data[end] < 127:
                end += 1
            if end < size and data[end] == 0 and end - index >= 4:
                out.append((BASE + index, data[index:end].decode("ascii")))
            index = end
        else:
            index += 1
    return out


def read_table(data: bytes, address: int) -> list[int]:
    """Read the methods of the table at the address. The address is the
    offset into the image."""
    size = len(data)
    out: list[int] = []
    offset = address
    while offset + 4 <= size:
        value = struct.unpack_from("<I", data, offset)[0]
        if not (0 < value < size and value % 4 == 0):
            break
        out.append(value)
        offset += 4
    return out


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    code = Path(sys.argv[1])
    image = Path(sys.argv[2])
    outdir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(__file__).parent
    outdir.mkdir(parents=True, exist_ok=True)

    data = image.read_bytes()
    size = len(data)
    blocks = read_blocks(code)

    # The constructors. The result has the address of the table and the
    # address of the constructor.
    constructors: dict[int, int] = {}
    for address, _name, body in blocks:
        for match in CONSTRUCTOR.finditer(body):
            pool = int(match.group(1), 16)
            offset = pool - BASE
            if offset < 0 or offset + 4 > size:
                continue
            value = struct.unpack_from("<I", data, offset)[0]
            if 0 < value < size and value % 4 == 0:
                constructors.setdefault(value, address)
    print(f"constructors: {len(constructors)}")

    # The tables. The result has the address of the table and the methods.
    tables: dict[int, list[int]] = {}
    for table in constructors:
        methods = read_table(data, table)
        if len(methods) >= MIN_SLOTS:
            tables[table] = methods
    print(f"tables with {MIN_SLOTS} slots or more: {len(tables)}")

    # The first file. The tables, the constructors and the methods.
    tables_path = outdir / "class-tables.tsv"
    with tables_path.open("w", encoding="utf-8") as handle:
        handle.write("table_address\tslots\tconstructor\tmethods\n")
        for table in sorted(tables):
            methods = ",".join(f"{slot:x}" for slot in tables[table])
            handle.write(
                f"{table:08x}\t{len(tables[table])}\t"
                f"{constructors[table]:08x}\t{methods}\n"
            )

    # The second file. The names of the tasks and the classes.
    names_path = outdir / "class-names.tsv"
    count = 0
    with names_path.open("w", encoding="utf-8") as handle:
        handle.write("address\tname\n")
        for address, text in read_strings(data):
            if NAME.fullmatch(text):
                handle.write(f"{address:08x}\t{text}\n")
                count += 1
    print(f"names: {count}")

    print(f"wrote {tables_path}")
    print(f"wrote {names_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
