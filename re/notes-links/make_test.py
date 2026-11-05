"""Make an emulator drive to test the Notes music links (stock firmware, no patches).

usage: SORT=1 uv run python -I re/notes-links/make_test.py
The profile goes to $PF_WORK/notes-links/profile (default /tmp/pf-work). Refer to re/notes-links.md.
"""
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "playlist-folders/harness"))
import emu  # noqa: E402

PROLOG = '<?xml version="1.0" encoding="UTF-8"?>\n'


def note(title: str, links: list[tuple[str, str]], meta: str = "") -> bytes:
    """A link note. The href is written as it is, so that each case controls its own escapes."""
    lines = [f"<title>{title}</title>"] + ([meta] if meta else [])
    lines += [f'<a href="{href}">{label}</a>' for label, href in links]
    return (PROLOG + "\n".join(lines) + "\n").encode()


M = "ipod:music?"
CASES = [
    ("01 playlist", M + "playlist=Alpha"),
    ("02 nowplaying=false", M + "playlist=Alpha&nowplaying=false"),
    ("03 song 3", M + "playlist=Alpha&song=Test Song 3"),
    ("04 song 3 nowplaying=false", M + "playlist=Alpha&song=Test Song 3&nowplaying=false"),
    ("05 nopush", M + "playlist=Alpha&nopush"),
    ("06 popall", M + "playlist=Alpha&popall"),
    ("07 song only", M + "song=Test Song 3"),
    ("08 R&amp;B as &amp;amp;", M + "playlist=R&amp;B"),
    ("09 R&amp;B as %26", M + "playlist=R%26B"),
    ("10 separator &amp;amp;", M + "playlist=Alpha&amp;song=Test Song 3"),
    ("11 Alpha songs", "Alpha.linx"),
    ("12 Alpha songs, no Now Playing", "AlphaNP.linx"),
    ("13 meta NowPlaying false", "Meta.linx"),
]

ALPHA = [(f"Test Song {n}", M + f"playlist=Alpha&song=Test Song {n}") for n in range(1, 11)]
FILES = {
    "index.linx": note("Link Test", CASES),
    "Alpha.linx": note("Alpha", ALPHA),
    "AlphaNP.linx": note("Alpha", [(t, h + "&nowplaying=false") for t, h in ALPHA]),
    "Meta.linx": note("Meta", [("Alpha", M + "playlist=Alpha")], '<meta name="NowPlaying" content="false">'),
}

if __name__ == "__main__":
    emu.PLAYLISTS["R&B"] = list(range(0, 5))
    prof = emu.build("notes-links", [])
    notes = emu.WORK / "notes-links/Notes"
    notes.mkdir(parents=True, exist_ok=True)
    for name, data in FILES.items():
        (notes / name).write_bytes(data)
    subprocess.run([emu.TOOLS / "ipod-boot", "put-files", prof / "drives/ipodfirm-custom.img", notes, "/Notes"],
                   check=True, capture_output=True)
    print(prof)
