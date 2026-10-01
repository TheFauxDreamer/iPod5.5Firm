"""Raw access to a connected iPod's firmware partition on macOS.

The iPod must be in disk mode or simply mounted over USB. Raw I/O goes
through /dev/rdiskN with block-aligned offsets, which needs root
(run with sudo). Partition table parsing follows ipodpatcher's
read_partinfo(): MBR for Windows-formatted iPods, APM for Mac-formatted.
"""

from __future__ import annotations

import os
import plistlib
import struct
import subprocess
from dataclasses import dataclass

from .partition import ENTRY_SIZE, FirmwareError, FirmwarePartition


@dataclass
class IPodDisk:
    disk: str          # e.g. "disk4"
    media_name: str
    block_size: int
    size: int

    @property
    def raw_path(self) -> str:
        return f"/dev/r{self.disk}"


def _diskutil(verb: str, *args: str) -> dict:
    out = subprocess.run(["diskutil", verb, "-plist", *args], check=True, capture_output=True).stdout
    return plistlib.loads(out)


def find_ipods() -> list[IPodDisk]:
    listing = _diskutil("list", "external", "physical")
    found = []
    for disk in listing.get("WholeDisks", []):
        info = _diskutil("info", disk)
        name = info.get("MediaName", "") or info.get("IORegistryEntryName", "")
        if "ipod" in name.lower():
            found.append(IPodDisk(disk, name, int(info.get("DeviceBlockSize", 512)), int(info.get("Size", 0))))
    return found


def pick_ipod(disk: str | None) -> IPodDisk:
    ipods = find_ipods()
    if disk:
        ipods = [i for i in ipods if i.disk == disk.removeprefix("/dev/")]
    if not ipods:
        raise FirmwareError("no iPod found (connect it, or pass --disk diskN)")
    if len(ipods) > 1:
        raise FirmwareError("several iPods connected; pass --disk " + " / ".join(i.disk for i in ipods))
    return ipods[0]


class RawDisk:
    def __init__(self, ipod: IPodDisk, writable: bool = False):
        self.ipod = ipod
        self.bs = ipod.block_size
        self.fd = os.open(ipod.raw_path, os.O_RDWR if writable else os.O_RDONLY)

    def close(self) -> None:
        os.close(self.fd)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def read(self, offset: int, length: int) -> bytes:
        start = offset - offset % self.bs
        end = -(-(offset + length) // self.bs) * self.bs
        chunks, pos = [], start
        while pos < end:
            n = min(4 * 1024 * 1024, end - pos)
            chunk = os.pread(self.fd, n, pos)
            if len(chunk) != n:
                raise OSError(f"short read at {pos}")
            chunks.append(chunk)
            pos += n
        data = b"".join(chunks)
        return data[offset - start:offset - start + length]

    def write_aligned(self, offset: int, data: bytes) -> None:
        if offset % self.bs or len(data) % self.bs:
            raise ValueError("unaligned raw write")
        if os.pwrite(self.fd, data, offset) != len(data):
            raise OSError(f"short write at {offset}")


def locate_firmware_partition(disk: RawDisk) -> tuple[int, int]:
    """Return (start_bytes, size_bytes) of the firmware partition."""
    bs = disk.bs
    sector0 = disk.read(0, bs)
    if sector0[510:512] == b"\x55\xaa":
        parts = [struct.unpack_from("<4xB3xII", sector0, 0x1BE + 16 * i) for i in range(4)]
        (t0, s0, n0), (t1, _s1, _n1) = parts[0], parts[1]
        if t0 != 0 or n0 == 0 or t1 not in (0x0B, 0x0C):
            raise FirmwareError("partition layout is not an iPod (MBR)")
        return s0 * bs, n0 * bs
    if sector0[:2] == b"ER":
        mul = sector0[2] // 2
        blk, count = 1, 1
        while blk <= count:
            entry = disk.read(blk * mul * 512, bs)
            if entry[:2] != b"PM":
                break
            count, start, nblocks = struct.unpack_from(">III", entry, 4)
            if entry[48:58] == b"Apple_MDFW":
                return start * bs, nblocks * bs
            blk += 1
        raise FirmwareError("no Apple_MDFW firmware partition in the Apple partition map")
    raise FirmwareError("unrecognised partition table")


def read_partition(disk: RawDisk) -> bytes:
    start, size = locate_firmware_partition(disk)
    return disk.read(start, size)


def unmount(ipod: IPodDisk) -> None:
    subprocess.run(["diskutil", "unmountDisk", ipod.disk], check=True, capture_output=True)


# -- safety checks + flashing ----------------------------------------------

def check_compatible(current: FirmwarePartition, new: FirmwarePartition, label: str) -> None:
    """new may only differ from current in the osos/rsrc length and checksum."""
    if (current.image_base, current.dir_offset) != (new.image_base, new.dir_offset):
        raise FirmwareError(f"{label}: partition layout differs from the iPod's (image base / directory)")
    if len(current.entries) != len(new.entries):
        raise FirmwareError(f"{label}: different number of firmware images than the iPod")
    for c, n in zip(current.entries, new.entries):
        if (c.type, c.dev_offset) != (n.type, n.dev_offset):
            raise FirmwareError(f"{label}: image {c.name} is at a different position than on the iPod")
        if c.name not in ("osos", "rsrc", "hibe") and c.pack() != n.pack():
            raise FirmwareError(f"{label}: directory entry for {c.name} differs from the iPod's")
    for name in ("osos", "rsrc"):
        if new.has(name) and not new.checksum_ok(name):
            raise FirmwareError(f"{label}: {name} checksum does not verify")
    if current.has("aupd") and current.image("aupd") != new.image("aupd"):
        raise FirmwareError(f"{label}: aupd (NOR flash updater) differs from the iPod's; refusing")


def preserve_hibernation(new: bytes, current: FirmwarePartition) -> bytes:
    """Keep the iPod's own hibernation snapshot (hibe): copy its current entry and data into new."""
    if not current.has("hibe"):
        return new
    e = current.entry("hibe")
    buf = bytearray(new)
    at = current.dir_offset + e.index * ENTRY_SIZE
    buf[at:at + ENTRY_SIZE] = current.data[at:at + ENTRY_SIZE]
    lo, hi = current.image_range("hibe")
    hi = min(hi, len(buf))
    if lo < hi:
        buf[lo:hi] = current.data[lo:hi]
    return bytes(buf)


def plan_writes(current: bytes, new: bytes, bs: int, protected: tuple[int, int]) -> list[tuple[int, int]]:
    """Block-aligned (offset, length) ranges, relative to the partition, where new differs."""
    ranges: list[tuple[int, int]] = []
    for off in range(0, len(new), bs):
        if new[off:off + bs] != current[off:off + len(new[off:off + bs])]:
            if ranges and ranges[-1][0] + ranges[-1][1] == off:
                ranges[-1] = (ranges[-1][0], ranges[-1][1] + bs)
            else:
                ranges.append((off, bs))
    p0, p1 = protected
    for off, length in ranges:
        if off < p1 and off + length > p0:
            raise FirmwareError("planned write overlaps the aupd image; refusing")
    return ranges


def flash(ipod: IPodDisk, new_bytes: bytes, backup_bytes: bytes, dry_run: bool) -> list[tuple[int, int]]:
    """Write new_bytes over the firmware partition, touching only changed blocks."""
    with RawDisk(ipod) as disk:
        part_start, part_size = locate_firmware_partition(disk)
        current_bytes = disk.read(part_start, part_size)
    if len(new_bytes) > part_size:
        raise FirmwareError(f"image ({len(new_bytes)} bytes) is larger than the firmware partition ({part_size})")

    current = FirmwarePartition(current_bytes)
    new_bytes = preserve_hibernation(new_bytes, current)
    new = FirmwarePartition(new_bytes)
    backup = FirmwarePartition(backup_bytes)
    check_compatible(current, backup, "backup")
    check_compatible(current, new, "new firmware")

    bs = ipod.block_size
    if current.has("aupd"):
        protected = current.image_range("aupd")
    else:
        protected = (0, 0)
    tail = len(new_bytes) % bs
    if tail:
        new_bytes = new_bytes + current_bytes[len(new_bytes):len(new_bytes) + bs - tail]
    ranges = plan_writes(current_bytes, new_bytes, bs, protected)
    if dry_run or not ranges:
        return ranges

    unmount(ipod)
    with RawDisk(ipod, writable=True) as disk:
        for off, length in ranges:
            disk.write_aligned(part_start + off, new_bytes[off:off + length])
        os.fsync(disk.fd)
        for off, length in ranges:
            if disk.read(part_start + off, length) != new_bytes[off:off + length]:
                raise FirmwareError(f"verification failed at partition offset 0x{off:x}; restore from your backup")
    return ranges


def rescue_restore(ipod: IPodDisk, backup_bytes: bytes, reference_bytes: bytes,
                   dry_run: bool) -> tuple[list[tuple[int, int]], bytes]:
    """Restore a backup when the iPod's firmware partition no longer parses (an interrupted write).

    flash() compares the new image with the iPod's current firmware. Here the reference backup
    (the first backup of this iPod) takes that role. Returns the planned ranges and the damaged bytes.
    """
    with RawDisk(ipod) as disk:
        part_start, part_size = locate_firmware_partition(disk)
        current_bytes = disk.read(part_start, part_size)
    try:
        FirmwarePartition(current_bytes)
    except FirmwareError:
        pass
    else:
        raise FirmwareError("the firmware on the iPod is not damaged; use 'ipodfw restore' without --rescue")
    reference = FirmwarePartition(reference_bytes)
    if len(reference_bytes) != part_size:
        raise FirmwareError("the reference backup is not from this iPod (the partition size is different)")
    if len(backup_bytes) > part_size:
        raise FirmwareError(f"backup ({len(backup_bytes)} bytes) is larger than the firmware partition ({part_size})")
    try:
        new = FirmwarePartition(backup_bytes)
    except FirmwareError as e:
        raise FirmwareError(f"the backup is damaged too ({e})") from e
    check_compatible(reference, new, "backup")

    bs = ipod.block_size
    protected = new.image_range("aupd") if new.has("aupd") else (0, 0)
    tail = len(backup_bytes) % bs
    if tail:
        backup_bytes = backup_bytes + current_bytes[len(backup_bytes):len(backup_bytes) + bs - tail]
    try:
        ranges = plan_writes(current_bytes, backup_bytes, bs, protected)
    except FirmwareError as e:
        raise FirmwareError("the damage includes the aupd area, which ipodfw never writes; restore the iPod with Finder") from e
    if dry_run or not ranges:
        return ranges, current_bytes

    unmount(ipod)
    with RawDisk(ipod, writable=True) as disk:
        for off, length in ranges:
            disk.write_aligned(part_start + off, backup_bytes[off:off + length])
        os.fsync(disk.fd)
        for off, length in ranges:
            if disk.read(part_start + off, length) != backup_bytes[off:off + length]:
                raise FirmwareError(f"verification failed at partition offset 0x{off:x}; try the rescue again or restore with Finder")
    return ranges, current_bytes
