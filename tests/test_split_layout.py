"""The Split layout theme and its main menu View."""
import importlib.util
import json
import struct
from pathlib import Path

import pytest

from ipodfw.themeimport import Theme, ThemeError, apply_theme, moved_layout, view_elements

ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "themes/layouts/Split.ipodtheme"


def _script():
    spec = importlib.util.spec_from_file_location("home_screen_views", ROOT / "re/home-screen-views.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_theme_has_two_changes_after_the_patch_area():
    theme = Theme.from_json(THEME.read_text())
    assert [c.resource for c in theme.changes] == ["View 24430", "View 24430"]
    assert theme.changes[0].offset == 0x736800
    assert len(theme.changes[1].new) == 8


def test_theme_holds_no_old_bytes():
    data = json.loads(THEME.read_text())
    assert data["format"] == 2
    assert all("old" not in c for c in data["changes"])


def test_theme_holds_no_stock_view_bytes():
    change = Theme.from_json(THEME.read_text()).changes[0]
    assert sum(e["length"] for e in change.copy) == 200
    assert not any(any(change.new[e["at"]:e["at"] + e["length"]]) for e in change.copy)


def test_view_has_the_list_width_cover_and_text():
    module = _script()
    view = Theme.from_json(THEME.read_text()).changes[0].new
    assert struct.unpack_from("<I", view)[0] == 7
    assert struct.unpack_from("<i", view, 76)[0] == -module.PANEL_WIDTH
    elements = view_elements(struct.pack("<I", 5) + view[208:])
    assert [e[2] for e in elements] == ["None", "Str ", "Str ", "Str ", "Str "]
    assert elements[0][3] == -356


def test_text_is_inside_the_screen():
    module = _script()
    view = struct.pack("<I", 5) + Theme.from_json(THEME.read_text()).changes[0].new[208:]
    for p, _, _, _ in view_elements(view)[1:]:
        top = struct.unpack_from("<i", view, p + module.TOP + 8)[0]
        height = struct.unpack_from("<i", view, p + module.BOTTOM + 8)[0]
        assert top + height <= 216


def test_moved_layout_follows_the_data_in_osos():
    theme = Theme.from_json(THEME.read_text())
    osos = bytes(0x73fe1d)
    moved = moved_layout(theme, osos)
    assert moved.changes[0].offset == 0x73fe20
    delta = 0x73fe20 - 0x736800
    old, new = (struct.unpack_from("<I", t.changes[1].new)[0] for t in (theme, moved))
    assert new - old == delta
    assert moved.changes[1].new[4:] == theme.changes[1].new[4:]


def test_dark_layout_uses_the_white_text_style():
    theme = Theme.from_json(THEME.read_text())
    light, dark = (moved_layout(theme, b"", d).changes[0].new for d in (False, True))
    assert light.count(struct.pack("<I", 0x5EA30000)) == 4
    assert dark.count(struct.pack("<I", 0x5E9F0000)) == 4
    assert dark.count(struct.pack("<I", 0x5EA30000)) == 0
    assert len(dark) == len(light)


def test_wrong_firmware_bytes_stop_the_build():
    theme = Theme.from_json(THEME.read_text())
    osos = bytearray(0x736000)
    with pytest.raises(ThemeError):
        apply_theme(theme, osos, theme.osos_sha256)
