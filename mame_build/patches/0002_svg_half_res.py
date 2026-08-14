#!/usr/bin/env python3
"""Patch: halve the Game & Watch SVG screen resolution.

The hh_sm510 SVG screens are configured at ~1671x1080 pixels - 2.6x the
1024x768 panel. Every per-frame cost scales with this resolution (SVG
render memcpy, segment blits, texture upload, GPU source read):
- 7.2 MB background memcpy per render
- 7.2 MB texture upload per changed frame
- full-res source for the RenderCopy scale

LCD segments are large flat shapes; rendering at half resolution
(835x540) is visually indistinguishable once scaled to the panel.

This patch divides the screen size by two in mcfg_svg_screen(), the
single funnel for all hh_sm510 screen sizes.

Idempotent: safe to run multiple times. Fails hard (exit 1) if the
anchor is missing so a stale/renamed source cannot silently produce an
unpatched binary.

Usage: python3 0002_svg_half_res.py <mame_src_dir>
"""

import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python3 0002_svg_half_res.py <mame_src_dir>")
        return 1

    path = sys.argv[1] + "/src/mame/drivers/hh_sm510.cpp"
    with open(path) as f:
        src = f.read()

    old = "\tscreen.set_size(width, height);\n"
    new = "\tscreen.set_size(width / 2, height / 2);\n"

    if new in src:
        print("[patch] hh_sm510.cpp: already applied, skipping")
        return 0

    count = src.count(old)
    if count != 1:
        print(f"[patch ERROR] expected exactly 1 set_size anchor, found {count}")
        return 1

    src = src.replace(old, new)

    with open(path, "w") as f:
        f.write(src)

    print("[patch] hh_sm510.cpp: applied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
