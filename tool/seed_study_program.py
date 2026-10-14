"""Write the study program web's `study-edit` frame shows, and take it away.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_study_program.py [--remove]

The seed holds no study program, so `study` frames the empty state and the
program editor of an EXISTING program has nothing to open. Web's theme-shots
writes `shot-study-program` before its `study-edit` shot and deletes it after
(NoteLetter-web/scripts/theme-shots.mjs, 'study-edit'); this writes the same
document, field for field, so the two clients frame one state:

  "Cooking fundamentals" over two of the seed's complete sources — the article
  answered as notes, the PDF as a reading through passage 3 — unit 1, begun six
  days ago, created nine days ago.

Shoot `study` (the empty state) BEFORE this and `study-edit` after it, then
`--remove`. Writes through the emulator REST with `Bearer owner`, which bypasses
rules — study programs are read-only to clients (INV-04).
"""
import json, os, sys, time, urllib.error, urllib.request
from datetime import datetime, timezone

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
ROOT = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
DOC = "shot-study-program"
AUTH = {"Authorization": "Bearer owner", "Content-Type": "application/json"}


def call(url, method, body=None):
    req = urllib.request.Request(url, method=method, headers=AUTH,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        return json.loads(urllib.request.urlopen(req).read() or b"{}")
    except urllib.error.HTTPError as e:
        if method == "DELETE" and e.code == 404:
            return {}
        raise


S = lambda v: {"stringValue": v}                    # noqa: E731
I = lambda v: {"integerValue": str(v)}              # noqa: E731
B = lambda v: {"booleanValue": v}                   # noqa: E731
N = {"nullValue": None}
A = lambda vs: {"arrayValue": {"values": vs}}       # noqa: E731
M = lambda f: {"mapValue": {"fields": f}}           # noqa: E731


def T(ms):
    ts = datetime.fromtimestamp(ms / 1000, tz=timezone.utc)
    return {"timestampValue": ts.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"}


if "--remove" in sys.argv:
    call(f"{ROOT}/study_programs/{DOC}", "DELETE")
    print(f"removed {DOC}")
    sys.exit(0)

now = int(time.time() * 1000)
day = 86400000
fields = {
    "user_id": S(UID), "title": S("Cooking fundamentals"),
    "document_ids": A([S("seed-doc-article-complete"), S("seed-doc-pdf-complete")]),
    "enabled": B(True), "status": S("active"),
    "delivery_time": S("07:00"), "timezone": S("America/Chicago"), "frequency": S("daily"),
    "email_enabled": B(True), "email_address": S(""),
    "new_per_session": I(5), "max_reviews_per_session": I(10),
    "unit_count": I(5), "introduced_count": I(2),
    "sources": M({
        "seed-doc-article-complete": M({"kind": S("notes"), "position": N}),
        "seed-doc-pdf-complete": M({"kind": S("reading"), "position": I(2)}),
    }),
    "unit_started_at": T(now - 6 * day), "unit_number": I(1),
    "material_runway": I(1), "low_material_notified_at": N, "low_material_reason": N,
    "dismissed_prompts": A([]),
    "created_at": T(now - 9 * day), "updated_at": T(now - day),
}
call(f"{ROOT}/study_programs/{DOC}", "PATCH", {"fields": fields})
print(f"wrote {DOC} (Cooking fundamentals, 2 sources, unit 1)")
