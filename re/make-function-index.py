"""Make the index of the functions of a decompiled image.

The script reads a file of decompiled C code. The file has one block for each
function. The block starts with a line that has the address and the name of the
function. The script writes a table with one row for each function.

The table has 5 columns.

| The column | The content |
|---|---|
| address | The address of the function. |
| name | The name of the function. |
| lines | The number of lines of the C code of the function. |
| bytes | The number of bytes of the C code of the function. |
| calls | The number of other functions that the function calls. |

Usage: python3 make-function-index.py INPUT.c OUTPUT.tsv
"""

from __future__ import annotations

import re
import sys

BLOCK = re.compile(r"^/\* ==== ([0-9a-f]+) (\S+) ==== \*/$", re.M)
CALL = re.compile(r"\b(FUN_[0-9a-f]{8})\(")


def rows(source: str) -> list[tuple[str, str, int, int, int]]:
    marks = [
        (m.start(), m.group(1), m.group(2))
        for m in BLOCK.finditer(source)
    ]
    out = []
    for i, (pos, address, name) in enumerate(marks):
        end = marks[i + 1][0] if i + 1 < len(marks) else len(source)
        body = source[pos:end]
        out.append(
            (address, name, body.count("\n"), len(body), len(set(CALL.findall(body))))
        )
    return out


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    with open(sys.argv[1], encoding="utf-8", errors="surrogateescape") as handle:
        source = handle.read()
    table = rows(source)
    with open(sys.argv[2], "w", encoding="utf-8") as handle:
        handle.write("address\tname\tlines\tbytes\tcalls\n")
        for row in table:
            handle.write("\t".join(str(v) for v in row) + "\n")
    print(f"{len(table)} functions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
