#!/bin/sh
# The camera-roll sweep's ledger and service on the simulator, against the
# EMULATOR suite (F-125 S2): integration_test/sweep_service_test.dart.
#
#   eval "$(tool/emu_alt.sh env)"        # after `tool/emu_alt.sh up`
#   NL_SIM_NAME="NL Flutter agent 17 Pro" tool/sweep_service_test.sh
#
# It
#   1. proves the emulator on the exported ports is ours (emu_assert_ours) —
#      a capture session WRITES a document, so this never runs without it;
#   2. adds the four test photos (tool/sweep_test_photos.py) with addmedia;
#   3. installs the app and sets FULL photo access in the simulator's own TCC
#      database (why not simctl alone: tool/sweep_bridge_test.sh);
#   4. runs the test with the emulator defines, so the app refuses prod;
#   5. resets the permission on exit.
# The burn-down's EMU and SIM locks are the caller's to take.
set -e
. "$(dirname "$0")/_emu_defines.sh"

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
python3 "$REPO/tool/sweep_test_photos.py" "$photos" >/dev/null
for f in "$photos"/*.jpg; do xcrun simctl addmedia "$udid" "$f"; done
echo "tool: added $(ls "$photos" | wc -l | tr -d ' ') photos to $udid"

cd "$REPO"
# `flutter test` uninstalls the app when it ends, and a grant made while the
# app is not installed does not survive the next install: install first, set
# the permission on it, and `flutter test`'s own install is an UPDATE.
app="$REPO/build/ios/iphonesimulator/Runner.app"
if [ ! -d "$app" ]; then
  # shellcheck disable=SC2086
  flutter build ios --simulator --debug -t integration_test/sweep_service_test.dart $EMU_DEFINES
fi
xcrun simctl install "$udid" "$app"

tcc="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/TCC/TCC.db"
xcrun simctl privacy "$udid" grant photos "$bundle"
sqlite3 "$tcc" "update access set auth_value=2, auth_version=2 \
  where service='kTCCServicePhotos' and client='$bundle';"
got="$(sqlite3 "$tcc" "select auth_value||'/'||auth_version from access \
  where service='kTCCServicePhotos' and client='$bundle';")"
[ "$got" = "2/2" ] || { echo "tool: photo permission not set ($got)" >&2; exit 1; }
echo "tool: full photo access; sweep service test on $udid (emulator firestore:$EMU_FIRESTORE_PORT auth:$EMU_AUTH_PORT shim:$EMU_FUNCTIONS_PORT)"

# 5.40.0: the test asks for a photo to be taken between two passes (a file in
# its tmp/), and a pass from the change token must read only that photo.
(
  for _ in $(seq 1 900); do
    data="$(xcrun simctl get_app_container "$udid" "$bundle" data 2>/dev/null || true)"
    if [ -n "$data" ] && [ -f "$data/tmp/sweep-take-a-photo" ]; then
      rm -f "$data/tmp/sweep-take-a-photo"
      xcrun simctl addmedia "$udid" "$photos/sweep-dense.jpg"
      echo "tool: took a photo (sweep-dense.jpg) for the change-token pass"
      exit 0
    fi
    sleep 1
  done
) &
watcher=$!
trap 'kill "$watcher" 2>/dev/null || true; rm -rf "$photos"; xcrun simctl privacy "$udid" reset photos "$bundle" 2>/dev/null || true' EXIT

# shellcheck disable=SC2086
flutter test integration_test/sweep_service_test.dart -d "$udid" --timeout none $EMU_DEFINES
