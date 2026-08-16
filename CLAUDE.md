# CLAUDE.md — NoteLetter Flutter

Flutter client for NoteLetter. Part of the multi-repo workspace — read the umbrella `../CLAUDE.md` and `../NoteLetter-contracts/spec/overview.md` before any data-layer work.

## Status: pinned at contract 4.1.1 — **full feature parity with the web reference** (2026-08-15)

**Contract version: 4.1.1** (2.8.0 → **4.1.1** on 2026-08-15, the Milestone-2 feature catch-up), targeting real project `noteletter-7a111` (web target only — native iOS/Android Firebase apps still not registered). `flutter analyze` clean apart from two pre-existing `landing_page` lints. Contract suite **179 tests green**, incl. two new fixture suites (`api/read-state`, `api/chunk-tags`) and three new pure-logic suites (`read_counters`, `dwell`, `chunk_shelves`).

**What this pass fixed, and why the first item mattered most.** `logReadEvent` bumped the document on **every** event and the chunk on any `chunkId` — non-conforming at 3.1.0 and 4.0.0, and this client is configured against **real prod**, so it re-inflated exactly the counters the 4.0.0 backfill had corrected. The contract record claimed this client pointed at the retired `luxletter-b7a40` project and therefore could not reach prod; that was **false and corrected at 4.1.1**. Nothing but "nobody currently runs it" stood in the way.

Landed: **2.13.0** reader byline (`author`, `publish_date` as a *calendar* date with no timezone conversion, source host, 220 wpm reading time) · **2.15.0** shelf-colour token swatches, replacing a free-text "Color (hex)" field that could not produce a conforming value · **2.19.0** `processing_stage` ("Reading the source" / "Indexing passages") · **2.20.0** shelf split, review-before-write · **2.21.0** OAuth `connection` · **2.29.0/2.30.0** timezone control + activation send · **2.33.0** the pinned-for-next-letter block, with its own subscription · **2.35.0** per-chunk shelf overrides computed at read · **3.1.0** the dwell rule, batched flush, and the reversible finish control · **4.0.0** one event, one counter.

Three defects found by reading the code this touched, none on the task list: `ActivityItem.statusLabel` ended `default: return status` — **the 2.19.0 defect itself**, showing users the literal `pending_upload`; `readTime` used **200 wpm** where the contract normatively says 220, so this client disagreed with the web reference on every document; and `NewsletterSettings` never modelled `itemsPerNewsletter`, **half of which is the per-letter pin cap**, so the pinned block would have had to guess.

**Study and Scripture are BUILT, end to end.** With them, this client reaches feature parity with the web reference. Contract suite **278 tests green**, `flutter analyze` clean apart from two pre-existing `landing_page` lints.

**Scripture** — the citation parser (`lib/scripture/parse.dart`, 22 cases) against a byte-identical copy of `spec/scripture-books.json`, pinned by test: `aliases_douay_rheims` is never merged (DR "1 Kings" is 1 Samuel and "Ecclus" is Sirach — both must return `null`), and a bare book name is not a citation. Plus `fn_scripture_lookup`, the settings pair with its **own** closed key set, and the opt-in readings-letter panel on Letters. **No send action there, deliberately** — `fn_build_scripture_newsletter` is an OIDC-only worker with no `fn_request_*` counterpart, so a button would be the 1.5.1 defect; and the **calendar is shown, not chosen**.

**Study** — all seven `fn_study_*` endpoints, three read-only collections, the programs list, the editor (ordered 1–10 source picker, `SourceKindPanel`, `UnitPanel`, syllabus attach → **editable** review → apply) and the session player at `/study/session/:id`, which is where the session email's CTA lands. The player subscribes to the **one** session document while `fn_submit_study_answer` writes into it — that is what makes a session resumable. Grading is non-optimistic, return dates come from `item.due_at`, `alreadyGraded`/`itemRetired` read as **recorded, never as errors**, and the gradable check is on **status, not item count** (the build writes `items` under `generating` before the questions are drawn — 2.37.2).

**Fixed in passing:** `listNewsletters` filtered nothing, so the first scripture letter this account generated would have appeared in the **daily** history. Now `kind != "scripture"`, never `== "daily"` — the field is absent on every pre-2.24.0 record and equality would drop a real user's whole history.

**One defect the port's own tests caught:** the web parser reaches the right output for a multi-chapter crossing range via a loose `null > n`; Dart will not compare a null, so `Genesis 1:1-3:5` crashed on the middle whole chapter.

**Not harness-provable, stated rather than implied:** `logReadEvent`'s transaction itself. `fake_cloud_firestore` cannot resolve here (4.1.1 is incompatible with `cloud_firestore` 6.x; 4.2.0 needs `meta ^1.17.0` against this SDK's 1.16.0), so the *rule* is extracted as a pure function and asserted while the Firestore plumbing is not. Same class as the web reference's own blind spot.

**2.5.0 (ADR-014) + 2.6.0 (ADR-015) — notification channels A+B, landed 2026-07-27.** `Api` gains `createNotificationChannel`/`updateNotificationChannel`/`deleteNotificationChannel` + `registerDevice`/`unregisterDevice` (added `ApiService.delete`); `ActivityItem` carries an additive `level` (`ActivityItem.docLevel` derives it for document rows) and `firestore_service` maps it on both event and document items; new `NotificationChannel` model + `FirestoreService.subscribeNotificationChannels`; `pages/notification_settings_page.dart` (route `/settings/notifications`, linked from Settings) is the CRUD editor (types onscreen/email/push, level FilterChips). Contract harness: `api_requests_test` now covers the multi-method `fn_notification_channels` + `fn_register_device`/`fn_unregister_device` via a method-aware dispatch (query merged into the request body, null-body DELETE handled); `_suites` +`api/notification-channels`,`api/device-registration`. **+117 tests pass**, pin → 2.6.0. **Deferred (non-conformance, like the web VAPID-key prerequisite):** live push token acquisition needs `firebase_messaging` + a registered native Firebase app — a push channel saves now but doesn't yet register an FCM token on this device.

**2.7.0 (ADR-016) — podcast ingestion, landed 2026-08-01.** `_detectUrlType` (`upload_notifier.dart`) maps `podcasts.apple.com` and `open.spotify.com/episode/*` → `podcast` (one more `fn_ingest_url` type — no new endpoint, INV-07); `Document` gains a nullable `sourceAudioUrl` (`source_audio_url`, the resolved RSS enclosure). `reader_page.dart` parses real per-line `data-start` timestamps from transcript chunk HTML (`_lineStarts`) and `pages/reader/listen_panel.dart` **prefers `sourceAudioUrl`** (plays the real episode, no TTS/`fn_generate_audio` step) **+ those real timestamps** over the word-count-proportional approximation. Podcast type label/icon added (`activity_item.dart`, `chat_notifier.dart`, `library_page.dart`); add-source hint → "Paste a link — article, video, or podcast…". Live playback of the enclosure works via the existing `audioplayers` dep.

**2.8.0 (ADR-017) — screenshot-resolved article carries the screenshot as a second source, landed 2026-08-01.** `Document` gains a nullable `sourceImageUrl` (`json['source_image_url']`); `pages/reader/original_panel.dart` renders **two sources** when it's set — the captured screenshot (`Image.network(sourceImageUrl)`, no `fn_get_raw_document_url` call) + a "View original article" button to `sourceUrl` — matching the web `OriginalPanel`.

**Pin advanced to 2.8.0** (both 2.7.0 and 2.8.0 above landed together): `flutter analyze` clean, the full Tier-1 contract suite green including `pin_check` and `firestore_shapes` doc-shapes (the new `sourceAudioUrl`/`sourceImageUrl` fields are additive, absent on captured fixtures).

Per-version delta status: all ✅ (1.1.0 reader-html · 1.2.x auto-org incl. settings/charter/reorg · 1.2.4/1.3.0 cloud-import · 1.4.0 Tier-C incl. sync-settings/freshness/completion-notifications · 1.5.0 · 2.0.0/2.2.0/2.3.0 · 2.5.0/2.6.0 channels · 2.7.0 podcast · 2.8.0 source_image_url). Baseline `reader.md`/`library.md` (all 6 reader panels, `fn_update_document` priority/tags, audio, multi-image) also complete. **Design-fidelity leftovers cleared 2026-07-26** — Geist/Geist Mono now bundled as OFL assets (Inter stand-in retired) and the sidebar/drawer render true plum chrome in both themes. **The one remaining non-conformance item is native iOS/Android Firebase registration** (still web-target only), which is harness-untested and needs interactive `flutterfire configure` against the live project.

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

**Native Firebase registration — DONE 2026-08-15.** Both platforms are registered in prod as **`xp.NoteLetter.Flutter`**, with sign-off. Its own bundle id deliberately: `xp.NoteLetter` belongs to the Swift app in `NoteLetter/` (Firebase allows one iOS app per bundle id per project), and although it is free on *Android*, `NoteLetter-android/` is a reserved slot for a planned native client — taking it here would foreclose that with a config decision rather than a product one. Verified: 2 apps before, 4 after, and the Swift app's iOS registration unchanged.

**flutterfire does not rename the native projects**, so both still said `com.example.*` while the generated config said `xp.NoteLetter.Flutter`. That mismatch fails at Firebase init rather than at build, so `applicationId`, `namespace`, the Kotlin package and `MainActivity`'s directory all moved with it, and all six pbxproj configurations were updated. `firebase_options.dart` now returns real options for `android` and `ios`; only macOS/Windows/Linux throw, which is accurate.

**Verification is partial and stated as such:** `xcodebuild` parses the project and resolves `PRODUCT_BUNDLE_IDENTIFIER = xp.NoteLetter.Flutter`, matching the plist. **The APK was not built — there is no Android SDK in this environment** — so the Android rename rests on string equality with `google-services.json`, which is exactly what Firebase checks, but not on a build. **A real device/emulator run is owed** and is the acceptance gate for push, which still needs `firebase_messaging` wired up.

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
