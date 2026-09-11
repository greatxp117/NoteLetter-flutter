#!/bin/sh
# The one place the emulator dart-defines are spelled. Sourced by dev.sh and
# shots.sh so the ports the app runs against and the ports the screenshot
# capture runs against cannot drift apart — two copies of a port list is how a
# capture ends up photographing a different database from the one you seeded.
#
# Override with the environment (EMULATOR_FIRESTORE_PORT=8580 tool/dev.sh ios)
# when running beside another workspace's suite on the defaults (/emu).

EMU_FIRESTORE_PORT="${EMULATOR_FIRESTORE_PORT:-8080}"
EMU_AUTH_PORT="${EMULATOR_AUTH_PORT:-9099}"
EMU_FUNCTIONS_PORT="${EMULATOR_FUNCTIONS_PORT:-5099}"
# Storage and Pub/Sub are not dart-defines (the app has no Storage SDK and no
# Pub/Sub client) but the identity gate asks about ALL FIVE emulators, and the
# alt-port recipe in /emu moves all five — a check that asks about two of them
# on the wrong ports reads "absent" and refuses a suite that is up.
EMU_STORAGE_PORT="${EMULATOR_STORAGE_PORT:-9199}"
EMU_PUBSUB_PORT="${EMULATOR_PUBSUB_PORT:-8085}"

EMU_DEFINES="--dart-define=USE_EMULATOR=true \
--dart-define=EMULATOR_FIRESTORE_PORT=$EMU_FIRESTORE_PORT \
--dart-define=EMULATOR_AUTH_PORT=$EMU_AUTH_PORT \
--dart-define=EMULATOR_FUNCTIONS_PORT=$EMU_FUNCTIONS_PORT \
--dart-define=EMULATOR_FUNCTIONS_SHIM=true"

# Resolved from git, not from $0: this file is SOURCED, and a sourced file's
# $0 is whatever shell sourced it (the skill's one-liner `. tool/_emu_defines.sh
# && emu_sim_udid` resolved ROOT two directories too high on its first run).
REPO="$(git rev-parse --show-toplevel 2>/dev/null)"
case "$REPO" in
  */NoteLetter-flutter) ;;
  *) echo "tool: run this from inside NoteLetter-flutter (got '$REPO')" >&2; exit 1 ;;
esac
ROOT="$(cd "$REPO/.." && pwd)"

# Is the suite on those ports OURS? A listening port is not an answer (5t):
# the 10MB workspace holds the defaults and is often mid-run.
emu_assert_ours() {
  identity="$ROOT/NoteLetter-contracts/harness/emulator_identity.py"
  if [ ! -f "$identity" ]; then
    echo "tool: $identity is missing — cannot prove the emulator is ours. Refusing." >&2
    exit 1
  fi
  FIRESTORE_EMULATOR_HOST="localhost:$EMU_FIRESTORE_PORT" \
  FIREBASE_AUTH_EMULATOR_HOST="localhost:$EMU_AUTH_PORT" \
  STORAGE_EMULATOR_HOST="http://localhost:$EMU_STORAGE_PORT" \
  FIREBASE_STORAGE_EMULATOR_HOST="localhost:$EMU_STORAGE_PORT" \
  PUBSUB_EMULATOR_HOST="localhost:$EMU_PUBSUB_PORT" \
  python3 "$identity" || {
    echo "" >&2
    echo "tool: the emulator on these ports is not proven ours (or is absent)." >&2
    echo "      (alt ports? export EMULATOR_{FIRESTORE,AUTH,STORAGE,PUBSUB,FUNCTIONS}_PORT first)" >&2
    echo "      Start it per /emu from NoteLetter-Firebase-Functions/:" >&2
    echo "        firebase emulators:start --project noteletter-7a111 \\" >&2
    echo "          --only auth,firestore,storage,pubsub --import ../NoteLetter-contracts/emulator-seed" >&2
    echo "      and the functions shim:" >&2
    echo "        (cd functions && venv/bin/python dev_server.py $EMU_FUNCTIONS_PORT)" >&2
    exit 1
  }
}

# The simulator by NAME, resolved to a UDID. Never `booted`: two simulators
# are routinely booted on this machine and `xcrun simctl io booted` picks one.
emu_sim_udid() {
  name="${NL_SIM_NAME:-iPhone 17}"
  xcrun simctl list devices available -j | python3 -c "
import json,sys
name=sys.argv[1]
d=json.load(sys.stdin)
hits=[x for r in d['devices'].values() for x in r if x['name']==name]
if not hits: sys.exit('no simulator named %r; set NL_SIM_NAME' % name)
print(hits[0]['udid'])" "$name"
}
