# CLAUDE.md — NoteLetter Flutter

Flutter client for NoteLetter. Part of the multi-repo workspace — read the umbrella `../CLAUDE.md` and `../NoteLetter-contracts/spec/overview.md` before any data-layer work.

## Status: Milestone 2 realignment landed (config/API/models/Firestore/read-tracking/screens/theming) — some gaps remain

**Contract version: 1.0.0**, targeting real project `noteletter-7a111` (web target only — native iOS/Android Firebase apps not yet registered). `flutter analyze` and `flutter build web` are clean as of the last pass. `/conformance` has not been formally run against this client — treat this status as "realigned per `/parity flutter`," not certified.

Full detail and remaining gaps: **[`REALIGNMENT.md`](REALIGNMENT.md)** — its "Deferred / not built" section is authoritative for what's left (tags UI, multi-image upload, audio, cloud-file-picker Sources screen, native app registration, Geist font assets, chunk `html` rendering in the Reader).

Historical drift this pass fixed (previously recorded in `NoteLetter-contracts/CHANGELOG.md` 1.0.0): stale Firebase project (`luxletter-b7a40`), removed endpoints (`fn_ingest_youtube`, `fn_settings/newsletter`, `fn_list_activity`), INV-02 HTTP polling instead of Firestore subscriptions, missing `logReadEvent`/INV-03, missing embedding stripping, amber/navy theme drift.

## What actually exists (the REAL layout — the old CLAUDE.md described a fictional `features/` structure)

```
lib/
├── main.dart, app.dart, router.dart      # entry, MaterialApp, routing (incl. /reader/:docId, /letters)
├── firebase_options.dart                 # noteletter-7a111 (web); native iOS/Android not registered
├── services/  api_service.dart (Dio + auth interceptor)
│              auth_service.dart
│              firestore_service.dart     # INV-02 subscriptions/reads + logReadEvent (INV-03)
├── state/     *_notifier.dart            # ChangeNotifiers: auth, upload, search, chat, activity, settings, theme, newsletter
├── models/    document, chunk, tag, newsletter, newsletter_settings, search_result, activity_item, cloud_integration, chat_message, upload_file
├── pages/     landing, dashboard, library, chat, settings, branding, not_found, reader_page, letters_page
├── widgets/   app_layout, sidebar, nav_drawer, file_uploader, vector_search, chat_interface, newsletter_card, …
└── theme/     app_colors.dart, app_theme.dart      # semantic tokens from design-tokens.md
```

Pattern: `pages/` + `state/` (Provider ChangeNotifiers) + `services/` — NOT feature-first. Keep this organization for future work.

## Build & run

```bash
flutter pub get
flutter run                    # -d chrome / macos / simulator
flutter analyze && dart test   # tests: contract harness lands in Milestone 3 (test/contract/)
```

Emulator development (after config fix): `--dart-define=USE_EMULATOR=true` per `/emu`.

## Realignment order (Milestone 2 — via /parity flutter → tandem tasks)

**→ The live, per-file execution checklist is [`REALIGNMENT.md`](REALIGNMENT.md).** Tasks 1–7 (config, API layer, models, Firestore layer, read-tracking, screens, theming) are checked off there; its "Deferred / not built" section is what's left. Regenerate it with `/parity flutter` after further changes.
