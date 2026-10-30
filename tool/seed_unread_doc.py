"""Mark as read's document (5.27.0, ADR-184), for the `reader-mark-as-read` pair.

The subject of the frame is an UNREAD passage, and the dwell rule turns any
passage on screen read — the seed's are a few words each, so they read in under
a second and a frame over them would show no control at all. This writes the
document web's own shot writes (`theme-shots.mjs` `writeUnreadDoc`,
`web-shot-unread`): three passages, the first stored READ, the other two unread
and long enough (>= 147 words) that the dwell rule waits its full 10 s cap — so
the frame carries both states, a read foot with no control above an unread one
with it. The hold pauses the dwell clock while it shoots.

`--remove` deletes it again, with the read events the open and any dwell left
behind. Run it after the shot: a leftover would sit in every Library frame.

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_unread_doc.py [--remove]

Writes with `Bearer owner`, which bypasses rules — a client cannot write
/documents (INV-04).
"""
import json, os, sys, urllib.request
from datetime import datetime, timezone

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
DOC = "web-shot-unread"

PASSAGES = [
    ("A commonplace book is not a diary. It keeps what you read rather than "
     "what happened to you, copied out by hand so that the copying is itself "
     "a kind of reading.", 1),
    ("The habit is older than printing. Students in the sixteenth century were "
     "taught to keep one under headings — friendship, death, the uses of "
     "adversity — and to file each passage they met under the heading it "
     "answered, so that a book became, over a lifetime, an index of their own "
     "attention. Locke published a method for it, with a two-page grid for "
     "finding any heading by its first letter and first vowel, and the grid "
     "was reprinted for a hundred years after anyone remembered why the vowel "
     "mattered. What the method understood, and what a search box does not, "
     "is that the act of choosing where a passage belongs is most of the work "
     "of understanding it. You cannot file a sentence under adversity without "
     "deciding that it is about adversity, and the decision is the thing you "
     "keep long after the sentence itself has gone. Copying slows the reader "
     "down to the speed of the hand, which is roughly the speed of thought, "
     "and that is the point of it.", 0),
    ("A modern reader keeps the same book in a different shape. The headings "
     "are shelves, the copying is a highlight, and the index is a search that "
     "reads meaning rather than letters — but the question underneath has not "
     "moved. Which of the things I read do I want to meet again, and when? "
     "Most of what anyone reads is read once and gone, and that is as it "
     "should be; a library that kept everything would be no easier to use "
     "than one that kept nothing. The passages worth keeping announce "
     "themselves slowly. They come back unbidden in a conversation, or they "
     "answer a question you did not have when you first read them, and the "
     "only way to be ready for that is to have kept them somewhere you will "
     "look. So the commonplace book survives, renamed and rebuilt, because "
     "the problem it solves is the reader’s and not the technology’s: "
     "attention is scarce, memory is unreliable, and a good sentence deserves "
     "a second chance to be understood.", 0),
]


def call(url, method, body=None):
    req = urllib.request.Request(
        url, method=method,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Bearer owner", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        if method == "DELETE" and e.code == 404:
            return {}
        raise


def put(path, fields):
    call(f"{BASE}/{path}", "PATCH", {"fields": fields})


def chunk_id(i):
    return f"{DOC}-chunk-{i}"


def remove():
    for i in range(len(PASSAGES)):
        call(f"{BASE}/chunks/{chunk_id(i)}", "DELETE")
    call(f"{BASE}/documents/{DOC}", "DELETE")
    q = {"structuredQuery": {"from": [{"collectionId": "read_events"}], "where": {
        "fieldFilter": {"field": {"fieldPath": "document_id"}, "op": "EQUAL",
                        "value": {"stringValue": DOC}}}}}
    for row in call(f"{BASE}:runQuery", "POST", q):
        name = row.get("document", {}).get("name")
        if name:
            call(f"http://{HOST}/v1/{name}", "DELETE")


remove()  # a run that died mid-shot left it behind
if "--remove" in sys.argv:
    print(f"removed {DOC}")
    sys.exit(0)

now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
words = sum(len(t.split()) for t, _ in PASSAGES)
put(f"documents/{DOC}", {
    "user_id": {"stringValue": UID},
    "title": {"stringValue": "On Keeping a Commonplace Book"},
    "type": {"stringValue": "article"},
    "mime_type": {"stringValue": "text/html"},
    "status": {"stringValue": "complete"},
    "gcs_path": {"nullValue": None},
    "gcs_paths": {"arrayValue": {}},
    "source_url": {"stringValue": "https://example.org/commonplace-book"},
    "created_at": {"timestampValue": now},
    "processed_at": {"timestampValue": now},
    "chunk_count": {"integerValue": str(len(PASSAGES))},
    "word_count": {"integerValue": str(words)},
    "summary": {"stringValue": "Why the commonplace book outlived its century."},
    "key_points": {"arrayValue": {}},
    "themes": {"arrayValue": {"values": [{"stringValue": "Reading"}]}},
    "tag_ids": {"arrayValue": {}},
    "source_priority": {"doubleValue": 0.5},
    "view_count": {"integerValue": "0"},
    "last_viewed_at": {"nullValue": None},
    "source_integration": {"nullValue": None},
})
for i, (text, read) in enumerate(PASSAGES):
    put(f"chunks/{chunk_id(i)}", {
        "user_id": {"stringValue": UID},
        "document_id": {"stringValue": DOC},
        "chunk_index": {"integerValue": str(i)},
        "text": {"stringValue": text},
        "html": {"stringValue": f"<p>{text}</p>"},
        "tag_ids": {"arrayValue": {}},
        "source_type": {"stringValue": "article"},
        "source_priority": {"doubleValue": 0.5},
        "user_edited": {"booleanValue": False},
        "created_at": {"timestampValue": now},
        "view_count": {"integerValue": str(read)},
        "last_viewed_at": {"timestampValue": now} if read else {"nullValue": None},
    })
print(f"seeded {DOC}: 3 passages, the first read")
