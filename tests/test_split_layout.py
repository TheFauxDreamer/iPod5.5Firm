"""The Split layout theme and its main menu View."""
import importlib.util
import json
import struct
from pathlib import Path

import pytest

from ipodfw.themeimport import Theme, ThemeError, apply_theme, view_elements

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
    assert [(e["at"], e["length"]) for e in change.copy] == [(4, 72), (80, 128)]
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


def test_wrong_firmware_bytes_stop_the_build():
    theme = Theme.from_json(THEME.read_text())
    osos = bytearray(0x736000)
    with pytest.raises(ThemeError):
        apply_theme(theme, osos, theme.osos_sha256)
