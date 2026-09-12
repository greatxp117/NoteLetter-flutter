"""Seed the letters the canonical emulator seed does not have.

The seed's two `/newsletters` records predate 2.0.0: they carry `html` and
nothing else — no `html_body`, no `subject`, no `chunk_ids`, no `delivery`, and
no readings letter at all. Every one of those is a state this screen has to
render, and four of them are states nothing else in the workspace exercises.

**The letterheaded body comes from the backend's own renderer**, imported in
process through `harness/inline.py` — not from HTML written here. A letter this
file composed would be a fake, and a fake encodes whatever the writer assumed:
the client would then be tuned to a letter that no build produces, and every
gate would agree with it. What is hand-written here is only what the MODEL
returns (theme, greeting, titles, commentary, closing), which is the one part
of a letter that genuinely is text from outside.

Run with the functions venv, which is where the backend's imports resolve:

    FIRESTORE_EMULATOR_HOST=localhost:8080 \\
      ../NoteLetter-Firebase-Functions/functions/venv/bin/python tool/seed_letters.py
"""
import datetime as dt
import json
import os
import sys
import urllib.request
from pathlib import Path

# This directory holds `queue.py`, and Python puts a script's own directory
# first on the path — so urllib3's `import queue` lands on the work queue and
# dies on `queue.LifoQueue`. Drop it before importing anything else.
_HERE = Path(__file__).resolve().parent
sys.path[:] = [p for p in sys.path if Path(p or ".").resolve() != _HERE]

HARNESS = Path(__file__).resolve().parents[2] / "NoteLetter-contracts" / "harness"
sys.path.insert(0, str(HARNESS))
import inline  # noqa: F401 — sets emulator env + sys.path before main is imported

import main  # noqa: E402 — the backend itself

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8080")
BASE = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"


def put(path, fields):
    req = urllib.request.Request(
        f"{BASE}/{path}", method="PATCH",
        data=json.dumps({"fields": fields}).encode(),
        headers={"Authorization": "Bearer owner",
                 "Content-Type": "application/json"})
    urllib.request.urlopen(req).read()


def S(v):
    return {"stringValue": v}


def ts(v):
    return {"timestampValue": v}


def arr(vs):
    return {"arrayValue": {"values": [S(v) for v in vs]}}


# ── the passages, and what the model said about them ────────────────────────
# The chunk HTML is the shape a stored chunk has (INV-11's vocabulary); the
# titles and commentary are the model's parts, which is exactly what a real
# build hands the renderer.
ITEMS = [
    {"source": {"title": "The Craft of Braising"},
     "match_html": "<p>Brown the meat before adding liquid, and never crowd the "
                   "pan. A crowded pan steams what it should sear, and the fond "
                   "that carries the whole dish never forms.</p>",
     "match_text": "Brown the meat before adding liquid.",
     "link": "https://noteletter.com/reader/seed-doc-article-complete?p=seed-chunk-article-0"},
    {"source": {"title": "Letters to a Young Poet"},
     "match_html": "<p>Be patient toward all that is unsolved in your heart and "
                   "try to love the questions themselves, like locked rooms and "
                   "like books that are now written in a very foreign tongue.</p>",
     "match_text": "Be patient toward all that is unsolved in your heart.",
     "link": "https://noteletter.com/reader/seed-doc-pdf-complete?p=seed-chunk-pdf-0"},
    {"source": {"title": "A Pattern Language"},
     "match_html": "<p>There is one timeless way of building. It is thousands of "
                   "years old, and the same today as it has always been.</p>",
     "match_text": "There is one timeless way of building.",
     "link": "https://noteletter.com/reader/seed-doc-docx-complete?p=seed-chunk-docx-0"},
]

PARTS = {
    "theme": "On Quiet Rooms",
    "greeting": "Three passages found each other today, and each of them is "
                "about waiting well.",
    "closing": "Until tomorrow.",
    "by_n": {
        1: {"title": "The crowded pan",
            "commentary": "You saved this the week you started cooking properly."},
        2: {"title": "Love the questions",
            "commentary": "It sat beside the braising note in your library, "
                          "which is how it got here."},
        3: {"title": "The timeless way"},
    },
}

now = dt.datetime(2026, 9, 10, 7, 0, tzinfo=dt.timezone.utc)
html_body, _links = main._render_newsletter_html(
    ITEMS, PARTS, now.strftime("%B %d, %Y"), now=now, letter_no=3)
text_body = main._letter_text_part(html_body)

assert 'data-nl-letterhead="1"' in html_body, "the renderer stopped marking the root"
assert 'data-nl-lede="1"' in html_body, "the renderer stopped marking the lede"

# ── a letterheaded letter, delivered ─────────────────────────────────────────
put(f"newsletters/{UID}_20260910T0700Z", {
    "user_id": S(UID),
    "generated_at": ts("2026-09-10T07:00:00Z"),
    "trigger": S("scheduled"),
    "status": S("sent"),
    "kind": S("daily"),
    "subject": S("Your NoteLetter — On Quiet Rooms"),
    "html_body": S(html_body),
    "text_body": S(text_body),
    "chunk_ids": arr(["seed-chunk-article-0", "seed-chunk-pdf-0",
                      "seed-chunk-docx-0"]),
    # 4.22.0 — the second axis. `delivered` is the only state that may be
    # rendered as "Delivered"; `sent` never is (INV-23).
    "delivery": {"mapValue": {"fields": {
        "state": S("delivered"),
        "mx_server": S("mx.example.com"),
        "attempts": {"integerValue": "1"},
        "updated_at": ts("2026-09-10T07:02:00Z"),
    }}},
})

# ── one the receiver is still deferring, and one it refused ──────────────────
put(f"newsletters/{UID}_20260909T0700Z", {
    "user_id": S(UID),
    "generated_at": ts("2026-09-09T07:00:00Z"),
    "trigger": S("scheduled"),
    "status": S("sent"),
    "kind": S("daily"),
    "subject": S("Your NoteLetter — On Beginnings"),
    "html_body": S("<p>An older letter, from before the letterhead.</p>"),
    "text_body": S("An older letter, from before the letterhead."),
    "chunk_ids": arr(["seed-chunk-article-0"]),
    "delivery": {"mapValue": {"fields": {
        "state": S("deferred"),
        "detail": S("451 4.3.2 Please try again later"),
        "attempts": {"integerValue": "8"},
        "updated_at": ts("2026-09-09T09:00:00Z"),
    }}},
})

# ── a manual send that found nothing (2.2.0, ADR-011) ───────────────────────
# Informational, never "Failed", and not openable: nothing was rendered.
put(f"newsletters/{UID}_20260908T101500Z_e1", {
    "user_id": S(UID),
    "generated_at": ts("2026-09-08T10:15:00Z"),
    "trigger": S("manual"),
    "status": S("empty"),
    "kind": S("daily"),
    "error_message": S("Every passage in the window has been in a recent "
                       "letter. Lower “Rest a passage for”, or widen the date "
                       "range."),
})

# ── the readings letter, with a day that did not fully answer ───────────────
put(f"newsletters/{UID}_20260910T0630Z_s", {
    "user_id": S(UID),
    "generated_at": ts("2026-09-10T06:30:00Z"),
    "trigger": S("scheduled"),
    "status": S("sent"),
    "kind": S("scripture"),
    "subject": S("The Readings — Thursday of week 23"),
    # A MAP, not a date string: the date lives inside it (4.52.3).
    "liturgical_day": {"mapValue": {"fields": {
        "name": S("Thursday of week 23 in Ordinary Time"),
        "date": S("2026-09-10"),
        "calendar": S("roman"),
        "season": S("ordinary_time"),
        "week": {"integerValue": "23"},
        "weekday": S("thursday"),
        "cycle": S("B"),
        "liturgical_year": {"integerValue": "2026"},
        "id": S("roman/b/ordinary_time/w23/thursday"),
    }}},
    "readings": {"arrayValue": {"values": [
        {"mapValue": {"fields": {
            "label": S("First reading"),
            "ref": S("Col 3:12-17"),
            "match_total": {"integerValue": "4"},
            "passages": {"arrayValue": {"values": [
                {"mapValue": {"fields": {
                    "chunk_id": S("seed-chunk-pdf-0"),
                    "document_id": S("seed-doc-pdf-complete"),
                    "text": S("Put on then, as God’s chosen ones, compassion, "
                              "kindness, humility, meekness and patience."),
                }}},
            ]}},
        }}},
        {"mapValue": {"fields": {
            "label": S("Responsorial"),
            "ref": S("Ps 150"),
            "match_total": {"integerValue": "0"},
            "passages": {"arrayValue": {"values": []}},
        }}},
        {"mapValue": {"fields": {
            "label": S("Gospel"),
            "ref": S("Lk 6:27-38"),
            "lead": {"booleanValue": True},
            "match_total": {"integerValue": "2"},
            "passages": {"arrayValue": {"values": [
                {"mapValue": {"fields": {
                    "chunk_id": S("seed-chunk-article-0"),
                    "document_id": S("seed-doc-article-complete"),
                    "text": S("Be merciful, even as your Father is merciful."),
                }}},
            ]}},
        }}},
    ]}},
    "passages_sent": {"integerValue": "2"},
    "passages_found": {"integerValue": "6"},
    "verse_source": S("system"),
    "verse_edition": S("World English Bible"),
    "bible_on_shelf": {"booleanValue": False},
})

# The readings letter's own settings document — opted in, mail on.
put(f"users/{UID}/settings/scripture_newsletter", {
    "enabled": {"booleanValue": True},
    "emailEnabled": {"booleanValue": True},
    "deliveryTime": S("06:30"),
    "timezone": S("America/Chicago"),
    "calendar": S("roman"),
})

print(f"tool: seeded 4 letters ({len(html_body)} bytes of letterheaded body) "
      f"and the readings settings, for {UID}")
