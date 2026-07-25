# CLAUDE.md — NoteLetter Flutter

Flutter client for NoteLetter. Part of the multi-repo workspace — read the umbrella `../CLAUDE.md` and `../NoteLetter-contracts/spec/overview.md` before any data-layer work.

## Status: Milestone 2 realignment landed + 1.1.0→2.3.0 catch-up substantially done — pin still 1.0.0 pending remaining gaps + a green /conformance

**Contract version: 1.0.0**, targeting real project `noteletter-7a111` (web target only — native iOS/Android Firebase apps not yet registered). `flutter analyze` clean. `/conformance` has not been run; the pin stays **1.0.0** until the remaining gaps land and a green run advances it.

**Catch-up landed (2026-07-24, `/parity flutter` → per-feature commits):**
- **2.0.0** newsletter canonical field names (`emailAddress`/`dateRangeDays`) — fixed an active prod 400 on settings save.
- **2.2.0** newsletter `empty`/`error` status rows (informational, not openable) + `excludeRecentDays` control.
- **1.1.0/1.5.0** dropped dead `display_html`/`questions` from `Document`.
- **Reader** now renders rich `chunk.html` via `flutter_html` (text fallback).
- **Cloud-import / Sources stack (1.2.4/1.3.0/1.4.0)**: new `/sources` screen — provider connect/disconnect + reconnect health banner, `fn_list_cloud_files` picker (breadcrumb/pagination/caps), `fn_import_from_cloud`, live `cloud_import_jobs` subscription with retry/duplicate affordances, `fn_request_cloud_sync`. Full API layer incl. `fn_sync_settings`/`fn_check_source_freshness`/`fn_update_from_source` (`CloudNotifier`).
- **2.3.0** OAuth return consumed on `/sources` (`cloud_connect`/`provider`/`reason`/`org`, auto-open picker, reason banner, strip params); retired the old wrong-route `/settings` handling.
- **Auto-organization (1.2.x)**: models + subscriptions (`organization_suggestions`, `cloud_folders`, `settings/organization`) + `OrgNotifier` (all org endpoints); Sources shows a live suggestions review queue + per-provider enable.
- **Tags UI** (`/tags`) over `subscribeTags` + all tag endpoints (`TagsNotifier`).

**Still deferred (this is what blocks the pin, alongside a green /conformance):** sync-settings panel + reader freshness banner + completion notifications (1.4.0 UI; API done); org settings sliders + organized-folders/charter panel + reorg-plan sheet (API done); document tag/priority + content editing (`fn_update_document`/`fn_update_content`) + raw-file view (`fn_get_raw_document_url`); multi-image upload; audio (`fn_generate_audio`); Geist font assets; plum chrome sidebar fidelity; native iOS/Android Firebase registration. Regenerate **[`REALIGNMENT.md`](REALIGNMENT.md)** via `/parity flutter` for the authoritative live list.

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
flutter analyze
flutter test test/contract/    # Tier-1 contract harness (Milestone 3 scaffold)
```

## Conformance (Milestone 3 scaffold)

`test/contract/` is the Tier-1 harness against the captured fixtures in
`../NoteLetter-contracts/fixtures/`. **It red-stops at `pin_check_test.dart`
by design** — the Flutter pin is contract **1.0.0** and the contracts VERSION is
ahead, so `/conformance` fails loudly on skew (the catch-up signal). The pure
suites that already conform run green: `activity_merge_test` (INV-02, backed by
the extracted pure `lib/services/activity_merge.dart`) and the chunk cases of
`firestore_shapes_test` (INV-05/06). `api_stub_test` marks api/* conformance as
NOT-IMPLEMENTED. Advancing the pin (and turning the whole suite green) is the
Milestone-2 realignment + catch-up work — e.g. `Document.fromJson` still reads
`tags` where the contract is `tag_ids`.

Emulator development (after config fix): `--dart-define=USE_EMULATOR=true` per `/emu`.

## Realignment order (Milestone 2 — via /parity flutter → tandem tasks)

**→ The live, per-file execution checklist is [`REALIGNMENT.md`](REALIGNMENT.md).** Tasks 1–7 (config, API layer, models, Firestore layer, read-tracking, screens, theming) are checked off there; its "Deferred / not built" section is what's left. Regenerate it with `/parity flutter` after further changes.
