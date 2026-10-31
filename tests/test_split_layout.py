"""The Split layout theme and its main menu View."""
import importlib.util
import json
import struct
from pathlib import Path

from ipodfw.themeimport import Theme, view_elements

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
    assert len(theme.changes[1].new) == 12


def test_theme_holds_no_old_bytes():
    data = json.loads(THEME.read_text())
    assert data["format"] == 2
    assert all("old" not in c for c in data["changes"])


def test_view_has_list_cover_and_text():
    view = Theme.from_json(THEME.read_text()).changes[0].new
    elements = view_elements(view)
    assert struct.unpack_from("<I", view)[0] == len(elements) == 7
    assert [e[2] for e in elements] == ["None", "None", "None", "Str ", "Str ", "Str ", "Str "]
    assert elements[1][3] == -288
    assert elements[2][3] == -356


def test_view_edges_are_inside_the_screen():
    module = _script()
    view = Theme.from_json(THEME.read_text()).changes[0].new
    elements = view_elements(view)
    right = struct.unpack_from("<i", view, elements[0][0] + module.RIGHT + 8)[0]
    assert right == -module.PANEL_WIDTH
    for p, _, _, _ in elements[3:]:
        top = struct.unpack_from("<i", view, p + module.TOP + 8)[0]
        height = struct.unpack_from("<i", view, p + module.BOTTOM + 8)[0]
        assert top + height <= 216
