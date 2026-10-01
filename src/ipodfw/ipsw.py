"""Extract the firmware partition image from an Apple iPod .ipsw (a zip)."""

from __future__ import annotations

import plistlib
import zipfile
from pathlib import Path

from .partition import FirmwareError


def extract_firmware(ipsw_path: str | Path) -> tuple[str, bytes]:
    """Return (name, bytes) of the Firmware-* payload inside an iPod ipsw."""
    with zipfile.ZipFile(ipsw_path) as z:
        names = z.namelist()
        name = None
        if "manifest.plist" in names:
            manifest = plistlib.loads(z.read("manifest.plist"))
            name = manifest.get("FirmwarePayload", {}).get("FirmwareName")
        if name not in names:
            candidates = [n for n in names if n.startswith("Firmware-")]
            if len(candidates) != 1:
                raise FirmwareError(f"cannot find the firmware payload in {ipsw_path}: {names}")
            name = candidates[0]
        return name, z.read(name)


def repack_ipsw(original_ipsw: str | Path, firmware: bytes, output: str | Path) -> str:
    """Copy an ipsw, swapping in a customised firmware payload (for emulators / restores)."""
    name, _ = extract_firmware(original_ipsw)
    with zipfile.ZipFile(original_ipsw) as src, zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as dst:
        for info in src.infolist():
            dst.writestr(info, firmware if info.filename == name else src.read(info.filename))
    return name
