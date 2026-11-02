"""A source's History with something in both halves (5.44.0, ADR-199; F-147),
for the `reader-history`, `reader-history-activity` and `reader-history-refused`
pairs.

The canonical seed holds no read event or Activity event for
`seed-doc-pdf-complete`, so this writes the rows web's own shot writes
(`theme-shots.mjs` `withSourceHistory` — keep the two alike): a first
extraction that failed, the note and the index of the run that worked, the
organizer filing the file, and an evening's reading.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_history.py              # write the rows
    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_history.py --deny-reads # + refuse read_events
    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_history.py --remove     # rows gone, rules back

`--deny-reads` swaps the emulator's ruleset for the backend's
`firestore.rules` with `/read_events`' `allow read` turned off — derived from
the file, never a second hand-written ruleset — so the hold photographs a real
`permission-denied` from the real query while the Activity half still answers.
`--remove` deletes the rows and puts the file's rules back. Run it after the
shot: a leftover row would sit in every reader frame after it.

Writes with `Bearer owner`, which bypasses rules — a client cannot write
/activity_events (INV-04) or another reader's /read_events.
"""
import json, os, sys, urllib.request
from pathlib import Path

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
PROJECT = "noteletter-7a111"
BASE = f"http://{HOST}/v1/projects/{PROJECT}/databases/(default)/documents"
RULES_URL = f"http://{HOST}/emulator/v1/projects/{PROJECT}:securityRules"
RULES_FILE = Path(__file__).resolve().parents[2] / "NoteLetter-Firebase-Functions" / "firestore.rules"
UID = "seed-user-1"
DOC = "seed-doc-pdf-complete"

EVENTS = [
    ("shot-hist-failed", {
        "type": "doc_processing_failed", "status": "error", "level": "error",
        "title": "Quarterly Tax Summary",
        "metadata": {"doc_id": DOC, "stage": "extraction",
                     "error": "This PDF could not be opened: the file is damaged."},
        "created_at": "2026-10-08T09:12:00Z"}),
    ("shot-hist-note", {
        "type": "doc_processing_note", "status": "info", "level": "warning",
        "title": "Quarterly Tax Summary",
        "metadata": {"doc_id": DOC,
                     "note": "2 pages had no text layer, so they were read from the page images."},
        "created_at": "2026-10-08T09:39:00Z"}),
    ("shot-hist-indexed", {
        "type": "doc_indexed", "status": "complete", "level": "success",
        "title": "Quarterly Tax Summary", "metadata": {"doc_id": DOC, "chunk_count": 2},
        "created_at": "2026-10-08T09:40:00Z"}),
    ("shot-hist-placed", {
        "type": "organization_placement", "status": "complete", "level": "success",
        "title": "Placed taxes.pdf → /Finance/2026", "provider": "google_drive",
        "metadata": {"doc_id": DOC, "to": "/Finance/2026", "auto": True},
        "created_at": "2026-10-09T07:02:00Z"}),
]
READS = [
    ("shot-hist-r1", "doc_opened", None, "2026-10-10T20:05:00Z"),
    ("shot-hist-r2", "chunk_read", "seed-chunk-pdf-0", "2026-10-10T20:06:00Z"),
    ("shot-hist-r3", "chunk_read", "seed-chunk-pdf-1", "2026-10-10T20:09:00Z"),
    ("shot-hist-r4", "chunk_viewed", "seed-chunk-pdf-1", "2026-10-14T11:30:00Z"),
]


def call(url, method, body=None, auth=True):
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["Authorization"] = "Bearer owner"
    req = urllib.request.Request(
        url, method=method, headers=headers,
        data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        if method == "DELETE" and e.code == 404:
            return {}
        raise


def value(v, key=None):
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: value(x, k) for k, x in v.items()}}}
    if key == "created_at":
        return {"timestampValue": v}
    return {"stringValue": v}


def put(path, fields):
    call(f"{BASE}/{path}", "PATCH", {"fields": {k: value(v, k) for k, v in fields.items()}})


def rules_denying_read(src, collection):
    at = src.index(f"match /{collection}/")
    start = src.index("allow read:", at)
    nxt = src.find("match /", at + 1)
    end = src.index(";", start)
    if nxt != -1 and start > nxt:
        raise SystemExit(f"no 'allow read:' inside /{collection}'s block")
    return src[:start] + "allow read: if false" + src[end:]


def set_rules(content):
    call(RULES_URL, "PUT", {"rules": {"files": [{"name": "firestore.rules", "content": content}]}},
         auth=False)


def main():
    args = set(sys.argv[1:])
    if "--remove" in args:
        for eid, _ in EVENTS:
            call(f"{BASE}/activity_events/{eid}", "DELETE")
        for rid, *_ in READS:
            call(f"{BASE}/read_events/{rid}", "DELETE")
        set_rules(RULES_FILE.read_text())
        print(f"removed {len(EVENTS)} events and {len(READS)} reads; rules restored from {RULES_FILE.name}")
        return
    for eid, e in EVENTS:
        put(f"activity_events/{eid}", {"user_id": UID, **e})
    for rid, typ, chunk, at in READS:
        put(f"read_events/{rid}", {"user_id": UID, "event_type": typ, "document_id": DOC,
                                   "chunk_id": chunk, "created_at": at})
    print(f"wrote {len(EVENTS)} events and {len(READS)} reads for {DOC}")
    if "--deny-reads" in args:
        set_rules(rules_denying_read(RULES_FILE.read_text(), "read_events"))
        print("rules: /read_events allow read turned off (run --remove after the shot)")


if __name__ == "__main__":
    main()
