"""The key store of the games of the iPod, and the files of a game.

The file `iPod_Control/iTunes/iEKInfo` holds the keys of the accounts of the
Apple ID. The file holds one record for each account. Each record holds one
record for each key of the account. The key of a game is 16 bytes.

The file `iPod_Control/iTunes/IC-Info.sidb` holds the same keys in a form
that the app cannot read. The file has no known format. The app copies the
file. The app never changes the bytes of the file.

The file `sinf` of a game holds the number of the account, the number of the
key, the vector of AES and the encrypted data of the program.

The research is in [../../re/games-keyfile.md](../../re/games-keyfile.md).
"""

from __future__ import annotations

import plistlib
import re
import shutil
import struct
from dataclasses import dataclass, field
from pathlib import Path

# The name of the file of the keys in the folder iPod_Control/iTunes.
KEY_STORE_NAME = "iEKInfo"

# The name of the other file of the keys. The app copies the file. The app
# cannot read the file.
KEY_FILE_NAME = "IC-Info.sidb"

# The offset of the first record of the file iEKInfo. The first 0x4c bytes
# are the header of the file.
KEY_STORE_HEADER_SIZE = 0x4C

# The size of one key, in bytes.
KEY_SIZE = 16


class KeyStoreError(Exception):
    """The file of the keys is not a file of keys."""


@dataclass
class Key:
    """One key of one account."""

    index: int          # the number of the key, for example 4
    value: bytes        # the key, 16 bytes

    def hex(self) -> str:
        return self.value.hex()


@dataclass
class Account:
    """One account of the Apple ID, with all of its keys."""

    number: int         # the number of the account of the purchase
    keys: list[Key] = field(default_factory=list)

    def key(self, index: int) -> Key | None:
        """Give the key with this number, or None when the account has no such key."""
        for k in self.keys:
            if k.index == index:
                return k
        return None


@dataclass
class Record:
    """One record of the file iEKInfo."""

    tag: str            # the name of the record, for example "user"
    fields: list[int]   # the 32-bit numbers at the start of the record
    data: bytes         # the bytes after the numbers
    children: list["Record"] = field(default_factory=list)

    def child(self, tag: str) -> "Record | None":
        """Give the first child record with this name, or None."""
        for c in self.children:
            if c.tag == tag:
                return c
        return None

    def children_named(self, tag: str) -> list["Record"]:
        """Give all the child records with this name."""
        return [c for c in self.children if c.tag == tag]


@dataclass
class KeyStore:
    """The file iEKInfo: the keys of the accounts of the iPod."""

    accounts: list[Account] = field(default_factory=list)
    device_ids: list[bytes] = field(default_factory=list)   # the records "guid"
    version: int = 0                                        # the number of the first record

    def account(self, number: int) -> Account | None:
        """Give the account with this number, or None when the file has no such account."""
        for a in self.accounts:
            if a.number == number:
                return a
        return None

    def key(self, number: int, index: int) -> Key | None:
        """Give the key of this account, or None when the file has no such key."""
        a = self.account(number)
        return a.key(index) if a else None


def _read_record(buf: bytes, off: int) -> tuple[int, str, bytes] | None:
    """Read one record at this offset. Give None when the bytes are not a record.

    A record has a length of 4 bytes, a name of 4 bytes and a body. The
    length counts the name and the body. The length and the name are big
    endian.
    """
    if off + 8 > len(buf):
        return None
    length = struct.unpack_from(">I", buf, off)[0]
    if length < 8 or off + length > len(buf):
        return None
    tag = buf[off + 4:off + 8].decode("latin-1")
    return length, tag, buf[off + 8:off + length]


def _has_name(tag: str) -> bool:
    """Tell whether the name of a record is a name.

    The name of a record has 4 characters. Each character is printable.
    The name of a record of the file of the keys is "sean", "valu", "indx",
    "user", "key " or "guid".
    """
    return len(tag) == 4 and all(0x20 <= ord(c) <= 0x7E for c in tag)


def _tile(buf: bytes, off: int, end: int) -> list[int] | None:
    """Read the records from off to end. Give the offsets of the records.

    The function gives None when the records do not fill the whole range, or
    when a record has no name.
    """
    out: list[int] = []
    p = off
    while p < end:
        rec = _read_record(buf, p)
        if rec is None or not _has_name(rec[1]):
            return None
        out.append(p)
        p += rec[0]
    return out if p == end else None


def _find_children(buf: bytes, off: int, length: int) -> list[int]:
    """Find the records that the body of a record holds.

    The body of a record starts with some 32-bit numbers. The records come
    after the numbers. The function tries every count of numbers and keeps
    the count that gives the most records.
    """
    body = buf[off + 8:off + length]
    best: list[int] = []
    for skip in range(0, min(len(body) + 1, 64), 4):
        found = _tile(buf, off + 8 + skip, off + length)
        if found is not None and len(found) > len(best):
            best = found
    return best


def _parse(buf: bytes, off: int) -> Record:
    """Make a record and all of its child records."""
    length, tag, body = _read_record(buf, off)
    fields = list(struct.unpack_from(">%dI" % (len(body) // 4), body, 0))
    rec = Record(tag=tag, fields=fields, data=body)
    for child_off in _find_children(buf, off, length):
        rec.children.append(_parse(buf, child_off))
    return rec


def parse_key_store(data: bytes) -> KeyStore:
    """Read the file iEKInfo. Give the keys of the accounts.

    The function raises KeyStoreError when the bytes are not a file of keys.
    """
    if len(data) < KEY_STORE_HEADER_SIZE + 8:
        raise KeyStoreError("The file is too short to be a file of keys.")
    top = _read_record(data, KEY_STORE_HEADER_SIZE)
    if top is None:
        raise KeyStoreError("The file has no record at the start of its body.")
    length, tag, _body = top
    if tag != "sean":
        raise KeyStoreError(f"The file does not start with a key store. It has the name {tag!r}.")

    store = KeyStore()
    for child_off in _find_children(data, KEY_STORE_HEADER_SIZE, length):
        child = _parse(data, child_off)
        if child.tag == "user":
            store.accounts.append(_account(child))
        elif child.tag == "guid":
            store.device_ids.append(child.data[12:])
        elif child.tag == "indx":
            store.version = child.fields[0] if child.fields else 0
    return store


def _account(rec: Record) -> Account:
    """Make an account and its keys from a record "user"."""
    number = rec.fields[0] if rec.fields else 0
    account = Account(number=number)
    for key_rec in rec.children_named("key "):
        index = key_rec.fields[0] if key_rec.fields else 0
        value_rec = key_rec.child("valu")
        if value_rec is None:
            continue
        value = value_rec.data[12:12 + KEY_SIZE]
        if len(value) == KEY_SIZE:
            account.keys.append(Key(index=index, value=value))
    return account


def load_key_store(path: str | Path) -> KeyStore:
    """Read the file iEKInfo at this path."""
    return parse_key_store(Path(path).read_bytes())


@dataclass
class GameKeys:
    """The keys of one game, and the account that owns the game."""

    number: int         # the number of the account, from the atom "user"
    key_index: int      # the number of the key, from the atom "key "
    iv: bytes           # the vector of AES, 16 bytes, from the atom "iviv"
    name: str           # the name of the account, from the atom "name"
    key: Key | None     # the key of the account, when the file of the keys has it


def _atoms(buf: bytes, off: int, end: int) -> list[tuple[str, bytes]]:
    """Read the atoms of a file. Give the name and the body of each atom.

    An atom has a size of 4 bytes, a name of 4 bytes and a body. The size
    counts the name and the body. The size and the name are big endian.
    """
    out: list[tuple[str, bytes]] = []
    while off + 8 <= end:
        size = struct.unpack_from(">I", buf, off)[0]
        if size < 8 or off + size > end:
            break
        out.append((buf[off + 4:off + 8].decode("latin-1"), buf[off + 8:off + size]))
        off += size
    return out


def parse_sinf(data: bytes) -> dict[str, bytes]:
    """Read the file sinf of a game. Give the body of each atom.

    The atoms "user", "key ", "iviv", "righ", "name" and "priv" are in the
    atom "schi" of the atom "sinf".
    """
    out: dict[str, bytes] = {}
    for tag, body in _atoms(data, 0, len(data)):
        if tag != "sinf":
            continue
        for tag2, body2 in _atoms(body, 0, len(body)):
            if tag2 == "schi":
                for tag3, body3 in _atoms(body2, 0, len(body2)):
                    out[tag3] = body3
            else:
                out[tag2] = body2
    return out


def game_keys(sinf_data: bytes, store: KeyStore | None) -> GameKeys:
    """Read the file sinf of a game. Give the account and the key of the game."""
    atoms = parse_sinf(sinf_data)
    number = struct.unpack_from(">I", atoms["user"], 0)[0] if "user" in atoms else 0
    index = struct.unpack_from(">I", atoms["key "], 0)[0] if "key " in atoms else 0
    iv = atoms.get("iviv", b"")
    name = atoms.get("name", b"").split(b"\x00")[0].decode("latin-1", "replace")
    key = store.key(number, index) if store else None
    return GameKeys(number=number, key_index=index, iv=iv, name=name, key=key)


def games_directory(root: str | Path) -> Path | None:
    """Find the folder with the games in a folder iPod_Control.

    The firmware asks for the name `games_RO` with small letters. The program of
    iTunes writes the name `Games_RO` with a capital letter. The function accepts
    both names. The function gives None when the folder has no such folder.
    """
    base = Path(root)
    for name in ("games_RO", "Games_RO"):
        candidate = base / name
        if candidate.is_dir():
            return candidate
    return None


def find_games(games_dir: str | Path) -> list[tuple[str, Path]]:
    """Find the games in a folder. Give the name of the game and the path of the file sinf.

    The folder holds one folder for each game. The folder holds the file
    sinf of the program of the game.
    """
    root = Path(games_dir)
    out: list[tuple[str, Path]] = []
    for folder in sorted(root.iterdir()):
        if not folder.is_dir():
            continue
        for sinf in sorted(folder.glob("Executables/*.sinf")):
            out.append((folder.name, sinf))
    return out


# The name of the folder of the games. The firmware asks for the name with
# small letters. The program of iTunes writes the name with a capital letter.
GAMES_DIR_NAME = "games_RO"
GAMES_DIR_NAME_ITUNES = "Games_RO"


@dataclass
class ManifestFile:
    """One file of the array Files of the manifest of a game."""

    path: str            # the path of the file, for example "Fonts/Arial15Hira13Hybrid0.ipd"
    size: int            # the size of the file in bytes
    digest: str          # the digest of the file, 40 hexadecimal characters

    @property
    def exists_in_manifest(self) -> bool:
        return True


@dataclass
class Manifest:
    """The file Manifest.plist of a game."""

    guid: str                            # the name of the folder of the game
    name: str                            # the name of the game, for example "iQuiz"
    version: str
    build_id: str
    platform_id: int                     # the PlatformID of the platform of the game
    executable: str                      # the path of the program of the game
    executable_size: int
    files: list[ManifestFile]            # the array Files of the manifest
    sample_data_path: str = ""
    user_data_path: str = ""

    @property
    def total_size(self) -> int:
        """The sum of the sizes of the files of the array Files."""
        return sum(f.size for f in self.files)


class ManifestError(Exception):
    """The file Manifest.plist of a game is not a manifest."""


def parse_manifest(data: bytes) -> Manifest:
    """Read the file Manifest.plist of a game.

    The function raises ManifestError when the bytes are not a manifest.
    """
    try:
        root = plistlib.loads(data)
    except Exception as e:
        raise ManifestError(f"The file is not a plist: {e}") from e
    if not isinstance(root, dict):
        raise ManifestError("The file is not a dictionary.")
    platforms = root.get("Platforms")
    if not isinstance(platforms, list) or not platforms:
        raise ManifestError("The manifest has no platform.")
    platform = platforms[0]
    files: list[ManifestFile] = []
    for entry in root.get("Files", []):
        files.append(ManifestFile(path=entry.get("Path", ""),
                                  size=int(entry.get("Size", 0)),
                                  digest=entry.get("Digest", "")))
    return Manifest(guid=str(root.get("GUID", "")),
                    name=str(root.get("Name", "")),
                    version=str(root.get("Version", "")),
                    build_id=str(root.get("BuildIdentifier", "")),
                    platform_id=int(platform.get("PlatformID", 0)),
                    executable=platform.get("ExecutablePath", ""),
                    executable_size=int(platform.get("Size", 0)),
                    files=files,
                    sample_data_path=str(root.get("SampleDataPath", "")),
                    user_data_path=str(root.get("UserDataPath", "")))


def load_manifest(path: str | Path) -> Manifest:
    """Read the file Manifest.plist of a game at this path."""
    return parse_manifest(Path(path).read_bytes())


@dataclass
class Game:
    """One game of a folder of games."""

    folder: str          # the name of the folder of the game, the GUID of the game
    path: Path           # the path of the folder of the game
    manifest: Manifest

    @property
    def name(self) -> str:
        return self.manifest.name or self.folder


# The files that the app copies in addition to the array Files of the manifest.
# The file Manifest.plist.p7b is the signature of the manifest. The app must
# never change the manifest or its signature.
EXTRA_FILES = ("Manifest.plist", "Manifest.plist.p7b", "iTunesMetaData")


def load_game(folder: str | Path) -> Game:
    """Read the game in this folder. The folder must hold the file Manifest.plist."""
    path = Path(folder)
    manifest_path = path / "Manifest.plist"
    if not manifest_path.exists():
        raise ManifestError(f"The folder {path} has no file Manifest.plist.")
    return Game(folder=path.name, path=path, manifest=load_manifest(manifest_path))


def load_library(games_dir: str | Path) -> list[Game]:
    """Read the games in a folder. Give the list of the games.

    The function skips a folder that has no file Manifest.plist.
    """
    root = Path(games_dir)
    out: list[Game] = []
    for folder in sorted(root.iterdir()):
        if not folder.is_dir():
            continue
        if not (folder / "Manifest.plist").exists():
            continue
        try:
            out.append(load_game(folder))
        except ManifestError:
            continue
    return out


# The name of the file of the keys that the DRM library of the system reads.
# The app copies the file. The app never changes the bytes of the file.
KEY_FILE_NAME = "IC-Info.sidb"

# The pattern of the folder of one game: hexadecimal characters only. The GUID
# of a game of Apple has 5 characters, for example `11002`. A longer name of
# hexadecimal characters is also a game folder, as iTunes can make one.
GAME_FOLDER_RE = re.compile(r"^[0-9A-Fa-f]+$")


class InstallError(Exception):
    """The app cannot install the games."""


@dataclass
class InstallReport:
    """The result of the copy of the games to an iPod."""

    installed: list[str] = field(default_factory=list)   # the GUID of each game
    skipped: list[str] = field(default_factory=list)      # the GUID of each game that was not copied
    warnings: list[str] = field(default_factory=list)     # the reason of each skip
    bytes_copied: int = 0
    key_file_copied: bool = False


def check_game(game: Game) -> list[str]:
    """Check the game against its manifest. Give the list of the problems.

    An empty list means that the game is complete.
    """
    problems: list[str] = []
    for f in game.manifest.files:
        full = game.path / f.path
        if not full.exists():
            problems.append(f"{f.path} is missing")
        elif full.stat().st_size != f.size:
            problems.append(f"{f.path} has the size {full.stat().st_size}, the manifest says {f.size}")
    for name in EXTRA_FILES:
        if not (game.path / name).exists():
            problems.append(f"{name} is missing")
    if game.manifest.executable:
        exe = game.path / game.manifest.executable
        if not exe.exists():
            problems.append(f"{game.manifest.executable} is missing")
    return problems


def install_game(game: Game, target_root: str | Path, copy_key_file: bool = False,
                 key_file_source: str | Path | None = None) -> InstallReport:
    """Copy one game to the folder iPod_Control of an iPod.

    The target root is the folder `iPod_Control` of the iPod. The app writes
    the game to the folder `games_RO/<GUID>`. The app uses the name with small
    letters. The app never removes a file of the iPod. The app copies over the
    files of the game only.

    The app copies the whole folder of the game. The array `Files` of the
    manifest holds the signed files. The other files of the folder hold the
    content of the game, for example the packs of questions. The app checks the
    size of each file of the array `Files` before the copy.

    The function raises InstallError when the game is not complete.
    """
    problems = check_game(game)
    if problems:
        raise InstallError(f"The game {game.folder} is not complete: " + "; ".join(problems[:5]))

    target_root = Path(target_root)
    games_dir = target_root / GAMES_DIR_NAME
    dest = games_dir / game.folder
    dest.mkdir(parents=True, exist_ok=True)

    report = InstallReport()
    copied = 0
    for src in sorted(game.path.rglob("*")):
        if not src.is_file():
            continue
        rel = src.relative_to(game.path)
        out = dest / rel
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(src.read_bytes())
        copied += out.stat().st_size
    report.installed.append(game.folder)
    report.bytes_copied += copied

    if copy_key_file and key_file_source is not None:
        source = Path(key_file_source)
        if source.exists():
            out = target_root / "iTunes" / KEY_FILE_NAME
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(source.read_bytes())
            report.key_file_copied = True
    return report


def install_library(games: list[Game], target_root: str | Path,
                    copy_key_file: bool = False, key_file_source: str | Path | None = None) -> InstallReport:
    """Copy the games to the folder iPod_Control of an iPod.

    The function copies each game that is complete. The function skips a game
    that is not complete and gives the reason in the report.
    """
    report = InstallReport()
    for game in games:
        try:
            one = install_game(game, target_root, copy_key_file, key_file_source)
        except InstallError as e:
            report.skipped.append(game.folder)
            report.warnings.append(str(e))
            continue
        report.installed.extend(one.installed)
        report.bytes_copied += one.bytes_copied
        report.key_file_copied = report.key_file_copied or one.key_file_copied
    return report


class RemoveError(Exception):
    """The app cannot remove the games."""


@dataclass
class RemoveReport:
    """The result of the removal of the games from an iPod."""

    removed: list[str] = field(default_factory=list)    # the GUID of each game
    missing: list[str] = field(default_factory=list)   # the GUID of each game that was not there
    warnings: list[str] = field(default_factory=list)  # the reason of each refused removal


def removable_folders(games_dir: str | Path) -> list[str]:
    """The GUID of each game folder in the folder of the games.

    The function gives only folders with a name of hexadecimal characters.
    The folders `gamedata_RW` and `gamestats_WO` of the iPod are not game
    folders: their names hold letters that are not hexadecimal.
    """
    base = Path(games_dir)
    if not base.is_dir():
        return []
    return sorted(p.name for p in base.iterdir() if p.is_dir() and GAME_FOLDER_RE.match(p.name))


def remove_games(target_root: str | Path, guids: list[str]) -> RemoveReport:
    """Remove games from the folder iPod_Control of an iPod.

    The function removes the folder `games_RO/<GUID>` of each selected game.
    The GUID must hold hexadecimal characters only. The function refuses every
    other name: it never removes a file outside the folder of a game. The
    folders `gamedata_RW` and `gamestats_WO` hold the saves and the scores of
    the games. The function does not touch them.
    """
    base = Path(target_root)
    games_dir = games_directory(base)
    if games_dir is None:
        raise RemoveError(f"The folder {base} has no folder of the games.")
    report = RemoveReport()
    for guid in guids:
        if not GAME_FOLDER_RE.match(guid):
            report.missing.append(guid)
            report.warnings.append(f"{guid} is not the GUID of a game; refused")
            continue
        folder = games_dir / guid
        if not folder.is_dir():
            report.missing.append(guid)
            continue
        # The folder is inside the folder of the games and its name is a GUID.
        # A link cannot escape: the removal checks that the path has no "..".
        if ".." in folder.resolve().parts or games_dir.resolve() not in folder.resolve().parents:
            report.missing.append(guid)
            report.warnings.append(f"{guid} does not resolve inside the folder of the games; refused")
            continue
        shutil.rmtree(folder)
        report.removed.append(guid)
    return report
