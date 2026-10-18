#!/usr/bin/env python3
"""The camera-roll sweep bridge's test photos (F-125 S1).

    python3 tool/sweep_test_photos.py <out dir>

Writes four JPEGs for `tool/sweep_bridge_test.sh` to add to the simulator's
library with `xcrun simctl addmedia`, each with a fixed EXIF capture time (so
the newest-first order is known and a re-import keeps its date):

  sweep-dense.jpg      a printed paragraph, far over 80 characters  -> candidate
  sweep-sparse.jpg     one short line, under 80 characters          -> noText
  sweep-blank.jpg      shapes, no text at all                        -> noText
  Café crème — 日本語 ノート.jpg
                       the dense paragraph again, under a non-ASCII
                       name: the key must carry the filename's bytes  -> candidate

Text is drawn large and black on white: this proves the bridge reports the
check's verdict, not the check's precision on a real camera roll (that gate
is live, on a phone; spec §Conformance).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

DENSE = (
    "The camera roll sweep keeps a photo only when it has something to read. "
    "This paragraph is printed text on a plain page, long enough to clear the "
    "eighty character threshold several times over, so the on-device check "
    "should call it a candidate."
)
SPARSE = "Lunch at noon"

# name -> (capture time, kind). Newest first is the order the bridge returns.
PHOTOS = [
    ("Café crème — 日本語 ノート.jpg", "2026:10:04 09:00:00", "dense"),
    ("sweep-dense.jpg", "2026:10:03 09:00:00", "dense"),
    ("sweep-sparse.jpg", "2026:10:02 09:00:00", "sparse"),
    ("sweep-blank.jpg", "2026:10:01 09:00:00", "blank"),
]


def font(size):
    for path in ("/System/Library/Fonts/Supplemental/Arial.ttf",
                 "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default(size=size)


def wrap(draw, text, f, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if draw.textlength(trial, font=f) > width and line:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line]


def render(kind):
    img = Image.new("RGB", (1600, 1200), "white")
    d = ImageDraw.Draw(img)
    if kind == "dense":
        f = font(56)
        y = 90
        for line in wrap(d, DENSE, f, 1440):
            d.text((80, y), line, fill="black", font=f)
            y += 78
    elif kind == "sparse":
        d.text((80, 520), SPARSE, fill="black", font=font(72))
    else:
        d.ellipse((300, 250, 900, 850), fill=(70, 130, 180))
        d.rectangle((1000, 400, 1400, 900), fill=(200, 120, 60))
    return img


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name, when, kind in PHOTOS:
        img = render(kind)
        exif = Image.Exif()
        exif[0x0132] = when                      # DateTime
        sub = exif.get_ifd(0x8769)               # Exif IFD
        sub[0x9003] = when                       # DateTimeOriginal
        sub[0x9004] = when                       # DateTimeDigitized
        sub[0x9011] = "+00:00"                   # OffsetTimeOriginal
        img.save(os.path.join(out, name), "JPEG", quality=92, exif=exif)
        print(os.path.join(out, name))


if __name__ == "__main__":
    main()
