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

    BAD_SEEDS = (0, 0x7FFFFFFF, 0x80000001)

    def __init__(self, seed: int, patched: bool = False):
        """With `patched`, the model is the patch shuffle-fixes: a bad seed becomes seed ^ 1 (bug 2)."""
        seed &= 0xFFFFFFFF
        if patched and seed in self.BAD_SEEDS:
            seed ^= 1
        self.state = s32(seed)
        self.patched = patched

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
        """A value in 0 ... n-1. The firmware gives n for 63 states (bug 1).

        With `patched`, the model is the patch shuffle-fixes: n and the
        result are 32-bit (bug 4), and a result of n becomes n-1 (bug 1).
        """
        u = f32(f32(float(self.step())) * 2.0**-31)
        if self.patched:
            p = int(f32(f32(float(n)) * u))
            return n - 1 if p >= n else p
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


def shuffle_albums(tracks, album_of, rng: Random, current=None, inner=False):
    """Albums mode. `tracks` must be in album order (slot 6). `inner` is the settings byte +0x93.

    With +0x93, the firmware also shuffles the tracks of each group in the source copy, then it
    copies the group. The stock firmware swaps with work[j], not work[start + j] (bug 3). A patched
    `rng` gives the corrected index.
    """
    work = list(tracks)
    groups = []                                   # [name, start, end]
    for k, t in enumerate(work):
        name = album_of(t)[:255]
        if groups and name and name == groups[-1][0]:
            groups[-1][2] = k
        else:
            groups.append([name, k, k])
    g = [(start, end) for _, start, end in groups]
    i = len(g)
    while i > 1:
        j = rng.index(i)
        g[j], g[i - 1] = g[i - 1], g[j]
        i -= 1
    if current is not None:
        for k, (start, end) in enumerate(g):
            if current in work[start:end + 1]:
                g[0], g[k] = g[k], g[0]
                break
    out = []
    for start, end in g:
        if inner:
            for k in range(end, start, -1):
                j = rng.index(k - start + 1)
                if rng.patched:
                    j += start
                work[k], work[j] = work[j], work[k]
        out += work[start:end + 1]
    if inner and current is not None and current in out:
        out.remove(current)
        out.insert(0, current)
    return out


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

    # Bug 4: the stock index is negative for n > 32767.
    assert Random(0x12345678).index(50000) < 0

    # The patch: the same order as the stock firmware for 60 tracks.
    rng = Random(0x12345678, patched=True)
    assert shuffle_songs(ids, rng) == songs and rng.state == 0x6C572DB3

    # The patch: the same index as the stock firmware for n <= 32767, except at the 63 bug 1 states.
    gen = Random(0x2468ACE)
    for k in range(20000):
        state = gen.step()
        n = 2 + k % 32766
        a, b = Random(state), Random(state, patched=True)
        sa, sb = a.index(n), b.index(n)
        assert sa == sb or (sa == n and sb == n - 1), (state, n, sa, sb)
    for n in (2, 60, 32767, 50000):
        r = Random(0, patched=True)
        r.step = lambda: 0x7FFFFFC0  # a bug 1 state
        assert r.index(n) == n - 1

    # The patch: a shuffle of 50000 tracks is a permutation, and each index is in 0 ... n-1.
    big = list(range(50000))
    rng = Random(0x12345678, patched=True)
    assert sorted(shuffle_songs(big, rng)) == big
    rng = Random(0x12345678, patched=True)
    for n in range(50000, 1, -1):
        assert 0 <= rng.index(n) < n

    # The patch, bug 2: a bad seed does not stop the generator.
    for seed in Random.BAD_SEEDS:
        r = Random(seed, patched=True)
        states = {r.step() for _ in range(5)}
        assert len(states) == 5 and MODULUS not in states, (hex(seed), states)
    r = Random(0x80000000)
    assert r.step() == 0x7FFFBE58

    # Bug 3: the stock inner album shuffle loses tracks; the patch gives each album as a permutation.
    name = lambda t: f"Test Album {album[t]}"
    lost, seeds = 0, Random(0x2468ACE)
    for _ in range(200):
        seed = seeds.step()
        stock = shuffle_albums(ids, name, Random(seed), inner=True)
        lost += len(set(stock)) < len(ids)
        fixed = shuffle_albums(ids, name, Random(seed, patched=True), current=200 + seed % 57, inner=True)
        assert sorted(fixed) == ids, seed
        assert fixed[0] == 200 + seed % 57
        assert [len({album[t] for t in fixed[k:k + 10]}) for k in range(10, 60, 10)].count(1) >= 4
    assert lost > 0
    # Without +0x93, the patch gives the same album order as the stock firmware.
    assert shuffle_albums(ids, name, Random(0x12345678, patched=True)) == order
    print("All checks pass.")


if __name__ == "__main__":
    check()
