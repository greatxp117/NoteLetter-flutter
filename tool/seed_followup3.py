"""The states web 7f85b50 frames the 2026-10-14 rulings in, and back.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_followup3.py uncounted|pinned|stalled
    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_followup3.py --remove

One state at a time, as web writes each inside its own shot: an uncounted
source in a Sources frame must not also carry a stalled card, and a pin must
not sit on every later Letters frame.

As web theme-shots writes them (withUncounted, letters-unpin-held,
activity-stalled):

  seed-doc-pdf-complete       chunk_count deleted   → library-uncounted,
                                                      sources-uncounted
  seed-doc-article-complete   next_letter_requested_at = now (pinned)
                                                    → letters-unpin-held
  shot-stalled-queued         a queued pdf whose processing_stalls_at is an
                              hour ago, chunk_count null → activity-stalled

What it changed is saved in .dart_tool/seed_followup3.json the first time and
`--remove` puts each field back and deletes the shot document. Writes through
the emulator REST with `Bearer owner`, which bypasses rules.
"""
import json, os, sys, urllib.error, urllib.parse, urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
AUTH = {"Authorization": "Bearer owner", "Content-Type": "application/json"}
STATE = Path(__file__).resolve().parent.parent / ".dart_tool" / "seed_followup3.json"
STALLED = "documents/shot-stalled-queued"


def call(url, method, body=None):
    req = urllib.request.Request(url, method=method, headers=AUTH,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        return json.loads(urllib.request.urlopen(req).read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 404 and method in ("GET", "DELETE"):
            return None
        raise


def ts(dt):
    return {"timestampValue": dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"}


def read_field(path, field):
    doc = call(f"{BASE}/{path}", "GET")
    if doc is None:
        raise SystemExit(f"{path} does not exist — seed it first")
    return doc.get("fields", {}).get(field)


def set_field(path, field, value):
    q = urllib.parse.urlencode({"updateMask.fieldPaths": field})
    call(f"{BASE}/{path}?{q}", "PATCH",
         {"fields": {field: value}} if value is not None else {"fields": {}})


FIELDS = [("documents/seed-doc-pdf-complete", "chunk_count"),
          ("documents/seed-doc-article-complete", "next_letter_requested_at")]

if "--remove" in sys.argv:
    saved = json.loads(STATE.read_text()) if STATE.exists() else {"fields": []}
    for path, field, value in saved["fields"]:
        set_field(path, field, value)
    call(f"{BASE}/{STALLED}", "DELETE")
    STATE.unlink(missing_ok=True)
    print(f"restored {len(saved['fields'])} field(s); removed shot-stalled-queued")
    sys.exit(0)

if not STATE.exists():
    STATE.parent.mkdir(exist_ok=True)
    STATE.write_text(json.dumps(
        {"fields": [[p, f, read_field(p, f)] for p, f in FIELDS]}))

now = datetime.now(timezone.utc)
mode = next((a for a in sys.argv[1:] if not a.startswith("-")), "")
if mode == "uncounted":
    set_field("documents/seed-doc-pdf-complete", "chunk_count", None)
    print("uncounted seed-doc-pdf-complete")
    sys.exit(0)
if mode == "pinned":
    set_field("documents/seed-doc-article-complete", "next_letter_requested_at",
              ts(now))
    print("pinned seed-doc-article-complete")
    sys.exit(0)
if mode != "stalled":
    raise SystemExit("usage: seed_followup3.py uncounted|pinned|stalled|--remove")
call(f"{BASE}/{STALLED}", "PATCH", {"fields": {
    "user_id": {"stringValue": UID},
    "title": {"stringValue": "Field notes, never started"},
    "type": {"stringValue": "pdf"},
    "status": {"stringValue": "queued"},
    "created_at": ts(now),
    "processing_stalls_at": ts(now - timedelta(hours=1)),
    "tag_ids": {"arrayValue": {}},
    "chunk_count": {"nullValue": None},
    "word_count": {"nullValue": None},
}})
print("wrote shot-stalled-queued")
