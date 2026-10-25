#!/usr/bin/env python3
"""Make the table of the state of the research of each system.

The script reads the table of the systems. The table is at `systems.tsv` in the
folder of the artifacts. The script reads the notes of the research. The
script then finds the note that gives the full research of each system and the
other notes that name a part of the system.

The script writes 1 file. The file is a TSV file. Each row has the name of a
system, the group of the system, the number of the parts, the number of the
parts that the table of the tasks holds, the name of the note that gives the
full research of the system and the names of the other notes.

Usage: make-systems-state.py [OUTDIR]
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
DOCS = HERE.parent / "docs"

# The folder of the artifacts. The folder holds the table of the systems.
STORE = (
    Path.home()
    / "Library/Application Support/iPodFirm/re/retailos-1.3-decompiled"
)

# The notes that give the full research of a system. The key is the group of
# the system. The value is the name of the note.
FULL_RESEARCH = {
    "The kernel of the system": "firmware-task-system.md",
    "The camera and the USB": "firmware-camera.md",
    "USB and the computer": "firmware-usb.md",
    "The user interface": "firmware-ui.md",
    "Power and the hardware": "firmware-power.md",
    "The music and the media": "firmware-media.md",
    "Storage and the file system": "firmware-storage.md",
}

# The notes of the research. The script does not use these notes for the
# table. These notes cover the whole firmware or the whole kernel. The script
# uses the notes to find the names of the parts of a system.
SKIP_NOTES = {
    "firmware-systems.md",
    "firmware-coverage.md",
    "firmware-task-system.md",
    "retailos-decompile.md",
}


def read_systems(path: Path) -> dict[str, str]:
    """Read the table of the systems. The result has the name of each system
    and its group."""
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 2 or parts[0] == "group":
            continue
        out[parts[0]] = parts[1]
    return out


def read_task_table(path: Path) -> dict[str, str]:
    """Read the table of the tasks. The result has the name of each task and
    its group."""
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines()[1:]:
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        out[parts[1]] = parts[3]
    return out


def main() -> int:
    outdir = Path(sys.argv[1]) if len(sys.argv) > 1 else STORE
    outdir.mkdir(parents=True, exist_ok=True)

    systems = read_systems(STORE / "systems.tsv")
    tasks = read_task_table(STORE / "task-table.tsv")
    print(f"systems: {len(systems)}")
    print(f"tasks: {len(tasks)}")

    # The groups of the systems.
    groups: dict[str, list[str]] = defaultdict(list)
    for name, group in systems.items():
        groups[group].append(name)

    # The notes of the research.
    notes = sorted(list(HERE.glob("*.md")) + list(DOCS.glob("*.md")))
    print(f"notes: {len(notes)}")

    # The functions of the code of each note. The script finds the names of
    # the systems in each note.
    hits: dict[str, set[str]] = defaultdict(set)
    for note in notes:
        if note.name in SKIP_NOTES:
            continue
        text = note.read_text(encoding="utf-8", errors="surrogateescape")
        for name in systems:
            if re.search(rf"\b{re.escape(name)}\b", text):
                hits[note.name].add(name)

    # The note that gives the full research of a system covers all the parts
    # of the system.
    for group, note_name in FULL_RESEARCH.items():
        for name in groups.get(group, []):
            hits[note_name].add(name)

    path = outdir / "systems-state.tsv"
    with path.open("w", encoding="utf-8") as handle:
        handle.write(
            "group\tparts\ttasks\tcovered\tnote\tother_notes\n"
        )
        for group in sorted(groups, key=lambda g: (-len(groups[g]), g)):
            parts = sorted(groups[group])
            count = sum(1 for name in tasks if tasks[name] == group)
            full = FULL_RESEARCH.get(group, "")
            covered = set()
            for note, names in hits.items():
                covered |= names & set(parts)
            other = sorted(
                note for note, names in hits.items()
                if names & set(parts) and note != full
            )
            handle.write(
                f"{group}\t{len(parts)}\t{count}\t{len(covered)}\t{full}\t"
                f"{','.join(other)}\n"
            )

    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
