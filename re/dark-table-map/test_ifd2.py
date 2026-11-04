"""Research only: tests of the "IFD2" encoder (ifd2.py) and decoder (decode.c).

Run: .venv/bin/python -m pytest re/dark-table-map/test_ifd2.py
The tests with firmware 1.3 need IPODFW_IPSW=path/to/iPod_25.1.3.ipsw.

The tests compile decode.c for the Mac with AddressSanitizer and UndefinedBehaviorSanitizer. The
table is in a buffer of its exact size (host_main.c). Thus a read past the end of the table stops
the program with an error.
"""

import os
import random
import struct
import subprocess
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "src"))
sys.path.insert(0, str(HERE))
import ifd2                                                        # noqa: E402

KINDS = ((ifd2.RAW,), (ifd2.RAW, ifd2.MAP), (ifd2.RAW, ifd2.MAP, ifd2.PAL))
SEEDS = range(300)


@pytest.fixture(scope="session")
def host(tmp_path_factory) -> Path:
    exe = tmp_path_factory.mktemp("host") / "host_main"
    subprocess.run(["xcrun", "clang", "-O1", "-g", "-DHOST", "-Wall", "-Werror",
                    "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
                    str(HERE / "decode.c"), str(HERE / "host_main.c"), "-o", str(exe)], check=True)
    return exe


def run_c(host: Path, tmp: Path, light: bytes, table: bytes) -> bytes:
    (tmp / "light").write_bytes(light)
    (tmp / "table").write_bytes(table)
    r = subprocess.run([str(host), str(tmp / "light"), str(tmp / "table"), str(tmp / "out")],
                       capture_output=True, text=True, timeout=60)
    assert r.returncode == 0, r.stderr[-2000:]
    return (tmp / "out").read_bytes()


def ifdm_table(light: bytes, dark: bytes) -> bytes:
    """An "IFDM" table with one entry for each run of changed bytes (as dark-mode 1.2)."""
    runs, data, i = [], bytearray(), 0
    while i < len(light):
        if light[i] == dark[i]:
            i += 1
            continue
        j = i
        while j < len(light) and light[j] != dark[j]:
            j += 1
        runs.append(struct.pack("<II", i, j - i))
        data += bytes(a ^ b for a, b in zip(light[i:j], dark[i:j]))
        i = j
    return struct.pack("<III", ifd2.IFDM, len(runs), 12 + 8 * len(runs)) + b"".join(runs) + bytes(data)


def synthetic(seed: int) -> tuple[bytes, bytes, list[tuple[int, int]]]:
    """A light image, a dark image and the 16-bit picture ranges, with each case that a theme or an
    owner edit can give."""
    rnd = random.Random(seed)
    size = rnd.choice((4096, 30000, 120000))
    light = bytearray(rnd.randbytes(size))
    dark = bytearray(light)
    pictures, at = [], rnd.randrange(0, 64) * 4
    while True:
        at += rnd.choice((0, 0, 4, 12, 100, rnd.randrange(0, 4000))) // 4 * 4  # 0: adjacent pictures
        n = rnd.choice((2, 4, 6, 64, 302, 2000, rnd.randrange(1, 9000) * 2))  # even, not always 4n
        if at + n > size:
            break
        pictures.append((at, at + n))
        at += n
    for a, e in pictures:
        px = (e - a) // 2
        colours = [rnd.randrange(0x10000) for _ in range(rnd.choice((1, 2, 3, 5, 16, 17, 70, 256, 257, 400)))]
        lx = [rnd.choice(colours) for _ in range(px)]
        struct.pack_into(f"<{px}H", light, a, *lx)
        mode = rnd.choice(("same", "map", "map", "map+errors", "many-to-one", "few", "noise", "part"))
        if mode == "same":
            dx = lx
        elif mode in ("map", "map+errors"):
            m = {c: rnd.randrange(0x10000) for c in colours}
            m[colours[0]] = colours[0]                       # one colour does not change
            dx = [m[c] for c in lx]
            if mode == "map+errors":
                for _ in range(rnd.randrange(1, 20)):
                    dx[rnd.randrange(px)] = rnd.randrange(0x10000)
        elif mode == "many-to-one":
            out = [rnd.randrange(0x10000) for _ in range(3)]
            m = {c: rnd.choice(out) for c in colours}
            dx = [m[c] for c in lx]
        elif mode == "few":
            out = [rnd.randrange(0x10000) for _ in range(rnd.choice((1, 2, 4, 15, 16, 200, 256)))]
            dx = [rnd.choice(out) for _ in range(px)]
        elif mode == "noise":
            dx = [rnd.randrange(0x10000) for _ in range(px)]
        else:
            dx = list(lx)
            s = rnd.randrange(px)
            for i in range(s, min(px, s + rnd.randrange(1, 50))):
                dx[i] = rnd.randrange(0x10000)
        struct.pack_into(f"<{px}H", dark, a, *dx)
    # Byte changes outside and across the pictures: Views, Types, odd addresses, edges.
    for _ in range(rnd.randrange(0, 60)):
        if pictures and rnd.random() < 0.4:
            a, e = rnd.choice(pictures)
            s = rnd.choice((a, e)) - rnd.randrange(0, 12)            # across an edge
        else:
            s = rnd.randrange(size)
        s = max(0, s)
        n = rnd.choice((1, 2, 3, 7, 8, 9, 30))
        for i in range(s, min(size, s + n)):
            dark[i] = rnd.randrange(256)
    return bytes(light), bytes(dark), pictures


@pytest.mark.parametrize("seed", SEEDS)
def test_synthetic_tables_give_the_dark_image(seed, host, tmp_path):
    light, dark, pictures = synthetic(seed)
    ifdm = ifdm_table(light, dark)
    for kinds in KINDS:
        table, _ = ifd2.encode(light, dark, pictures, kinds)
        assert len(table) % 4 == 0 and struct.unpack_from("<I", table, 8)[0] == len(table)
        work = bytearray(light)
        ifd2.decode(work, table)
        assert bytes(work) == dark, kinds
        assert run_c(host, tmp_path, light, table) == dark, kinds
        assert len(ifd2.choose(table, ifdm)) <= len(ifdm)


def test_the_encoder_refuses_overlapping_pictures():
    light = bytes(64)
    with pytest.raises(ValueError):
        ifd2.encode(light, b"\1" * 64, [(0, 32), (16, 48)])


def test_a_run_across_a_picture_edge_keeps_the_bytes_outside():
    light = bytearray(range(64))
    dark = bytearray(light)
    dark[14:20] = b"ABCDEF"                                   # 2 bytes before the picture at 16
    table, _ = ifd2.encode(bytes(light), bytes(dark), [(16, 32)])
    work = bytearray(light)
    ifd2.decode(work, table)
    assert work == dark


@pytest.mark.parametrize("seed", range(200))
def test_a_corrupted_table_is_not_read_past_its_size(seed, host, tmp_path):
    rnd = random.Random(1000 + seed)
    light, dark, pictures = synthetic(seed)
    table = bytearray(ifd2.encode(light, dark, pictures)[0])
    how = rnd.choice(("cut", "bytes", "count", "size"))
    if how == "cut":
        table = table[:max(12, rnd.randrange(len(table)))]
    elif how == "bytes":
        for _ in range(rnd.randrange(1, 8)):
            table[rnd.randrange(12, len(table))] = rnd.randrange(256)
    elif how == "count":
        struct.pack_into("<I", table, 4, rnd.choice((0xFFFFFFFF, 0x7FFFFFFF, rnd.randrange(1 << 20))))
    # The build writes the size in the header. The decoder must not read past t + size.
    struct.pack_into("<I", table, 8, len(table))
    if how == "size":
        struct.pack_into("<I", table, 8, rnd.choice((0, 11, 12, 13, len(table) - 1, len(table) - rnd.randrange(1, 64))))
    run_c(host, tmp_path, light, bytes(table))          # AddressSanitizer stops a bad read


def _firmware():
    ipsw = os.environ.get("IPODFW_IPSW")
    if not ipsw:
        pytest.skip("set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
    from ipodfw import themeimport
    import check
    fw, _ = themeimport.load_firmware(ipsw)
    image = themeimport._Image(fw)
    return fw, image, check.picture_ranges(image)


@pytest.mark.parametrize("layout_switch", (False, True))
def test_dark_gray_from_the_complete_build(layout_switch, host, tmp_path):
    """The table from the image that the iPod has in RAM at the start: the complete "Switch on iPod"
    build (dark-mode 1.2), with the IFDM table applied as the dark image."""
    from ipodfw import darkmode, themeimport
    fw, image, pictures = _firmware()
    osos = bytes(image.osos)
    theme = themeimport.Theme.from_json((REPO / "themes/Dark Gray.ipodtheme").read_text())
    layout = themeimport.Theme.from_json((REPO / "themes/layouts/Split.ipodtheme").read_text()) if layout_switch else None
    out, info = darkmode.build(fw, osos, theme, REPO / "patches/dark-mode", darkmode.stock_sha256(fw),
                               layout=layout, layout_switch=layout_switch)
    at, n = info["table"]
    dark = bytearray(out)
    darkmode.apply_switch_table(dark, out[at:at + n])
    table, _ = ifd2.encode(out, bytes(dark), pictures)
    work = bytearray(out)
    ifd2.decode(work, table)
    assert work == dark
    assert run_c(host, tmp_path, out, table) == dark
    assert len(table) < n // 9


def test_firmware_pictures_do_not_overlap():
    _, _, pictures = _firmware()
    for (a, e), (b, _) in zip(pictures, pictures[1:]):
        assert e <= b
