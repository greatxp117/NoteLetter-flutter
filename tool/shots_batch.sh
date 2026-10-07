#!/bin/sh
# The fidelity ritual's artifact for MANY screens in one build:
# screenshots/<screen>.flutter.{light,dark}.png, from the real renderer, against
# the emulator seed.
#
#   tool/shots_batch.sh <list-file>
#
# <list-file> has one hold per line, `screen|route|state` (state may be empty;
# `#` comments and blank lines are skipped) — the same three things
# `tool/shots.sh <screen> <route> [HOLD_STATE]` takes. Every hold is a testWidgets
# of its own in ONE run of integration_test/hold_screen_test.dart, over a fresh
# app tree, so the app builds once rather than once a pair (each shots.sh call
# rebuilds for its compile-time route: ~2-5 minutes a pair, ~40 pairs in a full
# re-shoot). Signed-out routes go last in the list: a hold signs in for itself,
# but a signed-out one signs the session out.
#
# Prints `OK <screen>` or `FAIL <screen>` per line. Not a gate: it asserts only
# that a state was reached. Look at the frames afterwards.
set -e
. "$(dirname "$0")/_emu_defines.sh"

list="${1:?usage: tool/shots_batch.sh <list-file>}"
emu_assert_ours >/dev/null
udid="$(emu_sim_udid)"
xcrun simctl boot "$udid" 2>/dev/null || true

# A RETIRED hold (QUEUE.md `retired-shots:`) names a state the app can no
# longer reach; it is never shot, so it is dropped here and said, not run into
# a hold that fails — or, worse, photographs another surface under its name.
retired="$(sed -n 's/^retired-shots:[[:space:]]*//p' "$REPO/QUEUE.md" \
  | sed 's/[[:space:]]*#.*$//' | tr ';' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' \
  | grep -v '^$' || true)"
body="$(grep -vE '^\s*(#|$)' "$list")"
for r in $retired; do
  if printf '%s\n' "$body" | cut -d'|' -f1 | grep -qxF "$r"; then
    echo "RETIRED $r :: QUEUE.md retired-shots — not shot"
    body="$(printf '%s\n' "$body" | awk -F'|' -v r="$r" '$1 != r')"
  fi
done
[ -n "$body" ] || { echo "tool: nothing left to shoot"; exit 0; }
holds="$(printf '%s\n' "$body" | tr '\n' ';')"
screens="$(printf '%s\n' "$body" | cut -d'|' -f1)"

cd "$REPO"
mkdir -p screenshots
log="$(mktemp -t nl-shots-batch)"
echo "tool: $(echo "$screens" | wc -l | tr -d ' ') holds on $udid (log $log)"
# shellcheck disable=SC2086
flutter test integration_test/hold_screen_test.dart -d "$udid" --timeout none \
  $EMU_DEFINES --dart-define=HOLD_LIST="$holds" >"$log" 2>&1 &
pid=$!

# Wait for `HOLD:<THEME>[<screen>]`; 0 when it appeared, 1 when the hold said
# it failed or the run ended first.
wait_mark() {
  m="HOLD:$1[$2]"; f="HOLD:FAIL[$2]"; n=0
  while ! grep -qF "$m" "$log"; do
    grep -qF "$f" "$log" && return 1
    kill -0 "$pid" 2>/dev/null || return 1
    n=$((n+1)); [ "$n" -gt 1500 ] && return 1
    sleep 1
  done
  sleep 2   # let the last frame paint
  base="$(mktemp -t nl-frame)"
  xcrun simctl io "$udid" screenshot "$base.png" >/dev/null 2>&1
  mv "$base.png" "screenshots/$2.flutter.$3.png"; rm -f "$base"
}

for s in $screens; do
  if wait_mark LIGHT "$s" light && wait_mark DARK "$s" dark; then
    echo "OK   $s"
  else
    echo "FAIL $s :: $(grep -F "HOLD:FAIL[$s]" "$log" | head -1 | cut -c1-300)"
  fi
done
wait "$pid" 2>/dev/null || true
if [ -d .dart_tool/flutter_build ]; then
  (cd .dart_tool/flutter_build && ls -t | tail -n +4 | xargs rm -rf)
fi
echo "tool: done — log kept at $log. Copy the web frames: tool/web_frames.sh <screen> …"
