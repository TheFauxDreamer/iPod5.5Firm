#!/usr/bin/env python3
"""Reference model of the RetailOS 1.3 music shuffle (0x94440). Refer to re/shuffle.md.

Run it to check the model against the emulator results:

    python3 re/shuffle-model.py
"""

import struct

MODULUS = 0x7FFFFFFF


def f32(x: float) -> float:
    """Round a value to IEEE single precision (round to nearest, ties to even)."""
    return struct.unpack("<f", struct.pack("<f", x))[0]


def s32(x: int) -> int:
    x &= 0xFFFFFFFF
    return x - (1 << 32) if x & 0x80000000 else x


def s16(x: int) -> int:
    x &= 0xFFFF
    return x - 0x10000 if x & 0x8000 else x


def cdiv(a: int, b: int) -> int:
    """Signed division that truncates toward zero, as 0x7d024."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


class Random:
    """The generator of 0xe5978: Park-Miller in Schrage form, and a float32 index."""

    def __init__(self, seed: int):
        self.state = s32(seed)

    @staticmethod
    def seed_from(a: int, b: int) -> int:
        """The seed of 0x55c from two reads A and B of the counter at 0x60006038."""
        return (a ^ (b << 16)) & 0xFFFFFFFF

    def step(self) -> int:
        s = self.state
        q = cdiv(s, 127773)
        r = s - q * 127773
        v = s32(16807 * r - 2836 * q)
        if v < 1:
            v = s32(v + MODULUS)
        self.state = v
        return v

    def index(self, n: int) -> int:
        """A value in 0 ... n-1. The firmware gives n for 63 states (bug 1)."""
        u = f32(f32(float(self.step())) * 2.0**-31)
        p = f32(f32(float(s16(n))) * u)
        return s16(int(p))


def shuffle_songs(tracks, rng: Random, current=None):
    """Songs mode: shuffle the full list, then put the current track first."""
    a = list(tracks)
    i = len(a)
    while i > 1:
        j = rng.index(i)
        a[j], a[i - 1] = a[i - 1], a[j]
        i -= 1
    if current is not None and current in a:
        a.remove(current)
        a.insert(0, current)
    return a


def shuffle_albums(tracks, album_of, rng: Random, current=None):
    """Albums mode with +0x93 = 0. `tracks` must be in album order (slot 6)."""
    groups = []
    for t in tracks:
        name = album_of(t)[:255]
        if groups and name and name == groups[-1][0]:
            groups[-1][1].append(t)
        else:
            groups.append([name, [t]])
    g = [members for _, members in groups]
    i = len(g)
    while i > 1:
        j = rng.index(i)
        g[j], g[i - 1] = g[i - 1], g[j]
        i -= 1
    if current is not None:
        for k, members in enumerate(g):
            if current in members:
                g[0], g[k] = g[k], g[0]
                break
    return [t for members in g for t in members]


def check():
    ids = list(range(197, 257))
    album = {t: (t - 197) // 10 + 1 for t in ids}

    # Emulator, Shuffle Songs, seed 0x12345678 (re/shuffle.md, "Emulator tests").
    rng = Random(0x12345678)
    songs = shuffle_songs(ids, rng)
    assert songs[:8] == [224, 207, 248, 232, 238, 246, 243, 203], songs[:8]
    assert rng.state == 0x6C572DB3, hex(rng.state)

    # Emulator, Settings > Shuffle > Albums, then Shuffle Songs, seed 0x12345678.
    rng = Random(0x12345678)
    order = shuffle_albums(ids, lambda t: f"Test Album {album[t]}", rng)
    assert [album[order[k]] for k in range(0, 60, 10)] == [5, 1, 6, 4, 3, 2]
    assert rng.state == 0x1F0E9102, hex(rng.state)

    # Bug 2: these seeds stop the generator at 0x7fffffff.
    for seed in (0, 0x7FFFFFFF, 0x80000001):
        r = Random(seed)
        r.step()
        assert r.state == MODULUS
    # Bug 1: 0x7fffffc0 is the first state that gives the index n.
    def index_at(state, n):
        return int(f32(float(n) * f32(f32(float(state)) * 2.0**-31)))
    assert index_at(0x7FFFFFBF, 60) == 59
    assert index_at(0x7FFFFFC0, 60) == 60
    print("All checks pass.")


if __name__ == "__main__":
    check()
