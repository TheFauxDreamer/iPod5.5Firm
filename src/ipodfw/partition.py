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
            # an iPod partition: put rsrc after the last image
            if any(self.data[self.image_base + last_end:self.image_base + last_end + rsrc.length]):
                raise FirmwareError("the space after the last image is not empty; rsrc cannot move there")
            self.data[self.image_base + last_end:self.image_base + last_end + rsrc.length] = data
            rsrc.dev_offset = last_end
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

    def _room_for(self, e: ImageEntry) -> int:
        following = [o.dev_offset for o in self.entries if o.dev_offset > e.dev_offset]
        end = min(following) if following else len(self.data) - self.image_base
        return end - e.dev_offset

    def _write_entry(self, e: ImageEntry) -> None:
        self.data[self.dir_offset + e.index * ENTRY_SIZE:self.dir_offset + (e.index + 1) * ENTRY_SIZE] = e.pack()

    def to_bytes(self) -> bytes:
        return bytes(self.data)
