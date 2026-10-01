"""Import an iPodWizard theme into a different firmware version.

An iPodWizard theme is a complete firmware partition. Most themes are for firmware 1.2.1.
The import compares the theme with the Apple firmware that it came from ("base"). Then it
applies the changed resources to the target firmware (for example, Apple firmware 1.3).

The result is an iPodFirm theme: a list of byte changes to the target osos. Each change has
the old bytes and the new bytes. Thus, the app can apply the theme or not, and an edit by
the owner stays when the old bytes are different.

Rules for each resource that the theme changed (same block, type and ID in the target):
- BMap: the import copies the picture if the target picture has the same header (format,
  width and height). Otherwise it skips the picture.
- View, Type: the import compares the words (4 bytes) of the base and of the target. It
  changes a word only where the target has the same word as the base.
- Other types, and changes to the code: the import does not apply them.
"""

from __future__ import annotations

import base64
import hashlib
import json
from dataclasses import dataclass, field
from pathlib import Path

from . import resources
from .partition import FirmwarePartition

FORMAT = 1
IMPORTED_TYPES = ("BMap", "View", "Type")
RUN_GAP = 16          # join two changed runs if fewer bytes than this separate them


class ThemeError(Exception):
    pass


@dataclass
class Change:
    resource: str
    offset: int        # in the target osos
    old: bytes
    new: bytes


@dataclass
class Theme:
    name: str
    source_sha256: str
    osos_sha256: str
    changes: list[Change] = field(default_factory=list)
    skipped: list[tuple[str, str]] = field(default_factory=list)   # (resource, reason)
    imported: list[str] = field(default_factory=list)

    def to_json(self) -> str:
        return json.dumps({
            "format": FORMAT,
            "name": self.name,
            "source_sha256": self.source_sha256,
            "osos_sha256": self.osos_sha256,
            "imported": self.imported,
            "skipped": [{"resource": r, "reason": why} for r, why in self.skipped],
            "changes": [{"resource": c.resource, "offset": c.offset,
                         "old": base64.b64encode(c.old).decode(), "new": base64.b64encode(c.new).decode()}
                        for c in self.changes],
        }, indent=1) + "\n"

    @classmethod
    def from_json(cls, text: str) -> "Theme":
        d = json.loads(text)
        if d.get("format") != FORMAT:
            raise ThemeError("This theme file has an unknown format.")
        return cls(d["name"], d["source_sha256"], d["osos_sha256"],
                   [Change(c["resource"], c["offset"], base64.b64decode(c["old"]), base64.b64decode(c["new"]))
                    for c in d["changes"]],
                   [(s["resource"], s["reason"]) for s in d["skipped"]], d["imported"])


def _sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


class _Image:
    """The Apple part of osos and its resources, keyed by (block, type, id)."""

    def __init__(self, fw: FirmwarePartition):
        self.osos = fw.image("osos")
        self.apple_len = fw.apple_os_length()
        self.blocks = resources.scan(self.osos[:self.apple_len])
        main = resources.main_block(self.blocks)
        self.main_index = main.index
        self.res: dict[tuple[str, str, int], tuple[int, int]] = {}
        for b in self.blocks:
            key = "main" if b is main else f"block{b.index}"
            for r in b.resources:
                self.res[(key, r.type, r.id)] = (b.abs(r), r.size)

    def data(self, key) -> bytes:
        pos, size = self.res[key]
        return self.osos[pos:pos + size]


def _words(b: bytes) -> list[int]:
    b = b + bytes(-len(b) % 4)
    return [int.from_bytes(b[i:i + 4], "little") for i in range(0, len(b), 4)]


def _align(a: list[int], b: list[int]) -> dict[int, int]:
    """Map each index of `a` to the index of the same word in `b` (longest common subsequence)."""
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
        # dp[i][j] = length of the common subsequence of a[lo+i:ha] and b[lo+j:hb]
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
    data = b"".join(w.to_bytes(4, "little") for w in out)[:len(target)]
    return data, lost


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


def make_theme(theme_fw: FirmwarePartition, base_fw: FirmwarePartition, target_fw: FirmwarePartition,
               name: str, source_sha256: str = "") -> Theme:
    t, b, n = _Image(theme_fw), _Image(base_fw), _Image(target_fw)
    if t.osos[:t.apple_len] == b.osos[:b.apple_len]:
        raise ThemeError("The theme and the base firmware are the same. Select the Apple firmware that the theme came from.")
    first_t = min(bl.start for bl in t.blocks)
    if len(t.osos) == len(b.osos) and t.osos[:first_t] != b.osos[:first_t]:
        diff = sum(1 for x, y in zip(t.osos[:first_t], b.osos[:first_t]) if x != y)
        if diff > len(t.osos) // 100:
            raise ThemeError("The base firmware is not the firmware that the theme came from.")
    theme = Theme(name, source_sha256, _sha256(n.osos))
    if len(t.osos) == len(b.osos):
        code = sum(1 for x, y in zip(t.osos[:first_t], b.osos[:first_t]) if x != y)
        if code:
            theme.skipped.append(("code", f"The theme changes {code} bytes of program code. "
                                          "Program changes are for one firmware version only."))

    for key in sorted(t.res, key=lambda k: (k[0], k[1], k[2])):
        if key not in b.res:
            continue
        old, new = b.data(key), t.data(key)
        if old == new:
            continue
        label = f"{key[1]} {key[2]}" + ("" if key[0] == "main" else f" ({key[0]})")
        if key[1] not in IMPORTED_TYPES:
            theme.skipped.append((label, f"The import does not change {key[1].strip()} resources."))
            continue
        if key not in n.res:
            theme.skipped.append((label, "The target firmware does not have this resource."))
            continue
        cur = n.data(key)
        pos = n.res[key][0]
        if key[1] == "BMap":
            if len(new) != len(cur) or new[:28] != cur[:28]:
                theme.skipped.append((label, "The picture has a different size or format in the target firmware."))
                continue
            result = new
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
    """Apply the theme to osos. Returns (changes applied, changes not applied because of other edits)."""
    if original_sha256 != theme.osos_sha256:
        raise ThemeError(f"The theme \"{theme.name}\" is for a different firmware.")
    done = conflicts = 0
    for c in theme.changes:
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
