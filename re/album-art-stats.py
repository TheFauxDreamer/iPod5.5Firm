"""Show the measurement of the album-art patch version 2.5 (record version 4).

Usage: python3 re/album-art-stats.py [path to iPodFirmAlbumArtStats]

Without a path, the script looks for iPod_Control/iTunes/iPodFirmAlbumArtStats on each disk in
/Volumes. The patch writes one record after each 256 album or playlist row draws. The script shows
the change between two records, thus the first pass and the second pass of a scroll are
different lines. It writes no file. The results are in re/album-art-v2.md.
"""

import struct
import sys
from pathlib import Path

# The same order as the enum in patches/album-art/album_art.c.
TIMERS = [
    "album row (all)", "other row (original)", "original, shifted", "original, no thumbnail",
    "build_art", "load", "check_for_new_file", "ithmb fill", "file read", "blit", "draw_runs",
]
COUNTERS = ["art_hits", "art_failed", "file_all_hits", "file_cache_hits", "db_loaded_calls"]
STATE = ["alloc_failed", "art_state", "art_count", "art_slots", "file_state", "file_count",
         "file_size", "file_all", "file_cache", "write_errors", "source", "waits", "ends", "redraws", "prefills"]
WORDS = 4 + 3 * len(TIMERS) + len(COUNTERS) + len(STATE)
MAGIC = 0x54534141                                         # "AAST"
ALLOCATIONS = ["index", "all_pixels", "cache_pixels", "name", "keys", "art", "window",
               "art_pixels", "slot_owner", "art_buffer"]


def find_file() -> Path:
    for volume in sorted(Path("/Volumes").iterdir()):
        path = volume / "iPod_Control" / "iTunes" / "iPodFirmAlbumArtStats"
        if path.is_file():
            return path
    sys.exit("No iPodFirmAlbumArtStats file. Connect the iPod or give the path.")


def records(data: bytes) -> list[dict]:
    """The records of the last session. Each session writes from record 0 again. Thus a record
    of an earlier session can follow. Its time or one of its counts is smaller."""
    out = []
    for offset in range(0, len(data) - WORDS * 4 + 1, WORDS * 4):
        w = struct.unpack_from(f"<{WORDS}I", data, offset)
        if w[0] != MAGIC or w[1] != 4 or w[2] != len(out):
            break
        timers = [w[4 + 3 * i: 7 + 3 * i] for i in range(len(TIMERS))]
        rest = w[4 + 3 * len(TIMERS):]
        if out:
            # A record of an earlier session: in one session, the time and each count only increase.
            last = out[-1]
            counts = [t[0] for t in timers] + list(rest[:len(COUNTERS)])
            before = [t[0] for t in last["timers"]] + list(last["counters"].values())
            if w[3] < last["time"] or any(c < b for c, b in zip(counts, before)):
                break
        out.append({"time": w[3], "timers": timers,
                    "counters": dict(zip(COUNTERS, rest[:len(COUNTERS)])),
                    "state": dict(zip(STATE, rest[len(COUNTERS):]))})
    return out


def main() -> None:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else find_file()
    recs = records(path.read_bytes())
    if not recs:
        sys.exit(f"{path}: no record.")
    print(f"{path}: {len(recs)} records\n")
    last = recs[-1]["state"]
    failed = [n for i, n in enumerate(ALLOCATIONS) if last["alloc_failed"] >> i & 1]
    print("State:", ", ".join(f"{k}={v if v < 0x80000000 else v - (1 << 32)}"
                               for k, v in last.items() if k != "alloc_failed"))
    print("Failed allocations:", ", ".join(failed) or "none")
    print()
    zero = {"time": recs[0]["time"], "timers": [(0, 0, 0)] * len(TIMERS),
            "counters": dict.fromkeys(COUNTERS, 0)}
    for n, (a, b) in enumerate(zip([zero] + recs, recs)):
        seconds = (b["time"] - a["time"]) / 1e6
        print(f"Record {n}: {seconds:.1f} s after the record before")
        for name, (c0, t0, _), (c1, t1, m1) in zip(TIMERS, a["timers"], b["timers"]):
            if c1 > c0:
                print(f"  {name:24} {c1 - c0:6} x  mean {(t1 - t0) / (c1 - c0):8.0f} µs"
                      f"  max (all) {m1:7} µs")
        changes = {k: b["counters"][k] - a["counters"][k] for k in COUNTERS}
        print("  " + (", ".join(f"{k} +{v}" for k, v in changes.items() if v) or "no counter change"))


if __name__ == "__main__":
    main()
