#!/usr/bin/env python3
"""Fit the Apple EQ presets to the bands of the Custom EQ editor.

Usage: python3 re/fit-apple-presets.py OSOS.bin

The script reads the filter records of firmware 1.3 from your own osos image (refer to
re/custom-eq.md). For each filter it finds the band with the nearest curve from 20 Hz to 20 kHz.
It prints a Swift table for CustomEQ.applePresets and a Markdown table of the errors.
"""

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))
from ipodfw import custom_eq as eq  # noqa: E402

TABLE = 0x6a1a00
PRESETS = 0x2a9d18
RATE = 44100
NAMES = ("Acoustic", "Bass Booster", "Bass Reducer", "Classical", "Dance", "Deep", "Electronic", "Flat",
         "Hip Hop", "Jazz", "Latin", "Loudness", "Lounge", "Piano", "Pop", "R&B", "Rock", "Small Speakers",
         "Spoken Word", "Treble Booster", "Treble Reducer", "Vocal Booster")
KINDS = (".lowShelf", ".peak", ".highShelf")
FREQS = [20 * 1000 ** (i / 47) for i in range(48)]


def curve(f):
    return [eq.response([f], x, RATE) for x in FREQS]


def error(a, b):
    return max(abs(p - q) for p, q in zip(a, b))


def fit(target):
    """A search on a coarse grid, then small steps from the best point."""
    best = None
    for kind in (eq.LOW_SHELF, eq.PEAK, eq.HIGH_SHELF):
        for step in range(40):
            freq = int(round(20 * 1000 ** (step / 39)))
            for gain in range(-120, 121, 10):
                for q in (40, 50, 71, 100, 141, 200, 300, 500):
                    if gain == 0:
                        continue
                    band = (kind, freq, gain, q)
                    e = error(target, curve(eq.biquad(band, RATE)))
                    if best is None or e < best[0]:
                        best = (e, band)
    e, band = best
    improved = True
    while improved:
        improved = False
        k, f, g, q = band
        for c in ((k, round(f * 1.04), g, q), (k, round(f / 1.04), g, q), (k, f, g + 2, q), (k, f, g - 2, q),
                  (k, f, g + 1, q), (k, f, g - 1, q), (k, f, g, round(q * 1.05)), (k, f, g, round(q / 1.05))):
            if not 20 <= c[1] <= 20000 or c[2] == 0 or abs(c[2]) > 120 or not 30 <= c[3] <= 800:
                continue
            new = error(target, curve(eq.biquad(c, RATE)))
            if new < e - 1e-4:
                e, band, improved = new, c, True
    return band


def main():
    d = Path(sys.argv[1]).read_bytes()
    rows = []
    for n, name in enumerate(NAMES):
        numbers = [int(v) for v in struct.unpack_from("<10f", d, PRESETS + n * 0x28) if v]
        records = [[v / eq.Q24 for v in struct.unpack_from("<5i", d, TABLE + i * 0x28)] for i in numbers]
        bands = sorted((fit(curve(r)) for r in records), key=lambda b: b[1])
        fitted = [eq.biquad(b, RATE) for b in bands]
        worst = max((abs(eq.response(fitted, x, RATE) - eq.response(records, x, RATE)) for x in FREQS), default=0.0)
        rows.append((name, numbers, bands, worst))
    for name, _, bands, _ in rows:
        text = ", ".join(f"Band(kind: {KINDS[k]}, frequency: {f}, gain: {g}, q: {q})" for k, f, g, q in bands)
        print(f'        Preset(name: "{name}", bands: [{text}]),')
    print()
    for name, numbers, bands, worst in rows:
        print(f"| {name} | {', '.join(map(str, numbers)) or '(none)'} | {len(bands)} | {worst:.2f} dB |")


if __name__ == "__main__":
    main()
