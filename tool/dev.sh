#!/bin/sh
# Run the app against the emulator suite — the ONLY sanctioned way to run it in
# development (umbrella law 1). A bare `flutter run` is a debug build that
# refuses to boot (lib/main.dart); this script is the convenience half of that
# guard, and the identity check is what makes "the emulator" mean OURS.
#
#   tool/dev.sh chrome            fast iteration; a different renderer from the phone
#   tool/dev.sh ios               the iPhone 17 simulator (NL_SIM_NAME to change)
#   tool/dev.sh ios --release     extra args are passed to flutter run
set -e
. "$(dirname "$0")/_emu_defines.sh"

target="${1:-}"
[ -n "$target" ] && shift || true
case "$target" in
  chrome) device="chrome" ;;
  ios)    device="$(emu_sim_udid)"; xcrun simctl boot "$device" 2>/dev/null || true ;;
  *) echo "usage: tool/dev.sh chrome|ios [flutter run args]" >&2; exit 2 ;;
esac

emu_assert_ours

cd "$REPO"
echo "tool: flutter run -d $device (emulator firestore:$EMU_FIRESTORE_PORT auth:$EMU_AUTH_PORT functions-shim:$EMU_FUNCTIONS_PORT)"
# shellcheck disable=SC2086
exec flutter run -d "$device" $EMU_DEFINES "$@"
