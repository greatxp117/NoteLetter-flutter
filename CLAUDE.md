# CLAUDE.md — NoteLetter Flutter

Flutter client. Part of the multi-repo workspace — read the umbrella
`../CLAUDE.md` (especially "Traps that have bitten us") and
`../NoteLetter-contracts/spec/overview.md` before any data-layer work.

**Contract version: 4.4.0** (pin — advanced only with a green `/conformance`
run; `test/contract/pin_check_test.dart` parses this exact line and fails while
it differs from `../NoteLetter-contracts/VERSION`).

At **full feature parity with the web reference**, Study and Scripture included.
Defaults to **real prod** `noteletter-7a111`. Registered as
`xp.NoteLetter.Flutter` — its own bundle id: `xp.NoteLetter` belongs to the
Swift app, and the Android slot is reserved for a native client.

What changed and when: `../NoteLetter-contracts/CHANGELOG.md`. Why:
`spec/decisions/`. What is open: `../TODO.md`. Per-file execution checklist:
[`REALIGNMENT.md`](REALIGNMENT.md) — regenerate with `/parity flutter` rather
than narrating progress here.

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

Pattern is `pages/` + `state/` + `services/` — **not** feature-first.

**Route names follow the web reference and are not the obvious ones:** `/` is
the **Library** (the greeting home, the rail's *Home*); the rail's *Library* is
`/sources`, which owns the volume list and the uploader.

The live theme is `theme/app_theme.dart` (`app.dart` only passes it on).
**Never reintroduce `ColorScheme.fromSeed`** — a generated palette is
self-consistent, so nothing looks broken while most widgets draw colours in no
token file. Guard: `test/contract/theme_tokens_test.dart`.

**Every builder routes through `lib/services/api.dart`**, which all the
notifiers call — that is what makes the app's live requests exactly what the
harness asserts. A notifier building its own request is untested by
construction.

## Build & run

```bash
flutter pub get
flutter run                    # -d chrome / macos / simulator
flutter analyze                # clean apart from two pre-existing landing_page lints
flutter test test/contract/    # Tier-1 contract harness
```

Emulator: `--dart-define=USE_EMULATOR=true` (+ `EMULATOR_*_PORT`), per `/emu`.
Device run: `integration_test/device_run_test.dart` — invocation in its header;
needs `--timeout none` (the iOS build outlasts the per-test timeout).

## Composition deviations

The kit's reference metrics are web's numbers and this client's **starting**
values; each scale factor is recorded here (component-kit.md) and applied
**once, inside the kit**, never per screen. All are viewport adaptations below
768pt, roles and proportions unchanged:

- §1.5 gutter 56 → 20 · §2.1 title 44 → 32
- §2.1 header actions and §5.3 hero actions stack under their content
- §6.6/§6.8 stack at 768, not web's 680 — one compact breakpoint, not two

## Rules that are easy to break here

- **`logReadEvent` decides which counter moves from the event type**, never from
  whether a `chunkId` was passed (INV-03a/03b). Getting this wrong here is not
  cosmetic: this client points at **real prod**, so a wrong bump re-inflates the
  same counters a backfill has already corrected.
- **`fake_cloud_firestore` cannot resolve against this SDK**, so the transaction
  is not harness-provable: the *rule* is extracted as a pure function and
  asserted, the Firestore plumbing is not. The web reference is equally blind.
- **Dart will not compare against null.** The web parser reaches the right answer
  for a chapter-crossing citation range via a loose `null > n`; the direct port
  crashed on the middle whole chapter. Any logic ported from `api.js` that leans
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
- **`flutterfire configure` does not rename the native projects.** A mismatch
  between `applicationId`/`PRODUCT_BUNDLE_IDENTIFIER` and the generated config
  fails at **Firebase init**, not at build — so a green build proves nothing here.
