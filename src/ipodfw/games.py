"""The games of the iPod: the manifest of a game, the copy and the removal.

The app copies the folder of each game to the folder `iPod_Control/games_RO`
of the iPod. The app can also copy the file `iPod_Control/iTunes/IC-Info.sidb`
from another folder. The app never reads or changes the bytes of that file.

The research is in [../../re/games.md](../../re/games.md).
"""

from __future__ import annotations

import plistlib
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path


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


# The name of the file of the keys of the games in the folder iPod_Control/iTunes.
# The app copies the file. The app never reads or changes the bytes of the file.
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
        copy_key(key_file_source, target_root)
        report.key_file_copied = True
    return report


# The largest key file that the app accepts. A real file is much smaller.
KEY_FILE_MAX_SIZE = 4 * 1024 * 1024


def check_key_file(path: str | Path) -> str | None:
    """Check a key file that the owner chose. Return the problem, or None if the file can be
    copied. The file has no known format, thus the check uses only the name and the size. The
    function does not read the bytes of the file."""
    path = Path(path)
    if not path.is_file():
        return f"The file {path.name} is not a file."
    if path.name.lower() != KEY_FILE_NAME.lower():
        return f"The key file must have the name {KEY_FILE_NAME}. The chosen file has the name {path.name}."
    size = path.stat().st_size
    if size == 0:
        return f"The file {path.name} is empty."
    if size > KEY_FILE_MAX_SIZE:
        return f"The file {path.name} is too large ({size} bytes) for a key file."
    return None


def copy_key(source: str | Path, target_root: str | Path) -> None:
    """Copy the owner's key file to iPod_Control/iTunes/IC-Info.sidb as it is. The app never
    reads, changes or makes a key file."""
    problem = check_key_file(source)
    if problem:
        raise InstallError(problem)
    out = Path(target_root) / "iTunes" / KEY_FILE_NAME
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(Path(source).read_bytes())


def install_library(games: list[Game], target_root: str | Path,
                    copy_key_file: bool = False, key_file_source: str | Path | None = None) -> InstallReport:
    """Copy the games to the folder iPod_Control of an iPod.

    The function copies each game that is complete. The function skips a game
    that is not complete and gives the reason in the report. If a key file is
    given, the function copies it one time, after the games.
    """
    report = InstallReport()
    for game in games:
        try:
            one = install_game(game, target_root)
        except InstallError as e:
            report.skipped.append(game.folder)
            report.warnings.append(str(e))
            continue
        report.installed.extend(one.installed)
        report.bytes_copied += one.bytes_copied
    if copy_key_file and key_file_source is not None:
        try:
            copy_key(key_file_source, target_root)
            report.key_file_copied = True
        except InstallError as e:
            report.warnings.append(f"key file: {e}")
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
