"""Tests for the key store of the games and for the file sinf of a game.

The tests use a small synthetic file of keys. The tests do not use the file of
a real iPod. The file of a real iPod is personal data.
"""

from __future__ import annotations

import plistlib
import struct

import pytest

from ipodfw import games


def record(tag: str, body: bytes) -> bytes:
    """Make one record of the file iEKInfo.

    The length of a record counts the length field, the name and the body.
    The length field is 4 bytes and the name is 4 bytes.
    """
    assert len(tag) == 4
    return struct.pack(">I", 8 + len(body)) + tag.encode("latin-1") + body


def words(*values: int) -> bytes:
    """Make the 32-bit numbers at the start of a record."""
    return b"".join(struct.pack(">I", v) for v in values)


def key_record(index: int, value: bytes) -> bytes:
    """Make the record of one key."""
    return record("key ", words(index, 1, 0) + record("valu", words(1, 0, 0) + value))


def user_record(number: int, keys: list[tuple[int, bytes]]) -> bytes:
    """Make the record of one account."""
    body = words(number, len(keys), 0) + b"".join(key_record(i, v) for i, v in keys)
    return record("user", body)


def build_key_store(accounts: list[tuple[int, list[tuple[int, bytes]]]],
                    guids: list[bytes] = ()) -> bytes:
    """Make a small file of keys."""
    body = words(1, 0, 0) + bytes(20)
    body += record("indx", words(1, 0, 0, 8))
    for number, keys in accounts:
        body += user_record(number, keys)
    for guid in guids:
        body += record("guid", words(1, 0, 0) + guid)
    top = record("sean", body)
    return struct.pack(">I", len(top)) + bytes(0x48) + top


def atom(tag: str, body: bytes) -> bytes:
    """Make one atom of a file sinf.

    The size of an atom counts the size field, the name and the body.
    """
    return struct.pack(">I", 8 + len(body)) + tag.encode("latin-1") + body


KEY_A = bytes.fromhex("00112233445566778899aabbccddeeff")
KEY_B = bytes.fromhex("0102030405060708090a0b0c0d0e0f10")


def test_reads_the_accounts_and_the_keys():
    data = build_key_store([
        (0x11111111, [(1, KEY_A), (4, KEY_B)]),
        (0x22222222, [(2, KEY_A)]),
    ])
    store = games.parse_key_store(data)
    assert len(store.accounts) == 2
    assert [a.number for a in store.accounts] == [0x11111111, 0x22222222]
    assert len(store.accounts[0].keys) == 2
    assert sum(len(a.keys) for a in store.accounts) == 3
    assert store.account(0x11111111).keys[1].value == KEY_B
    assert store.key(0x11111111, 1).value == KEY_A
    assert store.key(0x22222222, 2).value == KEY_A
    assert store.key(0x11111111, 99) is None
    assert store.account(1) is None


def test_the_key_index_is_the_number_of_the_key():
    data = build_key_store([(0x11111111, [(1, KEY_A), (4, KEY_B)])])
    store = games.parse_key_store(data)
    account = store.account(0x11111111)
    assert account.key(1).value == KEY_A
    assert account.key(4).value == KEY_B


def test_a_file_that_is_not_a_key_store_is_refused():
    with pytest.raises(games.KeyStoreError):
        games.parse_key_store(b"\x00" * 200)
    with pytest.raises(games.KeyStoreError):
        games.parse_key_store(b"")


def test_a_file_with_a_wrong_name_is_refused():
    data = bytearray(build_key_store([(1, [(1, KEY_A)])]))
    data[0x50:0x54] = b"xxxx"
    with pytest.raises(games.KeyStoreError):
        games.parse_key_store(bytes(data))


def test_the_device_ids_are_read():
    # A synthetic device id. A real id holds the serial of the USB of the iPod.
    guid = bytes.fromhex("0123456789abcdef01234567")
    data = build_key_store([(1, [(1, KEY_A)])], guids=[guid])
    store = games.parse_key_store(data)
    assert len(store.device_ids) == 1
    assert store.device_ids[0] == guid


def test_sinf_atoms():
    # The test uses synthetic values.
    inner = (atom("user", struct.pack(">I", 0x11111111))
             + atom("key ", struct.pack(">I", 4))
             + atom("iviv", bytes.fromhex("fedcba9876543210fedcba9876543210"))
             + atom("name", b"Test Account" + bytes(256 - 12)))
    sinf = atom("sinf", atom("frma", bytes(4)) + atom("schi", inner))
    parsed = games.parse_sinf(sinf)
    assert struct.unpack(">I", parsed["user"])[0] == 0x11111111
    assert struct.unpack(">I", parsed["key "])[0] == 4
    assert parsed["iviv"] == bytes.fromhex("fedcba9876543210fedcba9876543210")
    assert parsed["name"].split(b"\x00")[0] == b"Test Account"


def test_the_game_gives_the_account_and_the_key():
    inner = (atom("user", struct.pack(">I", 0x11111111))
             + atom("key ", struct.pack(">I", 4))
             + atom("iviv", bytes(16))
             + atom("name", b"Test Account" + bytes(256 - 12)))
    sinf = atom("sinf", atom("schi", inner))
    store = games.parse_key_store(build_key_store([(0x11111111, [(4, KEY_B)])]))
    g = games.game_keys(sinf, store)
    assert g.number == 0x11111111
    assert g.key_index == 4
    assert g.name == "Test Account"
    assert g.key.value == KEY_B


def test_a_game_without_a_key_in_the_store():
    inner = atom("user", struct.pack(">I", 0x11111111)) + atom("key ", struct.pack(">I", 9))
    sinf = atom("sinf", atom("schi", inner))
    store = games.parse_key_store(build_key_store([(0x11111111, [(4, KEY_B)])]))
    g = games.game_keys(sinf, store)
    assert g.key is None


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
