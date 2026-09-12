# Flutter work queue

folded-through: 4.52.1
pin-holds-at: 4.4.0

Driver: `/flutter-next` (one item per run, top to bottom). Refresh: `/parity flutter`.
Lint: `python3 tool/queue.py lint`. Format and rules: the header of `tool/queue.py`.
What this queue must satisfy: `../NoteLetter-contracts/spec/clients/flutter.md`.

Every CHANGELOG Flutter tandem line at or below `folded-through` is either a `folds:` entry
below or an n/a row in `flutter.md` §Out of scope. Items are in dependency order: the kit
widget an item builds is what the next one composes with. A `done` item is never edited —
a new obligation on a finished screen is a new item.

## F-00 · Red items, and a number nothing measured
- status: done 2026-09-11
- screen: none
- route: none
- spec: spec/api/cloud-storage.md; spec/clients/flutter.md §Out of scope
- web: src/api.js
- flutter: lib/services/api.dart; test/contract/api_requests_test.dart; lib/widgets/nav_drawer.dart; lib/build_info.dart
- folds: 4.45.0 (`review_rules` on `fn_sync_settings`); TODO "A fabricated storage figure is on screen in Flutter"; TODO "Flutter's contract suite is RED on `cloud:review-rules-set`"
- device_test: signs in and reaches the library
- shots: none
- extra_gates: none
- notes: (1) `Api.syncSettings` sends `{provider}` where the 4.45.0 fixture `cloud:review-rules-set`
  carries `{provider, review_rules}` — add `Map<String, dynamic>? reviewRules` → `review_rules`,
  and pass it through in the `fn_sync_settings` adapter (api_requests_test.dart ~:213). Web:
  `syncSettings` in api.js is the reference shape. (2) `nav_drawer.dart` draws `2.1 GB / 6 GB used`
  and a 0.35 bar; no endpoint reports storage, so delete the figure and the bar (umbrella trap:
  show only measured numbers). (3) `lib/build_info.dart:12` names `test/contract/build_info_test.dart`,
  which does not exist — the check is the second test in `pin_check_test.dart`; fix the comment.
  Gate: `flutter test test/contract test/kit -x pin` goes to zero failures.

## F-01 · Extraction markers — shared splitter + §17 kit widgets
- status: done 2026-09-12
- screen: none
- route: none
- spec: spec/extraction-contract.md; spec/component-kit.md §17; spec/decisions/ADR-089-a-marker-is-an-annotation-not-a-sentence.md
- web: src/shared/extractionMarkers.js; src/shared/MarkedText.jsx; src/styles/app-kit.css
- flutter: lib/shared/extraction_markers.dart (new); lib/widgets/kit/kit_markers.dart (new); lib/widgets/kit/kit.dart; test/contract/extraction_markers_test.dart (new)
- folds: 4.52.0; TODO "Flutter and iOS have no renderer"
- device_test: signs in and reaches the library
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/extraction_marker_check.py — Flutter flips PENDING → ok
- notes: Port `extractionMarkers.js` (six labels, the trailing `.` belongs to the marker, a body
  holding `[`/`]` is not a marker, case-sensitive). `KitMarkerAside` (§17.1) and `KitMarkerInline`
  (§17.2). The gate EXECUTES each consumer over an 8-row table via `RUNNERS` in
  `harness/extraction_marker_check.py` — this item adds the `flutter` runner there (a `dart run`
  of a tiny script that prints the labels and the splits as JSON, mirroring the web runner) in a
  contracts-repo commit made BEFORE the Flutter commit. Nothing renders a marker yet: F-06, F-07,
  F-09 and F-12 wire the widgets into their screens.

## F-02 · Notifications — recompose
- status: done 2026-09-11
- screen: notifications
- route: /settings/notifications
- spec: spec/screens/notifications.md §Composition §States §The editor; spec/component-kit.md §1.5 §2.2 §6.8 §14.1
- web: src/pages/NotificationSettings.jsx; src/styles/app-settings.css; src/styles/app-kit.css; src/styles/app-responsive.css
- flutter: lib/pages/notification_settings_page.dart; lib/widgets/kit/kit_headers.dart; lib/state/settings_notifier.dart; lib/models/notification_channel.dart; lib/services/api.dart; pubspec.yaml
- folds: 4.32.1 (`enabled` defaults true only on null — `??`, never `== true`); 4.8.0 (send `fid` via `firebase_app_installations` on register); 4.34.3 (§14 failure block on this screen); TODO "Flutter and iOS still register push by token only"
- device_test: notifications composes from the kit
- shots: notifications
- extra_gates: none
- notes: §2.2 sub-screen header is a NEW kit widget — build it in `kit_headers.dart`, not inline;
  F-03/F-04/F-05 reuse it. A channel that cannot deliver says so in its row (§14.2). The device
  test is new: add it to `device_run_test.dart` asserting required parts in order (never
  `pumpAndSettle` on a screen with a live animation — bounded `pump` loops).

## F-03 · Support — recompose
- status: done 2026-09-12
- screen: support
- route: /support
- spec: spec/screens/support.md §Composition §Behaviour §States; spec/component-kit.md §2.2 §5.2 §10 §13 §14.1
- web: src/pages/SupportView.jsx; src/styles/app-support.css
- flutter: lib/pages/support_page.dart; lib/widgets/kit/kit_cards.dart; lib/widgets/kit/kit_composer.dart; lib/state/support_notifier.dart
- folds: 4.18.0 (verify every §13 required part); 4.19.1; 4.33.1
- device_test: the footer opens support, and a send is write-before-move
- shots: support
- extra_gates: none
- notes: The passage card at reduced emphasis is a `KitPassageCard` variant, not a new card. The
  existing device test already covers write-before-move; extend it with the composition assert.

## F-04 · Settings — recompose
- status: done 2026-09-12
- screen: settings
- route: /settings
- spec: spec/screens/settings.md §Composition §Summaries section §Client-local preferences §States; spec/component-kit.md §2.1 §3 §4 §6 §14.1
- web: src/pages/SettingsView.jsx; src/pages/settings/summaryPrompt.js; src/pages/letters/schedule.js; src/styles/app-settings.css
- flutter: lib/pages/settings_page.dart; lib/pages/settings/summaries_section.dart; lib/pages/settings/summary_prompt.dart; lib/widgets/kit/kit_rows.dart; lib/state/schedule.dart; lib/state/settings_notifier.dart
- folds: 4.39.0 (exclude-days label); 4.3.0 (regenerate + editable style, verify); 2.29.0 (schedule control + timezone); 2.30.0 (switch copy + outcome line); 4.34.3 (§14); 4.32.4 (`AppTheme.htmlStyles`, verify)
- device_test: settings shows the Summaries section
- shots: settings
- extra_gates: none
- notes: `summary_prompt.dart` strings are gated byte-for-byte (`summary_prompt_test.dart`) — never
  reword a prompt. The "Run through setup again" row lands with F-14, not here. A setting row is a
  `kit_rows.dart` pattern; the letter settings that live on this page today move to their own
  route in F-05.

## F-05 · Letters + letter settings — recompose, `html_body`, delivery
- status: done 2026-09-12
- screen: letters
- route: /letters
- spec: spec/screens/letters.md §Composition §Data §States §Pinned sources §Scheduled delivery is a control; spec/component-kit.md §11 §5.2 §14.1; spec/api/newsletter.md
- web: src/pages/LettersView.jsx; src/pages/LetterSettings.jsx; src/pages/letters/LetterDocument.jsx; src/pages/letters/ReadingsLetter.jsx; src/pages/letters/PinnedSources.jsx; src/pages/letters/delivery.js; src/pages/letters/schedule.js; src/styles/app-kit.css
- flutter: lib/pages/letters_page.dart; lib/pages/letters/readings_letter.dart; lib/pages/letters/pinned_sources.dart; lib/pages/letter_settings_page.dart (new); lib/router.dart; lib/widgets/kit/kit_letter.dart (new); lib/widgets/kit/kit.dart; lib/models/newsletter.dart; lib/models/newsletter_settings.dart
- folds: 4.50.0 (`html_body` is the whole letter — render it, not `html`); 4.50.1; 4.22.0 (the `delivery` map + badge, INV-23); 4.24.0 (`emailEnabled` control, `email_failed` row); 2.29.0 + 2.30.0 (letters half); 2.33.0 (pinned sources, verify parts); 4.15.0 (`?p=` source links, verify); 2.26.0 + 2.25.x (readings letter settings, verify); TODO "Flutter is recorded as pending, not implemented" (html_body); TODO "Flutter and iOS render the six delivery activity types but not the delivery map"
- device_test: letters composes from the kit and opens a letter
- shots: letters; letter-settings; letter-reader
- extra_gates: none
- notes: New route `/letters/settings` (web has it; Flutter's letter settings live inside
  `settings_page.dart` today). §11 letter sheet is a NEW kit widget. Newsletters filter
  `kind != "scripture"`, never `== "daily"`. No send button for the readings letter (OIDC-only).
  `letter-reader` is a STATE (open one letter) — add `HOLD_STATE=letter` to `hold_screen_test.dart`.

## F-06 · Study — recompose, §12 Notice, runway
- status: done 2026-09-12
- screen: study
- route: /study
- spec: spec/screens/study.md §Composition §Programs list §Create / edit a program §Session player §States; spec/component-kit.md §12 §5.3 §6.8 §14.1 §17
- web: src/pages/StudyView.jsx; src/pages/study/ProgramEditor.jsx; src/pages/study/SessionPlayer.jsx; src/pages/study/schedule.js; src/styles/app-study.css
- flutter: lib/pages/study_page.dart; lib/pages/study/program_editor.dart; lib/pages/study/session_player.dart; lib/widgets/kit/kit_notice.dart (new); lib/widgets/kit/kit.dart; lib/models/study.dart; lib/services/api.dart
- folds: 4.7.0 (§12 Notice + `material_runway`/`low_material_reason` — never recompute the runway client-side); 2.36.0 + 2.37.x (syllabus UI, verify); 4.52.0 (markers in session excerpts via F-01); 4.34.3 (§14)
- device_test: study composes from the kit
- shots: study
- extra_gates: none
- notes: The seed holds no study program, so `study` is the EMPTY state by construction — same as
  the web reference frame. The session player cannot be shot from the seed; assert it in the
  device test by creating a program through the API in the test, then delete it.

## F-07 · Ask — recompose, route `/ask`, inspector rail
- status: open
- screen: ask
- route: /ask
- spec: spec/screens/ask.md §Composition §Data / endpoints §States; spec/component-kit.md §9 §10 §14.1 §17.2
- web: src/pages/AskView.jsx; src/styles/app-kit.css
- flutter: lib/pages/chat_page.dart; lib/widgets/chat_interface.dart; lib/widgets/kit/kit_rail.dart (new); lib/widgets/kit/kit.dart; lib/router.dart; lib/state/chat_notifier.dart; lib/widgets/sidebar.dart; lib/widgets/nav_drawer.dart
- folds: 4.34.3 (§14 on ask); 4.52.0 (markers inline in citation pills); 4.5.1 (route names follow web)
- device_test: ask composes from the kit
- shots: ask
- extra_gates: none
- notes: Route becomes `/ask`; keep `/chat` as a redirect. §9 inspector rail: the `KitRail*`
  pieces exist for the utility rail — compose the pattern, do not re-spell it. Rail entries in
  `sidebar.dart` and `nav_drawer.dart` follow the web rail order.

## F-08 · Shelves — recompose, route `/shelves`, colour names
- status: open
- screen: shelves
- route: /shelves
- spec: spec/screens/sources.md §Composition; spec/screens/library.md §Shelf granularity and splitting §Shelf color; spec/component-kit.md §5.1 §6.2 §14.2
- web: src/pages/ShelvesView.jsx; src/pages/sources/ShelfView.jsx; src/shared/shelfColor.js; src/styles/app-shelves.css; src/styles/app-sources-shelf.css
- flutter: lib/pages/tags_page.dart; lib/pages/tags/split_shelf_sheet.dart; lib/router.dart; lib/widgets/kit/kit_controls.dart; lib/theme/tokens.dart; lib/state/tags_notifier.dart; lib/widgets/sidebar.dart; lib/widgets/nav_drawer.dart
- folds: 2.15.0 (`tags.color` is a token NAME — a name→token map, and a hex from the seed renders too, per 4.32.2); 2.20.0 (split flow, verify parts); 4.34.0 (subscription `onError`, verify)
- device_test: shelves composes from the kit
- shots: shelves; shelf-color-picker
- extra_gates: none
- notes: Routes `/shelves` and `/shelves/:id`; `/tags` redirects. `shelf-color-picker` is a STATE
  (open the picker) — add `HOLD_STATE=color-picker` to `hold_screen_test.dart`. Setting a colour
  is write-before-move: await `fn_update_tag`, then repaint.

## F-09 · Reader — header, body, summary
- status: open
- screen: reader
- route: /reader/seed-doc-pdf-complete
- spec: spec/screens/reader.md §Composition §Header — byline & reading cost §Reading state & typography §Regenerate summary §States; spec/component-kit.md §8 §5.2 §2.1 §14.1 §17.1
- web: src/pages/ReaderView.jsx; src/pages/reader/SummaryPanel.jsx; src/styles/app-kit.css
- flutter: lib/pages/reader_page.dart; lib/pages/reader/summary_panel.dart; lib/pages/reader/reader_ui.dart; lib/pages/reader/passage_mark.dart; lib/widgets/kit/kit_cards.dart
- folds: 4.46.0 (`_metaRow` → `KitStatCluster` separated-row form; fix the `ruled` conflation in `kit_cards.dart`); 4.3.0 (regenerate, verify); 4.1.0 (detailed stats — optional, opt-in); 4.52.0 (§17.1 asides in passages; TTS speaks channel + body, never the brackets); 4.34.3 (§14); TODO "Flutter draws an icon where the reference draws a sentence"; TODO "Flutter and iOS: §8 is spelled inline on the reader"
- device_test: the reader renders and the passage mark tracks a REAL drag
- shots: reader
- extra_gates: none
- notes: The reader is OUTSIDE `AppLayout` and inside `SupportShell` — keep it there (INV-22).
  Reading speed is 220 wpm. Seed the long document first (`tool/seed_long_doc.py`) for the drag test.

## F-10 · Reader — panels, save obligations, follow-along
- status: open
- screen: reader-manuscript
- route: /reader/seed-doc-pdf-complete
- spec: spec/screens/reader.md §Panels §Saving a manuscript edit §Listen follow-along §Deep link to a passage §Per-chunk shelves §Supersession confirm §Finishing a document; spec/component-kit.md §6.6 §14.2
- web: src/pages/reader/ManuscriptPanel.jsx; src/pages/reader/ListenPanel.jsx; src/pages/reader/SpeedReadPanel.jsx; src/pages/reader/HistoryPanel.jsx; src/pages/reader/ReorganizeSheet.jsx; src/pages/reader/docAudio.js; src/styles/app-speedread.css
- flutter: lib/pages/reader/manuscript_panel.dart; lib/pages/reader/listen_panel.dart; lib/pages/reader/speed_read_panel.dart; lib/pages/reader/history_panel.dart; lib/pages/reader/reorganize_sheet.dart; lib/pages/reader/source_freshness.dart; lib/pages/reader/chunk_shelves.dart; lib/pages/reader/dwell.dart; integration_test/hold_screen_test.dart
- folds: 4.20.0 (the three save obligations — ADR-056); 4.11.0 (per-sentence follow-along); 4.15.0 (`?p=` scroll + flash, verify); 2.35.0 (per-chunk shelves, verify); 3.1.0 (finishing); TODO "Flutter: adopt the three save obligations"
- device_test: the reader opens every panel
- shots: reader-manuscript
- extra_gates: none
- notes: Listen, Original, SpeedRead and History were never opened on a device run — the new
  device test opens each. `reader-manuscript` is a STATE: add `HOLD_STATE=manuscript` to
  `hold_screen_test.dart` (select the Manuscript tab before holding).

## F-11 · Reader — recipe body, source file and set overlays
- status: open
- screen: recipe
- route: /reader/seed-doc-pdf-complete
- spec: spec/screens/reader.md §Recipe body; spec/component-kit.md §5.4 §15 §6.4; spec/features/source-visible-before-completion.md; spec/decisions/ADR-042-recipes-are-a-distilled-content-form.md
- web: src/pages/reader/RecipeBody.jsx; src/pages/reader/OriginalPanel.jsx; src/shared/SourceFile.jsx; src/shared/SourceSet.jsx; src/shared/FileBadge.jsx; src/overlays/SourceFileSheet.jsx; src/shared/Lightbox.jsx
- flutter: lib/widgets/kit/kit_recipe.dart (new); lib/widgets/kit/kit_overlay.dart (new); lib/widgets/kit/kit.dart; lib/pages/reader/original_panel.dart; lib/models/document.dart; lib/services/api.dart; test/contract/api_requests_test.dart
- folds: 4.6.0 (recipe content form, INV-20 — step times only where provable); 4.37.0 (§15.1 source file view, ADR-075); 4.38.0 (§15.2 source set gallery, ADR-076 — the `set` branch of §6.4.2 is three values, not `gcs_path != null`); 4.48.0 (`Document.skipReason`, verify)
- device_test: the reader opens the source file
- shots: recipe; source-file; source-set
- extra_gates: none
- notes: Lands the `fn_get_raw_document_url` fixture adapter and removes it from `_noBuilder` in
  the SAME commit. The `recipe` and `source-set` web frames come from theme-shots STATES that
  write Storage objects; if the Flutter hold cannot reproduce that state from the seed, record
  which frame is unshootable in `screenshots/README.md` rather than faking one.

## F-12 · Search — score explainer, server narrowing, citation path
- status: open
- screen: search
- route: /search
- spec: spec/screens/search.md §Score explainer §Data / endpoints §States; spec/component-kit.md §16 §6.7 §17.2; spec/api/search.md; spec/decisions/ADR-065-a-prefiltered-knn-needs-its-own-index.md
- web: src/pages/SearchView.jsx; src/pages/search/ScriptureResults.jsx; src/styles/app-scripture.css; src/styles/app-kit.css
- flutter: lib/pages/search_page.dart; lib/pages/search/result_card.dart; lib/pages/search/scripture_results.dart (new); lib/widgets/kit/kit_popover.dart (new); lib/widgets/kit/kit.dart; lib/state/search_notifier.dart; lib/models/search_result.dart; lib/scripture/parse.dart; lib/services/api.dart; integration_test/hold_screen_test.dart
- folds: 4.44.0 (§16 anchored popover + `score_parts` — never derive the missing part, ADR-082); 4.28.0 (send `sourceTypes`; drop the local `_matches` narrowing — ADR-065); 2.28.0 + 4.9.0 (`matched_reference`, parallels); 2.28.1 (citation echo — n/a, no palette; recorded in flutter.md); TODO "Search has no citation path"; TODO "Flutter and iOS still narrow search results locally"; TODO "Flutter and iOS: adopt the score explainer"
- device_test: search composes from the kit and opens a reading pane
- shots: search
- extra_gates: none
- notes: `scripture/parse.dart` and `Api.scriptureLookup` exist and nothing calls them — wire the
  citation path so a citation stops running as an ordinary vector query. `search` is a STATE
  (a typed query): add `HOLD_STATE=query` to `hold_screen_test.dart` using the reference's query.
  Verify against a REAL embedding key per this repo's CLAUDE.md, or the screen is green on its
  failure branch.

## F-13 · Sources — review queue, picker, rejections
- status: open
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Import review queue §Sync control §Cloud import §Document processing §States; spec/api/uploads.md; spec/api/cloud-storage.md; spec/component-kit.md §6.4 §6.6 §14.2
- web: src/pages/SourcesBrowse.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/uploadTypes.js; src/styles/app-source.css; src/styles/app-sources-browse.css
- flutter: lib/pages/sources_page.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/browse_section.dart; lib/widgets/file_uploader.dart; lib/services/api.dart; lib/models/import_job.dart; lib/state/cloud_notifier.dart; lib/state/upload_notifier.dart; test/contract/api_requests_test.dart
- folds: 4.45.0 (review rules editor, `awaiting_review` pill, `pptx`; `fn_review_import_jobs`); 4.13.0 + 4.12.0 + 4.10.0 (the picker built from the `api/uploads.md` table, per-type cap; video); 4.19.3 (rejection at the point of paste, §14.2); 4.14.0 (resumable — optional, recorded n/a); 4.47.0 (`Api.retryDocument(force:)` on a skipped row); 1.3.0 + 1.4.0 (trust + sync, verify); TODO "iOS and Flutter pickers"
- device_test: sources composes from the kit, in the contract order
- shots: sources; proc-affordances; source-file-stage
- extra_gates: python3 ../NoteLetter-contracts/harness/upload_set_check.py; python3 ../NoteLetter-contracts/harness/job_status_check.py
- notes: Lands the adapters for `fn_get_cloud_integrations`, `fn_list_cloud_files`,
  `fn_check_source_freshness`, `fn_review_import_jobs` and shrinks `_noBuilder` to the three
  out-of-scope rows in the SAME commit. `file_uploader.dart` is `FileType.image` today.

## F-14 · Onboarding wizard (new)
- status: open
- screen: onboarding
- route: /
- spec: spec/screens/onboarding.md §When it is shown §Rules §States §Composition; spec/component-kit.md §1.5 §5.3 §6.1
- web: src/pages/onboarding/OnboardingWizard.jsx; src/pages/onboarding/steps.jsx; src/shared/usePendingLetterSetup.js; src/styles/app-onboarding-wizard.css; src/App.jsx; src/pages/SettingsView.jsx; scripts/theme-shots.mjs
- flutter: lib/pages/onboarding/wizard.dart (new); lib/pages/onboarding/steps.dart (new); lib/router.dart; lib/pages/settings_page.dart; lib/widgets/kit/kit_ground.dart; lib/state/documents_notifier.dart
- folds: 2.27.0 (the wizard); 2.28.0 (the "I read scripture" entry); 4.14.0 (wizard upload path — the bare PUT); TODO "No onboarding wizard"
- device_test: a first-run account sees the wizard
- shots: onboarding
- extra_gates: none
- notes: Its own frame, not `AppLayout`; the client-local `nl-onboarded` flag via
  `shared_preferences`; shown on the first EMPTY documents snapshot, never before the snapshot
  arrives. Settings gains "Run through setup again". NO web reference frame exists — this item
  first adds an `onboarding` STATE to `NoteLetter-web/scripts/theme-shots.mjs` (open `/settings`,
  click "Run through setup again", shoot), commits it there, then copies it. The library-home
  onboarding checklist (`shared/OnboardingChecklist.jsx`) is in no screen spec: STOP AND ASK
  before building it.

## F-15 · Activity unread badge + shell rail
- status: open
- screen: activity
- route: /activity
- spec: spec/screens/activity.md §Toasts and unread §Composition; spec/component-kit.md §1.2 §2.1
- web: src/shell/AppShell.jsx; src/pages/ActivityView.jsx; src/shared/useLocalFlag.js
- flutter: lib/widgets/sidebar.dart; lib/widgets/nav_drawer.dart; lib/widgets/kit/kit_shell.dart; lib/state/activity_notifier.dart; lib/pages/library_page.dart
- folds: 2.5.0 (client-local `lastSeenActivityAt`, the rail count); 4.32.6 (chapter-opening title beside a wide action set — tandem check on every chapter-opening screen); TODO "Activity's unread badge has no Flutter equivalent"
- device_test: activity composes from the kit and is the MERGED feed
- shots: activity; library
- extra_gates: none
- notes: Refresh both pairs — the rail is in both frames.

## F-16 · Analytics (INV-25) — decide, then build or record
- status: open
- screen: none
- route: none
- spec: spec/features/analytics-events.md; spec/invariants.md
- web: src/analytics.js; src/firebase.js
- flutter: lib/services/analytics.dart (new); pubspec.yaml; lib/main.dart
- folds: 4.41.0; 4.42.0; 4.42.1; 4.43.0
- device_test: signs in and reaches the library
- shots: none
- extra_gates: none
- notes: STOP AND ASK first: INV-25 may not bind a client without a GA4 stream, and this app has
  none configured. If it binds, the provider is guarded by `!useEmulator && !isTest` (INV-25a)
  and `page_location` never carries a document id (INV-25b). If it does not, record the n/a row
  in `flutter.md` §Out of scope and mark this item done.

## F-17 · Raw-primitive lint + kit goldens
- status: open
- screen: none
- route: none
- spec: spec/component-kit.md §How to read a pattern; spec/decisions/ADR-041-composition-is-contract.md
- web: src/styles/app-kit.css
- flutter: test/kit/no_inline_composition_test.dart (new); test/kit/kit_smoke_test.dart; lib/widgets/kit/kit.dart
- folds: TODO "Add golden tests over the kit widgets and the rebuilt screens"
- device_test: signs in and reaches the library
- shots: none
- extra_gates: none
- notes: AFTER every screen above is recomposed, never before — goldens taken today would freeze
  the divergence and call it the standard. The lint fails on a `TextStyle(` or `EdgeInsets(`
  literal under `lib/pages/`; an exemption is a `kit-ok: <reason>` comment at the site.

## F-18 · Pin bump — 4.4.0 → VERSION
- status: open
- screen: none
- route: none
- spec: spec/clients/flutter.md §Pin; CHANGELOG.md
- web: src/api.js
- flutter: CLAUDE.md; lib/build_info.dart; test/contract/pin_check_test.dart; QUEUE.md
- folds: every version above
- device_test: signs in and reaches the library
- shots: none
- extra_gates: flutter test test/contract test/kit (pin INCLUDED); flutter test integration_test/device_run_test.dart (the whole run); python3 ../NoteLetter-contracts/harness/head_build_check.py; python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py; every 5-series gate that reads this repo
- notes: Only when every item above is done. Both pin lines move in one commit, with the full
  battery green INCLUDING the pin test, the whole device run on iPhone 17 and every pair current.
  Then `/contract-change` books the CHANGELOG line listing every folded version, and
  `flutter.md` §Screens reads "composed" on every row.
