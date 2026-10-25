#!/usr/bin/env python3
"""Make the inventory of the parts of the firmware.

The script reads the image of the osos of RetailOS 1.3. The script reads the
main resource block of the image. The table of the resources is the list of the
parts of the firmware. The firmware has 2,213 parts in this table.

The script also reads the notes of the research. The notes name the parts of
the firmware. The name has the type of the part and the number of the part.
The name has the form "View 24506" or "Menu 24598". The script finds these
names. The script then marks each part of the firmware as researched or not
researched.

The script also finds the addresses of the code that the notes name. The
address in a note is the offset of the image. The address in the table of the
functions has the base 0x10000000. The script removes the base from the
address of the table. The script then counts the functions that the notes name.

The script writes 3 files.

The first file is a TSV file. Each row has the type of the resource, the
number of the resource, the size of the resource, the offset of the resource
and the notes that name the resource.

The second file is a TSV file. Each row has the type of the resource, the
number of the resources of that type and the number of the resources that the
notes name.

The third file is a TSV file. Each row has the name of a note, the number of
the functions that the note names and the number of the lines of the C code of
those functions.

Usage: make-firmware-inventory.py IMAGE [OUTDIR]
"""

from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent

# The name of each type of resource. The name comes from the meaning of the
# type in the firmware of Apple.
TYPE_NAMES = {
    "View": "View",
    "BMap": "BMap",
    "Type": "Type",
    "Menu": "Menu",
    "Str ": "String",
    "Bits": "Bits",
    "LDTm": "Load time",
    "TCmd": "TCmd",
}

# The name of a part in a note. The name has the type and the number.
PART_NAME = re.compile(
    r"\b(View|Menu|BMap|TCmd|LDTm|Str)\s+(\d{1,6})\b"
)

# The type of a part in a note. The type "Str" has a space in the table.
NOTE_TYPES = {
    "View": "View",
    "Menu": "Menu",
    "BMap": "BMap",
    "TCmd": "TCmd",
    "LDTm": "LDTm",
    "Str": "Str ",
}

# The address of the code in a note.
CODE_ADDRESS = re.compile(r"0x([0-9a-fA-F]{4,8})")

# The base address of the osos image in the memory of the iPod. The addresses
# in the table of the functions have this base. The addresses in the notes do
# not have this base.
IMAGE_BASE = 0x10000000


def normalise(address: str) -> str:
    """The address without the base and without the leading zeroes. The notes
    and the table of the functions use the same form after this change."""
    value = int(address, 16)
    if value >= IMAGE_BASE:
        value -= IMAGE_BASE
    return f"{value:x}"


def read_notes(dirs: list[Path]) -> dict[tuple[str, int], set[str]]:
    """Find the parts that each note names. The result has the type and the
    number of the part, and the names of the notes."""
    found: dict[tuple[str, int], set[str]] = defaultdict(set)
    for directory in dirs:
        for note in sorted(directory.glob("*.md")):
            text = note.read_text(encoding="utf-8", errors="surrogateescape")
            for match in PART_NAME.finditer(text):
                key = (NOTE_TYPES[match.group(1)], int(match.group(2)))
                found[key].add(note.stem)
    return found


def read_code(dirs: list[Path], index: dict[str, int]) -> dict[str, set[str]]:
    """Find the functions of the code that each note names. The result has the
    name of the note and the addresses of the functions."""
    found: dict[str, set[str]] = {}
    for directory in dirs:
        for note in sorted(directory.glob("*.md")):
            text = note.read_text(encoding="utf-8", errors="surrogateescape")
            hits = {
                normalise(match.group(1))
                for match in CODE_ADDRESS.finditer(text)
            }
            hits = {hit for hit in hits if hit in index}
            if hits:
                found[note.stem] = hits
    return found


def read_index(index_path: Path) -> dict[str, int]:
    """Read the table of the functions. The result has the address of each
    function and the number of lines of the C code."""
    out: dict[str, int] = {}
    if not index_path.exists():
        return out
    for line in index_path.read_text(encoding="utf-8").split("\n")[1:]:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        out[normalise(parts[0])] = int(parts[2] or 0)
    return out


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    image = Path(sys.argv[1])
    outdir = Path(sys.argv[2]) if len(sys.argv) > 2 else HERE
    outdir.mkdir(parents=True, exist_ok=True)

    sys.path.insert(0, str(HERE.parent / "src"))
    from ipodfw import resources

    data = image.read_bytes()
    blocks = resources.scan(data)
    main_block = resources.main_block(blocks)

    notes = read_notes([HERE, HERE.parent / "docs"])
    index = read_index(Path(
        "~/Library/Application Support/iPodFirm/re/retailos-1.3-decompiled/"
        "osos-functions.tsv"
    ).expanduser())
    code = read_code([HERE, HERE.parent / "docs"], index)
    print(f"parts in the main block: {len(main_block.resources)}")
    print(f"parts named in the notes: {len(notes)}")
    print(f"functions in the table: {len(index)}")

    # The parts of the firmware. The key is the type and the number.
    parts: dict[tuple[str, int], dict] = {}
    for resource in main_block.resources:
        parts[(resource.type, resource.id)] = {
            "size": resource.size,
            "offset": main_block.abs(resource),
        }

    # The table of the parts.
    parts_path = outdir / "firmware-parts.tsv"
    with parts_path.open("w", encoding="utf-8") as handle:
        handle.write("type\ttype_name\tid\tsize\toffset\tnote_count\tnotes\n")
        for (rtype, rid), part in sorted(parts.items()):
            found = sorted(notes.get((rtype, rid), []))
            handle.write(
                f"{rtype}\t{TYPE_NAMES.get(rtype, rtype)}\t{rid}\t"
                f"{part['size']}\t0x{part['offset']:x}\t{len(found)}\t"
                f"{','.join(found)}\n"
            )

    # The table of the types.
    types_path = outdir / "firmware-types.tsv"
    total = Counter(rtype for rtype, _rid in parts)
    named = Counter(rtype for rtype, _rid in parts if (rtype, _rid) in notes)
    with types_path.open("w", encoding="utf-8") as handle:
        handle.write("type\ttype_name\tcount\tnamed\tpercent_named\n")
        for rtype, count in sorted(total.items(), key=lambda kv: -kv[1]):
            hits = named.get(rtype, 0)
            percent = 100.0 * hits / count if count else 0.0
            handle.write(
                f"{rtype}\t{TYPE_NAMES.get(rtype, rtype)}\t{count}\t"
                f"{hits}\t{percent:.1f}\n"
            )

    print(f"wrote {parts_path}")
    print(f"wrote {types_path}")

    # The table of the code that the notes name.
    code_path = outdir / "firmware-code-coverage.tsv"
    all_lines = sum(index.values())
    covered: set[str] = set()
    with code_path.open("w", encoding="utf-8") as handle:
        handle.write("note\tfunctions\tlines\tpercent_of_code\n")
        for name, hits in sorted(code.items(), key=lambda kv: -len(kv[1])):
            lines = sum(index[hit] for hit in hits)
            covered |= hits
            percent = 100.0 * lines / all_lines if all_lines else 0.0
            handle.write(
                f"{name}\t{len(hits)}\t{lines}\t{percent:.1f}\n"
            )
        covered_lines = sum(index[hit] for hit in covered)
        percent = 100.0 * covered_lines / all_lines if all_lines else 0.0
        handle.write(
            f"ALL\t{len(covered)}\t{covered_lines}\t{percent:.1f}\n"
        )
    print(f"wrote {code_path}")
    print(f"the notes name {len(covered)} of {len(index)} functions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
