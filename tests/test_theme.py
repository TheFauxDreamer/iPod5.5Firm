"""Tests for the theme import, for make_room, and for the flash rules for a moved rsrc."""

import os
import struct

import pytest

from ipodfw import device, themeimport
from ipodfw.partition import ENTRY_SIZE, FirmwareError, FirmwarePartition, checksum


def file_layout(partition_bytes: bytes) -> bytes:
    """The fixture without free space after the last image (as an Apple firmware file)."""
    fw = FirmwarePartition(partition_bytes)
    end = max(e.dev_offset + e.length for e in fw.entries)
    return partition_bytes[:fw.image_base + end]


def ipod_layout(partition_bytes: bytes, hibe_length: int = 0x2000, free: int = 0x10000) -> bytes:
    """The fixture with a hibe image after aupd and free space after it (as an iPod partition)."""
    fw = FirmwarePartition(partition_bytes)
    end = max(e.dev_offset + e.length for e in fw.entries)
    hibe_at = (end + 0x7FF) // 0x800 * 0x800
    buf = bytearray(partition_bytes[:fw.image_base + end])
    buf += bytes(fw.image_base + hibe_at + hibe_length + free - len(buf))
    buf[fw.image_base + hibe_at:fw.image_base + hibe_at + hibe_length] = b"\x55" * hibe_length
    at = fw.dir_offset + len(fw.entries) * ENTRY_SIZE
    struct.pack_into("<4s4s8I", buf, at, b"!ATA", b"ebih", 0, hibe_at, hibe_length, 0, 0, 0, 0xB012, 0)
    return bytes(buf)


def grow(fw: FirmwarePartition, extra: int) -> bytes:
    osos = fw.image("osos") + b"\x01" * extra
    fw.make_room(len(osos))
    fw.replace_image("osos", osos)
    return osos


def test_make_room_does_nothing_if_osos_fits(partition_bytes):
    fw = FirmwarePartition(file_layout(partition_bytes))
    before = [e.dev_offset for e in fw.entries]
    fw.make_room(len(fw.image("osos")))
    assert [e.dev_offset for e in fw.entries] == before


def test_make_room_in_a_file_moves_rsrc_and_aupd(partition_bytes):
    data = file_layout(partition_bytes)
    fw = FirmwarePartition(data)
    rsrc, aupd = fw.image("rsrc"), fw.image("aupd")
    osos = grow(fw, 5000)
    again = FirmwarePartition(fw.to_bytes())
    assert again.image("osos") == osos and again.checksum_ok("osos")
    assert again.image("rsrc") == rsrc and again.checksum_ok("rsrc")
    assert again.image("aupd") == aupd
    assert again.entry("rsrc").dev_offset >= again.entry("osos").dev_offset + len(osos)


def test_make_room_on_an_ipod_moves_only_rsrc(partition_bytes):
    data = ipod_layout(partition_bytes)
    fw = FirmwarePartition(data)
    aupd_at, hibe_at = fw.entry("aupd").dev_offset, fw.entry("hibe").dev_offset
    rsrc = fw.image("rsrc")
    grow(fw, 1500)                          # osos can grow up to aupd
    again = FirmwarePartition(fw.to_bytes())
    assert len(again.data) == len(data)
    assert again.entry("aupd").dev_offset == aupd_at and again.entry("hibe").dev_offset == hibe_at
    assert again.entry("rsrc").dev_offset > hibe_at
    assert again.image("rsrc") == rsrc
    device.check_compatible(FirmwarePartition(data), again, "new")


def test_make_room_refuses_to_overwrite_data(partition_bytes):
    data = bytearray(ipod_layout(partition_bytes))
    fw = FirmwarePartition(bytes(data))
    hibe_end = fw.entry("hibe").dev_offset + fw.entry("hibe").length
    data[fw.image_base + hibe_end + 10] = 1  # old data in the free space after hibe
    fw = FirmwarePartition(bytes(data))
    with pytest.raises(FirmwareError, match="not empty"):
        grow(fw, 1500)


def test_check_compatible_refuses_rsrc_over_hibe(partition_bytes):
    current = FirmwarePartition(ipod_layout(partition_bytes))
    new = FirmwarePartition(current.to_bytes())
    e = new.entry("rsrc")
    e.dev_offset = current.entry("hibe").dev_offset
    new._write_entry(e)
    with pytest.raises(FirmwareError, match="position|overlaps|checksum"):
        device.check_compatible(current, FirmwarePartition(new.to_bytes()), "new")


def test_fit_layout_puts_a_file_into_the_ipod_layout(partition_bytes):
    current = FirmwarePartition(ipod_layout(partition_bytes))
    f = FirmwarePartition(file_layout(partition_bytes))
    osos = grow(f, 1500)
    fitted = FirmwarePartition(device.fit_layout(f.to_bytes(), current))
    assert fitted.image("osos") == osos
    assert fitted.entry("aupd").dev_offset == current.entry("aupd").dev_offset
    assert fitted.entry("hibe").dev_offset == current.entry("hibe").dev_offset
    device.check_compatible(current, fitted, "new")


def test_fit_layout_keeps_a_restore_unchanged(partition_bytes):
    current = FirmwarePartition(ipod_layout(partition_bytes))
    backup = current.to_bytes()
    assert device.fit_layout(backup, current) == backup


def test_merge_words_changes_only_agreeing_words():
    base = struct.pack("<4I", 1, 2, 3, 4)
    theme = struct.pack("<4I", 1, 9, 3, 8)
    target = struct.pack("<5I", 1, 2, 7, 3, 5)     # a new word, and word 4 differs
    out, lost = themeimport.merge_words(base, theme, target)
    assert struct.unpack("<5I", out) == (1, 9, 7, 3, 5)
    assert lost == 1


def test_apply_theme_keeps_other_edits():
    th = themeimport.Theme("t", "", "abc", [themeimport.Change("BMap 1", 2, b"\x00\x00", b"\x11\x11"),
                                            themeimport.Change("BMap 2", 6, b"\x00", b"\x22")])
    osos = bytearray(8)
    osos[6] = 0x33                          # an edit by the owner
    assert themeimport.apply_theme(th, osos, "abc") == (1, 1)
    assert osos[2:4] == b"\x11\x11" and osos[6] == 0x33
    with pytest.raises(themeimport.ThemeError):
        themeimport.apply_theme(th, bytearray(8), "other")


def test_apply_theme_extends_osos():
    th = themeimport.Theme("t", "", "abc", [themeimport.Change("BMap 1", 10, b"\x00\x00", b"\x11\x11")])
    osos = bytearray(4)
    themeimport.apply_theme(th, osos, "abc")
    assert len(osos) == 0x800 and osos[10:12] == b"\x11\x11"


def test_apply_theme_keeps_the_blue_highlight():
    old = struct.pack("<4I", 0x18, 0xFFD06428, 0xFFE89858, 0x5E9E0000)
    new = struct.pack("<4I", 0x30, 0xFF252525, 0xFF343434, 0x5E9E0000)
    th = themeimport.Theme("t", "", "abc", [themeimport.Change("View 22034", 8, old, new),
                                            themeimport.Change("Type 14037", 24, old[4:8], new[4:8])])
    osos = bytearray(32)
    osos[8:24] = old
    osos[24:28] = old[4:8]
    themeimport.apply_theme(th, osos, "abc")
    assert struct.unpack_from("<4I", osos, 8) == (0x30, 0xFFD06428, 0xFFE89858, 0x5E9E0000)
    assert osos[24:28] == new[4:8]           # only View resources keep the blue colours


def test_edits_replace_the_theme_picture_and_survive_json():
    th = themeimport.Theme("t", "", "abc", [themeimport.Change("BMap 1", 4, b"\x00" * 4, b"\x11" * 4),
                                            themeimport.Change("BMap 2", 12, b"\x00", b"\x22")],
                           edits=[themeimport.Change("BMap 1", 4, b"\x00" * 4, b"\x33" * 4)])
    th = themeimport.Theme.from_json(th.to_json())
    osos = bytearray(16)
    assert themeimport.apply_theme(th, osos, "abc") == (2, 0)
    assert osos[4:8] == b"\x33" * 4 and osos[12] == 0x22


THEME_ENV = ("IPODFW_THEME", "IPODFW_THEME_BASE", "IPODFW_IPSW")


@pytest.mark.skipif(not all(os.environ.get(k) for k in THEME_ENV),
                    reason="set IPODFW_THEME (iPodWizard theme), IPODFW_THEME_BASE (its Apple .ipsw) and IPODFW_IPSW (1.3)")
def test_real_theme_import():
    theme_fw, sha = themeimport.load_firmware(os.environ["IPODFW_THEME"])
    base_fw, _ = themeimport.load_firmware(os.environ["IPODFW_THEME_BASE"])
    target_fw, _ = themeimport.load_firmware(os.environ["IPODFW_IPSW"])
    th = themeimport.make_theme(theme_fw, base_fw, target_fw, "test", sha)
    assert th.changes and any(r == "code" for r, _ in th.skipped)
    again = themeimport.Theme.from_json(th.to_json())
    osos = bytearray(target_fw.image("osos"))
    assert themeimport.apply_theme(again, osos, again.osos_sha256) == (len(th.changes), 0)
    target_fw.make_room(len(osos))
    target_fw.replace_image("osos", bytes(osos))
    out = FirmwarePartition(target_fw.to_bytes())
    assert out.checksum_ok("osos") and out.checksum_ok("rsrc")
    assert out.image("aupd") == themeimport.load_firmware(os.environ["IPODFW_IPSW"])[0].image("aupd")
    # the same theme on its own base gives no change
    with pytest.raises(themeimport.ThemeError):
        themeimport.make_theme(base_fw, base_fw, target_fw, "same")
    assert checksum(out.image("osos")) == out.entry("osos").chksum
