"""usage: python drive.py NAME step step ...
steps: w:SECONDS (emulated), p:BUTTON, r:DETENTS (wheel), s:LABEL (shot), regs, peek:ADDR:N
The emulator stays up between runs in a 'server' mode only if KEEP=1 (then use cmd.py)."""
import os
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / "src"))
from ipodfw.emucontrol import Emulator  # noqa: E402

HERE = Path(__file__).resolve().parent
WORK = Path(os.environ.get("PF_WORK", "/tmp/pf-work"))
BIN = str(Path.home() / "Library/Application Support/iPodFirm/emulator-src/target/release/ipod-emulator")


def run(name, steps, env=None):
    prof = WORK / name / "profile"
    shots = WORK / name / "shots"
    shots.mkdir(exist_ok=True)
    e = Emulator(prof, sock=f"/tmp/pf-{os.getuid()}.sock", binary=BIN,
                 env=dict({"IPODFW_RESET_AFTER": "1000000000"}, **(env or {})))
    e.start()
    try:
        e.wait_running(180)
        for st in steps:
            k, _, v = st.partition(":")
            if k == "w":
                e.wait_emulated(float(v))
            elif k == "p":
                e.press(v)
                e.wait_emulated(0.6)
            elif k == "r":
                e.wheel(int(v))
                e.wait_emulated(0.6)
            elif k == "s":
                e.shot(shots / f"{v}.png")
                print("shot", shots / f"{v}.png")
            elif k == "regs":
                for pc, r in e.regs():
                    print(hex(pc), " ".join("%08x" % x for x in r))
            elif k == "c":
                print(e.cmd(v.replace("_", " ")))
    finally:
        e.stop()


if __name__ == "__main__":
    run(sys.argv[1], sys.argv[2:])
