"""Drive siggifly/ipod-emulator through its control socket (`--control=PATH`).

Used for measurements (e.g. Play → Now Playing latency) and scripted UI checks.
Emulated time comes from the instruction counter: at clock=75 the machine runs
75 M instructions per emulated second.
"""

from __future__ import annotations

import os
import re
import socket
import subprocess
import time
from pathlib import Path

EMULATOR = "/Applications/ipod-emulator.app/Contents/MacOS/ipod-emulator"
INSTR_PER_SECOND = 75_000_000


class Emulator:
    def __init__(self, profile: str | Path, sock: str = f"/tmp/ipodfw-ctl-{os.getuid()}.sock",
                 binary: str = EMULATOR, env: dict | None = None):
        self.profile, self.sock, self.binary, self.extra_env = str(profile), sock, binary, env or {}
        self.proc: subprocess.Popen | None = None

    def start(self) -> None:
        if os.path.exists(self.sock):
            os.unlink(self.sock)
        env = dict(os.environ, IPOD_EMULATOR_DATA=self.profile, **self.extra_env)
        self.proc = subprocess.Popen([self.binary, "--headless=100000000000000", f"--control={self.sock}"],
                                     env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            if os.path.exists(self.sock):
                return
            time.sleep(0.1)
        raise RuntimeError("emulator did not open its control socket")

    def stop(self) -> None:
        if self.proc:
            self.proc.terminate()
            self.proc.wait(timeout=10)
            self.proc = None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *exc):
        self.stop()

    def cmd(self, line: str) -> str:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(10)
            s.connect(self.sock)
            s.sendall(line.encode() + b"\n")
            buf = b""
            while b"\n" not in buf:
                chunk = s.recv(65536)
                if not chunk:
                    break
                buf += chunk
            s.sendall(b"quit\n")
        return buf.decode().strip()

    def state(self) -> dict:
        st = self.cmd("state")
        out = {"raw": st, "running": "phase=Running" in st}
        for k in ("executed", "nonblack", "seq", "clicks"):
            m = re.search(rf"{k}=(\d+)", st)
            if m:
                out[k] = int(m.group(1))
        return out

    def executed(self) -> int:
        return self.state().get("executed", 0)

    def wait_running(self, timeout: float = 120) -> None:
        end = time.time() + timeout
        while time.time() < end:
            if self.state()["running"]:
                return
            time.sleep(0.5)
        raise TimeoutError("emulator never reached Running")

    def wait_emulated(self, seconds: float) -> None:
        """Wait until the iPod itself has run for `seconds` (independent of host speed)."""
        target = self.executed() + int(seconds * INSTR_PER_SECOND)
        while self.executed() < target:
            time.sleep(0.05)

    def press(self, name: str) -> None:
        self.cmd(f"press {name}")

    def wheel(self, detents: int) -> None:
        self.cmd(f"wheel {detents}")

    def hist(self) -> dict[int, int]:
        """PC histogram since the last call (64-byte buckets). Needs IPODFW_PROFILE=1 (iPodFirm emulator patch)."""
        r = self.cmd("hist")
        parts = r.split()
        if parts[:2] != ["ok", "hist"]:
            raise RuntimeError(r)
        return {int(a, 16): int(n) for a, n in (p.split(":") for p in parts[3:])}

    def regs(self) -> list[tuple[int, list[int]]]:
        """Registers recorded at IPODFW_REGS_AT since the last call (iPodFirm emulator patch)."""
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(30)
            s.connect(self.sock)
            s.sendall(b"regs\n")
            buf = b""
            while not buf.endswith(b"\nend\n") and not buf.startswith(b"error"):
                chunk = s.recv(1 << 20)
                if not chunk:
                    break
                buf += chunk
            s.sendall(b"quit\n")
        lines = buf.decode().splitlines()
        out = []
        for line in lines[1:]:
            if line == "end":
                break
            if not line.strip():
                continue
            v = [int(x, 16) for x in line.split()]
            out.append((v[0], v[1:]))
        return out

    def shot(self, path: str | Path) -> bytes:
        self.cmd(f"shot {path}")
        return Path(path).read_bytes()
