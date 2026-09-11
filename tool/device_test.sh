#!/bin/sh
# The device run, or one test of it, on the iPhone 17 simulator against the
# emulator suite.
#
#   tool/device_test.sh                                   the whole run
#   tool/device_test.sh "signs in and reaches the library"   one test, by --plain-name
#
# Exists because the defines are a LIST and zsh does not word-split an unquoted
# variable: `flutter test … $EMU_DEFINES` from an interactive zsh hands Flutter
# one argument reading "--dart-define=USE_EMULATOR=true --dart-define=…", the
# app boots without USE_EMULATOR, and the test refuses (correctly) in setUpAll.
# A POSIX sh splits it. So every path that runs the app goes through a script.
#
# Reader items need the long document seeded first (and again after every
# emulator restart — the seed import does not carry it):
#   FIRESTORE_EMULATOR_HOST=localhost:<firestore port> python3 tool/seed_long_doc.py
set -e
. "$(dirname "$0")/_emu_defines.sh"

emu_assert_ours
udid="$(emu_sim_udid)"
xcrun simctl boot "$udid" 2>/dev/null || true

cd "$REPO"
if [ -n "${1:-}" ]; then
  echo "tool: device test \"$1\" on $udid (emulator firestore:$EMU_FIRESTORE_PORT auth:$EMU_AUTH_PORT shim:$EMU_FUNCTIONS_PORT)"
  # shellcheck disable=SC2086
  exec flutter test integration_test/device_run_test.dart -d "$udid" --timeout none \
    $EMU_DEFINES --plain-name "$1"
else
  echo "tool: the whole device run on $udid"
  # shellcheck disable=SC2086
  exec flutter test integration_test/device_run_test.dart -d "$udid" --timeout none $EMU_DEFINES
fi
