#!/usr/bin/env python3
"""Writes the app icon SVG sources in this directory (docs/DECISIONS.md 0025).

Design (#53): the two caption lines of specimen B (a finished white line, then
a line whose tail fades from final text to grey "volatile" text) on a dark
rounded caption panel over the warm peach-to-coral gradient of specimen E.

Outputs (1024 x 1024 canvas, macOS icon grid: 824 px tile with a 100 px
margin, continuous-corner tile, soft drop shadow):
  AppIcon.svg         the icon, used for 32@2x (64 px) and larger
  AppIcon-32.svg      32 px master: panel and lines snapped to the 32 px grid,
                      2 px lines (used for 16@2x and 32@1x)
  AppIcon-16.svg      16 px master: 1 px lines on whole pixel rows, the tail
                      reduced to one grey segment (used for 16@1x)
  AppIcon-dark.svg    dark appearance (reference only; see DECISIONS 0025)
  AppIcon-tinted.svg  tinted appearance (reference only)

Pure standard library; run `python3 design/icon/generate-svgs.py`, then
`scripts/render-app-icon.sh` to turn the SVGs into the asset catalog PNGs.
"""

import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def squircle(x=100, y=100, s=824, n=5.0, pts=160):
    """Superellipse close to Apple's continuous-corner icon tile."""
    cx, cy, a = x + s / 2, y + s / 2, s / 2
    d = []
    for i in range(pts):
        t = 2 * math.pi * i / pts
        ct, st = math.cos(t), math.sin(t)
        px = cx + a * math.copysign(abs(ct) ** (2 / n), ct)
        py = cy + a * math.copysign(abs(st) ** (2 / n), st)
        d.append(f"{'M' if i == 0 else 'L'}{px:.1f} {py:.1f}")
    return " ".join(d) + "Z"


TILE = squircle()

# Appearance palettes: tile gradient (top, bottom), panel, line ink.
PALETTES = {
    "default": {"bg": ("#ffb36b", "#f2546b"), "panel": "#0b0b0d", "ink": "#ffffff"},
    "dark": {"bg": ("#5e362f", "#2a1718"), "panel": "#000000", "ink": "#ffffff"},
    "tinted": {"bg": ("#2a2620", "#121110"), "panel": "#000000", "ink": "#ffb347"},
}

# Opacity of the second line's segments: final text, volatile, most volatile.
FINAL, VOLATILE, TAIL = 1, 0.5, 0.22


def frame(palette, body):
    top, bottom = palette["bg"]
    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
<defs>
<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".35"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#fff" stop-opacity=".12"/></linearGradient>
<clipPath id="tile"><path d="{TILE}"/></clipPath>
<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%"><feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity=".28"/></filter>
</defs>
<path d="{TILE}" fill="url(#bg)" filter="url(#shadow)"/>
<g clip-path="url(#tile)">
{body}
</g>
<path d="{TILE}" fill="none" stroke="url(#rim)" stroke-width="5"/>
</svg>
"""


def rect(x0, x1, y0, y1, rx, fill, opacity=1):
    op = "" if opacity == 1 else f' fill-opacity="{opacity}"'
    return (f'<rect x="{x0:g}" y="{y0:g}" width="{x1 - x0:g}" height="{y1 - y0:g}" '
            f'rx="{rx:g}" fill="{fill}"{op}/>')


def icon(p):
    """Full-size design (64 px and up)."""
    ink, h = p["ink"], 84
    x0, x1, w = 262, 762, 500

    def seg(a, b, y, opacity):
        return rect(x0 + w * a, x0 + w * b, y - h / 2, y + h / 2, h / 2, ink, opacity)

    return frame(p, "".join([
        rect(172, 852, 322, 702, 132, p["panel"]),
        seg(0, 1, 444, FINAL),
        seg(0, 0.447, 580, FINAL),
        seg(0.517, 0.76, 580, VOLATILE),
        seg(0.83, 1, 580, TAIL),
    ]))


def icon32(p):
    """32 px master: one px = 32 units; edges on whole pixels, 2 px lines."""
    ink, u = p["ink"], 32

    def px(x0, x1, y0, y1, opacity=1, rx=0.5):
        return rect(x0 * u, x1 * u, y0 * u, y1 * u, rx * u, ink, opacity)

    return frame(p, "".join([
        rect(5 * u, 27 * u, 9 * u, 22 * u, 4 * u, p["panel"]),
        px(8, 24, 12, 14),
        px(8, 16, 17, 19),
        px(17, 21, 17, 19, VOLATILE),
        px(22, 24, 17, 19, TAIL + 0.08),
    ]))


def icon16(p):
    """16 px master: one px = 64 units; 1 px lines, square ends, one grey tail."""
    ink, u = p["ink"], 64

    def px(x0, x1, y0, y1, opacity=1):
        return rect(x0 * u, x1 * u, y0 * u, y1 * u, 0, ink, opacity)

    return frame(p, "".join([
        rect(3 * u, 13 * u, 5 * u, 10 * u, 2 * u, p["panel"]),
        px(4, 12, 6, 7),
        px(4, 8, 8, 9),
        px(9, 12, 8, 9, VOLATILE),
    ]))


def main():
    outputs = {
        "AppIcon.svg": icon(PALETTES["default"]),
        "AppIcon-32.svg": icon32(PALETTES["default"]),
        "AppIcon-16.svg": icon16(PALETTES["default"]),
        "AppIcon-dark.svg": icon(PALETTES["dark"]),
        "AppIcon-tinted.svg": icon(PALETTES["tinted"]),
    }
    for name, svg in outputs.items():
        with open(os.path.join(HERE, name), "w", encoding="utf-8") as f:
            f.write(svg)
        print(f"wrote design/icon/{name}")


if __name__ == "__main__":
    main()
