"""Make an iPod music library (iTunesDB and album thumbnails) from a folder of music files.

The files are read only. For the emulator, the audio is not copied: the lists do not need it.
"""

from __future__ import annotations

import io
import os
import shutil
from pathlib import Path

from PIL import Image

from . import albumart, mp4tags
from .itunesdb import Track, build


def scan(folder: str | Path) -> list[tuple[Path, mp4tags.Tags]]:
    out = []
    for root, _dirs, files in os.walk(folder):
        for name in sorted(files):
            if name.lower().endswith((".m4a", ".mp4")) and not name.startswith("._"):
                p = Path(root) / name
                try:
                    out.append((p, mp4tags.read(str(p))))
                except (OSError, ValueError, IndexError):
                    pass
    return out


def pick(items: list, limit: int, per_album: int) -> list:
    """Select up to `limit` songs: a maximum of `per_album` songs from each album, one album
    from each artist in turn, so that the selection has many albums and artists."""
    albums: dict[tuple[str, str], list] = {}
    for path, t in items:
        albums.setdefault((t.album_artist or t.artist, t.album), []).append((path, t))
    by_artist: dict[str, list] = {}
    for (artist, _album), songs in sorted(albums.items()):
        songs.sort(key=lambda pt: (pt[1].disc, pt[1].track))
        by_artist.setdefault(artist, []).append(songs[:per_album])
    chosen = []
    while len(chosen) < limit and any(by_artist.values()):
        for artist in sorted(by_artist):
            if by_artist[artist] and len(chosen) < limit:
                chosen += by_artist[artist].pop(0)[:limit - len(chosen)]
    return chosen


def make_library(folder: str | Path, out: str | Path, thumb_size: int = albumart.DEFAULT_SIZE,
                 limit: int | None = None, per_album: int = 8, copy_audio: bool = False) -> dict:
    items = scan(folder)
    if limit:
        items = pick(items, limit, per_album)
    out = Path(out)
    (out / "iPod_Control" / "iTunes").mkdir(parents=True, exist_ok=True)
    tracks, covers = [], {}
    for n, (path, t) in enumerate(items):
        album = t.album or "Unknown Album"
        folder_name, file_name = f"F{n % 50:02d}", f"T{n:05d}{path.suffix.lower()}"
        if copy_audio:
            dest = out / "iPod_Control" / "Music" / folder_name
            dest.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, dest / file_name)
        tracks.append(Track(
            title=t.title or path.stem, artist=t.artist or "Unknown Artist", album=album,
            album_artist=t.album_artist, genre=t.genre, year=t.year, track_nr=t.track, tracks=t.tracks,
            disc=t.disc, path=f":iPod_Control:Music:{folder_name}:{file_name}",
            size=path.stat().st_size, length_ms=t.length_ms))
        if t.cover and album not in covers:
            covers[album] = t.cover
    (out / "iPod_Control" / "iTunes" / "iTunesDB").write_bytes(build(tracks))
    images = {}
    for album, data in covers.items():
        try:
            images[album] = Image.open(io.BytesIO(data))
        except OSError:
            pass
    (out / "iPod_Control" / "iTunes" / "iPodFirmAlbumArt").write_bytes(albumart.build(images, thumb_size))
    return {"tracks": len(tracks), "albums": len({t.album for t in tracks}), "covers": len(images)}
