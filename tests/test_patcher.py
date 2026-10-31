"""Tests for the patcher options that the dark-mode build uses (needs IPODFW_IPSW)."""

import hashlib
import json
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
def test_playback_log_hooks():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/playback-log", 0x7f8000)
    assert report["code"][0] == "0x736800"                     # extended: after the end of osos
    for h in json.loads((REPO / "patches/playback-log/patch.json").read_text())["hooks"]:
        at, target = int(h["at"], 16), int(report["symbols"][h["to"]], 16)
        assert struct.unpack_from("<I", out, at)[0] == patcher.branch(h["kind"], at, target)
    # alone, each chain wrapper runs the replaced push and continues after it
    start = int(report["symbols"]["start_original"], 16)
    assert struct.unpack_from("<I", out, start)[0] == 0xe92d4038
    assert struct.unpack_from("<I", out, start + 4)[0] == patcher.branch("b", start + 4, 0xb40c8)


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_diagnostic_log_hooks():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/diagnostic-log", 0x7f8000)
    for h in json.loads((REPO / "patches/diagnostic-log/patch.json").read_text())["hooks"]:
        at, target = int(h["at"], 16), int(report["symbols"][h["to"]], 16)
        assert struct.unpack_from("<I", osos, at)[0] == int(h["expect"], 16)
        want = target if h["kind"] == "word" else patcher.branch(h["kind"], at, target)
        assert struct.unpack_from("<I", out, at)[0] == want
    for name, word, resume in (("drive_original", 0xe92d4ff8, 0x265ccc), ("file_open_original", 0xe92d41fc, 0x8f390),
                               ("file_read_original", 0xe92d4ff8, 0x8f468)):
        wrapper = int(report["symbols"][name], 16)
        assert struct.unpack_from("<I", out, wrapper)[0] == word
        assert struct.unpack_from("<I", out, wrapper + 4)[0] == patcher.branch("b", wrapper + 4, resume)


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


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_patch_option():
    """The up-next option "hold": the patcher writes the value into hold_default."""
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    standard, report = patcher.apply(osos, REPO / "patches/up-next", 0x736800)
    nxt, _ = patcher.apply(osos, REPO / "patches/up-next", 0x736800, options={"hold": 1})
    at = int(report["symbols"]["hold_default"], 16)
    assert struct.unpack_from("<I", standard, at)[0] == 3
    assert struct.unpack_from("<I", nxt, at)[0] == 1
    assert [i for i in range(len(nxt)) if nxt[i] != standard[i]] == [at]
    with pytest.raises(patcher.PatchError, match="no choice"):
        patcher.apply(osos, REPO / "patches/up-next", 0x736800, options={"hold": 7})


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
@pytest.mark.parametrize("name,symbol", [("flash-keep-awake", "keep_awake_ms"), ("flash-wake-on-input", "wake_ms")])
def test_storage_time_option(name, symbol):
    """The option "time": the patcher writes the selected time into the variable of each flash patch."""
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    standard, report = patcher.apply(osos, REPO / "patches" / name, 0x736800)
    short, _ = patcher.apply(osos, REPO / "patches" / name, 0x736800, options={"time": 60000})
    at = int(report["symbols"][symbol], 16)
    assert struct.unpack_from("<I", standard, at)[0] == 1800000
    assert struct.unpack_from("<I", short, at)[0] == 60000
    assert all(at <= i < at + 4 for i in range(len(short)) if short[i] != standard[i])
    with pytest.raises(patcher.PatchError, match="no choice"):
        patcher.apply(osos, REPO / "patches" / name, 0x736800, options={"time": 7})


def test_insert_menu_item():
    def item(label: int, target: int) -> bytes:
        i = bytearray(40)
        struct.pack_into("<H", i, 0x18, label)
        struct.pack_into("<I", i, 0x0C, target)
        struct.pack_into("<H", i, 0x20, label)
        return bytes(i)
    menu = struct.pack("<I", 3) + item(0xFF83, 0x40B2) + item(0xFF82, 0x41A2) + item(0xFF81, 0x415A)
    out = patcher.insert_menu_item(menu, 0x7E03, 0xFF82, 0xFF82)
    labels = [struct.unpack_from("<H", out, 4 + 40 * i + 0x18)[0] for i in range(4)]
    assert labels == [0xFF83, 0xFF82, 0x7E03, 0xFF81]
    assert struct.unpack_from("<I", out, 4 + 80 + 0x0C)[0] == 0x41A2       # the action of the template
    assert struct.unpack_from("<H", out, 4 + 80 + 0x20)[0] == 0x7E03
    keyed = patcher.insert_menu_item(menu, 0x7E04, 0xFF82, None, key=0x60007E05)
    assert struct.unpack_from("<I", keyed, 4 + 120 + 0x1C)[0] == 0x60007E05
    with pytest.raises(patcher.PatchError, match="already has an item"):
        patcher.insert_menu_item(out, 0x7E03, 0xFF82, None)
    with pytest.raises(patcher.PatchError, match="no item with the label"):
        patcher.insert_menu_item(menu, 0x7E03, 0x1111, None)


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_album_artists_menu_item():
    from ipodfw import resources
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/album-artists", 0x736800)
    main = resources.main_block(resources.scan(out))

    def labels(menu_id):
        r = next(r for r in main.resources if r.type == "Menu" and r.id == menu_id)
        at = main.abs(r)
        return at, [struct.unpack_from("<H", out, at + 4 + 40 * i + 0x18)[0] for i in range(struct.unpack_from("<I", out, at)[0])]
    at, music = labels(24440)
    assert hex(at) == report["menus"][0] and at >= int(report["code"][1], 16)
    assert len(music) == 11 and music[music.index(0xFF82) + 1] == 0x7E03
    _, root = labels(24094)
    assert len(root) == 32 and root[root.index(0x5F7C) + 1] == 0x7E03
    at, rows = labels(24600)
    assert len(rows) == 29 and rows[rows.index(0xFF5E) + 1] == 0x7E04
    assert struct.unpack_from("<I", out, at + 4 + 40 * (rows.index(0xFF5E) + 1) + 0x1C)[0] == 0x60007E05
    assert report["bytes"] == json.loads((REPO / "patches/album-artists/patch.json").read_text())["size"]
    assert len(out) % 0x800 == 0


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_apply_all_packs_the_patches():
    """The patches follow each other without a 0x800 gap: each one starts after the code, the
    variables and the menus of the patch before it. Only the result is a multiple of 0x800."""
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    names = ["album-art", "album-artists", "cover-flow", "instant-save", "something-comforting", "usb-host-probe"]
    out = patcher.apply_all(osos, [REPO / "patches" / n for n in names])
    assert len(out) % 0x800 == 0
    sizes = sum(json.loads((REPO / "patches" / n / "patch.json").read_text())["size"] for n in names)
    menus = (4 + 40 * 11) + (4 + 40 * 32) + (4 + 40 * 29) + (4 + 40 * 19)
    assert len(out) - patcher.PATCH_AREA_END < sizes + menus + len(names) * 16 + 0x800
    # one patch alone is still rounded
    alone, _ = patcher.apply(osos, REPO / "patches/instant-save", 0x736800)
    assert len(alone) % 0x800 == 0


def test_needs():
    """shuffle-album-mix needs shuffle-fixes: a build without it fails. Each name in "needs" is a patch."""
    names = {p.name for p in (REPO / "patches").iterdir() if (p / "patch.json").exists()}
    for p in (REPO / "patches").iterdir():
        if (p / "patch.json").exists():
            for need in json.loads((p / "patch.json").read_text()).get("needs", []):
                assert need in names, (p.name, need)
    with pytest.raises(patcher.PatchError, match="needs the patch"):
        patcher.apply_all(b"", [REPO / "patches/shuffle-album-mix"])


@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_playlist_folders():
    osos = FirmwarePartition(extract_firmware(os.environ["IPODFW_IPSW"])[1]).image("osos")
    out, report = patcher.apply(osos, REPO / "patches/playlist-folders", 0x736800)
    syms = {k: int(v, 16) for k, v in report["symbols"].items()}
    # the four calls that change a screen row into an array index
    for at, name in ((0x1ea66c, "hook_count"), (0x1ec914, "hook_name"), (0x1e7e7c, "hook_select"), (0x254cc4, "hook_otg")):
        assert struct.unpack_from("<I", out, at)[0] == patcher.branch("bl", at, syms[name])
    for at, name in ((0x1ea660, "hook_vmax"), (0x1d81cc, "hook_ui_event")):
        assert struct.unpack_from("<I", out, at)[0] == patcher.branch("b", at, syms[name])
    assert struct.unpack_from("<I", out, 0x6772c0)[0] == syms["hook_list_event"]
    # the UI handler slot does not change: cover-flow hooks it, and up-next reads it
    assert struct.unpack_from("<I", out, 0x6701f0)[0] == 0x1d81cc
    assert report["bytes"] == json.loads((REPO / "patches/playlist-folders/patch.json").read_text())["size"]
    # with the patches that use the same list event slot or the UI handler
    names = ("album-art", "cover-flow", "playlist-folders", "up-next")
    every = patcher.apply_all(osos, [REPO / "patches" / n for n in names])
    assert struct.unpack_from("<I", every, 0x6701f0)[0] != 0x1d81cc     # the hook of cover-flow
    assert struct.unpack_from("<I", every, 0x1d81cc)[0] >> 24 == 0xEA    # the b hook of playlist-folders
