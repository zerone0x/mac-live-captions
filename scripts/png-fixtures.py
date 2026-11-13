#!/usr/bin/env python3
"""Synthetic PNGs for the screenshot self-tests (#38). Standard library only.

    python3 scripts/png-fixtures.py compare <dir>   # compare-screenshots-selftest.sh
    python3 scripts/png-fixtures.py overlay <dir>   # live-screenshots-selftest.sh

Every image is RGBA with an sRGB chunk, so CoreGraphics reads the exact
values written here (no colour conversion) and the differences below are
the differences the compare sees.
"""
import os
import struct
import sys
import zlib


def write_png(path, width, height, pixel):
    """pixel(x, y) -> (r, g, b, a)."""
    rows = bytearray()
    for y in range(height):
        rows.append(0)  # filter: none
        for x in range(width):
            rows.extend(pixel(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"sRGB", b"\x00")
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


GREY = (128, 128, 128, 255)


def first_n(n):
    """The first n pixels in row order of a 100 x 100 image."""
    return lambda x, y: y * 100 + x < n


def changed(n, delta, channel):
    """GREY with `delta` added to `channel` on the first n pixels."""

    def pixel(x, y):
        if not first_n(n)(x, y):
            return GREY
        value = list(GREY)
        value[channel] += delta
        return tuple(value)

    return pixel


def compare(out):
    # 100 x 100 = 10 000 pixels: 0.1 % is 10 pixels.
    os.makedirs(out, exist_ok=True)
    write_png(f"{out}/grey.png", 100, 100, lambda x, y: GREY)
    write_png(f"{out}/grey-101.png", 101, 100, lambda x, y: GREY)
    # Fraction threshold: 10 pixels (0.1 %) may differ, 11 may not.
    write_png(f"{out}/grey-10-px.png", 100, 100, changed(10, 100, 0))
    write_png(f"{out}/grey-11-px.png", 100, 100, changed(11, 100, 0))
    # Channel tolerance, on one channel (green) of 20 % of the pixels:
    # off by 8 is the same, off by 9 differs.
    write_png(f"{out}/grey-green-8.png", 100, 100, changed(2000, 8, 1))
    write_png(f"{out}/grey-green-9.png", 100, 100, changed(2000, 9, 1))
    # Alpha only: opaque black against transparent black on 20 % of the
    # pixels. Premultiplied, the colour channels are 0 in both, so only a
    # compare that checks alpha sees it.
    write_png(f"{out}/black.png", 100, 100, lambda x, y: (0, 0, 0, 255))
    write_png(
        f"{out}/black-alpha.png",
        100,
        100,
        lambda x, y: (0, 0, 0, 0) if first_n(2000)(x, y) else (0, 0, 0, 255),
    )


def overlay(out):
    # A 300 x 150 point screen with the overlay at x=60 y=40 w=180 h=50
    # (top-left origin, as in CGWindowList), at scale 1 and at scale 2.
    os.makedirs(out, exist_ok=True)
    desktop = (200, 200, 205, 255)
    menu_bar = (235, 235, 235, 255)
    pill = (0, 0, 0, 255)
    text = (255, 255, 255, 255)

    def screen(scale, with_pill, background):
        def pixel(px, py):
            x, y = px / scale, py / scale
            if y < 24:
                return menu_bar
            if with_pill and 60 <= x < 240 and 40 <= y < 90:
                # Caption "text": white bars on the black pill.
                if 55 <= y < 65 and 76 <= x < 200 and int(x) % 6 < 4:
                    return text
                return pill
            return background(px, py)

        return pixel

    flat = lambda px, py: desktop  # noqa: E731
    black = lambda px, py: (0, 0, 0, 255)  # noqa: E731
    # A busy desktop picture: stripes of very different colours.
    busy = lambda px, py: (255, 255, 255, 255) if (px // 3) % 2 else (20, 40, 60, 255)  # noqa: E731

    write_png(f"{out}/shown.png", 300, 150, screen(1, True, flat))
    write_png(f"{out}/shown-2x.png", 600, 300, screen(2, True, flat))
    write_png(f"{out}/desktop-only.png", 300, 150, screen(1, False, flat))
    write_png(f"{out}/desktop-only-2x.png", 600, 300, screen(2, False, flat))
    write_png(f"{out}/black-desktop.png", 300, 150, screen(1, True, black))
    write_png(f"{out}/busy-desktop.png", 300, 150, screen(1, False, busy))


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("compare", "overlay"):
        sys.exit("usage: png-fixtures.py compare|overlay <dir>")
    {"compare": compare, "overlay": overlay}[sys.argv[1]](sys.argv[2])
