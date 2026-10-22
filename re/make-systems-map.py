#!/usr/bin/env python3
"""Make the map of the systems of the firmware.

The firmware of Apple has a list of the systems. Each system has a name. The
name is a string in the image. The name of a task ends with "Task" or
"Thread". The name of a manager ends with "Manager" or "Mgr". The name of a
driver ends with "Driver".

The firmware has a table of the tasks. The table is at 0x1025d63c. Each entry
of the table has the name of the task and the address of the method that
makes the task. The name is at the start of the entry. The name ends with a
zero byte. The name is padded so that the address of the method is a multiple
of 4.

The script reads the image of the osos of RetailOS 1.3. The script reads the
table of the tasks. The script then reads the decompiled code. The script
finds the functions that use each name.

The script also finds the tables of the classes. The table of a class has the
address of the method of each slot. The constructor of a class sets the first
word of the object to the address of the table. The script finds the
constructors with the script [make-class-map.py](make-class-map.py).

The script writes 3 files.

The first file is a TSV file. Each row has the name of a system, the group of
the system, the address of the string that has the name, the address of the
method and the functions that use the name.

The second file is a TSV file. Each row has the group of the systems and the
number of the systems of the group.

The third file is a TSV file. Each row has the address of a table of a class
and the number of the slots and the address of the constructor.

Usage: make-systems-map.py CODE IMAGE [OUTDIR]
"""

from __future__ import annotations

import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

# The base address of the osos image in the memory of the iPod.
BASE = 0x10000000

# The address of the table of the tasks. The offset is in the image.
TASK_TABLE = 0x25D63C

# The end of the table of the tasks.
TASK_TABLE_END = 0x25D7D0

# The header of a block of the decompiled code.
BLOCK_HEADER = re.compile(r"^/\* ==== ([0-9a-f]{8}) (\S+) ==== \*/$", re.M)

# The name of a task in the table of the tasks.
TASK_NAME = re.compile(
    r"([A-Z][A-Za-z0-9]*(?:Task|Thread|Mgr|Manager|Sense|Piezo|Audio))"
)

# The name of a system. The name ends with the word that gives the kind of
# the system.
NAME_SUFFIX = (
    "Task", "Thread", "Manager", "Mgr", "Service", "Driver", "Handler",
    "Controller",
)

# The group of each system. The rules are in the order of priority. The first
# rule that matches the name gives the group.
GROUP_RULES = [
    ("USB and the computer", (
        "USB", "Firewire", "FireWire", "CIap", "Iap", "Host", "Accessory",
        "Accsry", "Opto", "TopPlug", "HPhone",
    )),
    ("Storage and the file system", (
        "Disk", "ATA", "Volume", "FS", "File", "Storage", "HFS", "FAT",
        "Sector", "Flash", "NOR", "Partition", "Stream",
    )),    ("Power and the hardware", (
        "Power", "Backlight", "Battery", "Batt", "Watchdog", "Alarm", "RTC",
        "Piezo", "Motor", "Hold", "CNA", "LowBatt",
    )),
    ("The user interface", (
        "Window", "Menu", "View", "Label", "Dialog", "Event", "Timer",
        "Search", "Scroll", "Select", "Button", "Wheel", "Screen", "Time",
    )),
    ("The music and the media", (
        "Audio", "MP3", "Video", "Photo", "Album", "Artwork", "Track",
        "Song", "Codec", "Play", "Shuffle", "Cache", "Copy", "Import",
        "Daisy", "VC", "Mem",
    )),
    ("The camera and the USB", (
        "Camera", "ICAType4", "PTP",
    )),
    ("The games and the network", (
        "Game", "Net", "TCP", "HTTP", "Socket", "DNS", "DRM", "FairPlay",
    )),
]


def read_blocks(code: Path) -> list[tuple[str, str, str]]:
    """Read the decompiled code. The result has the address, the name and the
    body of every function."""
    text = code.read_text(encoding="utf-8", errors="surrogateescape")
    marks = list(BLOCK_HEADER.finditer(text))
    out = []
    for index, mark in enumerate(marks):
        start = mark.end()
        end = marks[index + 1].start() if index + 1 < len(marks) else len(text)
        out.append((mark.group(1), mark.group(2), text[start:end]))
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


def read_task_table(data: bytes) -> list[tuple[int, str, int]]:
    """Read the table of the tasks. The result has the address of the name,
    the name and the address of the method.

    The table is a list of records. Each record has the name of the task. The
    name ends with a zero byte. The name is padded so that the address of the
    method is a multiple of 4. The method is the address of the function that
    makes the task. Some records have a field with the address of the object
    in the RAM. The field is between the method and the next name.

    The script reads the names of the region. The script then finds the method
    of each name. The method is the first address of the code that follows the
    name."""
    region = data[TASK_TABLE:TASK_TABLE_END]
    names: list[tuple[int, str]] = []
    index = 0
    while index < len(region):
        if 32 <= region[index] < 127:
            end = index
            while end < len(region) and 32 <= region[end] < 127:
                end += 1
            text = region[index:end].decode("latin1")
            if text.isprintable() and TASK_NAME.search(text):
                names.append((BASE + TASK_TABLE + index, text))
            index = end
        else:
            index += 1

    out: list[tuple[int, str, int]] = []
    for address, name in names:
        # The address of the method is a multiple of 4 after the name.
        start = (address - BASE + len(name) + 1 + 3) & ~3
        method = 0
        for step in range(0, 16, 4):
            if start + step + 4 > TASK_TABLE_END:
                break
            value = struct.unpack_from("<I", data, start + step)[0]
            if 0x1000 < value < 0x736000 and value % 4 == 0:
                method = value
                break
        out.append((address, name, method))
    return out


def is_system_name(text: str) -> bool:
    """The text is the name of a system. The name starts with a capital
    letter. The name ends with the word that gives the kind of the system.
    The name has no space."""
    if " " in text or not text[0].isupper():
        return False
    if not text.isalnum():
        return False
    return text.endswith(NAME_SUFFIX)


def group_of(name: str) -> str:
    """The group of a system. The name of the group comes from the rules."""
    for group, keys in GROUP_RULES:
        for key in keys:
            if key in name:
                return group
    return "Other"


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
    lines = {address: body.count("\n") for address, _name, body in blocks}

    # The table of the tasks.
    tasks = read_task_table(data)
    print(f"tasks in the table: {len(tasks)}")

    # The names of the other systems.
    systems: dict[str, int] = {}
    for address, text in read_strings(data):
        if is_system_name(text):
            systems.setdefault(text, address)
    print(f"systems: {len(systems)}")

    # The methods of the tasks. The method makes the task.
    methods = {name: method for _a, name, method in tasks}

    # The functions that use each name.
    users: dict[str, list[str]] = defaultdict(list)
    for address, _name, body in blocks:
        for name in systems:
            if name in body:
                users[name].append(address)
    print(f"functions that use a name: {sum(len(v) for v in users.values())}")

    # The first file. The systems, the methods and the functions.
    systems_path = outdir / "systems.tsv"
    with systems_path.open("w", encoding="utf-8") as handle:
        handle.write(
            "system\tgroup\tstring_address\tmethod\tfunctions\tlines\n"
        )
        for name in sorted(systems):
            found = users.get(name, [])
            total_lines = sum(lines.get(address, 0) for address in found)
            method = methods.get(name, 0)
            handle.write(
                f"{name}\t{group_of(name)}\t{systems[name]:08x}\t"
                f"{method:08x}\t{len(found)}\t{total_lines}\n"
            )

    # The second file. The groups.
    groups_path = outdir / "system-groups.tsv"
    counter = Counter(group_of(name) for name in systems)
    with groups_path.open("w", encoding="utf-8") as handle:
        handle.write("group\tsystems\n")
        for group, count in sorted(counter.items(), key=lambda kv: -kv[1]):
            handle.write(f"{group}\t{count}\n")

    # The third file. The table of the tasks.
    tasks_path = outdir / "task-table.tsv"
    with tasks_path.open("w", encoding="utf-8") as handle:
        handle.write("name_address\tname\tmethod\tgroup\n")
        for address, name, method in tasks:
            handle.write(
                f"{address:08x}\t{name}\t{method:08x}\t{group_of(name)}\n"
            )

    print(f"wrote {systems_path}")
    print(f"wrote {groups_path}")
    print(f"wrote {tasks_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
