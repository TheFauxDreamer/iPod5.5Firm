"""Experiment harness: build a patched firmware, make an emulator drive, drive the UI.

usage: SORT=1 uv run python -I emu.py build NAME [patchdir ...]  -> $PF_WORK/NAME/profile
The work folder is $PF_WORK (default /tmp/pf-work). Then run srv.sh NAME or open the window.
"""
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "src"))
from ipodfw import ipsw, patcher, emudrive, itunesdb  # noqa: E402
from ipodfw.partition import FirmwarePartition  # noqa: E402

SUP = Path.home() / "Library/Application Support/iPodFirm"
IPSW = SUP / "Firmware/iPod_25.1.3.ipsw"
TOOLS = SUP / "emulator-src/target/release"
HERE = Path(__file__).resolve().parent
WORK = Path(os.environ.get("PF_WORK", "/tmp/pf-work"))  # never inside the repository


def make_lib(dst: Path, playlists: dict[str, list[int]]):
    src = SUP / "Emulator/TestLibrary/iPod_Control"
    if dst.exists():
        assert dst.is_relative_to(WORK)
        shutil.rmtree(dst)
    shutil.copytree(src / "Music", dst / "iPod_Control/Music")
    files = sorted((dst / "iPod_Control/Music/F00").glob("*.m4a"))
    tracks = []
    for n in range(60):
        f = files[n % len(files)]
        a, t = divmod(n, 10)
        tracks.append(itunesdb.Track(
            title=f"Test Song {n + 1}", artist=f"Test Artist {a // 5 + 1}", album=f"Test Album {a + 1}",
            path=":" + ":".join(f.relative_to(dst).parts), size=os.path.getsize(f), length_ms=30000,
            track_nr=t + 1, tracks=10, year=2006, genre="Test"))
    (dst / "iPod_Control/iTunes").mkdir(parents=True, exist_ok=True)
    db = bytearray(itunesdb.build(tracks, playlists=playlists))
    if SORT is not None:
        i = db.find(b"mhyp")
        while i != -1:
            db[i + 0x2c:i + 0x30] = SORT.to_bytes(4, "little")
            i = db.find(b"mhyp", i + 4)
    (dst / "iPod_Control/iTunes/iTunesDB").write_bytes(bytes(db))


SORT = int(os.environ["SORT"]) if os.environ.get("SORT") else None

PLAYLISTS = {
    "Alpha": list(range(0, 10)), "Bravo": list(range(10, 20)), "Charlie": list(range(20, 30)),
    "Delta": list(range(30, 40)), "Echo": list(range(40, 50)), "Foxtrot": list(range(50, 60)),
}


def build(name: str, patch_dirs: list[str], extra_files: dict[str, bytes] | None = None):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    fname, fw = ipsw.extract_firmware(IPSW)
    part = FirmwarePartition(fw)
    osos = part.image("osos")
    if patch_dirs:
        osos = patcher.apply_all(osos, patch_dirs)
    part.make_room(len(osos))
    part.replace_image("osos", osos)
    custom = out / "custom.ipsw"
    ipsw.repack_ipsw(IPSW, part.to_bytes(), custom)
    prof = out / "profile"
    drive = prof / "drives/ipodfirm-custom.img"
    drive.parent.mkdir(parents=True, exist_ok=True)
    if drive.exists():
        drive.unlink()
    subprocess.run([TOOLS / "ipod-boot", "make-disk", custom, drive], check=True, capture_output=True)
    emudrive.fix_osos_length(str(drive), len(osos))
    lib = WORK / "lib"
    make_lib(lib, PLAYLISTS)
    for rel, data in (extra_files or {}).items():
        p = lib / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_bytes(data)
    subprocess.run([TOOLS / "ipod-boot", "put-files", drive, lib / "iPod_Control", "/iPod_Control"],
                   check=True, capture_output=True)
    snaps = prof / "cache/snapshots"
    if snaps.exists() and snaps.is_relative_to(WORK):
        shutil.rmtree(snaps)
    (prof / "settings.txt").write_text(f"""chassis = white
nor_model = A444
nor_seed = 5500550055005500
disk = {drive}
check_updates_on_start = false
developer = false
welcomed = true
work_on_copy = false
library_seeded = true

res.0.name = iPodFirm test iPod
res.0.kind = firmware
res.0.nor_model = A444
res.0.nor_seed = 5500550055005500

disk.0.name = ipodfirm-custom
disk.0.path = {drive}
disk.0.built_from = iPodFirm custom
disk.0.installed = Apple's software

current = iPodFirm Test

device.0.name = iPodFirm Test
device.0.firmware = iPodFirm test iPod
device.0.disk = {drive}
device.0.chassis = white
device.0.work_on_copy = false
""")
    return prof


if __name__ == "__main__":
    # FOLDERS='--alpha|Road=Charlie,Delta|Zulu=Echo' adds an iPodFirmPlaylistFolders file.
    extra = {}
    if os.environ.get("FOLDERS"):
        import tempfile
        sys.path.insert(0, str(HERE))
        import folders as fmod
        args = os.environ["FOLDERS"].split("|")
        tmp = WORK / "lib-db"
        make_lib(tmp, PLAYLISTS)
        db = (tmp / "iPod_Control/iTunes/iTunesDB").read_bytes()
        ids = fmod.playlist_ids(db)
        colours = [(0xf800, (255, 0, 0)), (0x07e0, (0, 255, 0)), (0x001f, (0, 0, 255)), (0xffe0, (255, 255, 0))]
        named = [a for a in args if "=" in a]
        spec = [(a.split("=")[0], colours[i % 4][0], [ids[m] for m in a.split("=")[1].split(",") if m])
                for i, a in enumerate(named)]
        extra["iPod_Control/iTunes/iPodFirmPlaylistFolders"] = fmod.build(spec, "--alpha" in args)
        if "--art" in args:
            # the colour squares of the folders in the album-art file, as the app writes them
            from PIL import Image
            from ipodfw import albumart
            tiles = {name: Image.new("RGB", (40, 40), colours[i % 4][1]) for i, (name, _, _) in enumerate(spec)}
            extra["iPod_Control/iTunes/iPodFirmAlbumArt"] = albumart.build({}, playlists=tiles)
    if sys.argv[1] == "build":
        print(build(sys.argv[2], sys.argv[3:], extra))
