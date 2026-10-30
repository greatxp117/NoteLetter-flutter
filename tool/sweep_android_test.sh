#!/bin/sh
# The camera-roll sweep's device tests on an ANDROID emulator (F-125 S5,
# F-138): the iOS scripts' counterpart, over MediaStore and ML Kit.
#
#   tool/sweep_android_test.sh bridge             # integration_test/sweep_bridge_test.dart
#   eval "$(tool/emu_alt.sh env)"                 # after `tool/emu_alt.sh up`
#   tool/sweep_android_test.sh service            # integration_test/sweep_service_test.dart
#
# Needs one booted emulator (`adb devices`; ANDROID_SERIAL picks among
# several). It
#   1. pushes the four test photos (tool/sweep_test_photos.py) into Pictures/;
#      MediaStore indexes them and reads DATE_TAKEN from their EXIF;
#   2. installs the debug app with every runtime permission granted (`-g`), so
#      `flutter test`'s own install is an UPDATE and keeps READ_MEDIA_IMAGES
#      (the iOS scripts' reason for installing first, in Android's terms);
#   3. for `service`, watches for the test's request to take a photo (a file
#      in the app's cache/) and pushes sweep-dense.jpg again, into
#      DCIM/Camera/: a new MediaStore row under the same DISPLAY_NAME, so the
#      same key (INV-14), as a re-import is on iOS;
#   4. runs the test, and removes that second copy on exit.
set -e
. "$(dirname "$0")/_emu_defines.sh"

what="${1:?usage: tool/sweep_android_test.sh bridge|service}"
case "$what" in
  bridge) test=integration_test/sweep_bridge_test.dart; defines="--dart-define=SWEEP_BRIDGE_PHASE=granted" ;;
  service) emu_assert_ours; test=integration_test/sweep_service_test.dart; defines="$EMU_DEFINES" ;;
  *) echo "tool: bridge or service, not '$what'" >&2; exit 1 ;;
esac
# adb is in the SDK that local.properties names, which is seldom on PATH.
command -v adb >/dev/null ||
  PATH="$(sed -n 's/^sdk.dir=//p' "$REPO/android/local.properties")/platform-tools:$PATH"
serial="${ANDROID_SERIAL:-$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')}"
[ -n "$serial" ] || { echo "tool: no Android device is booted" >&2; exit 1; }
export ANDROID_SERIAL="$serial"
pkg=xp.NoteLetter.Flutter
again=/sdcard/DCIM/Camera/sweep-dense.jpg

scan() {  # Ask MediaStore to index what was pushed; FUSE usually has already.
  adb shell content call --uri content://media --method scan_volume --arg external_primary \
    >/dev/null 2>&1 || true
}

photos="$(mktemp -d)"
watcher=""
cleanup() {
  # Under set -e a failing command here ends the trap early: the watcher has
  # usually exited already, so its kill fails.
  if [ -n "$watcher" ]; then kill "$watcher" 2>/dev/null || true; fi
  rm -rf "$photos"
  adb shell rm -f "$again" >/dev/null 2>&1 || true
  scan
}
trap cleanup EXIT

python3 "$REPO/tool/sweep_test_photos.py" "$photos" >/dev/null
adb shell mkdir -p /sdcard/Pictures /sdcard/DCIM/Camera
adb shell rm -f "$again"
for f in "$photos"/*.jpg; do adb push "$f" "/sdcard/Pictures/$(basename "$f")" >/dev/null; done
scan
echo "tool: pushed $(ls "$photos" | wc -l | tr -d ' ') photos to $serial"

cd "$REPO"
# shellcheck disable=SC2086
flutter build apk --debug -t "$test" $defines
adb install -r -g build/app/outputs/flutter-apk/app-debug.apk >/dev/null
echo "tool: installed with every runtime permission granted"

if [ "$what" = service ]; then
  (
    for _ in $(seq 1 900); do
      # Dart's systemTemp is cache/ or code_cache/, by engine version.
      if adb shell run-as "$pkg" ls cache/sweep-take-a-photo >/dev/null 2>&1 ||
         adb shell run-as "$pkg" ls code_cache/sweep-take-a-photo >/dev/null 2>&1; then
        adb shell run-as "$pkg" rm -f cache/sweep-take-a-photo code_cache/sweep-take-a-photo
        adb push "$photos/sweep-dense.jpg" "$again" >/dev/null
        scan
        echo "tool: took a photo ($again) for the change-token pass"
        exit 0
      fi
      sleep 1
    done
  ) &
  watcher=$!
fi

# shellcheck disable=SC2086
flutter test "$test" -d "$serial" --timeout none $defines
