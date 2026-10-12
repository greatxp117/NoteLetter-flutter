"""Seed the two documents the §15 overlay frames need, and take them away again.

`source-file` and `source-set` are the reference's frames of the §15 overlay
SHEET opened from a processing row on Sources (web scripts/theme-shots.mjs
`source-file`, `source-set`): a FAILED DOCX whose bytes are stored, opened by
its row's View file, and a `pending_upload` image set with two of its three
pages landed. This client's holds framed the reader's Original section
instead — another surface under the same name (F-82 (1)) — so the two pairs
compared nothing. These are web's two documents, word for word.

Written for the shot and removed after it, as web writes and deletes them per
shot: left in the seed, the processing tray would carry two more rows and the
`sources` pair would count eight where the reference counts six.

    FIRESTORE_EMULATOR_HOST=localhost:8580 STORAGE_EMULATOR_HOST=http://localhost:9699 \\
      python3 tool/seed_overlay_sources.py [--remove]

Writes through the emulator REST with `Bearer owner`, which bypasses rules — a
client cannot write /documents directly (INV-04).
"""
import json, os, struct, sys, urllib.error, urllib.parse, urllib.request, zlib

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
STORAGE = os.environ.get("STORAGE_EMULATOR_HOST", "http://localhost:9699").rstrip("/")
BUCKET = "noteletter-7a111.firebasestorage.app"
UID = "seed-user-1"

FILE_DOC = "shot-failed-docx"
FILE_PATH = f"raw/{UID}/docx/{FILE_DOC}.docx"
SET_DOC = "shot-pending-set"
SET_PATHS = [f"raw/{UID}/image_sets/{SET_DOC}/{i}_{n}"
             for i, n in enumerate(["front.jpg", "middle.png", "back.jpg"])]


def call(url, method, data=None, headers=None):
    req = urllib.request.Request(url, data=data, method=method,
                                 headers=headers or {})
    try:
        urllib.request.urlopen(req).read()
    except urllib.error.HTTPError as e:
        if not (method == "DELETE" and e.code == 404):
            raise


def png(w, h, top, bottom):
    rows = b""
    for y in range(h):
        f = y / max(1, h - 1)
        px = bytes(round(top[i] + (bottom[i] - top[i]) * f) for i in range(3))
        rows += b"\x00" + px * w

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows))
            + chunk(b"IEND", b""))


def put_object(path, data, mime):
    call(f"{STORAGE}/upload/storage/v1/b/{BUCKET}/o?uploadType=media&name="
         + urllib.parse.quote(path, safe=""), "POST", data, {"Content-Type": mime})


def del_object(path):
    call(f"{STORAGE}/storage/v1/b/{BUCKET}/o/" + urllib.parse.quote(path, safe=""),
         "DELETE")


def put_doc(doc_id, fields):
    call(f"{BASE}/documents/{doc_id}", "PATCH",
         json.dumps({"fields": fields}).encode(),
         {"Authorization": "Bearer owner", "Content-Type": "application/json"})


def del_doc(doc_id):
    call(f"{BASE}/documents/{doc_id}", "DELETE", None,
         {"Authorization": "Bearer owner"})


S = lambda v: {"stringValue": v}                    # noqa: E731
I = lambda v: {"integerValue": str(v)}              # noqa: E731
D = lambda v: {"doubleValue": v}                    # noqa: E731
N = {"nullValue": None}
A = lambda vs: {"arrayValue": {"values": vs}}       # noqa: E731
TS = {"timestampValue": "2026-10-12T10:00:00Z"}

if "--remove" in sys.argv:
    del_doc(FILE_DOC)
    del_doc(SET_DOC)
    del_object(FILE_PATH)
    for p in (SET_PATHS[0], SET_PATHS[2]):
        del_object(p)
    print(f"removed {FILE_DOC} and {SET_DOC}")
    sys.exit(0)

# `source-file` — a failed DOCX whose bytes are stored: the stage names a type
# it cannot draw (§15.1 rule 1), which is the half of the pattern web frames.
put_object(FILE_PATH,
           "PK\x03\x04 — a truncated archive, which is why it failed".encode(),
           "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
put_doc(FILE_DOC, {
    "user_id": S(UID),
    "title": S("minutes-2026-08.docx"),
    "type": S("docx"),
    "mime_type": S("application/vnd.openxmlformats-officedocument.wordprocessingml.document"),
    "status": S("error"),
    "failed_stage": S("extraction"),
    "gcs_path": S(FILE_PATH),
    "gcs_paths": A([]),
    "source_url": N,
    "created_at": TS,
    "processed_at": N,
    "chunk_count": N,
    "word_count": N,
    "summary": N,
    "tag_ids": A([]),
    "error_message": S("Extraction failed: not a valid DOCX archive."),
    "source_priority": D(0.5),
    "retry_count": I(0),
    "view_count": I(0),
})

# `source-set` — three pages, the middle one's bytes deliberately absent (§15.2
# rule 1: a page that has not landed keeps its own index).
img = png(240, 320, (226, 176, 176), (150, 200, 170))
put_object(SET_PATHS[0], img, "image/jpeg")
put_object(SET_PATHS[2], img, "image/jpeg")
put_doc(SET_DOC, {
    "user_id": S(UID),
    "title": S("Kitchen notebook, three pages"),
    "type": S("image_set"),
    "mime_type": S("image_set"),
    "status": S("pending_upload"),
    "gcs_path": N,
    "gcs_paths": A([S(p) for p in SET_PATHS]),
    "image_count": I(3),
    "source_url": N,
    "created_at": TS,
    "processed_at": N,
    "chunk_count": N,
    "word_count": N,
    "summary": N,
    "error_message": N,
    "tag_ids": A([]),
    "source_priority": D(0.5),
    "retry_count": I(0),
    "view_count": I(0),
})
print(f"seeded {FILE_DOC} (failed WITH bytes) and {SET_DOC} (pending, 2 of 3 pages)")
