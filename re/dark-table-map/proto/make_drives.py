"""Research only: emulator drives that test the IFD2 decoder on the emulated ARM CPU.

Usage:
    python3 re/dark-table-map/proto/make_drives.py <iPod_25.1.3.ipsw> <work folder>

The script makes a research copy of patches/dark-mode in the work folder. The copy is the same as the
patch, with three additions in hook_lookup:
  - mark_start() and mark_done() before and after the apply of the dark table (for IPODFW_MARK_AT);
  - after both tables, an FNV-1a hash of the bytes hash_lo..hash_hi in the global word ifd2_hash.
The variant "ifd2" calls apply_table2 (the text of decode.c is put before the patch), and the
variant "ifdm" keeps apply_table.

Each build has Dark Gray and the Split layout with both switches ("Switch on iPod"). For the variant
ifd2, the script puts the IFD2 table in the place of the IFDM table. The table comes from the
complete image (the light image in RAM) and from that image with the IFDM tables applied.

Drives (emulator profiles EmulatorProfile-ifd2-*, in the iPodFirm support folder):
    ifdm-dark   IFDM decoder, iPodFirmDarkMode = '1'
    ifd2-dark   IFD2 decoder, iPodFirmDarkMode = '1'
    ifd2-light  IFD2 decoder, no file (light)
    ifd2-stock  IFD2 decoder, iPodFirmDarkMode = '1' and iPodFirmLayout = '0' (both tables)
The script writes expected.json in the work folder: the addresses and the expected hash of each drive.
measure.py reads it.
"""

import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
sys.path.insert(0, str(REPO / "src"))
sys.path.insert(0, str(HERE.parent))
import check                                                       # noqa: E402
import ifd2                                                        # noqa: E402
from ipodfw import darkmode, emudrive, patcher, themeimport        # noqa: E402
from ipodfw.ipsw import repack_ipsw                                # noqa: E402
from ipodfw.partition import FirmwarePartition                     # noqa: E402

SUPPORT = Path.home() / "Library/Application Support/iPodFirm"
TOOL = SUPPORT / "emulator-src/target/release/ipod-boot"
LIBRARY = SUPPORT / "Emulator/TestLibrary/iPod_Control"
PROFILE_PREFIX = "EmulatorProfile-ifd2-"

ADDITIONS = """
/* Research additions (re/dark-table-map/proto/make_drives.py). */
extern const unsigned char hash_lo[], hash_hi[];             /* set by the build */
void apply_table2(const unsigned *t);
unsigned ifd2_hash;                                          /* read with peek */
volatile unsigned ifd2_marks;

__attribute__((noinline)) void mark_start(void) { ifd2_marks = 1; }
__attribute__((noinline)) void mark_done(void) { ifd2_marks = 2; }

static unsigned fnv(const unsigned char *p, const unsigned char *end)
{
    unsigned h = 0x811c9dc5u;
    while (p < end)
        h = (h ^ *p++) * 0x01000193u;
    return h;
}

"""

OLD_APPLY = """        if (dark)
            apply_table(dark_table);
        if (!split)
            apply_table(layout_table);
    }"""

NEW_APPLY = """        mark_start();
        if (dark)
            APPLY(dark_table);
        mark_done();
        if (!split)
            apply_table(layout_table);
        ifd2_hash = fnv(hash_lo, hash_hi);
    }"""


def fnv(b: bytes) -> int:
    h = 0x811C9DC5
    for x in b:
        h = ((h ^ x) * 0x01000193) & 0xFFFFFFFF
    return h


def research_patch(work: Path, variant: str) -> Path:
    d = work / f"patch-{variant}"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir(parents=True)
    src = (REPO / "patches/dark-mode/dark_mode.c").read_text()
    assert src.count(OLD_APPLY) == 1 and src.count("static void apply_table(") == 1
    src = src.replace("static void apply_table(", ADDITIONS + "static void apply_table(")
    src = src.replace(OLD_APPLY, NEW_APPLY.replace("APPLY", "apply_table2" if variant == "ifd2" else "apply_table"))
    if variant == "ifd2":                  # the patcher compiles one C file
        src = (HERE.parent / "decode.c").read_text() + "\n" + src
    (d / "dark_mode.c").write_text(src)
    shutil.copy(REPO / "patches/dark-mode/patch.json", d / "patch.json")
    return d


def build(fw, osos, sha, theme, layout, patch_dir: Path, hash_range):
    """darkmode.build with the extra symbols hash_lo and hash_hi. Returns (image, info, symbols)."""
    original, seen = patcher.apply, {}

    def apply(*a, **k):
        k["symbols"] = {**k.get("symbols", {}), "hash_lo": hash_range[0], "hash_hi": hash_range[1]}
        out, report = original(*a, **k)
        seen.update(report["symbols"])
        return out, report

    patcher.apply = apply
    try:
        out, info = darkmode.build(fw, osos, theme, patch_dir, sha, layout=layout, layout_switch=True)
    finally:
        patcher.apply = original
    return out, info, {k: int(v, 16) for k, v in seen.items()}


def drive(name: str, fw, osos: bytes, work: Path, files: dict[str, bytes]) -> None:
    profile = SUPPORT / f"{PROFILE_PREFIX}{name}"
    assert profile.parent == SUPPORT and profile.name.startswith(PROFILE_PREFIX) and name
    part = FirmwarePartition(fw.to_bytes())
    part.make_room(len(osos))
    part.replace_image("osos", osos)
    custom = work / f"{name}.ipsw"
    repack_ipsw(Path(sys.argv[1]), part.to_bytes(), custom)
    (profile / "drives").mkdir(parents=True, exist_ok=True)
    img = profile / "drives/test.img"
    if img.exists():
        img.unlink()
    subprocess.run([str(TOOL), "make-disk", str(custom), str(img)], check=True, capture_output=True)
    emudrive.fix_osos_length(str(img), len(osos))
    subprocess.run([str(TOOL), "put-files", str(img), str(LIBRARY), "/iPod_Control"], check=True, capture_output=True)
    if files:
        extra = work / f"{name}-files/iPod_Control/iTunes"
        extra.mkdir(parents=True, exist_ok=True)
        for fname, data in files.items():
            (extra / fname).write_bytes(data)
        subprocess.run([str(TOOL), "put-files", str(img), str(extra.parent), "/iPod_Control"], check=True, capture_output=True)
    snaps = profile / "cache/snapshots"
    if snaps.is_dir() and snaps.parent.parent == profile:
        shutil.rmtree(snaps)
    (profile / "settings.txt").write_text(f"""# Written for the IFD2 research ({name}).
chassis = white
nor_model = A444
nor_seed = 5500550055005500
disk = {img}
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
disk.0.path = {img}
disk.0.built_from = iPodFirm custom
disk.0.installed = Apple's software

current = {name}

device.0.name = {name}
device.0.firmware = iPodFirm test iPod
device.0.disk = {img}
device.0.chassis = white
device.0.work_on_copy = false
""")
    print(f"{name}: drive ready")


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    work = Path(sys.argv[2]).resolve()
    work.mkdir(parents=True, exist_ok=True)
    fw, _ = themeimport.load_firmware(sys.argv[1])
    image = themeimport._Image(fw)
    osos, sha = bytes(image.osos), darkmode.stock_sha256(fw)
    theme = themeimport.Theme.from_json((REPO / "themes/Dark Gray.ipodtheme").read_text())
    layout = themeimport.Theme.from_json((REPO / "themes/layouts/Split.ipodtheme").read_text())
    pictures = check.picture_ranges(image)

    # The hash range: all bytes that a table can change. A first build gives the ranges.
    first, info, _ = build(fw, osos, sha, theme, layout, research_patch(work, "ifdm"), (0, 0))
    t = first[info["table"][0]:info["table"][0] + info["table"][1]]
    lt = first[info["layout_table"][0]:info["layout_table"][0] + info["layout_table"][1]]
    r = ifd2.covered_ranges(t) + ifd2.covered_ranges(lt)
    hash_range = (min(a for a, _ in r) & ~3, (max(e for _, e in r) + 3) & ~3)
    assert hash_range[1] <= info["table"][0]
    print(f"hash range 0x{hash_range[0]:x}..0x{hash_range[1]:x}")

    expected = {"hash_range": [hex(a) for a in hash_range], "drives": {}}
    for variant in ("ifdm", "ifd2"):
        out, info, syms = build(fw, osos, sha, theme, layout, research_patch(work, variant), hash_range)
        (at, n), (lat, ln) = info["table"], info["layout_table"]
        ifdm, ltable = out[at:at + n], out[lat:lat + ln]
        light = bytes(out)
        dark = bytearray(light)
        darkmode.apply_switch_table(dark, ifdm)
        stock = bytearray(dark)
        darkmode.apply_switch_table(stock, ltable)
        if variant == "ifd2":
            table, _ = ifd2.encode(light, bytes(dark), pictures)
            assert all(e <= at for _, e in ifd2.covered_ranges(table))
            image2 = bytearray(light)
            image2[at:at + n] = bytes(n)
            image2[at:at + len(table)] = table
            light = bytes(image2)
            for want in (dark, stock):
                want[at:at + n] = image2[at:at + n]
            check_dark = bytearray(light)
            ifd2.decode(check_dark, table)
            assert check_dark == dark, "the Python model does not give the dark image"
            print(f"ifd2: table {len(table):,} bytes in place of {n:,} bytes")
        lo, hi = hash_range
        hashes = {"light": fnv(light[lo:hi]), "dark": fnv(dark[lo:hi]), "stock": fnv(stock[lo:hi])}
        cases = {"ifdm": {"dark": {"iPodFirmDarkMode": b"1"}},
                 "ifd2": {"dark": {"iPodFirmDarkMode": b"1"}, "light": {},
                          "stock": {"iPodFirmDarkMode": b"1", "iPodFirmLayout": b"0"}}}[variant]
        for case, files in cases.items():
            name = f"{variant}-{case}"
            drive(name, fw, light, work, files)
            expected["drives"][name] = {
                "profile": f"{PROFILE_PREFIX}{name}", "hash": hex(hashes[case]),
                "ifd2_hash": hex(syms["ifd2_hash"]), "mark_start": hex(syms["mark_start"]),
                "mark_done": hex(syms["mark_done"]), "table": [hex(at), n]}
    (work / "expected.json").write_text(json.dumps(expected, indent=2))
    print(json.dumps(expected, indent=2))


if __name__ == "__main__":
    main()
