#!/usr/bin/env python3
"""Patch: skip SVG screen re-render when no segment state changed.

Game & Watch LCD segments change only a few times per second, but the SVG
screen renderer re-blitted every frame: a full-screen background memcpy
(1671x1080x4 = 7.2 MB) plus per-pixel scalar blits of every lit segment,
60x per second. This dominates CPU usage on the TrimUI Brick.

This patch makes the SVG renderer skip the frame entirely when no output
(segment) changed since the last render, returning UPDATE_HAS_NOT_CHANGED.
The render pipeline then skips the screen texture upload for that frame.

Correctness: we only skip when the previous draw was actually committed
(screen.m_curbitmap flipped in update_quads). Otherwise a change that
landed on a frameskip-skipped frame could be lost - we re-render instead.

Idempotent: safe to run multiple times. Fails hard (exit 1) if any edit
anchor is missing so a stale/renamed source cannot silently produce an
unpatched binary.

Usage: python3 0001_svg_skip_unchanged.py <mame_src_dir>
"""

import sys


def apply_replace(src: str, old: str, new: str, what: str) -> str:
    count = src.count(old)
    if count == 0:
        print(f"[patch ERROR] {what}: anchor not found in screen.cpp")
        sys.exit(1)
    print(f"[patch] {what}: {count} anchor(s) found, replacing")
    return src.replace(old, new)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: python3 0001_svg_skip_unchanged.py <mame_src_dir>")
        return 1

    path = sys.argv[1] + "/src/emu/screen.cpp"
    with open(path) as f:
        src = f.read()

    if "m_last_draw_bitmap" in src:
        print("[patch] screen.cpp: already applied, skipping")
        return 0

    # 1. member variables
    src = apply_replace(
        src,
        "\tint m_sx, m_sy;\n\tdouble m_scale;\n\tstd::vector<u32> m_background;\n",
        "\tint m_sx, m_sy;\n"
        "\tdouble m_scale;\n"
        "\tbool m_dirty;\n"
        "\tint m_last_draw_bitmap;\n"
        "\tstd::vector<u32> m_background;\n",
        "member variables",
    )

    # 2. constructor init
    src = apply_replace(
        src,
        "\tm_sx = m_sy = 0;\n\tm_scale = 1.0;\n",
        "\tm_sx = m_sy = 0;\n"
        "\tm_scale = 1.0;\n"
        "\tm_dirty = true;\n"
        "\tm_last_draw_bitmap = -1;\n",
        "constructor init",
    )

    # 3. output_change marks the renderer dirty
    src = apply_replace(
        src,
        "\tm_key_state[l->second] = value;\n}\n",
        "\tm_key_state[l->second] = value;\n\tm_dirty = true;\n}\n",
        "output_change",
    )

    # 4. rebuild_cache marks the renderer dirty (size change)
    src = apply_replace(
        src,
        "void screen_device::svg_renderer::rebuild_cache()\n{\n\tm_cache.clear();\n",
        "void screen_device::svg_renderer::rebuild_cache()\n"
        "{\n"
        "\tm_dirty = true;\n"
        "\tm_cache.clear();\n",
        "rebuild_cache",
    )

    # 5. render(): skip unchanged frames, but only if the previous draw
    #    was committed (m_curbitmap flipped by update_quads)
    old_render = (
        "\t\tm_background.resize(m_sx * m_sy);\n"
        "\t\trebuild_cache();\n"
        "\t}\n"
        "\n"
        "\tfor(unsigned int y = 0; y < m_sy; y++)\n"
        "\t\tmemcpy(bitmap.raw_pixptr(y, 0), &m_background[y * m_sx], m_sx * 4);\n"
    )
    new_render = (
        "\t\tm_background.resize(m_sx * m_sy);\n"
        "\t\trebuild_cache();\n"
        "\t}\n"
        "\n"
        "\tif(!m_dirty && screen.m_curbitmap == m_last_draw_bitmap)\n"
        "\t\treturn UPDATE_HAS_NOT_CHANGED;\n"
        "\tm_dirty = false;\n"
        "\tm_last_draw_bitmap = screen.m_curbitmap;\n"
        "\n"
        "\tfor(unsigned int y = 0; y < m_sy; y++)\n"
        "\t\tmemcpy(bitmap.raw_pixptr(y, 0), &m_background[y * m_sx], m_sx * 4);\n"
    )
    src = apply_replace(src, old_render, new_render, "render()")

    with open(path, "w") as f:
        f.write(src)

    print("[patch] screen.cpp: applied (all 5 edits)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
