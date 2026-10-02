"""Tests for the patcher options that the dark-mode build uses (needs IPODFW_IPSW)."""

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
