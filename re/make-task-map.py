#!/usr/bin/env python3
"""Make the map of the tasks of the firmware.

The firmware of Apple has a class of tasks. The class has the name "Task". The
name is at 0x100e9d28 in the image of the osos.

The firmware makes a task with the function FUN_1011c808. The function has 7
arguments:

| The argument | The value |
|---|---|
| 1 | The name of the task. |
| 2 | The address of the method of the task. |
| 3 | The names of the classes of the task. The names have a space between them. The function splits the text into the words. |
| 4 | The size of the stack of the task. |
| 5 | The priority of the task. |
| 6 | 0 or 1. The value 1 makes the task with a list of the events. |
| 7 | The number of the events. |

The value 0 of the 3rd argument means that the class of the task is the base
class. The base class has the name "Task". The name is at 0x100e9d28 in the
image of the osos.

The function FUN_100c6b90 makes the object of the task. The function puts the
fields of the object in the object.

| The offset | The value |
|---|---|
| +0x00 | The name of the class. |
| +0x04 | The address of the method of the task. |
| +0x08 | The size of the stack of the task. |
| +0x0c | The priority of the task. |
| +0x10 | The object of the queue. |
| +0x14 | The class of the priority. |

The function FUN_10116e64 gives the number of the priority. The function has 9
classes.

| The class | The number |
|---|---|
| 0 | 126 |
| 1 | 60 |
| 2 | 52 |
| 3 | 51 |
| 4 | 49 |
| 5 | 48 |
| 6 | 10 |
| 7 | 9 |
| 8 | 8 |

The script reads the decompiled code. The script finds each call of
FUN_1011c808. The script writes the table of the tasks.

Usage: make-task-map.py CODE IMAGE [OUTDIR]
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

# The call of the function that makes a task.
CREATE = re.compile(r"FUN_1011c808\(([^;]{0,260}?)\);", re.S)

# The name of a string in the decompiled code. The name has the address of the
# string at the end.
STRING_NAME = re.compile(r"\bs_(.*)_([0-9a-f]{8})\b")

# The name of the class of the task. The base class has the name "Task".
BASE_CLASS = "Task"

# The function that gives the number of the priority class.
PRIORITY = {
    0: 126,
    1: 60,
    2: 52,
    3: 51,
    4: 49,
    5: 48,
    6: 10,
    7: 9,
    8: 8,
}


def read_blocks(code: Path) -> list[tuple[str, str]]:
    """Read the decompiled code. The result has the address and the body of
    every function."""
    text = code.read_text(encoding="utf-8", errors="surrogateescape")
    marks = list(BLOCK_HEADER.finditer(text))
    out = []
    for index, mark in enumerate(marks):
        start = mark.end()
        end = marks[index + 1].start() if index + 1 < len(marks) else len(text)
        out.append((mark.group(1), text[start:end]))
    return out


def pool_value(data: bytes, address: int) -> int | None:
    """The number that the word at the address holds."""
    offset = address - BASE
    if offset < 0 or offset + 4 > len(data):
        return None
    return struct.unpack_from("<I", data, offset)[0]


def name_of(token: str, data: bytes) -> str:
    """The text of a name in the decompiled code. The name has the address of
    the string at the end."""
    match = STRING_NAME.match(token)
    if not match:
        return token
    address = int(match.group(2), 16)
    offset = address - BASE
    if offset < 0 or offset >= len(data):
        return match.group(1)
    end = data.find(b"\x00", offset)
    if end < 0:
        return match.group(1)
    return data[offset:end].decode("ascii", errors="replace")


def classes_of(token: str, data: bytes) -> str:
    """The names of the classes of a task. The argument has the names of the
    classes. The names have a space between them. The value 0 means that the
    class of the task is the base class."""
    if token in ("0", "0x0"):
        return BASE_CLASS
    if token.startswith("&") or token.startswith("auStack") or token.startswith(
        "param"
    ) or token.startswith("uVar") or token.startswith("DAT_"):
        return token
    return name_of(token, data)


def method_of(token: str, data: bytes) -> int:
    """The address of the method of the task. The token is the name of a word
    of a literal pool. The word holds the address of the method."""
    match = re.fullmatch(r"DAT_([0-9a-f]{8})", token)
    if not match:
        return 0
    value = pool_value(data, int(match.group(1), 16))
    return value or 0


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    code = Path(sys.argv[1])
    image = Path(sys.argv[2])
    outdir = Path(sys.argv[3]) if len(sys.argv) > 3 else Path(__file__).parent
    outdir.mkdir(parents=True, exist_ok=True)

    data = image.read_bytes()
    blocks = read_blocks(code)

    rows = []
    for address, body in blocks:
        for match in CREATE.finditer(body):
            arguments = [
                part.strip()
                for part in " ".join(match.group(1).split()).split(",")
            ]
            if len(arguments) < 5:
                continue
            rows.append({
                "creator": address,
                "name": name_of(arguments[0], data),
                "method": method_of(arguments[1], data),
                "class": classes_of(arguments[2], data),
                "stack": arguments[3],
                "priority": arguments[4],
            })
    print(f"the tasks: {len(rows)}")

    tasks_path = outdir / "task-map.tsv"
    with tasks_path.open("w", encoding="utf-8") as handle:
        handle.write(
            "name\tmethod\tclass\tstack_size\tpriority\tcreator\n"
        )
        for row in sorted(rows, key=lambda r: r["name"]):
            handle.write(
                f"{row['name']}\t{row['method']:08x}\t{row['class']}\t"
                f"{row['stack']}\t{row['priority']}\t{row['creator']}\n"
            )

    # The classes of the tasks. The class of the task is the name of the
    # second string, or the base class.
    classes: dict[str, int] = {}
    for row in rows:
        key = row["class"] or BASE_CLASS
        classes[key] = classes.get(key, 0) + 1
    classes_path = outdir / "task-classes.tsv"
    with classes_path.open("w", encoding="utf-8") as handle:
        handle.write("class\ttasks\n")
        for name in sorted(classes, key=lambda n: -classes[n]):
            handle.write(f"{name}\t{classes[name]}\n")

    print(f"the classes of the tasks: {len(classes)}")
    print(f"wrote {tasks_path}")
    print(f"wrote {classes_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
