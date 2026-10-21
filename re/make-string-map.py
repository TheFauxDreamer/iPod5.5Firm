#!/usr/bin/env python3
"""Make the map of the strings and the functions of the decompiled firmware.

The script reads the C code of every function. The code comes from the
decompiler. The script reads the image of the firmware.

The firmware reaches a string in 2 ways that the image shows.

1. The decompiler gives a string a name. The name starts with "s_" and ends
   with the address of the string. The script reads the address from the name.
   The script reads the text from the image.

2. The firmware puts the number of a string in a word of a literal pool. The
   decompiler gives the word the name "DAT_". The name ends with the address
   of the word. The script reads the number from the word. The number is the
   id of a string in the resource table of the image. The script reads the
   text from the resource table. The script accepts the word only if the code
   passes the word to a call. The script accepts the number only if the
   number is the id of a string in the table.

The script writes 3 files.

The first file is a TSV file. Each row has the address of a function, the
name of the function, the address of a string, the text of the string and the
way that the function reaches the string.

The second file is a TSV file. Each row has the address of a function, the
name of the function, the name that this script gives to the function, the
subsystem of the function and the strings that the function uses.

The third file is a TSV file. Each row has the address of a string, the text
of the string and the functions that use the string.

Usage: make-string-map.py CODE IMAGE [OUTDIR]
"""

from __future__ import annotations

import re
import struct
import sys
from collections import Counter, defaultdict
from pathlib import Path

# The name that the decompiler gives to a string. The name starts with "s_".
# The name ends with the address of the string.
STRING_SYMBOL = re.compile(r"\bs_[A-Za-z0-9_]*_([0-9a-f]{8})\b")

# The name that the decompiler gives to a word of a literal pool.
POOL_SYMBOL = re.compile(r"\bDAT_([0-9a-f]{8})\b")

# The call of a function. The pattern has the arguments of the call.
CALL = re.compile(r"\b(?:thunk_)?FUN_[0-9a-f]{8}\(([^()]*)\)")

# An argument of a call that is the name of a word of a literal pool.
POOL_ARGUMENT = re.compile(r"^DAT_([0-9a-f]{8})$")

# The header of a block of the decompiled code.
BLOCK_HEADER = re.compile(r"^/\* ==== ([0-9a-f]{8}) (\S+) ==== \*/$", re.M)

# The base address of the osos image in the memory of the iPod.
BASE = 0x10000000

# The rules that name a subsystem. The first rule that matches a string names
# the subsystem. The rules are in the order of priority.
SUBSYSTEM_RULES = [
    ("DRM and FairPlay", (
        "game", "Game", "games", "Games", "DRM", "drm", "FairPlay",
        "AppleVideo", "AppleDRM", "IDatabase", "sinf", "account",
    )),
    ("Video and photo", (
        "Video", "video", "Photo", "photo", "Album", "album", "Artwork",
        "artwork", "ARTWORK", "Thumbnail", "thumbnail", "Codec", "codec",
        "MPEG", "H264", "Screen", "screen", "Display", "display", "ithmb",
        "Movie", "movie", "TV ",
    )),
    ("Music and audio", (
        "Audio", "audio", "MP3", "mp3", "AAC", "aac", "WAV", "wav", "AIFF",
        "MIDI", "midi", "Sound", "sound", "Volume", "volume", "Equalizer",
        "Play", "play", "Song", "song", "Track", "track", "Artist", "artist",
        "Genre", "genre", "Shuffle", "shuffle", "Repeat", "M4A", "m4a",
        "Music", "music", "Radio", "radio",
    )),
    ("Files and storage", (
        "File", "file", "Directory", "directory", "Folder", "folder",
        "HFS", "hfs", "FAT", "Disk", "disk", "ATA", "SFLASH", "NOR", "Flash",
        "Storage", "storage", "iPod_Control", "itdb", "iTunesDB", "Database",
        "database", "IC-Info",
    )),
    ("System and services", (
        "Kernel", "kernel", "Task", "task", "Thread", "thread", "Timer",
        "timer", "IRQ", "Semaphore", "Mutex", "Message", "Queue", "ThreadX",
        "eSystem", "Config", "config", "Setting", "setting", "Prefs",
        "prefs", "Region", "region", "Locale", "Battery", "battery", "Power",
        "power", "Sleep", "sleep", "Wake", "wake", "Backlight", "backlight",
        "ClickWheel", "clickwheel", "Button", "button", "Input", "input",
        "OSManager", "Menu", "menu", "ScreenManager", "Device", "device",
        "About", "Reset", "Language", "language",
    )),
    ("Tools and build", (
        "build", "Build", "Make", "make", "Version", "version", "Copyright",
        "Debug", "debug", "Error", "error", "Log", "log", "Test", "test",
    )),
]

# The name for a function that uses no string.
NO_STRING = "No string"


def read_blocks(code: Path) -> list[tuple[str, str, str]]:
    """Read the decompiled code. The result has the address, the name and the
    body of every function."""
    text = code.read_text(encoding="utf-8", errors="surrogateescape")
    blocks = []
    matches = list(BLOCK_HEADER.finditer(text))
    for index, match in enumerate(matches):
        start = match.end()
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        blocks.append((match.group(1), match.group(2), text[start:end]))
    return blocks


def read_resource_strings(image: Path) -> dict[int, tuple[int, str]]:
    """Read the strings of the resource table of the image. The result has the
    number of each string, the address of the string and the text of the
    string.

    The script uses the reader of the project. The reader gives the main
    resource block of the image."""
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))
    from ipodfw import resources

    data = image.read_bytes()
    blocks = resources.scan(data)
    if not blocks:
        return {}
    main = resources.main_block(blocks)
    out: dict[int, tuple[int, str]] = {}
    for key, resource in resources.string_key(main):
        if not key.lstrip("-").isdigit():
            continue
        text = data[main.abs(resource):main.abs(resource) + resource.size]
        out[int(key)] = (main.abs(resource), text.rstrip(b"\0").decode(
            "utf-8", errors="surrogateescape"))
    return out


def word_at(data: bytes, address: int) -> int | None:
    """The number that the word at the address holds."""
    offset = address - BASE
    if offset < 0 or offset + 4 > len(data):
        return None
    return struct.unpack_from("<I", data, offset)[0]


def as_number(value: int) -> int:
    """The number that a word holds as a signed number."""
    if value >= 0x80000000:
        return value - 0x100000000
    return value


def clean(text: str) -> str:
    """The text of a string without the characters that break the TSV file."""
    return text.replace("\t", " ").replace("\r", " ").replace("\n", " ")


def subsystem_of(texts: list[str]) -> str:
    """Give the subsystem of a function. The name comes from the strings that
    the function uses."""
    for name, keys in SUBSYSTEM_RULES:
        for text in texts:
            for key in keys:
                if key in text:
                    return name
    return NO_STRING


def function_name(texts: list[str]) -> str:
    """Give a name to a function. The name comes from the strings that the
    function uses. The name is the text of the longest string that the
    function uses. The name is short."""
    if not texts:
        return ""
    best = max(texts, key=len)
    name = re.sub(r"[^A-Za-z0-9]+", "_", best).strip("_")
    if not name:
        return ""
    return name[:48]


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    code = Path(sys.argv[1])
    image = Path(sys.argv[2])
    outdir = Path(sys.argv[3]) if len(sys.argv) > 3 else code.parent
    outdir.mkdir(parents=True, exist_ok=True)

    data = image.read_bytes()
    resource_strings = read_resource_strings(image)
    blocks = read_blocks(code)

    # The strings of every function. The key is the address of the function.
    # The value has the address of the string, the text of the string and the
    # way that the function reaches the string.
    used: dict[str, dict[str, tuple[str, str]]] = defaultdict(dict)

    for address, _name, body in blocks:
        found = used[address]

        # Way 1. The decompiler gives a string a name.
        for match in STRING_SYMBOL.finditer(body):
            string_address = int(match.group(1), 16)
            offset = string_address - BASE
            if offset < 0 or offset >= len(data):
                continue
            end = data.find(b"\x00", offset)
            if end < 0:
                continue
            text = data[offset:end].decode("ascii", errors="replace")
            found[f"{string_address:08x}"] = (text, "name")

        # Way 2. The number of a string in a word of a literal pool. The code
        # must pass the word to a call. The number must be the id of a string
        # in the resource table.
        for call in CALL.finditer(body):
            for argument in call.group(1).split(","):
                match = POOL_ARGUMENT.match(argument.strip())
                if not match:
                    continue
                value = word_at(data, int(match.group(1), 16))
                if value is None:
                    continue
                number = as_number(value)
                if number not in resource_strings:
                    continue
                string_address, text = resource_strings[number]
                found[f"{string_address:08x}"] = (text, "pool")

    # The first file. The strings and the functions that use them.
    map_path = outdir / "osos-string-map.tsv"
    with map_path.open("w", encoding="utf-8") as handle:
        handle.write(
            "function_address\tfunction_name\tstring_address\tstring_text\tway\n"
        )
        for address, name, _body in blocks:
            for string_address, (text, way) in sorted(used.get(address, {}).items()):
                handle.write(
                    f"{address}\t{name}\t{string_address}\t"
                    f"{clean(text)}\t{way}\n"
                )

    # The second file. The name of every function and the strings that it uses.
    name_path = outdir / "osos-function-names.tsv"
    with name_path.open("w", encoding="utf-8") as handle:
        handle.write(
            "function_address\tfunction_name\tsuggested_name\tsubsystem\tstrings\n"
        )
        for address, name, _body in blocks:
            found = used.get(address, {})
            texts = [text for text, _way in found.values()]
            suggested = function_name(texts)
            subsystem = subsystem_of(texts)
            joined = " | ".join(
                f"{key}:{clean(text)}" for key, (text, _way) in sorted(found.items())
            )
            handle.write(
                f"{address}\t{name}\t{suggested}\t{subsystem}\t{joined}\n"
            )

    # The third file. Every string and the functions that use it.
    table_path = outdir / "osos-strings.tsv"
    users: dict[str, list[str]] = defaultdict(list)
    texts_by_address: dict[str, str] = {}
    for address, _name, _body in blocks:
        for string_address, (text, _way) in used.get(address, {}).items():
            users[string_address].append(address)
            texts_by_address.setdefault(string_address, text)
    with table_path.open("w", encoding="utf-8") as handle:
        handle.write("string_address\tstring_text\tuser_count\tfunctions\n")
        for string_address, addresses in sorted(users.items()):
            handle.write(
                f"{string_address}\t{clean(texts_by_address[string_address])}\t"
                f"{len(addresses)}\t{','.join(sorted(addresses))}\n"
            )

    with_strings = sum(1 for address in used if used[address])
    ways = Counter(way for found in used.values() for _t, way in found.values())
    print(f"functions: {len(blocks)}")
    print(f"functions with a string: {with_strings}")
    print(f"distinct strings: {len(users)}")
    print(f"ways: {dict(ways)}")
    print(f"wrote {map_path}")
    print(f"wrote {name_path}")
    print(f"wrote {table_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
