"""Seed a document long enough to SCROLL, for the device run.

The canonical emulator seed's complete documents are 9-54 words each — shorter
than a phone viewport. That is right for the fixture suites (they assert shapes,
not layout) but it means the passage mark's scroll tracking cannot be exercised
at all: with nothing to scroll, every passage sits above the reading line and
the fill pins at 1.0 from the first frame.

Writes through the emulator REST with `Bearer owner`, which bypasses rules — a
client cannot write /documents directly (INV-04).
"""
import json, os, urllib.request

# The suite's host, from the same env var every other tool here reads (/emu).
# It was hardcoded to the alt-port 8580, which silently wrote nothing useful
# when the suite came up on the defaults — the device run then failed with
# "run tool/seed_long_doc.py first", having just been run.
HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
DOC = "device-run-long-doc"

PARA = ("The reader moves the pointer, and the passage is the unit that the "
        "system tracks. Each of these sentences exists so that this passage is "
        "taller than the viewport it is rendered into, because a mark that "
        "reports scroll progress cannot be exercised by a document that never "
        "scrolls. ")

def put(path, fields):
    req = urllib.request.Request(
        f"{BASE}/{path}", method="PATCH",
        data=json.dumps({"fields": fields}).encode(),
        headers={"Authorization": "Bearer owner", "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()

put(f"documents/{DOC}", {
    "user_id": {"stringValue": UID},
    "title": {"stringValue": "Device run — a document long enough to scroll"},
    "type": {"stringValue": "article"},
    "status": {"stringValue": "complete"},
    "chunk_count": {"integerValue": "6"},
    "word_count": {"integerValue": "1200"},
    "source_priority": {"doubleValue": 0.5},
    "view_count": {"integerValue": "0"},
    "created_at": {"timestampValue": "2026-08-16T12:00:00Z"},
    "processed_at": {"timestampValue": "2026-08-16T12:01:00Z"},
    "summary": {"stringValue": "A long document used only by the device run."},
})

for i in range(6):
    body = (PARA * 5)
    put(f"chunks/device-run-chunk-{i}", {
        "user_id": {"stringValue": UID},
        "document_id": {"stringValue": DOC},
        "chunk_index": {"integerValue": str(i)},
        "text": {"stringValue": body},
        "html": {"stringValue": f"<p>{body}</p>"},
        # UNCOUNTED on purpose: a counted passage renders full regardless of
        # scroll, so a counted fixture could never show the bar rising.
        "view_count": {"integerValue": "0"},
        "user_edited": {"booleanValue": False},
        "source_type": {"stringValue": "article"},
        "source_priority": {"doubleValue": 0.5},
        "last_viewed_at": {"nullValue": None},
        "created_at": {"timestampValue": "2026-08-16T12:01:00Z"},
        "tag_ids": {"arrayValue": {}},
    })
print("seeded", DOC, "with 6 uncounted chunks")
