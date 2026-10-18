#!/bin/sh
# The camera-roll sweep IN THE BACKGROUND on the simulator, against the
# EMULATOR suite (F-125 S4): integration_test/sweep_background_test.dart.
#
#   eval "$(tool/emu_alt.sh env)"        # after `tool/emu_alt.sh up`
#   tool/sweep_background_test.sh
#
# It
#   1. proves the emulator on the exported ports is ours (emu_assert_ours) — a
#      pass opens capture sessions, which WRITE documents;
#   2. adds the four test photos (tool/sweep_test_photos.py, simctl addmedia);
#   3. installs the app and sets FULL photo access in the simulator's own TCC
#      database (simctl's grant does not reach .readWrite on iOS 26.5:
#      tool/sweep_bridge_test.sh);
#   4. runs the hold proxy (tool/sweep_hold_proxy.py) on localhost, which
#      holds an upload $NL_SWEEP_HOLD_MS (default 50000) before passing it to
#      the storage emulator — longer than iOS's ~30 s of background running
#      time, so it lands after the app is suspended;
#   5. runs the test with the emulator defines (the app refuses prod) and,
#      when it prints SWEEP:BACKGROUND, opens the Settings app over it — the
#      app goes to the background with its upload in flight — and brings it
#      back $NL_SWEEP_AWAY seconds later (default 100);
#   6. prints RunningBoard's record of the app's states while it was away
#      (running-active / running-suspended), beside when the bytes landed;
#   7. resets the permission and stops the proxy on exit.
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
away="${NL_SWEEP_AWAY:-100}"
hold_ms="${NL_SWEEP_HOLD_MS:-50000}"
proxy_port="${NL_SWEEP_PROXY_PORT:-8597}"
xcrun simctl boot "$udid" 2>/dev/null || true

work="$(mktemp -d)"
proxy_pid=""
cleanup() {
  [ -n "$proxy_pid" ] && kill "$proxy_pid" 2>/dev/null || true
  rm -rf "$work"
  xcrun simctl privacy "$udid" reset photos "$bundle" 2>/dev/null || true
}
trap cleanup EXIT

python3 "$REPO/tool/sweep_test_photos.py" "$work/add" >/dev/null
for f in "$work"/add/*.jpg; do xcrun simctl addmedia "$udid" "$f"; done
echo "tool: added $(ls "$work/add" | wc -l | tr -d ' ') photos to $udid"

if lsof -nP -tiTCP:"$proxy_port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "tool: port $proxy_port is taken; set NL_SWEEP_PROXY_PORT" >&2
  exit 1
fi
python3 "$REPO/tool/sweep_hold_proxy.py" "$proxy_port" "$work/proxy.log" &
proxy_pid=$!

cd "$REPO"
app="$REPO/build/ios/iphonesimulator/Runner.app"
if [ ! -d "$app" ]; then
  # shellcheck disable=SC2086
  flutter build ios --simulator --debug -t integration_test/sweep_background_test.dart $EMU_DEFINES
fi
xcrun simctl install "$udid" "$app"
tcc="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/TCC/TCC.db"
xcrun simctl privacy "$udid" grant photos "$bundle"
sqlite3 "$tcc" "update access set auth_value=2, auth_version=2 \
  where service='kTCCServicePhotos' and client='$bundle';"
got="$(sqlite3 "$tcc" "select auth_value||'/'||auth_version from access \
  where service='kTCCServicePhotos' and client='$bundle';")"
[ "$got" = "2/2" ] || { echo "tool: photo permission not set ($got)" >&2; exit 1; }

echo "tool: full photo access; sweep background test on $udid (emulator firestore:$EMU_FIRESTORE_PORT auth:$EMU_AUTH_PORT shim:$EMU_FUNCTIONS_PORT; hold proxy :$proxy_port)"
log="$(mktemp -t nl-sweep-bg)"
# shellcheck disable=SC2086
flutter test integration_test/sweep_background_test.dart -d "$udid" --timeout none \
  $EMU_DEFINES --dart-define=SWEEP_HOLD_PROXY="http://localhost:$proxy_port" \
  --dart-define=SWEEP_HOLD_MS="$hold_ms" >"$log" 2>&1 &
pid=$!
sent=0
while kill -0 "$pid" 2>/dev/null; do
  if [ "$sent" = 0 ] && grep -qF 'SWEEP:BACKGROUND' "$log"; then
    xcrun simctl launch "$udid" com.apple.Preferences >/dev/null
    went="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "tool: $(date -u +%H:%M:%S)Z the app is in the background (Settings opened over it)"
    sleep "$away"
    xcrun simctl launch "$udid" "$bundle" >/dev/null
    back="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "tool: $(date -u +%H:%M:%S)Z the app is back in the foreground"
    sent=1
  fi
  sleep 1
done
set +e
wait "$pid"
rc=$?
set -e
grep -E 'sweep bg:|SWEEP:|tests? passed|Some tests failed|EXCEPTION|Expected|Actual|reason|timed out|Error' "$log" | cut -c1-600
echo "tool: proxy log:"; cat "$work/proxy.log" 2>/dev/null || true
if [ "$sent" = 1 ]; then
  echo "tool: RunningBoard, $bundle, while away (local time):"
  xcrun simctl spawn "$udid" log show --start "$went" --end "$back" --style compact \
    --predicate "process == \"runningboardd\" AND eventMessage CONTAINS \"Calculated state for app<$bundle\"" 2>/dev/null \
    | grep -oE '^[0-9-]+ [0-9:.]+|: (running-[a-z]+|none) \(role: [A-Za-z]+\)' | paste -d' ' - - | uniq -f2
  echo "tool: the app's own record of being woken for its upload session:"
  xcrun simctl spawn "$udid" log show --start "$went" --end "$back" --style compact \
    --predicate "process == \"Runner\" AND eventMessage CONTAINS[c] \"handleEventsForBackgroundURLSession\"" 2>/dev/null \
    | grep -E '^20' | cut -c1-200 | head -5
fi
echo "tool: log kept at $log (exit $rc)"
exit "$rc"
