"""Tests for the hibernation area of the iPod and for the repair of a partition.

The tests use a small synthetic partition. The tests do not use the file of a
real iPod. The file of a real iPod is personal data.
"""

from __future__ import annotations

import struct

import pytest

from ipodfw import hibe
from ipodfw.partition import FirmwarePartition, FirmwareError


def make_snapshot(size: int = 0x100800) -> bytes:
    """A valid snapshot: the header of the iPod and the memory of one page."""
    buf = bytearray(size)
    struct.pack_into("<III", buf, 0, 1, 0x20000, 1)     # the version, the page size, the pages
    buf[0x18:0x3c] = b"\x88" * 0x24                    # the pattern of the pages
    buf[0x800:] = b"\x5a" * (size - 0x800)              # the memory of the iPod
    return bytes(buf)


def make_partition(with_hibe: bool = True, stale: int = 0, snapshot: bool = True) -> bytes:
    """Make a small partition with the images osos, rsrc and aupd.

    The partition has the image hibe when `with_hibe`. Without the image, the
    partition has the hibernation area at its fixed place when `snapshot`: the
    header of a snapshot and the memory of the iPod. The partition has `stale`
    bytes of old data after the last image when the area has no header.

    The layout copies the iPod of the owner, at a small scale. The image aupd
    ends at 0x2800. The hibernation area starts at 0x3800: the gap of 0x1000
    bytes, as on the iPod. The header of the test gives one page, thus the
    area is 0x800 + 0x100000 bytes and it ends at 0x103800. The image rsrc
    parks at 0x103800 when the osos grows. The partition is 0x108000 bytes,
    thus the parked rsrc of 0x400 bytes fits.
    """
    size = 0x108000
    buf = bytearray(size)
    # The header. The directory is at 0x800, as the value at 0x104 says. The
    # image base is 2048, thus the images start at 0x800 + 2048.
    buf[0:16] = b"{{~~  /-----\\   "
    buf[0x100:0x104] = b"]ih["
    struct.pack_into("<I", buf, 0x104, 0x800 - 0x200)
    struct.pack_into("<H", buf, 0x10A, 3)
    images = [("soso", 0x1000, 0x800), ("crsr", 0x1800, 0x400),
              ("dpua", 0x1C00, 0xC00)]
    if with_hibe:
        images.append(("ebih", 0x3800, 0x100800))
    for n, (name, offset, length) in enumerate(images):
        at = 0x800 + n * 40
        buf[at:at + 4] = b"!ATA"
        buf[at + 4:at + 8] = name.encode("latin-1")
        struct.pack_into("<I", buf, at + 8, n + 1)
        struct.pack_into("<I", buf, at + 12, offset)
        struct.pack_into("<I", buf, at + 16, length)
        struct.pack_into("<I", buf, at + 32, 0xB012)
        if name == "ebih":
            # The image hibe holds a valid snapshot, so that the area is
            # readable when the entry is missing.
            buf[2048 + offset:2048 + offset + length] = make_snapshot(length)
        else:
            buf[2048 + offset:2048 + offset + length] = bytes([n + 1]) * length
        # The checksum of the image. The function `_detect_image_base` tries the
        # bases in order and keeps the first where the checksum of osos is right.
        if name == "soso":
            struct.pack_into("<I", buf, at + 28,
                             sum(buf[2048 + offset:2048 + offset + length]) & 0xFFFFFFFF)
    # The header of the snapshot at the fixed place of the area, when the
    # directory has no entry for the image hibe. One page: the memory of one
    # megabyte, as the header of the iPod gives one page for each megabyte.
    if not with_hibe and snapshot:
        at = 2048 + 0x3800
        struct.pack_into("<III", buf, at, 1, 0x20000, 1)    # the version, the page size, the pages
        buf[at + 0x18:at + 0x3c] = b"\x88" * 0x24            # the pattern of the pages
        buf[at + 0x800:at + 0x800 + 0x1000] = b"\x5a" * 0x1000   # the memory of the iPod
    if stale:
        at = 2048 + 0x2800
        buf[at:at + stale] = b"\xa5" * stale
    return bytes(buf)


def test_check_gives_the_state_of_a_healthy_partition():
    p = FirmwarePartition(make_partition(with_hibe=True))
    report = hibe.check_hibe(p)
    assert report.present
    assert report.ok
    assert report.length == 0x100800
    assert report.offset == 0x3800


def test_check_gives_the_state_of_a_partition_that_lost_the_entry():
    """The area is intact and the entry is missing. The repair needs no backup."""
    p = FirmwarePartition(make_partition(with_hibe=False, snapshot=True))
    report = hibe.check_hibe(p)
    assert not report.present
    assert not report.ok
    assert report.offset == 0x3800
    assert report.length == 0x100800
    assert report.stale_bytes == 0


def test_check_gives_the_state_of_a_broken_area():
    """The area has no header. The data there is unknown."""
    p = FirmwarePartition(make_partition(with_hibe=False, snapshot=False, stale=64))
    report = hibe.check_hibe(p)
    assert not report.present
    assert not report.ok
    assert report.stale_bytes == 64
    assert report.notes


def test_the_hibernation_area_of_a_healthy_partition():
    p = FirmwarePartition(make_partition(with_hibe=True))
    assert p.hibe_area() == (0x3800, 0x100800)


def test_the_hibernation_area_without_the_entry():
    """The function finds the area by the header of the snapshot."""
    p = FirmwarePartition(make_partition(with_hibe=False, snapshot=True))
    assert p.hibe_area() == (0x3800, 0x100800)


def test_the_hibernation_area_refuses_data_without_a_header():
    p = FirmwarePartition(make_partition(with_hibe=False, snapshot=False, stale=0x400))
    assert p.hibe_area() is None


def test_the_place_of_the_image_hibe():
    p = FirmwarePartition(make_partition(with_hibe=True))
    offset, image = hibe.build_hibe_entry(p, b"\x00" * 0x100800)
    # The image follows the image aupd with the gap.
    assert offset == p.entry("aupd").dev_offset + p.entry("aupd").length + hibe.HIBE_GAP
    assert len(image) == 0x100800


def test_the_repair_writes_the_entry_only_when_the_area_is_intact():
    """The repair of a partition that lost the entry changes the directory only."""
    broken = make_partition(with_hibe=False, snapshot=True)
    before = bytes(broken)
    out = hibe.restore_hibe(broken)
    assert out != before
    fixed = FirmwarePartition(out)
    assert fixed.has("hibe")
    # Only the directory changed.
    diff = [i for i in range(len(out)) if out[i] != before[i]]
    assert all(0x800 <= i < 0x800 + 4 * 40 for i in diff)
    # The data of the area did not change.
    at = 2048 + 0x3800
    assert out[at:at + 0x10800] == before[at:at + 0x10800]


def test_the_repair_makes_the_entry_of_the_image_hibe():
    """The entry of the image hibe has the fields that the iPod writes.

    The research measured the entry in the healthy partition of the owner. The
    load address is the address of the memory of the iPod, 0x10000000. The
    second load address is 0xffffffff.
    """
    broken = make_partition(with_hibe=False, snapshot=True)
    out = hibe.restore_hibe(broken)
    fixed = FirmwarePartition(out)
    entry = fixed.entry("hibe")
    assert entry.type == b"ebih"
    assert entry.id == 1
    assert entry.addr == 0x10000000
    assert entry.load_addr == 0xFFFFFFFF
    assert entry.chksum == 0
    assert entry.vers == 0
    # The place and the size are the place and the size of the area.
    assert (entry.dev_offset, entry.length) == fixed.hibe_area()


def test_the_repair_with_a_backup_clears_an_area_without_a_header():
    """The area has no valid header. The repair clears the data and writes the snapshot."""
    broken = make_partition(with_hibe=False, snapshot=False, stale=0x400)
    snapshot = make_snapshot()
    out = hibe.restore_hibe(broken, snapshot)
    fixed = FirmwarePartition(out)
    assert fixed.has("hibe")
    assert bytes(fixed.image("hibe")) == snapshot
    # The other images do not change.
    p = FirmwarePartition(broken)
    for name in ("osos", "rsrc", "aupd"):
        assert bytes(fixed.image(name)) == bytes(p.image(name))


def test_the_repair_refuses_a_partition_that_has_the_image():
    healthy = make_partition(with_hibe=True)
    with pytest.raises(FirmwareError):
        hibe.restore_hibe(healthy)


def test_the_repair_refuses_a_short_image():
    broken = make_partition(with_hibe=False, snapshot=False, stale=0x100)
    with pytest.raises(FirmwareError):
        hibe.restore_hibe(broken, bytes(16))


def test_the_repair_refuses_an_image_that_covers_the_area():
    """No image may cover the place where the snapshot goes."""
    broken = make_partition(with_hibe=False, snapshot=False, stale=0)
    # Make the image rsrc longer, so that it covers the place of the snapshot.
    buf = bytearray(broken)
    at = 0x800 + 1 * 40
    struct.pack_into("<I", buf, at + 16, 0x2800)     # rsrc: from 0x1800 to 0x4000
    buf[2048 + 0x1800:2048 + 0x1800 + 0x2800] = b"\x02" * 0x2800
    snapshot = make_snapshot()
    with pytest.raises(FirmwareError):
        hibe.restore_hibe(bytes(buf), snapshot)


def test_the_repair_makes_the_space_for_a_bigger_osos():
    broken = make_partition(with_hibe=False, snapshot=True)
    out = hibe.restore_hibe(broken)
    fixed = FirmwarePartition(bytearray(out))
    # The image rsrc moves after the image hibe. The function needs the space.
    fixed.make_room(fixed.entry("osos").length + 0x100)
    assert fixed.entry("rsrc").dev_offset == fixed.entry("hibe").dev_offset + fixed.entry("hibe").length


def test_make_room_parks_rsrc_after_the_area_without_the_entry():
    """The iPod lost the entry. make_room finds the area and parks rsrc after it."""
    broken = make_partition(with_hibe=False, snapshot=True)
    fixed = FirmwarePartition(bytearray(broken))
    fixed.make_room(fixed.entry("osos").length + 0x100)
    area = FirmwarePartition(broken).hibe_area()
    assert fixed.entry("rsrc").dev_offset >= area[0] + area[1]
    # The data of the area did not change.
    at = 2048 + area[0]
    assert bytes(fixed.data[at:at + area[1]]) == broken[at:at + area[1]]


def test_make_room_refuses_data_without_a_header():
    """The data after the last image is not a hibernation area. The function refuses."""
    broken = make_partition(with_hibe=False, snapshot=False, stale=0x400)
    fixed = FirmwarePartition(bytearray(broken))
    with pytest.raises(FirmwareError, match="not a hibernation area"):
        fixed.make_room(fixed.entry("osos").length + 0x100)


def test_the_flash_keeps_the_image_hibe():
    """A firmware file has no image hibe. A flash must not remove the image of the iPod."""
    from ipodfw import device
    healthy = make_partition(with_hibe=True)
    current = FirmwarePartition(healthy)
    assert current.has("hibe")
    # A file without the image hibe: the same partition with the entry removed.
    at = current.dir_offset + current.entry("hibe").index * 40
    file = bytearray(healthy)
    file[at:at + 40] = bytes(40)
    assert not FirmwarePartition(bytes(file)).has("hibe")
    # The flash must give the layout of the iPod, with the image hibe.
    out = device.fit_layout(bytes(file), current)
    fixed = FirmwarePartition(out)
    assert fixed.has("hibe")
    assert bytes(fixed.image("hibe")) == bytes(current.image("hibe"))


def test_the_flash_adds_the_entry_when_the_ipod_lost_it():
    """The file has the entry and the iPod does not. The flash adds the entry.

    The data of the area of the iPod stays: the file holds a snapshot of
    another day.
    """
    from ipodfw import device
    healthy = make_partition(with_hibe=True)
    file = FirmwarePartition(healthy)
    # The iPod lost the entry, and its memory is different.
    current_bytes = bytearray(healthy)
    at = file.dir_offset + file.entry("hibe").index * 40
    current_bytes[at:at + 40] = bytes(40)
    # Keep the header of the snapshot, change the memory only.
    current_bytes[2048 + 0x3800 + 0x800:2048 + 0x3800 + 0x800 + 0x100] = b"\x77" * 0x100
    current = FirmwarePartition(bytes(current_bytes))
    assert not current.has("hibe")
    assert current.hibe_area() == (0x3800, 0x100800)
    out = device.fit_layout(healthy, current)
    fixed = FirmwarePartition(out)
    assert fixed.has("hibe")
    # The data of the area of the iPod stays.
    assert out[2048 + 0x3800 + 0x800:2048 + 0x3800 + 0x800 + 0x100] == b"\x77" * 0x100


def test_the_flash_on_an_ipod_without_the_entry_and_a_file_without_the_entry():
    """Neither the iPod nor the file has the entry. The flash parks rsrc after the area."""
    from ipodfw import device
    broken = make_partition(with_hibe=False, snapshot=True)
    current = FirmwarePartition(broken)
    # A firmware file: no entry, and an osos that fits before rsrc.
    out = device.fit_layout(broken, current)
    fixed = FirmwarePartition(out)
    assert not fixed.has("hibe")
    # The images stay in place: the osos of the file fits before rsrc.
    for name in ("osos", "rsrc", "aupd"):
        assert fixed.entry(name).dev_offset == current.entry(name).dev_offset
    # A larger osos parks rsrc after the area, without the entry.
    fixed2 = FirmwarePartition(bytearray(broken))
    fixed2.make_room(fixed2.entry("osos").length + 0x800)
    area = FirmwarePartition(broken).hibe_area()
    assert fixed2.entry("rsrc").dev_offset >= area[0] + area[1]
    # The data of the area did not change.
    at = fixed2.image_base + area[0]
    assert bytes(fixed2.data[at:at + area[1]]) == broken[at:at + area[1]]


def test_the_flash_of_a_file_with_the_entry_on_an_ipod_without_the_area():
    """The iPod has no hibernation area. The file has the entry. The flash refuses."""
    from ipodfw import device
    broken = make_partition(with_hibe=False, snapshot=False, stale=0x400)
    current = FirmwarePartition(broken)
    healthy = make_partition(with_hibe=True)
    with pytest.raises(FirmwareError):
        device.fit_layout(healthy, current)


def test_check_compatible_allows_one_extra_hibe():
    """The entry came back. The check allows the extra image when it fits the area."""
    from ipodfw import device
    broken = make_partition(with_hibe=False, snapshot=True)
    current = FirmwarePartition(broken)
    healthy = make_partition(with_hibe=True)
    new = FirmwarePartition(device.fit_layout(healthy, current))
    assert new.has("hibe")
    assert not current.has("hibe")
    device.check_compatible(current, new, "New firmware")


def test_check_compatible_refuses_a_rsrc_over_the_area():
    """The image rsrc must not cover the hibernation area, with or without the entry."""
    from ipodfw import device
    broken = make_partition(with_hibe=False, snapshot=True)
    current = FirmwarePartition(broken)
    # Move rsrc to the place of the area.
    buf = bytearray(broken)
    at = current.dir_offset + current.entry("rsrc").index * 40
    struct.pack_into("<I", buf, at + 12, 0x3800)
    new = FirmwarePartition(bytes(buf))
    with pytest.raises(FirmwareError):
        device.check_compatible(current, new, "New firmware")
