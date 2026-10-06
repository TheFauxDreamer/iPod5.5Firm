import json
import os
import struct
from pathlib import Path

import pytest
from PIL import Image

from ipodfw import device, pictures, resources, theme
from ipodfw.ipsw import extract_firmware
from ipodfw.partition import FirmwareError, FirmwarePartition


def test_parse_directory(partition_bytes):
    fw = FirmwarePartition(partition_bytes)
    assert fw.image_base == 2048
    assert [e.name for e in fw.entries] == ["osos", "rsrc", "aupd"]
    assert fw.model == "Video (5G/5.5G)"
    assert fw.checksum_ok("osos") and fw.checksum_ok("rsrc")
    assert fw.to_bytes() == partition_bytes


def test_rejects_non_firmware():
    with pytest.raises(FirmwareError):
        FirmwarePartition(bytes(4096))


def test_corrupt_osos_detected(partition_bytes):
    data = bytearray(partition_bytes)
    data[2048 + 0x4800 + 10] ^= 0xFF
    with pytest.raises(FirmwareError, match="checksum"):
        FirmwarePartition(data)


def test_never_modifies_aupd(partition_bytes):
    fw = FirmwarePartition(partition_bytes)
    with pytest.raises(FirmwareError, match="aupd"):
        fw.replace_image("aupd", b"x")


def test_resource_scan(partition_bytes):
    osos = FirmwarePartition(partition_bytes).image("osos")
    blocks = resources.scan(osos)
    assert len(blocks) == 2
    main = resources.main_block(blocks)
    assert [r.id for r in main.of_type("BMap")] == [100, 101, 102]
    assert resources.read_strings(osos, main) == {"129": "January", "130": "Feb", "131": "Mar"}
    assert resources.read_strings(osos, blocks[1])["130"] == "Fév"


def test_picture_decode(partition_bytes):
    osos = FirmwarePartition(partition_bytes).image("osos")
    main = resources.main_block(resources.scan(osos))
    pics = [pictures.parse(osos, main.abs(r)) for r in main.of_type("BMap")]
    assert [p.format_name for p in pics] == ["RGB565", "ARGB4444", "grey4"]
    argb = pictures.decode(osos, pics[1])
    assert argb.getpixel((0, 0)) == (0, 0, 255, 255)     # LE word 0xF00F: a=15 r=0 g=0 b=15
    grey = pictures.decode(osos, pics[2])
    assert [grey.getpixel((x, 0)) for x in range(3)] == [255, 0, 119]


def test_unchanged_round_trip(partition_bytes, tmp_path):
    fw = FirmwarePartition(partition_bytes)
    theme.unpack(fw, tmp_path)
    report = theme.repack(fw, tmp_path)
    assert not report.changed
    assert fw.to_bytes() == partition_bytes


def test_edit_picture_and_string(partition_bytes, tmp_path):
    fw = FirmwarePartition(partition_bytes)
    manifest = theme.unpack(fw, tmp_path)
    png = tmp_path / manifest["pictures"][0]["file"]
    img = Image.open(png).convert("RGB")
    img.putpixel((1, 1), (255, 0, 0))
    img.save(png)
    strings_file = tmp_path / manifest["string_blocks"][0]["file"]
    strings = json.loads(strings_file.read_text())
    strings["130"] = "Febr"            # grows into the alignment slack
    strings_file.write_text(json.dumps(strings))

    report = theme.repack(fw, tmp_path)
    assert report.pictures_changed and report.string_blocks_changed
    out = FirmwarePartition(fw.to_bytes())          # re-parse: checksum must verify
    assert out.checksum_ok("osos")
    assert out.image("aupd") == FirmwarePartition(partition_bytes).image("aupd")
    assert out.image("rsrc") == FirmwarePartition(partition_bytes).image("rsrc")

    again = tmp_path / "again"
    theme.unpack(out, again)
    assert Image.open(again / manifest["pictures"][0]["file"]).convert("RGB").getpixel((1, 1)) == (255, 0, 0)
    assert json.loads((again / manifest["string_blocks"][0]["file"]).read_text())["130"] == "Febr"


def test_string_overflow_refused(partition_bytes, tmp_path):
    fw = FirmwarePartition(partition_bytes)
    manifest = theme.unpack(fw, tmp_path)
    f = tmp_path / manifest["string_blocks"][0]["file"]
    strings = json.loads(f.read_text())
    strings["131"] = "March is far too long"
    f.write_text(json.dumps(strings))
    with pytest.raises(resources.ResourceError, match="too many"):
        theme.repack(fw, tmp_path)


def test_picture_size_mismatch_refused(partition_bytes, tmp_path):
    fw = FirmwarePartition(partition_bytes)
    manifest = theme.unpack(fw, tmp_path)
    Image.new("RGB", (5, 5)).save(tmp_path / manifest["pictures"][0]["file"])
    with pytest.raises(pictures.PictureError):
        theme.repack(fw, tmp_path)


def test_repack_onto_other_firmware_refused(partition_bytes, tmp_path):
    fw = FirmwarePartition(partition_bytes)
    theme.unpack(fw, tmp_path)
    manifest = json.loads((tmp_path / "manifest.json").read_text())
    manifest["osos_sha256"] = "0" * 64
    (tmp_path / "manifest.json").write_text(json.dumps(manifest))
    with pytest.raises(resources.ResourceError, match="different firmware"):
        theme.repack(fw, tmp_path)


# -- flashing safety -------------------------------------------------------

def test_plan_writes_only_changed_blocks(partition_bytes):
    new = bytearray(partition_bytes)
    new[5000] ^= 1
    ranges = device.plan_writes(partition_bytes, bytes(new), 512, (0, 0))
    assert ranges == [(4608, 512)]


def test_plan_writes_refuses_aupd_overlap(partition_bytes):
    fw = FirmwarePartition(partition_bytes)
    start, end = fw.image_range("aupd")
    new = bytearray(partition_bytes)
    new[start + 1] ^= 1
    with pytest.raises(FirmwareError, match="aupd"):
        device.plan_writes(partition_bytes, bytes(new), 512, (start, end))


def test_check_compatible_rejects_changed_aupd(partition_bytes):
    current = FirmwarePartition(partition_bytes)
    data = bytearray(partition_bytes)
    start, _ = current.image_range("aupd")
    data[start] ^= 1
    with pytest.raises(FirmwareError, match="aupd"):
        device.check_compatible(current, FirmwarePartition(data), "new")


class FakeDisk:
    def __init__(self, data, bs):
        self.data, self.bs = data, bs

    def read(self, offset, length):
        return self.data[offset:offset + length]


def test_locate_mbr_partition():
    disk = bytearray(4096)
    struct.pack_into("<4xB3xII", disk, 0x1BE, 0x00, 63, 1000)
    struct.pack_into("<4xB3xII", disk, 0x1CE, 0x0B, 1063, 99999)
    disk[510:512] = b"\x55\xaa"
    assert device.locate_firmware_partition(FakeDisk(bytes(disk), 512)) == (63 * 512, 1000 * 512)


def test_locate_apm_partition():
    bs = 2048
    disk = bytearray(bs * 8)
    disk[0:4] = b"ER\x08\x00"
    for n, (name, start, count) in enumerate([("Apple_partition_map", 1, 3), ("Apple_MDFW", 40, 500)], start=1):
        e = n * 4 * 512
        disk[e:e + 2] = b"PM"
        struct.pack_into(">III", disk, e + 4, 2, start, count)
        disk[e + 48:e + 48 + len(name)] = name.encode()
    assert device.locate_firmware_partition(FakeDisk(bytes(disk), bs)) == (40 * bs, 500 * bs)


# -- optional: Apple's real firmware --------------------------------------

@pytest.mark.skipif(not os.environ.get("IPODFW_IPSW"), reason="set IPODFW_IPSW=path/to/iPod_25.1.3.ipsw")
def test_real_firmware_round_trip(tmp_path):
    _, data = extract_firmware(os.environ["IPODFW_IPSW"])
    fw = FirmwarePartition(data)
    assert fw.checksum_ok("osos") and fw.checksum_ok("rsrc")
    manifest = theme.unpack(fw, tmp_path)
    assert len(manifest["pictures"]) == 403
    assert not theme.repack(fw, tmp_path).changed
    assert fw.to_bytes() == data


def _classic_partition(header: bytes = b"8702") -> bytes:
    """A small partition with the layout of the iPod classic 6G firmware 1.1.2 (re/ipod-classic-6g.md):
    the directory at 0x4000 + 0x1000, rsrc first, and an osos that starts with an "8702" image header."""
    from ipodfw.partition import STOP_SIGN_PREFIX
    d = bytearray(0x8000)
    d[:len(STOP_SIGN_PREFIX)] = STOP_SIGN_PREFIX
    d[0x100:0x104] = b"]ih["
    struct.pack_into("<I", d, 0x104, 0x4000)
    d[0x5000:0x5008] = b"!ATAcrsr"
    struct.pack_into("<II", d, 0x5000 + 12, 0x6000, 0x100)
    d[0x5028:0x5030] = b"!ATAsoso"
    struct.pack_into("<II", d, 0x5028 + 12, 0x7000, 0x800)
    struct.pack_into("<I", d, 0x5028 + 32, 0x13000)
    d[0x7000:0x7008] = header + b"1.0\x03"
    for i in range(0x7800, 0x8000):
        d[i] = (i * 7919) & 0xFF
    return bytes(d)


def test_classic_is_identified():
    from ipodfw.partition import samsung_image_header
    assert samsung_image_header(_classic_partition()) == "8702"
    assert samsung_image_header(_classic_partition(b"\x00\x01\x02\x03")) == "unknown"
    with pytest.raises(FirmwareError, match="iPod classic"):
        FirmwarePartition(_classic_partition())


def test_video_is_not_samsung(partition_bytes):
    from ipodfw.partition import samsung_image_header
    assert samsung_image_header(partition_bytes) is None
    assert samsung_image_header(bytes(0x8000)) is None
