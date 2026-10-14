"""Stamp the four cooldowns web frames as held controls, and put them back.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_wait_states.py [--remove]

Web's `letter-send-wait`, `study-wait`, `retry-wait` and `sync-wait`
(NoteLetter-web/scripts/theme-shots.mjs, 7ef365c) each stamp the endpoint's
OWN cooldown field, press the control, require the real 429 and its
`retry_after_s`, and frame the held control counting down. This writes the
same four stamps, so the holds of the same names press the same controls into
the same refusals:

  letter-send-wait  the newest letter's `generated_at` → now
                    (fn_request_newsletter refuses within 60s of it)
  study-wait        web's study-edit program and one session of it, generated
                    now (fn_request_study_session: 60s of the newest session)
  retry-wait        seed-doc-error's `last_retry_at` → now
                    (fn_retry_document: 300s)
  sync-wait         the Drive integration's `last_manual_sync_at` → now
                    (fn_request_cloud_sync: 300s)

Each stamp is written AHEAD of now (the 60s windows by ten minutes, the 300s
ones by two): the app is built and launched between this script and the
press, and a 60s window stamped "now" had lapsed by the time study-wait
pressed (2026-10-14 — the request was accepted, the frame never existed).
`_cooldown_left` clamps a stamp ahead of its clock to the window, so the held
label still counts down from at most 1:00 / 5:00, as web's does.

What it changed is saved in .dart_tool/seed_wait_states.json and `--remove`
puts it back (a field that was absent is deleted again). Writes through the
emulator REST with `Bearer owner`, which bypasses rules.
"""
import json, os, sys, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
AUTH = {"Authorization": "Bearer owner", "Content-Type": "application/json"}
STATE = Path(__file__).resolve().parent.parent / ".dart_tool" / "seed_wait_states.json"
PROG = "shot-study-program"
SESS = f"{UID}_{PROG}_shot"


def call(url, method, body=None):
    req = urllib.request.Request(url, method=method, headers=AUTH,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        return json.loads(urllib.request.urlopen(req).read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 404 and method in ("GET", "DELETE"):
            return None
        raise


def now_ts(ahead_s=0):
    at = datetime.now(timezone.utc) + timedelta(seconds=ahead_s)
    return {"timestampValue": at.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"}


def read_field(path, field):
    doc = call(f"{BASE}/{path}", "GET")
    if doc is None:
        raise SystemExit(f"{path} does not exist — seed it first")
    return doc.get("fields", {}).get(field)


def set_field(path, field, value):
    q = urllib.parse.urlencode({"updateMask.fieldPaths": field})
    body = {"fields": {field: value}} if value is not None else {"fields": {}}
    call(f"{BASE}/{path}?{q}", "PATCH", body)


def newest_letter():
    q = {"structuredQuery": {"from": [{"collectionId": "newsletters"}], "where": {
        "fieldFilter": {"field": {"fieldPath": "user_id"}, "op": "EQUAL",
                        "value": {"stringValue": UID}}}}}
    rows = [r["document"] for r in call(f"{BASE}:runQuery", "POST", q) if "document" in r]
    if not rows:
        raise SystemExit("no letter to stamp — run tool/seed_letters.py first")
    rows.sort(key=lambda d: d.get("fields", {}).get("generated_at", {})
              .get("timestampValue", ""), reverse=True)
    return rows[0]["name"].split("/documents/")[1]


STAMPS = lambda letter: [  # noqa: E731  (path, field, seconds ahead)
    (letter, "generated_at", 600),
    ("documents/seed-doc-error", "last_retry_at", 120),
    (f"users/{UID}/integrations/google_drive", "last_manual_sync_at", 120),
]

if "--remove" in sys.argv:
    saved = json.loads(STATE.read_text()) if STATE.exists() else {"fields": []}
    for path, field, value in saved["fields"]:
        set_field(path, field, value)
    call(f"{BASE}/study_sessions/{SESS}", "DELETE")
    call(f"{BASE}/study_programs/{PROG}", "DELETE")
    STATE.unlink(missing_ok=True)
    print(f"restored {len(saved['fields'])} field(s); removed {PROG} and its session")
    sys.exit(0)

letter = newest_letter()
saved = []
for path, field, ahead in STAMPS(letter):
    saved.append([path, field, read_field(path, field)])
    set_field(path, field, now_ts(ahead))
STATE.parent.mkdir(exist_ok=True)
STATE.write_text(json.dumps({"fields": saved}))

# study-wait: web's study-edit program, and one session of it generated now.
os.system(f'"{sys.executable}" "{Path(__file__).with_name("seed_study_program.py")}"')
S = lambda v: {"stringValue": v}                    # noqa: E731
I = lambda v: {"integerValue": str(v)}              # noqa: E731
session = {
    "user_id": S(UID), "program_id": S(PROG), "program_title": S("Cooking fundamentals"),
    "generated_at": now_ts(600), "trigger": S("manual"), "status": S("sent"),
    "items": {"arrayValue": {}}, "responses": {"mapValue": {"fields": {}}},
    "new_count": I(0), "review_count": I(0), "due_remaining": I(0), "ramp_count": I(0),
}
call(f"{BASE}/study_sessions/{SESS}", "PATCH", {"fields": session})
print(f"stamped {letter}, seed-doc-error, google_drive; wrote {PROG} + {SESS}")
