import struct

from ipodfw.itunesdb import Track, build, parse_counts


def tracks(n):
    return [Track(title=f"Song {i}", artist="A", album=f"Album {i // 10}", path=f":iPod_Control:Music:F00:T{i:04d}.m4a",
                  size=1000, length_ms=30000, track_nr=i % 10 + 1) for i in range(n)]


def test_structure_and_sizes():
    db = build(tracks(25))
    info = parse_counts(db)
    assert info["size"] == len(db)
    assert struct.unpack_from("<I", db, 4)[0] == 244
    assert [(s["type"], s["list"], s["count"]) for s in info["sections"]] == [(1, "mhlt", 25), (2, "mhlp", 1)]


def test_every_chunk_size_is_consistent():
    db = build(tracks(3))
    # walk tracks: each mhit's total size must land exactly on the next mhit / the next mhsd
    p = 244 + 96 + 92
    for _ in range(3):
        assert db[p:p + 4] == b"mhit"
        hlen, total, nmhod = struct.unpack_from("<III", db, p + 4)
        q = p + hlen
        for _ in range(nmhod):
            assert db[q:q + 4] == b"mhod"
            q += struct.unpack_from("<I", db, q + 8)[0]
        assert q == p + total
        p = q
    assert db[p:p + 4] == b"mhsd"


def test_strings_are_utf16():
    db = build([Track(title="Ishtar ✓", artist="A", album="B", path=":x", size=1, length_ms=1)])
    assert "Ishtar ✓".encode("utf-16-le") in db


def test_playlists():
    db = build(tracks(5), playlists={"Mix": [4, 0], "Empty": []})
    info = parse_counts(db)
    assert info["size"] == len(db)
    assert [(s["type"], s["list"], s["count"]) for s in info["sections"]] == [(1, "mhlt", 5), (2, "mhlp", 3)]
    mix = db.index("Mix".encode("utf-16-le"))
    mhyp = db.rindex(b"mhyp", 0, mix)
    assert db[mhyp + 20] == 0                                    # not hidden: not the master playlist
    assert struct.unpack_from("<I", db, mhyp + 16)[0] == 2
    mhip = db.index(b"mhip", mhyp)
    assert struct.unpack_from("<I", db, mhip + 24)[0] == 1004    # the track ID of tracks[4]
