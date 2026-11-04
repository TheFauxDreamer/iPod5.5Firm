"""Research only: read the result of each drive of make_drives.py in the instrumented emulator.

Usage: python3 re/dark-table-map/proto/measure.py <work folder> [drive ...]

For each drive, the script starts the emulator without a window, waits until ifd2_hash is set, and
reads it with peek. It compares the value with the expected hash. It reads the markers of
mark_start and mark_done in the evlog and gives the time of the apply (instructions and emulated µs).
Then it stops the emulator. Only the emulator of this script stops; the iPodFirm app does not.
"""

import json
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[2] / "src"))
from ipodfw.emucontrol import Emulator                             # noqa: E402

SUPPORT = Path.home() / "Library/Application Support/iPodFirm"
BINARY = SUPPORT / "emulator-src/target/release/ipod-emulator"
MARKER = 0xFFFFFFFD


def peek(emu: Emulator, addr: int) -> int | None:
    r = emu.cmd(f"peek {0x10000000 + addr:x}")
    m = re.search(r"= (0x[0-9a-f]+)", r)
    return int(m.group(1), 16) if m else None


def measure(work: Path, name: str, d: dict) -> dict:
    profile = SUPPORT / d["profile"]
    env = {"IPODFW_MARK_AT": f"{d['mark_start']},{d['mark_done']}", "IPODFW_RESET_AFTER": "1000000000"}
    sock = f"/tmp/ipodfw-ifd2-{os.getuid()}.sock"
    events, value = [], None
    with Emulator(profile, sock=sock, binary=str(BINARY), env=env) as emu:
        emu.wait_running()
        end = time.time() + 600
        while time.time() < end:
            events += emu.evlog()
            value = peek(emu, int(d["ifd2_hash"], 16))
            if value:
                break
            time.sleep(1)
        events += emu.evlog()
        shot = work / f"{name}.png"
        emu.wait_emulated(20)
        emu.shot(shot)
        later = peek(emu, int(d["ifd2_hash"], 16))
    marks = [(n, us, v) for n, us, pc, a, v in events if a == MARKER and v in (0, 1)]
    start = next((m for m in marks if m[2] == 0), None)
    done = next((m for m in marks if m[2] == 1), None)
    return {"hash": hex(value) if value is not None else None, "expected": d["hash"],
            "same": value == int(d["hash"], 16), "hash_after_20_s": hex(later) if later is not None else None,
            "marks": len(marks),
            "instructions": done[0] - start[0] if start and done else None,
            "usec": done[1] - start[1] if start and done else None, "screen": str(shot)}


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    work = Path(sys.argv[1]).resolve()
    drives = json.loads((work / "expected.json").read_text())["drives"]
    names = sys.argv[2:] or list(drives)
    results = {}
    for name in names:
        results[name] = measure(work, name, drives[name])
        print(name, json.dumps(results[name]))
    (work / "results.json").write_text(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
