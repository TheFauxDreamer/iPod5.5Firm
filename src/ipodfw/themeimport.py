"""Import an iPodWizard theme into a different firmware version.

An iPodWizard theme is a complete firmware partition. Most themes are for firmware 1.2.1.
The import compares the theme with the Apple firmware that it came from ("base"). Then it
applies the changes to the target firmware (for example, Apple firmware 1.3).

The result is an iPodFirm theme: a list of byte changes to the target osos. Each change has
the old bytes and the new bytes. Thus, the app can apply the theme or not, and an edit by
the owner stays when the old bytes are different.

Rules:
- The resources are matched by block, type and ID. Apple moved some IDs between the versions
  (1.2.1 View -279 is 1.3 View -277, Type 14034 is 14037), so the import finds them by their contents.
- BMap: the import copies a picture if the target picture has the same header (format, width
  and height). A picture that the theme made larger needs free space in the target osos.
- Type: the import changes a word (4 bytes) only where the target has the base value.
- View: a View is a count and a list of elements (u32 size - 4, u32 flags, tag, u32 ID, ...).
  The import matches the elements and changes a field only where the target has the base
  value. It translates the resource IDs in the fields.
- Other resource types and program code: the import does not apply them.
- The highlight bar keeps Apple's blue colours (APPLE_HIGHLIGHT). The blue bar is easier to see.
- Edits: the owner can replace a picture of the theme in the app. An edit replaces the theme
  changes in the same bytes. Theme.edits keeps the edits apart from the import.
"""

from __future__ import annotations

import base64
import hashlib
import json
import struct
from dataclasses import dataclass, field, replace
from pathlib import Path

from . import pictures, resources
from .partition import FirmwarePartition

FORMAT = 1
# Format 2 stores, for each change, the SHA-256 of the old bytes in place of
# the old bytes. Thus a theme in format 2 does not store the bytes that it
# replaces, so the app can ship it. Both formats apply the same.
FORMAT_STRIPPED = 2
RUN_GAP = 16              # join two changed runs if fewer bytes than this separate them
ID_SHIFTS = range(-8, 9)  # the IDs of a type move by a small amount between versions
# Element tag -> the resource type that the ID at +12 refers to
ELEMENT_ID_TYPE = {"BMap": "BMap", "Draw": "BMap", "Str ": "Str ", "None": "View"}
# The reset code of RetailOS stops if the end of the OS image is after 8 MB (0x800004).
# A picture that the theme makes larger goes after the current end of osos, below this limit.
# Extended patches ("load_address": "extended") also stay below this limit. The 32 KB below 8 MB
# stay empty as a margin (64 KB before 9 October 2026). Keep the same value in patcher.py.
OSOS_LIMIT = 0x7F8000
# Resources of the target that keep the Apple version: the progress bar in Now Playing (1.3).
# The dark themes make it almost black, so it is not visible.
KEEP_APPLE = {"BMap 24342": "Apple's progress bar stays (the theme makes it almost invisible).",
              "BMap 24343": "Apple's progress bar stays (the theme makes it almost invisible)."}
# The colours of the highlight bar in Apple's Views (element +76 and +80, ABGR). The dark themes
# make the bar dark grey. The owner wants the blue bar, because it is easier to see.
APPLE_HIGHLIGHT = (0xFFD06428, 0xFFE89858)


class ThemeError(Exception):
    pass


@dataclass
class Change:
    resource: str
    offset: int        # in the target osos
    old: bytes
    new: bytes
    old_sha256: str = ""   # format 2: the hash of the old bytes, in place of the old bytes
    # Bytes to take from the firmware at the build: {"at", "length", "source", "sha256"}.
    # The file holds zeros at "at" in `new`. Thus the file holds none of these bytes.
    copy: list[dict] = field(default_factory=list)


@dataclass
class Theme:
    name: str
    source_sha256: str
    osos_sha256: str
    changes: list[Change] = field(default_factory=list)
    skipped: list[tuple[str, str]] = field(default_factory=list)   # (resource, reason)
    imported: list[str] = field(default_factory=list)
    edits: list[Change] = field(default_factory=list)   # pictures that the owner replaced

    def to_json(self, stripped: bool = False) -> str:
        """The theme as JSON. `stripped` writes format 2: each change holds the hash of the
        old bytes in place of the old bytes, and the file holds no byte of the Apple firmware."""
        fmt = FORMAT_STRIPPED if stripped else FORMAT
        def one(c: Change):
            out = {"resource": c.resource, "offset": c.offset, "new": base64.b64encode(c.new).decode()}
            if c.copy:
                out["copy"] = c.copy
            if stripped and c.old:
                out["old_sha256"] = c.old_sha256 or _sha256(c.old)
            elif stripped:
                out["old_sha256"] = ""            # the change has no old bytes (data after the end of osos)
            else:
                out["old"] = base64.b64encode(c.old).decode()
            return out
        return json.dumps({
            "format": fmt,
            "name": self.name,
            "source_sha256": self.source_sha256,
            "osos_sha256": self.osos_sha256,
            "imported": self.imported,
            "skipped": [{"resource": r, "reason": why} for r, why in self.skipped],
            "changes": [one(c) for c in self.changes],
            "edits": [one(c) for c in self.edits],
        }, indent=1) + "\n"

    @classmethod
    def from_json(cls, text: str) -> "Theme":
        d = json.loads(text)
        if d.get("format") not in (FORMAT, FORMAT_STRIPPED):
            raise ThemeError("This theme file has an unknown format.")
        def changes(items):
            out = []
            for c in items:
                old = base64.b64decode(c["old"]) if "old" in c else b""
                out.append(Change(c["resource"], c["offset"], old, base64.b64decode(c["new"]),
                                  c.get("old_sha256", ""), c.get("copy", [])))
            return out
        return cls(d["name"], d["source_sha256"], d["osos_sha256"], changes(d["changes"]),
                   [(s["resource"], s["reason"]) for s in d["skipped"]], d["imported"], changes(d.get("edits", [])))

    def effective_changes(self) -> list[Change]:
        """The changes to apply: without KEEP_APPLE, with Apple's highlight colours, and with the edits
        of the owner in place of the theme changes in the same bytes."""
        out = []
        for c in self.changes:
            if c.resource in KEEP_APPLE:            # a theme file from an earlier version
                continue
            if any(c.offset < e.offset + len(e.new) and e.offset < c.offset + len(c.new) for e in self.edits):
                continue
            c = _keep_highlight(c)
            if c.old != c.new:
                out.append(c)
        return out + self.edits

    def with_old_bytes(self, osos: bytes) -> "Theme":
        """The same theme with the old bytes of every change.

        A theme in format 2 holds the hash of the old bytes in place of the old
        bytes. This function takes the old bytes from the firmware and checks
        the hash. A change whose bytes do not agree with the hash becomes old
        bytes that agree with the firmware: the change then counts as a
        conflict, the same as in format 1. The function gives back the same
        object when the theme already holds the old bytes.
        """
        if all(c.old for c in self.changes):
            return self
        out = replace(self)
        out.changes = []
        for c in self.changes:
            if c.old or not c.old_sha256:
                out.changes.append(c)
                continue
            # The old bytes come from the firmware again. A read past the end of
            # osos gives zeros: apply_theme extends osos with zeros before it
            # compares, so the bytes there are zeros.
            hi = c.offset + len(c.new)
            old = bytes(osos[c.offset:min(hi, len(osos))]) + bytes(max(0, hi - max(c.offset, len(osos))))
            if _sha256(old) != c.old_sha256 and c.new:
                # The bytes at the offset are not the old bytes of the change: an edit
                # by the owner sits there, or the change is already applied. The old
                # bytes are not in the file. Set the old bytes to the new bytes with
                # one bit turned over. The sentinel makes the apply step take the
                # same branch as in format 1: done when the firmware already holds
                # the new bytes, a conflict in every other case. The step never
                # writes the change, so the owner's edit stays.
                old = bytes([c.new[0] ^ 0x80]) + c.new[1:]
            out.changes.append(Change(c.resource, c.offset, old, c.new, c.old_sha256, c.copy))
        return out


def _keep_highlight(c: Change) -> Change:
    """The change with Apple's highlight colours where the theme changes them."""
    if not c.resource.startswith("View ") or len(c.old) != len(c.new):
        return c
    new = bytearray(c.new)
    for i in range(-c.offset % 4, len(c.old) - 3, 4):
        if struct.unpack_from("<I", c.old, i)[0] in APPLE_HIGHLIGHT:
            new[i:i + 4] = c.old[i:i + 4]
    return Change(c.resource, c.offset, c.old, bytes(new), c.old_sha256, c.copy)


def _with_copied_bytes(c: Change, osos: bytes) -> Change:
    """The change with the bytes of its "copy" list, taken from osos. A wrong hash stops the build."""
    if not c.copy:
        return c
    new = bytearray(c.new)
    for e in c.copy:
        data = bytes(osos[e["source"]:e["source"] + e["length"]])
        if _sha256(data) != e["sha256"]:
            raise ThemeError(f"{c.resource}: the firmware does not have the expected bytes.")
        new[e["at"]:e["at"] + e["length"]] = data
    return replace(c, new=bytes(new), copy=[])


def _sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


class _Image:
    """The Apple part of osos and its resources, keyed by (block, type, id)."""

    def __init__(self, fw: FirmwarePartition):
        self.osos = fw.image("osos")
        self.apple_len = fw.apple_os_length()
        self.blocks = resources.scan(self.osos[:self.apple_len])
        main = resources.main_block(self.blocks)
        self.main = main
        self.res: dict[tuple[str, str, int], resources.Resource] = {}
        self.block_of: dict[tuple[str, str, int], resources.ResourceBlock] = {}
        for b in self.blocks:
            key = "main" if b is main else f"block{b.index}"
            for r in b.resources:
                self.res[(key, r.type, r.id)] = r
                self.block_of[(key, r.type, r.id)] = b

    def pos(self, key) -> int:
        return self.block_of[key].abs(self.res[key])

    def data(self, key) -> bytes:
        p = self.pos(key)
        return self.osos[p:p + self.res[key].size]


def _label(key) -> str:
    return f"{key[1].strip()} {key[2]}" + ("" if key[0] == "main" else f" ({key[0]})")


def _id_map(base: _Image, target: _Image) -> dict[tuple[str, str, int], tuple[str, str, int]]:
    """Map the resource keys of base to target.

    Apple moved some IDs between the versions (for example Type 14034 in 1.2.1 is 14037 in 1.3).
    Pass 1 maps a resource to the same ID if the data is the same, else to the only resource
    nearby with the same data. Pass 2 maps each other resource with the shift of the nearest
    resource of the same type that pass 1 mapped.
    """
    out = {}
    shifts = sorted((d for d in ID_SHIFTS if d), key=abs)
    for key in base.res:
        data = base.data(key)
        if key in target.res and target.data(key) == data:
            out[key] = key
            continue
        hits = [k2 for d in shifts for k2 in [(key[0], key[1], key[2] + d)]
                if k2 in target.res and target.data(k2) == data]
        if len(hits) == 1:
            out[key] = hits[0]
    mapped: dict[tuple[str, str], list[tuple[int, int]]] = {}
    for key, k2 in out.items():
        mapped.setdefault(key[:2], []).append((key[2], k2[2] - key[2]))
    for key in base.res:
        if key in out or not mapped.get(key[:2]):
            continue
        _id, d = min(mapped[key[:2]], key=lambda m: (abs(m[0] - key[2]), m[0]))
        k2 = (key[0], key[1], key[2] + d)
        if k2 in target.res and (target.data(k2) == base.data(key) or target.res[k2].size == base.res[key].size):
            out[key] = k2
    return out


def _words(b: bytes) -> list[int]:
    b = b + bytes(-len(b) % 4)
    return [int.from_bytes(b[i:i + 4], "little") for i in range(0, len(b), 4)]


def _align(a: list, b: list) -> dict[int, int]:
    """Map each index of `a` to the index of the same item in `b` (longest common subsequence)."""
    pairs: dict[int, int] = {}
    lo = 0
    while lo < len(a) and lo < len(b) and a[lo] == b[lo]:
        pairs[lo] = lo
        lo += 1
    ha, hb = len(a), len(b)
    while ha > lo and hb > lo and a[ha - 1] == b[hb - 1]:
        ha -= 1
        hb -= 1
        pairs[ha] = hb
    m, n = ha - lo, hb - lo
    if m and n:
        dp = [[0] * (n + 1) for _ in range(m + 1)]
        for i in range(m - 1, -1, -1):
            ai, row, nxt = a[lo + i], dp[i], dp[i + 1]
            for j in range(n - 1, -1, -1):
                row[j] = nxt[j + 1] + 1 if ai == b[lo + j] else max(nxt[j], row[j + 1])
        i = j = 0
        while i < m and j < n:
            if a[lo + i] == b[lo + j]:
                pairs[lo + i] = lo + j
                i += 1
                j += 1
            elif dp[i + 1][j] >= dp[i][j + 1]:
                i += 1
            else:
                j += 1
    return pairs


def merge_words(base: bytes, theme: bytes, target: bytes) -> tuple[bytes, int]:
    """Apply the word changes base -> theme to target. Returns (result, words not applied)."""
    bw, tw, nw = _words(base), _words(theme), _words(target)
    out = list(nw)
    where = _align(bw, nw)
    lost = 0
    for i, (old, new) in enumerate(zip(bw, tw)):
        if old == new:
            continue
        if i in where:
            out[where[i]] = new
        else:
            lost += 1
    lost += abs(len(tw) - len(bw))
    return b"".join(w.to_bytes(4, "little") for w in out)[:len(target)], lost


def view_elements(d: bytes) -> list[tuple[int, int, str, int]] | None:
    """(position, size, tag, id) of each element, or None if the data is not a View."""
    out = []
    p = 4
    while p + 16 <= len(d):
        size = struct.unpack_from("<I", d, p)[0] + 4
        if size < 16 or p + size > len(d):
            return None
        out.append((p, size, d[p + 8:p + 12][::-1].decode("latin1"), struct.unpack_from("<h", d, p + 12)[0]))
        p += size
    return out if p == len(d) else None


class _Merger:
    def __init__(self, ids: dict):
        self.ids = ids

    def tr(self, rtype: str, value: int, block: str = "main") -> int:
        """Translate a resource ID from base to target."""
        if value == 0:
            return value
        k = self.ids.get((block, rtype, value))
        return k[2] if k else value

    def fields(self, d: bytes, p: int, size: int, tag: str) -> list[int]:
        """The words of one element, with the resource IDs translated."""
        w = list(struct.unpack_from(f"<{size // 4}I", d, p))
        rtype = ELEMENT_ID_TYPE.get(tag)
        if rtype:
            lo = struct.unpack_from("<h", d, p + 12)[0]
            w[3] = (w[3] & 0xFFFF0000) | (self.tr(rtype, lo) & 0xFFFF)
        if tag == "Str " and size > 88:
            hi = struct.unpack_from("<h", d, p + 86)[0]
            w[21] = (w[21] & 0x0000FFFF) | ((self.tr("Type", hi) & 0xFFFF) << 16)
        return w

    def view(self, base: bytes, theme: bytes, target: bytes) -> tuple[bytes, int]:
        be, te, ne = view_elements(base), view_elements(theme), view_elements(target)
        if be is None or te is None or ne is None:
            raise ThemeError("not a View")
        if len(be) != len(te) or any(x[1] != y[1] for x, y in zip(be, te)):
            raise ThemeError("the theme changes the structure of this View")
        if [x[1:3] for x in be] == [x[1:3] for x in ne]:
            where = {i: i for i in range(len(be))}
        else:
            where = _align([(x[1], x[2], self.tr(ELEMENT_ID_TYPE.get(x[2], ""), x[3])) for x in be],
                           [(x[1], x[2], x[3]) for x in ne])
        out = bytearray(target)
        lost = 0
        for i, ((p, size, tag, _), (q, _s, ttag, _i)) in enumerate(zip(be, te)):
            bw = self.fields(base, p, size, tag)
            tw = self.fields(theme, q, size, ttag)
            if bw == tw:
                continue
            if i not in where:
                lost += sum(1 for x, y in zip(bw, tw) if x != y)
                continue
            r = ne[where[i]][0]
            nw = list(struct.unpack_from(f"<{size // 4}I", target, r))
            for f, (old, new) in enumerate(zip(bw, tw)):
                if old == new:
                    continue
                if nw[f] == old or (f == 3 and old & 0xFFFF0000 == new & 0xFFFF0000
                                    and (nw[f] & 0xFFFF) == (old & 0xFFFF)):
                    nw[f] = new
                else:
                    lost += 1
            struct.pack_into(f"<{size // 4}I", out, r, *nw)
        return bytes(out), lost


def _runs(pos: int, old: bytes, new: bytes, resource: str) -> list[Change]:
    out: list[Change] = []
    i = 0
    while i < len(old):
        if old[i] == new[i]:
            i += 1
            continue
        start = end = i
        while i < len(old) and i - end < RUN_GAP:
            if old[i] != new[i]:
                end = i + 1
            i += 1
        out.append(Change(resource, pos + start, old[start:end], new[start:end]))
    return out


def _smaller_picture(data: bytes) -> bytes:
    """A 4-bit grey copy of an RGB565 picture if each pixel is grey (exact to 1/15), else data."""
    pic = pictures.parse(data, 0)
    if pic is None or pic.depth != 16 or pic.texture_format == 0x1444:
        return data
    img = pictures.decode(data, pic)
    for r, g, b in img.get_flattened_data():
        if not (r == g == b and abs(r - round(r / 17) * 17) <= 8):
            return data
    bpr = (pic.width + 1) // 2
    out = bytearray(struct.pack(pictures.HEADER_FMT, 4, 0, bpr, 4, bytes(8), pic.height, pic.width, bpr * pic.height))
    out += bytes(bpr * pic.height)
    pictures.encode(out, pictures.parse(bytes(out), 0), img.convert("L"))
    return bytes(out)


def make_theme(theme_fw: FirmwarePartition, base_fw: FirmwarePartition, target_fw: FirmwarePartition,
               name: str, source_sha256: str = "", free_area: tuple[int, int] | None = None) -> Theme:
    """Make an iPodFirm theme for target_fw from an iPodWizard theme and the firmware that it came from.

    free_area is a range of the target osos for a picture that the theme made larger. The default
    is the space after the end of osos (where rsrc starts) to OSOS_LIMIT. To use it, the app moves
    rsrc (FirmwarePartition.make_room).
    """
    t, b, n = _Image(theme_fw), _Image(base_fw), _Image(target_fw)
    if t.osos[:t.apple_len] == b.osos[:b.apple_len]:
        raise ThemeError("The theme and the base firmware are the same. Select the Apple firmware that the theme came from.")
    same = sum(1 for k in t.res if k in b.res and t.res[k].size == b.res[k].size)
    if same < len(t.res) * 0.9:
        raise ThemeError("The base firmware is not the firmware that the theme came from.")
    first_t = min(bl.start for bl in t.blocks)
    theme = Theme(name, source_sha256, _sha256(n.osos))
    if len(t.osos) == len(b.osos):
        code = sum(1 for x, y in zip(t.osos[:first_t], b.osos[:first_t]) if x != y)
        if code:
            theme.skipped.append(("code", f"The theme changes {code} bytes of program code. "
                                          "The import does not apply program changes."))
    ids = _id_map(b, n)
    merger = _Merger(ids)
    if free_area is None:
        os_e, rs_e = target_fw.entry("osos"), target_fw.entry("rsrc")
        free_area = (rs_e.dev_offset - os_e.dev_offset, OSOS_LIMIT)
    free = list(free_area)

    for key in sorted(t.res, key=lambda k: (k[0], k[1], k[2])):
        if key not in b.res:
            continue
        old, new = b.data(key), t.data(key)
        if old == new:
            continue
        label = _label(key)
        if key[1] not in ("BMap", "View", "Type"):
            theme.skipped.append((label, f"The import does not change {key[1].strip()} resources."))
            continue
        nkey = ids.get(key)
        if nkey is None:
            theme.skipped.append((label, "The target firmware does not have this resource."))
            continue
        cur = n.data(nkey)
        pos = n.pos(nkey)
        label = _label(nkey)
        if label in KEEP_APPLE:
            theme.skipped.append((label, KEEP_APPLE[label]))
            continue
        changes: list[Change] = []
        if key[1] == "BMap":
            if len(new) == len(cur) and new[:28] == cur[:28]:
                changes = _runs(pos, cur, new, label)
            elif len(new) != len(old):
                blob = _smaller_picture(new)
                at = (free[0] + 3) & ~3
                if at + len(blob) > free[1]:
                    theme.skipped.append((label, "The picture is larger than the free space."))
                    continue
                free[0] = at + len(blob)
                old_area = n.osos[at:at + len(blob)] + bytes(max(0, at + len(blob) - max(at, len(n.osos))))
                changes = [Change(label, at, old_area, blob)]
                r, blk = n.res[nkey], n.block_of[nkey]
                entry = n.osos[r.table_pos:r.table_pos + 12]
                new_entry = entry[:4] + struct.pack("<II", at - blk.data_start, len(blob))
                changes += _runs(r.table_pos, entry, new_entry, label)
            else:
                theme.skipped.append((label, "The picture has a different size or format in the target firmware."))
                continue
        elif key[1] == "View":
            try:
                result, lost = merger.view(old, new, cur)
            except ThemeError as e:
                theme.skipped.append((label, f"The import cannot use this View: {e}."))
                continue
            if lost:
                theme.skipped.append((label, f"{lost} changed fields do not agree with the target firmware."))
            changes = _runs(pos, cur, result, label)
        else:
            result, lost = merge_words(old, new, cur)
            if lost:
                theme.skipped.append((label, f"{lost} changed words do not agree with the target firmware."))
            changes = _runs(pos, cur, result, label)
        if changes:
            theme.changes.extend(changes)
            theme.imported.append(label)
    return theme


def apply_theme(theme: Theme, osos: bytearray, original_sha256: str) -> tuple[int, int]:
    """Apply the theme to osos. Returns (changes applied, changes not applied because of other edits).

    A theme in format 2 holds no old bytes: the hash of the old bytes stands in
    for them. The function takes the old bytes from the firmware again and
    checks the hash, through `with_old_bytes`.
    """
    if original_sha256 != theme.osos_sha256:
        raise ThemeError(f"The theme \"{theme.name}\" is for a different firmware.")
    theme = theme.with_old_bytes(osos)
    done = conflicts = 0
    changes = [_with_copied_bytes(c, osos) for c in theme.effective_changes()]
    end = max((c.offset + len(c.new) for c in changes), default=0)
    if end > len(osos):
        osos.extend(bytes((end + 0x7FF) // 0x800 * 0x800 - len(osos)))
    for c in changes:
        cur = bytes(osos[c.offset:c.offset + len(c.old)])
        if cur == c.old:
            osos[c.offset:c.offset + len(c.new)] = c.new
            done += 1
        elif cur == c.new:
            done += 1
        else:
            conflicts += 1
    return done, conflicts


def load_firmware(path: str | Path) -> tuple[FirmwarePartition, str]:
    """A firmware partition from an .ipsw or from a partition image, and the SHA-256 of the file."""
    from .ipsw import extract_firmware
    p = Path(path)
    raw = p.read_bytes()
    data = extract_firmware(p)[1] if p.suffix.lower() == ".ipsw" else raw
    return FirmwarePartition(data), _sha256(raw)
