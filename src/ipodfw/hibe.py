"""The hibernation image of the iPod, and the repair of a partition that lost it.

The file `iPod_Control/Device/SysInfo` of the iPod is not the hibernation image.
The hibernation image is the image `hibe` of the firmware partition. The image
holds a snapshot of the memory of the iPod. The firmware uses the snapshot to
start faster. The image is 64 MB on the iPod Video.

The image `hibe` is the last image of the partition. The firmware reads the
image through the directory. The firmware does not use a fixed place for the
image. The app never writes or moves the image. The app only copies it.

A partition without the image `hibe` cannot take a larger `osos`. The function
`make_room` of the partition moves the image `rsrc` to the space after the last
image. Without the image `hibe`, the space after the last image is the space
after the image `aupd`. The image `rsrc` moves there. The image `hibe` is the
only image that holds the space.

A partition without the image `hibe` also holds the data of a former build
after the last image. The data is a copy of the image `osos` and a copy of the
image `hibe`. The data is at the place where the image `rsrc` must go. The
function `make_room` refuses to write the image `rsrc` there.

The research is in [../../re/games-keyfile.md](../../re/games-keyfile.md) and in
[../../re/firmware-hibe.md](../../re/firmware-hibe.md).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

from .partition import FirmwarePartition, FirmwareError

# The name of the image in the directory of the partition. The name is
# byte-reversed in the directory: "ebih".
HIBE_NAME = "hibe"

# The size of the image on the iPod Video: 64 MB and 2 KB.
HIBE_LENGTH = 0x4000800

# The smallest size that the function `restore_hibe` accepts. The size of the
# image of the iPod Video is `HIBE_LENGTH`. The function accepts a smaller
# image so that the tests can use a small image.
MIN_HIBE_LENGTH = 0x1000

# The gap between the end of the image `aupd` and the start of the image `hibe`.
# The research measured the place of the image `hibe` in the backups of the
# owner. The gap is the same in all of them.
HIBE_GAP = 0x1000


@dataclass
class HibeReport:
    """The result of the check of the image `hibe` of a partition."""

    present: bool = False           # the partition has the image `hibe`
    length: int = 0                 # the size of the image in the directory
    offset: int = 0                 # the place of the image in the partition
    stale_bytes: int = 0            # the bytes of old data after the last image
    stale_head: bytes = b""         # the first bytes of the old data
    overlap: int = 0                # the bytes of the old data that cover the image
    ok: bool = False                 # the partition is in the state that the app expects
    notes: list[str] = field(default_factory=list)


def check_hibe(partition: FirmwarePartition) -> HibeReport:
    """Check the hibernation area of a partition and the entry of the image `hibe`.

    The function does not change the partition. The function gives the state of the
    partition. The hibernation area is the image `hibe` when the directory has the entry.
    Without the entry, the area keeps its fixed place after the image `aupd`, and the
    function finds it by the header of the snapshot.
    """
    report = HibeReport()
    if partition.has(HIBE_NAME):
        entry = partition.entry(HIBE_NAME)
        report.present = True
        report.length = entry.length
        report.offset = entry.dev_offset
        report.ok = True
        return report

    report.notes.append("The partition has no entry for the image hibe.")
    area = partition.hibe_area()
    if area is not None:
        report.offset, report.length = area
        report.notes.append(
            f"The hibernation area of the iPod is intact at 0x{area[0]:x}, "
            f"0x{area[1]:x} bytes. Only the entry of the directory is missing. "
            f"A patch flashes with or without the entry: the image rsrc goes after "
            f"the area. The repair adds the entry only.")
    else:
        last_end = max(e.dev_offset + e.length for e in partition.entries)
        aligned = (last_end + 0x7FF) // 0x800 * 0x800
        start = partition.image_base + aligned
        region = partition.data[start:start + partition.entry("rsrc").length]
        report.stale_bytes = sum(1 for b in region if b)
        report.stale_head = bytes(region[:16])
        report.notes.append(
            f"The space after the last image holds {report.stale_bytes} bytes of data "
            f"that is not a hibernation area. The image rsrc must go there. Clear the "
            f"data with the repair, or restore the iPod with Finder.")
    return report


def build_hibe_entry(partition: FirmwarePartition, hibe: bytes) -> tuple[int, bytes]:
    """Make the place of the image `hibe` and the bytes of the image.

    The place is the place that the image `hibe` has on a healthy partition: the
    image follows the image `aupd` with a gap of 0x1000 bytes. The research
    measured the place in the backups of the owner. The place is the same in
    all of them.
    """
    aupd = partition.entry("aupd")
    offset = aupd.dev_offset + aupd.length + HIBE_GAP
    return offset, hibe


def restore_hibe(partition_data: bytes, hibe: bytes | None = None) -> bytes:
    """Put the entry of the image `hibe` back into a partition of an iPod.

    The repair is minimal. When the hibernation area of the iPod is intact (a
    valid header of a snapshot is at the fixed place), the function writes the
    entry of the directory only. The data of the area does not change: the area
    holds the memory of the iPod, and the memory is newer than any backup. When
    no valid header is there, the function clears the space after the last
    image and writes the snapshot `hibe` from a backup, because the area is
    not usable.

    The function raises FirmwareError when the partition is not in a state that
    the function can repair, or when an image covers the hibernation area.
    """
    partition = FirmwarePartition(partition_data)
    if partition.has(HIBE_NAME):
        raise FirmwareError("the partition already has the image hibe")

    out = FirmwarePartition(partition_data)
    area = out.hibe_area()
    if area is not None and hibe is None:
        # The hibernation area is intact. Write the entry only.
        out.add_hibe_entry()
        return out.to_bytes()

    # The area has no valid header. Clear the space after the last image and
    # write the snapshot from a backup.
    if hibe is None:
        raise FirmwareError("the hibernation area has no valid header; give a snapshot from a backup")
    if len(hibe) < MIN_HIBE_LENGTH:
        raise FirmwareError(
            f"the image hibe must have at least {MIN_HIBE_LENGTH} bytes, it has {len(hibe)}")
    offset, image = build_hibe_entry(out, hibe)
    start = partition.image_base + offset
    if start + len(image) > len(out.data):
        raise FirmwareError("the image hibe does not fit in the partition")
    # No image may cover the hibernation area.
    for e in partition.entries:
        a = partition.image_base + e.dev_offset
        if a < start + len(image) and a + e.length > start:
            raise FirmwareError(f"the image {e.name} covers the hibernation area; the repair is not safe")
    buf = bytearray(out.to_bytes())
    last_end = max(e.dev_offset + e.length for e in partition.entries)
    stale_start = partition.image_base + (last_end + 0x7FF) // 0x800 * 0x800
    stale_end = start + len(image)
    if stale_end > len(buf):
        raise FirmwareError("the space after the last image is outside the partition")
    buf[stale_start:stale_end] = bytes(stale_end - stale_start)
    buf[start:start + len(image)] = image
    out = FirmwarePartition(bytes(buf))
    out.add_hibe_entry()
    return out.to_bytes()


def find_hibe_in_backups(directory: str | Path) -> tuple[Path, bytes] | None:
    """Find the newest backup that has the image `hibe`. Give the path and the image.

    The image `hibe` is a snapshot of the memory of the iPod. The iPod writes a new
    snapshot now and then. Thus the newest backup has the newest snapshot. The
    function reads the files in the folder, from the newest to the oldest. The
    function uses the time of the file, not its name.

    The function gives None when no file has the image.
    """
    paths = sorted(Path(directory).glob("*.bin"),
                  key=lambda p: p.stat().st_mtime, reverse=True)
    for path in paths:
        try:
            partition = FirmwarePartition(path.read_bytes())
        except FirmwareError:
            continue
        if partition.has(HIBE_NAME):
            entry = partition.entry(HIBE_NAME)
            return path, bytes(partition.image(HIBE_NAME))
    return None
