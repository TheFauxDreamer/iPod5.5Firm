"""Tests for the "Switch on iPod" build (ipodfw.darkmode)."""

import os
import struct
from pathlib import Path

import pytest

from ipodfw import darkmode, themeimport
from ipodfw.partition import FirmwarePartition

REPO = Path(__file__).resolve().parent.parent


def test_switch_table_switches_both_ways_and_keeps_edits():
    osos = bytearray(range(64))
    th = themeimport.Theme("t", "", "x", [
        themeimport.Change("View 1", 4, bytes([4, 5, 6]), bytes([9, 9, 9])),
        themeimport.Change("BMap 2", 20, bytes([20, 21]), bytes([0, 0])),
        themeimport.Change("BMap 3", 40, bytes([99]), bytes([1])),          # the owner changed this byte
        themeimport.Change("View 1", 4, bytes([4, 5, 6]), bytes([9, 9, 9])),  # the same change again
    ])
    table, skipped = darkmode.switch_table(th, bytes(osos))
    assert skipped == 1
    dark = bytearray(osos)
    darkmode.apply_switch_table(dark, table)
    assert dark[4:7] == bytes([9, 9, 9]) and dark[20:22] == bytes([0, 0]) and dark[40] == 40
    darkmode.apply_switch_table(dark, table)
    assert dark == osos


def test_settings_menu_gets_the_item_after_clicker():
    def item(key, label):
        it = bytearray(40)
        struct.pack_into("<III", it, 0x18, label, key, label)
        return bytes(it)
    menu = struct.pack("<I", 3) + item(darkmode.TEMPLATE_KEY, 0xFF69) + item(darkmode.INSERT_AFTER_KEY, 0xFF68) + item(0x600060AD, 0xFF67)
    new = darkmode.settings_menu(menu)
    assert struct.unpack_from("<I", new, 0)[0] == 4
    keys = [struct.unpack_from("<I", new, 4 + 40 * i + 0x1C)[0] for i in range(4)]
    assert keys == [darkmode.TEMPLATE_KEY, darkmode.INSERT_AFTER_KEY, darkmode.DARK_KEY, 0x600060AD]
    assert struct.unpack_from("<I", new, 4 + 80 + 0x18)[0] == darkmode.LABEL_ID
    with pytest.raises(darkmode.DarkModeError):
        darkmode.settings_menu(new)


ENV = ("IPODFW_THEME", "IPODFW_THEME_BASE", "IPODFW_IPSW")


@pytest.mark.skipif(not all(os.environ.get(k) for k in ENV),
                    reason="set IPODFW_THEME, IPODFW_THEME_BASE and IPODFW_IPSW")
def test_switch_build_gives_the_dark_theme_at_the_start():
    theme_fw, sha = themeimport.load_firmware(os.environ["IPODFW_THEME"])
    base_fw, _ = themeimport.load_firmware(os.environ["IPODFW_THEME_BASE"])
    fw, _ = themeimport.load_firmware(os.environ["IPODFW_IPSW"])
    th = themeimport.make_theme(theme_fw, base_fw, fw, "test", sha)
    stock = fw.image("osos")
    osos, info = darkmode.build(fw, stock, th, REPO / "patches/dark-mode", th.osos_sha256)
    assert info["changes_left_out"] == 0 and len(osos) <= themeimport.OSOS_LIMIT
    # the start in dark mode: the table applied in RAM
    dark = bytearray(osos)
    table_at, table_len = info["table"]
    darkmode.apply_switch_table(dark, bytes(osos[table_at:table_at + table_len]))
    built_in = bytearray(stock)
    themeimport.apply_theme(th, built_in, th.osos_sha256)
    menu_entry = None
    image = themeimport._Image(fw)
    r = image.res[darkmode.SETTINGS_MENU]
    menu_entry = range(r.table_pos + 4, r.table_pos + 12)
    patched = set(range(0x21f254, 0x21f258)) | set(range(0x66c94c, 0x66c954))
    diff = [i for i in range(len(stock)) if dark[i] != built_in[i] and i not in menu_entry and i not in patched]
    assert diff == []
    # the start in light mode: Apple's bytes, except the hooks and the menu entry
    diff = [i for i in range(len(stock)) if osos[i] != stock[i] and i not in menu_entry and i not in patched]
    assert diff == []
    fw.make_room(len(osos))
    fw.replace_image("osos", osos)
    assert FirmwarePartition(fw.to_bytes()).checksum_ok("osos")
