#!/bin/sh
# A scratch emulator suite on the ALTERNATE ports, for frame batches and the
# device run, beside whatever holds the defaults (the 10MB workspace's suite
# usually does; never kill it).
#
#   tool/emu_alt.sh up      boot from the canonical seed, add the frame seeds,
#                           start the functions shim (NL_DEV_FAKES=1) on 5599
#   tool/emu_alt.sh down    stop all of it
#   tool/emu_alt.sh env     print the exports a batch needs (`eval` them)
#
# Ports: firestore 8580 · auth 9599 · storage 9699 · pubsub 8585 · hub 4412 ·
# logging 4512 · shim 5599. The burn-down's EMU lock is the caller's to take
# (`mkdir /tmp/noteletter-emu.lock`) — this script does not take it.
#
# It lives here, not in a session scratchpad: macOS's daily tmp cleanup deletes
# files under /tmp older than three days, and on 2026-10-18 it took the
# batch's boot scripts and alt-port config overnight, mid-job. The Firebase
# config is generated into .dart_tool/ on every `up`, with absolute rule paths,
# so nothing here depends on the directory the emulator is started from.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WS="$(cd "$REPO/.." && pwd)"
FN="$WS/NoteLetter-Firebase-Functions"
PY="$FN/functions/venv/bin/python"
OUT="$REPO/.dart_tool/emu_alt"
mkdir -p "$OUT"

exports() {
  cat <<'EOF'
export FIRESTORE_EMULATOR_HOST=localhost:8580
export FIREBASE_AUTH_EMULATOR_HOST=localhost:9599
export STORAGE_EMULATOR_HOST=http://localhost:9699
export FIREBASE_STORAGE_EMULATOR_HOST=localhost:9699
export PUBSUB_EMULATOR_HOST=localhost:8585
export EMULATOR_FIRESTORE_PORT=8580 EMULATOR_AUTH_PORT=9599 EMULATOR_STORAGE_PORT=9699 EMULATOR_PUBSUB_PORT=8585 EMULATOR_FUNCTIONS_PORT=5599
EOF
}

down() {
  for p in shim emu; do
    [ -f "$OUT/$p.pid" ] && kill "$(cat "$OUT/$p.pid")" 2>/dev/null && echo "stopped $p"
    rm -f "$OUT/$p.pid"
  done
  sleep 5
  pkill -f "dev_server.py 5599" 2>/dev/null || true
  for port in 8580 9599 9699 8585 4412 4512 5599; do
    pid=$(lsof -nP -tiTCP:$port -sTCP:LISTEN 2>/dev/null || true)
    [ -n "$pid" ] && kill $pid 2>/dev/null && echo "killed listener on $port ($pid)"
  done
  true
}

up() {
  for port in 8580 9599 9699 8585 4412 4512 5599; do
    if lsof -nP -tiTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
      echo "tool: port $port is taken — another suite is up (tool/emu_alt.sh down if it is yours)" >&2
      exit 1
    fi
  done
  "$PY" - "$OUT/firebase.alt.json" "$FN" <<'EOF'
import json, sys
out, fn = sys.argv[1], sys.argv[2]
json.dump({
    "firestore": {"rules": fn + "/firestore.rules",
                  "indexes": fn + "/firestore.indexes.json"},
    "storage": {"rules": fn + "/storage.rules"},
    "emulators": {"auth": {"port": 9599}, "firestore": {"port": 8580},
                  "storage": {"port": 9699}, "pubsub": {"port": 8585},
                  "hub": {"port": 4412}, "logging": {"port": 4512},
                  "ui": {"enabled": False}, "singleProjectMode": True},
}, open(out, "w"), indent=2)
EOF
  eval "$(exports)"
  cd "$FN"
  nohup firebase emulators:start --project noteletter-7a111 \
    --config "$OUT/firebase.alt.json" --only auth,firestore,storage,pubsub \
    --import ../NoteLetter-contracts/emulator-seed > "$OUT/emu.log" 2>&1 &
  echo $! > "$OUT/emu.pid"
  i=0
  until grep -q "All emulators ready" "$OUT/emu.log"; do
    i=$((i+1)); [ $i -gt 150 ] && { echo "tool: emulators did not come up"; tail -20 "$OUT/emu.log"; exit 1; }
    sleep 1
  done
  echo "emulators up"
  # The seed import does not carry these; every frame and the device run
  # read them (memory: frame state is not the seed).
  for f in seed_letters.py seed_recipe_and_sources.py seed_long_doc.py; do
    "$PY" "$REPO/tool/$f" >> "$OUT/seed.log" 2>&1 && echo "$f ok" \
      || { echo "$f FAILED"; tail -5 "$OUT/seed.log"; exit 1; }
  done
  cd "$FN/functions"
  PYTHONUNBUFFERED=1 NL_DEV_FAKES=1 nohup "$PY" dev_server.py 5599 > "$OUT/shim.log" 2>&1 &
  echo $! > "$OUT/shim.pid"
  i=0
  until curl -s -o /dev/null http://localhost:5599/; do
    i=$((i+1)); [ $i -gt 90 ] && { echo "tool: shim did not come up"; tail -20 "$OUT/shim.log"; exit 1; }
    sleep 1
  done
  echo "shim up"
}

case "${1:-}" in
  up) up ;;
  down) down ;;
  env) exports ;;
  *) echo "usage: tool/emu_alt.sh up|down|env" >&2; exit 2 ;;
esac
