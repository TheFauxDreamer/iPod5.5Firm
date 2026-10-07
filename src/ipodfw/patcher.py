"""Compile, link and apply code patches to the osos image.

A patch is a folder that contains `patch.json` and one or more C files:

    {
      "name": "...",
      "osos_sha256": "<sha256 of the unpatched osos image>",
      "load_address": "0x735900",
      "symbols":   { "label_draw": "0x244924", ... },        # firmware functions for the C code
      "hooks": [
        { "kind": "bl",   "at": "0x1bb434", "expect": "0xeb0224ba", "to": "hook_label_draw" },
        { "kind": "word", "at": "0x677a14", "expect": "0x00244924", "to": "hook_label_draw" }
      ]
    }

A patch can also change data. Both sections are optional:

      "bytes":   [ { "at": "0x4baa76", "expect": "fffe", "value": "003c" } ],   # hexadecimal bytes
      "strings": { "24": { "-140": "60 Seconds" } }                            # block index -> id -> text

A patch with no C file has no code, and then it needs no "load_address".

The C code is compiled with Xcode clang for an ARM7TDMI (ARMv4T, ARM state). A small linker
in this file puts .text, .rodata and .data at `load_address` and resolves the relocations.
The code must fit in the space after the original image: the osos image can grow to the start
of the next image (0x736800 bytes in firmware 1.3), and that area must be zero in the original.
"""

from __future__ import annotations

import hashlib
import json
import struct
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

from . import resources

CLANG_FLAGS = ["--target=armv4t-none-eabi", "-mcpu=arm7tdmi", "-marm", "-mfloat-abi=soft", "-O2",
               "-ffreestanding", "-fno-builtin", "-fno-pic", "-fno-exceptions", "-fno-unwind-tables",
               "-fno-asynchronous-unwind-tables", "-fno-stack-protector", "-ffunction-sections",
               "-fdata-sections", "-nostdlib", "-Wall", "-Werror", "-c"]

R_ARM_NONE, R_ARM_ABS32, R_ARM_REL32, R_ARM_CALL, R_ARM_JUMP24, R_ARM_V4BX = 0, 2, 3, 28, 29, 40


# "load_address": "extended": the build puts the patch after all the data that is already there
# (the end of the image, at least PATCH_AREA_END): after a theme, the Dark Mode items and other
# extended patches. The limit is OSOS_LIMIT (themeimport.OSOS_LIMIT). The build must then move rsrc.
EXTENDED = "extended"
PATCH_AREA_END = 0x736800
OSOS_LIMIT = 0x7F0000


def extended_base(osos: bytes) -> int:
    """The load address of an extended patch: after the end of osos, aligned to 16 bytes."""
    return (max(len(osos), PATCH_AREA_END) + 15) & ~15


class PatchError(Exception):
    pass


@dataclass
class Section:
    index: int
    name: str
    kind: int
    flags: int
    offset: int
    size: int
    link: int
    info: int
    align: int
    data: bytes


def parse_elf(blob: bytes):
    if blob[:4] != b"\x7fELF" or blob[4] != 1 or blob[5] != 1:
        raise PatchError("not a 32-bit little-endian ELF file")
    e_shoff, = struct.unpack_from("<I", blob, 0x20)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", blob, 0x2E)
    raw = []
    for i in range(e_shnum):
        name, kind, flags, _addr, off, size, link, info, align, _entsize = struct.unpack_from(
            "<10I", blob, e_shoff + i * e_shentsize)
        raw.append((name, kind, flags, off, size, link, info, align))
    shstr = raw[e_shstrndx]
    names = blob[shstr[3]:shstr[3] + shstr[4]]

    def cname(o: int) -> str:
        return names[o:names.index(b"\0", o)].decode()

    sections = [Section(i, cname(n), k, f, o, s, l, inf, a, blob[o:o + s] if k != 8 else bytes(s))
                for i, (n, k, f, o, s, l, inf, a) in enumerate(raw)]
    return sections


def read_symbols(blob: bytes, sections: list[Section]):
    symtab = next(s for s in sections if s.kind == 2)
    strtab = sections[symtab.link]
    syms = []
    for i in range(0, symtab.size, 16):
        name, value, _size, info, _other, shndx = struct.unpack_from("<IIIBBH", symtab.data, i)
        n = strtab.data[name:strtab.data.index(b"\0", name)].decode()
        syms.append((n, value, info, shndx))
    return syms


def link(obj: bytes, base: int, firmware_symbols: dict[str, int]) -> tuple[bytes, dict[str, int]]:
    """Return (code blob, symbol table) for the object placed at `base`."""
    sections = parse_elf(obj)
    syms = read_symbols(obj, sections)
    alloc = [s for s in sections if s.flags & 0x2 and s.size and s.kind in (1, 8)]   # SHF_ALLOC; PROGBITS or NOBITS
    place: dict[int, int] = {}
    cursor = base
    for s in alloc:
        align = max(s.align, 4)
        cursor = (cursor + align - 1) // align * align
        place[s.index] = cursor
        cursor += s.size
    out = bytearray(cursor - base)
    for s in alloc:
        out[place[s.index] - base:place[s.index] - base + s.size] = s.data

    def sym_addr(i: int) -> int:
        name, value, _info, shndx = syms[i]
        if shndx == 0:
            if name not in firmware_symbols:
                raise PatchError(f"undefined symbol {name!r}: add it to \"symbols\" in patch.json")
            return firmware_symbols[name]
        if shndx not in place:
            raise PatchError(f"symbol {name!r} is in a section that is not loaded")
        return place[shndx] + value

    for rel in (s for s in sections if s.kind == 9):            # SHT_REL
        target = rel.info
        if target not in place:
            continue
        for i in range(0, rel.size, 8):
            r_off, r_info = struct.unpack_from("<II", rel.data, i)
            kind, si = r_info & 0xFF, r_info >> 8
            p = place[target] + r_off
            at = p - base
            word, = struct.unpack_from("<I", out, at)
            if kind in (R_ARM_NONE, R_ARM_V4BX):
                continue
            s_addr = sym_addr(si)
            if kind == R_ARM_ABS32:
                value = (s_addr + word) & 0xFFFFFFFF
            elif kind == R_ARM_REL32:
                value = (s_addr + word - p) & 0xFFFFFFFF
            elif kind in (R_ARM_CALL, R_ARM_JUMP24):
                addend = ((word & 0xFFFFFF) ^ 0x800000) - 0x800000
                offset = s_addr + addend * 4 - p
                if offset & 3 or not -(1 << 25) <= offset < (1 << 25):
                    raise PatchError(f"branch at {p:#x} cannot reach {s_addr:#x}")
                value = (word & 0xFF000000) | ((offset >> 2) & 0xFFFFFF)
            else:
                raise PatchError(f"relocation type {kind} is not supported")
            struct.pack_into("<I", out, at, value)

    table = {n: sym_addr(i) for i, (n, _v, info, shndx) in enumerate(syms)
             if n and shndx != 0 and (info >> 4) == 1 and shndx in place}                 # STB_GLOBAL
    link.last_map = {n: sym_addr(i) for i, (n, _v, info, shndx) in enumerate(syms)
                     if n and shndx in place and (info & 0xF) in (1, 2)}                  # objects and functions
    return bytes(out), table


def branch(op: str, at: int, to: int) -> int:
    offset = to - (at + 8)
    if offset & 3 or not -(1 << 25) <= offset < (1 << 25):
        raise PatchError(f"branch at {at:#x} cannot reach {to:#x}")
    return {"b": 0xEA000000, "bl": 0xEB000000}[op] | ((offset >> 2) & 0xFFFFFF)


def compile_c(sources: list[Path], workdir: Path) -> bytes:
    objs = []
    for src in sources:
        obj = workdir / (src.stem + ".o")
        r = subprocess.run(["clang", *CLANG_FLAGS, str(src), "-o", str(obj)], capture_output=True, text=True)
        if r.returncode:
            raise PatchError(f"compile failed for {src.name}:\n{r.stderr}")
        objs.append(obj)
    if len(objs) != 1:
        raise PatchError("put all patch code in one C file")
    return objs[0].read_bytes()


def apply_data(out: bytearray, spec: dict) -> None:
    """Apply the "bytes" and "strings" sections of a patch to `out`."""
    for e in spec.get("bytes", []):
        at = int(e["at"], 16)
        expect, value = bytes.fromhex(e["expect"]), bytes.fromhex(e["value"])
        if len(expect) != len(value):
            raise PatchError(f"bytes at {at:#x}: \"expect\" and \"value\" have different lengths")
        if out[at:at + len(expect)] != expect:
            raise PatchError(f"bytes at {at:#x}: found {out[at:at + len(expect)].hex()}, expected {expect.hex()}")
        out[at:at + len(value)] = value
    if spec.get("strings"):
        blocks = resources.scan(bytes(out))
        for index, values in spec["strings"].items():
            try:
                resources.write_strings(out, blocks[int(index)], values)
            except (IndexError, resources.ResourceError) as e:
                raise PatchError(f"strings for block {index}: {e}") from e


def apply(osos: bytes, patch_dir: str | Path, max_size: int, load_address: int | None = None,
          symbols: dict[str, int] | None = None, original_sha256: str | None = None) -> tuple[bytes, dict]:
    """Return (patched osos, report). `max_size` is the largest size the osos image can have.

    `load_address` replaces the address in patch.json. `symbols` adds addresses that the build
    decides (for example the address of a table that the build puts in the osos image).
    `original_sha256` is the SHA-256 of the osos before other changes (pictures, text, a theme);
    without it, osos itself must be Apple's.
    """
    patch_dir = Path(patch_dir)
    spec = json.loads((patch_dir / "patch.json").read_text())
    if (original_sha256 or hashlib.sha256(osos).hexdigest()) != spec["osos_sha256"]:
        raise PatchError(f"patch {spec['name']!r} is for a different firmware (osos SHA-256 does not agree)")
    sources = sorted(patch_dir.glob("*.c"))
    code, table, base = b"", {}, 0
    if sources:
        if load_address is not None:
            base = load_address
        elif spec["load_address"] == EXTENDED:
            base = extended_base(osos)
        else:
            base = int(spec["load_address"], 16)
        fw_syms = {k: int(v, 16) for k, v in spec.get("symbols", {}).items()}
        fw_syms.update(symbols or {})
        with tempfile.TemporaryDirectory() as tmp:
            obj = compile_c(sources, Path(tmp))
        code, table = link(obj, base, fw_syms)
    end = base + len(code)
    if load_address is None and spec.get("load_address") == EXTENDED:
        max_size = OSOS_LIMIT
    if end > max_size:
        raise PatchError(f"patch code ends at {end:#x}, but the osos image can only grow to {max_size:#x}")
    out = bytearray(osos) + bytes(max(0, end - len(osos)))
    if any(out[base:end]):
        raise PatchError(f"the area {base:#x}-{end:#x} is not empty in the original firmware")
    out[base:end] = code
    for h in spec.get("hooks", []):
        at = int(h["at"], 16)
        expect = int(h["expect"], 16)
        old, = struct.unpack_from("<I", out, at)
        if old != expect:
            raise PatchError(f"hook at {at:#x}: found {old:#010x}, expected {expect:#010x}")
        target = table.get(h["to"]) if not h["to"].startswith("0x") else int(h["to"], 16)
        if target is None:
            raise PatchError(f"hook target {h['to']!r} is not a global function in the patch")
        new = target if h["kind"] == "word" else branch(h["kind"], at, target)
        struct.pack_into("<I", out, at, new)
    apply_data(out, spec)
    # keep the image size a multiple of 0x800, as in Apple's file
    size = max(len(osos), (end + 0x7FF) // 0x800 * 0x800)
    out += bytes(max(0, size - len(out)))
    report = {"name": spec["name"], "code": [hex(base), hex(end)], "bytes": len(code),
              "map": {k: hex(v) for k, v in sorted(getattr(link, "last_map", {}).items(), key=lambda kv: kv[1])},
              "symbols": {k: hex(v) for k, v in table.items()}, "hooks": len(spec.get("hooks", []))}
    return bytes(out[:size]), report
