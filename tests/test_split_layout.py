"""The Split layout theme and its main menu View."""
import hashlib
import importlib.util
import json
import struct
from pathlib import Path

import pytest

from ipodfw.themeimport import (Theme, ThemeError, apply_theme, half_width, moved_layout, small_text, view_elements,
                                with_clock)

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


def test_small_text_uses_types_of_size_14():
    theme = Theme.from_json((ROOT / "themes/layouts/Split.ipodtheme").read_text())
    small = small_text(theme)
    view = small.changes[0].new
    assert view.count(struct.pack("<I", 0x5E980000)) == 4
    assert view.count(struct.pack("<I", 0x5EA30000)) == 0
    assert len(view) == len(theme.changes[0].new)
    dark = moved_layout(small, b"", True).changes[0].new
    assert dark.count(struct.pack("<I", 0x5E990000)) == 4
    assert dark.count(struct.pack("<I", 0x5E980000)) == 0


# The SHA-256 of the View at 1/2 width. testSplitLayoutFile in Swift checks the same value.
HALF_WIDTH_VIEW_SHA256 = "748e8964aa99916d1b0dca9d130e58a76e82d6f63ceb99ca590b0444ef884109"


def test_half_width_moves_only_the_edges():
    theme = Theme.from_json(THEME.read_text())
    half = half_width(theme)
    view = half.changes[0].new
    assert len(view) == len(theme.changes[0].new)
    assert [struct.unpack_from("<i", view, at)[0] for at in (76, 256, 280, 352, 376, 464, 488, 560, 584, 656, 680)] == \
        [-160, 186, -27, 164, -6, 164, -6, 164, -6, 164, -6]
    assert hashlib.sha256(view).hexdigest() == HALF_WIDTH_VIEW_SHA256
    assert half.changes[1] == theme.changes[1]
    # The order with the small text does not change the result, and a second call changes nothing.
    assert half_width(small_text(theme)).changes[0].new == small_text(half).changes[0].new
    assert half_width(half).changes[0].new == view


# The SHA-256 of the View at 1/2 width with the clock lines. testSplitLayoutFile in Swift checks the same value.
HALF_WIDTH_CLOCK_VIEW_SHA256 = "8805963c20cb4f2cf2e8012762d11b302dddb03ac1e5f7028ff7fca0e94424dd"


def test_clock_adds_three_lines_after_the_panel():
    theme = Theme.from_json(THEME.read_text())
    clock = with_clock(theme)
    view = clock.changes[0].new
    assert len(view) == 704 + 3 * 96
    assert view[:4] == struct.pack("<I", 10) and view[4:704] == theme.changes[0].new[4:704]
    assert clock.changes[1].new == theme.changes[1].new[:4] + struct.pack("<I", len(view))
    for i, (ident, top) in enumerate(((0x7E41, 72), (0x7E42, 96), (0x7E43, 118))):
        line = view[704 + 96 * i:800 + 96 * i]
        assert struct.unpack_from("<II", line, 8) == (0x53747220, ident)
        assert struct.unpack_from("<i", line, 36)[0] == top
        assert line[40:] == view[456:512]
    # A second call changes nothing. The width must come first: half_width needs the View of 704 bytes.
    assert with_clock(clock).changes[0].new == view
    assert half_width(clock).changes[0].new == view
    half = with_clock(half_width(theme)).changes[0].new
    assert struct.unpack_from("<i", half, 704 + 48)[0] == 164
    assert hashlib.sha256(half).hexdigest() == HALF_WIDTH_CLOCK_VIEW_SHA256


def test_clock_lines_get_the_dark_and_small_text():
    theme = with_clock(Theme.from_json(THEME.read_text()))
    assert moved_layout(theme, b"", True).changes[0].new.count(struct.pack("<I", 0x5E9F0000)) == 7
    small = with_clock(small_text(Theme.from_json(THEME.read_text()))).changes[0].new
    assert small.count(struct.pack("<I", 0x5E980000)) == 7
    moved = moved_layout(theme, bytes(0x73fe1d))
    assert moved.changes[1].new[4:] == struct.pack("<I", 992)
