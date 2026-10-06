#!/usr/bin/env python3
"""Builds re/collect-ipod-info.html: the instructions for iPod classic owners, with both scripts inside.

The page is one self-contained file. It has no external fonts, scripts or styles. Run this program
after each change to collect-ipod-info.sh, collect-ipod-info.ps1 or the template. tests/test_collect_page.py fails if
the page does not agree with the script.

Usage: python3 re/build-collect-page.py
"""
import html
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent


def build() -> str:
    template = (HERE / "collect-ipod-info.template.html").read_text()
    mac = (HERE / "collect-ipod-info.sh").read_text()
    win = (HERE / "collect-ipod-info.ps1").read_text()
    mac_version = re.search(r"^VERSION=(\d+)", mac, re.M).group(1)
    win_version = re.search(r"^\$Version = (\d+)", win, re.M).group(1)
    return (template.replace("__SCRIPT_WIN__", html.escape(win, quote=False))
            .replace("__VERSION_WIN__", win_version)
            .replace("__SCRIPT__", html.escape(mac, quote=False))
            .replace("__VERSION__", mac_version))


if __name__ == "__main__":
    out = HERE / "collect-ipod-info.html"
    out.write_text(build())
    print(f"Wrote {out}")
