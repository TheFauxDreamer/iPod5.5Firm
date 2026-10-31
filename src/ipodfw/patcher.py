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

A hook with "chain" can share its place with a hook of an earlier patch. The patch gets the
symbol "chain": the previous target, which it calls for all the work that it does not do itself.
A "b" hook also needs "chain_default": the function in the patch that runs the replaced
instruction and continues in the firmware (see chain_target):

        { "kind": "word", "at": "0x66c950", "expect": "0x001919d8", "to": "hook_set", "chain": "set_next" }

"settings_items" adds On/Off items to the Settings menu (Menu 24598, see add_settings_items):

      "settings_items": [ { "key": "0x600060e4", "label_id": "0x7e01", "after_key": "0x60006088" } ]

"menu_items" adds a copy of an item to another menu, for example the Music menu (see add_menu_items):

      "menu_items": [ { "menu_id": 24440, "label_id": "0x7e03", "template_label": "0xff82", "after_label": "0xff82" } ]

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

from . import custom_eq, resources

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
PATCH_AREA_START = 0x7358D0        # a hook that points at or after this address is the hook of a patch
SETTINGS_MENU_ID = 24598
SOUND_CHECK_KEY = 0x600060B7       # the Sound Check item: an On/Off item
OSOS_LIMIT = 0x7F8000               # the same as themeimport.OSOS_LIMIT


# The precompiled object of a patch. If it is in the folder, apply() links it and does not compile.
OBJECT_FILE = "patch.o"


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


def chain_target(h: dict, osos: bytes, patch_symbols: dict[str, int]) -> int:
    """The previous target of a hook with "chain". "word": the word in the firmware ("expect") or the
    address that an earlier patch wrote. "b": "chain_default" if the instruction is "expect", or the
    target of the branch of an earlier patch."""
    at, expect = int(h["at"], 16), int(h["expect"], 16)
    word, = struct.unpack_from("<I", osos, at)
    if h["kind"] == "word":
        if word == expect or word >= PATCH_AREA_START:
            return word
    elif h["kind"] == "b":
        if word == expect:
            if h.get("chain_default") not in patch_symbols:
                raise PatchError(f"hook at {at:#x}: \"chain_default\" must be a global function in the patch")
            return patch_symbols[h["chain_default"]]
        if word & 0xFF000000 == 0xEA000000:
            offset = ((word & 0xFFFFFF) ^ 0x800000) - 0x800000
            target = at + 8 + offset * 4
            if target >= PATCH_AREA_START:
                return target
    else:
        raise PatchError(f"hook at {at:#x}: \"chain\" is possible only for the kinds \"word\" and \"b\"")
    raise PatchError(f"hook at {at:#x}: found {word:#010x}, expected {expect:#010x} or the hook of a patch")


def insert_settings_item(menu: bytes, key: int, label: int, after: int | None,
                         template: int = SOUND_CHECK_KEY) -> bytes:
    """The Settings menu with one more item: a copy of the item `template`, with `key` and `label`,
    after the item `after` (or at the end, if the menu has no such item)."""
    count = struct.unpack_from("<I", menu, 0)[0]
    if len(menu) < 4 + 40 * count:
        raise PatchError("The Settings menu is not complete.")
    items = [bytearray(menu[4 + 40 * i:44 + 40 * i]) for i in range(count)]
    keys = [struct.unpack_from("<I", it, 0x1C)[0] for it in items]
    if key in keys:
        raise PatchError(f"The Settings menu already has an item with the key {key:#x}.")
    if template not in keys:
        raise PatchError("The Settings menu is not the menu of firmware 1.3.")
    item = bytearray(items[keys.index(template)])
    struct.pack_into("<I", item, 0x18, label)
    struct.pack_into("<I", item, 0x1C, key)
    struct.pack_into("<I", item, 0x20, label)
    items.insert(keys.index(after) + 1 if after in keys else len(items), item)
    return struct.pack("<I", len(items)) + b"".join(items)


def add_settings_items(out: bytearray, items: list[dict]) -> int:
    """Add the items to the Settings menu. The menu can be the menu of an earlier build step (for
    example Dark Mode): the resource table entry gives its place. The new menu goes after the end of
    `out`, and the table entry then points to it. Returns the address of the new menu."""
    main = resources.main_block(resources.scan(bytes(out)))
    res = next((r for r in main.resources if r.type == "Menu" and r.id == SETTINGS_MENU_ID), None)
    if res is None:
        raise PatchError("The firmware has no Settings menu (Menu 24598).")
    menu = bytes(out[main.abs(res):main.abs(res) + res.size])
    for item in items:
        after = int(item["after_key"], 16) if "after_key" in item else None
        template = int(item.get("template_key", hex(SOUND_CHECK_KEY)), 16)
        menu = insert_settings_item(menu, int(item["key"], 16), int(item["label_id"], 16), after, template)
    menu_at = extended_base(bytes(out))
    size = menu_at + len(menu)
    if size > OSOS_LIMIT:
        raise PatchError("No space for the Settings menu.")
    out += bytes(size - len(out))
    out[menu_at:menu_at + len(menu)] = menu
    struct.pack_into("<II", out, res.table_pos + 4, menu_at - main.data_start, len(menu))
    return menu_at


def _label(item: bytes) -> int:
    return struct.unpack_from("<H", item, 0x18)[0]


def insert_menu_item(menu: bytes, label: int, template: int, after: int | None, key: int | None = None) -> bytes:
    """The menu with one more item: a copy of the item with the label `template`, with the label
    `label`, after the item with the label `after` (or at the end). Labels are 16-bit string IDs.
    `key` replaces the 32-bit value at +0x1c (the settings key of an item in a Settings list)."""
    count = struct.unpack_from("<I", menu, 0)[0]
    if len(menu) < 4 + 40 * count:
        raise PatchError("The menu is not complete.")
    items = [bytearray(menu[4 + 40 * i:44 + 40 * i]) for i in range(count)]
    labels = [_label(it) for it in items]
    if label in labels:
        raise PatchError(f"The menu already has an item with the label {label:#x}.")
    if template not in labels:
        raise PatchError(f"The menu has no item with the label {template:#x}.")
    item = bytearray(items[labels.index(template)])
    struct.pack_into("<H", item, 0x18, label)
    struct.pack_into("<H", item, 0x20, label)
    if key is not None:
        struct.pack_into("<I", item, 0x1C, key)
    items.insert(labels.index(after) + 1 if after in labels else len(items), item)
    return struct.pack("<I", len(items)) + b"".join(items)


def add_menu_items(out: bytearray, items: list[dict]) -> list[int]:
    """Add the items to their menus, as add_settings_items does. Returns the addresses of the new menus."""
    placed = []
    for menu_id in dict.fromkeys(int(i["menu_id"]) for i in items):
        main = resources.main_block(resources.scan(bytes(out)))
        res = next((r for r in main.resources if r.type == "Menu" and r.id == menu_id), None)
        if res is None:
            raise PatchError(f"The firmware has no Menu {menu_id}.")
        menu = bytes(out[main.abs(res):main.abs(res) + res.size])
        for item in (i for i in items if int(i["menu_id"]) == menu_id):
            after = int(item["after_label"], 16) if "after_label" in item else None
            key = int(item["key"], 16) if "key" in item else None
            menu = insert_menu_item(menu, int(item["label_id"], 16), int(item["template_label"], 16), after, key)
        menu_at = extended_base(bytes(out))
        size = menu_at + len(menu)
        if size > OSOS_LIMIT:
            raise PatchError(f"No space for Menu {menu_id}.")
        out += bytes(size - len(out))
        out[menu_at:menu_at + len(menu)] = menu
        struct.pack_into("<II", out, res.table_pos + 4, menu_at - main.data_start, len(menu))
        placed.append(menu_at)
    return placed


def padded(osos: bytes) -> bytes:
    """The image with zeros to the next multiple of 0x800 bytes, as in Apple's file."""
    return bytes(osos) + bytes((len(osos) + 0x7FF) // 0x800 * 0x800 - len(osos))


def apply_all(osos: bytes, patch_dirs: list, original_sha256: str | None = None) -> bytes:
    """Apply several patches, as the app does: each one starts after the code, the variables and the
    menus of the patch before it (16-byte steps). Only the result is rounded to 0x800 bytes."""
    names = {json.loads((Path(d) / "patch.json").read_text())["name"] for d in patch_dirs}
    for d in patch_dirs:
        spec = json.loads((Path(d) / "patch.json").read_text())
        for need in spec.get("needs", []):
            if need not in names:
                raise PatchError(f'the patch "{spec["name"]}" needs the patch "{need}"')
    original = original_sha256 or hashlib.sha256(osos).hexdigest()
    out = bytes(osos)
    for d in patch_dirs:
        out, _ = apply(out, d, PATCH_AREA_END, original_sha256=original, pad=False)
    return padded(out)


def set_options(spec: dict, values: dict[str, int], code: bytearray, base: int, table: dict[str, int]) -> None:
    """Write the selected value of each option ("options" in patch.json) into its variable in the code.

    A missing value uses "default", or the first choice.
    """
    for o in spec.get("options", []):
        choices = [c["value"] for c in o["choices"]]
        value = values.get(o["id"], o.get("default", choices[0] if choices else 0))
        if value not in choices:
            raise PatchError(f"option {o['id']!r} has no choice with the value {value}")
        at = table.get(o["symbol"])
        if at is None or at < base or at - base + 4 > len(code) or at & 3:
            raise PatchError(f"option {o['id']!r}: {o['symbol']} is not a global 32-bit variable of the patch")
        struct.pack_into("<I", code, at - base, value & 0xFFFFFFFF)
    editor = spec.get("eq_editor")
    if editor:
        data, mask = custom_eq.records(custom_eq.bands_from_options(values), values.get("precut") == 1)
        at, mask_at = table.get(editor["records"]), table.get(editor["mask"])
        if at is None or mask_at is None or at < base or at - base + len(data) > len(code) \
                or mask_at < base or mask_at - base + 4 > len(code):
            raise PatchError(f"eq_editor of {spec['name']!r}: the variables are not in the patch")
        code[at - base:at - base + len(data)] = data
        struct.pack_into("<I", code, mask_at - base, mask)


def apply(osos: bytes, patch_dir: str | Path, max_size: int, load_address: int | None = None,
          symbols: dict[str, int] | None = None, original_sha256: str | None = None,
          options: dict[str, int] | None = None, pad: bool = True) -> tuple[bytes, dict]:
    """Return (patched osos, report). `max_size` is the largest size the osos image can have.

    With `pad`, the result is rounded to 0x800 bytes. Without it, the image ends at the last byte
    of the patch (code, variables and menus), so that the next patch can start there (apply_all).

    `load_address` replaces the address in patch.json. `symbols` adds addresses that the build
    decides (for example the address of a table that the build puts in the osos image).
    `original_sha256` is the SHA-256 of the osos before other changes (pictures, text, a theme);
    without it, osos itself must be Apple's. `options` gives the selected value of each option, by id.
    """
    patch_dir = Path(patch_dir)
    spec = json.loads((patch_dir / "patch.json").read_text())
    if (original_sha256 or hashlib.sha256(osos).hexdigest()) != spec["osos_sha256"]:
        raise PatchError(f"patch {spec['name']!r} is for a different firmware (osos SHA-256 does not agree)")
    sources = sorted(patch_dir.glob("*.c"))
    prebuilt = patch_dir / OBJECT_FILE
    code, table, base = b"", {}, 0
    if sources or prebuilt.exists():
        if load_address is not None:
            base = load_address
        elif spec["load_address"] == EXTENDED:
            base = extended_base(osos)
        else:
            base = int(spec["load_address"], 16)
        fw_syms = {k: int(v, 16) for k, v in spec.get("symbols", {}).items()}
        fw_syms.update(symbols or {})
        if prebuilt.exists():
            # A precompiled patch (a .ipodpatch file): link patch.o, do not compile.
            obj = prebuilt.read_bytes()
        else:
            with tempfile.TemporaryDirectory() as tmp:
                obj = compile_c(sources, Path(tmp))
        chained = [h for h in spec.get("hooks", []) if "chain" in h]
        if chained:
            # The layout does not depend on the symbol values. Thus a first link gives the address of chain_default.
            _, first = link(obj, base, {**fw_syms, **{h["chain"]: 0 for h in chained}})
            for h in chained:
                fw_syms[h["chain"]] = chain_target(h, osos, first)
        code, table = link(obj, base, fw_syms)
        code = bytearray(code)
        set_options(spec, options or {}, code, base, table)
        code = bytes(code)
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
        if old != expect and "chain" not in h:      # chain_target examined a chained hook
            raise PatchError(f"hook at {at:#x}: found {old:#010x}, expected {expect:#010x}")
        target = table.get(h["to"]) if not h["to"].startswith("0x") else int(h["to"], 16)
        if target is None:
            raise PatchError(f"hook target {h['to']!r} is not a global function in the patch")
        new = target if h["kind"] == "word" else branch(h["kind"], at, target)
        struct.pack_into("<I", out, at, new)
    apply_data(out, spec)
    # the code ends at `end`; apply_all and the app round only the final image to 0x800
    size = max(len(osos), end)
    out += bytes(max(0, size - len(out)))
    menu_at = None
    if spec.get("settings_items"):
        out = out[:size]
        menu_at = add_settings_items(out, spec["settings_items"])
        size = len(out)
    menus = []
    if spec.get("menu_items"):
        out = out[:size]
        menus = add_menu_items(out, spec["menu_items"])
        size = len(out)
    report = {"name": spec["name"], "code": [hex(base), hex(end)], "bytes": len(code),
              "map": {k: hex(v) for k, v in sorted(getattr(link, "last_map", {}).items(), key=lambda kv: kv[1])},
              "symbols": {k: hex(v) for k, v in table.items()}, "hooks": len(spec.get("hooks", [])),
              "settings_menu": hex(menu_at) if menu_at is not None else None,
              "menus": [hex(m) for m in menus]}
    result = bytes(out[:size])
    return (padded(result) if pad else result), report
