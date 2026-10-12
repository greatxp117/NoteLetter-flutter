"""Put the emulator into the two states the reference frames `scripture-day` and
`settings-plan` in, and take them away again (F-90 (3), (4)).

Both pairs compared two STATES rather than two drawings of one:

  scripture-day   web theme-shots writes `shot-readings-day` — a readings letter
                  for Friday of week 18 in Ordinary Time with three readings —
                  and makes the Psalm's search fail, so its frame carries the
                  partial notice, the `—` count and the §14.2 line. This client's
                  hold opened the seed's Thursday of week 23 at rest. This
                  writes web's letter, word for word, dated as web's committed
                  frame is (Friday, October 2 2026); the hold opens it and arms
                  the same failure.

  settings-plan   the reference frames the Plan row AT its cap, with §12's
                  notice and *Ask about upgrading*; this client's hold framed the
                  plain row. This writes `config/plans` with the free plan's
                  `max_documents` at the seed reader's own count, so the row is
                  at its cap the way the reference's is. `_plan_limits()` caches
                  the plan for 60s per backend instance: write it a minute before
                  the shot.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_frame_states.py [--remove]

Writes through the emulator REST with `Bearer owner`, which bypasses rules —
`config/plans` is a document no client may read or write (INV-28).
"""
import json, os, sys, urllib.error, urllib.request

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
ROOT = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
DOC = "shot-readings-day"
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

if "--remove" in sys.argv:
    call(f"{ROOT}/newsletters/{DOC}", "DELETE")
    call(f"{ROOT}/config/plans", "DELETE")
    print(f"removed {DOC} and config/plans")
    sys.exit(0)

# ── scripture-day: web theme-shots `scriptureLetter(date)` ──────────────────
REFS = ["Isaiah 55:1-11", "Psalm 42", "John 6:1-15"]
DAY = "Friday of week 18 in Ordinary Time"
call(f"{ROOT}/newsletters/{DOC}", "PATCH", {"fields": {
    "user_id": S(UID),
    "generated_at": {"timestampValue": "2026-10-02T12:00:00Z"},
    "kind": S("scripture"),
    "status": S("sent"),
    "subject": S(f"Your readings — {DAY}"),
    "liturgical_day": M({
        "date": S("2026-10-02"), "calendar": S("roman"),
        "liturgical_year": S("2026"), "season": S("ordinary_time"),
        "week": I(18), "weekday": S("friday"), "cycle": S("B"),
        "id": S("ot-18"), "name": S(DAY), "keys": A([S("ot-18")]),
    }),
    # `lead` is a BOOL on every letter the backend writes (main.py
    # `"lead": bool(r.get("lead"))`). Web's shot writes each reading's opening
    # line there — a string, truthy, so all three draw as lead rows on web —
    # and this client's model reads the field typed, so a string made the
    # whole newsletters subscription fail ("Your letters could not be read").
    # True for all three: the shape the backend writes, drawn as the
    # reference draws it.
    "readings": A([M({
        "label": S(["First reading", "Psalm", "Gospel"][i]),
        "ref": S(ref), "lead": B(True),
        "passages": A([]), "match_total": I(0),
    }) for i, ref in enumerate(REFS)]),
    "passages_sent": I(3), "passages_found": I(5),
    "bible_on_shelf": B(False), "verse_source": S("none"), "verse_edition": N,
}})

# ── settings-plan: the free plan capped at the reader's own count ───────────
res = call(f"{ROOT}:runQuery", "POST", {"structuredQuery": {
    "from": [{"collectionId": "documents"}],
    "where": {"fieldFilter": {"field": {"fieldPath": "user_id"},
                              "op": "EQUAL", "value": S(UID)}},
}})
count = sum(1 for r in res if "document" in r) if isinstance(res, list) else 0
# Only the cap: `_plan_limits()` merges this block over `_PLAN_DEFAULTS`, and
# every other figure on the row (the month's ingests, narration) must stay the
# default the reference frames — a 40 written here drew "0 of 40" against
# web's "0 of 60".
call(f"{ROOT}/config/plans", "PATCH", {"fields": {
    "free": M({"max_documents": I(count)}),
}})
print(f"seeded {DOC} ({DAY}, 2026-10-02) and config/plans (free cap {count} "
      f"= {UID}'s documents)")
