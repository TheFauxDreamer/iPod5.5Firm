"""Tests for the ArtworkDB writer and the artwork fields of the tracks."""

import struct

from PIL import Image

from ipodfw import artworkdb, itunesdb


def items():
    return [artworkdb.Artwork(0x1000_0000_0000 + n, Image.new("RGB", (300, 300), (40 * n, 0, 255)), 1000 + n)
            for n in range(3)]


def test_round_trip():
    arts = items()
    db, ithmb = artworkdb.build(arts)
    assert [a.image_id for a in arts] == [100, 101, 102]
    assert len(ithmb["F1028_1.ithmb"]) == 3 * 100 * 100 * 2
    assert len(ithmb["F1029_1.ithmb"]) == 3 * 200 * 200 * 2
    images = artworkdb.parse(db)
    assert [i["image_id"] for i in images] == [100, 101, 102]
    assert [i["dbid"] for i in images] == [a.track_dbid for a in arts]
    t = images[2]["thumbs"]
    assert t[0] == {"format": 1028, "offset": 2 * 20000, "size": 20000, "width": 100, "height": 100, "file": ":F1028_1.ithmb"}
    assert t[1]["format"] == 1029 and t[1]["offset"] == 2 * 80000
    assert struct.unpack_from("<I", db, 8)[0] == len(db)                       # total length
    assert struct.unpack_from("<I", db, 0x1C)[0] == 103                        # next ID


def test_track_artwork_fields():
    t = itunesdb.Track("T", "A", "B", ":iPod_Control:Music:F00:T0.m4a", 100, 1000,
                       dbid=0x1234, image_id=100, artwork_size=5555)
    db = itunesdb.build([t])
    mhit = db.index(b"mhit")
    assert struct.unpack_from("<Q", db, mhit + 0x70)[0] == 0x1234
    assert struct.unpack_from("<H", db, mhit + 0x7C)[0] == 1
    assert struct.unpack_from("<I", db, mhit + 0x80)[0] == 5555
    assert db[mhit + 0xA4] == 1
    assert struct.unpack_from("<I", db, mhit + 0x160)[0] == 100
