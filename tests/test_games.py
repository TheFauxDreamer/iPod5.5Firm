"""Tests for the manifest of a game, and for the copy and the removal of the games.

The tests use small synthetic games. The tests do not use the files of a real iPod.
"""

from __future__ import annotations

import plistlib

import pytest

from ipodfw import games


def test_the_games_directory_accepts_both_names(tmp_path):
    # The firmware asks for the name games_RO with small letters. The program of iTunes
    # writes the name Games_RO with a capital letter. The file system of macOS keeps no
    # case by default, thus the test uses the name of the case that the file system keeps.
    assert games.games_directory(tmp_path) is None
    for name in ("games_RO", "Games_RO"):
        (tmp_path / name).mkdir()
        found = games.games_directory(tmp_path)
        assert found is not None
        assert found.name.lower() == "games_ro"
        (tmp_path / name).rmdir()


def make_manifest(guid: str = "11002", name: str = "iQuiz", files: list[dict] | None = None) -> bytes:
    """Make the file Manifest.plist of a game."""
    root = {
        "BuildIdentifier": "1446269457-ca6ac6febe09",
        "Files": files if files is not None else [
            {"Digest": "A" * 40, "Path": "Fonts/Arial15Hira13Hybrid0.ipd", "Size": 19504},
            {"Digest": "B" * 40, "Path": "Fonts/Arial15Hira13Hybrid0.txt", "Size": 4779},
        ],
        "GUID": guid,
        "Name": name,
        "Platforms": [{"BuildID": 2902110, "ExecutablePath": "Executables/TWA_1_1_2902110.bin",
                       "LaunchingArtwork": "iQuiz.raw.lcd5", "PlatformID": 1, "PlatformVersion": 1,
                       "Size": 463944}],
        "SampleDataPath": "UserTrivia/Samples",
        "UserDataPath": "UserTrivia/Packs",
        "Version": "1.0",
    }
    return plistlib.dumps(root)


def make_game(folder: Path, guid: str = "11002", name: str = "iQuiz",
              files: list[dict] | None = None, extra: bool = True,
              with_files: bool = True) -> Path:
    """Make a folder of a game with the files of the manifest."""
    folder.mkdir(parents=True, exist_ok=True)
    manifest_files = files if files is not None else [
        {"Digest": "A" * 40, "Path": "Fonts/Arial15Hira13Hybrid0.ipd", "Size": 19504},
        {"Digest": "B" * 40, "Path": "Fonts/Arial15Hira13Hybrid0.txt", "Size": 4779},
    ]
    (folder / "Manifest.plist").write_bytes(make_manifest(guid, name, manifest_files))
    (folder / "Manifest.plist.p7b").write_bytes(b"\x30" * 3548)
    (folder / "iTunesMetaData").write_bytes(b"<plist></plist>")
    exe = folder / "Executables"
    exe.mkdir(exist_ok=True)
    (exe / "TWA_1_1_2902110.bin").write_bytes(b"\x00" * 463944)
    if with_files:
        for entry in manifest_files:
            out = folder / entry["Path"]
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(b"\x00" * entry["Size"])
    if extra:
        (folder / "UserTrivia").mkdir(exist_ok=True)
        (folder / "UserTrivia" / "Packs").mkdir(exist_ok=True)
        (folder / "UserTrivia" / "Packs" / "sample1.txt").write_bytes(b"questions")
    return folder


def test_reads_the_manifest():
    data = make_manifest()
    m = games.parse_manifest(data)
    assert m.guid == "11002"
    assert m.name == "iQuiz"
    assert m.version == "1.0"
    assert m.platform_id == 1
    assert m.executable == "Executables/TWA_1_1_2902110.bin"
    assert m.executable_size == 463944
    assert len(m.files) == 2
    assert m.files[0].path == "Fonts/Arial15Hira13Hybrid0.ipd"
    assert m.files[0].size == 19504
    assert m.total_size == 19504 + 4779


def test_a_file_that_is_not_a_manifest_is_refused():
    with pytest.raises(games.ManifestError):
        games.parse_manifest(b"not a plist")
    with pytest.raises(games.ManifestError):
        games.parse_manifest(plistlib.dumps({"GUID": "1"}))


def test_reads_the_library(tmp_path):
    make_game(tmp_path / "11002", "11002", "iQuiz")
    make_game(tmp_path / "50514", "50514", "Royal Solitaire")
    (tmp_path / "not-a-game").mkdir()
    library = games.load_library(tmp_path)
    assert [g.folder for g in library] == ["11002", "50514"]
    assert library[0].name == "iQuiz"


def test_the_check_gives_the_missing_files(tmp_path):
    game = games.load_game(make_game(tmp_path / "11002"))
    assert games.check_game(game) == []          # the game is complete
    (game.path / "Fonts" / "Arial15Hira13Hybrid0.txt").write_bytes(b"\x00" * 100)
    assert any("Arial15Hira13Hybrid0.txt" in p for p in games.check_game(game))


def test_the_check_gives_a_missing_file(tmp_path):
    game = games.load_game(make_game(tmp_path / "11002", with_files=False))
    problems = games.check_game(game)
    assert any("Arial15Hira13Hybrid0.ipd" in p for p in problems)
    assert any("is missing" in p for p in problems)


def test_installs_a_game(tmp_path):
    source = make_game(tmp_path / "source" / "11002")
    target = tmp_path / "target"
    game = games.load_game(source)
    report = games.install_game(game, target)
    assert report.installed == ["11002"]
    dest = target / "games_RO" / "11002"
    assert (dest / "Manifest.plist").read_bytes() == (source / "Manifest.plist").read_bytes()
    assert (dest / "Manifest.plist.p7b").exists()
    assert (dest / "iTunesMetaData").exists()
    assert (dest / "Executables" / "TWA_1_1_2902110.bin").exists()
    # The files that are not in the manifest are part of the game.
    assert (dest / "UserTrivia" / "Packs" / "sample1.txt").read_bytes() == b"questions"


def test_installs_only_the_selected_games(tmp_path):
    source = tmp_path / "source"
    make_game(source / "11002", "11002", "iQuiz")
    make_game(source / "50514", "50514", "Royal Solitaire")
    target = tmp_path / "target"
    library = games.load_library(source)
    wanted = [g for g in library if g.folder == "11002"]
    report = games.install_library(wanted, target)
    assert report.installed == ["11002"]
    assert sorted(p.name for p in (target / "games_RO").iterdir()) == ["11002"]


def test_install_skips_a_game_that_is_not_complete(tmp_path):
    source = tmp_path / "source"
    make_game(source / "11002", "11002", "iQuiz")
    # The files of the manifest of the second game are missing.
    make_game(source / "50514", "50514", "Royal Solitaire", with_files=False)
    target = tmp_path / "target"
    library = games.load_library(source)
    report = games.install_library(library, target)
    assert report.installed == ["11002"]
    assert report.skipped == ["50514"]
    assert report.warnings


def test_install_copies_the_key_file(tmp_path):
    source = make_game(tmp_path / "source" / "11002")
    key = tmp_path / "IC-Info.sidb"
    key.write_bytes(b"\x11" * 23396)
    target = tmp_path / "target"
    game = games.load_game(source)
    report = games.install_game(game, target, copy_key_file=True, key_file_source=key)
    assert report.key_file_copied
    out = target / "iTunes" / "IC-Info.sidb"
    assert out.read_bytes() == b"\x11" * 23396


def test_install_never_removes_a_file(tmp_path):
    source = make_game(tmp_path / "source" / "11002")
    target = tmp_path / "target"
    game = games.load_game(source)
    games.install_game(game, target)
    keep = target / "games_RO" / "11002" / "KeepMe.txt"
    keep.write_bytes(b"keep")
    games.install_game(game, target)
    assert keep.read_bytes() == b"keep"


def test_remove_games_removes_only_the_game_folders(tmp_path):
    source = make_game(tmp_path / "source" / "11002")
    make_game(tmp_path / "source" / "1B200")
    target = tmp_path / "target"
    games.install_library(games.load_library(tmp_path / "source"), target)
    # the saves and the scores of the games, and a file next to the games
    (target / "gamedata_RW" / "11002").mkdir(parents=True)
    (target / "gamedata_RW" / "11002" / "save.bin").write_bytes(b"data")
    (target / "gamestats_WO" / "11002").mkdir(parents=True)
    (target / "games_RO" / "extra.txt").write_bytes(b"a file")

    report = games.remove_games(target, ["11002"])

    assert report.removed == ["11002"]
    assert not (target / "games_RO" / "11002").exists()
    assert (target / "games_RO" / "1B200").exists()
    # the saves, the scores and the other files stay
    assert (target / "gamedata_RW" / "11002" / "save.bin").read_bytes() == b"data"
    assert (target / "gamestats_WO" / "11002").is_dir()
    assert (target / "games_RO" / "extra.txt").read_bytes() == b"a file"


def test_remove_games_refuses_a_name_that_is_not_a_guid(tmp_path):
    source = make_game(tmp_path / "source" / "11002")
    target = tmp_path / "target"
    games.install_game(games.load_game(source), target)
    (target / "iTunes").mkdir()          # the folder of the keys, outside the games

    report = games.remove_games(target, ["../iTunes"])

    assert report.removed == []
    assert report.missing == ["../iTunes"]
    assert report.warnings
    assert (target / "iTunes").is_dir()  # nothing outside the games was touched


def test_removable_folders_lists_only_guid_folders(tmp_path):
    source = make_game(tmp_path / "source" / "11002")
    target = tmp_path / "target"
    games.install_game(games.load_game(source), target)
    (target / "games_RO" / "gamedata_RW").mkdir()

    assert games.removable_folders(target / "games_RO") == ["11002"]


def test_remove_games_reports_a_missing_game(tmp_path):
    target = tmp_path / "target"
    (target / "games_RO").mkdir(parents=True)

    report = games.remove_games(target, ["50514"])

    assert report.removed == []
    assert report.missing == ["50514"]
    assert report.warnings == []
