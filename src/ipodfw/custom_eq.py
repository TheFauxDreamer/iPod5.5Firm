"""The coefficients of the patch custom-eq. mac/Sources/IPodFWKit/CustomEQ.swift has the same code.

Refer to re/custom-eq.md for the format of a record.
"""

from __future__ import annotations

import cmath
import math
import struct

BANDS = 5
RATES = (44100, 48000)
LOW_SHELF, PEAK, HIGH_SHELF = 0, 1, 2
Q24 = 1 << 24
GAIN_LIMIT = 120  # tenths of a dB
FREQ_RANGE = (20, 20000)
Q_RANGE = (30, 800)  # hundredths
# The default bands: (type, frequency in Hz, gain in tenths of a dB, Q in hundredths).
DEFAULTS = ((LOW_SHELF, 60, 0, 71), (PEAK, 230, 0, 100), (PEAK, 910, 0, 100), (PEAK, 3600, 0, 100), (HIGH_SHELF, 14000, 0, 71))
GRID = 512


class EQError(ValueError):
    pass


def bands_from_options(values: dict[str, int]) -> list[tuple[int, int, int, int]]:
    """Read the 5 bands from the option values. A missing value uses the default."""
    out = []
    for i, d in enumerate(DEFAULTS, 1):
        out.append((values.get(f"band{i}_type", d[0]), values.get(f"band{i}_freq", d[1]),
                    values.get(f"band{i}_gain", d[2]), values.get(f"band{i}_q", d[3])))
    return out


def check(band: tuple[int, int, int, int]) -> None:
    kind, freq, gain, q = band
    if kind not in (LOW_SHELF, PEAK, HIGH_SHELF):
        raise EQError(f"unknown band type {kind}")
    if not FREQ_RANGE[0] <= freq <= FREQ_RANGE[1]:
        raise EQError(f"the frequency {freq} Hz is out of range")
    if abs(gain) > GAIN_LIMIT:
        raise EQError(f"the gain {gain / 10} dB is out of range")
    if not Q_RANGE[0] <= q <= Q_RANGE[1]:
        raise EQError(f"the Q {q / 100} is out of range")


def biquad(band: tuple[int, int, int, int], rate: int) -> list[float]:
    """Return b0, b1, b2, a1, a2 (Audio EQ Cookbook, R. Bristow-Johnson), with a0 = 1."""
    kind, freq, gain, q = band
    w = 2 * math.pi * freq / rate
    cw, sw = math.cos(w), math.sin(w)
    alpha = sw / (2 * q / 100)
    a = 10 ** (gain / 400)
    if kind == PEAK:
        c = [1 + alpha * a, -2 * cw, 1 - alpha * a, 1 + alpha / a, -2 * cw, 1 - alpha / a]
    else:
        root = 2 * math.sqrt(a) * alpha
        sign = 1 if kind == LOW_SHELF else -1
        c = [a * ((a + 1) - sign * (a - 1) * cw + root),
             2 * sign * a * ((a - 1) - sign * (a + 1) * cw),
             a * ((a + 1) - sign * (a - 1) * cw - root),
             (a + 1) + sign * (a - 1) * cw + root,
             -2 * sign * ((a - 1) + sign * (a + 1) * cw),
             (a + 1) + sign * (a - 1) * cw - root]
    return [c[0] / c[3], c[1] / c[3], c[2] / c[3], c[4] / c[3], c[5] / c[3]]


def response(filters: list[list[float]], freq: float, rate: int) -> float:
    """The gain of a chain of biquads in dB."""
    z = cmath.exp(-2j * math.pi * freq / rate)
    h = 1 + 0j
    for b0, b1, b2, a1, a2 in filters:
        h *= (b0 + b1 * z + b2 * z * z) / (1 + a1 * z + a2 * z * z)
    return 20 * math.log10(max(abs(h), 1e-9))


def peak(filters: list[list[float]], rate: int) -> float:
    """The highest gain in dB of a chain, from 20 Hz to 20 kHz."""
    return max(response(filters, 20 * 1000 ** (i / (GRID - 1)), rate) for i in range(GRID))


def records(bands: list[tuple[int, int, int, int]]) -> tuple[bytes, int]:
    """Return the 200 bytes of custom_eq_records and the value of custom_eq_mask."""
    if len(bands) != BANDS:
        raise EQError(f"the EQ has {BANDS} bands")
    for b in bands:
        check(b)
    mask = sum(1 << i for i, b in enumerate(bands) if b[2] != 0)
    out = [[0] * 10 for _ in range(BANDS)]
    for r, rate in enumerate(RATES):
        filters = {i: biquad(b, rate) for i, b in enumerate(bands) if b[2] != 0}
        cut = 10 ** (-max(peak(list(filters.values()), rate), 0.0) / 20) if filters else 1.0
        for n, (i, f) in enumerate(filters.items()):
            if n == 0:  # the precut: the numerator of the first active band
                f = [x * cut for x in f[:3]] + f[3:]
            q = [round(x * Q24) for x in f]
            if not (q[4] < Q24 and abs(q[3]) < Q24 + q[4]):
                raise EQError(f"the band {i + 1} is not stable")
            if any(abs(x) >= 0x7ffffffe for x in q):
                raise EQError(f"the band {i + 1} is out of range")
            out[i][r * 5:r * 5 + 5] = q
    return b"".join(struct.pack("<10i", *row) for row in out), mask
