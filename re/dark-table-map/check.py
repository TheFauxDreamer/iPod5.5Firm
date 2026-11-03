"""Research only: measure and check the "IFD2" dark switch table (ifd2.py, decode.c).

Usage: python3 re/dark-table-map/check.py <iPod_25.1.3.ipsw> <theme.ipodtheme>

The script does these steps. It writes files only in a temporary folder, which it removes.
1. It makes the light osos and the dark osos (apply_theme), with and without the highlight rule for
   a part word (_keep_highlight_words).
2. It makes the table of dark-mode 1.2 (XOR) and the IFD2 table with RAW only, RAW + MAP and
   RAW + MAP + PAL. It gives the size of each table.
3. It applies each IFD2 table with the Python model and with decode.c compiled for the Mac. Both
   results must be the same as the dark osos.
4. It compiles decode.c with the flags of the patches and gives the code size of each decoder.
5. It gives the counts of the decoder work for the start time.
The results are in re/dark-mode-compression.md.
"""

import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "src"))
sys.path.insert(0, str(HERE))
import ifd2                                                        # noqa: E402
from ipodfw import darkmode, pictures, themeimport                 # noqa: E402

# The flags of Patcher.clangFlags (mac/Sources/IPodFWKit/Patcher.swift).
ARM_FLAGS = ["--target=armv4t-none-eabi", "-mcpu=arm7tdmi", "-marm", "-mfloat-abi=soft", "-O2",
             "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-exceptions", "-fno-unwind-tables",
             "-fno-asynchronous-unwind-tables", "-fno-stack-protector", "-ffunction-sections",
             "-fdata-sections", "-nostdlib", "-Wall", "-Werror", "-c"]


def picture_ranges(image) -> list[tuple[int, int]]:
    """The pixel data (start, end) of each 16-bit picture in osos."""
    out = set()
    for key, res in image.res.items():
        if key[1] != "BMap":
            continue
        pos = image.pos(key)
        pic = pictures.parse(image.osos, pos)
        if pic and pic.depth == 16:
            out.add((pic.data_pos, pic.data_pos + pic.bytes_per_row * pic.height))
    return sorted(out)


def dark_osos(theme, osos: bytes, rule: bool) -> bytes:
    keep = themeimport._keep_highlight_words
    if not rule:
        themeimport._keep_highlight_words = lambda c, osos: c
    try:
        dark = bytearray(osos)
        themeimport.apply_theme(theme, dark, theme.osos_sha256)
        table, _ = darkmode.switch_table(theme, osos)
    finally:
        themeimport._keep_highlight_words = keep
    return bytes(dark[:len(osos)]), table


def code_sizes(tmp: Path) -> dict[str, int]:
    obj = tmp / "decode.o"
    subprocess.run(["xcrun", "clang", *ARM_FLAGS, str(HERE / "decode.c"), "-o", str(obj)], check=True)
    out = subprocess.run(["xcrun", "llvm-objdump", "-h", str(obj)], check=True, capture_output=True, text=True).stdout
    sizes = {}
    for line in out.splitlines():
        m = re.match(r"\s*\d+\s+(\S+)\s+([0-9a-f]+)\s", line)
        if m and m.group(1).startswith(".text."):
            sizes[m.group(1)[6:]] = int(m.group(2), 16)
    undefined = subprocess.run(["xcrun", "llvm-nm", "-u", str(obj)], check=True, capture_output=True, text=True).stdout.split()
    if undefined:
        raise SystemExit(f"decode.c calls functions that the patch does not have: {undefined}")
    return sizes


def c_result(tmp: Path, light: bytes, table: bytes) -> bytes:
    exe = tmp / "host_main"
    if not exe.exists():
        subprocess.run(["xcrun", "clang", "-O2", "-DHOST", "-Wall", "-Werror", str(HERE / "decode.c"),
                        str(HERE / "host_main.c"), "-o", str(exe)], check=True)
    (tmp / "light").write_bytes(light)
    (tmp / "table").write_bytes(table)
    subprocess.run([str(exe), str(tmp / "light"), str(tmp / "table"), str(tmp / "out")], check=True)
    return (tmp / "out").read_bytes()


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    fw, _ = themeimport.load_firmware(sys.argv[1])
    image = themeimport._Image(fw)
    osos = bytes(image.osos)
    theme = themeimport.Theme.from_json(Path(sys.argv[2]).read_text())
    ranges = picture_ranges(image)
    print(f"Theme {theme.name}: {len(ranges)} pictures of 16 bits in osos")
    with tempfile.TemporaryDirectory(prefix="ifd2-") as name:
        tmp = Path(name)
        for rule in (False, True):
            dark, xor = dark_osos(theme, osos, rule)
            changed = sum(1 for a, b in zip(osos, dark) if a != b)
            print(f"\nHighlight rule for a part word: {'on' if rule else 'off'}. Changed bytes in osos: {changed:,}")
            print(f"  dark-mode 1.2 (XOR)  {len(xor):>9,} bytes")
            for label, kinds in (("RAW only", (ifd2.RAW,)), ("RAW + MAP", (ifd2.RAW, ifd2.MAP)),
                                 ("RAW + MAP + PAL", (ifd2.RAW, ifd2.MAP, ifd2.PAL))):
                table, st = ifd2.encode(osos, dark, ranges, kinds)
                work = bytearray(osos)
                ifd2.decode(work, table)
                same_py = bytes(work) == dark
                same_c = c_result(tmp, osos, table) == dark
                print(f"  {label:20} {len(table):>9,} bytes, {struct.unpack_from('<I', table, 4)[0]:>5} records, "
                      f"Python model {'OK' if same_py else 'WRONG'}, C decoder {'OK' if same_c else 'WRONG'}")
                if not (same_py and same_c):
                    raise SystemExit("A decoder does not give the dark osos.")
                names = {ifd2.RAW: "RAW", ifd2.MAP: "MAP", ifd2.PAL: "PAL"}
                print("    pictures: " + ", ".join(f"{names[k]} {st.pictures[k]} ({st.picture_bytes[k]:,} bytes)"
                                                 for k in sorted(st.pictures)))
                print(f"    other RAW records: {st.other_runs} ({st.other_bytes:,} bytes)")
                print(f"    work: RAW copies {st.raw_bytes:,} bytes, MAP {st.map_pixels:,} pixels "
                      f"({st.map_misses:,} searches, {st.map_steps:,} search steps), PAL {st.pal_pixels:,} pixels")
            print(f"  work of dark-mode 1.2: XOR of {len(xor) - 12 - 8 * struct.unpack_from('<I', xor, 4)[0]:,} bytes")
        print("\nCode size (ARM, the flags of the patches):")
        for fn, size in code_sizes(tmp).items():
            print(f"  {fn:14} {size:>5} bytes")


if __name__ == "__main__":
    main()
