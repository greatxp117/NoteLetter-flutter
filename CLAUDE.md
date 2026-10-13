# CLAUDE.md — NoteLetter Flutter

Flutter client. Part of the multi-repo workspace — read the umbrella
`../CLAUDE.md` (especially "Traps that have bitten us") and
`../NoteLetter-contracts/spec/overview.md` before any data-layer work.

**Contract version: 5.3.1** (pin — advanced only with a green `/conformance`
run; `test/contract/pin_check_test.dart` parses this exact line and fails while
it differs from `../NoteLetter-contracts/VERSION`).

Current since F-18 (2026-10-13): the pin moves with each version's Flutter
tandem, as web's does (`spec/clients/flutter.md` §Pin). [`QUEUE.md`](QUEUE.md)
is the work queue; `/flutter-next` works it, `/parity flutter` refreshes it;
never narrate here.
Debug builds **refuse prod** — run through `tool/dev.sh`. Bundle id
`xp.NoteLetter.Flutter` (`xp.NoteLetter` is the Swift app's).

## Layout

```
lib/
├── main.dart, app.dart, router.dart      # entry, MaterialApp, routing
├── firebase_options.dart                 # noteletter-7a111
├── services/  api.dart                   # the canonical request builders
│              api_service.dart           # Dio + auth interceptor
│              firestore_service.dart     # INV-02 subscriptions + logReadEvent
│              activity_merge.dart        # extracted pure fn (INV-02)
├── state/     *_notifier.dart            # Provider ChangeNotifiers
├── models/    document, chunk, tag, newsletter, activity_item, …
├── pages/     one per screen (+ pages/study/, pages/reader/)
├── widgets/   support_shell, app_layout, sidebar, nav_drawer, kit/
└── theme/     app_colors.dart            # semantic tokens from design-tokens.md
```

Pattern is `pages/` + `state/` + `services/` — **not** feature-first.

**Routes follow the web reference, not the obvious names:** `/` is the
**Library** (the rail's *Home*); the rail's *Library* is `/sources` (volumes,
uploader).

The live theme is `theme/app_theme.dart`.
**Never reintroduce `ColorScheme.fromSeed`** — a generated palette looks
consistent while most widgets draw colours from no token file. Guard:
`test/contract/theme_tokens_test.dart`.

**Every request is built in `lib/services/api.dart`** — what the harness
asserts; a notifier building its own is untested.

## Build & run

```bash
tool/dev.sh chrome|ios                        # emulator only, proven ours
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/contract test/kit           # pin included since F-18
tool/shots_batch.sh <list> && tool/web_frames.sh <screen>…
```

Device run: `tool/device_test.sh ["<test name>"]` — always the script: zsh
passes an unquoted define list as one argument, so the app boots on prod's
config and refuses.

## Composition deviations

Kit metrics are web's numbers and this client's **starting** values; each
deviation is recorded here and applied **once, inside the kit**. Roles and
proportions hold:

- §1.5 gutter 56 → 20 · §2.1 title 44 → 32
- §2/§5.3 actions stack under the whole title BLOCK, standfirst included —
  never between a title and its standfirst
- §6.6/§6.8, §4.2's timestamp, §12's action and a setting row's control strip
  stack, and §4.1's count hides, at 768, not web's 680/640/480 — one breakpoint
- §16's anchor also opens on **tap**: a coarse pointer has neither trigger
- touch copy, no keys bound: speed read hints only *Hold to pause & rest*
  (F-77 (8)); the drop zone says *tap* (F-79)
- Sources' *Add an image set* row: a device capability web lacks
- §15.1 draws no PDF (no renderer is embedded): the stage names it (F-82)

## Rules that are easy to break here

- **`logReadEvent` decides which counter moves from the event type**, never from
  whether a `chunkId` was passed (INV-03a/03b). Getting this wrong here is not
  cosmetic: this client points at **real prod**, so a wrong bump re-inflates the
  same counters a backfill has already corrected.
- **`fake_cloud_firestore` cannot resolve against this SDK**, so the transaction
  is not harness-provable: the *rule* is extracted as a pure function and
  asserted, the Firestore plumbing is not. The web reference is equally blind.
- **Dart will not compare against null.** The web parser gets a chapter-crossing
  citation range right via a loose `null > n`; the direct port crashed on its
  middle chapter. Any logic ported from `api.js` that leans
  on JS coercion needs an explicit null branch.
- **The reading-speed constant is 220 wpm**, normatively — this client shipped
  200 and silently disagreed with the reference on every document.
- **Never end a status/label switch with `default: return status`.** That is how
  users get shown the literal token `pending_upload`.
- **Newsletters filter `kind != "scripture"`, never `== "daily"`** — the field is
  absent on every pre-2.24.0 record and equality drops a real user's history.
- **`aliases_douay_rheims` is never merged** into the citation lookup: DR
  "1 Kings" is 1 Samuel, so merging resolves citations to the wrong book while
  looking complete. A bare book name is not a citation.
- **INV-22's footer wraps the whole authenticated surface, not `AppLayout`** —
  a wide reader is outside `AppLayout`. `widgets/support_shell.dart`, nowhere else.
- **`flutterfire configure` does not rename the native projects.** A mismatch
  between `applicationId`/`PRODUCT_BUNDLE_IDENTIFIER` and the generated config
  fails at **Firebase init**, not at build — so a green build proves nothing here.
