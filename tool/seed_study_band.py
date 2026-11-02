"""Write the study session Home's study band frames show, and take it away
(F-153, 5.49.0).

The seed holds no study program or session, so Home draws no band. Web's
theme-shots writes `shot-study-program` and one session of it,
`seed-user-1_shot-study-program_w5`, generated NOW, for `home-study-band`
(no response) and `home-study-band-started` (the first question graded);
this writes the same, word for word:

    FIRESTORE_EMULATOR_HOST=localhost:8580 python3 tool/seed_study_band.py [--started|--remove]

Shoot `home-study-band` after a plain run, `home-study-band-started` after
`--started`, then `--remove`. Writes through the emulator REST with
`Bearer owner` — study documents are read-only to clients (INV-04).
"""
import datetime, json, os, subprocess, sys, urllib.error, urllib.request
from pathlib import Path

HOST = os.environ.get("FIRESTORE_EMULATOR_HOST", "localhost:8580")
ROOT = f"http://{HOST}/v1/projects/noteletter-7a111/databases/(default)/documents"
UID = "seed-user-1"
PROG = "shot-study-program"
SESS = f"{UID}_{PROG}_w5"
AUTH = {"Authorization": "Bearer owner", "Content-Type": "application/json"}


def call(url, method, body=None):
    req = urllib.request.Request(url, method=method, headers=AUTH,
                                 data=None if body is None else json.dumps(body).encode())
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        if method == "DELETE" and e.code == 404:
            return 404
        raise SystemExit(f"{method} {url}: {e.code} {e.read().decode()[:300]}")


if "--remove" in sys.argv:
    call(f"{ROOT}/study_sessions/{SESS}", "DELETE")
    subprocess.run([sys.executable, str(Path(__file__).with_name("seed_study_program.py")), "--remove"], check=True)
    print("removed")
    raise SystemExit(0)

subprocess.run([sys.executable, str(Path(__file__).with_name("seed_study_program.py"))], check=True)
s = lambda v: {"stringValue": v}
n = lambda v: {"integerValue": str(v)}
q = lambda qid, question, answer: {"mapValue": {"fields": {
    "qid": s(qid), "question": s(question), "answer": s(answer)}}}


def item(kind, doc, chunk, title, excerpt, qs):
    return {"mapValue": {"fields": {
        "kind": s(kind), "document_id": s(doc), "chunk_id": s(chunk), "title": s(title),
        "excerpt_html": s(excerpt), "questions": {"arrayValue": {"values": qs}}}}}


now = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
responses = {"shot-q1": {"mapValue": {"fields": {"grade": s("good")}}}} if "--started" in sys.argv else {}
fields = {
    "user_id": s(UID), "program_id": s(PROG), "program_title": s("Cooking fundamentals"),
    "generated_at": {"timestampValue": now}, "trigger": s("scheduled"), "status": s("sent"),
    "new_count": n(2), "review_count": n(1), "due_remaining": n(0), "ramp_count": n(0),
    "items": {"arrayValue": {"values": [
        item("new", "seed-doc-article-complete", "shot-w5-no-such-chunk-1", "Pasta Fundamentals",
             "<p>Salt the water until it tastes of the sea, then add the pasta and stir in the first minute.</p>",
             [q("shot-q1", "When should pasta water be salted?", "Before the pasta goes in — salted until it tastes of the sea."),
              q("shot-q2", "Why stir in the first minute?", "So the pasta does not stick while its surface starch sets.")]),
        item("review", "seed-doc-pdf-complete", "shot-w5-no-such-chunk-2", "Household budget 2026",
             "<p>Fixed costs come first; what is left is divided by the month’s priorities.</p>",
             [q("shot-q3", "What does the budget settle first?", "The fixed costs, before anything is divided.")]),
    ]}},
    "responses": {"mapValue": {"fields": responses}},
}
call(f"{ROOT}/study_sessions/{SESS}", "PATCH", {"fields": fields})
print(f"wrote {SESS} ({'started' if responses else 'not started'})")
