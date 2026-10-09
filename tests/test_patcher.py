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
        patcher.apply(osos, REPO / "patches/album-art", 0x736800, load_address=0x7eb000)
    out, report = patcher.apply(osos, REPO / "patches/album-art", 0x7F0000, load_address=0x7eb000)
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
    assert report["code"][0] == "0x736800"                     # extended: after the end of osos
    assert len(out) % 0x800 == 0 and len(out) > 0x736800
    event = int(report["symbols"]["hook_event"], 16)
    assert struct.unpack_from("<I", out, 0x1d8260)[0] == patcher.branch("bl", 0x1d8260, event)
    assert struct.unpack_from("<I", out, 0x6c8730)[0] == int(report["symbols"]["hook_hub_init"], 16)
    assert struct.unpack_from("<I", out, 0x6c878c)[0] == int(report["symbols"]["hook_storage_init"], 16)
    # with the other code patches: all use different areas and hook sites
    original = hashlib.sha256(osos).hexdigest()
    every = osos
    for name in ("album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "usb-host-probe"):
        every, _ = patcher.apply(every, REPO / "patches" / name, 0x736800, original_sha256=original)
    # after other data (for example a theme and the Dark Mode items to 0x7eb123): the probe goes after it
    filled = osos + bytes(0x7eb123 - len(osos) - 1) + b"\x01"
    out, report = patcher.apply(filled, REPO / "patches/usb-host-probe", 0x736800, original_sha256=original)
    assert report["code"][0] == "0x7eb130"


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_cover_flow():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/cover-flow", 0x736800)
    assert report["code"][0] == "0x736800"                     # extended: after the end of osos
    # three word hooks: the browse-list event slot, the UI handler slot and the damage literal
    for at, old, name in ((0x6772c0, 0x23b704, "hook_list_event"), (0x6701f0, 0x1d81cc, "hook_ui_event"),
                          (0x17ef8c, 0x17ef98, "hook_display_damage")):
        assert struct.unpack_from("<I", osos, at)[0] == old
        assert struct.unpack_from("<I", out, at)[0] == int(report["symbols"][name], 16)
    code = out[0x736800:0x736800 + report["bytes"]]
    assert struct.pack("<I", 0x60005010) in code                    # USEC_TIMER
    # with the other code patches: all use different areas and hook sites
    original = hashlib.sha256(osos).hexdigest()
    every = osos
    for name in ("album-art", "sleep-now", "flash-keep-awake", "flash-wake-on-input", "usb-host-probe", "cover-flow"):
        every, _ = patcher.apply(every, REPO / "patches" / name, 0x736800, original_sha256=original)


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_precompiled_object(tmp_path):
    """A patch folder with patch.o and no C file gives the same bytes as the compiled C file."""
    import shutil
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    src = REPO / "patches/sleep-now"
    folder = tmp_path / "sleep-now"
    folder.mkdir()
    shutil.copy(src / "patch.json", folder)
    (folder / patcher.OBJECT_FILE).write_bytes(patcher.compile_c(sorted(src.glob("*.c")), tmp_path))
    expected, _ = patcher.apply(osos, src, 0x736800)
    out, _ = patcher.apply(osos, folder, 0x736800)
    assert out == expected


def _settings_keys(osos: bytes) -> list[int]:
    """The keys of the items in the Settings menu, through the resource table entry."""
    from ipodfw import resources
    main = resources.main_block(resources.scan(osos))
    r = next(r for r in main.resources if r.type == "Menu" and r.id == patcher.SETTINGS_MENU_ID)
    at = main.abs(r)
    count = struct.unpack_from("<I", osos, at)[0]
    return [struct.unpack_from("<I", osos, at + 4 + 40 * i + 0x1C)[0] for i in range(count)]


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_something_comforting_alone_and_after_dark_mode():
    from ipodfw import darkmode, themeimport
    fw = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1])
    osos = fw.image("osos")
    original = hashlib.sha256(osos).hexdigest()
    patch = REPO / "patches/something-comforting"
    # alone: the chains go to the firmware (word) and to the trampoline of the patch (b)
    out, report = patcher.apply(osos, patch, 0x736800)
    syms = {k: int(v, 16) for k, v in report["symbols"].items()}
    assert struct.unpack_from("<I", out, 0x66c94c)[0] == syms["hook_settings_get"]
    assert struct.unpack_from("<I", out, 0x66c950)[0] == syms["hook_settings_set"]
    assert struct.unpack_from("<I", out, 0x21f254)[0] == patcher.branch("b", 0x21f254, syms["hook_lookup"])
    keys = _settings_keys(out)
    assert keys[keys.index(0x60006088) + 1] == 0x600060E4         # after Clicker
    assert len(out) % 0x800 == 0 and len(out) <= patcher.OSOS_LIMIT
    assert int(report["settings_menu"], 16) >= int(report["code"][1], 16)
    # after the Dark Mode build: both items, and the hooks of this patch call the Dark Mode hooks
    empty = themeimport.Theme("empty", original, original)
    dark, info = darkmode.build(fw, osos, empty, REPO / "patches/dark-mode", original)
    dark_get = struct.unpack_from("<I", dark, 0x66c94c)[0]
    out, report = patcher.apply(dark, patch, 0x736800, original_sha256=original)
    keys = _settings_keys(out)
    assert keys.count(0x600060E0) == 1 and keys.count(0x600060E4) == 1
    assert keys.index(0x600060E4) == keys.index(0x60006088) + 1
    assert dark_get >= patcher.PATCH_AREA_START
    assert int(report["code"][0], 16) >= info["end"]
    # the same patch two times: the Settings item exists already
    with pytest.raises(patcher.PatchError, match="already has an item"):
        patcher.apply(out, patch, 0x736800, original_sha256=original)


def test_chain_target_rules():
    osos = bytearray(0x800)
    struct.pack_into("<I", osos, 0x100, 0x00190B00)
    word = {"kind": "word", "at": "0x100", "expect": "0x00190b00", "chain": "next"}
    assert patcher.chain_target(word, bytes(osos), {}) == 0x190B00
    struct.pack_into("<I", osos, 0x100, 0x7EB010)                 # the hook of an earlier patch
    assert patcher.chain_target(word, bytes(osos), {}) == 0x7EB010
    struct.pack_into("<I", osos, 0x100, 0x123456)                 # something else
    with pytest.raises(patcher.PatchError, match="or the hook of a patch"):
        patcher.chain_target(word, bytes(osos), {})
    b = {"kind": "b", "at": "0x200", "expect": "0xe92d40f8", "chain": "next", "chain_default": "orig"}
    struct.pack_into("<I", osos, 0x200, 0xE92D40F8)
    assert patcher.chain_target(b, bytes(osos), {"orig": 0x7EC000}) == 0x7EC000
    struct.pack_into("<I", osos, 0x200, patcher.branch("b", 0x200, 0x7EB100))
    assert patcher.chain_target(b, bytes(osos), {"orig": 0x7EC000}) == 0x7EB100
