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
    # below the extended area, max_size is the limit
    with pytest.raises(patcher.PatchError, match="can only grow"):
        patcher.apply(osos, REPO / "patches/row-marker", 0x736800, load_address=0x7e0000)
    out, report = patcher.apply(osos, REPO / "patches/row-marker", 0x7E8000, load_address=0x7e0000)
    assert report["code"][0] == "0x7e0000"
    assert len(out) % 0x800 == 0 and len(out) > 0x7e0000
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
    off = int(report["symbols"]["hook_drive_power_off"], 16)
    assert struct.unpack_from("<I", out, 0x23344c)[0] == patcher.branch("bl", 0x23344c, off)
    assert out[0x1d8344:0x1d8348] == osos[0x1d8344:0x1d8348]     # the input wake is flash-wake-on-input
    base = int(report["code"][0], 16)
    code = out[base:base + report["bytes"]]
    assert struct.pack("<I", 0x1086bedc) in code and struct.pack("<I", 0x1086bf0c) in code   # the slot arrays
    # the album-art patch and this patch use different areas
    with_art, _ = patcher.apply(osos, REPO / "patches/album-art", 0x736800)
    patcher.apply(with_art, REPO / "patches/flash-keep-awake", 0x736800,
                  original_sha256=hashlib.sha256(osos).hexdigest())


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_flash_wake_on_input():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    sha = hashlib.sha256(osos).hexdigest()
    out, report = patcher.apply(osos, REPO / "patches/flash-wake-on-input", 0x736800)
    hook = int(report["symbols"]["hook_user_event"], 16)
    assert struct.unpack_from("<I", out, 0x1d8344)[0] == patcher.branch("bl", 0x1d8344, hook)
    code = out[hook:hook + report["bytes"]]
    assert struct.pack("<I", 0x60005010) in code                    # USEC_TIMER
    # all the flash and art patches together: different areas, below the end of the patch area
    for name in ("album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input"):
        osos, report = patcher.apply(osos, REPO / "patches" / name, 0x736800, original_sha256=sha)
    assert int(report["code"][1], 16) <= 0x736800


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


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_backlight_60s():
    from ipodfw import resources
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/backlight-60s", 0x736800)
    assert len(out) == len(osos) and report["bytes"] == 0                         # data only, no code
    blocks = resources.scan(out)
    text = {k: v for k, v in resources.read_strings(out, blocks[24]).items()}
    menu = 0x4b069c + 4                                                           # Menu -138, 40 bytes an item
    items = [(text[str(struct.unpack_from("<h", out, menu + 40 * k + 24)[0])],
              struct.unpack_from("<H", out, menu + 40 * k + 28)[0]) for k in range(7)]
    assert items == [("Off", 0x6032), ("5 Seconds", 0x6035), ("10 Seconds", 0x6036), ("15 Seconds", 0x6037),
                     ("20 Seconds", 0x6038), ("60 Seconds", 0x6039), ("Always On", 0x603a)]
    assert out[0x4baa75:0x4baa78] == bytes.fromhex("58003c")                     # the script pushes 60
    assert resources.read_strings(out, blocks[3])["-140"] == "60 Sekunden"
    # a firmware with other bytes is refused
    bad = bytearray(osos)
    bad[0x4baa76] = 0
    with pytest.raises(patcher.PatchError, match="0x4baa76"):
        patcher.apply(bytes(bad), REPO / "patches/backlight-60s", 0x736800,
                      original_sha256=hashlib.sha256(osos).hexdigest())
    # with the code patches
    original = hashlib.sha256(osos).hexdigest()
    both, _ = patcher.apply(osos, REPO / "patches/sleep-now", 0x736800)
    patcher.apply(both, REPO / "patches/backlight-60s", 0x736800, original_sha256=original)


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_usb_host_probe_extended_area():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/usb-host-probe", 0x736800)
    assert report["code"][0] == "0x7e8000"                     # the extended area
    assert len(out) % 0x800 == 0 and len(out) > patcher.EXTENDED_AREA[0]
    event = int(report["symbols"]["hook_event"], 16)
    assert struct.unpack_from("<I", out, 0x1d8260)[0] == patcher.branch("bl", 0x1d8260, event)
    assert struct.unpack_from("<I", out, 0x6c8730)[0] == int(report["symbols"]["hook_hub_init"], 16)
    assert struct.unpack_from("<I", out, 0x6c878c)[0] == int(report["symbols"]["hook_storage_init"], 16)
    # with the other code patches: all use different areas and hook sites
    original = hashlib.sha256(osos).hexdigest()
    every = osos
    for name in ("album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "usb-host-probe"):
        every, _ = patcher.apply(every, REPO / "patches" / name, 0x736800, original_sha256=original)
