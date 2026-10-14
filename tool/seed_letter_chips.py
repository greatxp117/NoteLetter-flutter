"""Put the emulator into the states web frames the letter chip in, and back.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_letter_chips.py [--off | --remove]

Web 91026a9 (theme-shots `library-letter-chips`, `library-letter-cards`,
`library-letter-off`, `shelves-letter-chips`, `shelves-letter-off`) frames
the chip over the same data, and this writes it:

  seed-tag-finance  letter_mode = lead    → "Lead"
  seed-tag-recipes  letter_mode = muted   → "Muted"
  seed-tag-stories  untouched (mixed)     → no chip
  settings/newsletter enabled = true, or false with --off (no chip anywhere)

What it changed is saved in .dart_tool/seed_letter_chips.json the first time
and `--remove` puts each field back (one that was absent is deleted again).
Writes through the emulator REST with `Bearer owner`, which bypasses rules.
"""
import json, os, sys, urllib.error, urllib.parse, urllib.request
from pathlib import Path

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
AUTH = {"Authorization": "Bearer owner", "Content-Type": "application/json"}
STATE = Path(__file__).resolve().parent.parent / ".dart_tool" / "seed_letter_chips.json"
SETTINGS = f"users/{UID}/settings/newsletter"


def call(url, method, body=None):
    req = urllib.request.Request(url, method=method, headers=AUTH,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        return json.loads(urllib.request.urlopen(req).read() or b"{}")
    except urllib.error.HTTPError as e:
        if e.code == 404 and method == "GET":
            return None
        raise


def read_field(path, field):
    doc = call(f"{BASE}/{path}", "GET")
    if doc is None:
        raise SystemExit(f"{path} does not exist — seed it first")
    return doc.get("fields", {}).get(field)


def set_field(path, field, value):
    q = urllib.parse.urlencode({"updateMask.fieldPaths": field})
    call(f"{BASE}/{path}?{q}", "PATCH",
         {"fields": {field: value}} if value is not None else {"fields": {}})


FIELDS = [("tags/seed-tag-finance", "letter_mode"),
          ("tags/seed-tag-recipes", "letter_mode"),
          (SETTINGS, "enabled")]

if "--remove" in sys.argv:
    saved = json.loads(STATE.read_text()) if STATE.exists() else {"fields": []}
    for path, field, value in saved["fields"]:
        set_field(path, field, value)
    STATE.unlink(missing_ok=True)
    print(f"restored {len(saved['fields'])} field(s)")
    sys.exit(0)

if not STATE.exists():
    STATE.parent.mkdir(exist_ok=True)
    STATE.write_text(json.dumps(
        {"fields": [[p, f, read_field(p, f)] for p, f in FIELDS]}))

on = "--off" not in sys.argv
set_field("tags/seed-tag-finance", "letter_mode", {"stringValue": "lead"})
set_field("tags/seed-tag-recipes", "letter_mode", {"stringValue": "muted"})
set_field(SETTINGS, "enabled", {"booleanValue": on})
print(f"finance=lead, recipes=muted, letter enabled={str(on).lower()}")
