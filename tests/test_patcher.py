"""Tests for the patcher options that the dark-mode build uses (needs IPODFW_IPSW)."""

import hashlib
import os
import struct
from pathlib import Path

import pytest

from ipodfw import patcher
from ipodfw.ipsw import extract_firmware
from ipodfw.partition import FirmwarePartition

REPO = Path(__file__).resolve().parent.parent


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_load_address_and_size_limit():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    with pytest.raises(patcher.PatchError, match="can only grow"):
        patcher.apply(osos, REPO / "patches/row-marker", 0x736800, load_address=0x7eb000)
    out, report = patcher.apply(osos, REPO / "patches/row-marker", 0x7F0000, load_address=0x7eb000)
    assert report["code"][0] == "0x7eb000"
    assert len(out) % 0x800 == 0 and len(out) > 0x7eb000
    assert struct.unpack_from("<I", out, 0x677a14)[0] == int(report["symbols"]["hook_label_draw"], 16)


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_flash_keep_awake():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/flash-keep-awake", 0x736800)
    hook = int(report["symbols"]["hook_keep_awake_time"], 16)
    assert struct.unpack_from("<I", out, 0x284c7c)[0] == patcher.branch("bl", 0x284c7c, hook)
    assert struct.unpack_from("<I", out, hook)[0] == 0xe5941018      # the replaced "ldr r1, [r4, #0x18]"
    assert struct.pack("<I", 1800000) in out[hook:hook + report["bytes"]]
    wake = int(report["symbols"]["hook_after_wake"], 16)
    assert struct.unpack_from("<I", out, 0xb45f4)[0] == patcher.branch("bl", 0xb45f4, wake)
    # the album-art patch and this patch use different areas
    with_art, _ = patcher.apply(osos, REPO / "patches/album-art", 0x736800)
    patcher.apply(with_art, REPO / "patches/flash-keep-awake", 0x736800,
                  original_sha256=hashlib.sha256(osos).hexdigest())
