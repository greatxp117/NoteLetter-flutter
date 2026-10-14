#!/usr/bin/env python3
"""Is a captured frame one a person should look at twice? Two questions,
asked by `tool/shots_batch.sh` of every frame it keeps.

    python3 tool/frame_check.py settled A.png B.png   exit 0: B is A (the screen stopped moving)
    python3 tool/frame_check.py blank A.png           exit 0: A has no content below its chrome
    python3 tool/frame_check.py measure A.png [B.png] print both numbers
    python3 tool/frame_check.py selftest              both questions over synthetic frames

WHY
---
The batch shot each theme two seconds after the hold's marker, and nothing
looked at what it caught but a person. On 2026-10-14 three of 18 first
catches were wrong and every line said `OK`: letter-reader and
letter-settings were the letter's WebView before its first paint (a blank
sheet), and reader-history was a frame mid-transition (the header over an
empty body). A re-shoot of each was right. The capture is now taken again
until two consecutive shots agree, and a frame that is still empty when it
does is flagged rather than kept silently.

SETTLED compares two shots below the status bar and above the home strip:
the clock and the strip move between any two shots and say nothing about
the screen. A spinner or a caret moves a few hundred pixels; a page that is
still painting moves tens of thousands. The bar is between them.

BLANK counts TEXT-like pixels in the content band (15%–92% of the height):
a pixel that differs from its own 25px neighbourhood by more than 60 levels.
The paper grain and the flat sheet are under that everywhere; any glyph is
over it. Measured over every committed Flutter frame (2026-10-14): the
emptiest real screen is reader-history with one event, 0.0067; an empty
region of the same frame reads 0.0000. The bar sits well under the first and
well over the second.

Pure PIL, no project imports: it runs from the batch's shell with the
system `python3`.
"""
from __future__ import annotations

import sys

from PIL import Image, ImageChops, ImageFilter

# Below the status bar (y 79–117 on a 3x iPhone 17 Pro frame) and above the
# home strip (the last ~40px), as fractions so a 2x or 3x frame both work.
TOP, BOTTOM = 0.05, 0.985
# A pixel "moved" when its luminance changed by more than this.
MOVED_LEVEL = 24
# Settled when at most this fraction of the compared band moved.
SETTLED_MAX = 0.002
# The content band BLANK reads, and its bar.
BAND = (0.15, 0.92)
INK_LEVEL = 60
BLANK_MAX = 0.002


def _band(img: Image.Image, top: float, bottom: float) -> Image.Image:
    w, h = img.size
    return img.crop((0, int(h * top), w, int(h * bottom)))


def moved(a_path: str, b_path: str) -> float:
    a = Image.open(a_path).convert("L")
    b = Image.open(b_path).convert("L")
    if a.size != b.size:
        return 1.0
    d = ImageChops.difference(_band(a, TOP, BOTTOM), _band(b, TOP, BOTTOM))
    hist = d.histogram()
    return sum(hist[MOVED_LEVEL + 1:]) / max(1, sum(hist))


def ink(path: str) -> float:
    img = _band(Image.open(path).convert("L"), *BAND)
    bg = img.filter(ImageFilter.BoxBlur(12))
    hist = ImageChops.difference(img, bg).histogram()
    return sum(hist[INK_LEVEL + 1:]) / max(1, sum(hist))


def selftest() -> int:
    """Both questions over synthetic frames, so a threshold edited into
    uselessness is red here before it is wrong on a batch."""
    import os
    import random
    import tempfile

    random.seed(7)
    w, h = 402, 874  # 1x: the fractions make the size irrelevant
    ground = Image.new("L", (w, h), 246)
    ground.putdata([246 + random.randint(-6, 6) for _ in range(w * h)])
    text = ground.copy()
    for row in range(int(h * 0.2), int(h * 0.85), 24):
        for col in range(20, w - 20, 9):
            for dy in range(10):
                text.putpixel((col, row + dy), 30)
    # A blank catch is rarely spotless: the loading sheet's edge or a stray
    # glyph of the chrome can reach the band. One short line is still blank.
    stray = ground.copy()
    for x in range(100, 140):
        for y in range(int(h * 0.3), int(h * 0.3) + 6):
            stray.putpixel((x, y), 30)
    clock = text.copy()
    for x in range(40, 90):
        for y in range(int(h * 0.01), int(h * 0.04)):
            clock.putpixel((x, y), 0)
    # A caret or a spinner moves a few pixels on a screen that has stopped.
    caret = text.copy()
    for x in range(200, 203):
        for y in range(int(h * 0.4), int(h * 0.4) + 18):
            caret.putpixel((x, y), 0)
    moving = text.copy()
    for x in range(0, w):
        for y in range(int(h * 0.5), int(h * 0.6)):
            moving.putpixel((x, y), 120)
    d = tempfile.mkdtemp(prefix="frame-check-")
    paths = {}
    for name, img in {"ground": ground, "stray": stray, "text": text,
                      "clock": clock, "caret": caret,
                      "moving": moving}.items():
        paths[name] = os.path.join(d, name + ".png")
        img.save(paths[name])
    cases = [
        ("an empty sheet is BLANK", ink(paths["ground"]) <= BLANK_MAX),
        ("one stray line on it is still BLANK", ink(paths["stray"]) <= BLANK_MAX),
        ("a page of text is not", ink(paths["text"]) > BLANK_MAX),
        ("the clock alone moving is SETTLED",
         moved(paths["text"], paths["clock"]) <= SETTLED_MAX),
        ("a caret blinking is SETTLED",
         moved(paths["text"], paths["caret"]) <= SETTLED_MAX),
        ("a tenth of the page moving is not",
         moved(paths["text"], paths["moving"]) > SETTLED_MAX),
    ]
    bad = [c for c, ok in cases if not ok]
    for c, ok in cases:
        print(("  ok    " if ok else "  FAIL  ") + c)
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    if argv[:1] == ["selftest"]:
        return selftest()
    if len(argv) >= 3 and argv[0] == "settled":
        m = moved(argv[1], argv[2])
        print(f"moved {m:.4f} (settled at <= {SETTLED_MAX})")
        return 0 if m <= SETTLED_MAX else 1
    if len(argv) >= 2 and argv[0] == "blank":
        i = ink(argv[1])
        print(f"ink {i:.4f} (blank at <= {BLANK_MAX})")
        return 0 if i <= BLANK_MAX else 1
    if len(argv) >= 2 and argv[0] == "measure":
        print(f"ink {ink(argv[1]):.4f}")
        if len(argv) >= 3:
            print(f"moved {moved(argv[1], argv[2]):.4f}")
        return 0
    print(__doc__.split("WHY")[0].strip(), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
