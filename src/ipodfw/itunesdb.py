"""Minimal iTunesDB writer, for putting a test library on an emulated iPod.

Layout follows libgpod's itdb_itunesdb.c writer (mk_mhbd, mk_mhit, mk_mhod,
write_playlist, ...): mhbd → mhsd(1: tracks) → mhlt → mhit + string mhods,
then mhsd(2: playlists) → mhlp → master mhyp with one mhip (+ position mhod)
per track. No library index mhods (52/53); RetailOS builds its own lists.
"""

from __future__ import annotations

import random
import struct
import time
from dataclasses import dataclass

MAC_EPOCH_OFFSET = 2082844800  # seconds between 1904-01-01 and 1970-01-01

MHOD_TITLE, MHOD_PATH, MHOD_ALBUM, MHOD_ARTIST, MHOD_GENRE, MHOD_FILETYPE = 1, 2, 3, 4, 5, 6
MHOD_ALBUMARTIST = 22
MHOD_PLAYLIST = 100


@dataclass
class Track:
    title: str
    artist: str
    album: str
    path: str               # iPod path with colons, e.g. ":iPod_Control:Music:F00:T0001.m4a"
    size: int               # bytes
    length_ms: int
    track_nr: int = 0
    tracks: int = 0
    year: int = 0
    genre: str = ""
    bitrate: int = 128
    samplerate: int = 44100
    filetype: str = "AAC audio file"
    aac: bool = True
    album_artist: str = ""
    disc: int = 0
    dbid: int = 0           # 0: build() makes one
    image_id: int = 0       # the mhii of the artwork in ArtworkDB (0: no artwork)
    artwork_size: int = 0   # bytes of the artwork in the music file


def _mac_now() -> int:
    return (int(time.time()) + MAC_EPOCH_OFFSET) & 0xFFFFFFFF


def _patch_size(buf: bytearray, at: int) -> None:
    """Fill the total-size field (+8) of the chunk that starts at `at`."""
    struct.pack_into("<I", buf, at + 8, len(buf) - at)


def _string_mhod(kind: int, text: str) -> bytes:
    body = text.encode("utf-16-le")
    return (b"mhod" + struct.pack("<III", 24, 40 + len(body), kind) + bytes(8)
            + struct.pack("<IIII", 1, len(body), 1, 0) + body)


def _position_mhod(pos: int) -> bytes:
    return b"mhod" + struct.pack("<III", 24, 44, MHOD_PLAYLIST) + bytes(8) + struct.pack("<I", pos) + bytes(16)


def _mhit(tid: int, t: Track, dbid: int, now: int, mhods: list[bytes]) -> bytes:
    h = bytearray(0x248)
    h[0:4] = b"mhit"
    struct.pack_into("<III", h, 4, 0x248, 0, len(mhods))
    struct.pack_into("<III", h, 0x10, tid, 1, 0x4D344120 if t.aac else 0x4D503320)  # visible, "M4A "/"MP3 "
    h[0x1C] = 0 if t.aac else 1   # type1
    h[0x1D] = 0 if t.aac else 1   # type2
    struct.pack_into("<IIIIIIII", h, 0x20, now, t.size, t.length_ms, t.track_nr, t.tracks, t.year,
                     t.bitrate, t.samplerate << 16)
    struct.pack_into("<I", h, 0x5C, t.disc)
    struct.pack_into("<I", h, 0x68, now)                  # date added
    struct.pack_into("<Q", h, 0x70, dbid)
    h[0x78] = 1                                           # checked
    struct.pack_into("<I", h, 0xD0, 1)                    # media type: audio
    struct.pack_into("<I", h, 0x12C, t.size)
    struct.pack_into("<Q", h, 0x134, 0x808080808080)
    struct.pack_into("<I", h, 0x168, 1)
    if t.image_id:
        struct.pack_into("<H", h, 0x7C, 1)                # artwork count
        struct.pack_into("<I", h, 0x80, t.artwork_size)
        h[0xA4] = 1                                       # has artwork
        struct.pack_into("<I", h, 0x160, t.image_id)      # mhii link
    body = b"".join(mhods)
    struct.pack_into("<I", h, 8, len(h) + len(body))
    return bytes(h) + body


def build(tracks: list[Track], library_name: str = "iPod") -> bytes:
    rnd = random.Random(0x1505)
    now = _mac_now()
    db_id = rnd.getrandbits(64)

    out = bytearray()
    # mhbd
    out += b"mhbd" + struct.pack("<IIII I", 244, 0, 1, 0x13, 2) + struct.pack("<Q", db_id)
    out += struct.pack("<H", 1)                                     # platform: Mac
    out += bytes(244 - len(out))
    struct.pack_into("<H", out, 0x46, int.from_bytes(b"en", "little"))

    # mhsd type 1: tracks
    mhsd1 = len(out)
    out += b"mhsd" + struct.pack("<III", 96, 0, 1) + bytes(80)
    out += b"mhlt" + struct.pack("<II", 92, len(tracks)) + bytes(80)
    for i, t in enumerate(tracks):
        mhods = [_string_mhod(MHOD_TITLE, t.title), _string_mhod(MHOD_ARTIST, t.artist),
                 _string_mhod(MHOD_ALBUM, t.album), _string_mhod(MHOD_FILETYPE, t.filetype),
                 _string_mhod(MHOD_PATH, t.path), _string_mhod(MHOD_ALBUMARTIST, t.artist)]
        if t.genre:
            mhods.append(_string_mhod(MHOD_GENRE, t.genre))
        dbid = rnd.getrandbits(64)
        out += _mhit(1000 + i, t, t.dbid or dbid, now, mhods)
    _patch_size(out, mhsd1)

    # mhsd type 2: playlists (master playlist only)
    mhsd2 = len(out)
    out += b"mhsd" + struct.pack("<III", 96, 0, 2) + bytes(80)
    out += b"mhlp" + struct.pack("<II", 92, 1) + bytes(80)
    mhyp = len(out)
    out += b"mhyp" + struct.pack("<IIII", 108, 0, 2, len(tracks))
    out += bytes([1, 0, 0, 0]) + struct.pack("<I", now) + struct.pack("<Q", rnd.getrandbits(64))
    out += struct.pack("<IHHI", 0, 1, 0, 0) + bytes(60)
    out += _string_mhod(MHOD_TITLE, library_name)
    out += _long_playlist_mhod()
    for pos in range(len(tracks)):
        mhip = len(out)
        out += b"mhip" + struct.pack("<IIIIIIII", 76, 0, 1, 0, 0, 1000 + pos, 0, 0) + bytes(40)
        out += _position_mhod(pos)
        _patch_size(out, mhip)
    _patch_size(out, mhyp)
    _patch_size(out, mhsd2)

    _patch_size(out, 0)
    return bytes(out)


def _long_playlist_mhod() -> bytes:
    """libgpod's mk_long_mhod_id_playlist: column/view settings mhod for the master playlist."""
    words = [0x010084, 5, 9, 3, 0x120001, 0, 0, 0, 0xC80002, 0, 0, 0, 0x3C000D, 0, 0, 0, 0x7D0004, 0, 0, 0,
             0x7D0003, 0, 0, 0, 0x640008, 0, 0, 0, 0x640017, 1, 0, 0, 0x500014, 1, 0, 0, 0x7D0015, 1]
    body = bytes(24) + b"".join(struct.pack("<I", w) for w in words) + bytes(4 * 114)
    return b"mhod" + struct.pack("<III", 0x18, 0x288, MHOD_PLAYLIST) + body


def parse_counts(db: bytes) -> dict:
    """Small reader used by tests and to sanity-check a real iPod's database."""
    if db[:4] != b"mhbd":
        raise ValueError("not an iTunesDB")
    hlen, total, _unk, version, children = struct.unpack_from("<IIIII", db, 4)
    info = {"version": version, "size": total, "sections": []}
    p = hlen
    for _ in range(children):
        if db[p:p + 4] != b"mhsd":
            break
        sh, stotal, stype = struct.unpack_from("<III", db, p + 4)
        child = p + sh
        count = struct.unpack_from("<I", db, child + 8)[0] if db[child:child + 4] in (b"mhlt", b"mhlp", b"mhla", b"mhli") else None
        info["sections"].append({"type": stype, "list": db[child:child + 4].decode(), "count": count})
        p += stotal
    return info


def make_library(outdir, songs: int = 6, total_tracks: int | None = None, seconds: int = 30) -> dict:
    """Write iPod_Control/{Music/F00/*.m4a, iTunes/iTunesDB} under outdir.

    `songs` distinct AAC files (sine tones, encoded with macOS afconvert). `total_tracks` > songs
    simulates a big library: extra tracks reuse those files under their own titles and albums.
    """
    import math
    import os
    import subprocess
    import tempfile
    import wave
    from pathlib import Path

    out = Path(outdir)
    music = out / "iPod_Control" / "Music" / "F00"
    itunes = out / "iPod_Control" / "iTunes"
    music.mkdir(parents=True, exist_ok=True)
    itunes.mkdir(parents=True, exist_ok=True)

    files = []
    with tempfile.TemporaryDirectory() as tmp:
        for i in range(songs):
            wav = Path(tmp) / f"t{i}.wav"
            rate, freq = 44100, 220 * (2 ** (i / 12))
            with wave.open(str(wav), "wb") as w:
                w.setnchannels(2)
                w.setsampwidth(2)
                w.setframerate(rate)
                frames = bytearray()
                for n in range(rate * seconds):
                    v = int(6000 * math.sin(2 * math.pi * freq * n / rate))
                    frames += struct.pack("<hh", v, v)
                w.writeframes(bytes(frames))
            m4a = music / f"T{i:04d}.m4a"
            subprocess.run(["/usr/bin/afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", str(wav), str(m4a)],
                           check=True, capture_output=True)
            files.append(m4a)

    total = max(total_tracks or songs, songs)
    tracks = []
    for n in range(total):
        f = files[n % songs]
        album_no, track_no = divmod(n, 10)
        tracks.append(Track(
            title=f"Test Song {n + 1}", artist=f"Test Artist {album_no // 5 + 1}", album=f"Test Album {album_no + 1}",
            path=":" + ":".join(f.relative_to(out).parts), size=os.path.getsize(f), length_ms=seconds * 1000,
            track_nr=track_no + 1, tracks=10, year=2006, genre="Test"))
    (itunes / "iTunesDB").write_bytes(build(tracks))
    return {"songs": songs, "tracks": total, "path": str(out)}
