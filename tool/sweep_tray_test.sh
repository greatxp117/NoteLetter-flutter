#!/bin/sh
# The camera-roll sweep's SCREENS on the simulator, against the EMULATOR suite
# (F-125 S3).
#
#   eval "$(tool/emu_alt.sh env)"           # after `tool/emu_alt.sh up`
#   tool/sweep_tray_test.sh                  # integration_test/sweep_tray_test.dart
#   tool/sweep_tray_test.sh frames <list>    # tool/shots_batch.sh <list>, with access
#
# It
#   1. proves the emulator on the exported ports is ours (emu_assert_ours) — an
#      Add opens a capture session, which WRITES a document;
#   2. adds the test photos with simctl addmedia (the four of
#      tool/sweep_test_photos.py for the test; its three pages for frames);
#   3. installs the app and sets FULL photo access in the simulator's own TCC
#      database (simctl's grant does not reach .readWrite on iOS 26.5:
#      tool/sweep_bridge_test.sh);
#   4. runs the test (or the frames) with the emulator defines, so the app
#      refuses prod — and, for the test, adds sweep-live.jpg when the test
#      prints SWEEP:ADD-PHOTO, the photo the change observer must bring in;
#   5. resets the permission on exit.
# The burn-down's EMU and SIM locks are the caller's to take.
set -e
. "$(dirname "$0")/_emu_defines.sh"

mode="${1:-test}"
emu_assert_ours
udid="$(emu_sim_udid)"
case "$udid" in
  16CF29E7*|F392E2C8*)
    echo "tool: $udid belongs to another workspace or the retired app. Set NL_SIM_NAME." >&2
    exit 1 ;;
esac
bundle=xp.NoteLetter.Flutter
xcrun simctl boot "$udid" 2>/dev/null || true

photos="$(mktemp -d)"
trap 'rm -rf "$photos"; xcrun simctl privacy "$udid" reset photos "$bundle" 2>/dev/null || true' EXIT
if [ "$mode" = frames ]; then
  python3 "$REPO/tool/sweep_test_photos.py" "$photos/add" --pages >/dev/null
else
  python3 "$REPO/tool/sweep_test_photos.py" "$photos/add" >/dev/null
  python3 "$REPO/tool/sweep_test_photos.py" "$photos/live" --live >/dev/null
fi
# NL_SWEEP_NO_ADD=1: a re-shoot over the photos an earlier run added (each
# run adds another copy of each, and a tray of copies is a busier frame).
if [ -z "${NL_SWEEP_NO_ADD:-}" ]; then
  for f in "$photos"/add/*.jpg; do xcrun simctl addmedia "$udid" "$f"; done
  echo "tool: added $(ls "$photos/add" | wc -l | tr -d ' ') photos to $udid"
fi

cd "$REPO"
# `flutter test` uninstalls the app when it ends, and a grant made while the
# app is not installed does not survive the next install: install first, set
# the permission on it, and `flutter test`'s own install is an UPDATE.
app="$REPO/build/ios/iphonesimulator/Runner.app"
if [ ! -d "$app" ]; then
  # shellcheck disable=SC2086
  flutter build ios --simulator --debug -t integration_test/sweep_tray_test.dart $EMU_DEFINES
fi
xcrun simctl install "$udid" "$app"
tcc="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/TCC/TCC.db"
xcrun simctl privacy "$udid" grant photos "$bundle"
sqlite3 "$tcc" "update access set auth_value=2, auth_version=2 \
  where service='kTCCServicePhotos' and client='$bundle';"
got="$(sqlite3 "$tcc" "select auth_value||'/'||auth_version from access \
  where service='kTCCServicePhotos' and client='$bundle';")"
[ "$got" = "2/2" ] || { echo "tool: photo permission not set ($got)" >&2; exit 1; }

if [ "$mode" = frames ]; then
  list="${2:?usage: tool/sweep_tray_test.sh frames <list-file>}"
  echo "tool: full photo access; frames on $udid"
  # The grant is undone by this script's trap, not by shots_batch.sh.
  sh "$REPO/tool/shots_batch.sh" "$list"
  exit $?
fi

echo "tool: full photo access; sweep tray test on $udid (emulator firestore:$EMU_FIRESTORE_PORT auth:$EMU_AUTH_PORT shim:$EMU_FUNCTIONS_PORT)"
log="$(mktemp -t nl-sweep-tray)"
# shellcheck disable=SC2086
flutter test integration_test/sweep_tray_test.dart -d "$udid" --timeout none \
  $EMU_DEFINES >"$log" 2>&1 &
pid=$!
added=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$added" = 0 ] && grep -qF 'SWEEP:ADD-PHOTO' "$log"; then
    xcrun simctl addmedia "$udid" "$photos/live/sweep-live.jpg"
    echo "tool: added sweep-live.jpg while the app runs"
    added=1
  fi
  sleep 1
done
set +e
wait "$pid"
rc=$?
set -e
grep -E 'sweep tray:|SWEEP:|tests? passed|Some tests failed|EXCEPTION|Expected|Actual|reason|timed out' "$log" | cut -c1-400
echo "tool: log kept at $log (exit $rc)"
exit "$rc"
