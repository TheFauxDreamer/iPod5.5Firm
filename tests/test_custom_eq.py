"""The coefficients of the patch custom-eq."""

import hashlib
import struct

import pytest

from ipodfw import custom_eq as eq

# testCustomEQRecords in IPodFWKitTests.swift has the same value.
GOLDEN = "3b42c6967ea9203f0867f660877a10c744cd9c2a6f9b8f2bb723bd176ecdd8c7"


def row(data: bytes, band: int, rate: int) -> list[float]:
    values = struct.unpack_from("<5i", data, (band * 10 + rate * 5) * 4)
    return [v / eq.Q24 for v in values]


def run(c: list[float], samples: list[int]) -> list[int]:
    """The loop of 0x7163b0 for one channel, with the shifts of 0x7164c8 and 0x7164e8."""
    q = [round(v * eq.Q24) for v in c]
    x1 = x2 = y1 = y2 = 0
    out = []
    for s in samples:
        x = s << 9
        y = (q[0] * x + q[1] * x1 + q[2] * x2 - q[3] * y1 - q[4] * y2) >> 24
        assert -(1 << 31) <= y < 1 << 31
        x2, x1, y2, y1 = x1, x, y1, y
        out.append(max(-32768, min(32767, y >> 9)))
    return out


def test_gain_at_both_rates():
    bands = list(eq.DEFAULTS)
    bands[2] = (eq.PEAK, 910, -60, 100)
    data, mask = eq.records(bands, precut=True)
    assert mask == 1 << 2 and len(data) == 200
    for r, rate in enumerate(eq.RATES):
        assert eq.response([row(data, 2, r)], 910, rate) == pytest.approx(-6, abs=0.1)


def test_precut_keeps_the_peak_at_0_db():
    bands = [(eq.LOW_SHELF, 100, 120, 71), *eq.DEFAULTS[1:]]
    data, mask = eq.records(bands, precut=True)
    assert mask == 1
    assert hashlib.sha256(data).hexdigest() == GOLDEN
    for r, rate in enumerate(eq.RATES):
        assert eq.peak([row(data, 0, r)], rate) == pytest.approx(0, abs=0.05)


def test_no_precut_keeps_the_boost():
    data, _ = eq.records([(eq.LOW_SHELF, 100, 120, 71), *eq.DEFAULTS[1:]])
    for r, rate in enumerate(eq.RATES):
        assert eq.peak([row(data, 0, r)], rate) == pytest.approx(12, abs=0.1)


def test_three_bands_by_default():
    values = {f"band{i}_gain": 30 for i in range(1, 6)}
    assert eq.records(eq.bands_from_options(values))[1] == 0b10101
    assert eq.records(eq.bands_from_options({**values, "all_bands": 1}))[1] == 0b11111


def test_flat_has_no_active_band():
    assert eq.records(list(eq.DEFAULTS)) == (bytes(200), 0)


def test_all_five_bands_are_stable():
    bands = [(eq.LOW_SHELF, 20, 120, 800), (eq.PEAK, 100, 120, 800), (eq.PEAK, 1000, -120, 30),
             (eq.PEAK, 8000, 120, 800), (eq.HIGH_SHELF, 20000, 120, 800)]
    data, mask = eq.records(bands)
    assert mask == 31
    impulse = [32767] + [0] * 300000  # 7 seconds: 20 Hz with Q 8 rings for a long time
    for band in range(5):
        # The loop rounds down, so a low band keeps a small DC value. It must not oscillate.
        tail = run(row(data, band, 0), impulse)[-100:]
        assert max(tail) - min(tail) <= 1 and max(abs(s) for s in tail) <= 500


def test_library_gives_each_active_band_a_filter():
    a = [(eq.LOW_SHELF, 100, 30, 71), *eq.DEFAULTS[1:]]
    b = [(eq.LOW_SHELF, 100, 30, 71), eq.DEFAULTS[1], (eq.PEAK, 1000, 30, 80), *eq.DEFAULTS[3:]]
    rows, entries = eq.library([("Car", a, False), ("Rock", b, False)])
    assert len(rows) == 1000 and len(entries) == 350
    assert entries[0:2] == b"\x03\0" and entries[2:8] == "Car".encode("utf-16-le")
    assert list(entries[64:69]) == [55, 0, 0, 0, 0]
    assert list(entries[70 + 64:70 + 69]) == [56, 0, 57, 0, 0]
    assert rows[:40] == eq.records(a)[0][:40]
    assert rows[80:120] == eq.records(b)[0][80:120]


def test_library_maximum_is_filter_79():
    five = [(eq.PEAK, 100 * (i + 1), 30, 100) for i in range(5)]
    rows, entries = eq.library([(f"E{i}", five, False) for i in range(5)])
    assert len(rows) == 1000 and len(entries) == 350
    assert list(entries[4 * 70 + 64:4 * 70 + 69]) == [75, 76, 77, 78, 79]


def test_library_limits():
    with pytest.raises(eq.EQError):
        eq.library([(f"E{i}", list(eq.DEFAULTS), False) for i in range(6)])
    with pytest.raises(eq.EQError):
        eq.library([("x" * 32, list(eq.DEFAULTS), False)])
    with pytest.raises(eq.EQError):
        eq.library([("", list(eq.DEFAULTS), False)])


@pytest.mark.parametrize("band", [(eq.PEAK, 10, 10, 100), (eq.PEAK, 1000, 130, 100), (eq.PEAK, 1000, 10, 900), (9, 100, 10, 100)])
def test_bad_bands(band):
    with pytest.raises(eq.EQError):
        eq.records([band, *eq.DEFAULTS[1:]])
