# CLAUDE.md — NoteLetter Flutter

Flutter client for NoteLetter. Part of the multi-repo workspace — read the umbrella `../CLAUDE.md` and `../NoteLetter-contracts/spec/overview.md` before any data-layer work.

## Status: Milestone 2 complete — Flutter pinned at contract 2.3.0, `/conformance` fully green

**Contract version: 2.3.0** (advanced 1.0.0 → 1.3.0 interim → **2.3.0** on 2026-07-26 after the screen-gap sweep closed every functional gap), targeting real project `noteletter-7a111` (web target only — native iOS/Android Firebase apps not yet registered). `flutter analyze` clean. **The full Tier-1 `/conformance` suite is green including `pin_check`** — the `api/*` request-construction suite (89 cases over all nine `api/*` fixture suites, mirroring the web `api-request` harness), the `firestore` suite (incl. the four `doc-shapes` **Document** cases added with the `tag_ids` fix), `activity-merge`, and the version pin all pass. The data layer and every contracted screen conform to 2.3.0.

Per-version delta status: all ✅ (1.1.0 reader-html · 1.2.x auto-org incl. settings/charter/reorg · 1.2.4/1.3.0 cloud-import · 1.4.0 Tier-C incl. sync-settings/freshness/completion-notifications · 1.5.0 · 2.0.0/2.2.0/2.3.0). Baseline `reader.md`/`library.md` (all 6 reader panels, `fn_update_document` priority/tags, audio, multi-image) also complete. **Design-fidelity leftovers cleared 2026-07-26** — Geist/Geist Mono now bundled as OFL assets (Inter stand-in retired) and the sidebar/drawer render true plum chrome in both themes. **The one remaining non-conformance item is native iOS/Android Firebase registration** (still web-target only), which is harness-untested and needs interactive `flutterfire configure` against the live project.

**Screen-gap sweep (2026-07-26, per-feature commits):** 6-panel reader (Summary/Manuscript+edit via `fn_update_content`/SpeedRead/Listen via `fn_generate_audio`/Original via `fn_get_raw_document_url`/History) + source-freshness banner (`fn_check_source_freshness`/`fn_update_from_source`) + Reorganize sheet (`fn_analyze`/`fn_execute_reorganization` + `/reorg_plans/{id}` sub); library priority/tags detail sheet (`fn_update_document`); Tier-C sync-settings panel (`fn_sync_settings`) + import/sync completion notifications; auto-org settings sliders + organized-folders charter panel (`fn_organization_settings`/`fn_update_folder_charter`/`fn_scan_organization`); multi-image upload (`fn_create_multi_image_session`/`fn_signal_uploads_complete`). Added `audioplayers` dep; `Document.sourceIntegration`; `FirestoreService.getReadHistory`/`subscribeReorgPlan`/`getDocument`/`getTags`/quiet reader reload. **`REALIGNMENT.md` is now stale — regenerate via `/parity flutter`.**

**Catch-up landed (2026-07-24, `/parity flutter` → per-feature commits):**
- **2.0.0** newsletter canonical field names (`emailAddress`/`dateRangeDays`) — fixed an active prod 400 on settings save.
- **2.2.0** newsletter `empty`/`error` status rows (informational, not openable) + `excludeRecentDays` control.
- **1.1.0/1.5.0** dropped dead `display_html`/`questions` from `Document`.
- **Reader** now renders rich `chunk.html` via `flutter_html` (text fallback).
- **Cloud-import / Sources stack (1.2.4/1.3.0/1.4.0)**: new `/sources` screen — provider connect/disconnect + reconnect health banner, `fn_list_cloud_files` picker (breadcrumb/pagination/caps), `fn_import_from_cloud`, live `cloud_import_jobs` subscription with retry/duplicate affordances, `fn_request_cloud_sync`. Full API layer incl. `fn_sync_settings`/`fn_check_source_freshness`/`fn_update_from_source` (`CloudNotifier`).
- **2.3.0** OAuth return consumed on `/sources` (`cloud_connect`/`provider`/`reason`/`org`, auto-open picker, reason banner, strip params); retired the old wrong-route `/settings` handling.
- **Auto-organization (1.2.x)**: models + subscriptions (`organization_suggestions`, `cloud_folders`, `settings/organization`) + `OrgNotifier` (all org endpoints); Sources shows a live suggestions review queue + per-provider enable.
- **Tags UI** (`/tags`) over `subscribeTags` + all tag endpoints (`TagsNotifier`).

**Done 2026-07-26 (design-fidelity leftovers):** Geist/Geist Mono bundled as OFL TTF assets (`assets/fonts/`, `pubspec` `fonts:`, license `Geist-OFL.txt`); `fontFamily 'Geist'` set on both themes and every `GoogleFonts.inter()` call replaced (`AppTheme` is dead code — the live theme is inline in `app.dart`). Plum "chrome": added `--plum-600`/chrome tokens to `app_colors.dart` and rebuilt `Sidebar` + `NavDrawer` to the web `app-kit.css .sb` spec (plum in both themes, paper-50 fg, brick-400 active bar). analyze clean, Tier-1 +100 unchanged.

**Still deferred (non-conformance only — none block the pin):** native iOS/Android Firebase registration. `android/` uses placeholder `com.example.flutter_app` and `ios/` `com.example.flutterApp`; `firebase_options.dart` has web only and throws for native. Registration needs a real bundle-ID decision + interactive `dart pub global activate flutterfire_cli` → `firebase login` → `flutterfire configure --project=noteletter-7a111` (writes `google-services.json`/`GoogleService-Info.plist`/native `firebase_options.dart` and creates the apps in the **prod** project — needs sign-off). The `/conformance` harness does not test any of this.

**Theme toggle wired + upgraded 2026-07-26:** `ThemeNotifier` is now in `main.dart`'s `MultiProvider` and `app.dart` reads `context.watch<ThemeNotifier>().themeMode` (was hardcoded `ThemeMode.system` with the notifier unprovided → the Sidebar/NavDrawer toggle previously crashed/was inert). The notifier is now a **three-way** system/light/dark control **persisted** via `shared_preferences` (key `theme_mode`, stores `ThemeMode.name`), defaulting to `system` until the stored value loads. The Sidebar/NavDrawer affordance **cycles** system→light→dark→system with a per-mode icon (`brightness_auto`/`light_mode`/`dark_mode`) + label from `ThemeNotifier.modeIcon`/`modeLabel`. No dedicated Settings-screen segmented control yet (web has one); the cycling toggle is the only entry point. Regenerate **[`REALIGNMENT.md`](REALIGNMENT.md)** via `/parity flutter` for the authoritative live list.

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
