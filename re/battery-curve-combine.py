#!/usr/bin/env python3
"""Make the 3000 mAh table of battery-display from more than one battery log. Refer to battery.md.

Usage: python3 re/battery-curve-combine.py --empty LOG [LOG ...] [--check LOG ...]

--empty: logs that continue until the iPod stops. Each log gives the hours that remain at each raw
         value. The script calculates the mean of these hours where two or more logs have the raw
         value. Above the top of the shorter logs, the shape of the highest log continues the curve.
         Put the log from a full charge first.
--check: logs that do not continue until the iPod stops. The script compares their fall rate with
         the combined curve. They do not change the table.

The method to read a log is the same as BatteryCurve.make: the longest run, a mean of 7 samples,
and a start at the highest mean value. The percentages are the same 16 values as in the app. But
the script finds the raw value where the hours that remain reach each percentage. The app reads the
raw value at equal times. Thus the values can differ by a few units.
"""
import argparse
from pathlib import Path

POINTS = 16
WINDOW = 3
CHARGER_LIMIT = 460   # a value above this is from a charger (re/battery-logs, log of 2 November)


def runs(path):
    """The runs of a log: lists of (seconds, raw). A line "start" begins a new run."""
    out = [[]]
    for line in Path(path).read_text(errors="replace").splitlines():
        if line.strip() == "start":
            out.append([])
            continue
        fields = line.split()
        if len(fields) == 4 and fields[0].isdigit() and fields[1].isdigit():
            out[-1].append((int(fields[0]), int(fields[1])))
    return out


def run(path):
    """The longest run of a log, from its highest mean value. Returns (seconds, mean raw, last raw)."""
    longest = max(runs(path), key=lambda r: r[-1][0] if r else 0)
    if len(longest) < 2:
        raise SystemExit(f"{path}: the log has too few samples.")
    mean = []
    for i in range(len(longest)):
        part = longest[max(0, i - WINDOW):i + WINDOW + 1]
        mean.append(sum(raw for _, raw in part) // len(part))
    first = max(range(len(mean)), key=lambda i: (mean[i], -i))
    return [s for s, _ in longest[first:]], mean[first:], longest[-1][1]


def remaining(path):
    """The hours that remain at each raw value, for a log to empty. Returns (table, top, last raw)."""
    seconds, mean, last = run(path)
    end, table, low = seconds[-1], {}, mean[0]
    for s, value in zip(seconds, mean):
        while low >= value:          # the first time that the mean is at or below a raw value
            table[low] = (end - s) / 3600
            low -= 1
    return table, mean[0], last


def combine(paths):
    logs = [remaining(p) for p in paths]
    top = max(t for _, t, _ in logs)
    bottom = round(sum(last for _, _, last in logs) / len(logs))
    shape = next(table for table, t, _ in logs if t == top)
    hours, joint = {}, None
    for raw in range(top, bottom - 1, -1):
        have = [table[raw] for table, t, _ in logs if raw in table]
        if len(have) > 1 and joint is None:
            joint = raw
        hours[raw] = sum(have) / len(have) if have else 0.0
    if joint is not None:             # above the joint, keep the shape of the highest log
        for raw in range(top, joint, -1):
            hours[raw] = shape[raw] - shape[joint] + hours[joint]
    return hours, top, bottom, joint, logs


def table(hours, top, bottom):
    total = hours[top]
    raw, pct = [], []
    for i in range(POINTS):
        p = 100 - (100 * i + (POINTS - 1) // 2) // (POINTS - 1)
        if i == POINTS - 1:
            value = bottom
        else:
            value = next((r for r in range(top, bottom - 1, -1) if hours[r] <= total * p / 100), bottom)
        if raw:
            value = min(value, raw[-1] - 1)
        raw.append(value)
        pct.append(p)
    return raw, pct, total


def check(path, hours):
    """Compare the time between two raw values in a log with the combined curve."""
    seconds, mean, _ = run(path)
    high, low = mean[0], mean[-1]
    if high not in hours or low not in hours or high <= low:
        return f"{Path(path).name}: raw {high} to {low}: not in the combined curve."
    log_h = (seconds[-1] - seconds[0]) / 3600
    curve_h = hours[high] - hours[low]
    return (f"{Path(path).name}: raw {high} to {low}: {log_h:.2f} h in the log, "
            f"{curve_h:.2f} h in the curve ({(log_h / curve_h - 1) * 100 if curve_h else 0:+.0f} %).")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--empty", nargs="+", required=True)
    parser.add_argument("--check", nargs="*", default=[])
    args = parser.parse_args()

    hours, top, bottom, joint, logs = combine(args.empty)
    for path, (t, start, last) in zip(args.empty, logs):
        note = "  CAUTION: a charger value" if start > CHARGER_LIMIT else ""
        print(f"{Path(path).name}: raw {start} to {last}, {t[start]:.2f} h{note}")
    if joint is not None:
        for path, (t, _, _) in zip(args.empty, logs):
            if joint in t:
                print(f"  hours that remain at raw {joint}: {t[joint]:.2f}")
    raw, pct, total = table(hours, top, bottom)
    print(f"Combined: raw {top} to {bottom}, {total:.2f} h. The mean of the logs starts at raw {joint}." if joint
          else f"Combined: raw {top} to {bottom}, {total:.2f} h. Only one log.")
    for path in args.check:
        print(check(path, hours))
    print("#define MAH3000_RAW  { " + ", ".join(f"{v:3d}" for v in raw) + " }")
    print("#define MAH3000_PCT  { " + ", ".join(f"{v:3d}" for v in pct) + " }")


if __name__ == "__main__":
    main()
