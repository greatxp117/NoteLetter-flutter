# CLAUDE.md — NoteLetter Flutter

Flutter client for NoteLetter. Part of the multi-repo workspace — read the umbrella `../CLAUDE.md` and `../NoteLetter-contracts/spec/overview.md` before any data-layer work.

## Status: Milestone 2 realignment landed + 1.1.0→2.3.0 catch-up substantially done — interim pin 1.3.0 (data layer conforms to 2.3.0; UI completeness caught up through the cloud-import wave)

**Contract version: 1.3.0** (interim — advanced from 1.0.0 on 2026-07-25), targeting real project `noteletter-7a111` (web target only — native iOS/Android Firebase apps not yet registered). `flutter analyze` clean. **The Tier-1 `/conformance` harness itself runs fully green except the deliberate `pin_check` red-stop** — the `api/*` request-construction suite is implemented (89 cases over all nine `api/*` fixture suites, mirroring the web `api-request` harness), and the `firestore` (incl. the four `doc-shapes` **Document** cases, added when the `tag_ids` drift was fixed) and `activity-merge` suites pass. So the **data layer conforms to 2.3.0** — the harness would certify it.

The **1.3.0 pin is a deliberately conservative *completeness* signal, not the harness ceiling**: it marks how far Flutter's shipped *screen surface* has caught up, chosen as the last version whose delta Flutter fully shipped end-to-end before the first partial. `pin_check` compares this pin to the contracts VERSION (2.3.0) and **still red-stops** — by design, as the catch-up signal for the screen gaps below. Per-version delta status: 1.1.0 ✅, 1.2.0–1.2.3 auto-org ⚠️ partial (suggestions review + per-provider enable shipped; settings sliders / charter / reorg sheet deferred), 1.2.4 Tier A ✅, 1.3.0 Tier B ✅, 1.4.0 Tier C ⚠️ partial (request-sync wired; sync-settings panel + freshness banner deferred), 1.5.0 ✅, 2.0.0/2.2.0/2.3.0 ✅. Baseline `reader.md`/`library.md` gaps (Original/Listen/edit modes, `fn_update_document` priority/tag affordances, audio, multi-image) are older than the pin and persist across all versions — see "Still deferred". Advancing to 2.3.0 requires closing those screen gaps, then flipping this line to `2.3.0`.

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
ahead, so `/conformance` fails loudly on skew (the catch-up signal). The
suites that conform run green: `api_requests_test` (api/* request construction,
89 cases — every builder routes through the canonical `lib/services/api.dart`,
which all ten `state/*_notifier.dart` now call so the app's live requests are
exactly what is asserted), `activity_merge_test` (INV-02, backed by the
extracted pure `lib/services/activity_merge.dart`), and the chunk cases of
`firestore_shapes_test` (INV-05/06). The remaining work to turn the WHOLE suite
green and advance the pin is the deferred UI + one known model drift:
`Document.fromJson` still reads `tags` where the contract is `tag_ids` (the
`firestore_shapes_test` Document cases are why that suite only exercises chunks
today).

Emulator development (after config fix): `--dart-define=USE_EMULATOR=true` per `/emu`.

## Realignment order (Milestone 2 — via /parity flutter → tandem tasks)

**→ The live, per-file execution checklist is [`REALIGNMENT.md`](REALIGNMENT.md).** Tasks 1–7 (config, API layer, models, Firestore layer, read-tracking, screens, theming) are checked off there; its "Deferred / not built" section is what's left. Regenerate it with `/parity flutter` after further changes.
