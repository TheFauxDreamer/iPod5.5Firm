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
    assert struct.unpack_from("<I", out, hook + 4)[0] == 0xe3510001      # "cmp r1, #1": a release stays a release
    gate = int(report["symbols"]["hook_storage_in_use"], 16)
    assert struct.unpack_from("<I", out, 0x1d871c)[0] == patcher.branch("bl", 0x1d871c, gate)
    base = int(report["code"][0], 16)
    code = out[base:base + report["bytes"]]
    assert struct.pack("<I", 0x1086bedc) in code and struct.pack("<I", 0x1086bf0c) in code   # the slot arrays
    # the album-art patch and this patch use different areas
    with_art, _ = patcher.apply(osos, REPO / "patches/album-art", 0x736800)
    patcher.apply(with_art, REPO / "patches/flash-keep-awake", 0x736800,
                  original_sha256=hashlib.sha256(osos).hexdigest())


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_sleep_now():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/sleep-now", 0x736800)
    item = int(report["symbols"]["hook_sleep_item"], 16)
    power = int(report["symbols"]["hook_power_test"], 16)
    assert struct.unpack_from("<I", out, 0x69fd2c)[0] == item                      # the table entry
    assert struct.unpack_from("<I", out, 0x1e8ce8)[0] == patcher.branch("bl", 0x1e8ce8, item)
    assert struct.unpack_from("<I", out, 0x1ee930)[0] == patcher.branch("bl", 0x1ee930, power)
    # the three code patches use different areas
    original = hashlib.sha256(osos).hexdigest()
    both, _ = patcher.apply(osos, REPO / "patches/album-art", 0x736800)
    both, _ = patcher.apply(both, REPO / "patches/sleep-now", 0x736800, original_sha256=original)
    patcher.apply(both, REPO / "patches/flash-keep-awake", 0x736800, original_sha256=original)
