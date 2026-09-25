#!/usr/bin/env python3
"""The Flutter work queue — `QUEUE.md`, read and written by one script.

    python3 tool/queue.py next            first open / in-progress item, as JSON (exit 3: none)
    python3 tool/queue.py start F-02      open → in-progress
    python3 tool/queue.py done F-02       → done (stamps today's date)
    python3 tool/queue.py block F-02 "device test: <first error line>"
    python3 tool/queue.py add < item.json append an item (used by /parity and /feature)
    python3 tool/queue.py lint            every block well-formed, every path real (exit 1)

WHY A FILE WITH A SCHEMA, AND A SCRIPT
--------------------------------------
`REALIGNMENT.md` (2026-07-05, contract 1.0.0) was the last list of what this
client owed. Nothing read it, so nothing noticed when it stopped being true —
its "deferred" section still named a Tags screen, a Sources screen and bundled
fonts months after all three existed. A queue that only a human reads is prose
with checkboxes, and prose is what the next reader trusts.

This one is read by `/flutter-next` (which takes the top item), by
`/conformance` (which decides whether the pin test is excluded by policy), by
the contract suite (`api_requests_test.dart` — an endpoint may sit in
`_noBuilder` only if an open item here will land its adapter, or
`spec/clients/flutter.md` §Out of scope names it) and by
`harness/screenshot_pair_check.py` (which knows a pair is stale because a done
item's files moved after it). A field a script reads cannot quietly stop being
true.

FORMAT
------
    # Flutter work queue
    folded-through: 4.52.1
    pin-holds-at: 4.4.0

    ## F-02 · Notifications — recompose
    - status: open                       open | in-progress | blocked: <reason> | done [date]
    - screen: notifications              the theme-shots name; = screenshots/<screen>.*.png
    - route: /settings/notifications
    - spec: spec/screens/notifications.md §Composition; spec/component-kit.md §2.2
    - web: src/pages/NotificationSettings.jsx; src/styles/app-settings.css
    - flutter: lib/pages/notification_settings_page.dart; lib/widgets/kit/kit_headers.dart (new)
    - folds: 4.32.1; 4.8.0; TODO "Flutter and iOS still register push by token only"
    - device_test: notifications composes from the kit
    - shots: notifications
    - extra_gates: none
    - notes: free text; may continue on following lines indented two spaces

Lists split on `;`. A path tagged `(new)` need not exist yet. `spec:` paths are
relative to NoteLetter-contracts/, `web:` to NoteLetter-web/, `flutter:` to this
repo. The script never reorders items and never edits a `done` one — a new
obligation on a finished screen is a new item, so the history of what was done
against which spec stays readable.
"""
from __future__ import annotations

import datetime as _dt
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO.parent
QUEUE = REPO / "QUEUE.md"

FIELDS = ["status", "screen", "route", "spec", "web", "flutter", "folds",
          "device_test", "shots", "extra_gates", "notes"]
LIST_FIELDS = {"spec", "web", "flutter", "folds", "shots", "extra_gates"}
STATUS = re.compile(r"^(open|in-progress|done(\s+\d{4}-\d{2}-\d{2})?|blocked:\s*\S.*)$")
HEAD = re.compile(r"^## (F-\d{2}) · (.+)$")
FIELD = re.compile(r"^- ([a-z_]+): ?(.*)$")
NEW = re.compile(r"\s*\(new\)\s*$")


# ── parse / render ───────────────────────────────────────────────────────────

def parse(text: str):
    """→ (header: dict, items: list[dict]). Each item keeps its raw field
    order plus `id`, `title`, `_start`, `_end` line indexes for in-place edits."""
    lines = text.splitlines()
    header, items, cur, field = {}, [], None, None
    for i, line in enumerate(lines):
        m = HEAD.match(line)
        if m:
            if cur:
                cur["_end"] = i
            cur = {"id": m.group(1), "title": m.group(2).strip(), "_start": i}
            items.append(cur)
            field = None
            continue
        if cur is None:
            hm = re.match(r"^([a-z-]+):\s*(.+?)\s*(#.*)?$", line)
            if hm:
                header[hm.group(1)] = hm.group(2)
            continue
        fm = FIELD.match(line)
        if fm:
            field = fm.group(1)
            cur[field] = fm.group(2).strip()
        elif field and line.startswith("  ") and line.strip():
            cur[field] = (cur[field] + " " + line.strip()).strip()
        elif not line.strip():
            field = None
    if cur:
        cur["_end"] = len(lines)
    return header, items


def as_list(v: str) -> list[str]:
    if not v or v.strip().lower() == "none":
        return []
    return [x.strip() for x in v.split(";") if x.strip()]


def public(item: dict) -> dict:
    out = {k: v for k, v in item.items() if not k.startswith("_")}
    for f in LIST_FIELDS:
        if f in out:
            out[f] = as_list(out[f])
    return out


def status_kind(item: dict) -> str:
    s = item.get("status", "")
    return "blocked" if s.startswith("blocked") else s.split()[0] if s else "?"


def set_status(item_id: str, new: str) -> dict:
    text = QUEUE.read_text(encoding="utf-8")
    _, items = parse(text)
    item = next((x for x in items if x["id"] == item_id), None)
    if item is None:
        sys.exit(f"queue: no item {item_id}")
    if status_kind(item) == "done":
        sys.exit(f"queue: {item_id} is done; a done item is never edited — add a new one")
    lines = text.splitlines()
    for i in range(item["_start"], item["_end"]):
        if lines[i].startswith("- status:"):
            lines[i] = f"- status: {new}"
            break
    QUEUE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    item["status"] = new
    return item


# ── commands ─────────────────────────────────────────────────────────────────

PIN_BUMP = re.compile(r"^Pin bump\b")


def cmd_next() -> int:
    """The first unfinished item — except the pin bump, which is handed out
    only once nothing else is open. `add` appends, so every obligation queued
    after the bump was written sits BELOW it, and a positional `next` offered
    the final item (spec/clients/flutter.md §Pin: "one bump at the end") with
    fourteen items still open behind it."""
    _, items = parse(QUEUE.read_text(encoding="utf-8"))
    rest = [it for it in items if not PIN_BUMP.match(it["title"])]
    pin = [it for it in items if PIN_BUMP.match(it["title"])]
    for it in rest + pin:
        k = status_kind(it)
        if k in ("open", "in-progress", "blocked"):
            print(json.dumps(public(it), indent=2))
            return 0 if k != "blocked" else 4
    print("queue: no open items", file=sys.stderr)
    return 3


def cmd_start(item_id: str) -> int:
    it = set_status(item_id, "in-progress")
    print(f"{it['id']} → in-progress")
    return 0


def cmd_done(item_id: str) -> int:
    it = set_status(item_id, f"done {_dt.date.today().isoformat()}")
    print(f"{it['id']} → {it['status']}")
    return 0


def cmd_block(item_id: str, reason: str) -> int:
    if not reason.strip():
        sys.exit("queue: block needs a reason — the first error line of the gate that failed")
    it = set_status(item_id, f"blocked: {reason.strip()}")
    print(f"{it['id']} → {it['status']}")
    return 0


def cmd_add(payload: dict) -> int:
    """Append one item. Payload: {"title", "after"?: "F-NN", <fields>}; list
    fields may be lists. The id is the next free F-NN. `after` inserts behind
    that item instead of at the end, so /feature can queue a small obligation
    beside the screen it belongs to rather than after the pin bump."""
    text = QUEUE.read_text(encoding="utf-8")
    _, items = parse(text)
    missing = [f for f in FIELDS if f not in payload and f != "status"]
    if "title" not in payload or missing:
        sys.exit(f"queue: add needs title + {', '.join(FIELDS)} (missing: {missing})")
    n = max((int(x["id"][2:]) for x in items), default=-1) + 1
    block = [f"## F-{n:02d} · {payload['title']}", f"- status: {payload.get('status', 'open')}"]
    for f in FIELDS:
        if f == "status":
            continue
        v = payload[f]
        if isinstance(v, list):
            v = "; ".join(v) if v else "none"
        block.append(f"- {f}: {v}")
    lines = text.rstrip("\n").splitlines()
    after = payload.get("after")
    if after:
        tgt = next((x for x in items if x["id"] == after), None)
        if tgt is None:
            sys.exit(f"queue: no item {after} to insert after")
        lines[tgt["_end"]:tgt["_end"]] = [""] + block
    else:
        lines += [""] + block
    QUEUE.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"F-{n:02d} added")
    return 0


def cmd_lint() -> int:
    text = QUEUE.read_text(encoding="utf-8")
    header, items = parse(text)
    problems: list[str] = []
    warns: list[str] = []
    for key in ("folded-through", "pin-holds-at"):
        if not re.match(r"^\d+\.\d+\.\d+$", header.get(key, "")):
            problems.append(f"header: `{key}:` missing or not a version")
    ids = [x["id"] for x in items]
    if ids != sorted(ids):
        problems.append(f"items are out of order: {ids}")
    if len(set(ids)) != len(ids):
        problems.append("duplicate item ids")
    web_shots = ROOT / "NoteLetter-web" / "screenshots"
    for it in items:
        for f in FIELDS:
            if f not in it:
                problems.append(f"{it['id']}: missing field `{f}`")
        s = it.get("status", "")
        if not STATUS.match(s):
            problems.append(f"{it['id']}: status `{s}` is not open | in-progress | "
                            f"blocked: <reason> | done [YYYY-MM-DD]")
        if status_kind(it) == "done" and not re.search(r"\d{4}-\d{2}-\d{2}", s):
            problems.append(f"{it['id']}: done without a date")
        for f, base in (("spec", ROOT / "NoteLetter-contracts"),
                        ("web", ROOT / "NoteLetter-web"),
                        ("flutter", REPO)):
            for entry in as_list(it.get(f, "")):
                if NEW.search(entry):
                    continue
                path = entry.split(" §")[0].split(" (")[0].strip()
                if not (base / path).exists():
                    problems.append(f"{it['id']}: {f} path does not exist: {path}")
        for shot in as_list(it.get("shots", "")):
            for theme in ("light", "dark"):
                if not (web_shots / f"{shot}.web.{theme}.png").exists():
                    warns.append(f"{it['id']}: no web reference frame "
                                 f"{shot}.web.{theme}.png yet — the item must produce it "
                                 f"(theme-shots.mjs --only {shot}) before its pair can be checked")
    n_open = sum(1 for x in items if status_kind(x) in ("open", "in-progress", "blocked"))
    print(f"queue: {len(items)} item(s), {n_open} open, folded-through "
          f"{header.get('folded-through')}, pin held at {header.get('pin-holds-at')}")
    for w in warns:
        print(f"  WARN  {w}")
    for p in problems:
        print(f"  FAIL  {p}")
    print(f"  {len(problems)} problem(s)")
    return 1 if problems else 0


def main(argv: list[str]) -> int:
    if not QUEUE.exists():
        sys.exit(f"queue: {QUEUE} is missing")
    cmd = argv[0] if argv else "help"
    if cmd == "next":
        return cmd_next()
    if cmd == "start" and len(argv) == 2:
        return cmd_start(argv[1])
    if cmd == "done" and len(argv) == 2:
        return cmd_done(argv[1])
    if cmd == "block" and len(argv) == 3:
        return cmd_block(argv[1], argv[2])
    if cmd == "add":
        return cmd_add(json.load(sys.stdin))
    if cmd == "lint":
        return cmd_lint()
    print(__doc__.split("WHY", 1)[0])
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
