#!/bin/sh
# The camera-roll sweep bridge's device test (F-125 S1), on the simulator.
#
#   NL_SIM_NAME="NL Flutter agent 17 Pro" tool/sweep_bridge_test.sh
#
# No emulator: the bridge reads the photo library and nothing else. It
#   1. adds the four test photos (tool/sweep_test_photos.py) with simctl addmedia,
#   2. sets FULL photo access and runs integration_test/sweep_bridge_test.dart
#      (enumerate, key, text check, rendered JPEG),
#   3. sets LIMITED access and runs its refusal half (the Swift sentence),
#   4. sets NO access and runs the same,
#   5. resets the permission to never-asked, as it was before.
# Re-running adds the photos again. That is part of the proof: a re-import is a
# new localIdentifier with the SAME key (INV-14's restore case), and the test
# asserts it.
#
# How the permission is set, and why not with simctl alone: on the iOS 26.5
# runtime `simctl privacy grant photos` writes a TCC row at auth_version 1,
# and `PHPhotoLibrary.authorizationStatus(for: .readWrite)` asks tccd at
# auth_version 2 — it read "not determined" (so `denied`) under a fresh grant
# (tccd log, 2026-10-18: AUTHREQ_RESULT authValue=1 authVersion=2). simctl also
# has no `limited` at all. So simctl makes the row through tccd, and the row is
# then set to the readWrite model's own values: 2 full, 3 limited, 0 denied.
# This is the simulator's TCC database only (data/Library/TCC/TCC.db).
set -e
. "$(dirname "$0")/_emu_defines.sh"

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
# `flutter test` UNINSTALLS the app when it ends (IntegrationTestTestDevice.kill),
# and a grant made while the app is not installed does not survive the next
# install — the first run of this script read `denied` that way. So the app is
# installed first (any build: the bundle id is what the grant attaches to), the
# permission is set on it, and `flutter test`'s own install is then an UPDATE,
# which keeps it.
install_any() {
  app="$REPO/build/ios/iphonesimulator/Runner.app"
  if [ ! -d "$app" ]; then
    flutter build ios --simulator --debug -t integration_test/sweep_bridge_test.dart
  fi
  xcrun simctl install "$udid" "$app"
}

tcc="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/TCC/TCC.db"
set_photos() {  # 2 full · 3 limited · 0 denied (the readWrite model, auth_version 2)
  xcrun simctl privacy "$udid" grant photos "$bundle"
  sqlite3 "$tcc" "update access set auth_value=$1, auth_version=2 \
    where service='kTCCServicePhotos' and client='$bundle';"
  got="$(sqlite3 "$tcc" "select auth_value||'/'||auth_version from access \
    where service='kTCCServicePhotos' and client='$bundle';")"
  [ "$got" = "$1/2" ] || { echo "tool: photo permission not set ($got)" >&2; exit 1; }
}

for phase in granted:2 limited:3 denied:0; do
  install_any
  set_photos "${phase#*:}"
  echo "tool: photo access ${phase%%:*}"
  flutter test integration_test/sweep_bridge_test.dart -d "$udid" --timeout none \
    --dart-define=SWEEP_BRIDGE_PHASE="${phase%%:*}"
done
