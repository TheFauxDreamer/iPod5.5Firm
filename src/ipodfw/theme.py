"""Unpack osos resources to an editable folder and repack them."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image

from . import pictures, resources
from .partition import FirmwarePartition

MANIFEST = "manifest.json"
SAMPLE_STRING_ID = "129"  # "January" in every language block


def _osos_work(fw: FirmwarePartition) -> tuple[bytearray, int]:
    """Apple's part of osos (any appended Rockbox bootloader is left alone)."""
    osos = bytearray(fw.image("osos"))
    return osos, fw.apple_os_length()


def list_pictures(osos: bytes, block: resources.ResourceBlock) -> list[tuple[int, resources.Resource, pictures.Picture]]:
    out = []
    for n, r in enumerate(block.of_type("BMap")):
        pic = pictures.parse(osos, block.abs(r))
        if pic:
            out.append((n, r, pic))
    return out


def unpack(fw: FirmwarePartition, outdir: Path) -> dict:
    osos, apple_len = _osos_work(fw)
    blocks = resources.scan(bytes(osos[:apple_len]))
    main = resources.main_block(blocks)
    (outdir / "pictures").mkdir(parents=True, exist_ok=True)
    (outdir / "strings").mkdir(parents=True, exist_ok=True)

    manifest = {
        "osos_sha256": hashlib.sha256(osos).hexdigest(),
        "model": fw.model,
        "pictures": [],
        "string_blocks": [],
    }
    for n, r, pic in list_pictures(osos, main):
        name = f"pictures/{n:04d}_{r.id}.png"
        pictures.decode(osos, pic).save(outdir / name)
        manifest["pictures"].append({"index": n, "id": r.id, "file": name, "format": pic.format_name,
                                     "width": pic.width, "height": pic.height})
    for b in blocks:
        if not b.of_type("Str "):
            continue
        strings = resources.read_strings(osos, b)
        tag = "main" if b is main else "lang"
        name = f"strings/block{b.index:02d}_{tag}.json"
        (outdir / name).write_text(json.dumps(strings, ensure_ascii=False, indent=1) + "\n")
        manifest["string_blocks"].append({"block": b.index, "file": name, "count": len(strings),
                                          "sample": strings.get(SAMPLE_STRING_ID, "")})
    (outdir / MANIFEST).write_text(json.dumps(manifest, indent=1, ensure_ascii=False) + "\n")
    return manifest


@dataclass
class RepackReport:
    pictures_changed: list[str] = field(default_factory=list)
    string_blocks_changed: list[str] = field(default_factory=list)

    @property
    def changed(self) -> bool:
        return bool(self.pictures_changed or self.string_blocks_changed)


def repack(fw: FirmwarePartition, workdir: Path, force: bool = False) -> RepackReport:
    """Apply edited PNGs / string JSON from workdir to fw (in memory)."""
    manifest = json.loads((workdir / MANIFEST).read_text())
    osos, apple_len = _osos_work(fw)
    if manifest["osos_sha256"] != hashlib.sha256(osos).hexdigest() and not force:
        raise resources.ResourceError(
            "this folder was unpacked from a different firmware; repack onto the same file "
            "it came from (or pass --force)")
    blocks = resources.scan(bytes(osos[:apple_len]))
    main = resources.main_block(blocks)
    pics = {n: pic for n, _r, pic in list_pictures(osos, main)}
    by_index = {b.index: b for b in blocks}

    report = RepackReport()
    for entry in manifest["pictures"]:
        path = workdir / entry["file"]
        if not path.exists():
            continue
        with Image.open(path) as img:
            if pictures.encode(osos, pics[entry["index"]], img):
                report.pictures_changed.append(entry["file"])
    for entry in manifest["string_blocks"]:
        path = workdir / entry["file"]
        if not path.exists():
            continue
        new = json.loads(path.read_text())
        if resources.write_strings(osos, by_index[entry["block"]], new):
            report.string_blocks_changed.append(entry["file"])

    if report.changed:
        fw.replace_image("osos", bytes(osos))
    return report
