# CLAUDE.md — NoteLetter Flutter

Flutter client for NoteLetter. Part of the multi-repo workspace — read the
umbrella `../CLAUDE.md` (especially "Traps that have bitten us") and
`../NoteLetter-contracts/spec/overview.md` before any data-layer work.

**Contract version: 4.4.0** (pin — advanced only with a green `/conformance`
run; `test/contract/pin_check_test.dart` parses this exact line and fails loudly
while it differs from `../NoteLetter-contracts/VERSION`).

At **full feature parity with the web reference**, Study and Scripture included.
Configured against **real prod** `noteletter-7a111`, and registered natively as
`xp.NoteLetter.Flutter` — deliberately its own bundle id, because `xp.NoteLetter`
belongs to the Swift app in `NoteLetter/` and the Android slot is reserved for a
planned native client.

What changed and when: `../NoteLetter-contracts/CHANGELOG.md`. Why:
`spec/decisions/`. What is still open here: `../TODO.md`. The live per-file
execution checklist is [`REALIGNMENT.md`](REALIGNMENT.md) — regenerate it with
`/parity flutter` rather than narrating progress in this file.

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
├── scripture/ parse.dart                 # citation parser
├── widgets/   app_layout, sidebar, nav_drawer, …
└── theme/     app_colors.dart            # semantic tokens from design-tokens.md
```

Pattern is `pages/` + `state/` + `services/` — **not** feature-first. Keep it.

The live theme is `theme/app_theme.dart` (`app.dart` only passes it on).
**Never reintroduce `ColorScheme.fromSeed`** — it generates a palette from one
token, so most widgets draw colours in no token file, and since a generated
palette is self-consistent nothing looks broken and no test fails. Guard:
`test/contract/theme_tokens_test.dart`.

**Every builder routes through `lib/services/api.dart`**, which all the notifiers
call — that is what makes the app's live requests exactly what the harness
asserts. A notifier that builds its own request is untested by construction.

## Build & run

```bash
flutter pub get
flutter run                    # -d chrome / macos / simulator
flutter analyze                # clean apart from two pre-existing landing_page lints
flutter test test/contract/    # Tier-1 contract harness
```

Emulator development: `--dart-define=USE_EMULATOR=true`, per `/emu`.

## Rules that are easy to break here

- **`logReadEvent` decides which counter moves from the event type**, never from
  whether a `chunkId` was passed (INV-03a/03b). Getting this wrong here is not
  cosmetic: this client points at **real prod**, so a wrong bump re-inflates the
  same counters a backfill has already corrected.
- **`fake_cloud_firestore` cannot resolve against this SDK**, so the transaction
  itself is not harness-provable. The *rule* is extracted as a pure function and
  asserted; the Firestore plumbing is not. Stated rather than implied — the web
  reference has the same blind spot.
- **Dart will not compare against null.** The web parser reaches the right answer
  for a chapter-crossing citation range via a loose `null > n`; the direct port
  crashed on the middle whole chapter. Any logic ported from `api.js` that leans
  on JS coercion needs an explicit null branch.
- **The reading-speed constant is 220 wpm**, normatively — this client shipped
  200 and silently disagreed with the web reference on every document.
- **Never end a status/label switch with `default: return status`.** That is how
  users get shown the literal token `pending_upload`.
- **Newsletters filter `kind != "scripture"`, never `== "daily"`** — the field is
  absent on every pre-2.24.0 record and equality drops a real user's history.
- **`aliases_douay_rheims` is never merged** into the citation lookup: DR
  "1 Kings" is 1 Samuel, so merging resolves citations to the wrong book while
  looking complete. A bare book name is not a citation.
- **`flutterfire configure` does not rename the native projects.** A mismatch
  between `applicationId`/`PRODUCT_BUNDLE_IDENTIFIER` and the generated config
  fails at **Firebase init**, not at build — so a green build proves nothing here.
