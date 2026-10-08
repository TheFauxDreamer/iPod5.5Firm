#!/usr/bin/env python3
"""Converts one track of a MIDI file into a note table for the iPod piezo. Ghidra is not necessary.

Usage: python3 re/midi-to-tones.py FILE.mid TRACK FIRST_BAR LAST_BAR [OCTAVE_SHIFT]

TRACK is the track number (0 is the first track). The bars are numbered from 1, and the program
uses LAST_BAR as the last bar. The program supposes 4 beats in each bar. OCTAVE_SHIFT moves all
notes up (for example 1) or down (for example -1) by octaves.

The piezo plays one note at a time. Thus, if the track has a chord, the program keeps only the
highest note ("skyline"). A note stops at the start of the next note. A time with no note becomes
a rest. The table starts with the first note.

The piezo value is a period: Hz = 91225 / value (see re/piezo.md). A rest has the value 0. The
result is a C table of {value, milliseconds}, with the note name in a comment.
"""
import struct
import sys

PIEZO_CLOCK = 91225          # Hz = PIEZO_CLOCK / value (re/piezo.md)
GAP_MS = 20                  # a short rest between two notes, so that a repeated note is audible
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]


def vlq(b: bytes, i: int) -> tuple[int, int]:
    v = 0
    while True:
        c = b[i]
        i += 1
        v = (v << 7) | (c & 0x7F)
        if c < 0x80:
            return v, i


def read_midi(path: str) -> tuple[int, list[tuple[int, int]], list[list[tuple[int, int, int]]]]:
    """The ticks per beat, the tempo changes (tick, µs per beat) and the notes (start, end, key) of each track."""
    d = open(path, "rb").read()
    if d[:4] != b"MThd":
        raise SystemExit(f"{path} is not a MIDI file.")
    _, count, division = struct.unpack(">HHH", d[8:14])
    if division & 0x8000:
        raise SystemExit("The program cannot read a MIDI file with SMPTE time.")
    p, tempos, tracks = 14, [], []
    for _ in range(count):
        if d[p:p + 4] != b"MTrk":
            raise SystemExit("The MIDI file has a bad track.")
        length = struct.unpack(">I", d[p + 4:p + 8])[0]
        b = d[p + 8:p + 8 + length]
        p += 8 + length
        i = tick = status = 0
        on: dict[int, int] = {}
        notes = []
        while i < len(b):
            dt, i = vlq(b, i)
            tick += dt
            s = b[i]
            if s == 0xFF:
                kind = b[i + 1]
                n, j = vlq(b, i + 2)
                if kind == 0x51:
                    tempos.append((tick, int.from_bytes(b[j:j + n], "big")))
                i = j + n
                continue
            if s in (0xF0, 0xF7):
                n, j = vlq(b, i + 1)
                i = j + n
                continue
            if s & 0x80:
                status = s
                i += 1
            kind = status & 0xF0
            n = 1 if kind in (0xC0, 0xD0) else 2
            a = b[i:i + n]
            i += n
            if kind == 0x90 and a[1] > 0:
                on[a[0]] = tick
            elif kind in (0x80, 0x90) and a[0] in on:
                notes.append((on.pop(a[0]), tick, a[0]))
        tracks.append(sorted(notes))
    return division, sorted(tempos) or [(0, 500000)], tracks


def ms_at(tick: int, division: int, tempos: list[tuple[int, int]]) -> float:
    """The time of a tick in milliseconds, with all the tempo changes before it."""
    t, last_tick, last_tempo = 0.0, 0, tempos[0][1]
    for at, tempo in tempos:
        if at >= tick:
            break
        t += (at - last_tick) * last_tempo / division / 1000
        last_tick, last_tempo = at, tempo
    return t + (tick - last_tick) * last_tempo / division / 1000


def skyline(notes: list[tuple[int, int, int]], start: int, end: int) -> list[tuple[int, int, int]]:
    """The highest note at each start time, cut at the next start and at the end of the range."""
    top: dict[int, tuple[int, int]] = {}
    for s, e, key in notes:
        if start <= s < end and (s not in top or key > top[s][1]):
            top[s] = (e, key)
    starts = sorted(top)
    line = []
    for n, s in enumerate(starts):
        e, key = top[s]
        e = min(e, end, starts[n + 1] if n + 1 < len(starts) else end)
        line.append((s, e, key))
    return line


def table(line, start, end, division, tempos, shift):
    """The rows (value, ms, comment). Each note ends with a short rest."""
    rows, now = [], start
    for s, e, key in line:
        if s > now and rows:                                 # no rest before the first note
            rows.append((0, round(ms_at(s, division, tempos) - ms_at(now, division, tempos)), "rest"))
        key += 12 * shift
        hz = 440 * 2 ** ((key - 69) / 12)
        length = round(ms_at(e, division, tempos) - ms_at(s, division, tempos))
        name = f"{NAMES[key % 12]}{key // 12 - 1}"
        rows.append((round(PIEZO_CLOCK / hz), max(1, length - GAP_MS), f"{name} ({hz:.0f} Hz)"))
        rows.append((0, min(GAP_MS, length - 1), "gap"))
        now = e
    if end > now:
        rows.append((0, round(ms_at(end, division, tempos) - ms_at(now, division, tempos)), "rest"))
    merged = []
    for r in rows:
        if r[1] <= 0:
            continue
        if merged and r[0] == 0 and merged[-1][0] == 0:     # one rest for a gap and the rest after it
            merged[-1] = (0, merged[-1][1] + r[1], "rest")
        else:
            merged.append(r)
    return merged


def main() -> None:
    if len(sys.argv) not in (5, 6):
        raise SystemExit(__doc__)
    path, track, first, last = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
    shift = int(sys.argv[5]) if len(sys.argv) == 6 else 0
    division, tempos, tracks = read_midi(path)
    if not 0 <= track < len(tracks):
        raise SystemExit(f"The file has the tracks 0 to {len(tracks) - 1}.")
    bar = 4 * division
    start, end = (first - 1) * bar, last * bar
    rows = table(skyline(tracks[track], start, end), start, end, division, tempos, shift)
    total = sum(r[1] for r in rows)
    print(f"/* Track {track}, bars {first}-{last}, octave shift {shift}: {len(rows)} entries, {total} ms. */")
    for value, ms, comment in rows:
        print(f"    {{ {value:4}, {ms:5} }},  /* {comment} */")


if __name__ == "__main__":
    main()
