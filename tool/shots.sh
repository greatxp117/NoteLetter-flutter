#!/bin/sh
# The fidelity ritual's artifact (ADR-041 §5): screenshots/<screen>.flutter.{light,dark}.png
# from the REAL renderer, against the emulator seed.
#
#   tool/shots.sh <screen> <route> [HOLD_STATE]
#   tool/shots.sh notifications /settings/notifications
#   tool/shots.sh reader-manuscript /reader/seed-doc-pdf-complete manuscript
#
# <screen> is the theme-shots name (NoteLetter-web/scripts/theme-shots.mjs), so
# the Flutter frame and the web frame sit beside each other under one name and
# harness/screenshot_pair_check.py can pair them. HOLD_STATE is passed to
# hold_screen_test.dart for states no route reaches (a typed query, a tab).
#
# Drives integration_test/hold_screen_test.dart, which prints HOLD:LIGHT and
# HOLD:DARK and holds each theme ~30s; the frame is caught from OUTSIDE the
# process with `xcrun simctl io <UDID> screenshot` because iOS cannot convert
# the Flutter surface under `flutter test`. Not a gate: it asserts nothing.
# Look at the four frames afterwards — that is the whole point.
set -e
. "$(dirname "$0")/_emu_defines.sh"

screen="${1:?usage: tool/shots.sh <screen> <route> [HOLD_STATE]}"
route="${2:?usage: tool/shots.sh <screen> <route> [HOLD_STATE]}"
state="${3:-}"

emu_assert_ours
udid="$(emu_sim_udid)"
xcrun simctl boot "$udid" 2>/dev/null || true

cd "$REPO"
mkdir -p screenshots
log="$(mktemp -t nl-shots)"
extra=""
[ -n "$state" ] && extra="--dart-define=HOLD_STATE=$state"

echo "tool: holding $route on $udid → screenshots/$screen.flutter.{light,dark}.png"
# shellcheck disable=SC2086
flutter test integration_test/hold_screen_test.dart -d "$udid" --timeout none \
  $EMU_DEFINES --dart-define=HOLD_ROUTE="$route" $extra >"$log" 2>&1 &
pid=$!

wait_for() {
  marker="$1"; out="$2"; n=0
  while ! grep -q "$marker" "$log"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "tool: the hold test exited before $marker — its output:" >&2
      tail -40 "$log" >&2
      exit 1
    fi
    n=$((n+1)); [ "$n" -gt 900 ] && { echo "tool: timed out waiting for $marker" >&2; kill "$pid"; exit 1; }
    sleep 1
  done
  sleep 2   # let the last frame paint
  # Caught into the temp dir, then moved: CoreSimulator writes the file, not
  # this shell, and it may hold no permission for a repo under ~/Desktop
  # (NSCocoaErrorDomain 513 — the hold then runs on with no frame written).
  base="$(mktemp -t nl-frame)"
  xcrun simctl io "$udid" screenshot "$base.png" >/dev/null
  mv "$base.png" "$out"; rm -f "$base"
  echo "tool: wrote $out"
}

wait_for "HOLD:LIGHT" "screenshots/$screen.flutter.light.png"
wait_for "HOLD:DARK"  "screenshots/$screen.flutter.dark.png"
kill "$pid" 2>/dev/null || true
wait "$pid" 2>/dev/null || true
rm -f "$log"
# Every hold build leaves a ~68 MB dir under .dart_tool/flutter_build that
# nothing prunes — it filled the disk. Keep the newest three.
if [ -d .dart_tool/flutter_build ]; then
  (cd .dart_tool/flutter_build && ls -t | tail -n +4 | xargs rm -rf)
fi
echo "tool: now copy the web frame beside them: tool/web_frames.sh $screen"
