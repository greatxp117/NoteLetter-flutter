#!/bin/sh
# Put the web reference frame beside the Flutter pair, so the comparison the
# fidelity ritual asks for is IN the repo rather than in a task summary.
#
#   tool/web_frames.sh <screen> [<screen> ...]
#
# The web set (NoteLetter-web/screenshots/<screen>.web.{light,dark}.png) is the
# source — it is shot by theme-shots.mjs and committed there. This repo carries
# a byte-identical copy, and harness/screenshot_pair_check.py fails the day the
# two differ (STALE-WEB-FRAME): the reference moved, so the Flutter screen has to
# be looked at again.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
WEB="$REPO/../NoteLetter-web/screenshots"
[ $# -ge 1 ] || { echo "usage: tool/web_frames.sh <screen> [...]" >&2; exit 2; }

for screen in "$@"; do
  for theme in light dark; do
    src="$WEB/$screen.web.$theme.png"
    if [ ! -f "$src" ]; then
      echo "tool: no web reference frame $src" >&2
      echo "      Shoot it first, from NoteLetter-web/ with the emulator + seed up:" >&2
      echo "        VITE_USE_EMULATOR=true npm run dev &   # port 3000" >&2
      echo "        node scripts/theme-shots.mjs --only $screen" >&2
      echo "      and commit it there — the web set is the source, this repo holds a copy." >&2
      exit 1
    fi
    cp "$src" "$REPO/screenshots/$screen.web.$theme.png"
    echo "tool: copied $screen.web.$theme.png"
  done
done
