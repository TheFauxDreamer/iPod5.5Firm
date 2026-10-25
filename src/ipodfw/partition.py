"""Parse and rebuild the iPod firmware partition.

Layout (ported from Rockbox utils/ipodpatcher/ipodpatcher.c, verified
against Apple's iPod_25.1.3.ipsw):

    0x000  Apple "STOP" copyright banner
    0x100  "]ih[" magic
    0x104  u32 LE: directory offset - 0x200
    0x10a  u16 LE: partition format version (3 on the Video)
    dir    40-byte entries: dev[4] type[4] id devOffset len addr
           entryOffset chksum vers loadAddr (all u32 LE)

Image data lives at ``image_base + devOffset`` where ``image_base`` is one
device sector (512 or 2048 bytes). Apple's 1.3 file uses 2048; rather than
guessing, we pick the base at which the osos checksum verifies.

The directory checksum is a plain 32-bit sum of the image bytes (the
model number is only added for Rockbox ``.ipod`` file headers).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

STOP_SIGN_PREFIX = b"{{~~  /-----\\   "
MAGIC = b"]ih["
ENTRY_FMT = "<4s4s8I"
ENTRY_SIZE = struct.calcsize(ENTRY_FMT)  # 40
DEVICE_TAGS = (b"!ATA", b"DNAN")
IMAGE_BASE_CANDIDATES = (2048, 512, 1024, 4096, 0)
IMAGE_ALIGN = 0x800         # images start at a multiple of 2048 bytes (as in Apple's files)

# The gap between the end of the image aupd and the start of the hibernation area.
# The research measured the gap in the backups of the owner. The gap is the same in
# all of them. Refer to re/firmware-hibe.md.
HIBE_GAP = 0x1000
# The size of the header of a hibernation snapshot. The memory image starts after it.
HIBE_HEADER = 0x800
# The name of the hibernation image in the directory.
HIBE_NAME = "hibe"

# The type field is stored byte-reversed on disk ("soso" == "osos").
IMAGE_NAMES = {b"soso": "osos", b"crsr": "rsrc", b"dpua": "aupd", b"kbso": "osbk", b"ebih": "hibe"}

# ipodpatcher getmodel(): (vers >> 8) -> model
MODELS = {
    0x01: "1st/2nd Generation", 0x02: "3rd Generation", 0x40: "Mini 1G",
    0x50: "4th Generation", 0x60: "Photo/Color", 0x70: "Mini 2G",
    0xC0: "Nano 1G", 0xB0: "Video (5G/5.5G)",
}


class FirmwareError(Exception):
    pass


def samsung_image_header(data: bytes | bytearray) -> str | None:
    """The image header tag if `data` is the firmware of an iPod with a Samsung CPU.

    The iPod classic and the iPod nano 3G and later use 4096-byte sectors, thus the directory is at
    the value at 0x104 + 0x1000, not + 0x200. Their osos starts with an "87xx" image header (for
    example "8702"). The body is encrypted and signed, so ipodfw cannot change it. Refer to
    re/ipod-classic-6g.md. The result is the tag, "unknown" if the header is not readable, or None.
    """
    if len(data) <= 0x200 or not bytes(data).startswith(STOP_SIGN_PREFIX) or data[0x100:0x104] != MAGIC:
        return None
    p = struct.unpack_from("<I", data, 0x104)[0] + 0x200
    if data[p:p + 4] in DEVICE_TAGS:
        return None                      # a directory at the iPod Video position: a PortalPlayer firmware
    p = struct.unpack_from("<I", data, 0x104)[0] + 0x1000
    for _ in range(10):
        if p + ENTRY_SIZE > len(data) or data[p:p + 4] not in DEVICE_TAGS:
            return None
        if data[p + 4:p + 8] == b"soso":
            at = struct.unpack_from("<I", data, p + 12)[0]       # the image header is at devOffset
            tag = bytes(data[at:at + 4])
            if len(tag) == 4 and tag[:2] == b"87" and tag[2:].isdigit():
                return tag.decode("ascii")
            return "unknown"
        p += ENTRY_SIZE
    return None


def samsung_message(header: str) -> str:
    return (f"this firmware is for an iPod classic or an iPod nano 3G or later (Samsung CPU, image header "
            f"\"{header}\"); its firmware is encrypted and signed, and ipodfw cannot change it. "
            "ipodfw supports only the iPod Video (5G/5.5G)")


def checksum(data: bytes | memoryview) -> int:
    return sum(data) & 0xFFFFFFFF


@dataclass
class ImageEntry:
    index: int
    dev: bytes
    type: bytes
    id: int
    dev_offset: int
    length: int
    addr: int
    entry_offset: int
    chksum: int
    vers: int
    load_addr: int

    @property
    def name(self) -> str:
        return IMAGE_NAMES.get(self.type, self.type[::-1].decode("latin1"))

    def pack(self) -> bytes:
        return struct.pack(ENTRY_FMT, self.dev, self.type, self.id, self.dev_offset,
                           self.length, self.addr, self.entry_offset, self.chksum,
                           self.vers, self.load_addr)


class FirmwarePartition:
    """An in-memory firmware partition (an Apple Firmware-* file or a device dump)."""

    def __init__(self, data: bytes | bytearray):
        self.data = bytearray(data)
        if not self.data.startswith(STOP_SIGN_PREFIX):
            raise FirmwareError("missing Apple STOP banner: not an iPod firmware partition")
        if self.data[0x100:0x104] != MAGIC:
            raise FirmwareError("bad firmware directory magic (expected ']ih[')")
        self.format_version = struct.unpack_from("<H", self.data, 0x10A)[0]
        self.dir_offset = struct.unpack_from("<I", self.data, 0x104)[0] + 0x200
        self.entries = self._read_directory()
        if not any(e.name == "osos" for e in self.entries):
            header = samsung_image_header(self.data)
            raise FirmwareError(samsung_message(header) if header else "no osos image in directory")
        self.image_base = self._detect_image_base()

    def _read_directory(self) -> list[ImageEntry]:
        entries = []
        p = self.dir_offset
        while p + ENTRY_SIZE <= len(self.data) and self.data[p:p + 4] in DEVICE_TAGS and len(entries) < 10:
            entries.append(ImageEntry(len(entries), *struct.unpack_from(ENTRY_FMT, self.data, p)))
            p += ENTRY_SIZE
        return entries

    def _detect_image_base(self) -> int:
        osos = self.entry("osos")
        for base in IMAGE_BASE_CANDIDATES:
            start = base + osos.dev_offset
            if start + osos.length <= len(self.data) and checksum(self.data[start:start + osos.length]) == osos.chksum:
                return base
        raise FirmwareError("osos checksum does not verify at any known image base; file is corrupt or truncated")

    # -- queries -----------------------------------------------------------

    @property
    def model(self) -> str:
        return MODELS.get(self.entry("osos").vers >> 8, f"unknown (0x{self.entry('osos').vers:x})")

    def entry(self, name: str) -> ImageEntry:
        for e in self.entries:
            if e.name == name:
                return e
        raise FirmwareError(f"no {name} image")

    def has(self, name: str) -> bool:
        return any(e.name == name for e in self.entries)

    def image_range(self, name: str) -> tuple[int, int]:
        e = self.entry(name)
        start = self.image_base + e.dev_offset
        return start, start + e.length

    def image(self, name: str) -> bytes:
        start, end = self.image_range(name)
        return bytes(self.data[start:end])

    def apple_os_length(self) -> int:
        """Length of Apple's own code in osos (excludes an appended Rockbox bootloader)."""
        e = self.entry("osos")
        return e.entry_offset or e.length

    def checksum_ok(self, name: str) -> bool:
        start, end = self.image_range(name)
        return checksum(self.data[start:end]) == self.entry(name).chksum

    # -- modification ------------------------------------------------------

    def replace_image(self, name: str, new: bytes) -> None:
        """Replace an image in place, updating len and chksum. aupd is refused."""
        if name == "aupd":
            raise FirmwareError("refusing to modify aupd: it reflashes the NOR boot flash")
        e = self.entry(name)
        start = self.image_base + e.dev_offset
        limit = self._room_for(e)
        if len(new) > limit:
            raise FirmwareError(f"new {name} ({len(new)} bytes) does not fit in the {limit} bytes available")
        old_end = start + e.length
        self.data[start:start + len(new)] = new
        if len(new) < e.length:
            self.data[start + len(new):old_end] = bytes(old_end - start - len(new))
        e.length = len(new)
        e.chksum = checksum(new)
        self._write_entry(e)

    def make_room(self, osos_length: int) -> None:
        """Move rsrc if an osos of osos_length bytes does not fit before it.

        An iPod partition has free space after its last image: rsrc goes there, and aupd and
        hibe stay where they are. A firmware file has no free space: rsrc and the images after
        it move forward together and the file becomes longer. The content of the images does
        not change. The OS finds each image through the directory.

        An iPod can lose the entry of the image hibe and keep the hibernation area at its
        fixed place. The function then finds the area by the header of the snapshot and parks
        rsrc after the area. Refer to re/firmware-hibe.md.
        """
        osos = self.entry("osos")
        need = osos.dev_offset + osos_length
        later = sorted((e for e in self.entries if e.dev_offset > osos.dev_offset), key=lambda e: e.dev_offset)
        if not later or later[0].dev_offset >= need:
            return
        if later[0].name != "rsrc":
            raise FirmwareError(f"the image after osos is {later[0].name}; only rsrc can move")
        rsrc = later[0]
        data = self.image("rsrc")
        last_end = max(e.dev_offset + e.length for e in self.entries)
        last_end = (last_end + IMAGE_ALIGN - 1) // IMAGE_ALIGN * IMAGE_ALIGN
        if self.image_base + last_end + rsrc.length <= len(self.data):
            # an iPod partition: rsrc goes after the last image, and never over
            # the hibernation area of the iPod.
            at = last_end
            area = self.hibe_area()
            if area is not None:
                after = (area[0] + area[1] + IMAGE_ALIGN - 1) // IMAGE_ALIGN * IMAGE_ALIGN
                at = max(at, after)
            elif any(self.data[self.image_base + last_end:self.image_base + last_end + rsrc.length]):
                raise FirmwareError(
                    "the space after the last image holds data that is not a hibernation "
                    "area; restore the image hibe first")
            if self.image_base + at + rsrc.length > len(self.data):
                raise FirmwareError("there is no space for rsrc after the hibernation area")
            if any(self.data[self.image_base + at:self.image_base + at + rsrc.length]):
                raise FirmwareError("the space after the last image is not empty; rsrc cannot move there")
            self.data[self.image_base + at:self.image_base + at + rsrc.length] = data
            rsrc.dev_offset = at
            self._write_entry(rsrc)
            return
        if self.has("hibe"):
            raise FirmwareError("there is no space for rsrc after the last image, and hibe cannot move")
        if self.image_base + last_end < len(self.data.rstrip(b"\0")):
            raise FirmwareError("the file has data after its last image; the images cannot move")
        # a firmware file: move rsrc and the images after it forward
        delta = (need - rsrc.dev_offset + IMAGE_ALIGN - 1) // IMAGE_ALIGN * IMAGE_ALIGN
        moving = [(e, self.image(e.name)) for e in later]
        self.data.extend(bytes(max(0, self.image_base + last_end + delta - len(self.data))))
        for e, _ in moving:
            start = self.image_base + e.dev_offset
            self.data[start:start + e.length] = bytes(e.length)
        for e, img in moving:
            e.dev_offset += delta
            start = self.image_base + e.dev_offset
            self.data[start:start + e.length] = img
            self._write_entry(e)

    def add_hibe_entry(self) -> None:
        """Write the entry of the image hibe into the directory, without its data.

        The iPod writes the entry of the image hibe itself, through its boot code. The
        iPod can lose the entry and keep the hibernation area. The function writes the
        entry back: the fields come from the healthy partitions of the research, and the
        place and the size come from the hibernation area of this partition. The data of
        the area does not change: the area holds the memory of the iPod. Refer to
        re/firmware-hibe.md.
        """
        if self.has(HIBE_NAME):
            raise FirmwareError("the partition already has the image hibe")
        area = self.hibe_area()
        if area is None:
            raise FirmwareError("the partition has no hibernation area for the image hibe")
        start, length = area
        entry = bytearray(ENTRY_SIZE)
        entry[0:4] = b"!ATA"
        entry[4:8] = b"ebih"
        struct.pack_into("<I", entry, 8, 1)               # the image id
        struct.pack_into("<I", entry, 12, start)          # the place of the image
        struct.pack_into("<I", entry, 16, length)         # the size of the image
        struct.pack_into("<I", entry, 20, 0x10000000)     # the load address in SDRAM
        struct.pack_into("<I", entry, 24, 0)              # the entry point
        struct.pack_into("<I", entry, 28, 0)              # the checksum: the image is not code
        struct.pack_into("<I", entry, 32, 0)              # the version
        struct.pack_into("<I", entry, 36, 0xFFFFFFFF)     # the second load address
        for index in range(10):
            at = self.dir_offset + index * ENTRY_SIZE
            if self.data[at:at + 4] in DEVICE_TAGS:
                continue
            self.data[at:at + ENTRY_SIZE] = entry
            self.entries = self._read_directory()
            return
        raise FirmwareError("the directory of the partition has no free entry")

    def hibe_area(self) -> tuple[int, int] | None:
        """The devOffset range of the hibernation area of this iPod, or None.

        The area is the image hibe when the directory has the entry. Without the entry, the
        area starts at the end of the image aupd with a gap of 0x1000 bytes. A valid header
        of a snapshot gives the size of the area: the version 1, a page size that is a power
        of two of at least 0x1000, and the number of the pages. The size of the area is the
        header of 0x800 bytes plus the memory: the page size times the number of the pages.
        The function gives None when the data there has no such header.

        The research measured the header in the backups of the owner: the page size
        0x20000 and 64 pages on the iPod Video. Refer to re/firmware-hibe.md and
        re/firmware-hibernation.md.
        """
        if self.has(HIBE_NAME):
            e = self.entry(HIBE_NAME)
            return e.dev_offset, e.length
        if not self.has("aupd"):
            return None
        aupd = self.entry("aupd")
        start = aupd.dev_offset + aupd.length + HIBE_GAP
        at = self.image_base + start
        if at + 0x14 > len(self.data):
            return None
        version, page_size, pages = struct.unpack_from("<III", self.data, at)
        if (version != 1 or page_size < 0x1000 or page_size & (page_size - 1)
                or pages == 0 or pages > 128):
            return None
        # The header holds the page size of the disk and the number of the pages of the
        # memory. The area holds one megabyte of memory for each page: the memory of the
        # iPod is 64 MB and the header gives 64 pages of 0x20000 bytes. The research
        # proved this: the image hibe is 0x4000800 bytes and the header gives the pages
        # 64. Refer to re/firmware-hibernation.md, Part 2.
        length = HIBE_HEADER + (pages << 20)
        if at + length > len(self.data):
            return None
        return start, length

    def _room_for(self, e: ImageEntry) -> int:
        following = [o.dev_offset for o in self.entries if o.dev_offset > e.dev_offset]
        end = min(following) if following else len(self.data) - self.image_base
        return end - e.dev_offset

    def _write_entry(self, e: ImageEntry) -> None:
        self.data[self.dir_offset + e.index * ENTRY_SIZE:self.dir_offset + (e.index + 1) * ENTRY_SIZE] = e.pack()

    def to_bytes(self) -> bytes:
        return bytes(self.data)
