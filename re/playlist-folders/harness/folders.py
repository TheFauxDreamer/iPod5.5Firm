"""Writes an iPodFirmPlaylistFolders file for the emulator test library (format: playlist_folders.c).

usage: python -I folders.py ITUNESDB OUT [--alpha] "Folder=Playlist,Playlist" ...
"""
import struct
import sys


def playlist_ids(db: bytes) -> dict[str, int]:
    out, i = {}, db.find(b"mhyp")
    while i != -1:
        pid = struct.unpack_from("<Q", db, i + 0x1c)[0]
        j = db.find(b"mhod", i)
        size = struct.unpack_from("<I", db, j + 8)[0]
        n = struct.unpack_from("<I", db, j + 0x1c)[0]
        out[db[j + 0x28:j + 0x28 + n].decode("utf-16-le")] = pid
        i = db.find(b"mhyp", i + 4)
    return out


def build(folders: list[tuple[str, int, list[int]]], alphabetical: bool) -> bytes:
    b = bytearray(b"IFPF" + struct.pack("<HHHH", 1, 1 if alphabetical else 0, len(folders), 0))
    for name, colour, ids in folders:
        text = name.encode("utf-16-le")
        b += struct.pack("<HHHH", colour, len(text) // 2, len(ids), 0) + text + bytes(-len(text) % 4)
        for pid in ids:
            b += struct.pack("<Q", pid)
    return bytes(b)


if __name__ == "__main__":
    db = open(sys.argv[1], "rb").read()
    ids = playlist_ids(db)
    alpha = "--alpha" in sys.argv
    spec = []
    for arg in sys.argv[3:]:
        if arg.startswith("--"):
            continue
        name, _, members = arg.partition("=")
        spec.append((name, 0xf800, [ids[m] for m in members.split(",") if m]))
    open(sys.argv[2], "wb").write(build(spec, alpha))
    print(ids)
