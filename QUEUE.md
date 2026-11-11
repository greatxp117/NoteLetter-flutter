# Flutter work queue

folded-through: 5.80.0
pin-holds-at: 5.24.0
retired-shots: shelf-backfill-review   # 4.102.0 (ADR-136): the in-sheet review is a stored task now; its pair is web's review-backfill on /review
retired-paths: lib/pages/library/document_detail_sheet.dart; lib/widgets/kit/kit_section_rail.dart; lib/pages/search/result_card.dart; lib/pages/search/reading_pane.dart; lib/pages/sources/file_under.dart; lib/widgets/kit/kit_capture.dart   # F-99 (2026-10-13): the library row's Priority & tags sheet; a finished source's priority is the reader's (sources.md §Per-source affordances). F-142 (2026-10-30): §19's section rail retired with direction D — the source page's sheet carries Contents (kit §29) F-143 (2026-10-30): Search in direction D reads a result in place among its neighbours (search.md §Composition), so the result card and the reading pane retired with web's ResultCard + ReadingPane (ResultD, lib/pages/search/result_d.dart). F-156 (2026-11-03): File under left the return page and the import picker (5.52.0, ADR-203) — an import is shelved by indexing (INV-12). F-183 (2026-11-11): kit §23's capture card, retired by 5.43.0 (ADR-198), was still on disk unmounted; F-125 lists it.
retired-web-paths: src/pages/sources/ShelfView.jsx; src/styles/app-sources-shelf.css; src/pages/letters/LetterBarActions.jsx   # direction D (web redesign-d 2026-10-30): W1 deleted the spine view (the Library is List / Grid); W4 deleted the letter bar's actions (a68efb7)

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
- status: done 2026-09-12
- screen: ask
- route: /ask
- spec: spec/screens/ask.md §Composition §Data / endpoints §States; spec/component-kit.md §9 §10 §14.1 §17.2
- web: src/pages/AskView.jsx; src/styles/app-kit.css
- flutter: lib/pages/chat_page.dart; lib/widgets/kit/kit_rail.dart (new); lib/widgets/kit/kit.dart; lib/widgets/kit/kit_headers.dart; lib/router.dart; lib/state/chat_notifier.dart; lib/models/ask_thread.dart (new); lib/services/api.dart; lib/services/firestore_service.dart; lib/theme/app_colors.dart; lib/theme/tokens.dart; lib/widgets/sidebar.dart; lib/widgets/nav_drawer.dart
- folds: 4.34.3 (§14 on ask); 4.52.0 (markers inline in citation pills); 4.5.1 (route names follow web); 4.53.0 (ADR-090 — Ask conversation history, fn_ask_turn/fn_ask_threads + the §9 rail); 4.54.0 (ask_threads.preview)
- device_test: ask composes from the kit
- shots: ask; ask-thread; ask-rail
- extra_gates: none
- notes: Route becomes `/ask`; keep `/chat` as a redirect. §9 inspector rail: the `KitRail*`
  pieces exist for the CHROME rail (§1.2) — §9 is a different pattern and wants its own
  `kit_rail.dart`; do not re-spell either. Rail entries in `sidebar.dart` and `nav_drawer.dart`
  follow the web rail order.
  UNBLOCKED 2026-09-12: the rail had no reference implementation and was blocked rather than
  built ahead of it. Resolved by ADR-090 — web now ships it, so this item mirrors rather than
  leads. Read `NoteLetter-web/src/pages/AskView.jsx` and the four frames
  (`ask`, `ask-thread` × light/dark). A turn is ONE `fn_ask_turn` call, not `fn_search_notes`;
  threads and messages are subscriptions; `title` is the first question and `preview` the latest;
  restoring a thread issues no request and must never draw the searching state.

## F-08 · Shelves — recompose, route `/shelves`, colour names
- status: done 2026-09-12
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
- status: done 2026-09-14
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
- status: done 2026-09-13
- screen: reader-manuscript
- route: /reader/seed-doc-pdf-complete
- spec: spec/screens/reader.md §Panels §Saving a manuscript edit §Listen follow-along §Deep link to a passage §Opening at a shared carousel slide §Per-chunk shelves §Supersession confirm §Finishing a document; spec/component-kit.md §6.6 §14.2
- web: src/pages/reader/ManuscriptPanel.jsx; src/pages/reader/ListenPanel.jsx; src/pages/reader/SpeedReadPanel.jsx; src/pages/reader/HistoryPanel.jsx; src/pages/reader/ReorganizeSheet.jsx; src/pages/reader/docAudio.js; src/styles/app-speedread.css
- flutter: lib/pages/reader/manuscript_panel.dart; lib/pages/reader/listen_panel.dart; lib/pages/reader/speed_read_panel.dart; lib/pages/reader/history_panel.dart; lib/pages/reader/reorganize_sheet.dart; lib/pages/reader/source_freshness.dart; lib/pages/reader/chunk_shelves.dart; lib/pages/reader/dwell.dart; integration_test/hold_screen_test.dart
- folds: 4.20.0 (the three save obligations — ADR-056); 4.11.0 (per-sentence follow-along); 4.15.0 (`?p=` scroll + flash, verify); 4.58.0 (`data-shared` — open at the marked slide and draw the standing margin rule; `?p=` WINS when both are present); 2.35.0 (per-chunk shelves, verify); 3.1.0 (finishing); TODO "Flutter: adopt the three save obligations"
- device_test: the reader opens every panel
- shots: reader-manuscript
- extra_gates: none
- notes: Listen, Original, SpeedRead and History were never opened on a device run — the new
  device test opens each. `reader-manuscript` is a STATE: add `HOLD_STATE=manuscript` to
  `hold_screen_test.dart` (select the Manuscript tab before holding).
  4.58.0 is folded here rather than into a new item because this is the item that owns
  §Deep link, and the two rules are deliberate opposites that have to be built together:
  `?p=` is a 2.6s flash and takes precedence; `data-shared` is a standing mark. Two effects
  racing to scroll one pane land on whichever finishes last. Note `folded-through` does NOT
  move for this — 4.53.0–4.57.4 are still unfolded, and claiming otherwise is what that
  marker exists to prevent.

## F-11 · Reader — recipe body, source file and set overlays
- status: done 2026-09-14
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
- status: done 2026-09-14
- screen: search
- route: /search
- spec: spec/screens/search.md §Score explainer §Data / endpoints §States; spec/component-kit.md §16 §6.7 §17.2; spec/api/search.md; spec/decisions/ADR-065-a-prefiltered-knn-needs-its-own-index.md
- web: src/pages/SearchView.jsx; src/pages/search/ScriptureResults.jsx; src/styles/app-scripture.css; src/styles/app-kit.css
- flutter: lib/pages/search_page.dart; lib/pages/search/result_card.dart; lib/pages/search/reading_pane.dart; lib/pages/search/cohesive_column.dart; lib/pages/search/scripture_results.dart (new); lib/pages/search/score_explainer.dart (new); lib/widgets/kit/kit_popover.dart (new); lib/widgets/kit/kit.dart; lib/widgets/kit/kit_controls.dart; lib/state/search_notifier.dart; lib/models/search_result.dart; lib/models/cohesive_reading.dart; lib/models/scripture_lookup.dart (new); lib/shared/local_flags.dart (new); lib/pages/settings_page.dart; test/contract/search_response_test.dart; test/kit/kit_smoke_test.dart; integration_test/hold_screen_test.dart; integration_test/device_run_test.dart; CLAUDE.md
- folds: 4.44.0 (§16 anchored popover + `score_parts` — never derive the missing part, ADR-082); 4.28.0 (send `sourceTypes`; drop the local `_matches` narrowing — ADR-065); 2.28.0 + 4.9.0 (`matched_reference`, parallels); 2.28.1 (citation echo — n/a, no palette; recorded in flutter.md); TODO "Search has no citation path"; TODO "Flutter and iOS still narrow search results locally"; TODO "Flutter and iOS: adopt the score explainer"
- device_test: search composes from the kit and opens a reading pane
- shots: search
- extra_gates: none
- notes: `scripture/parse.dart` and `Api.scriptureLookup` exist and nothing calls them — wire the
  citation path so a citation stops running as an ordinary vector query. `search` is a STATE
  (a typed query): add `HOLD_STATE=query` to `hold_screen_test.dart` using the reference's query.
  Verify against a REAL embedding key per this repo's CLAUDE.md, or the screen is green on its
  failure branch.
  The citation branch is gated on the client-local `nl-scripture` flag (ADR-027 §7), which this
  client had neither a store nor a control for — so `shared/local_flags.dart` and the Settings
  §Scripture row land here too. **Xavier's call 2026-09-14**: default OFF as the reference has
  it, and the toggle inside this item rather than a new one on a done screen, so the path is
  never dark.

## F-13 · Sources — review queue, picker, rejections
- status: done 2026-09-14
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
- status: done 2026-09-14
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
- status: done 2026-09-15
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
- status: done 2026-09-15
- screen: none
- route: none
- spec: spec/features/analytics-events.md; spec/invariants.md
- web: src/analytics.js; src/firebase.js
- flutter: lib/services/analytics.dart (new); test/contract/analytics_test.dart (new);
  pubspec.yaml; lib/main.dart; lib/router.dart; lib/services/api_service.dart;
  lib/state/theme_notifier.dart; lib/state/search_notifier.dart; lib/state/chat_notifier.dart;
  lib/state/upload_notifier.dart; lib/state/cloud_notifier.dart; lib/pages/reader_page.dart;
  lib/pages/search_page.dart; lib/pages/letters_page.dart; lib/pages/letter_settings_page.dart;
  lib/pages/tags_page.dart; lib/pages/support_page.dart; lib/pages/onboarding/wizard.dart;
  lib/pages/study/session_player.dart; lib/pages/tags/split_shelf_sheet.dart;
  ios/Runner/Info.plist; android/app/src/main/AndroidManifest.xml
- folds: 4.41.0; 4.42.0; 4.42.1; 4.43.0
- device_test: signs in and reaches the library
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/analytics_vocab_check.py (5q)
- notes: ASKED, decided to RECORD, then Xavier reversed it: BUILT 2026-09-15. The mirror of
  `src/analytics.js`: the same 19 names, the same closed sets, 26 call sites, and the reference's
  own `screen_name` tokens rather than this client's route spellings — one vocabulary, one
  membership. Three things this platform makes different, and the first is the whole job.
  (1) **On mobile a provider is not something you construct.** The SDK collects on Firebase init
  — `first_open`, `session_start`, `user_engagement` — with NO call site anywhere, so the
  emulator build law 1 requires would post development sessions into the production property
  with nothing in the bundle to find. Collection therefore ships OFF in both native manifests
  and `Analytics.start()` is the only thing that turns it on, behind the same two conditions the
  reference tests. INV-25(a) inverted: the guard is a default, not an `if`.
  (2) **`screen_name` is keyed on go_router's route PATTERN** (`/reader/:docId`), never on the
  location — the reference's `buildPath`-with-no-ids argument transposed, so a route that gains
  an id later cannot carry one onto the wire. `analytics_test.dart` walks the REAL `appRoutes()`
  and fails on a pattern with no token, which is the direction no Python reader can take: the
  route table is a list of closures.
  (3) **Automatic screen reporting is off** because it stamps `firebase_screen_class` from the
  platform view, which is one `FlutterViewController` for every screen here. Recorded honestly:
  that is NOT the mobile shape of ADR-081's `page_location` leak (no id is involved) — it is a
  constant reported as though it were a measurement.
  Gated by 5q's new FLUTTER directions plus COLLECTION-DEFAULT, AUTO-SCREENVIEW, SCREEN-TOKEN and
  READER-INCOMPLETE; 19 gate mutations and 4 test mutations, all red. `firebase_analytics` is
  pinned EXACTLY at 12.4.6, the newest that pairs with the `firebase_core 4.13.0` already locked:
  12.5.0+ moves the Firebase iOS SDK 12.17.0 -> 12.19.0 under Auth, Firestore and Installations,
  and adding a member is not a reason to move the family.
  **The streams already existed**: `analyticsDetails` reports GA4 property 535275995 with a
  mapping for all four apps, this one at stream `15444020564`. `IS_ANALYTICS_ENABLED` is a legacy
  key the modern SDK does not read — proven here, the SDK started with it false — so it was never
  the signal it looked like. **The guard is proven live in both directions** from one launch of a
  prod build: `I-ACS023013 Analytics collection disabled` at init, `I-ACS023012 Analytics
  collection enabled` 1.6s later from `start()`, and only `disabled` on the emulator device run.
  **The wire was read (2026-09-15)** — a throwaway integration test drove the real app against
  REAL PROD as a scratch account, and the SDK's own queue was copied out of the app container
  mid-run. `/reader/CANARY-…` arrived as `_sn=reader`, `/shelves/CANARY-…` as `shelf`, and the
  canary id, the canary query, the scratch email and the scratch uid are absent from the whole
  store. `endpoint=/fn_list_cloud_files` — query stripped. Two findings no code reading would
  have given: `_pn`/`_pc` (the PREVIOUS screen) are attached by the SDK to every screen_view with
  no call site passing them — ADR-081's shape on this platform, id-free only because `_sn` is —
  and `error_code` arrives as `REQUEST_ERROR`, which the catalog did not allow for and the web
  has been sending since 4.41.0. Spec corrected. The scratch accounts are deleted.

## F-17 · Raw-primitive lint + kit goldens
- status: done 2026-09-24
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
- status: done 2026-10-13
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

## F-19 · Shelf page — the shelf's place in the letter
- status: done 2026-09-24
- screen: shelves
- route: /shelves/seed-tag-recipes
- spec: spec/screens/library.md §A shelf's place in the letter; spec/api/tags.md §fn_update_tag; spec/data-model.md; spec/component-kit.md §8 §14.2
- web: src/pages/ShelvesView.jsx
- flutter: lib/pages/tags/shelf_page.dart; lib/state/tags_notifier.dart; lib/models/tag.dart
- folds: 4.88.0 (ADR-122)
- device_test: shelves composes from the kit
- shots: shelf-letter; shelf-letter-error
- extra_gates: none
- notes: Decided 2026-09-24 (Xavier: make it real, not remove it) — this was a stop-and-ask because the web's "Feed today's letter" switch, Lead/Mixed picker and "In your letter" stat stored nothing. 4.88.0 made them `/tags.letter_mode` (lead · mixed · muted; absent or unknown = mixed), written by `fn_update_tag`, read by the letter's selection. Port the section and the stat: the switch (off = muted; on writes mixed), "How prominently" Lead/Mixed only while on, the stat Lead · Mixed · Muted from the stored value. Write before move: one `updateTag(tagId, letterMode:)` per change, controls disabled meanwhile, the control moves only when the call resolves, a refusal is a dense §14.2 line under the section with the controls unchanged. `NLTag`/`Tag` needs `letterMode` decoded (absent → mixed).
## F-20 · Ask rail — §9.1 entry actions (rename · delete)
- status: done 2026-09-13
- screen: ask-rail
- route: /ask
- spec: spec/component-kit.md §9.1; spec/screens/ask.md §Composition §States; spec/decisions/ADR-091-a-list-you-can-only-add-to-is-not-a-list.md
- web: src/pages/AskView.jsx; src/styles/app-kit.css
- flutter: lib/widgets/kit/kit_rail.dart; lib/pages/chat_page.dart; lib/state/chat_notifier.dart; lib/services/api.dart
- folds: 4.55.0 (ADR-091 — the client surface fn_ask_threads PATCH/DELETE never had)
- device_test: ask composes from the kit
- shots: ask-rail
- extra_gates: none
- notes: F-07 built the §9 rail and is done, so this is its own item (a done item is never edited). §9.1 is an OPTIONAL part of §9 and this is its first consumer. The entry becomes a CONTAINER: the open affordance and the two actions are siblings, never nested. On Flutter the rail is §9's overlay form, which is a COARSE pointer — so the cluster is unconditionally present, not hover-revealed, and the trailing time yields to it. Rename edits in place in the title's own type role (commit on submit/blur, abandon on Escape) and the title moves only when `Api.renameAskThread` resolves. Delete confirms first and names what is lost and what is not; deleting the OPEN thread returns the screen to the new-conversation state. A rejection is §14.2 inline in that entry, dense. Both adapters (`fn_ask_threads` PATCH and DELETE, threadId on the QUERY STRING for DELETE) land with this item; `AskView.jsx` is the reference.

## F-21 · Confirmation — §18 kit widget, three copies retired
- status: done 2026-09-13
- screen: none
- route: none
- spec: spec/component-kit.md §18; spec/decisions/ADR-092-a-confirmation-that-cannot-report-a-refusal.md
- web: src/shared/ConfirmDialog.jsx; src/styles/app-onboarding.css
- flutter: lib/widgets/kit/kit_confirm.dart (new); lib/widgets/kit/kit.dart; lib/pages/tags/shelf_page.dart; lib/pages/chat_page.dart; lib/pages/sources/browse_section.dart; lib/pages/study/program_editor.dart; lib/state/chat_notifier.dart; test/kit/kit_smoke_test.dart
- folds: 4.56.0 (ADR-092 — §18 Confirmation and its required failure slot)
- device_test: ask composes from the kit
- shots: none
- extra_gates: none
- notes: The same `_confirm` helper was copied VERBATIM into three pages and a fourth dialog in program_editor drew plain Material chrome. `KitConfirm` replaces all four. The contract is the ADR's: `onConfirm` returns null on success or the server's sentence on a refusal, the widget pops only on success, and a refusal keeps the panel open with §14.2 inside it — so `ChatNotifier.deleteThread` returns `String?` like ActivityNotifier's writers, not `bool`. No screenshot: the panel is not a screen state any pair names.

## F-22 · The two missing confirmations — channel delete, cloud disconnect
- status: done 2026-09-13
- screen: none
- route: none
- spec: spec/screens/notifications.md; spec/screens/settings.md; spec/component-kit.md §18
- web: src/pages/NotificationSettings.jsx; src/pages/SourcesBrowse.jsx
- flutter: lib/pages/notification_settings_page.dart; lib/pages/sources_page.dart
- folds: 4.56.1 (the confirmations §18 made checkable)
- device_test: signs in and reaches the library
- shots: none
- extra_gates: none
- notes: Both actions ran on the FIRST TAP, on every client, while two screen specs required a confirmation. Channel delete is the one that mattered: removing the last `push` channel also unregisters the device, so one tap could stop every notification of every level reaching it — the copy says so. `CloudNotifier.disconnect` already returned null-or-the-sentence, which is exactly §18's contract with the panel; `_remove` in notification_settings_page was changed to match. The third confirmation in 4.56.1 (cloud-import bulk Dismiss) has no Flutter host — this client has no review queue yet — and arrives with that screen.

## F-23 · Sources — folder contents, and a filter that inverted when emptied
- status: done 2026-09-24
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Folder contents; spec/api/cloud-storage.md §`fn_scan_cloud_folder`; spec/features/cloud-folder-scan.md
- web: src/pages/sources/CloudFilePicker.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/api.js
- flutter: lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources_page.dart; lib/pages/sources/folder_contents.dart (new); test/contract/api_requests_test.dart; test/kit/folder_contents_test.dart (new); integration_test/device_run_test.dart
- folds: 4.59.0
- device_test: a folder row in the import picker expands and reports its contents
- shots: sources; folder-contents
- extra_gates: none
- notes: Adds `scanCloudFolder` (GET `fn_scan_cloud_folder`) and the per-folder disclosure on every folder row of the picker, in BOTH modes. Two things must not be merged: `excluded_by_settings` is a setting and carries the affordance back to the type pills; `unreadable` is a fact and carries none — merging them reports a folder of decks as unreadable when it is one toggle from working (pptx is off by default). `held_for_review` qualifies the importable line, it is not a fourth bucket. On `complete: false` the counts are a FLOOR ("at least N") and are never extrapolated. A refusal renders as §14.2 `.fail-inline`, never as a zero — a zero the scan did not measure is what this whole surface is against. NEVER scan the rows the picker lists; the scan is per-folder, on expand. Also: `sync_settings_panel.dart` needs the empty-`include_types` inert note — at 4.59.0 an empty list means nothing imports, where before it silently imported everything.


## F-24 · Re-shoot the four pairs F-15 staled
- status: done 2026-09-15
- screen: none
- route: none
- spec: spec/decisions/ADR-041-composition-is-contract.md
- web: screenshots/
- flutter: screenshots/shelf-color-picker.flutter.light.png; screenshots/shelf-color-picker.flutter.dark.png; screenshots/ask.flutter.light.png; screenshots/ask.flutter.dark.png; screenshots/ask-thread.flutter.light.png; screenshots/ask-thread.flutter.dark.png; screenshots/ask-rail.flutter.light.png; screenshots/ask-rail.flutter.dark.png
- folds: none
- device_test: signs in and reaches the library
- shots: shelf-color-picker; ask; ask-thread; ask-rail
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py — the whole point
- notes: F-15 changed kit_shell.dart, kit_headers.dart, sidebar.dart, nav_drawer.dart, local_flags.dart and both harness files, so every item listing one of them went STALE-PAIR — six pairs. Four were re-shot and committed (activity, library, reader-manuscript, search, notifications, shelves); these four were not, because the disk filled mid-run. Nothing about these screens changed — the §2.1 row F-15 rewrote is the WIDE branch and every frame here is compact — but the gate cannot tell a shared-file touch from a redesign, and that is exactly why it is not waived. Routes: shelf-color-picker `/shelves/seed-tag-recipes` HOLD_STATE color-picker; ask `/ask`; ask-thread `/ask` HOLD_STATE ask-thread; ask-rail `/ask` HOLD_STATE ask-rail (the last two run a REAL turn through the shim on 5099). Delete each target PNG before capturing: simctl refuses to overwrite one of these files in place (`Operation not permitted`) and writes happily once the path is free.

## F-25 · Ask: a sent turn stays, and a failed read says so
- status: done 2026-09-15
- screen: ask
- route: /ask
- spec: spec/screens/ask.md §States; spec/invariants.md; spec/decisions/ADR-097-a-state-setter-is-not-a-consumer.md
- web: src/pages/AskView.jsx
- flutter: lib/pages/chat_page.dart; lib/state/chat_notifier.dart
- folds: 4.62.0 / ADR-098 — Ask scoped to a shelf: `tagId` on fn_ask_turn (a property of the THREAD, fixed at creation, inherited by a follow-up), the shelf named on the header, empty state and composer, component-kit §9.2 scope label in the rail entry, and the TWO empty answers told apart (searched the shelf exhaustively vs filtered out of a truncated pool) · 4.63.0 / ADR-099 — an Ask citation carries `source_url` (copied from the document, null for a stored file and an image set) and offers it named by HOST; the kit's `.pact` inline action was scoped to `.passage` on web and Ask's three uses rendered as browser buttons — check the Flutter equivalent is the kit's own control and not a raw TextButton · 4.65.0 / ADR-101 — a conversation is a place: the open thread is `/ask/thread/{threadId}` (three route forms, the thread form carrying no shelf segment because the thread carries its own scope), the first turn navigates to the thread `fn_ask_turn` returned once it is recorded, and "New conversation" and deleting the open thread both return to `/ask`. `chat_page.dart` opens the Reader with `context.go`, which REPLACES — the citation must leave a way back (see F-26)
- device_test: sends a question with the network off: the question stays on screen with the failure and a retry, and never returns to the composer
- shots: ask-turn-failed
- extra_gates: failure_pattern_check.py
- notes: Two rules from 4.61.0. (1) The turn the reader sent is rendered from send until its own STORED message arrives to replace it — counted against the copies the thread already held, so asking the same question twice does not clear the new turn against the old one's message — and a refusal leaves it in place with the server's sentence (§14.2) plus a retry that re-sends that turn, never back in the composer. (2) The transcript and the rail are two subscriptions and each renders §14.1 in its own region when it cannot be READ; neither may fall back to an empty state, which asserts the reader has asked nothing. Flutter's streams already pass onError (INV-24's third layer) — what it owes is the consumer and both regions. The fourth layer added at 4.61.0 (a React state setter is not a consumer) is JS-specific and has no Dart analogue.

## F-26 · Reader — one continuous scroll, §19 Section rail
- status: done 2026-09-15
- screen: reader
- route: /reader/seed-doc-pdf-complete
- spec: spec/screens/reader.md §Continuous scroll §Composition §Deep link to a passage §Opening at a shared carousel slide; spec/component-kit.md §19; spec/decisions/ADR-100-a-panel-is-not-a-place.md
- web: src/pages/ReaderView.jsx; src/styles/app-source.css
- flutter: lib/pages/reader_page.dart; lib/pages/reader/reader_ui.dart; lib/widgets/kit/kit_section_rail.dart (new); lib/widgets/kit/kit.dart
- folds: 4.64.0 (ADR-100 — six sections in one scroll, the rail reports scroll position, nothing is hidden) · 4.65.0 (ADR-101 — the back control NAMES the screen the Reader was opened from and returns there; `reader_page.dart` hardcodes `Library` in both places today. A pushed Reader satisfies the rule with a pop, but `context.go` replaces, so either push from the citation or carry `?from=` as web does — and a `from` the router does not produce is dropped, never guessed: cold opens say `Library` → `/sources`)
- device_test: the reader scrolls from Summary to History without a tap, and the rail's current jump follows the scroll
- shots: reader
- extra_gates: none
- notes: A new item rather than a fold into F-09/F-10/F-11 because all three are done and this changes the frame they were built into.
  The acceptance test is the DEEP LINK, not the scroll: open /reader/{doc}?p={chunk} cold and the passage must come into view. On web that had never worked, because the panel holding the anchor was not mounted until the reader picked its tab (CHANGELOG 4.64.0). Flutter must not reproduce it — check the cold open, not the tap.
  Order is normative (Summary · Manuscript · Speed read · Listen · Original · History). Deferred mount on approach is allowed; mount-on-tap is the defect.
  Speed read's keyboard bindings, if any, are scoped to its own section.

## F-27 · Re-shoot every pair F-16 staled
- status: done 2026-09-15
- screen: none
- route: none
- spec: spec/decisions/ADR-041-composition-is-contract.md
- web: scripts/theme-shots.mjs
- flutter: screenshots/README.md
- folds: none
- device_test: none
- shots: ask; ask-thread; letters; letter-settings; letter-reader; notifications; support; study; shelves; shelf-color-picker; reader; reader-manuscript; recipe; source-file; source-set; search; activity; library
- extra_gates: screenshot_pair_check.py
- notes: F-16 (measurement) added a track() call to almost every page file, so
    almost every pair in this repo is now OLDER than the screen it photographs and
    screenshot_pair_check reports 22 STALE-PAIR. None of them is wrong in what it SHOWS
    — an analytics call renders nothing — but a frame older than its code is exactly
    what the gate refuses to trust, and a standing red is a gate nobody reads.
    Re-shoot each with tool/shots.sh + tool/web_frames.sh; ~2.5 min apiece on the
    simulator. Six were already re-shot while F-25 was landing (ask-rail, onboarding,
    sources, proc-affordances, source-file-stage, and F-25's own ask-turn-failed),
    so those are current unless a later commit touches their screens.
    LOOK at each set of four while re-shooting: the ritual is the comparison, not the
    capture, and a re-shoot that only refreshes timestamps is the gate being fed.

## F-28 · The comparator matches an EMBEDDED token
- status: done 2026-09-24
- screen: none
- route: none
- spec: fixtures/normalization.md (rule 3); fixtures/tokens.json
- web: tests/contract/helpers/match.js; tests/contract/fixture-tokens.test.js
- flutter: test/contract/api_requests_test.dart; test/contract/token_match.dart (new); test/contract/fixture_tokens_test.dart (new)
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Contract 4.66.1. `normalization.md` says a token's predicate replaces string
    equality, and `_match` dispatches on `startsWith('«')` — so a token EMBEDDED in a
    longer string never reaches a predicate at all. Three shapes are embedded today:
    a signed URL (`…?«sig»`), a gcs path carrying `«uuid#1»`, and the new `«seconds»`
    countdown inside a 429 RATE_LIMITED sentence. Each one falls through to string
    equality AGAINST THE TOKEN TEXT and would fail the moment anything compared one.
    Nothing is red because no suite deep-compares such a value today — they all live
    in `api/*` response bodies, which this client FEEDS to the client rather than
    compares. That is why this is debt and not an outage.
    Mirror the reference: split the expected string on `«[^»]*»`, apply each token's
    predicate to the span it stands for, match the literal text between them exactly,
    and keep `«uuid#N»` identity across an embedded and a whole-value occurrence.
    Mutation check: removing the embedded dispatch must fail the positive cases
    (it fails 3 of 7 on web).

## F-29 · Look again: the web reference moved on three screens
- status: done 2026-09-25
- screen: support · notifications · reader (Summary)
- route: /support · /settings/notifications · /reader/{id}
- spec: spec/component-kit.md §How to read a pattern ("a pattern may not be scoped to its first host") · §2
- web: src/pages/SupportView.jsx; src/pages/NotificationSettings.jsx; src/pages/reader/SummaryPanel.jsx
- flutter: lib/widgets/kit/kit_headers.dart; lib/pages/support_page.dart; lib/pages/notification_settings_page.dart; lib/pages/letter_settings_page.dart; lib/pages/reader/summary_panel.dart; test/kit/goldens/headers.light.png; test/kit/goldens/headers.dark.png
- folds: 4.88.1 (component-kit §2.2 corrected)
- device_test: none
- shots: support; notifications; letter-settings
- extra_gates: screenshot_pair_check.py
- notes: Contract 4.66.2. Three web screens changed what they DRAW, not what they do:
    Support and Notification settings each open with the eyebrow/lede pair and were
    mounting a class whose only rule lived on another screen, so the lede rendered as
    bare body copy; it is the kit's standalone italic-serif lede now (`.sources-sub`,
    §2). The reader's Summary panel's "Edit your summary style" was the same shape and
    is the underlined muted-sans link it was always meant to be.
    Nothing here is a Flutter DEFECT — there is no cascade, so this failure mode cannot
    happen in a widget kit. What is owed is the comparison: the reference frames in
    screenshots/ were updated with the web ones, so look at all four per screen and ask
    whether the Flutter lede and the Flutter link carry the same type role. If they do,
    close this by re-shooting nothing.

## F-30 · A batch that partly failed reads as a batch that worked
- status: done 2026-09-25
- screen: sources (import review queue)
- route: /sources
- spec: spec/api/cloud-storage.md §fn_review_import_jobs · spec/decisions/ADR-103-a-record-moved-before-its-task-is-a-record-nobody-owns.md §Decision 4 (as amended) · spec/component-kit.md §14.2
- web: src/api.js; src/pages/sources/CloudImportPanel.jsx
- flutter: lib/services/api.dart; lib/state/cloud_notifier.dart; lib/pages/sources_page.dart
- folds: 4.69.0 (`failed` on `fn_review_import_jobs`)
- device_test: none
- shots: sources
- extra_gates: none
- notes: Contract 4.69.0. `reviewJobs` awaits the call and reads **nothing out of the
    response** — not `skipped`, and now not `failed` either. Both are id lists and they
    mean opposite things, which is why reading neither is worse than it looks: a batch
    where the queue refused returns **202**, so the current code returns `null` (its
    "success") and the reader is told nothing at all. The two lists:
      `skipped` — a JUDGEMENT about an id (already triaged elsewhere, foreign, gone).
        Not an error; the row leaves the queue on the next snapshot. Web renders a
        measured count in `.proc-note`.
      `failed`  — the task QUEUE refused, so the approve started nothing. The row is
        `error` with a sentence and retries through `retryImportJob`. Web names the
        FILE, not a count: "something went wrong" and "reading-pack.pdf could not be
        started" are different sentences and only one says which file to retry.
    Third fact, derived rather than sent: the server STOPS at the first `failed` id, so
    the four buckets do not cover every id sent. Anything past it was not attempted and
    is still `awaiting_review` — `sent − approved − dismissed − |failed| − |skipped|`.
    Web stops sending further chunks once a chunk comes back with `failed`.
    `failed` is §14.2 inline and sits BESIDE the skipped note rather than replacing the
    section — what the batch did do is real and already on the rows. Mind the §14.2
    trap: a failure line composed from the kit can be outdrawn by its host and render as
    body copy (ADR-070, 4.34.2).

## F-31 · A refused read draws zeros, and the type cannot say otherwise
- status: done 2026-09-25
- screen: library · sources · shelves · reader · study
- route: /
- spec: spec/component-kit.md §8 · spec/decisions/ADR-109-an-unmeasured-figure-is-not-a-zero.md
- web: src/shared/Stat.jsx; src/App.jsx; src/shell/AppShell.jsx; src/pages/ShelvesView.jsx; src/pages/AdminMetricsView.jsx
- flutter: lib/widgets/kit/kit_cards.dart; lib/pages/tags/shelf_page.dart; lib/pages/reader_page.dart; lib/state/documents_notifier.dart; test/kit/kit_smoke_test.dart
- folds: 4.75.0 (§8 unmeasured figure)
- device_test: none
- shots: library; shelves
- extra_gates: `python3 ../NoteLetter-contracts/harness/stat_figure_check.py --target flutter`
- notes: Contract 4.75.0, and the gate already reports this client as *behind* every run —
    it becomes a FAILURE the day the pin reaches VERSION. `KitStat` takes
    `final String value`, so a screen **cannot express** "this was not measured": every
    cluster draws a refused or unarrived subscription as whatever its caller computed,
    which is `0` everywhere it is a count. Web's frame of the defect is
    `NoteLetter-web/screenshots/reader-error.web.light.png` — the §14.1 block and three
    confident zeros in one picture.
    Make `value` nullable and render `—` for null: the numeral's own face and size at
    `t.fgSubtle`, the label unchanged, the **denominator dropped with it** (`— / 12` is a
    claim about a total nothing read), and any state the value decides (a level tint, an
    unread highlight) suppressed. `0` must still draw `0` — an empty library is a real
    measurement and §7's offer beside it needs that figure true; assert both directions,
    because a `?? '0'` at the call site passes a test that only checks the dash.
    Then the call sites: every page computing a figure out of a notifier passes `null`
    while `error != null` or the first snapshot has not arrived. `DocumentsNotifier`
    already carries the error (C2's subject) — this is the same read, one layer out.
    Gate: the extra_gate above stops saying "behind", and `flutter test test/kit` —
    the cluster's cases go in `kit_smoke_test.dart` beside the kit's others.

## F-32 · A refused rename keeps the name the server refused
- status: done 2026-09-25
- screen: shelves
- route: /shelves/{id}
- spec: spec/component-kit.md §Rules (*write before you move*, text-field clause) · §14.2
- web: src/pages/ShelvesView.jsx (`saveName`); tests/contract/optimistic-revert.test.js
- flutter: lib/pages/tags/shelf_page.dart; test/kit/shelf_rename_test.dart (new)
- folds: 4.75.2 (the text field's half of ADR-022)
- device_test: none
- shots: shelves
- extra_gates: none
- notes: Contract 4.75.2. This client is **already better than web was** — `_saveName`
    awaits, records `_nameError` and moves `_savedName` only on success, so a refusal
    never reads as a rename. What it does not do is the other half: `_name` (the
    `TextEditingController`) keeps the refused text, so the field still SHOWS a name the
    shelf does not have, under a sentence saying it could not be saved. §Rules' new
    clause is explicit — the field goes back to the value the server still holds.
    Fix: in the `err != null` branch, `_name.text = _savedName` (and leave the cursor
    at the end). Then assert it: a widget test with `updateTag` returning a message,
    asserting the controller's text is the OLD name AND `KitFailureInline` carries the
    server's sentence — plus the control direction, an ACCEPTED rename that keeps the
    new text, because a revert that fires on success would be worse than none (4.34.8).
    `letter_settings_page.dart` is NOT in scope and was checked: its fields are
    controller-backed behind an explicit Save, so there is no debounced optimistic
    write to revert — web's `putReadings` has no counterpart here.


## F-33 · The readings day view — a screen this client does not have
- status: done 2026-09-18
- screen: scripture-day
- route: /letters
- spec: spec/screens/letters.md §"See all" is a live search, and says so; spec/decisions/ADR-029-readings-letter-is-a-second-newsletter.md §5; spec/component-kit.md §14.1
- web: src/pages/letters/ScriptureDayView.jsx; src/pages/LettersView.jsx; src/styles/app-scripture.css; tests/contract/scripture-day-partial-failure.test.js
- flutter: lib/pages/letters/scripture_day_page.dart (new); lib/pages/letters/readings_letter.dart; lib/pages/letters_page.dart; test/kit/scripture_day_test.dart (new)
- folds: 2.24.0 (ADR-029 §5, the live "See all"); 4.75.3 (§14.1 per reading)
- device_test: the readings day view opens from a letter and composes from the kit
- shots: scripture-day
- extra_gates: none
- notes: **Xavier's call, 2026-09-18: this is a parity gap, not a web-only surface.**
    It was neither — the screen exists only on the reference, is named in no §Out of
    scope row and was in no queue, which is exactly the standing `spec/clients/flutter.md`
    §Out of scope calls "a fixture nothing drives and nothing owns".
    `ReadingsLetterSection` renders the letter and its archive rows; what it has no
    counterpart for is `rl-seeall` → `ScriptureDayView`. Build the day view: the folio,
    the day name (`liturgical_day.name`, and note `liturgical_day` is a **MAP** — the
    field that threw a Dart cast when it was modelled as `String?`), the stand, the Live
    banner, then one section per reading.
    **It re-runs the search NOW** (ADR-029 §5) — one `Api.searchNotes(r.ref, limit: 50)`
    per reading, never a replay of the stored `passages`, because freezing it shows a
    reader fewer passages than their library now holds. The stored `passages_found` is
    what makes the count honest AS SENT, and the banner states the difference.
    The four states the web frames show, all of which came out of B7 and are the reason
    this item exists at all (`NoteLetter-web/screenshots/scripture-day{,-failed}.web.*`):
    a reading that could not be searched **answered nothing, not zero** — it draws
    `KitFailureBlock` (naming line, the server's sentence, the `request_id`, one Retry
    that re-runs **that one reading**) where §7's offer would be, `—` in the count slot,
    stays OUT of the live tally, and suppresses the drift claim in favour of a partial
    sentence. A reading that genuinely found nothing still gets §7's offer. Do not
    reproduce web's first shape: it used §14.2, and the frame showed the server's own
    sentence asking for a `request_id` that §14.2 cannot draw.
    Gate: `flutter test test/contract test/kit -x pin`, the device test above, and the
    pair — `tool/shots.sh scripture-day` beside the web frames already committed.

## F-34 · Re-shoot the pairs a shared kit file staled
- status: done 2026-09-25
- screen: activity
- route: /
- spec: spec/decisions/ADR-041-composition-is-contract.md
- web: scripts/theme-shots.mjs
- flutter: tool/shots.sh; tool/web_frames.sh
- folds: none
- device_test: none
- shots: activity; library; letters; letter-settings; notifications; ask; ask-thread; ask-rail; ask-turn-failed; search; reader-manuscript; recipe; source-file; source-set; sources; proc-affordances; source-file-stage
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: `screenshot_pair_check.py` is RED on 18 pairs and it is right to be: a pair older than the code is a pair nobody has looked at since. Two are older than this item — F-20 `ask-rail` and F-25 `ask-turn-failed` went stale on 2026-09-15 and were already failing before F-33 started (verified by stashing every change and re-running). The other 16 were staled by F-33's commit, which touched `kit_shell.dart` and `kit_headers.dart` — files many items list, so the gate's timestamp rule fires on all of them. **What the change can actually reach was measured, and it is not these.** `ChapterOpening.footnote` is null-default and additive. `KitUtilityBar`'s crumb floor fires only where a crumb exists, and the bar is mounted in three places: the day view, `letter_reader.dart`, and `AppLayout` — whose bar renders in the WIDE branch only and is passed a crumb by NO page. Both reachable screens were re-shot and looked at. So this item is the honest cost of a time-based gate, not a list of suspected defects — which is also why it must not be closed by touching the files: re-shoot each pair, LOOK at all four frames, and fix whatever looking finds. A pair refreshed without being read is the ritual not having run, which is the thing this gate exists to catch. Do it in one pass after the next kit change rather than per item, and expect it to recur every time a shared kit file moves — if that proves too noisy to act on, the gate needs a direction that reads WHAT changed rather than WHEN, and that is a change to the gate, booked here, not a reason to ignore a red run. (2026-09-25, second half of the pass: settings, study, onboarding, shelves and shelf-color-picker re-shot and read; onboarding's footer now owns the phone's bottom inset; F-56 and F-57 booked. STOPPED with the emulator hub down — auth 9599, storage 9699 and the hub 4600 stopped answering during `tool/seed_recipe_and_sources.py`'s first Storage upload, while Firestore 8580 and Pub/Sub 8585 stayed up. Still owed: source-file-stage, ask, ask-rail, ask-turn-failed, ask-thread, search, recipe, source-file, source-set, folder-contents, letters, letter-reader, notifications, letter-settings, shelf-create-sheet, shelf-backfill-review, then tool/web_frames.sh for the remaining STALE-WEB-FRAME pairs. A clean native build is ~16 min, past the hold test's 12-min load timeout, so `build/ios` has to be warm (`flutter build ios --simulator --debug -t integration_test/hold_screen_test.dart` + the defines) before the first shot.)

## F-35 · The summary regen constant, where the server sent a sentence
- status: done 2026-09-21
- screen: reader
- route: /reader/{docId}
- spec: spec/component-kit.md §14 · spec/decisions/ADR-070-failure-is-a-pattern.md
- web: src/pages/reader/SummaryPanel.jsx (`cooldownSentence`); tests/contract/cooldown-sentence.test.js
- flutter: lib/pages/reader/summary_panel.dart; lib/pages/study_page.dart; lib/state/org_notifier.dart; lib/services/api_service.dart; test/contract/cooldown_sentence_test.dart
- folds: 4.71.0 (§14's SUBSTITUTED shape); TODO B5 and B11 on the reference
- device_test: none
- shots: reader-manuscript
- extra_gates: python3 ../NoteLetter-contracts/harness/failure_pattern_check.py
- notes: Found by `failure_pattern_check.py`'s new **SUBSTITUTED** direction (B14), which
    reports it as `behind` against this queue's held pin rather than failing — it is
    correct at 4.4.0, because the reference carried the same two constants until B5.
    `_regenerate`'s `on ApiException catch (e)` renders
    `e.statusCode == 429 ? 'Just regenerated — give it a minute…' : 'The summary could
    not be regenerated just now…'`: it consults the rejection's SHAPE and throws away
    both its sentence and its `request_id`. The endpoint says the exact remaining wait
    (`Please wait 43 seconds before regenerating again.`), so the constant is wrong in
    both directions at once — it reads as a minute when three seconds remain and as a
    minute when fifty-five do — and it goes stale SILENTLY the day
    `_SUMMARY_REGEN_COOLDOWN_SECONDS` moves, because nothing ties the copy to it.
    Fix: mirror web's `cooldownSentence(e, fallback)` — parse the seconds out of the
    server's own sentence and render THAT, falling back to our words only when the
    endpoint sent none. Render the whole thing as `KitFailureInline` so the
    `request_id` has somewhere to go. The bare `catch (_)` arm below keeps its constant
    and is right to: a request that never reached a server has no sentence to quote,
    and that is the arm the direction deliberately does not read.
    Assert both: a 429 carrying `Please wait 43 seconds…` renders **43**, and the
    control direction — a 429 with no parsable seconds keeps the fallback, because a
    parser that invents a number would be worse than the constant it replaces.
    **Closed 2026-09-21 as TODO C11**, which is the same defect counted across the
    client rather than at one site: the reader's regenerate, the study card's
    Study now, and the organized-folder rescan (a **409** COOLDOWN, not a 429).
    Two departures from the note above, each because the note was written before
    the client's own half was understood. (1) The helper does **not** parse the
    seconds — it renders the server's sentence verbatim, exactly as the reference
    does. A parser is a second place for the copy to be wrong and it invents the
    one thing it cannot know; quoting gives you the 43 either way. (2) It is
    **not** `KitFailureInline` for the cooldown, and §14.2 is the reason: it draws
    no `request_id`, so routing a wait through it buys nothing the caption slot
    does not already do, and it paints a correct panel as a failure. The split
    is the reference's — 429 to the calm caption, everything else to §14.2 beside
    the button, with "The existing one is unchanged." as the caption under it.
    What this client needed FIRST is what the reference never did:
    `ApiException.message` held either the envelope's sentence or one of
    `_handle`'s own constants with nothing able to tell them apart, so
    `serverSentence` had to exist before a helper could mean anything — and every
    case in `test/contract/cooldown_sentence_test.dart` carries its CONTROL, the
    same status with no envelope, because a helper that renders `message`
    unconditionally passes the first half of all of them and puts "The server did
    not answer as expected (HTTP 429)." where a wait belongs. Mutation-proven both
    ways (fallback-always and flag-ignored each kill 4 of 10). The `reader-manuscript`
    pair is owed for the new §14.2 line and rides F-34, which already lists it.

## F-36 · The Plan row, and a refusal the server now sends
- status: done 2026-09-22
- screen: settings
- route: /settings
- spec: spec/screens/settings.md §Plan row · spec/api/plans.md · spec/decisions/ADR-113-a-plan-limit-is-enforced-where-the-resource-is-created.md · spec/component-kit.md §12
- web: src/api.js (`getPlanStatus`, `subscribeProfile`); src/shared/plan.js; src/shared/Notice.jsx; src/pages/SettingsView.jsx (`PlanRow`); tests/contract/plan-row.test.js
- flutter: lib/services/api_service.dart; lib/pages/settings_page.dart; lib/pages/reader/listen_panel.dart
- folds: 4.79.0 (fn_plan_status; 403 PLAN_LIMIT; `plan_limit_reached` — the chip landed on 2026-09-22 because 5f reads every client)
- device_test: Settings shows the Plan row with the endpoint's figures; a free account at a cap of 1 shows the §12 notice and its one action opens support
- shots: settings; reader-manuscript
- extra_gates: python3 ../NoteLetter-contracts/harness/failure_pattern_check.py; python3 ../NoteLetter-contracts/harness/stat_figure_check.py
- notes: Three touches, all measured. (1) `getPlanStatus()` — GET `fn_plan_status`, the ONLY
    source of a limit; never draw a count of the documents subscription (§12: a notice is
    measured, not decorative — and this client already shipped one fabricated figure, F-00).
    (2) The Plan row in Settings › Account, above Sign out: title `Free plan`/`Paid plan`,
    description `{documents} of {max} sources · {ingests} of {max} added this month ·
    resets {1 October}` (null = `Unlimited sources`; `Listen included` when
    `audio_narration`), and at a cap a §12 notice under the row with ONE action, **Ask
    about upgrading** → the support thread — there is no checkout. Mirror web's
    `planSummary()` word for word, including the unanswered state: title `Plan`, NO
    figures (ADR-109). Refetch after any `PLAN_LIMIT` rejection anywhere in the app
    (web dispatches an event from the one `call()` seam; `ApiService._handle` is this
    client's). (3) Every ingest surface and the Listen control already render the
    server's sentence as `KitFailureInline`; verify the 403 reaches them unaltered
    (`failure_pattern_check` SUBSTITUTED direction) and add nothing of our own. Do NOT hide
    Listen for a free account — a hidden control cannot say why.

## F-37 · The stale-pair debt — 7 screens the ritual has outrun
- status: done 2026-09-25
- screen: various
- route: various
- spec: ../NoteLetter-contracts/spec/decisions/ADR-041-composition-is-contract.md
- web: ../NoteLetter-web/screenshots
- flutter: screenshots
- folds: none — no contract version; this is the fidelity ritual catching up
- device_test: none
- shots: source-file-stage; onboarding; activity; library; ask-rail; ask-turn-failed; reader
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: screenshot_pair_check.py has been RED at HEAD since before F-36, with 28 STALE-PAIR findings across F-13, F-14, F-15 (activity + library), F-20, F-25 and F-26: each screen's code was committed after its pair was shot, so the frames show a screen that no longer exists. F-36 refreshed its own two (settings, reader-manuscript) and added nothing to the list. This item is the rest. A stale pair is not cosmetic debt — the pair IS the composition gate (ADR-041), and a frame older than its screen is the ritual not having run, whatever any task summary said. One shoot at a time: Xcode refuses concurrent builds and two overlapping tool/shots.sh runs both fail at the 12-minute test timeout with the real cause ('Xcode build failed due to concurrent builds') only visible if the script's output is NOT piped through tail.

## F-38 · Create a shelf from the rail, and fill it from the library
- status: done 2026-09-25
- screen: shelves
- route: /shelves
- spec: spec/screens/library.md §Creating a shelf §Backfill review; spec/component-kit.md §15 §14.1 §14.2; spec/api/tags.md §fn_suggest_shelf_backfill §fn_apply_shelf_backfill; spec/invariants.md §INV-29
- web: src/shared/ShelfForm.jsx; src/shell/AppShell.jsx; src/pages/ShelvesView.jsx; src/api.js
- flutter: lib/widgets/sidebar.dart; lib/pages/tags_page.dart; lib/pages/tags/shelf_page.dart; lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/pages/tags/shelf_sheet.dart (new)
- folds: 4.83.0 (ADR-117)
- device_test: none
- shots: shelf-create-sheet; shelf-backfill-review
- extra_gates: python3 ../NoteLetter-contracts/harness/client_timeout_check.py --target flutter
- notes: Contract 4.83.0. Three pieces, one form. (1) The rail's Shelves group gains a `+` ("New shelf") beside its label; `sidebar.dart` today shows only an "All shelves" item, so this is the first shelf control the rail has — do NOT also start listing every shelf there, that is a separate parity question. (2) One form for the rail sheet and `_NewShelfForm`: name, optional "What belongs here?" description (it is embedded, and it is what the backfill reads), the ten colours, and "Find sources that belong here" (checked; absent when no complete source exists). Write before you move: `createTag` resolves, THEN the sheet moves on. (3) The review: `suggestShelfBackfill` → reading (no figure — there is none until the answer) / proposal (all checked, title + reason, "File N sources") / nothing-fits sentence / §14.1 block with retry. INV-29: a failed suggest is NEVER the nothing-fits sentence. Apply holds the sheet open (barrier and back dismissal included) until `applyShelfBackfill` resolves; a refusal stays with the sentence. Also offered from `shelf_page.dart` as "Find sources for this shelf". Budgets: fn_suggest_shelf_backfill 120s, fn_apply_shelf_backfill 60s — add both to endpoint_budgets.dart or 5ak goes red. (2026-09-24: the two `Api` methods, their contract builders and both budgets landed early with F-40 to turn the suite green — what is left here is the UI.) (2026-09-25: the UI landed — rail `+`, one form for the sheet and the index card, the review, and the shelf page's offer; `test/kit/shelf_backfill_test.dart` gates it. OWED: the `shelf-create-sheet` + `shelf-backfill-review` pair — no emulator of ours was up. Shoot it, then `done`.) (2026-09-25, emulator up: `hold_screen_test.dart` gained the `shelf-create-sheet` and `shelf-backfill-review` HOLD_STATEs. The create-sheet frame is NOT clean — both KitTextFields draw the typed value and placeholder in the MONO face, where web's `.ss-input` is serif 15 (name) and the description is sans; a kit variant is owed (`KitTextField` is mono by design for data fields) — fix, then re-shoot. The backfill-review state failed twice: after tapping Create shelf the create seam never recorded a tag id against the 5599 shim (the frame showed the form, not the review); the state now asserts that instead of photographing the form. No frames committed.)

## F-39 · Reader — a Shelves row that edits the source's shelves
- status: done 2026-09-29
- screen: reader
- route: /reader/{id}
- spec: spec/screens/reader.md §Document shelves §Composition; spec/component-kit.md §20 §20.1 §14.2; spec/screens/library.md §Creating a shelf; spec/api/documents.md §fn_update_document
- web: src/pages/ReaderView.jsx; src/shared/ShelfChipEditor.jsx; src/shared/shelfPick.js; src/shared/ShelfForm.jsx; src/styles/app-source.css
- flutter: lib/pages/reader_page.dart; lib/widgets/kit/kit_shelf_chips.dart; lib/widgets/kit/kit.dart; lib/shared/shelf_pick.dart; lib/pages/tags/shelf_sheet.dart; lib/models/tag.dart; lib/models/document.dart
- folds: 4.83.0 (ADR-117); 4.104.0 (ADR-137)
- device_test: none
- shots: reader; reader-shelves; shelf-picker-search
- extra_gates: none
- notes: Contract 4.83.0 + 4.104.0. Under the reader's header, a mono caps `Shelves` label and a §20 Shelf chip editor over `doc.tag_ids`: × removes, the dashed `+ Shelf` (always present) opens the §20.1 Shelf picker — a serif search field, the shelves not on the document ranked by `shared/shelf_pick.dart` (the reference's `shelfPick.js` rule for rule), a create row always last. Each change is one `updateDocument(docId, tagIds: …)` built from the list last READ ± one id; the row is busy meanwhile, chips move only when the call resolves (`Document.withTagIds`), and a refusal is a dense §14.2 line beside the row. The create row opens `showShelfSheet` with the query as its name; the new id comes back once `fn_create_tag` resolved and the row files it — the reader stays. With backfill checked the review still follows in the sheet, as on the other two entry points, until F-72 (f) moves it to the background. Shown for every complete document. `chunk_shelves.dart` (the per-passage chips, not built here) will be the kit widget's second consumer.


## F-40 · Brand kinds + source links (4.84.0)
- status: done 2026-09-24
- screen: sources
- route: /sources
- spec: spec/component-kit.md §6.4.1 §6.4.3
- web: src/shared/FileBadge.jsx; src/pages/SourcesBrowse.jsx; src/pages/SearchView.jsx; src/pages/sources/ShelfView.jsx
- flutter: lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_source_link.dart (new); lib/pages/sources/browse_section.dart; lib/pages/search_page.dart; lib/pages/library_page.dart; lib/pages/tags/shelf_page.dart; lib/pages/search/result_card.dart; lib/pages/search/cohesive_column.dart; lib/pages/search/scripture_results.dart; lib/pages/chat_page.dart
- folds: 4.84.0 (ADR-118); 4.84.1 (Audio + Video chips on Sources)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/doc_kind_check.py
- notes: Contract 4.84.0. youtube/instagram/tiktok are their own kinds (plates YT/IG/TT; chips/groups YouTube/Instagram/TikTok after web). Every control that opens a source in the reader is a url_launcher `Link` (KitSourceLink) with the reader route, plain tap = in-app push, modifier tap = browser follows the anchor. Flutter has no shelf spine view, so the SHELF_KIND_LONG/SPINE_KIND_ICON/cloth rows have no consumer here.

## F-41 · Delete a shelf, then re-shelve its sources (4.85.0)
- status: done 2026-09-24
- screen: shelves
- route: /shelves/{id}
- spec: spec/screens/library.md §Deleting a shelf §Re-shelve review; spec/api/tags.md §fn_suggest_reshelve; spec/component-kit.md §15 §18 §14.1 §14.2; spec/invariants.md §INV-29
- web: src/pages/ShelvesView.jsx; src/shared/ShelfForm.jsx; src/api.js
- flutter: lib/pages/tags/shelf_page.dart; lib/pages/tags/reshelve_sheet.dart; lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/widgets/kit/kit_overlay.dart; lib/widgets/kit/kit_controls.dart; test/contract/api_requests_test.dart; test/kit/reshelve_review_test.dart
- folds: 4.85.0 (ADR-119)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/client_timeout_check.py; python3 ../NoteLetter-contracts/harness/failure_pattern_check.py; python3 ../NoteLetter-contracts/harness/confirm_check.py
- notes: Contract 4.85.0. Delete confirmation names sources on no other shelf and offers a checked-by-default re-shelve (only with >=1 complete source AND another shelf); ids captured before fn_delete_tag; the review opens on the root navigator after go('/shelves'). Review in slices of 150; three answers kept apart (failure / nothing fits / nowhere to go); apply per shelf sequentially, filed shelves skipped on retry; KitOverlaySheet gained `holding` to stay open while filing. KitCheckRow added to the kit (F-38's form is its second consumer).

## F-42 · Bare address is a link (4.86.0)
- status: done 2026-09-24
- screen: upload
- route: /upload
- spec: spec/api/ingest.md §Normalize, then detect
- web: src/api.js
- flutter: lib/state/upload_notifier.dart; test/contract/url_detection_test.dart
- folds: 4.86.0 (ADR-120)
- device_test: none
- shots: none
- extra_gates: none
- notes: normalizeUrl + detectUrlType top-level; shared table fixtures/url-detection/cases.json

## F-43 · Type the last pages from the kit — 9 kit-ok marks and 63 font-helper calls
- status: done 2026-10-01
- screen: various
- route: various
- spec: spec/component-kit.md §How to read a pattern; spec/design-tokens.md §Type
- web: src/styles/app-source.css; src/styles/app-kit.css; src/pages/reader/ListenPanel.jsx; src/pages/reader/SpeedReadPanel.jsx; src/pages/reader/HistoryPanel.jsx; src/pages/reader/ManuscriptPanel.jsx
- flutter: lib/widgets/kit/kit_text.dart; test/kit/no_inline_composition_test.dart; lib/pages/reader/listen_panel.dart; lib/pages/reader/speed_read_panel.dart; lib/pages/reader/history_panel.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader/reorganize_sheet.dart; lib/pages/library/document_detail_sheet.dart; lib/pages/chat_page.dart; lib/pages/search/scripture_results.dart; lib/pages/onboarding/wizard.dart; lib/pages/reader/reader_ui.dart; integration_test/hold_screen_test.dart; tool/seed_listen_audio.py
- folds: none — found by F-17's lint
- device_test: none
- shots: reader-manuscript; reader-speed-read; reader-listen; reader-history
- extra_gates: none
- notes: F-17's lint left 9 `kit-ok: F-43` sites whose metric no kit role names, and pinned 63 `AppTheme.serif(`/`AppTheme.mono(` calls across 18 page files (the same inline type in another spelling) in a ratchet that only falls. Drive both to zero, then delete the ratchet. The reader panels are not only respelled — they DRIFT from the reference: web `.player-eyebrow` and `.pf-label` are MONO caps 10 at `--fg-subtle` (Flutter: sans 10/600 at 0.8); `.player-times` and `.history-when` are mono 11 subtle (Flutter: sans 12 muted); `.history-label` is sans 14 (Flutter 13); the manuscript panel is built as `.ms-chunk-head`/`.ms-editbadge` where Flutter has its own toolbar and pill. Recompose against the web, then shoot the panels. Also: `ReaderUi`'s colour getters return raw `AppColors` steps, not `Tokens` — check each against its semantic token while there.

## F-44 · Sign in (F-44a) — `/signin`, the sign-up modal with its letter opt-in, and Continue with Google
- status: done 2026-09-26
- screen: signin
- route: /signin
- spec: spec/decisions/ADR-041-composition-is-contract.md; spec/component-kit.md §14.2
- web: src/pages/SignIn.jsx; src/styles/signin.css; src/shared/AuthModal.jsx; src/shared/authErrors.js; src/shared/usePendingLetterSetup.js; src/AuthContext.jsx
- flutter: lib/site/signin_page.dart (new); lib/site/auth_modal.dart (new); lib/site/site_sheet.dart (new); lib/services/auth_service.dart; lib/services/auth_errors.dart (new); lib/services/google_sign_in_setup.dart (new); lib/state/pending_letter_setup.dart (new); lib/state/auth_notifier.dart; lib/router.dart; lib/services/analytics.dart; lib/pages/landing_page.dart; lib/widgets/kit/kit_shell.dart; ios/Runner/Info.plist; pubspec.yaml; test/contract/signed_out_test.dart (new); test/contract/google_sign_in_setup_test.dart (new); test/contract/support_footer_test.dart; test/contract/analytics_test.dart; test/kit/no_inline_composition_test.dart; integration_test/hold_screen_test.dart; integration_test/device_run_test.dart
- folds: none — found by F-17's lint; the web's signed-out surfaces (2026-09-10) were UI-only, no contract version
- device_test: signs in through /signin against the emulator
- shots: signin; signin-fail
- extra_gates: none
- notes: Split from F-44 on Xavier's 2026-09-26 decisions: (1) the WEB REFERENCE BINDS for the signed-out pages — site furniture with their own sheet (`lib/site/site_sheet.dart`, the port of signin.css), not the app kit; tokens still bind; (2) BUILD Continue with Google. The landing is F-68 (F-44b). This item: `/signin` (router redirect for both signed-out routes, `analytics.dart` map, `support_footer_test` exempt), the AuthModal (Sign in | Subscribe, the letter opt-in stashed before the auth call and replayed by the signed-in app), "Forgot it?" that sends, the reference's error vocabulary gated against `authErrors.js` itself, and Google through `google_sign_in` (native) / Firebase's popup (web), guarded by `GoogleSignInSetup` whose flags a test reads from the native config. Android has no OAuth client (no SHA-1) so its button says "Google sign-in is not set up on this build." The old landing's Material dialog is deleted; its two doors open the modal.

## F-45 · Sources — an import-activity row breaks its title across two lines
- status: done 2026-10-12
- screen: sources
- route: /sources
- spec: spec/screens/sources.md; spec/component-kit.md §4.1
- web: src/pages/sources/CloudImportPanel.jsx
- flutter: lib/pages/sources_page.dart
- folds: none — found by F-23's folder-contents frame
- device_test: none
- shots: sources
- extra_gates: none
- notes: A `_JobRow` carrying two actions (View · Import again) plus its status glyph leaves the title so little width that `taxes.pdf` renders as `taxes.pd` / `f` and the subtitle as `Already im…` — on the seed's already-imported job, iPhone 17 Pro. Seen in screenshots/folder-contents.flutter.*.png (first shot, below the picker). The row is §4.1: when actions and title cannot share a line, the actions go under the title, never the title into a sliver.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): sources MATCH — the import row keeps its title on one line with its controls under it on a phone (folder-contents frame).

## F-46 · Notifications — a level label ellipsises in the channel cards
- status: done 2026-09-25
- screen: notifications
- route: /settings/notifications
- spec: spec/screens/notifications.md §The editor; spec/component-kit.md §6.8
- web: src/pages/NotificationSettings.jsx
- flutter: lib/widgets/kit/kit_controls.dart; lib/pages/notification_settings_page.dart
- folds: none — found by F-29's re-shoot
- device_test: none
- shots: notifications
- extra_gates: none
- notes: In each channel card's level track the third segment reads `Success…` on iPhone 17 Pro. The 2026-09-15 frame (b7e7b07) showed `Successes` whole; the track's segment labels were wrapped in `Flexible` + ellipsis at 4.84.0 (F-40, for a brand chip at a narrow bar), after that frame. Find which of the two changed the fit — the wrapper, or the card's inner width — and make four level labels fit a 390pt phone again (kit_controls.dart already carries a comment about exactly this label). A label the reader cannot read is a control that lies about what it selects.

## F-47 · Sources — choose sync folders (the folders-only picker)
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Sync control §Folder contents §Composition; spec/decisions/ADR-096-a-folder-you-cannot-see-into.md
- web: src/pages/sources/SyncSettingsPanel.jsx; src/pages/sources/CloudFilePicker.jsx; src/api.js
- flutter: lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/sync_folder_picker.dart (new); lib/widgets/kit/kit_controls.dart; test/contract/sync_folders_test.dart (new)
- folds: TODO CS-6 "Flutter cannot choose sync folders"
- device_test: none
- shots: sources
- extra_gates: none
- notes: §Sync control's folder scope had no control here: `folder_ids` could be set only from web, so the auto-sync warning and the Sync-now footnote both said "choose sync folders" on a screen that could not, and Sync now was disabled for good. Build the sync-folder chooser as web does: a *Sync folders* group in the panel (count n/20, chips with a remove affordance, *Choose folders…* / *Change folders…*) opening the picker in folders-only mode (≤20, one pool, `fn_list_cloud_files` filtered to folders, §Folder contents on every row, the ADR-026 §3 Notion advisory). Confirm and remove are `fn_sync_settings {folder_ids}` whole-list, and the chips render ONLY the returned `integration` — write before move. A refused save keeps the picker open with the sentence inline (§14.2). The seed has no cloud integration, so the `sources` pair cannot show the panel; the widget test is the gate.

## F-48 · Sources + reader — the cloud-sync tandem tasks of 4.89.0–4.92.0
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/api/cloud-storage.md §fn_disconnect_cloud_storage §fn_scan_cloud_folder §fn_import_from_cloud §fn_review_import_jobs §fn_retry_import_job; spec/api/organization.md §fn_execute_reorganization; spec/screens/sources.md §Cloud import §Trust & feedback §Sync control; spec/decisions/ADR-123-a-grant-is-reachable-only-by-its-own-flow.md; spec/decisions/ADR-124-an-import-job-is-owned-until-it-ends.md; spec/decisions/ADR-125-a-cloud-request-can-be-refused.md; spec/decisions/ADR-126-inv-13-on-the-providers-own-terms.md; spec/decisions/ADR-127-the-cloud-audits-leftovers.md; spec/component-kit.md §14.2 §18
- web: src/pages/SourcesBrowse.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/OrganizationPanel.jsx; src/pages/sources/SuggestionCard.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/pages/reader/ReorganizeSheet.jsx; tests/contract/cloud-sync-tandem.test.js
- flutter: lib/pages/sources_page.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/organization_settings_panel.dart; lib/pages/reader/reorganize_sheet.dart; lib/state/cloud_notifier.dart; lib/state/org_notifier.dart; lib/models/import_job.dart; lib/models/organization_suggestion.dart; lib/services/firestore_service.dart; lib/pages/sources/cloud_sync_copy.dart (new); test/contract/cloud_sync_tandem_test.dart (new)
- folds: 4.89.0; 4.90.0; 4.91.0; 4.92.0; 4.93.0; TODO CS-5 "Tandem UI owed to Flutter" (Notion advisory in the import picker); TODO CS-5 "preferred-hour select shows for daily/weekly only"
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/job_status_check.py — FLUTTER names 9 of 9
- notes: The Flutter tandem lines of CHANGELOG 4.89.0–4.92.0 (cloud sync audit CS-1..CS-4), web reference NoteLetter-web@12daabd. (1) Disconnect §18 confirm: only held and not-yet-downloaded imports stop, downloaded files finish (ADR-124 §7); Google/Dropbox are ASKED to revoke, OneDrive/Notion offer none and the copy says where the reader removes it (ADR-123 §5); after the call `revoked` true/false/null is said as a standing note, absent says nothing about the grant. (2) Import picker: a file the upload classifier refuses gets no checkbox and the classifier's sentence (ADR-125 §1; exportable and Notion exempt); the import's refusal (400 UNKNOWN_KEYS/caps, 403 PLAN_LIMIT) renders §14.2 inline in the picker, not a toast; the ADR-026 §3 Notion advisory as the sync picker has it. (3) Rows: `unsupported_type` a no-retry skip with its sentence; `pending`/`queued` drawn by name, not by the default branch. (4) Review queue: `skipped` names both causes (another device, or the service no longer connected). (5) Reorganize sheet: per-operation outcome from `executed_operations` incl. `created_without_artifact` + `artifact_reason`; a 409 shows the server's sentence with Analyze again and disables the stale Execute. (6) Suggestions: a readme card shows the proposed charter and says approving adopts it and writes nothing at the provider; approved ids are followed per document so a `failed` approval (the "interrupted" sentence) stays as §14.2 until cleared; a resolve refusal renders inline, not a toast. (7) Sync settings: the preferred-hour control hides on Hourly (the backend ignores it there, `_scheduled_sync_due`). `stalls_at` is backend-only and never rendered (data-model.md) — the hourly sweep turns a stalled row into `error`, which already offers Retry; `time_cap` needs nothing (clients key on `complete`; 4.93.0's 2.5 s per-call bound only makes it reachable). (8) 4.93.0 (ADR-127): `fn_organization_settings` refusals (now 400 `UNKNOWN_KEYS`) render §14.2 in the Organization panel, not a toast — the client sends only the three keys; `fn_update_from_source`'s 500 "Could not start the update. Try again." already reaches the reader's inline slot (`source_freshness.dart`, `e.message`). The seed has no cloud integration, so the widget test is the gate; the `sources` pair is owed to an emulator.

## F-49 · Exportable rows by mime (4.94.0), the re-shelve lede, and mono field tracking
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/api/cloud-storage.md; spec/api/uploads.md; spec/screens/sources.md; spec/screens/library.md; spec/component-kit.md
- web: src/pages/sources/CloudFilePicker.jsx; src/uploadTypes.js; src/shared/ShelfForm.jsx; src/styles/app-responsive.css
- flutter: lib/pages/sources_page.dart; lib/pages/sources/cloud_sync_copy.dart; lib/shared/upload_types.dart; lib/models/cloud_file.dart; lib/pages/tags/reshelve_sheet.dart; lib/widgets/kit/kit_controls.dart; test/contract/cloud_sync_tandem_test.dart; test/kit/reshelve_review_test.dart; test/kit/kit_text_field_test.dart
- folds: 4.94.0
- device_test: none
- shots: letter-settings
- extra_gates: python3 ../NoteLetter-contracts/harness/upload_set_check.py
- notes: (1) 4.94.0 Flutter tandem, web reference NoteLetter-web@42160c1: the import picker's exportable subtitle reads `mimeType` (cloudExportLabel) — PDF / PowerPoint / the pre-4.94.0 native Doc mime as PDF, an unmapped mime no label; `uploadRejection` refuses every `application/vnd.google-apps.*` mime with the generic unsupported-type sentence (the Slides deck's native mime matched `contains presentation`). The sync-folder picker is folders-only and draws no export label. (2) reshelve_sheet.dart (F-41) drew web's `.bf-lede` in the italic `KitText.lede`; it moves to F-38's `KitText.reviewLede`/`reviewEm` with the counts and shelf name emphasised as ShelfForm.jsx does. (3) Mono KitTextField took Material bodyLarge's 0.5 letter-spacing (F-38 pinned serif/sans only); pinned to 0 so a data field draws at web `.timefield`'s width — shot on letter-settings, whose Send-to field is the first mono field above any fold. (2026-09-25: landed. The Send-to value measures 177.0pt against web's 177.0 CSS px (was 186.3pt). The re-shelve review has NO pair: no HOLD_STATE, no web frame in theme-shots.mjs, and every state but the transient read needs fn_suggest_reshelve's model call, which the 5599 shim answers only under NL_DEV_FAKES=1 — the lede is gated by reshelve_review_test's span assertion instead.)

## F-50 · Sources — the add panel as the reference composes it: Library, What can I add?, processing under the zone
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Composition; spec/component-kit.md §3 §7 §15
- web: src/pages/SourcesBrowse.jsx; src/overlays/SourcesInfoSheet.jsx; src/styles/app-sources-browse.css; src/styles/app-responsive.css
- flutter: lib/pages/sources_page.dart; lib/pages/sources/browse_section.dart; lib/pages/sources/sources_info_sheet.dart (new); lib/widgets/file_uploader.dart; lib/widgets/kit/kit_headers.dart; lib/widgets/kit/kit_empty.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Four drifts the pair showed beside the web phone frame. (1) Title `Your *library*` → `Library` (§Composition Header; the rail already calls it Library). (2) The add section's header carries the trailing `What can I add?` help trigger — SectionHeader gains `actionIcon` (web `.si-open`: sans 12.5/500 at --fg-muted, 13px glyph, no underline) — opening a §15 sheet with SourcesInfoSheet.jsx's content word for word. (3) `Being processed · N` moved out of the In-your-library section to directly under the zone and link row (§Composition: 'the processing rows sit directly under it'); the note counts stalled rows as needing attention and says 'passages appear as each finishes' otherwise, as the reference does. (4) The drop zone lost its format pills and the accent upload glyph: KitDropZone now draws `.empty-dropzone` (1.5px dashed, --r-lg, 44/28 padding, glyph at --fg-subtle, serif 22/600, SANS 14 --fg-muted help); pills stay optional (Library's empty state keeps them). The link row is always visible (field + Add link, disabled on an empty field) rather than behind a 'Paste a link' ghost; the field no longer draws the theme's pill outline inside its box. Image-set capture stays as a ghost under the row — a device capability the web has no surface for. Web draws the processing rows as cards with a status pill; the spec says a processing row keeps §4.1 anatomy, so this client keeps the row (spec/web disagreement, reported, not resolved here).

## F-51 · Letter settings — the reference's config form: caps group labels and the tinted schedule card
- status: done 2026-09-25
- screen: letter-settings
- route: /letters/settings
- spec: spec/screens/letters.md; spec/decisions/ADR-041-composition-is-contract.md
- web: src/pages/LetterSettings.jsx; src/pages/letters/ReadingsLetter.jsx; src/styles/app-responsive.css; src/styles/app-scripture.css
- flutter: lib/pages/letter_settings_page.dart; lib/widgets/kit/kit_config.dart (new); lib/widgets/kit/kit_controls.dart; lib/pages/tags/reshelve_sheet.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: letter-settings
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The screen was a stack of Settings' icon-plate setting rows under an eyebrow title; the reference is `.letter-config`: back control, a serif 24/600 HEADING with the italic lede, then groups — each a mono caps label (`SCHEDULED DELIVERY`, `SEND TO`, `HOW OFTEN`, `ARRIVES AT`, …) over its control, a hairline --rule between them — opened by a tinted `.cfg-rl` toggle card (accent-chip ground and edge when on, sunken when off; the card writes before it moves, ADR-022). Groups are the existing KitFieldGroup (notification settings and onboarding already use it; it gains the `.cfg-second` variant for the readings letter). New kit parts in kit_config.dart: KitConfigHeading, KitConfigToggle, KitConfigHint (the `.cfg-hint`/`.cfg-note` sentence under an empty Send-to), KitConfigField + KitConfigStatic (the readings letter's `.rl-field`s). KitSelect's value was mono 15 (the text field's data face); web's `.timefield select` is sans 14 and that is now the default — the re-shelve picker passes KitFieldFace.serif for `.ss-input`. No spec section names this form (letters.md §Composition covers the Letters screen only) — reported. Still different, booked separately: the live letter preview + Send now under the form, and `Draw from` shelves. `Your librarian` stays here (the reference edits purposeText from Settings).

## F-52 · Support — the quiet empty state and the accent send control
- status: done 2026-09-25
- screen: support
- route: /support
- spec: spec/screens/support.md §Composition; spec/component-kit.md §7 §10
- web: src/pages/SupportView.jsx; src/styles/app-support.css; src/styles/app-kit.css
- flutter: lib/pages/support_page.dart; lib/widgets/kit/kit_empty.dart; lib/widgets/kit/kit_composer.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: support
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Re-shooting the stale pair showed two drifts. (1) The empty thread drew §7's chrome tile and 28px letterpressed title; the reference's `.sup-empty` is a 52px --accent-soft disc with a solid --accent-chip-border edge and the glyph at --seal, over serif 22/30 and a 16/24 lede — KitEmptyState gains `quiet`. (2) §10's send control drew a grey --surface-raised disc with a north-east arrow while it could not fire; the reference's is always --accent with IcoSend's RIGHT arrow, at 0.45 opacity when disabled. Fixed in KitComposerDock, so Ask's composer moves with it (its pairs are re-shot in the same pass).

## F-53 · Letter settings — the live letter preview and Draw from
- status: done 2026-09-26
- screen: letter-settings
- route: /letters/settings
- spec: spec/screens/letters.md §The letter-settings preview; spec/decisions/ADR-131-the-reference-implementation-is-what-the-spec-describes.md; spec/api/newsletter.md
- web: src/pages/LetterSettings.jsx; src/pages/letters/LetterHost.jsx; src/pages/letters/letterActions.js; src/api.js
- flutter: lib/pages/letter_settings_page.dart; lib/widgets/kit/kit_config.dart; lib/models/newsletter_settings.dart; test/contract/letter_draw_from_test.dart; lib/pages/letters/letter_preview.dart (new); lib/pages/letters/letter_host.dart (new); lib/pages/letters/letter_reader.dart; lib/models/newsletter.dart; lib/services/firestore_service.dart; lib/state/newsletter_notifier.dart; test/contract/letter_preview_test.dart (new); integration_test/hold_screen_test.dart
- folds: 4.98.0 (tandem 3a: the preview); none else — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: letter-settings; letter-reader; letters
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Left over after the form was recomposed (F-51). The reference puts the letter itself beside (desktop) or under (phone) the form: `.letter-preview-pane` — today's letter (getNewsletter) rendered through LetterDocument with the first `count` passages, a §14.2 line if it could not be read, and an actions row (`N passages · ~N+1 min read`, Copy, Send now with its sent/failed sentence). This client has no preview and no Send now on this screen. Also `Draw from`: a shelf list with switches whose titles save as `topicFilters` (titles, not ids) in the same PUT; SettingsNotifier.saveLetterSettings already accepts topicFilters. Build both from the kit (§11 Letter sheet for the preview).
  2026-09-25: not reached this sitting (disk, see F-61). Unchanged.
  2026-09-25 (Draw from landed, item still open): NewsletterSettings reads `topicFilters`; the page holds
  the selection as shelf TITLES and saves `topicFiltersFor(shelves, selected)` (titles in shelf order, a
  vanished shelf's title dropped, as web's id-mapped selection drops it) in the same PUT. `LetterDrawFrom`
  is a KitFieldGroup (`Draw from`, note `N|all shelves`) over one new kit row per shelf, KitSourceToggle
  (`.src-toggle`: 8px shelf dot, sans 14 name, KitSwitch, --rule between rows) in kit_config.dart. Below the
  fold on the phone frame; letter_draw_from_test.dart (4) is the proof. The PREVIEW PANE is not built,
  deliberately — the reference's is broken: it renders `passagesToSections(letter.passages)` and
  `letter.editorial_note`, two fields no current contract record carries, so web's own frame draws "0
  passages · 0 sources" with an empty body over a letter that holds 3; and its Copy button has no onClick.
  Porting it would port both defects. Decide the preview's source (the letter's `html_body`, as the Letters
  reader draws it, cannot be cut to `count` passages) on the web side first.
  2026-09-26 (preview landed, 4.98.0 / ADR-131 answered the question above): the pane is the stored
  letter — FirestoreService.getLatestLetter pages `generated_at desc` ten at a time to the newest
  Newsletter.isBuiltLetter (daily, `html_body`, not empty/error; NewsletterNotifier.latest now uses the
  same predicate, as web's card and preview share one), rendered by LetterHost — the Letters reader's
  daily branch, extracted so both surfaces use one host (bare on a letterhead, §11 sheet otherwise, never
  re-sanitised). Figures via letterFigures from `chunk_ids` only; Newsletter.chunkIdsKnown tells an
  absent field from an empty one, and absent draws NO figure (spec + web; the sheet's seal count too).
  None built says "No letter has been built yet."; a failed read is §14.2 "Today's letter could not be
  read — …". Copy writes `html_body` (Flutter's Clipboard takes one flavour, so the HTML — web's
  single-flavour branch), says Copied, a refusal in §14.2 under the row. Send now sits beside it with
  web's sentence, disabled with no address. Beside the form above 1024, under it below. HOLD_STATE
  `letter-preview` scrolls to the pane for looking (the web frame is the page top). The web
  letter-settings frame is still pre-596edef (v4.97.0 f0143dc footer, "0 passages · 0 sources").

## F-54 · Library — the setup checklist, the search field row, and the spine views
- status: done 2026-09-25
- screen: library
- route: /
- spec: spec/screens/library.md §Composition; spec/screens/onboarding.md; spec/component-kit.md §2.1 §5.3
- web: src/pages/LibraryHome.jsx; src/styles/app-kit.css
- flutter: lib/pages/library_page.dart; lib/state/newsletter_notifier.dart; lib/models/newsletter.dart; lib/widgets/kit/kit_cards.dart; test/contract/library_hero_test.dart; lib/widgets/kit/kit_headers.dart; lib/widgets/kit/kit_library_head.dart (new); lib/widgets/kit/kit_shelf.dart; lib/state/chat_notifier.dart; test/contract/library_setup_test.dart (new); test/kit/library_head_test.dart (new); test/contract/documents_failure_test.dart; integration_test/hold_screen_test.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: library
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The 2026-09-25 re-shoot beside the web phone frame. Under the chapter opening the reference draws (1) the setup checklist card — a chevron, a progress bar, `4 of 5 set up`, the next step as a pill (`Ask your library a question`) and Hide; this client has none; (2) a full-width SEARCH FIELD (`Search your library by meaning…`, italic serif placeholder) and, under it on a phone, a full-width `+ Add a source` primary — this client puts a ghost `Search` and an `Add a source` button in the header's actions slot instead; (3) `Recently read` with a list/shelf (spine) view toggle, and `Shelves` with a shelf/card toggle — this client has the list and the card grid only. The Today's-letter hero is absent here for a data reason, not a composition one: web's getNewsletter takes the newest record of any status/kind, this client takes the latest `sent` daily letter with an `html_body`, and the seed's two letters are pre-2.0.0 records with `html` only — so web says 'Today's letter is ready — 0 passages' where this client says the library is being read. Decide which is right before building the hero's appearance rule. Read LibraryHome.jsx for the checklist's steps and its persistence before building it.
  2026-09-25: the hero question is answered on the reference side — NoteLetter-web ef14f8a "Library hero:
  Today's letter is the newest DAILY letter, never a readings letter"; read it before choosing the rule.
  2026-09-25: not reached this sitting (disk, see F-61). The hero rule to mirror (web ef14f8a):
  getNewsletter pages `/newsletters` by generated_at desc, 10 at a time, and takes the first record
  whose `kind != 'scripture'` CLIENT-SIDE (a `!=` query would move the first orderBy onto `kind` and
  drop the kindless pre-2.24.0 records), paging on past a full page of readings letters; 404 when
  none. It does NOT require `status == sent` or an `html_body` — this client's
  `letters.latest?.status == 'sent'` gate is the other half of the difference. The standfirst takes
  the lede by web 5d6fe8d's shared letterLede (the `data-nl-lede` rule), never a slice of
  `text_body`. tool/seed_letters.py is now loaded in the emulator (4 letters incl. a readings one).
  2026-09-25 (hero landed, item still open): `NewsletterNotifier.todaysLetter` is the newest
  daily record of ANY status (`history.first` — newest first, `kind != 'scripture'` client-side),
  replacing `latest` gated on `status == 'sent'`; it reads load()'s 30-record window where web pages
  on past 10 readings letters. The standfirst is `Newsletter.ledeOf(140)` (the shared `data-nl-lede`
  rule, 120 kept for the Letters rows) with web's fallback sentence; the masthead number is the
  subject; the cells are Passages (`chunk_ids`) and Sent (only on a `sent` letter; no min-read cell,
  as before); Schedule goes to `/letters/settings` (it went to `/settings`); a failed read says
  "Today's letter could not be read." with §14.2, never "Tomorrow's letter…". KitHeroCard's masthead
  is now web's `.masthead` (title nowrap, the number the item that wraps) — the seed's subject
  overflowed the phone row by 44px. Still owed here: (1) the setup checklist, (2) the search field
  row with the full-width Add a source, (3) the list/shelf spine toggles (build ShelfView once in the
  kit with F-65).
  2026-09-25 (done): (1) the checklist is KitSetupChecklist (kit_library_head.dart, a part of
  kit_headers.dart): the compact strip under the chapter opening (caret, 90px bar, `N of M set up`,
  the remaining steps as pills, Hide; the pills take their own line on a phone and the label wraps
  at 320), and the full card on the empty Library. Steps as web's buildSteps — account (done), a
  first source (any document), a volume on a shelf, the letter set up (`enabled || deliveryTime` on
  a settings doc that exists; SettingsNotifier.loadAll per visit), a first question (`nl-onboard-
  asked`, set by ChatNotifier.ask on a RECORDED turn, never a refusal). Hidden (`nl-onboard-
  dismissed`) or complete, it is gone; `nl-onboard-expanded` remembers the disclosure, default open
  for the card and closed for the strip; web's established-reader guard (preDone) is kept. (2)
  KitLibraryActions: the italic-serif search field (a button to /search; the Vector pill wide only)
  and the accent Add a source (to /sources), stacked full width on a phone — the ghost Search and Add
  a source left the header's actions slot. Stacked widgets add margins CSS collapses, so the strip
  has no bottom margin and the row no bottom one (22 and 32 between, as web). (3) SectionHeader gains
  a `tools` slot (`.lib-section-tools`): Recently read is list (5 rows) or F-65's KitShelfView (12,
  bare), Shelves is F-65's named KitShelfUnit ledges (320–440 wide, one to a line on a phone, one
  pulled book across all of them) or the existing card grid — kept under `nl-recent-view` /
  `nl-shelves-view`, shelf the default. KitShelfUnit/KitSourceCard counts now pluralise (`1 passage`);
  web's named head says `1 passages` — a web defect, not ported. Frames: after the ask shots the
  simulator's prefs hold `nl-onboard-asked`, so a later library frame there draws no strip until
  the key is cleared.
## F-55 · Reader — the manuscript counts words from the text, not the passage html, and flattens a table
- status: done 2026-09-25
- screen: reader-manuscript
- route: /reader/{docId}
- spec: spec/screens/reader.md §Composition; spec/component-kit.md §17
- web: src/pages/reader/ManuscriptPanel.jsx; src/pages/ReaderView.jsx
- flutter: lib/pages/reader/manuscript_panel.dart; lib/pages/reader_page.dart; lib/pages/reader/dwell.dart; lib/pages/reader/content_form_action.dart (new); lib/theme/app_theme.dart; test/contract/dwell_test.dart; test/contract/content_form_test.dart (new)
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: reader-manuscript; reader
- extra_gates: none
- notes: The 2026-09-25 re-shoot beside the web phone frame (web frame 2026-09-18). (1) On the seed's Quarterly Tax Summary the manuscript header says `2 passages · 12 words` where web says `9 words`: web counts `htmlWords(c.html)` (ManuscriptPanel.jsx:521/801/858), this client `_wordCount(c.text)` (manuscript_panel.dart:311/524/585) — and the same count drives the dwell timer (`dwellFor(wordsIn(c.text))`, :485, vs web :521), so the read-tracking dwell differs too, not only the label. Decide the unit from the reference and port it, with a test on a passage whose text and html disagree. (2) The table passage renders as `QuarterInvoice total` / `Q2 $1,200` — cells run together with no separator — where web draws a ruled table; the image passage draws its caption as body text. (3) The reader frame lacks web's `Treat as…` action and the `LISTEN —` stat; the manuscript frame's tab indicator stays on Summary while the manuscript panel is in view. Composition of the panel itself (drop cap, `.ms-chunk-head`) is F-43's.

## F-56 · Shelf settings panel — the colour group drops whole under its label at phone width
- status: done 2026-09-25
- screen: shelf-color-picker
- route: /shelves/seed-tag-recipes
- spec: spec/screens/library.md; spec/component-kit.md §6
- web: src/styles/app-shelves.css; src/pages/ShelvesView.jsx
- flutter: lib/widgets/kit/kit_controls.dart; lib/pages/tags/shelf_page.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: shelf-color-picker
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The 2026-09-25 re-shoot beside the web phone frame. Web's `.ss-row` is `display:flex; flex-wrap:wrap; gap:16px; row-gap:8px` with a 64px `.ss-label`, so on a phone the ten-swatch group (10 x 24 + 9 x 8 = 312px) does not fit beside the label and wraps WHOLE onto its own line under COLOR, one row of ten. KitPanelRow is a Row with a fixed label column and an Expanded child, so the swatches wrap 7 + 3 inside the column instead. Fix inside the kit (a KitPanelRow that drops its child below the label when the child's natural width does not fit — flex-wrap, not a per-screen branch). kit_controls.dart is listed by F-08, F-12, F-47, F-49, F-51 and F-46, so the change re-stales those pairs: re-shoot shelves, shelf-color-picker, search, sources and letter-settings in the same pass. Found while disk allowed only the pairs already owed.

## F-57 · Shell — the brand mark and wordmark, and the phone app bar's search
- status: done 2026-09-25
- screen: library
- route: /
- spec: spec/component-kit.md §1.2
- web: src/shell/AppShell.jsx; src/styles/app-kit.css
- flutter: lib/widgets/kit/kit_shell.dart; lib/widgets/app_layout.dart; lib/widgets/sidebar.dart; lib/pages/onboarding/wizard.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: library; settings; onboarding
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Seen in every phone frame of the 2026-09-25 re-shoot. §1.2's brand lockup is `mark + serif wordmark`: the reference draws its quill mark and a SMALL-CAPS wordmark (NOTELETTER with large initials) in the app bar, the rail and the onboarding head; this client draws Material's `Icons.edit_note` and a plain serif `NoteLetter` in all three (KitBrand callers, plus `_sealMark` in kit_letter.dart and KitMark on the onboarding welcome and the Settings feature card). The reference's phone app bar also carries a trailing search control; this client's has none. (Web's phone frames also show a bottom tab bar — §1.1 allows 'a drawer or tab bar', so the drawer is conformant and is not part of this item.) A shell kit change re-stales every pair — do it at the head of a re-shoot pass, not in the middle of one.

## F-58 · Reader — on a phone the reader draws no app bar, where the reference keeps the shell's header
- status: done 2026-09-25
- screen: reader
- route: /reader/{docId}
- spec: spec/component-kit.md §1.1; spec/screens/reader.md §Composition
- web: src/App.jsx; src/shell/AppShell.jsx; src/styles/app-source.css
- flutter: lib/pages/reader_page.dart; lib/widgets/kit/kit_overlay.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: reader; reader-manuscript; recipe; source-file; source-set
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The 2026-09-25 re-shoot beside reader.web.phone.png: web renders the reader INSIDE the shell, so a phone keeps `.app-mobile-header` (menu · quill lockup · search) above the reader's own back control; this client mounts the reader outside AppLayout (CLAUDE.md: INV-22's footer wraps it from support_shell instead), so the phone frame opens on a bare status bar and `< Library`. Decide whether the reader joins AppLayout's compact branch (keeping its own full-bleed body and INV-22 placement) or records a deviation — the recipe/source-file/source-set frames show the same bare top.
  2026-09-25 (not landed): the approach was written and analyze-clean — `ReaderPage.build` returns
  `LayoutBuilder(maxWidth >= AppSpacing.compactWidth ? page : AppLayout(child: page))`, done in the
  page rather than `router.dart` because the route table is listed by 9 done pairs (ask ×3, letters,
  letter-reader, letter-settings, onboarding, shelf-color-picker, shelves) and the page by 3; SupportShell
  and INV-22 untouched, wide unchanged. Reverted unshot: the NoteLetter Firestore emulator died of
  `OutOfMemoryError: Java heap space` at 15:53 (back channel >10,000 pending listen messages) and every
  frame after it is the onboarding gate over an unreadable library. Owes: reader, reader-manuscript,
  recipe, source-file, source-set, library, shelves re-shot on a restarted emulator.

## F-59 · §4.1 source row — the reference hides the row's count at phone width; this client stacks it as a third line
- status: done 2026-09-25
- screen: library
- route: /
- spec: spec/component-kit.md §4.1
- web: src/styles/app-responsive.css; src/pages/LibraryHome.jsx
- flutter: lib/widgets/kit/kit_rows.dart; CLAUDE.md
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: library; sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: app-responsive.css at max-width 680px: `.src-row .count { display: none; }` — the subtitle already says `N passages`, so the figure is dropped. KitSourceRow instead moves the count under the subtitle below 768 (a recorded CLAUDE.md §Composition deviation), which on the Library frame reads `Stories · 1 passage` over a lone `1`. Either retire the deviation (hide the count below the breakpoint, as the reference does) or re-argue it; the deviation list is word-capped, so a change there is a swap.

## F-60 · Readings day — a passage card is the reference's `.sc-p`: a small badge, a sans title, a mono score
- status: done 2026-09-25
- screen: scripture-day
- route: /letters
- spec: spec/screens/letters.md; spec/component-kit.md §4
- web: src/pages/letters/ScriptureDayView.jsx; src/styles/app-scripture.css
- flutter: lib/pages/letters/scripture_day_page.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: scripture-day
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The 2026-09-25 frame beside scripture-day.web.phone.png. `.sc-p` is --surface with --shadow-1 and NO border, padding 14/16; its head `.sc-p-h` is a content-sized FileBadge (mono 9, no fixed box), the title in SANS 13/600 and the score mono 10.5 --fg-subtle pushed right; the text serif 15/25 in --fg-lede. This client's _DayPassage draws a bordered card at 24/22, a 36x44 row badge, the title in serif h4 and body at reading size — so each passage reads as a source row rather than a quoted passage. Needs a badge size the kit does not have (a content-sized chip), which is a kit_controls change and re-stales its pairs; do it at the head of a re-shoot pass. The web frame's eyebrow is --fg-subtle where this client's is accent — check which is current before changing it.

## F-61 · Sources — the import picker is the reference's flat panel: a Root crumb, open folder rows, the counter top-right, Import N items + Cancel
- status: done 2026-09-25
- screen: folder-contents
- route: /sources
- spec: spec/screens/sources.md; spec/component-kit.md §6
- web: src/pages/sources/CloudImportPanel.jsx; src/styles/app-sources-browse.css
- flutter: lib/pages/sources_page.dart; lib/state/cloud_notifier.dart; test/contract/cloud_sync_tandem_test.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: folder-contents
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The 2026-09-25 frame beside folder-contents.web.phone.png. Web's picker is one sunken panel: an underlined `Root` breadcrumb with the `0/20 folders · 0/50 files` counter in italic serif at its right, folder rows that are a checkbox + underlined name + chevron with NO box around them, the scan disclosure indented under its rule, and `Import 0 items` (primary, enabled at zero, naming the count) beside a `Cancel` text button. This client titles the card `Import from Google Drive` with a close control, sets `ROOT` as a caps label, boxes each folder row, puts the counter at the foot beside a disabled `Import selected`. The data and the disclosure are right; the composition is not. Read CloudImportPanel.jsx before rebuilding — the enabled-at-zero button may be a web defect, not a rule.
  2026-09-25 (not started — disk): the host was at 1.6 GB free with 9.6 GB of swap, and this item's
  sources_page.dart change re-stales five pairs (sources, proc-affordances, source-file-stage,
  folder-contents under NL_DEV_FAKES, letter-settings via F-49). Read, ready to build: the reference
  is CloudFilePicker.jsx (not CloudImportPanel.jsx) — a --bg-2 panel, r-lg, padding 14; crumbs are
  `.set-link` buttons (`Root` › …) with the counter as `.proc-note` at the right of the same row;
  folder rows are checkbox + `.set-link` name + chevron + the FolderContents disclosure, no box; the
  foot is `proc-retry` `Import N item(s)` + `proc-remove` Cancel. The button is NOT enabled at zero:
  `disabled={saving || !canConfirm}` — the frame's proc-retry only draws disabled faintly. There is
  no title row and no close control; Cancel is the way out.
  2026-09-25 (done): `_PickerPanel` is now CloudFilePicker's import mode — a --surface-raised (--bg-2)
  panel, r-lg, padding 14, border; the crumbs are KitSettingLink (`.set-link`, `Root` › …) with the
  counter as a KitProcNote at the right of the same row; one failure slot at the top (import refusal
  or listing failure, as web's single `error`); a cap note IN the panel in the reference's words
  (`N-file limit reached — import these first, then pick more.`, the notifier's strings, which the
  toast used to carry); rows unboxed — checkbox + KitSettingLink name + chevron + FolderContents for
  a folder, checkbox + chip plate + name + size/export note for a file; `Nothing here.`/`Loading…` as
  proc-notes; `Load more…` a bare link; the foot `Import N item(s)` (primary, disabled at zero,
  `Queuing…` while it sends) + ghost Cancel. Title row and close control gone. The sync picker
  (sync_folder_picker.dart) keeps its boxed rows and caps crumbs — the same drift, not this item.

## F-62 · Sources — Update from source on a kept refresh row (4.96.0 cloud tandem)
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: CHANGELOG.md; spec/screens/sources.md; spec/decisions/ADR-129-a-reentry-claims-before-it-enqueues.md
- web: src/pages/sources/CloudImportPanel.jsx
- flutter: lib/models/import_job.dart; lib/pages/sources_page.dart; test/contract/cloud_sync_tandem_test.dart
- folds: 4.96.0
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: CHANGELOG 4.96.0 tandem 3, reference NoteLetter-web@f0143dc (`ImportJobRow`). `ImportJob.canUpdateFromSource` = `skipped` + `skip_reason` `document_complete | document_unchanged` + `document_id` set; the row draws a ghost **Update from source** → `CloudNotifier.updateFromSource(documentId)`, busy `Queuing…`, a refusal as §14.2 `KitFailureInline` under the row — the same shape as Retry. `canRetry` stays false for both reasons. No client parses the sentence: a gone-file row still gets the control. The seed has no cloud import rows, so the widget tests are the proof, not the pair.

## F-63 · Update from source — the §Supersession confirm on the Sources row and the reader banner
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/screens/reader.md §Supersession confirm §Source freshness; spec/screens/sources.md §Trust & feedback; spec/component-kit.md §18; spec/decisions/ADR-092-a-confirmation-that-cannot-report-a-refusal.md
- web: src/pages/ReaderView.jsx; src/pages/sources/CloudImportPanel.jsx
- flutter: lib/pages/reader/supersession_confirm.dart (new); lib/pages/reader/content_form_action.dart; lib/pages/reader/source_freshness.dart; lib/pages/sources_page.dart; test/contract/supersession_confirm_test.dart (new); test/contract/cloud_sync_tandem_test.dart; test/contract/sources_harness.dart
- folds: none — booked 2026-09-25 from the umbrella's confirm gap
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: reader.md §Supersession confirm names Update from source first among the operations that re-derive content: the client MUST confirm (a §18 Confirmation, danger variant) when any chunk has `user_edited` or the document is in a study program, naming both consequences. F-62's row button and the reader's freshness banner both sent `fn_update_from_source` on the first tap. The web reference skips it too (ReaderView.jsx `update()`, CloudImportPanel.jsx `updateRow`) — the spec is normative here and web owes the same fix. Both facts are three-valued: a read that failed says 'could not check' and still confirms; only two definite noes skip it, and then a refusal stays §14.2 on the row/banner as before. The row holds no chunks, so it reads them quietly (no doc_opened, INV-03). No seed state reaches either surface (no cloud rows, no newer-at-provider document), so the widget tests are the proof, not a pair.

## F-64 · Phone widths — web 9a84288's tandem: the letters card and the library hero wrap their actions, the schedule wraps, Order by stays whole
- status: done 2026-09-25
- screen: letters
- route: /letters
- spec: spec/component-kit.md §5.3 §6.6 §6.8; spec/screens/letters.md §Composition; spec/screens/library.md §Composition
- web: src/styles/app-responsive.css; src/styles/app-sources-browse.css; src/styles/app-kit.css
- flutter: lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_cards.dart; lib/pages/letters_page.dart; test/kit/phone_width_test.dart (new)
- folds: none — web 9a84288 (gate:phone), booked 2026-09-25
- device_test: none
- shots: letters; library
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Web 9a84288 fixed four phone overflows gate:phone found once it stopped excusing `.view`. Per surface here: (1) Sources `.browse-controls` wraps (sort, then the view toggle on its own line; `.ltabs { width: 100% }` at <=680 already put the track under `Order by`) — KitControlBar's compact tail was already a Wrap and KitSegmented fills its own line, so Order by already matched; this client has NO list/cards/shelf view toggle, booked separately. (2) Letters `.next-letter` at 320: `minmax(0, 1fr)`, `.nl-status { white-space: normal }`, `.nl-actions { flex-wrap: wrap } .btn { flex: 1; justify-content: center }` — the schedule Text lost its 2-line ellipsis cap, and the actions (a content-width Wrap) are now KitActionFlow(grow) with centred labels (KitButton `center`): Send now + Preview share line one, Settings drops alone and full width at 390 and 320. (3) Library `.letter-hero .actions { flex-direction: row; flex-wrap: wrap }` — KitHeroCard's compact actions were a STRETCHED column (every action its own full-width bar); now a KitActionFlow row at natural widths, the second action dropping at 320. (4) `.seg { flex-wrap: wrap }` — component-kit §6.8 says nothing about a track that cannot fit one line; this client implements web's behaviour (the last option drops to its own line only when the labels cannot share one), which KitSegmented has done since F-46. (5) `.link-add input { min-width: 0 }` — the Flutter field is already Expanded. A Flutter Column cannot hold min-content open the way a bare `1fr` track does, so (2)/(3)'s grid fix has no Flutter analogue. KitActionFlow is a new kit render object (flex-wrap with optional grow and the min-content floor) in kit_controls.dart, not a new file, to keep kit.dart's nine listed pairs fresh. Proof is test/kit/phone_width_test.dart at 390 and 320 with the bundled faces; the pair (402pt simulator) shows the 390-class layout.

## F-65 · Sources — the list / cards / shelf view toggle beside Order by
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Composition; spec/component-kit.md §6.6
- web: src/pages/SourcesBrowse.jsx; src/styles/app-sources-browse.css
- flutter: lib/pages/sources/browse_section.dart; lib/pages/sources/shelf_books.dart (new); lib/widgets/kit/kit_shelf.dart (new); lib/widgets/kit/kit_rows.dart; lib/widgets/kit/kit_controls.dart; lib/shared/local_flags.dart; test/contract/sources_view_toggle_test.dart (new); test/kit/shelf_test.dart (new); integration_test/hold_screen_test.dart
- folds: none — found while folding web 9a84288 (F-64)
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Web's `.browse-controls` holds `Order by` + the `.ltabs` sort AND a `.view-toggle` (32x30 `.vt-btn` icon segments: IcoRows list, IcoGrid cards, IcoShelf shelf; the choice persisted by `pickView`) that switches the volume list between rows, a `.src-cards` two-column card grid, and ShelfView (spines). This client's browse section has the sort only and always draws rows. On a phone the toggle wraps to its own line (9a84288). Read SourcesBrowse.jsx `view`/`pickView`/ShelfView and the card anatomy before building; F-54's Library spine view is the same ShelfView — build the spine once, in the kit, and let both screens compose it.
  2026-09-25 (done): the toggle is KitSegmented with `KitSegment.icon` cells (`.vt-btn` 32x30, the
  same sunken track and raised selection; a glyph-only track never fills a phone line), after the
  sort in KitControlBar's tail — its own line on a phone, as 9a84288. Kept per viewer under
  `nl-sources-view` in LocalFlags (write before move; an unknown stored value reads as the shelf);
  the shelf is the default, as web's. Views: §4.1 rows; KitSourceCardGrid of KitSourceCard
  (`.src-card`: 30x38 plate — a new KitBadgeSize.card — kind in mono caps from KIND_NAME, the unread
  dot, date; serif 17 title, 2 lines; shelf; ruled foot with shelf and the count in accent-text;
  2 columns at <=720, 1 at <=460); KitShelfView. The shelf is ONE kit build in
  lib/widgets/kit/kit_shelf.dart, a part of kit_rows.dart (so kit.dart's twelve listed pairs stay
  fresh): KitBook (the kit holds no model; pages map through pages/sources/shelf_books.dart),
  KitBookSpine (cloth per kind — component-kit §6.4.1's table, raw steps that do not flip — band in
  the first shelf's colour, the title set vertically, the kind's mark, the unread dot; width on
  web's log scale of words, height from web's id hash), KitBookCover, KitBookDetail (cover, kind ·
  added, title, host, Words/Passages/Shelf/Added/Views stats, note, Open in reader + Find a passage;
  stacks under the compact width), KitShelfUnit (eyebrow head, or the named plate/serif/mono head F-54
  needs; spines on a 244 ledge; openId owned by the host) and KitShelfView (web's ordering, and
  SHELF_GROUPS under Type). Not ported: web's hover popover `.bpop` — no hover on touch; the hint
  drops its hover clause. KitControlBar now also stacks when the BAR is under 720 wide (web's
  `.browse-controls` line), since the wider tail left the chips 3px on an 800 window. Two frame
  defects found and fixed by looking: BoxDecoration ignores `color` under a gradient, so the first
  spines had no cloth (the shading is now blended onto it); the phone cover split "Cornbread,"
  mid-word (the title now steps down until its longest word fits) and clipped the detail's close.
  LocalFlags also gains the three `nl-onboard-*` keys F-54's checklist reads, so it is touched once.
  HOLD_STATEs `sources-browse` / `sources-book` shoot the section and a pulled book for looking only;
  `query` now settles before typing. Re-shot and read: sources, proc-affordances, source-file-stage,
  letters, library, notifications, settings, shelves, shelf-color-picker, letter-settings, search
  (NL_DEV_FAKES).

## F-66 · Owed confirms — Retry / Index it anyway through the §Supersession confirm; Start a new unit holds its §18 panel
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/screens/reader.md §Supersession confirm; spec/component-kit.md §18; spec/decisions/ADR-092-a-confirmation-that-cannot-report-a-refusal.md
- web: src/pages/SourcesBrowse.jsx; src/shared/SupersessionConfirm.jsx; src/pages/study/ProgramEditor.jsx
- flutter: lib/pages/sources/browse_section.dart; lib/pages/study/program_editor.dart; test/contract/owed_confirms_test.dart (new)
- folds: none — confirm_check (NoteLetter-contracts@7635d61) owed list; web 71987f6
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/confirm_check.py; python3 ../NoteLetter-contracts/harness/confirm_mutations.py
- notes: reader.md §Supersession confirm names "retry of an errored doc": an errored document CAN hold edited passages (a failed RE-extraction keeps them) and be in a study program, so `_runPrimary`'s Retry and Index it anyway both run through SupersessionConfirm.run (F-63's runner) with web 71987f6's words — `Retry “{title}”?` / `Index “{title}” anyway?`, the reference's two lead sentences, `Retry and replace` / `Index it anyway` on the danger control; two definite noes send straight through, a refusal then stays §14.2 under the row. The row's labels never claimed work behind the confirm here, so web's `askingFor` defect has no counterpart. `ProcessingRow` is public with two check seams for the tests. Start a new unit (`UnitPanel`, now public) closed its §18 on `null` and called afterwards (§18 rule 1): the call is now the panel's `onConfirm`, a refusal in its slot, and the row's own failure slot went with the old path; the toast's unit number is taken before the refresh. manuscript_panel.dart's close-first confirm is the leave guard, which calls nothing (the act IS the navigation) and is annotated `confirm-ok:` exactly as web ReaderView's — no change. The contracts owed list lost both Flutter entries (NoteLetter-contracts 54e6738). Neither UnitPanel nor manuscript is declared in confirm_required.json; declaring the unit panel is a contracts change this item was not allowed to make.

## F-67 · Sync folder picker — the same flat panel as the import picker: `.set-link` crumbs, unboxed rows, the counter beside the crumbs
- status: done 2026-09-25
- screen: sources
- route: /sources
- spec: spec/screens/sources.md; spec/component-kit.md §6
- web: src/pages/sources/CloudFilePicker.jsx
- flutter: lib/pages/sources/sync_folder_picker.dart; lib/pages/sources/cloud_picker.dart (new); lib/pages/sources_page.dart; lib/pages/sources/sync_settings_panel.dart; test/contract/sync_folders_test.dart; integration_test/hold_screen_test.dart
- folds: none — found while building F-61
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The sync chooser is CloudFilePicker in `folders` mode on web — the same component F-61 rebuilt the import picker to match. sync_folder_picker.dart still draws caps crumbs (`ROOT`), the counter as its own line under them, and each folder as a boxed KitSourceRow with a folder icon. Recompose as F-61's `_PickerPanel` (KitSettingLink crumbs with the counter as a KitProcNote on the same row; checkbox + KitSettingLink name + chevron + FolderContents, unboxed; `Sync N folders` + Cancel). Consider lifting F-61's row and crumb row into one shared picker body so the two cannot drift again. No seed state opens the sync picker; widget tests (sync_folders_test.dart) are the proof.
  2026-09-25 (done): F-61's composition lifted into lib/pages/sources/cloud_picker.dart (CloudPickerPanel,
  CloudPickerCrumbs, CloudPickerCheck, CloudPickerFolderRow, CloudPickerLoadMore, CloudPickerFoot); the
  import picker and the sync chooser both compose from it, so neither can drift alone. The sync chooser:
  `Root` as a KitSettingLink with `N/20 folders selected` on the crumb row, unboxed checkbox + link +
  chevron + FolderContents rows, `Sync N folders` + Cancel; the cap note is web f050fe2's folders-mode
  sentence (`N-folder limit reached — untick one to choose another.`); `allowEmpty` (web 12daabd) lets an
  emptied selection save when folders were saved before; a save that throws leaves `Could not save these
  folders.`. HOLD_STATE `sync-folders` (shim under NL_DEV_FAKES) shoots it for looking only — web has no
  frame of the state, so none is checked in.

## F-68 · The signed-out landing (F-44b) — LandingActual, an edition of the letter
- status: done 2026-09-26
- screen: landing-actual
- route: /landing
- spec: spec/decisions/ADR-041-composition-is-contract.md
- web: src/pages/LandingActual.jsx; src/styles/landing-actual.css
- flutter: lib/site/landing_page.dart (new); lib/site/landing_bits.dart (new); lib/pages/landing_page.dart; test/contract/landing_test.dart (new); test/kit/no_inline_composition_test.dart; integration_test/hold_screen_test.dart; integration_test/device_run_test.dart
- folds: none — F-44's second half; the landing redesign (cb6ee41) was UI-only, no contract version
- device_test: signs in and reaches the library
- shots: landing-actual
- extra_gates: none
- notes: Split from F-44 (2026-09-26). Web binds: site furniture composed against LandingActual.jsx 903 + landing-actual.css 507, tokens only, in lib/site/ beside the sign-in sheet. Masthead with the computed dateline (Vol. roman(year-2025) · No. day-of-year), the retyping hero, the letter stack (one letter at phone width), ticker, ten departments (the scroll-lit brief, Fig. 1 drawn as a CustomPainter), the contents rail above 980, colophon, the plum footer (its one /signin link), the drawer and the theme toggle. The 7 remaining `kit-ok: F-44` marks and the file's 4 ratchet entries leave with the old file.

## F-69 · The 4.98.0 composition tandem — reader badge, processing cards, Ask citation pill, Study's failed read, letter rows, sync type spelling
- status: done 2026-09-26
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-131-the-reference-implementation-is-what-the-spec-describes.md; spec/screens/reader.md §Composition; spec/screens/sources.md §Composition; spec/screens/ask.md §Composition; spec/screens/study.md §Composition; spec/screens/letters.md §Composition; spec/component-kit.md §6.4
- web: src/pages/SourcesBrowse.jsx; src/styles/app-sources-browse.css; src/pages/AskView.jsx; src/styles/app-kit.css; src/pages/StudyView.jsx; src/pages/LettersView.jsx; src/styles/app-responsive.css; src/pages/sources/SyncSettingsPanel.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/reader/ListenPanel.jsx; src/styles/app-source.css
- flutter: lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_proc.dart (new); lib/widgets/kit/kit_cards.dart; lib/widgets/kit/kit_letter.dart; lib/pages/sources/browse_section.dart; lib/pages/chat_page.dart; lib/pages/study_page.dart; lib/pages/letters_page.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/folder_contents.dart; lib/pages/reader/listen_panel.dart; lib/pages/reader/manuscript_panel.dart; test/contract/composition_4_98_test.dart (new); test/contract/cloud_sync_audit_test.dart; test/kit/goldens/controls.light.png; test/kit/goldens/controls.dark.png
- folds: 4.98.0 (tandem 3c 3d 3e 3f 3g)
- device_test: none
- shots: reader; sources; proc-affordances; ask-thread; letters; study
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: CHANGELOG 4.98.0 Flutter tandem (c)-(g), plus web 13c910c's two touches. (a) is F-53; (b) is F-44/F-68, done.
  2026-09-26 (done): (c) KitBadgeSize.header is 34x42 / mono 9 (was 40x48 / 10, from the dead `.reader-head`
  class); the reader's chapter-opening lead takes it, no deviation to record. (d) Being processed: one
  KitProcCard per document (kit_proc.dart, a part of kit_controls.dart): 32x40 badge (new KitBadgeSize.proc),
  serif 15/500 title, mono 11 `{type} · {n} passages`, and KitProcPill toned per web procPill (work + spinner,
  wait, done, fail + alert glyph, hold); the stage is the pill's, never the subtitle's (skipped reads Error, as
  web). Beneath it KitProcActive (the 3px bar, the source affordance, Cancel) or KitProcAttention (ruled strip,
  the italic serif detail or web's DEFAULT_PROC_ERROR, §14.2 retry refusal, the one primary + Remove + the
  source affordance). The processing row's overflow menu is gone (web has none); Cancel/Remove are the same
  §18 confirms, lifted to confirmCancel/confirmRemove. The pill drops under the title at 768. (e) Ask citation:
  index, a content-sized File badge (web's bare `.filebadge`), a WRAPPING title over the excerpt, and a trailing
  Open / host column (host capped at 160, KitPassageAction.maxWidth); the radius stays pillR(44) = 22 at every
  width (web: --r-xl 20 at <=680, a true pill wider — this client's single cap is the deviation, since a
  wrapped citation is 2+ lines everywhere here). (f) Study: a failed programs read keeps the chapter opening
  (folio `…`) with §14.1 where the list goes; sentences now web's (`Your study programs could not be read.`,
  `Your recent sessions could not be read.`). (g) Letters archive: KitLetterRowList / KitLetterRow in
  kit_letter.dart (`.archive-list` / `.letter-row`): № mono 12, serif 16/600 subject over italic serif 13 lede,
  mono 11 figures, sans 13 date, mono 9 pill badge (settled = positive chip, open = accent soft); figures and
  date hide below 768; `generating` rows say web's BUILDING_LEDE. Sync settings: type chips and rule rows use
  cloudTypeLabel (PDF / Word / PowerPoint / Notion page), web's. 13c910c: the Listen play button's Play glyph
  sits 2px right while it shows (Material's triangle is already 1.5px right of centre; the sum matches web's
  nudged IcoPlay); the manuscript's edit-mode word count was already --fg-muted and now takes web's mono 11
  face. Frames re-shot and read: proc-affordances, sources, reader, study, letters, ask-thread, ask-rail, ask
  (ask pairs against a separate NL_DEV_FAKES shim on :5598, stopped after). The failed-study and letter-row
  states have no seed frame; composition_4_98_test.dart is the proof. Still different on the reader frame,
  not this item: the Shelves row (F-39, open) and the Listen stat.

## F-70 · The 4.99.0 tandem — the Library hero names its letter's day; the Ask citation radius follows the reference
- status: done 2026-09-28
- screen: library
- route: /
- spec: spec/decisions/ADR-132-the-hero-names-the-day-of-its-letter.md; spec/screens/library.md §The letter; spec/screens/ask.md §Composition
- web: src/pages/LibraryHome.jsx; src/api.js; src/styles/app-kit.css
- flutter: lib/pages/library_page.dart; lib/state/newsletter_notifier.dart; lib/pages/chat_page.dart; test/contract/library_hero_test.dart; test/contract/composition_4_99_test.dart (new)
- folds: 4.99.0 (tandem 3)
- device_test: none
- shots: library; ask-thread
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: CHANGELOG 4.99.0 Flutter tandem. (a) The hero reads NewsletterNotifier.latest (the newest BUILT daily letter, web getLatestLetter); delete todaysLetter. (b) library.md §The letter: header Today's letter / Latest letter by whether generated_at is on the device's calendar day; standfirst `Today's letter is ready — {n} passages from your library.` or `Your latest letter is from {Weekday, Month D} — {n} passages from your library.`, the count clause dropped when chunk_ids is absent (chunkIdsKnown); failure `Your latest letter could not be read.`; Sent already only for status == sent. (c) Ask citation: AppRadius.xl below compactWidth, a full pill above it (was pillR(44) = 22 at every width — F-69's recorded single-cap deviation, now superseded by ask.md 4.99.0).

## F-71 · Library hero — the masthead is web's versal A LETTER, and the stat cluster carries Min read
- status: done 2026-10-12
- screen: library
- route: /
- spec: spec/screens/library.md §Composition; spec/screens/letters.md §The letter-settings preview; spec/component-kit.md §5.3
- web: src/pages/LibraryHome.jsx; src/styles/app-kit.css
- flutter: lib/pages/library_page.dart
- folds: none
- device_test: none
- shots: library
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Seen on F-70's frames (2026-09-28), not F-70's subject. (1) The hero masthead: web draws `.masthead-title versal` — small caps with versal initials (`A LETTER`); this client draws 'A *Letter*' with the accent italic. (2) The stat cluster: web draws Passages · Min read (`~{n+1}`, dash without chunk_ids) · Sent; this client drops Min read on a comment calling it arithmetic, while letters.md specifies `{n} passages · ~{n+1} min read` on the same record. Decide by the reference; KitStat cannot yet carry an unmeasured figure (stat_figure_check CARRIES-ABSENCE).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): library MATCH — the masthead is the versal A LETTER; Passages · ~4 Min read · Sent.

## F-72 · For your review — the inbox (4.100.0 tandem)
- status: done 2026-10-07
- screen: review
- route: /review
- spec: spec/screens/review.md; spec/decisions/ADR-135-for-your-review-is-one-inbox.md; spec/invariants.md §INV-30; spec/component-kit.md §1.2 attention count; spec/api/documents.md §fn_review_documents
- web: src/pages/ReviewView.jsx; src/shared/useReviewInbox.js; src/shell/AppShell.jsx; src/api.js; src/styles/app-kit.css
- flutter: lib/pages/review_page.dart (new); lib/state/review_inbox.dart (new); lib/services/api.dart; lib/router.dart; lib/widgets/nav_drawer.dart; lib/services/endpoint_budgets.dart; test/contract/api_requests_test.dart
- folds: 4.100.0 (tandem 3); 4.101.0 (tandem 3 — the Proposals and Running sections, §22 Review row, the stored re-shelve review, delete via fn_request_task, the `deleting` filter on tags); 4.102.0 (tandem 3 — backfill and split as task kinds: the stored backfill and split reviews, Run again beside an apply_error); 4.103.0 (tandem 3 — syllabus_plan and reorg_plan as task kinds: the syllabus editor and the reorganize sheet over a stored proposal)
- device_test: signs in, opens For your review from the drawer, dismisses a failed source
- shots: review
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: CHANGELOG 4.100.0 + 4.101.0 Flutter tandems. (a) Api.reviewDocuments(docIds) → `fn_review_documents` {docIds, action:'dismiss'} (fixture documents:review-*); budget above the 60s host. (b) Three subscriptions per screens/review.md §Data — held imports (status == awaiting_review, limit 500, NOT the 50-newest window), pending suggestions, and documents status in [error, skipped, processing] limit 500 — and ONE notifier that yields {needs, count, measured} to both the drawer item and the page (INV-30: a failed subscription makes the count unmeasured, drawn as the dash, never a partial count). (c) The page reuses this client's processing card (+ Dismiss, Dismiss all with the §18 confirm), the import review rows and the suggestion cards with their outcome rows; sections in the order the spec gives, absent when empty, §7 empty state when all are. (d) Drawer: For your review under Home with the §1.2 attention count; the app bar's menu button carries the dot while it is above zero. (e) 4.101.0: `fn_request_task` / `fn_resolve_task` builders (add api/tasks to api_requests_test's suites), the background_tasks subscription in the same notifier, Proposals + Running (§22 Review row), the stored re-shelve review, the shelf delete through the task, and hiding a `deleting` shelf in the tags stream. (f) 4.102.0: "Find sources for this shelf", the create form's backfill and "Split this shelf" become `fn_request_task` {kind: shelf_backfill | shelf_split} + a local toast; the backfill review gains a stored mode (apply = `fn_resolve_task` {documentIds}, `skipped` said before Done) and the split review applies `{parts: [{index, title, description}]}` — never document ids — saying `skipped.moved_away` and drawing a 409 STALE inline; a task row with `apply_error` carries Run again (`retry`). Until this lands the held client keeps `fn_suggest_shelf_backfill`/`fn_suggest_shelf_split`, which stay served. (g) 4.103.0: "Read the syllabus" and the reader's Reorganize become `fn_request_task` {kind: syllabus_plan {programId, documentId} | reorg_plan {documentId}} + a local toast; For your review opens the syllabus plan editor over `result` (apply = `fn_resolve_task` {units, assessments} — the reader's edited plan) and the reorganize sheet over `result` (apply = {operations}; a 409 STALE offers Run again = `retry`); an apply answering 409 SUBJECT_GONE has already dismissed the task. The held client keeps `fn_suggest_syllabus_plan`/`fn_analyze_reorganization`, which stay served.
  2026-10-02: built 538cd99 (a, b), 8eb9b57 (c, d, e: screen, rail count, §22 rows, stored re-shelve), 72c0d80 (e: delete via task, `deleting` filter), 1b004dc (f), 6cc0dc3 (g); analyze clean, contract+kit 1098 green, confirm_check PASS; device run + the review pair owed — no emulator this wave.
  2026-10-05: the review pair MATCHES and is committed (a8e9ec6). (f) was incomplete: the Shelves index's New shelf card still opened the live in-sheet backfill review — fixed f03961c. The device test exists (711f7a8) and has never run: the device run was stopped by the disk (under 5 GB). Still owed: the device run.
  2026-10-07: the whole device run over bed2e81 (alt-port emulator, scratch boot, NL_DEV_FAKES shim, iPhone 17 Pro simulator): this item's test PASSES — "signs in, opens For your review from the drawer, dismisses a failed source" — 22 of 25 green; the three reds are F-77's and F-44a's, not this item's (burn-down evidence/flutter/device-run-2026-10-07.log). The review pair matched at a8e9ec6. Done.

## F-73 · Reader — Delete a source; the re-shelve review's shelf select (4.105.0)
- status: done 2026-10-12
- screen: reader
- route: /reader/{id}
- spec: spec/screens/reader.md §Deleting a source §Composition; spec/component-kit.md §18 §20.2; spec/screens/library.md §Re-shelve review; spec/api/documents.md §fn_delete_document
- web: src/pages/ReaderView.jsx; src/shared/ShelfSelect.jsx; src/shared/ShelfForm.jsx
- flutter: lib/pages/reader_page.dart; lib/widgets/kit/kit_shelf_chips.dart; lib/pages/tags/reshelve_sheet.dart; lib/services/api.dart
- folds: 4.105.0 (ADR-138)
- device_test: none
- shots: reader
- extra_gates: confirm_check.py
- notes: Contract 4.105.0. (a) The reader's last header action is a ghost *Delete* with a trash glyph, for complete/error/skipped documents, opening a §18 KitConfirm: `Delete “{title}”?`, the body naming what is lost (its {n} passages, original file, reading history, its shelves by name) and what is not (letters received, other sources, the shelves; a study program drops its passages at its next session), *Keep it* / *Delete source* (danger). One `Api.deleteDocument` (add it: `fn_delete_document {docId}`); the panel holds until it resolves, a refusal answers inside it, success pops back to the reader's origin. (b) §20.2 Shelf select as a kit widget beside §20 in `kit_shelf_chips.dart` — a trigger (dot + title, or the none label in --fg-muted, chevron) opening the §20.1 panel over every shelf, the chosen one checked, a none row first while nothing is typed, the create row last — and `reshelve_sheet.dart`'s `KitSelect` becomes it (none = Leave unshelved; the create row opens showShelfSheet and the new id becomes the row's choice).
  2026-10-02: built 4790210 (analyze clean, contract+kit 1026 green, confirm_check PASS); device run + the reader pair owed — no emulator this wave.
  2026-10-05: the reader pair was re-shot from 0d329b8; this item's own parts (the ghost Delete with its trash glyph, §20.2's select) are on screen, but the pair does NOT match for other reasons, booked as F-77 — so it is not committed and this stays open until F-77's reader frame matches.
  2026-10-07: re-shot over 5b0b73e. Delete and its trash glyph, the §20.2 select (reader-shelves, shelf-picker-search — those two pairs MATCH and are committed) are right; the reader pair still does not match, for F-77 (2) and (3) only — not committed, still open.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): reader — Delete with its trash glyph and the §20.2 select (reader-shelves, shelf-picker-search) are right; the one difference, web's new Priority row under Shelves, is booked on F-99 (BLOCKED, Xavier).

## F-74 · Reader — the manuscript's reading controls: Aa, the reading-progress rule, Pick up where you left off, the drop cap
- status: done 2026-10-12
- screen: reader-manuscript
- route: /reader/{id}
- spec: spec/screens/reader.md §Composition §Sections; spec/component-kit.md §5.2
- web: src/pages/reader/ManuscriptPanel.jsx; src/styles/app-source.css
- flutter: lib/pages/reader/manuscript_panel.dart
- folds: none — left by F-43's recomposition
- device_test: none
- shots: reader-manuscript
- extra_gates: none
- notes: F-43 recomposed the panel bar, the sheet, its type, the edit-mode chunk head, the split control and the foot. Four reference parts were left for this item, each a behaviour rather than a type role: (1) `TypeControls` — the `Aa` popover beside Edit text (`.ms-type`, useReaderPrefs: size, leading, family, measure as `--ms-*` vars on the sheet); (2) `.ms-progress` — the accent reading-progress rule above the sheet, a MEASURED fraction of the sheet scrolled (only measured numbers on screen); (3) `.ms-resume` — `You stopped about N% of the way through.` with Pick up where you left off / Start over; (4) the drop cap on the first passage's first paragraph (`::first-letter`, serif 58/0.86/600 at --accent-text) — flutter_html has no first-letter, so it needs a decision on how the first paragraph is drawn. Read ManuscriptPanel.jsx for where (2) and (3) take their numbers before building either.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): reader-manuscript MATCH — Aa, the progress rule, the drop cap at the body's optical size, the framed image with its alt.

## F-75 · Search — the cohesive column's passage type and source title follow the reference
- status: done 2026-10-12
- screen: search
- route: /search
- spec: spec/screens/search.md §Composition; spec/component-kit.md §5.2
- web: src/pages/SearchView.jsx; src/styles/app-kit.css
- flutter: lib/pages/search/cohesive_column.dart
- folds: none — found by F-43's respelling
- device_test: none
- shots: search
- extra_gates: none
- notes: F-43 respelled these sites into KitText roles without moving a pixel, and found four drifts it did not fix: (1) the cohesive passage body is `.passage .quote` serif 18/30 on the reference, 17/28 here; (2) its `Html` branch sets no family, so stored html renders in the UI SANS while the no-html branch is serif — the manuscript had the same defect (fixed in F-43 by `fontFamily: AppTheme.fontSerif` on the body Style); (3) `.cohesive-passage .pmeta .srctitle` is 14/500, 15/1.2/500 here; (4) `.cohesive-note` is at --fg-subtle, --fg-muted here. Needs a frame of the COHESIVE mode — the `search` pair's query does not reach it.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): search MATCH — the passage text on one collapsed line, the source title in the serif.

## F-76 · Letters and Sources — the reader bar's Copy and Open in email; readings rows are letter rows; the source control's glyph
- status: done 2026-10-07
- screen: letter-reader
- route: /letters
- spec: spec/screens/letters.md §Composition; spec/screens/sources.md §Document processing; spec/component-kit.md §1.3
- web: src/pages/letters/LetterBarActions.jsx; src/pages/letters/letterActions.js; src/pages/letters/ReadingsLetter.jsx; src/pages/SourcesBrowse.jsx; src/styles/app-scripture.css
- flutter: lib/pages/letters/letter_reader.dart; lib/pages/letters/readings_letter.dart; lib/widgets/kit/kit_letter.dart; lib/pages/sources/source_sheet.dart; lib/pages/sources/browse_section.dart
- folds: TODO CS-6 "Owed on Flutter: Letters reader bar has no Copy / Open in email (d153111); processing card source link has no file/external glyph; readings-letter archive rows still old style"
- device_test: none
- shots: letter-reader; proc-affordances; letters
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Found owed inside TODO CS-6's 4.98.0 Letter-settings line (web d153111, b51f414 — the latter already closed by F-70's NewsletterNotifier.latest). (1) The reader bar (`.lr-bar`): Copy copies html_body (disabled with no body; Copied; §14.2 under the bar on refusal), Open in email is `mailto:?subject=` (a handoff no mail app takes is said, never swallowed); below ~400px the two keep their glyphs and drop their labels — the reference's own `.lr-actions .btn span { display: none }`, which reaches nothing on web because its labels are not spans. (2) The readings archive is `.archive-list` of `.letter-row.rl-row`: KitLetterRow gains `kind` (`.lr-kind`, the book glyph + READINGS on the accent chip) and `refs` (`.lr-refs`, mono 10.5 at --fg-subtle, wrapping below the compact width). (3) The processing card's source control carries web SourceAffordance's glyph: open_in_new / layers / file.
  2026-10-05: built 06bdce6. proc-affordances MATCHES (committed a8e9ec6). letter-reader and letters did not: a 24pt band of app ground above a letterhead letter, the card's figures at --fg-subtle 14 instead of `.nl-meta`, and the readings card's zone as a city — all three fixed in f417c96, and their re-shoot was stopped by the disk. Still owed: the letter-reader and letters pairs from f417c96 or later.
  2026-10-07: re-shot over HEAD and compared to web 5413658's phone frames. letter-reader: f417c96's call holds — the ground above the paper is the LETTER's own `padding:34px 20px` (#FAFAF7), not app ground, on both sides. What did NOT match was scale: KitLetterPaper laid the 640px paper out at 640 and fitted it by scaling the page (~0.6: title 27 on one line where web wraps it at 38, 12pt margins vs 20). Fixed by web's host rule (`[data-nl-letterhead]>table{table-layout:fixed}`, app-kit.css) plus, because WKWebView did not reflow with that rule alone, the paper held to its cell (`width:100%; max-width:640px`, !important over the inline width) — the letter now reflows at its true sizes. Residual, web-side: `.letter-sheet` inherits the app's 24px body line box into the letter, so web spaces the folio's two lines 24 apart where the letter itself (and this host, and a mail client) sets them at `normal`. letters: the card head read ~14% tight — its lines now take web's inherited 24px line box, `.nl-status`'s 13, the masthead's 12 row gap, `.nl-lede`'s 9/13, the phone grid's 18 and `padding: 20px`; every gap within 2pt of the reference. proc-affordances re-shot and still matches. All three pairs committed.

## F-77 · Reader — the parts the 2026-10-05 pairs found: LISTEN stat, a link web has not, the rail's ground, History lands short
- status: done 2026-10-12
- screen: reader
- route: /reader/{id}
- spec: spec/screens/reader.md §Composition §Sections; spec/component-kit.md §19 §5.4 §15.2
- web: src/pages/ReaderView.jsx; src/styles/app-source.css; src/pages/reader/ManuscriptPanel.jsx
- flutter: lib/pages/reader_page.dart; lib/widgets/kit/kit_section_rail.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader/speed_read_panel.dart; lib/widgets/kit/kit_recipe.dart; lib/widgets/kit/kit_overlay.dart
- folds: none — found by the 2026-10-05 re-shoot (burn-down report, flutter)
- device_test: none
- shots: reader; reader-history; reader-manuscript; reader-speed-read; reader-shelves; shelf-picker-search; recipe; source-set
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Each read off a pair re-shot from 0d329b8, against web code. (1) The stat cluster has no `— LISTEN` cell; web always draws it (ReaderView.jsx ~692); left out on purpose at reader_page.dart ~929-961 but recorded nowhere (F-55 note 3 booked it). (2) A "How these passages reached you" link under Mark finished (reader_page.dart ~1077) that web does not draw at rest (its toggle is Reading stats inside the Aa popover — F-74). (3) The §19 rail paints --surface full width (kit_section_rail.dart ~73, reader_page.dart ~557): web `.src-rail` is --bg with a right-edge fade on a phone. (4) History lands short: the rail reports Original and the list starts half way down; web gives the last section `min-height: calc(100vh - var(--src-rail-h) - 72px)` (app-source.css ~100); here only a trailing SizedBox. (5) No rule between sections (`.src-section + .src-section`). (6) Glyphs: Ask forum_outlined vs IcoChat, Reorganize account_tree vs IcoText, rail auto_awesome/notes/history vs IcoSparkle/IcoText/IcoClock. (7) Manuscript: the passage mark takes 26pt inside the column (web `.ms-mark` sits in the sheet padding, left -26/-14); table cells 19 vs `.ms-body table` 15. (8) Speed read: the hint row under the stage is absent and recorded nowhere (`Hold to pause & rest` applies on touch). (9) Recipe: ingredients 16 vs 15, a rule under every item (web rules between), caption 14 --fg-subtle vs 12 --fg-muted. (10) Image set: the 3:4 aspect applies to the whole cell, caption included (kit_overlay.dart ~503); `.srcset-frame` is 3:4. Reader pair is also F-73's: F-73's own parts (ghost Delete with trash, §20.2 select) were seen present.
  2026-10-06: (1) and (6) built — LISTEN is drawn as §8's unmeasured dash (the reference reads `audio_seconds`, which nothing writes, so it is the dash there too), and Ask / Reorganize / the Manuscript and History jumps take IcoChat / IcoText / IcoClock as this client draws them elsewhere (chat_bubble_outline, title, schedule). Not re-shot. (2) is blocked on F-74: the reference's only stats toggle is Reading stats inside the Aa popover, which this client does not have, so removing the link would leave the opt-in unreachable. (3) is a page-ground question, not the rail's: the reader sits outside AppLayout on the support shell's --surface, and the rail paints that ground to avoid a band — compare the page grounds before moving the rail. (4) and (5) built — `KitRailSection` (kit §19): a 1px --rule 40 above every section after the first (30 on a phone), the panel 22 under it, the host's key on the box that starts at the rule, and the last section held to `viewport - rail - 72` (`.src-section:last-child`); test/kit/rail_section_test.dart. Owed: the device run's jump tests over it, and the reader-history pair. (10) built — the set gallery's FRAME is 3:4 (`AspectRatio`) with the caption line under it and the grid's extent computed from the tile width (`.srcset-grid` padding 14); test/kit/kit_smoke_test.dart. Owed: the source-set pair, which is also F-82 (1)'s wrong-surface hold. (9) built — ingredients sans 15/26 (was the body's 16), the --rule BETWEEN items (`li + li`, was under every item), the figure caption sans 12 at --fg-muted (was §3's 14 at --fg-subtle); kit_smoke_test. Owed: the recipe pair. (8) built — `KitKeyHint`, and the row says only Hold to pause & rest: this client binds no keys, so the reference's Space and arrow hints would name controls that do nothing. A composition deviation, recorded in CLAUDE.md §Composition deviations (b9d77ee; the file was at its 750-word cap until prose was tightened) and at the site. (7) built — the passage mark sits in the sheet's padding at -26 (-14 where the padding collapses), top/bottom 4, and the text keeps its measure; a manuscript table sets at 15 (`.ms-body table`); dwell_test. Still open: (2) (needs F-74's Aa popover) and (3) (the reader's page ground, --surface here vs --bg on web). Every pair this item lists is owed: no re-shoot this session (disk under 5 GB; the emulator held by other lanes).
  2026-10-07: every listed hold re-shot over 5b0b73e (frames in the burn-down evidence, flutter-3), compared to web 5413658's phone frames. MATCH, committed: reader-shelves, shelf-picker-search. NOT matching: reader — (2) and (3). reader-history — the hold ends with the rail marking Original and History's head 72 under the rail (its `lastReach`), where web marks History with the rows under the rail. reader-manuscript — no drop cap on the first passage, no `Aa` (F-74), no accent rule above the sheet, the image caption drawn without its figure frame, marks full sage where web's are unfilled, and 22 words where web counts 9. reader-speed-read — the rail scrolls the current jump to its leading edge and clips its glyph; the standfirst omits web's key sentence (8, recorded here). recipe — ingredients sit flush with their eyebrow where web indents the list (and outdents `To finish`). source-set — F-82 (1), two surfaces.
  2026-10-12: (2) done with F-74 (f9d1d56): Aa → Reading stats is the breakdown's one door, and the link under Mark finished is gone. (3) built: on a phone the reader sits in AppLayout's --bg, so the rail paints --bg there (--surface wide, outside AppLayout), its trailing 26 fade (`mask-image`), each jump 12 a side; rail_section_test. recipe: the reference's `.ms-body ul/ol { padding-left: 26px }` outranks `.rc-ings`/`.rc-steps`, so the items indent 26 under the eyebrow and a group key does not, `li` 5 / 11 with the rule between, the tick 4 down and 11 before the text, step text 26 in; kit_smoke_test. reader-manuscript's image: `.ms-body img` is framed (1px --border, --r-sm, 6/14) and a tap opens the lightbox; one that does not load keeps its frame with a broken glyph and its alt, as the browser draws it (`kitManuscriptImage`). reader-speed-read: the hold revealed the jump's LABEL, which put it at the rail's leading edge and cut its glyph; it reveals the whole jump now. The full-sage marks are the hold's dwell (12 words count as read in 1.6 s; web shoots before that) — a hold-timing difference, not a defect. Owed: reader-history's landing (to be read on the device), and every listed pair.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): reader (Priority row → F-99), reader-history (History lands and stays; its first batch frame was shot late and re-taken), reader-manuscript, reader-speed-read (the jump's glyph whole), reader-shelves and shelf-picker-search (Priority row → F-99), recipe (26 indent), source-set (the §15.2 sheet on Sources) — all MATCH otherwise.

## F-78 · Ask and Search — passage text keeps its line breaks, the Ask header and composer, the rail overlay, the open result card
- status: done 2026-10-12
- screen: ask
- route: /ask
- spec: spec/screens/ask.md §Composition; spec/screens/search.md §Composition; spec/component-kit.md §6.6 §17
- web: src/pages/AskView.jsx; src/pages/SearchView.jsx; src/styles/app-kit.css; src/styles/app-responsive.css
- flutter: lib/pages/chat_page.dart; lib/widgets/kit/kit_markers.dart; lib/pages/search/result_card.dart; lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_composer.dart; lib/widgets/kit/kit_headers.dart
- folds: none — found by the 2026-10-05 re-shoot (burn-down report, flutter)
- device_test: none
- shots: ask; ask-thread; ask-rail; ask-turn-failed; search
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: (1) One root, two screens: kit_markers.dart ~169 renders `TextSpan(text: p.text)`, so a `\n` in chunk text breaks the line in Search snippets and Ask citation excerpts; web collapses white space (`.sresult-passage`). (2) Ask: History is a padded KitButton.ghost (chat_page.dart ~180) where web has a bare `.pact` link (sans 12, padding 0, 13px glyph); the title stays 30 at phone width, web 26 at ≤680 (app-responsive.css ~385); the empty state starts ~48pt lower (chat_page.dart ~370 `s8` on KitEmptyState's own `s8`); the prompt glyph is a filled auto_awesome vs IcoSparkle; the empty send is drawn at 0.45 (kit_composer.dart ~209, Support's rule) where Ask's `.send` has no disabled rule. (3) ask-thread: the reader avatar uses the flipping toneSage; web pins raw `--sage-700` in both themes (app-kit.css ~365). (4) ask-rail: the overlay is a Stack inside the page body, so the app bar and footer stay undimmed; web's rail is position fixed over everything with its backdrop. (5) Search: the open card draws an accent border + shadow-2 (result_card.dart ~56) that web has no rule for; the count line is left-aligned (kit_controls.dart ~913) where search.md says it stays trailing. (6) ask-turn-failed: the batch hold reported OK yet the frame is the empty scoped screen — no question, no refusal, no Try again; find out how a hold that asserts `Try again` photographed a state without it. The web hold for it runs on /ask with an injected shelf key (theme-shots.mjs ~690), so the headers differ by construction — align the two holds first.
  2026-10-12: built — (1) `KitMarkedText` collapses white space as every web host of `MarkedText` does (a normal-flow element), and the manuscript's plain text is one paragraph as web's `<p>${text}</p>` is; (2) History is the bare `.pact` link (`KitPassageAction`), the title 26 below the compact width (`ScreenHeader.titleSizeCompact`), the empty state 20 under the rule where it was s8 on s8, the prompts draw `KitSparkle` (the reference's stroked IcoSparkle, painted; Material has none) at the row's 15; (3) the reader's avatar pins raw --sage-700 in both themes (`AppColors.askAvatarYou`); (4) the rail and its backdrop draw on the ROOT overlay, over the app bar and the support footer; (5) the open result card has no rule of its own (`.sresult.open` has none) and the count line is `KitControlBar.count` — last in the row, or its own line at the trailing edge once the bar stacks. NOT done, a spec-vs-web disagreement for Xavier: Ask's empty send is held at 0.45 here (Support's `.sup-send:disabled`); web's Ask `.send` has no disabled rule at all, and component-kit §6.1 says a held control dims at --held-opacity 0.5. (6) the two holds still differ by construction (web injects a shelf key on /ask; this client's hold is /ask/shelf/no-such-shelf) — web's hold is the web lane's. Pairs owed.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): ask, ask-thread, ask-turn-failed (the transcript against the composer), ask-rail (one conversation, full height, the status bar legible over it), search — MATCH; the held send's look is booked on F-103 (BLOCKED, Xavier).

## F-79 · Sources, the folder picker and Activity — the drop zone, a disabled Add link, the import counter row, the timeline spine
- status: done 2026-10-12
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Composition; spec/screens/activity.md §Composition; spec/component-kit.md §4.2 §6.4
- web: src/pages/SourcesBrowse.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/ActivityView.jsx; src/styles/app-kit.css
- flutter: lib/widgets/file_uploader.dart; lib/pages/sources_page.dart; lib/widgets/kit/kit_rows.dart; lib/widgets/kit/kit_controls.dart; lib/pages/activity_page.dart
- folds: none — found by the 2026-10-05 re-shoot (burn-down report, flutter)
- device_test: none
- shots: sources; folder-contents; activity
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: (1) Drop zone: a centred filled Material upload arrow vs web's stroke upload-tray glyph at the leading edge; copy says "tap to add a few" where web says "click to add a few" — a touch adaptation recorded nowhere, so either record it in CLAUDE.md §Composition deviations or follow web. (2) Add link with an empty field is drawn disabled, nearly invisible in dark; web draws `.btn-secondary` at full strength. (3) An "Add an image set (up to 20)" row under the link row that is in no §Composition and no recorded deviation. (4) Folder picker: "Import 0 items" is dimmed where web is full-strength (web may be the side at fault — a disabled control drawn enabled; decide by spec), Import + Cancel left-aligned where web right-aligns at phone width (`.proc-error-actions`), the checkbox a heavy 2px Material square vs web's 1px rounded box. (5) Activity: the spine sits at left 15 but rows lack web's `margin: 0 -12px` inset, so it runs along the nodes' left edge, not their centres (kit_rows.dart KitTimeline); the youtube/instagram/tiktok/podcast/video badges are filled --surface-sunken where web leaves them untinted.
  2026-10-12: built (b79b16e) — (1) the drop zone draws `KitUploadGlyph` (web's stroked IcoUpload tray, painted) in a 40 box at the zone's LEADING edge, as `.dz-feather` sits; *tap* not *click* is a recorded touch deviation (CLAUDE.md). (2) MATCH since 4.108.0: web's `.btn:disabled` holds Add link at --held-opacity too, and both draw it faint in dark. (3) recorded in CLAUDE.md §Composition deviations: *Add an image set* is a device capability web lacks. (4) "Import 0 items" held as web's `.proc-retry:disabled` (MATCH); confirm and Cancel at the trailing edge on a phone; the checkbox is `KitCheckbox`, the reference's 13px box. (5) the timeline's rows carry their -12 inset, so the spine runs through the nodes' centres; platform and recording badges take no tint. Pairs owed (sources, folder-contents, activity).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): sources (the tray, the leading upload glyph), folder-contents (the picker's box and trailing foot; Import 0 items held → F-103), activity (the inset spine) — MATCH.

## F-80 · Readings day, Notifications, Settings, Onboarding — the drifts the 2026-10-05 pairs found
- status: done 2026-10-12
- screen: scripture-day
- route: /letters
- spec: spec/screens/letters.md §Composition; spec/screens/notifications.md §Composition; spec/screens/settings.md §Composition; spec/screens/onboarding.md §Composition
- web: src/pages/letters/ScriptureDayView.jsx; src/styles/app-scripture.css; src/pages/NotificationSettings.jsx; src/shell/AppShell.jsx; src/pages/onboarding/OnboardingWizard.jsx; src/styles/app-onboarding-wizard.css
- flutter: lib/pages/letters/scripture_day_page.dart; lib/pages/notification_settings_page.dart; lib/pages/settings_page.dart; lib/pages/onboarding/wizard.dart
- folds: none — found by the 2026-10-05 re-shoot (burn-down report, flutter)
- device_test: none
- shots: scripture-day; notifications; settings; onboarding; letter-settings
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: (1) Readings day: the reading reference is h3 28 where `.sc-day-ref` is serif 21/600; on a phone web wraps the header with `.sc-day-ct{margin-left:0}` so the count follows the reference, here it is pinned right by an Expanded; the live notice's figures are plain where web wraps them in <b>. (2) Notifications: the Type group is `KitFieldGroup(first: true)` and draws no top rule; web's `.cfg-group:first-of-type` does not match there, so web rules it. (3) Settings: Theme is a labelled segmented control (Light / System / Dark, settings_page.dart ~99); web's ThemeToggle is three glyphs with titles, no text. (4) Onboarding: the head borrows §2.1's two-bar rule where web draws `.ob-rule` (a 38px --ink-300 dash with a 12px accent tick); title 32 vs `.ob-title` 27 at ≤460 (wraps "library." alone); standfirst ~19 vs 17; the rail band reads lighter than --chrome in dark. (5) Letter settings — a RULING, not a fix: web phone stacks two separately scrolling panes with the preview on the first screen; here the preview follows the whole form. The spec says only "below it on a phone". The web references for letter-settings are v4.97.0 and show the pre-4.98.0 preview — re-shoot web first.
  2026-10-12: built — (1) the readings day's head is `.sc-day-h`: the label mono 9.5, the reference `.sc-day-ref` serif 21/600 (not h3's 28), the count mono 10.5 at --fg-subtle pushed trailing, and on a phone the row wraps at 8 with the count FOLLOWING the reference; the live notice is sans 13/20 --fg-muted with its figures in `<b>` (--fg, 600); scripture_day_test. (2) the Type group is ruled above, as web's `.cfg-group:first-of-type` never matches there. (3) Theme is `KitThemeToggle` — three glyphs named by their titles, no text, web's `.theme-toggle` pill track. (4) onboarding's head is its own (`ChapterOpening(onboarding: true)`): `.ob-title` 40 / 31 below the compact width / 27 at ≤460, `.ob-stand` 19 → 17 at ≤460, and `.ob-rule` (a 38px --ink-300 dash, a 12px accent tick) in place of the two-bar chapter rule; the rail band's dark shade is still to be measured on the frames. (5) closed by F-88 (the two-pane letter settings, ruled 2026-10-08). Pairs owed.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): scripture-day (web's Friday of week 18 with the partial notice; its seed now writes `lead` as the bool the backend writes), notifications, settings (icon-only theme toggle), onboarding (Step 1 of 6, four steps, the two-tone rule), letter-settings — MATCH.

## F-81 · Shelves — the grid's top margin, spine heights, the selected swatch's size, the sheet's glyph; serif optical size everywhere
- status: done 2026-10-12
- screen: shelves
- route: /shelves
- spec: spec/screens/library.md §Shelves §Shelf color; spec/component-kit.md §15 §21; spec/design-tokens.md
- web: src/pages/ShelvesView.jsx; src/styles/app-shelves.css; src/shared/ShelfForm.jsx; src/styles/theme.css
- flutter: lib/pages/tags_page.dart; lib/widgets/kit/kit_cards.dart; lib/widgets/kit/kit_controls.dart; lib/pages/tags/shelf_sheet.dart; lib/widgets/kit/kit_overlay.dart; lib/theme/app_theme.dart
- folds: none — found by the 2026-10-05 re-shoot (burn-down report, flutter)
- device_test: none
- shots: shelves; shelf-color-picker; shelf-create-sheet
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: (1) The grid follows the chapter opening directly; web `.shelf-grid { margin-top: 26px }`. (2) Spines scale on 44 (kit_cards.dart ~644) where web's percent heights are of a 56px strip. (3) `Empty shelf` is serif italic; `.scv-empty` is sans italic. (4) The index standfirst says `N volumes, shelved.` with no singular. (5) KitSwatch draws the 2px selection ring OUTSIDE the 24pt circle, so the selected swatch is 28; web's ring is the circle's own border, every swatch one size, hairline 2px inside. (6) The create sheet's glyph is layers_outlined vs IcoStack (three layers), coloured accentText where web uses --seal (same value today, wrong name). (7) Cross-cutting, seen on ask, search, recipe and the landing: serif text sets 8-15% wider than web at the same glyph height. app_theme.dart drives only the `wght` axis; web sets `opsz` per role (theme.css ~480-519). Cause unproven — measure before changing a face every screen uses. (8) shelf-backfill-review is RETIRED (4.102.0) and fails its hold, but done item F-38 still lists it in shots:, so screenshot_pair_check reports it STALE-PAIR forever; the review's pair is web's review-backfill, which needs a stored shelf_backfill task. Needs a pair-check rule for a retired state, not an edit to F-38.
  2026-10-12: built — (1) 26 above the grid (`.shelf-grid { margin-top }`); (2) the spines are percents of 56, `.shelf-spines`' height; (3) *Empty shelf* is sans italic (`.scv-empty`); (4) the standfirst counts `1 volume` singular; (5) `KitSwatch` is one 24 circle in every state, the 2px ring its own border drawn inside it, the --border hairline inset under the ring; (6) the create sheet's mark is `KitStackGlyph` (web's IcoStack, painted) and every §15 sheet mark is at --seal. (7) MEASURED and moved to F-100: the cause is proved (no `opsz` is set; `Library` at 44 lays out 158 wide against web's ~133, 134 with `opsz`), but flutter_html cannot set font variations, so it waits on a plan for html-rendered serif. (8) already settled by the queue's `retired-shots:` header, which screenshot_pair_check reads. Pairs owed (shelves, shelf-color-picker, shelf-create-sheet).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): shelves, shelf-color-picker (one row of one-size swatches), shelf-create-sheet (the stack mark at 18 in its tile — the batch caught it drawn at 36, fixed in 252b19b) — MATCH.

## F-82 · Holds that shoot a different surface than the reference, and the site's control heights and hero lines
- status: done 2026-10-12
- screen: source-file
- route: /reader/{id}
- spec: spec/component-kit.md §15.1 §15.2; spec/clients/flutter.md
- web: scripts/theme-shots.mjs; src/styles/signin.css; src/pages/LandingActual.jsx; src/styles/landing-actual.css
- flutter: integration_test/hold_screen_test.dart; lib/widgets/kit/kit_overlay.dart; lib/site/site_sheet.dart; lib/site/landing_page.dart
- folds: none — found by the 2026-10-05 re-shoot (burn-down report, flutter)
- device_test: none
- shots: source-file; source-set; signin; signin-fail; landing-actual
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: (1) source-file and source-set: the Flutter holds frame the reader's Original section (§15.1/§15.2 inline on the reader) while web theme-shots frames the §15 overlay sheet opened from /sources (theme-shots.mjs ~1067, ~1621), so the pairs compare two surfaces — align one side's hold before judging either. §15.1 asks for a PDF in a frame on a white sheet; Flutter prints a sentence (kit_overlay.dart ~398), recorded nowhere. (2) signin / signin-fail: fields 49 vs 43, Sign in 47 vs 43, Google 46 vs 43 — the field's 13pt vertical padding vs `padding: 11px 13px`, the button's 13 vs 12, line height 1.3 vs normal (site_sheet.dart ~307-348, signin.css ~137-159). (3) landing-actual: on a phone the hero's two fixed lines are joined with a space (landing_page.dart ~912), so "deserve" and "to be re-" share a line; web's lines are display:block. The masthead is ~26pt shorter (tighter line boxes, landing_page.dart ~698).
  2026-10-12: built — (1) the holds now frame the reference's surface: `source-file` and `source-set` open the §15 SHEET from a processing row on /sources (a failed DOCX with stored bytes; a pending image set with two of three pages), seeded by `tool/seed_overlay_sources.py` before the shot and removed after (`--remove`), as web writes and deletes them per shot; the PDF stage's sentence is a recorded deviation (CLAUDE.md: no PDF renderer is embedded, §15.1 rule 1). (2) the sign-in field is `padding: 11px 13px` (was 13), Sign in 12 (was 13), the Google button 11 (was 12); Geist's own normal line height is 1.3 (hhea 1005/-295/0), so the line box was never the gap. (3) the hero's two lines never join (`.ln { display: block }` at every width). The masthead's height is to be measured on the frames. Pairs owed (source-file, source-set — routes now /sources; signin, signin-fail, landing-actual).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): source-file and source-set (the §15 sheet from Sources' processing rows), signin, signin-fail (control heights), landing-actual (the hero's break) — MATCH; the sheet's `esc to close` foot is touch copy (CLAUDE.md).

## F-83 · Cooldowns wait it out — `retry_after_s` and §6.1 Waiting (4.107.0 tandem)
- status: done 2026-10-06
- screen: none
- route: none
- spec: spec/decisions/ADR-140-a-cooldown-says-how-long-as-a-number.md; spec/component-kit.md §6.1; spec/api/endpoints.md §Error shape; fixtures/tokens.json
- web: src/shared/cooldown.js; src/api.js; src/shared/SupersessionConfirm.jsx; src/shared/ConfirmDialog.jsx; tests/contract/cooldown-wait.test.js
- flutter: lib/shared/cooldown.dart; lib/widgets/kit/kit_wait.dart; lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_rows.dart; lib/widgets/kit/kit_composer.dart; lib/widgets/kit/kit_confirm.dart; lib/services/api.dart; lib/services/api_service.dart; lib/pages/reader/supersession_confirm.dart; test/contract/cooldown_wait_test.dart; test/contract/token_match.dart
- folds: 4.107.0 (ADR-140, tandem 3)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/confirm_check.py
- notes: ApiException.retryAfterS (a whole number >= 1 from our envelope only; never the sentence). One registry (lib/shared/cooldown.dart, web cooldown.js): WaitKey per endpoint + server scope, armed by the nine Api builders through withCooldown, so a wait outlives the widget. The kit pattern is KitWait (web useCooldown) feeding `wait:` on KitButton / KitSettingLink, `waitLeft:` on KitComposerDock (its accessible title) and `waitKey:` on KitConfirm. Sites: summary regenerate; Study now per program; the folder rescan (provider clock; this client draws no Rescan all — the sentence is said once over the provider's folders, not a toast); the processing row's Retry / Index it anyway on Sources and For your review, and inside the supersession confirm; the import job's Retry (job) and Update from source (document); Sync now (provider, calm note); Send now on Letters and Letter settings (one clock); the support send; the reader's freshness banner (now the kit's `.set-link`, was a Material TextButton). The comparator learns «retry_after_s»; api_requests_test feeds 42 for the token and asserts retryAfterS on every captured envelope (5 cooldown cases; red when the parse is removed). The Waiting state has no frame: the seed holds no cooldown, so it is gated by cooldown_wait_test (39 cases, mutation-checked) rather than a pair.

## F-84 · The 4.111.0–4.114.0 tandems — generateAudio's answer, the `assessment` skip reason, a YouTube playlist link
- status: done 2026-10-08
- screen: none
- route: none
- spec: spec/api/ingest.md; spec/screens/study.md §Syllabus; spec/decisions/ADR-149-a-unit-that-names-an-assessment-is-not-a-unit.md; spec/decisions/ADR-151-a-playlist-link-is-detected-as-a-playlist.md; fixtures/url-detection/cases.json
- web: src/api.js; src/shared/playlist.js; src/overlays/QuickAdd.jsx; src/pages/SourcesBrowse.jsx; src/pages/study/schedule.js; tests/contract/playlist-link.test.js
- flutter: lib/services/api.dart; lib/pages/study/syllabus_plan_editor.dart; lib/state/upload_notifier.dart; lib/models/upload_file.dart; lib/widgets/file_uploader.dart; lib/shared/playlist.dart (new); test/contract/playlist_link_test.dart (new); test/contract/skip_reason_copy_test.dart (new); test/kit/stored_plans_test.dart
- folds: 4.111.0 (no duration_seconds in fn_generate_audio's answer — doc comment); 4.112.0 (ADR-149, `assessment` skip reason); 4.114.0 (ADR-151, `youtube_playlist` detection + the docIds sentences)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/upload_set_check.py
- notes: 4.111.0: Api.generateAudio's doc comment drops duration_seconds (nothing read it; the Listen stat reads the document's stored field). 4.112.0: skipReasonCopy (was _skipReason) is web's SKIP_REASONS copy for copy — every row had been this client's paraphrase, and `assessment` fell to the generic line; skip_reason_copy_test reads schedule.js itself. 4.114.0: detectUrlType maps youtube.com /playlist with a non-empty `list` to youtube_playlist before the video row (the 3 shared url-detection cases were red); lib/shared/playlist.dart ports web playlist.js (playlistAdded from `enqueued`/`failed`/`notStarted`, never docIds.length, never `warnings`; pendingBadgeKind). FileUploader is this client's one link-add surface (Sources and onboarding's step 2): its in-flight row is web QuickAdd's tile, so it plates a link by its detected kind (a playlist as YT), reads "YouTube playlist — uploading" while pending and the count sentence when done; a single link keeps "Queued for processing". No frame: the seed holds no pending link, and the playlist expansion has never run live.

## F-85 · The 2026-10-08 web tandems — the eleventh, read-only "current" swatch; Sources' filter note says "type"
- status: done 2026-10-09
- screen: shelf-color-picker
- route: /shelves/seed-tag-stories
- spec: spec/screens/library.md §Shelf color; spec/screens/sources.md §States
- web: src/pages/ShelvesView.jsx; src/shared/shelfColor.js; src/styles/app-shelves.css; src/pages/SourcesBrowse.jsx; tests/contract/ui-rulings-2026-10-08.test.js
- flutter: lib/widgets/kit/kit_controls.dart; lib/pages/tags/shelf_parts.dart; lib/pages/tags/shelf_page.dart; lib/pages/sources/browse_section.dart; integration_test/hold_screen_test.dart; test/kit/shelf_current_swatch_test.dart (new)
- folds: TODO "RULED 2026-10-08: an eleventh, read-only 'current' swatch" (web b70f5ea, spec 4a38fe7); TODO "No sources of that kind yet." → "type" (web b70f5ea)
- device_test: none
- shots: shelf-color-picker
- extra_gates: python3 ../NoteLetter-contracts/harness/token_contrast_check.py --target flutter
- notes: KitSwatch gains readOnly + tooltip (no button role, no pointer, never dimmed as a held control is). ShelfSwatches(showCurrent:) draws a stored colour outside the ten after them, selected, in what every other surface paints (AppColors.shelfColor, else --fg-subtle) — only on the shelf's settings (shelf_page), never in the create form. The `color-picker` hold now frames Stories (seed-tag-stories, #059669) as the reference does, and asserts at least ten swatches. _NoneOfThatKind says the reference's "No sources of that type yet.", held to SourcesBrowse.jsx's own line by the test. Mutation-checked: no eleventh → 4 red; the eleventh dimmed like a held control → 2 red.

## F-86 · One connect-card pattern — the fixed §5.1 card, an "Import from {provider}" header per connected provider, organizing enabled from Settings (ruled 2026-10-08)
- status: done 2026-10-09
- screen: sources
- route: /sources
- spec: spec/component-kit.md §5.1 §3 §6.1 §14.2 §18; spec/screens/sources.md §Composition §Cloud import §Sync control; spec/screens/settings.md §Organization card; spec/api/cloud-storage.md
- web: src/pages/SourcesBrowse.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/pages/SettingsView.jsx
- flutter: lib/widgets/kit/kit_cards.dart; lib/pages/sources_page.dart; lib/pages/sources/sync_settings_panel.dart; lib/models/cloud_integration.dart; lib/shared/cloud_providers.dart (new); lib/pages/settings/organization_section.dart (new); lib/pages/settings_page.dart; integration_test/hold_screen_test.dart; test/contract/connect_card_test.dart (new); test/contract/cooldown_wait_test.dart; test/contract/cloud_sync_tandem_test.dart
- folds: TODO "RULED 2026-10-08: web's fixed card" (CS-6, one connect-card pattern)
- device_test: sources composes from the kit, in the contract order
- shots: sources; settings
- extra_gates: python3 ../NoteLetter-contracts/harness/confirm_check.py
- notes: KitConnectCard loses actions/notice/footnote: iconbox → title → subtitle → status pill, nothing else. The card is the affordance (web ConnectCard): Connect when not connected ("Connecting…" while in flight, a refused connect §14.2 under the card), the §18 Disconnect confirm when connected; the pill says the reference's Connect / Connected (an expired sign-in is still Connected — its banner is under its header). Per connected provider, _ImportFromProvider (web CloudImportPanel): a §3 header — provider glyph + "Import from {provider}", trailing links Sync now (· m:ss on the provider's clock) · Sync settings · Browse files… — that wraps the links under the eyebrow on a phone; then the no-folders sentence, the sync answer (calm kickoff / KitWaitNote / §14.2), the sync settings (SyncSettingsPanel embedded: opened by the link, its own heading the reference's AUTO-SYNC + last sync), the reconnect banner with Reconnect, and the picker. "Enable auto-organization" left the card for Settings → Organization (settings.md §Organization card, web OrganizationSection): one row per connected provider, Enable organizing, or "Choose organized folders in Sources" once the integration's `organization` is write-ready (CloudIntegration now reads that block). The threshold and the three capability toggles stay on Sources' OrganizationSettingsPanel here (web draws them on Settings) — a placement difference not reopened. Mutation-checked: the no-folders note dropped → red; the panel mounted with its own header → red.

## F-87 · The 4.115.0 tandem — an EPUB is a book: the Book class, a live kind shaped `file`, and "Books & PDFs" sends it
- status: done 2026-10-09
- screen: none
- route: none
- spec: spec/decisions/ADR-152-an-epub-is-a-book-read-in-spine-order.md; spec/api/uploads.md; spec/component-kit.md §6.4.1 §6.4.2; spec/screens/search.md
- web: src/uploadTypes.js; src/shared/FileBadge.jsx; src/pages/SearchView.jsx
- flutter: lib/shared/upload_types.dart; lib/widgets/kit/kit_controls.dart; lib/pages/search_page.dart; test/contract/epub_kind_test.dart (new)
- folds: 4.115.0 (ADR-152)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/upload_set_check.py; python3 ../NoteLetter-contracts/harness/doc_kind_check.py
- notes: upload_types: the epub class (application/epub+zip, .epub, the extension fallback) and the drop zone's help names EPUB. kit_controls: epub is a live kind and kShapeByType epub → file (it was a pending kind with no shape). search_page: `_searchFolds` {'pdf': ['epub']} feeds searchSourceTypes for both the passages and the cohesive request — until 4.115.0 doc_kind_check held this fold itself while the request sent pdf alone. Held in the working tree from 04:48Z at backend-2's request (both gates read the trees live) and committed after its 09:24Z VERSION signal. No frame: the seed holds no book.

## F-88 · Letter settings on a phone — the form over the letter, two panes that scroll on their own (ruled 2026-10-08)
- status: done 2026-10-09
- screen: letter-settings
- route: /letters/settings
- spec: spec/screens/letters.md §The letter-settings preview
- web: src/pages/LetterSettings.jsx; src/styles/app-responsive.css
- flutter: lib/pages/letter_settings_page.dart
- folds: TODO "RULED 2026-10-08 … the letter-settings preview sits where web puts it on a phone (Flutter moves)"; F-80 (5)
- device_test: none
- shots: letter-settings
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Web below its studio breakpoint makes `.letter-studio` a flex column: `.letter-config` and `.letter-preview-pane` each `overflow: auto`, shrinking to share the height, with `.letter-config`'s 1px --rule between — so the letter is on the first screen. Flutter below 1024 had the letter after the whole form. Now a Column of two Expanded KitPages (each with its own ScrollController — two scroll views cannot share the primary one) parted by a 1px --rule. Web's split follows the panes' content heights (flex-shrink by basis); here it is even, which the web frame (form ~53%, letter ~47%) is within a few points of. No widget test mounts this page (it needs most of the app's notifiers); the gate is the phone frame against letter-settings.web.phone.

## F-89 · Suggest shelves (4.116.0 tandem) — the Library sheet beside New shelf, and onboarding's shelves step
- status: done 2026-10-12
- screen: onboarding
- route: /settings
- spec: spec/decisions/ADR-153-suggested-shelves-are-new-shelves.md; spec/api/tags.md; spec/screens/library.md §Suggesting shelves; spec/screens/onboarding.md
- web: src/shared/SuggestShelves.jsx; src/pages/onboarding/OnboardingWizard.jsx; src/pages/onboarding/steps.jsx; tests/contract/suggest-shelves.test.js
- flutter: lib/services/api.dart; lib/pages/onboarding/wizard.dart; lib/pages/onboarding/steps.dart
- folds: 4.116.0 (ADR-153); TODO "RULED 2026-10-08: BUILD the surface" (Suggest shelves on every client)
- device_test: none
- shots: onboarding; shelves
- extra_gates: python3 ../NoteLetter-contracts/harness/endpoint_reach_check.py
- notes: Booked by the 2026-10-09 frame sitting: web's onboarding now reads "Step 1 of 6" and "Four steps and it's yours." with a "Choose your shelves" step; Flutter reads "Step 1 of 5" / "Three steps". The sheet: what you read about → `fn_suggest_tags {purposeText}` only (closed key) → the proposals, with the answer's `existing` titles said, never re-proposed → keep the ones you tick → `fn_approve_tags` with `{title, description, color}` and the ANSWERED colour token (always one of the ten since 4.116.0). Fewer than eight or none is a normal 200; a model failure is 502 PROVIDER_API_ERROR through §14. Flutter's approveTags/suggestTags builders exist and have no caller. Not built in this lane (coordinator: owed, after the frames).
  2026-10-12: built — `lib/pages/tags/suggest_shelves.dart` mirrors web's SuggestShelves.jsx: one `ShelfSuggestions` state for both hosts (the field seeded until typed, `fn_suggest_tags {purposeText}` stateless and repeatable, every proposal ticked, `existing` said, a 4xx beside the button and anything else §14.1 — never "no shelves to suggest"), the §15 sheet (480, the sparkle, *Nothing is created until you choose.*) creating with ONE `fn_approve_tags` (`{title, description, color}`, the colour one of the ten or a swatch by position), write before move, the follow-on fill per new shelf. Entry cards: Shelves' *Suggest shelves* after *New shelf*; the Library home's card grid gains *New shelf* and *Suggest shelves*. Onboarding is six steps: the shelves step (№ 03 · of 04) holds the ticks, and Finish makes them as a THIRD, separate write, at most once, its failure its own standfirst and line; the summary's sources row is *Your sources* (it said *Your shelves*) and *Your shelves* follows it. test/contract/suggest_shelves_test.dart (9, over the captured api/tags answers); the device run's first-run test now reads Step 1 of 6 and № 01 · OF 04. Pairs owed (onboarding, shelves).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): onboarding (Step 1 of 6 — the shelves step is counted), shelves — MATCH; the step and the sheet are gated by suggest_shelves_test.

## F-90 · What the 2026-10-09 frame sitting found — the notification level control, Study's glyph, two holds that frame another state
- status: done 2026-10-12
- screen: notifications
- route: /settings/notifications
- spec: spec/screens/notifications.md §Composition; spec/screens/study.md §Composition; spec/screens/letters.md §Composition; spec/screens/settings.md §Plan row
- web: src/pages/NotificationSettings.jsx; src/pages/StudyView.jsx; scripts/theme-shots.mjs
- flutter: lib/pages/notification_settings_page.dart; lib/pages/study_page.dart; lib/pages/sources/organization_settings_panel.dart; integration_test/hold_screen_test.dart
- folds: none — found by the 2026-10-09 re-shoot (burn-down report, flutter)
- device_test: none
- shots: notifications; study; scripture-day; settings-plan; ask-thread; ask-turn-failed; org-scan-wait
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: (1) Notifications on a phone: each channel's level control (Errors · Warnings · Successes · Info) spans the whole card in one row; web indents it under the channel's text (beside the icon column) where it wraps into a 2×2 block. (2) Study's empty state: the plate's glyph is a cards icon; web draws its study glyph (IcoStudy, a document). (3) scripture-day: the reference frame is now Friday of week 18 (Oct 2) with the partial-failure notice ("One reading could not be searched just now…"); the hold opens the seed's Thursday of week 23 at rest — align the two holds before the pair can be judged (pair NOT committed in the sitting). (4) settings-plan: the reference frames the plan AT its cap (13 of 13, the limit notice and Ask about upgrading); the hold frames the plain row, and the dev shim's pinned plan clock says "resets 1 October" — align the hold (pair NOT committed). (5) Ask: a short transcript (one turn, or one refused turn) starts under the header here; on web it sits at the BOTTOM, against the composer, as a chat does (ask-thread and ask-turn-failed pairs, 2026-10-09). (6) Sources → Organized folders, seen in the first Rescan-all frame (org-scan-wait, 2026-10-09): web's §3 header names the provider (glyph + "· Google Drive") and carries "Choose folders · Rescan all"; here it is "ORGANIZED FOLDERS" with Rescan all alone. Web's folder rows carry a README status pill (pending / edited by you / written) and a rescan glyph, with the charter as a mono quote followed by Edit · Regenerate; here the row has a doc count, the charter in serif italic, and Edit charter / Rescan buttons. Web orders Suggestions ABOVE the folders and says the wait sentence above the header; here suggestions follow the folders and the sentence sits under the header. Tooling found on the way, fixed in hold_screen_test.dart (bdf30a6 and the 2026-10-09 keyboard commit): a fresh simulator raises the software keyboard over every state that focuses a field; ask-turn-failed's refused turn returns focus to the composer (F-78 (6)'s mystery); the Library's setup checklist hides once an Ask hold has set the asked flag earlier in the same app install — shoot library first after `simctl uninstall`.
  2026-10-12: (5) built with F-78 — `KitPage.anchorBottom`: a transcript shorter than the viewport rests against the composer (`.ask-thread { margin: auto auto 0 }`); ask-thread / ask-turn-failed pairs owed.
  2026-10-12: built — (1) a setting row's `below` (the level picker) stays in the text column at every width, beside the icon column, where its track wraps 2×2 on a phone. (2) Study's empty plate is `KitCardsGlyph` (web's IcoCards, painted). (3) the hold now frames the reference's state: `tool/seed_frame_states.py` writes web's readings letter (Friday of week 18, dated as web's frame, 2026-10-02) and the hold makes the Psalm's search fail through the backend, as theme-shots arms it. (4) the same script caps the free plan at the reader's own count (`config/plans`, `--remove` after), so the Plan row is at its cap with §12's notice as the reference frames it. (5) built with F-78 (ae81173). (6) the organized-folders panel is web's OrganizationPanel: the suggestions first, the scan wait above the header, the header the provider's glyph and *Organized folders · {provider}* with *Choose folders · Rescan all* (Choose folders opens the folders-only picker over `organization.root_folder_ids`, ≤10, write before move), each folder a `.proc-row` card (`KitFolderCard`: the path over *N files*, `KitReadmeChip`, the rescan as an icon titled *Rescan this folder*), its charter a mono italic quote with Edit · Regenerate inline, the folders ordered by path, *No organized folders yet — choose folders to begin.* Pairs owed (notifications, study, scripture-day, settings-plan, org-scan-wait, ask-thread, ask-turn-failed).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): notifications (the level picker in the text column, 2×2), study (the cards glyph), scripture-day, settings-plan (13 of 13 with §12's notice; "resets 1 October" against web's "1 November" is the dev shim's pinned plan clock, not the screen), ask-thread, ask-turn-failed, org-scan-wait (web's anatomy; the README chips read the stored `readme.status` since 5422e2e) — MATCH.

## F-91 · A shelf colour resolves per theme (4.117.0 tandem) — the dark ten, at every site that paints a shelf
- status: done 2026-10-09
- screen: library
- route: /
- spec: spec/decisions/ADR-154-a-shelf-colour-resolves-per-theme.md; spec/design-tokens.md
- web: src/styles/theme.css; src/shared/shelfColor.js
- flutter: lib/theme/app_colors.dart; lib/pages/tags/shelf_parts.dart; lib/pages/sources/shelf_books.dart
- folds: 4.117.0 (ADR-154)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/token_contrast_check.py
- notes: `shelfColorsDark` beside `shelfColors`, the ten values of design-tokens.md's `--shelf-{name}` dark column (sage-500 → _sage300, brick-400 → _brick300, the rest literal). `shelfColor(value, dark:)` takes `dark` as REQUIRED — a defaulted flag would let a forgotten site paint the light ten on a dark surface with nothing red — and every painting site passes `Tokens.of(context).isDark` / `t.isDark` (twelve sites; `bookOf` gains `dark:` for its four callers). The picker's ten swatches paint the theme's map; a legacy hex paints the same in both themes. The kit cloth in kit_shelf.dart is a fixed raw step (pair-ok) and stays. shelf_sheet's default colour reads the first NAME from `shelfColorLabels`, since a bare `shelfColors` is now one half of a pair (5l PAIR-HALF). The contract test reads the dark ten from design-tokens.md's table, not a copy; the swatch test mounts each theme in its own test (a second mount in one test animates between themes and one pump reads the old one) and was red with the dark map unread. controls.dark.png re-baselined: 43px, the Theology tag's sage dot only. Done by the coordinator on 2026-10-09 because the Flutter lane had ended and the token gate was refusing every web and extension commit on this arm alone. No frame re-shot: web's dark frames predate its own ADR-154 half.

## F-92 · A folder sync may take books (4.120.0 tandem) — EPUB is a sync type pill, a rule row and a folder-contents count
- status: done 2026-10-09
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-157-a-folder-sync-may-take-books.md; spec/api/cloud-storage.md; spec/screens/sources.md
- web: src/pages/sources/CloudFilePicker.jsx; tests/contract/cloud-type-keys.test.js
- flutter: lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/folder_contents.dart; lib/models/import_job.dart
- folds: 4.120.0 (ADR-157)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/vocab_check.py
- notes: `cloudFileTypes` (public now, web `CLOUD_TYPE_KEYS`) gains `epub`, so the sync settings offer a fourth *Import these types* pill and a fourth review-rule row; `cloudTypeLabel('epub')` is EPUB; `ImportJob.typeKey` maps `application/epub+zip`. `test/contract/cloud_type_keys_test.dart` reads the contract's `include_types` set and sources.md's label line both ways, as web's test does. The default stays pdf + docx (ADR-157), so no existing panel changes until the reader ticks the pill. No Flutter pair to re-shoot: the `sync-folders` hold is shot for looking only, with no committed pair; web's `sync-folders` frames are web's to re-shoot.

## F-93 · Settings → Sources: the organization settings' one home, and the door to it from Sources (ruled 2026-10-09)
- status: done 2026-10-09
- screen: settings
- route: /settings/sources
- spec: spec/screens/settings.md §Sources section; spec/screens/sources.md §Organized-folders panel
- web: src/pages/SettingsView.jsx; src/pages/sources/CloudImportPanel.jsx; src/shell/useRoute.js; tests/contract/settings-sources.test.js
- flutter: lib/pages/settings/sources_section.dart; lib/pages/sources/organization_settings_panel.dart; lib/pages/sources_page.dart; lib/router.dart
- folds: TODO "RULED 2026-10-09: a Sources section in Settings, reachable from the Sources page as well" (the flutter lane's BLOCKED/XAVIER on where the Organization controls live)
- device_test: none
- shots: settings; sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The threshold (web's words now: "Confidence threshold"), the default reorganize mode (Split · Copy) and each write-ready provider's three switches moved OFF Sources (`OrganizationSettingsPanel`, gone) into Settings' section, renamed Organization → Sources (`SourcesSection`, file `settings/sources_section.dart`). The switches write `{enabled: true, flag: v}` and draw `flag && enabled`, as the reference does; the segmented control and switches draw the STORED value (write before you move). Sources keeps `OrganizedFoldersSection`: one `OrganizedFoldersPanel` per provider whose integration is write-ready — the reference's gate, no longer the settings read's. Every connected provider's Import-from header gains **Organization settings** → `/settings/sources` (`SettingsPage(focusSources: true)`, which `Scrollable.ensureVisible`s the section once it is drawn). `screenNames` gains `/settings/sources` → `settings-sources`. The C4 unread-settings and UNKNOWN_KEYS tests moved with the controls (they mount `SourcesSection`); the focus scroll is mutation-checked.

## F-95 · A cloud connection is claimed, not read off the URL (5.0.0 tandem, ADR-158, INV-32)
- status: done 2026-10-12
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-158-a-grant-is-claimed-by-the-account-that-asked.md; spec/api/cloud-storage.md; spec/screens/sources.md
- web: src/shared/cloudClaim.js; src/pages/SourcesBrowse.jsx; src/api.js; tests/contract/cloud-claim.test.js
- flutter: lib/router.dart; lib/pages/sources_page.dart; lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/shared/cloud_return.dart; lib/state/cloud_notifier.dart; lib/state/org_notifier.dart; lib/pages/settings/sources_section.dart; android/app/src/main/AndroidManifest.xml; pubspec.yaml
- folds: 5.0.0 (ADR-158); 5.1.0 (ADR-159)
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/client_timeout_check.py --target flutter; python3 ../NoteLetter-contracts/harness/endpoint_reach_check.py
- notes: The callback no longer says a connection happened: it redirects to /sources?cloud_connect=claim&claim=…&provider=… (or cloud_connect=error&reason=…). The router reads `claim`; SourcesPage strips the params FIRST (`context.go('/sources')`), calls `Api.claimCloudConnection(claim)` ONCE (`{claim}`, closed key set) and feeds the answer — {cloud_connect, provider, connection, org, reason}, the vocabulary `_handleOAuthReturn` already reads from the URL — into that handler. `cloud_connect=success` in a URL is believed by nobody. A refusal (403 FORBIDDEN another account started it, 404 NOT_FOUND expired or spent) shows the server's sentence on the kit's inline failure, never copy of ours. While the claim runs, the return says 'Finishing the {Provider} connection…' (web's words). `endpoint_budgets.dart` gains fn_claim_cloud_connection at the recipe's 60s. On a PHONE the return lands in the system browser's web app, not here, until an app return exists (an additive MINOR booked in TODO); the web app claims it if signed in to the same account, and this app sees the connection on its next loadIntegrations. Web's frames: cloud-claim pending / refused / success were rendered for looking only (not committed).
  2026-10-12: built with the app return folded in (5.1.0, ADR-159, live since backend 19:08Z). Connect and the organization grant send `return: "app"` from every non-web build and run the consent in an in-app auth session (flutter_web_auth_2 ^5.1.0, scheme `noteletter`; Android registers its CallbackActivity, iOS needs no plist entry); the session's `noteletter://cloud-connect?…` is HELD by `CloudReturn` and Sources takes it once — on arrival, or through its listener when the session ends while it is open; Settings → Sources' grant routes to /sources for it. A web build's /sources params are stripped first and acted on the same way. `claim` → `CloudNotifier.claim` once → the answer's success/org/reconnected (toast, and the picker only for a new connection), an `error` answer the reason banner, a refusal the server's sentence on §14.2; *Finishing the {Provider} connection…* while it runs. A cancelled session says nothing. The reason copy is now the reference's connectErrorCopy (it names the provider). Unproven live: no OAuth runs against the emulator, so the session's round trip is gated on its params (the captured `*-return-app` redirects), not on a consent.
- placed: after F-93

## F-94 · The landing names EPUBs (ruled 2026-10-09)
- status: done 2026-10-09
- screen: landing
- route: /
- spec: spec/decisions/ADR-152-an-epub-is-a-book-read-in-spine-order.md
- web: src/pages/LandingActual.jsx
- flutter: lib/site/landing_page.dart
- folds: TODO "RULED 2026-10-09: yes, name EPUB (every landing)"
- device_test: none
- shots: landing-actual
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: `_ticker` and the "Read" group gain EPUBs after PDFs, verbatim from web's TICKER and WAYS; `test/contract/landing_test.dart` now reads both lists out of LandingActual.jsx, so a format one landing names and the other does not is red. The `landing-actual` pair is re-shot with web's in the same sitting.

## F-96 · Sources — the empty library says the passages arrive as each source is read (web e924677)
- status: done 2026-10-12
- screen: sources
- route: /sources
- spec: spec/screens/sources.md
- web: src/pages/SourcesBrowse.jsx
- flutter: lib/pages/sources/browse_section.dart
- folds: none — web e924677, contracts 66dea71 (UI-only, 2026-10-12)
- device_test: none
- shots: none
- extra_gates: none
- notes: The §7 standfirst under the control bar of an empty library said the passages "start arriving within a minute", which nothing measured and a long video breaks. It reads web's sentence: *Add a file or connect a service, and the passages arrive as each source is read — a long video or recording takes longest.* (sources.md §Composition). browse_section.dart ~814. The seed is not an empty library, so no pair shows it: a widget test is the proof. Booked by the coordinator from the web lane's close (signals 19:38Z).

## F-97 · Playlist — a cut playlist says where it was cut (5.2.0, ADR-160)
- status: done 2026-10-12
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-160-a-playlist-says-where-it-was-cut.md; spec/api/ingest.md
- web: src/shared/playlist.js
- flutter: lib/shared/playlist.dart; test/contract/playlist_link_test.dart
- folds: 5.2.0 (ADR-160)
- device_test: none
- shots: none
- extra_gates: none
- notes: Every playlist answer from fn_ingest_url gains `capped` (bool, measured) and `cap` (100); `warnings` now carries only our sentences. When `capped`, `playlistAdded` appends LAST "The playlist has more than {cap} videos; only the first {cap} were read." with the answer's `cap`, never a constant. Tested from fixture `ingest:youtube-playlist-capped` (POST {url,type}, replays like `ingest:youtube-playlist`), as web's playlist.js is. Booked from the backend's 19:27Z VERSION line.

## F-98 · Frames — re-look at the pairs whose web reference moved (ask, reader, reader-shelves, shelf-picker-search)
- status: done 2026-10-12
- screen: none
- route: none
- spec: spec/clients/flutter.md
- web: scripts/theme-shots.mjs
- flutter: integration_test/hold_screen_test.dart
- folds: none — web 985bb87 re-shot them (2026-10-12)
- device_test: none
- shots: ask; reader; reader-shelves; shelf-picker-search
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: screenshot_pair_check reports STALE-WEB-FRAME on all four: Ask's §7 rows span 512, not 440 (web's §7 fold, 18e19c3), and the reader draws a Priority row under Shelves (web 9477c9c). Copy web's frames (`tool/web_frames.sh`) once the screens they frame are done, look again, and commit each pair MATCH or booked — the reader's Priority row is booked on the blocked Priority item below.
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): ask, reader, reader-shelves, shelf-picker-search re-copied from web 985bb87 and looked at: Ask's rows MATCH; the reader's Priority row is booked on F-99.

## F-99 · Reader — the Priority row (web 9477c9c)
- status: done 2026-10-13
- screen: reader
- route: /reader/{id}
- spec: spec/screens/reader.md §Source priority; spec/screens/sources.md §Composition; spec/decisions/ADR-155-a-chosen-priority-is-stamped.md; spec/component-kit.md §6.8
- web: src/pages/ReaderView.jsx; src/styles/app-source.css; src/api.js
- flutter: lib/pages/reader/source_priority.dart; lib/pages/reader_page.dart; lib/models/document.dart; lib/widgets/kit/kit_text.dart; lib/pages/sources/browse_section.dart; test/kit/source_priority_test.dart; integration_test/device_run_test.dart; integration_test/hold_screen_test.dart; tool/queue.py
- folds: none — web 9477c9c, contracts 66dea71 (UI-only, 2026-10-12); ruled 2026-10-13 (TODO "RULED 2026-10-13: the reader")
- device_test: the reader sets a source's priority
- shots: reader; reader-shelves; shelf-picker-search; reader-priority
- extra_gates: none
- notes: reader.md §Source priority: under the Shelves row a §6.8 Segmented control Default · Low · Normal · High, the stored number in mono, one quiet line; Default sends `sourcePriority: null`; the lit segment is read off `source_priority_set_at`, never the number (ADR-155); write before move. This client sets priority from the library rows' overflow (browse_section.dart ~704) and sources.md now says a finished source's settings live in the reader. Do not move the priority control until Xavier rules where it lives (coordinator, 2026-10-12).
  2026-10-13: RULED — the reader (Low 0.2, High 0.8 stand). Built: `SourcePriorityRow` under the Shelves row (the mono caps label, the track, the stored figure in mono 12 `--fg-muted`, the `KitText.note` line; below 768 the figure rides beside the label and the track fills, as web below 680); `priorityChoice` lights off the stamp with Flutter's old slider bands; Default sends null; the pressed segment reads Saving… and the track holds; §14.2 under the row; the document commits through `withSourcePriority` only after the 200. `Document` reads `source_priority_set_at` (tsMs) and keeps `source_priority` null when absent (no figure is solved for). sources.md §Per-source affordances: a library row is the link and carries no other control — the `_RowMenu` overflow (Open · Priority & tags… · Remove) is gone, and with it every mount of `DocumentDetailSheet` (its slider wrote any number and could not send Default). Its file was Flutter's last under lib/pages/library/, which 5n's SCREENS table named; the backend lane dropped that path (contracts 8448627) and the file is deleted, with `retired-paths:` in this file's header (new in tool/queue.py), since F-43 lists it. Device test drives the real write through the shim and back to Default; hold `priority-high` frames web's `reader-priority` and presses Default after.

## F-100 · Serif optical size — every serif role sets `opsz` as the reference does (measured from F-81 (7))
- status: done 2026-10-12
- screen: none
- route: none
- spec: spec/design-tokens.md
- web: src/styles/theme.css; src/styles/app-kit.css
- flutter: lib/theme/app_theme.dart; lib/widgets/kit/kit_text.dart; lib/widgets/kit/kit_reading.dart; lib/widgets/kit/kit_letter.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/search/cohesive_column.dart; lib/pages/search/search_field.dart; lib/pages/reader/speed_read_panel.dart
- folds: none — F-81 (7), measured 2026-10-12
- device_test: none
- shots: none
- extra_gates: none
- notes: Measured (flutter_test, the bundled SourceSerif4-Variable, axes wght 200-900 and opsz 8-20-60): `Library` at 44/600 lays out 165.8 wide with only `wght` set and 141.9 with `opsz` 44 — less the title's -0.024em, 158 against 134; web's `.ch-title` on the 2026-10-12 sources frame measures ~133 CSS px. `Ask your library a question` 28/600: 376.0 vs 336.4; the manuscript's 19px body: 431.8 vs 400.8. So the cause F-81 (7) asked to prove is proved: `AppTheme.serif` drives only `wght`, while web sets `font-variation-settings: "opsz" N` per role (≈ the size: `.ms-body` 18, `.ob-title` 48, `.proc-title` 16). The fix is one line in `AppTheme.serif` (`opsz` = the size, clamped 8-60) — but NOT alone: serif drawn by flutter_html (the manuscript's html, the summary, letter bodies) has no font-variation support, so the two renderers would then disagree inside one passage (the drop cap's paragraph is a Text, the rest is Html). It needs a way for Html's serif to take the same optical size (an `opsz`-pinned instance of the face for the html bodies, or an Html TextStyle hook) before it lands, then every pair re-shot and the kit goldens re-baselined.
  2026-10-12: built, with no modified face. `AppTheme.serif` drives `opsz` beside `wght` (`serifAxes`: the size clamped 8–60, the browser's auto; a role passes its own where web names one — the reading roles' 18 through `bodyReading`, the drop cap's inherited 18, the search field's 24, speed read's 16, a versal cap at its line's). The html bodies take theirs WITHOUT a font-variation hook: flutter_html builds every block as a `Text.rich` whose spans inherit `DefaultTextStyle`, so `AppTheme.htmlOpticalSize` wraps the manuscript (18, as `.ms-body`), the letter body (17) and the cohesive quote (18) — the drop cap's Text and the Html around it now draw at one size. Measured first (flutter_test, the bundled face): a style naming no `opsz` draws the default outlines, 573.2 wide where opsz 18 is 538.1 (19px line) — every html body was 6.5% wide, not only the titles. An `opsz`-pinned instance of the face was built and NOT used: the OFL reserves the name *Source*, so a modified face must be renamed, and inheritance made it unnecessary. serif_optical_size_test (3); kit goldens type_roles/headers/cards re-baselined, looked at (the serif narrows; nothing else moves). Every pair re-shot after it.

## F-101 · Sources and Settings — the connectors draw their vendors' own marks (web ProviderLogo)
- status: done 2026-10-12
- screen: sources
- route: /sources
- spec: spec/screens/sources.md; spec/screens/settings.md; spec/component-kit.md §5.1
- web: src/shared/ProviderLogo.jsx; src/pages/SourcesBrowse.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/OrganizationPanel.jsx; src/pages/SettingsView.jsx
- flutter: lib/widgets/kit/kit_provider_logo.dart; lib/widgets/kit/kit_shell.dart; lib/widgets/kit/kit_cards.dart; lib/widgets/kit/kit_rows.dart; lib/shared/cloud_providers.dart; lib/pages/sources_page.dart; lib/pages/sources/organization_settings_panel.dart
- folds: none — found by the 2026-10-12 org-scan-wait pair
- device_test: none
- shots: sources; org-scan-wait; folder-contents; settings
- extra_gates: python3 ../NoteLetter-contracts/harness/token_contrast_check.py --target flutter
- notes: Web draws each connector's published brand mark, unmodified and in its own colours (ProviderLogo: the connect card plate at 22, the Import from / Organized folders headers at 14, Settings → Sources' rows at 18 on a white plate); this client drew generic Material glyphs in --fg-muted (a drive-add, a cloud, a document, a box).
  2026-10-12 pairs (frame batch 2, over 1e2da8c..2d32f79, every pair looked at in both themes): sources, org-scan-wait, folder-contents, settings — the vendors' marks MATCH (the Drive mark in its colours in both headers; the white plates).

## F-102 · Sources — an import job row's sub-line names its provider, with the mark (web CloudImportPanel)
- status: done 2026-10-13
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Cloud import; spec/screens/sources.md §Trust & feedback; spec/component-kit.md §4.1; spec/component-kit.md §6.3
- web: src/pages/sources/CloudImportPanel.jsx; src/styles/app-sources-browse.css; src/shared/ProviderLogo.jsx
- flutter: lib/pages/sources_page.dart; lib/widgets/kit/kit_proc.dart; lib/widgets/kit/kit_headers.dart; integration_test/hold_screen_test.dart; test/contract/cloud_sync_tandem_test.dart; test/contract/cooldown_wait_test.dart; test/contract/stream_builder_failure_test.dart
- folds: none — found beside F-101, 2026-10-12
- device_test: none
- shots: import-activity; import-activity-failed
- extra_gates: none
- notes: Web's import-activity and history rows read `{ProviderLogo 12} {provider name} · {path}` under the file name, the status apart; this client's `_JobRow` reads `{status} · {path} · {reason}`. No pair frames an import row (the folder-contents frame is cropped to the picker on web), so the difference is read from the source, not a frame: frame it (a hold that scrolls to Import activity) before changing it.
  2026-10-12, read further: the difference is the whole row, not its sub-line. Web's import-activity and history row is a `.proc-row` card (FileBadge · the file name over `{mark} {provider} · {path}` · the controls and a status pill on the right; the job's error under it as `.proc-error`, a skip's reason as a `.proc-note`, each control's wait and refusal in its own slot); this client's `_JobRow` is a §4.1 source row with the status folded into its subtitle. Frame it first (a hold that scrolls to Import activity — the seed's `old-notes.pdf` job is waiting), then recompose on `KitProcCard`.
  2026-10-13: web framed it (import-activity: Cloud imports with the seed's waiting old-notes.pdf; import-activity-failed: Import history opened — report.docx failed, taxes.pdf imported, its duplicate). Recomposed: `_JobRow` is a `KitProcCard` — the File badge (the MIME's kind) · the file name over `{mark} {provider} · {path}` (`KitProcCard.subtitleLeading`, the vendor mark at 12, new) · the controls as `.set-link`s (KitSettingLink: View · Retry/Import again · Update from source, each with its wait) ahead of the §6.3 pill (`KitProcCard.actions`, new; under the title on a phone) — then the failure's sentence in `.proc-error`'s strip (KitProcAttention with no actions now draws none), a skip's reason as `.proc-note`, each control's refusal slot; a failed card takes the failed edge; skipped/cancelled cards are muted at 0.55 as the reference's. The pill map is web's `PILL` (Needs you · Error, where this said Waiting for you · Failed; tones from `KitProcTone`). The section reads *Cloud imports* (was *Import activity*); `.proc-list` 10 apart; history's day line is `.proc-note`. Holds `import-activity` / `import-activity-failed` scroll the section's header to 32 under the bar, as the reference's shot does.
  2026-10-13, read off the first frames: `SectionHeader`'s note was a loose Flexible, so a one-line note ("0 of 1 imported") shrank to its text and sat mid-row where web's `space-between` puts it at the end — Expanded now (only Sources, Study, For your review and onboarding pass a note; a wrapping note draws as before). History's day line halved the row and wrapped "1 skipped"; the date keeps its width now.

## F-103 · A held send or confirm — how it looks is not ruled (spec 0.5, web full on Ask and the picker, faded on Support)
- status: done 2026-10-13
- screen: ask
- route: /ask
- spec: spec/component-kit.md §6.1; spec/decisions/ADR-145-a-wait-looks-like-a-wait.md; spec/screens/ask.md; spec/screens/sources.md
- web: src/styles/app-kit.css; src/styles/app-support.css; src/styles/signin.css; src/shared/AuthModal.jsx; src/pages/AskView.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/pages/sources/OrganizationPanel.jsx; src/pages/reader/ReorganizeSheet.jsx; src/pages/study/ProgramEditor.jsx
- flutter: lib/widgets/kit/kit_composer.dart; lib/widgets/kit/kit_cards.dart; lib/site/site_sheet.dart; lib/site/auth_modal.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/organization_settings_panel.dart; lib/pages/reader/reorganize_sheet.dart; lib/pages/study/program_editor.dart; test/kit/held_button_test.dart; test/contract/cloud_sync_tandem_test.dart
- folds: none — read off the 2026-10-12 pairs; ruled 2026-10-13 (TODO "RULED 2026-10-13: the spec stands")
- device_test: none
- shots: ask; ask-thread; ask-rail; ask-turn-failed; folder-contents; support; org-scan-wait
- extra_gates: none
- notes: Seen on every Ask pair (the empty composer's send) and the folder-contents pair (Import 0 items with nothing chosen): web draws the held control at full strength, this client at 0.45, as both draw Support's held send. A spec-vs-web disagreement, not adjudicated here (flutter-next §6): rule which look a held send/confirm has, then the clients follow.
  2026-10-13: RULED — the spec stands (ADR-145 §4: every held control at `--held-opacity`, 0.5); web dims Ask's send and the picker's Import and swept its other held controls to the token (web lane, same day). Read before building: the picker's Import and Cancel were already KitButtons at the token; the 0.45 was the composer's send alone (Ask AND Support), which also drew full strength while busy. Every place that was not the token, matched to the web site that moved: the send (0.45 → token, busy held — web disables it in flight); sign-in's submit, ghost and text link and the sign-up modal's Google row and submit (0.6 → token, as signin.css / AuthModal); the connect card (no held look → token, `.connect-card:disabled`); an organized folder's Rescan while scanning or waiting (none → token, `.proc-cancel:disabled`); the sync settings panel while it saves (0.6 → token; web's is 0.5); and the Material FilledButton/OutlinedButton/TextButton held in Material's own disabled grey where web draws `.btn`/`.proc-retry` — the reorganize sheet (Run again · Analyze again · Close · Yes, reorganize · Go back · Reorganize N · Cancel) and the program editor (Save/Create · Start a new unit · Detach · Read this syllabus) are KitButtons now. Left as web leaves them (not §6.1, each web's own figure): filter chip 0.4 (`.browse-chip`), shelf select 0.55 / shelf chip controls 0.4, speed read 0.4, swatch 0.5. held_button_test holds the send, the card and the three sign-in controls to the token.

## F-104 · Search — the explainer's Source-priority row reads default while unset (4.118.0 tandem, ADR-155)
- status: done 2026-10-12
- screen: search
- route: /search
- spec: spec/screens/search.md §Score explainer; spec/api/search.md; spec/decisions/ADR-155-a-chosen-priority-is-stamped.md
- web: src/pages/SearchView.jsx; src/styles/app-kit.css
- flutter: lib/models/search_result.dart; lib/models/cohesive_reading.dart; lib/pages/search/score_explainer.dart; lib/pages/search/result_card.dart; lib/pages/search/cohesive_column.dart; lib/widgets/kit/kit_popover.dart
- folds: 4.118.0 (ADR-155)
- device_test: none
- shots: none
- extra_gates: none
- notes: CHANGELOG 4.118.0's Flutter tandem ("the same row; its Sources priority control may offer Default") was marked queued and never was: no item held it. Every search result and cohesive passage carries `source_priority_set` (bool); while false the explainer's row draws `default · 0.50` (`.pop-default`) in place of the bar, with "You have not weighted this source, so it counts at the default."; true reads "The weight you gave this source."; absent (an older response) draws as before. Default (sending `null`) on the priority control belongs with the control's placement: F-99, blocked on Xavier. No pair frames the open popover (search is framed closed).

## F-105 · Sources and For your review — a run that never started is stalled too (5.3.0, ADR-161)
- status: done 2026-10-13
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Stalled rows; spec/screens/review.md; spec/decisions/ADR-161-a-run-that-never-started-is-stalled.md; spec/data-model.md
- web: src/shared/stalled.js; src/pages/SourcesBrowse.jsx; src/api.js
- flutter: lib/models/document.dart; lib/pages/sources/browse_section.dart; lib/services/firestore_service.dart; lib/state/review_inbox.dart; test/contract/review_inbox_test.dart; test/contract/composition_4_98_test.dart
- folds: 5.3.0
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/job_status_check.py
- notes: CHANGELOG 5.3.0 Flutter tandem (backend signal 11:52Z, contracts 3efed6e): `processing_stalls_at` is meaningful while status ∈ {queued, processing}; one comparison. `Document.isStalled` accepts `queued` (a `queued` with no stamp — a passage, a pre-5.3.0 row — is never stalled); `browse_section.dart`: the Stalled label and `fail` tone checked before the Queued label, the never-started sentence ("Indexing never started. Waiting will not help — Retry to start it.", ruled 2026-10-13; processing keeps its own), Retry as the primary, the row's 15 s tick while `queued` too; `firestore_service.dart` `subscribeAttentionDocuments` reads `queued`; `review_inbox.dart`'s clock ticks while a `queued` row is held. Tests: the row (Stalled · fail · the sentence · Retry · no Cancel; a fresh queued still waits; a stalled processing keeps its sentence) and the needs-decision set (stalled queued in; fresh or unstamped out). The three new api/documents fixture cases are requests this client's builders already construct. No pair: the seed holds no stamped `queued` row, so no frame changes; the frames re-shot over this code show the seed's own queued row still Queued.

## F-106 · Sources and For your review — an organization suggestion is a .proc-row card, with batch select (web SuggestionCard, SuggestionQueue)
- status: done 2026-10-13
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Suggestion review queue; spec/screens/review.md; spec/component-kit.md §4.1; spec/component-kit.md §6.3
- web: src/pages/sources/SuggestionCard.jsx; src/pages/sources/OrganizationPanel.jsx
- flutter: lib/pages/sources/suggestion_queue.dart; lib/widgets/kit/kit_proc.dart; lib/models/organization_suggestion.dart; lib/pages/sources_page.dart; integration_test/hold_screen_test.dart; test/contract/cloud_sync_tandem_test.dart; test/contract/stream_builder_failure_test.dart
- folds: none — found by F-102's import-activity pairs, 2026-10-13 (no frame had shown a suggestion before)
- device_test: none
- shots: folder-contents; import-activity; import-activity-failed
- extra_gates: none
- notes: The import-activity frames (F-102) were the first to show a pending suggestion, and its card was not web's: a §5.1 card titled by type ("Move a file") with a "60% SURE" status pill, the reason, then "Move \"taxes.pdf\" → /Docs/Finance", and no selection — the spec's "Approve/decline per card + batch select (≤20/call)" had no batch at all. Recomposed on KitProcCard: the selection box in the badge slot; the title the action with its subject in bold (`KitProcCard.titleSpans`, new: Move/Copy (Notion) **file** → to · Place in **to** · Adopt README edits · Reorganize this document); the sub-line `from {from_path} · {reason}`; a README card's proposed charter and its adoption sentence under it (`KitProcCard.infoExtra`, new); the confidence as a work-tone pill with no spinner (`KitProcPill.spin`, new); Approve ("Working…" while busy) — or *Review plan…*, which opens the reader, for `reorganize` (INV-13: approving never executes it) — and Decline under the row, at its end on a phone. The queue holds the batch: chosen boxes put "Approve N · Decline N" beside the count, one resolve at a time holds every control, ids go 20 a call, the selection clears on success, and a refusal is §14.2 under the list as web's notice. Sources' eyebrow reads *Suggestions* (was *Organization suggestions*). The approval OUTCOME rows are web's `ApprovalOutcome` too: a badge-less `.proc-row` (KitFolderCard, its sub-line optional now) — the title, the *Applying* work pill or *Clear*, the worker's sentence under it; they were §4.1 rows (no frame shows one).

## F-107 · Pairs drawn through §7's file — ask, study and onboarding are judged against kit_empty.dart (5aa)
- status: done 2026-10-14
- screen: study
- route: /study
- spec: spec/component-kit.md §7
- web: src/shared/EmptyState.jsx; src/styles/app-kit.css; src/styles/app-study.css; src/styles/app-onboarding-wizard.css
- flutter: lib/widgets/kit/kit_empty.dart
- folds: TODO "screenshot_pair_check misses study's pair, because its queue item does not list kit_empty.dart"
- device_test: none
- shots: ask; study; onboarding
- extra_gates: harness/screenshot_pair_check.py
- notes: STALE-PAIR reads a done item's `flutter:` files, and a pair is judged only against the files its items list. These three frames DRAW kit_empty.dart — Ask's and Study's §7 (KitEmptyState, KitSuggestion, Study's move group) and onboarding's KitMark and ruled KitNumberedMove — and no item naming them listed it, so 9521e0b moved Study's frame with the gate green; only support's and sources' items listed the file. This item adds the edge and nothing else (a done item is never edited). The class is the gate's: a pair drawn through a shared file its items do not list is invisible to it, and only a list kept by hand closes each one.

## F-108 · Study — the program editor composed from the kit, as web's ProgramEditor (study-new, study-edit)
- status: done 2026-10-14
- screen: study-new
- route: /study/new
- spec: spec/screens/study.md §Create / edit a program; spec/screens/study.md §Syllabus; spec/component-kit.md §4.1; spec/component-kit.md §18
- web: src/pages/study/ProgramEditor.jsx; src/styles/app-study.css; src/styles/app-scripture.css; src/styles/app-responsive.css
- flutter: lib/pages/study/program_editor.dart; lib/widgets/kit/kit_form.dart; lib/models/study.dart; test/kit/program_editor_test.dart; test/kit/stepper_test.dart; tool/seed_study_program.py
- folds: TODO "The program editor (/study/new, /study/:id) is plain Material, against web's card-and-row layout, and no pair covers it"
- device_test: none
- shots: study-new; study-edit
- extra_gates: harness/screenshot_pair_check.py; harness/confirm_check.py
- notes: Built in ba5fd86 (kit_form.dart; KitStepper to web's .stepper; sunken fields). Frames 2026-10-14 over web 7ef365c's study-new/study-edit: the sections, rows, sunken fields and foot MATCH web's phone frames. One difference booked against WEB, not here: web's `.st-picker-h .ct` has no rule (`.ct` is styled only inside `.st-sec-h`), so its "0 of 10 chosen" renders in the body sans 16 at --fg; this client draws it as `.st-sec-h .ct` (mono 11, --fg-subtle).

## F-109 · Settings — the summary style's reset confirm is framed (summary-reset-confirm), and its body follows the theme
- status: done 2026-10-14
- screen: summary-reset-confirm
- route: /settings
- spec: spec/screens/settings.md §Summaries; spec/component-kit.md §18
- web: src/pages/SettingsView.jsx; scripts/theme-shots.mjs
- flutter: lib/pages/settings/summaries_section.dart; lib/widgets/kit/kit_confirm.dart; integration_test/hold_screen_test.dart
- folds: TODO "Flutter frames owed for web-4's third pass" — the reset confirm
- device_test: none
- shots: summary-reset-confirm
- extra_gates: harness/screenshot_pair_check.py
- notes: The hold (f2fd1ce) writes the custom style through fn_summary_settings, presses Reset to default and holds the §18 panel; leaveState cancels it and removes the style. Its first frame found a defect: the panel's body was built in the SECTION's context, so its --fg-subtle was resolved once, in whichever theme was active when it opened — the light frame drew the dark theme's grey on white and read blank. It is a Builder now, resolved in the panel (the other three bodyWidget sites already were). The panel sits centred on a phone where web's sits under the header — every §18 panel on this client does (booked, not changed here).

## F-110 · The four held cooldowns are framed (letter-send-wait, study-wait, retry-wait, sync-wait)
- status: done 2026-10-14
- screen: letter-send-wait
- route: /letters
- spec: spec/component-kit.md §6.1; spec/screens/letters.md; spec/screens/study.md; spec/screens/sources.md
- web: scripts/theme-shots.mjs; src/pages/LettersView.jsx; src/pages/StudyView.jsx; src/pages/SourcesBrowse.jsx
- flutter: integration_test/hold_screen_test.dart; tool/seed_wait_states.py; lib/pages/letters_page.dart; lib/pages/study_page.dart; lib/pages/sources_page.dart; lib/pages/sources/browse_section.dart; lib/widgets/kit/kit_wait.dart; lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_program_card.dart; lib/widgets/kit/kit_proc.dart
- folds: TODO "Flutter frames owed for web-4's third pass" — "Study now · 0:42", "Send now · 0:42", "Retry · 4:00", "Sync now · m:ss"
- device_test: none
- shots: letter-send-wait; study-wait; retry-wait; sync-wait
- extra_gates: harness/screenshot_pair_check.py
- notes: Web frames all four since 7ef365c. The holds (7c927f2, 91af131) press the control into the server's own 429 — tool/seed_wait_states.py stamps each cooldown field first, AHEAD of now (the app is built between the seed and the press, and a 60s window stamped "now" had lapsed: the first study-wait press was accepted), and retry-wait presses seed-doc-error's Retry ("corrupt.docx"), not the overlay scan's — and requires the held label counting down. Each frame carries the held label and the server's sentence, as web's do; the number differs (web shoots at the refusal, this client after the settle check). The frames found two defects, fixed before these were taken: the Letters card ellipsised its own countdown ("Send now · 0:…", F-112) and the study card's composition (F-111).

## F-111 · Study — a program card is web's .st-prog (study-wait)
- status: done 2026-10-14
- screen: study-wait
- route: /study
- spec: spec/screens/study.md §Composition; spec/component-kit.md §12; spec/component-kit.md §6.1
- web: src/pages/StudyView.jsx; src/styles/app-study.css; src/shared/Notice.jsx
- flutter: lib/pages/study_page.dart; lib/widgets/kit/kit_program_card.dart; lib/widgets/kit/kit_notice.dart; test/kit/study_card_test.dart
- folds: none (found by this item's own frame)
- device_test: none
- shots: study-wait; study
- extra_gates: harness/screenshot_pair_check.py
- notes: Found by the study-wait frame beside web's PHONE frame: every earlier study pair was read against web's desktop frame, where the controls sit in a side column and their order cannot be seen. Built in 68a3c0d (KitProgramCard, KitStudyChip, KitStudyMeter): the controls before the notice, the notice in KitNotice's own glyph (the page had passed Icons.error_outline over it), the hint under a rule with its alert glyph, the chip wrapping with the title, the mono figure, a 2-high --seal meter on --rule, ON/OFF beside the switch, an off program on --bg. The `study` frame is the seed's empty state (no program); the card is framed by study-wait. study-wait MATCHES web's phone frame.

## F-112 · KitActionFlow — a grown row cut a held label's countdown (letters, letter-send-wait)
- status: done 2026-10-14
- screen: letters
- route: /letters
- spec: spec/component-kit.md §6.1
- web: src/styles/app-responsive.css; src/pages/LettersView.jsx
- flutter: lib/widgets/kit/kit_controls.dart; test/kit/action_flow_wait_test.dart
- folds: none (found by the letter-send-wait frame)
- device_test: none
- shots: letters; letter-send-wait; letter-reader
- extra_gates: harness/screenshot_pair_check.py
- notes: ae12688. The flow floored a child's natural width (and a share a hair over one), and a real font's width is fractional, so "Send now · 0:42" (158.3) got 158 and ellipsised its countdown. Naturals are rounded up to the pixel before the lines are planned; shares are still floored. The test loads the app's real faces (the test font's glyphs are whole pixels and cannot show it) and sweeps 280–380 by quarter pixels.

## F-113 · Sources — 5.9.0: a synced folder is sent with its name and its chip draws it
- status: done 2026-10-14
- screen: sources
- route: /sources
- spec: spec/api/cloud-storage.md §fn_import_from_cloud; spec/api/cloud-storage.md §fn_sync_settings; spec/screens/sources.md §Sync settings panel
- web: src/api.js; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/styles/app-kit.css
- flutter: lib/services/api.dart; lib/models/cloud_integration.dart; lib/pages/sources/sync_folder_picker.dart; lib/pages/sources/sync_settings_panel.dart; lib/state/cloud_notifier.dart; test/contract/sync_folders_test.dart
- folds: CHANGELOG 5.9.0 Flutter tandem
- device_test: none
- shots: none
- extra_gates: none
- notes: 16ad9ed + e5f2bad (as web 5876fb4 builds it: the picker seeded with the stored names, a listed name clipped at 200, a long name ellipsised in its pill via KitTag `clip`). Seen on a device through the look-only hold `sync-folders-saved` (99114d0): a folder saved from the picker through the dev shim's real fn_sync_settings drew as "Docs" beside the seed's unnamed "gd-root-docs". Web has no frame of it. Not followed: web's chip title is the name; the spec says the whole id — this client keeps the id (reported).

## F-114 · Library — the letter chip on Home's named shelves and the Shelves index cards; the folder chip's tooltip (Xavier's rulings 2026-10-14)
- status: done 2026-10-14
- screen: library-letter-chips
- route: /
- spec: spec/screens/library.md §The letter chip; spec/component-kit.md §21; spec/component-kit.md §6.3; spec/screens/sources.md §Sync settings panel
- web: src/shared/ShelfLetterChip.jsx; src/pages/LibraryHome.jsx; src/pages/ShelvesView.jsx; src/styles/app-shelves.css; scripts/theme-shots.mjs
- flutter: lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_shelf.dart; lib/widgets/kit/kit_cards.dart; lib/pages/library_page.dart; lib/pages/tags_page.dart; lib/state/settings_notifier.dart; lib/models/newsletter_settings.dart; lib/services/firestore_service.dart; lib/pages/sources/sync_settings_panel.dart; test/kit/shelf_letter_chip_test.dart; test/contract/sync_folders_test.dart; tool/seed_letter_chips.py
- folds: CHANGELOG none (UI-only, contracts a302239); TODO "the folder chip's tooltip, name or id"
- device_test: signs in and reaches the library
- shots: library-letter-chips; library-letter-cards; library-letter-off; shelves-letter-chips; shelves-letter-off
- extra_gates: harness/screenshot_pair_check.py
- notes: f1fd8ed (KitLetterChip: lead → "Lead" §6.3 positive, muted → "Muted" §6.3 idle, mixed/absent/unknown none; none unless settings/newsletter holds enabled: true — absent, unread and failed are off; Home's named KitShelfUnit head at its trailing edge, the Shelves index card's foot, never Home's cards) and 82e1f35 (the folder chip's tooltip is its name, the whole id without one). f1fd8ed also stops reading an absent `enabled` (and no settings document) as ON — web reads `Boolean(data.enabled)`. Holds 8f1446d over tool/seed_letter_chips.py, web 91026a9's data.

## F-115 · Five rulings of 2026-10-14 (web follow-up 3): no passage figure without a count, the compact track, a steady held Unpin, Stalled and Retry on Activity
- status: done 2026-10-14
- screen: activity-retry-error
- route: /activity
- spec: spec/screens/library.md §States; spec/component-kit.md §6.8; spec/component-kit.md §4.2; spec/screens/letters.md; spec/screens/activity.md §The row; spec/screens/activity.md §Where a row leads
- web: src/shared/passageFigure.js; src/shared/stalled.js; src/pages/ActivityView.jsx; src/pages/letters/PinnedSources.jsx; src/styles/app-responsive.css; scripts/theme-shots.mjs
- flutter: lib/shared/passage_figure.dart; lib/shared/stalled.dart; lib/pages/activity_page.dart; lib/pages/letters/pinned_sources.dart; lib/pages/library_page.dart; lib/pages/sources/browse_section.dart; lib/pages/sources/shelf_books.dart; lib/pages/tags/shelf_page.dart; lib/pages/study/program_editor.dart; lib/widgets/kit/kit_reading.dart; lib/widgets/kit/kit_rows.dart; lib/widgets/kit/kit_shelf.dart; test/kit/rulings_2026_10_14_test.dart; tool/seed_followup3.py
- folds: TODO F3 (Activity Retry); TODO "a complete source with no count"; TODO ".ms-type-seg / .ob-seg"; TODO ".pinned-unpin pulse"
- device_test: signs in and reaches the library
- shots: library-uncounted; sources-uncounted; reader-type; onboarding-letter; letters-unpin-held; activity-stalled; activity-retry-error; activity
- extra_gates: harness/screenshot_pair_check.py
- notes: d243862 (the five rulings, contracts b39e72a, web 088099c). Holds and tool/seed_followup3.py (uncounted | pinned | stalled, one at a time, --remove) frame web 7f85b50's seven states; `activity` is re-paired because the seed's failed document now carries Retry. In progress until those pairs and the device run land.

## F-116 · Activity — a stalled document's row carries Retry too (Xavier's ruling, 2026-10-17)
- status: done 2026-10-16
- screen: activity-stalled
- route: /activity
- spec: spec/screens/activity.md §Where a row leads
- web: src/shared/stalled.js; src/pages/ActivityView.jsx; scripts/theme-shots.mjs
- flutter: lib/pages/activity_page.dart; test/kit/rulings_2026_10_14_test.dart
- folds: TODO "Retry on Activity's stalled row" (web follow-up 3 FOUND)
- device_test: signs in and reaches the library
- shots: activity-stalled; activity-retry-error
- extra_gates: harness/screenshot_pair_check.py
- notes: 1d561c1 (contracts 6eb5761, web 2a61e3a): Retry while the document is `error` OR stalled, on the newest row per document. activity-retry-error's 404 now reads "This source no longer exists." (5.9.1, contracts f37033b), drawn verbatim — no code. Web references 522f68b / e75978b.

## F-117 · Source file view — 5.10.0/5.10.1: a stitched scroll is read tall and captioned; the hint under Add an image set (ADR-170)
- status: done 2026-10-17
- screen: source-stitched
- route: /sources
- spec: spec/component-kit.md §15.1; spec/screens/sources.md §Endpoints used; spec/screens/reader.md §Original; spec/decisions/ADR-170-a-scroll-is-one-picture.md
- web: src/shared/SourceFile.jsx; src/styles/app-source.css; src/shared/ImageSetChoice.jsx; scripts/theme-shots.mjs
- flutter: lib/widgets/kit/kit_overlay.dart; lib/models/document.dart; lib/pages/reader/original_panel.dart; lib/pages/sources/source_sheet.dart; lib/widgets/file_uploader.dart; tool/seed_overlay_sources.py; integration_test/hold_screen_test.dart; test/kit/scroll_stitch_test.dart (new)
- folds: 5.10.0; 5.10.1
- device_test: signs in and reaches the library
- shots: source-stitched
- extra_gates: harness/screenshot_pair_check.py
- notes: An image set whose pages are one continuous scroll is re-typed `image` with a `stitch` record by the run that joins them (backend 5d0a3ac, live). §15.1 rule 4: an image more than 2x as tall as wide renders at the stage's width (never past its own pixels) in a stage that scrolls, DECODED DOWNSAMPLED to the drawn width (cacheWidth — a 1290x40000 PNG is 200 MB of pixels at full size); caption "Joined from N screenshots of one scroll." from stitch.frame_count. The hint sentence "Screenshots of one long scroll are joined into one picture." (verbatim) under Add an image set. Flutter keeps its own set entry — the web One/Separate question is web's (sources.md). Web references d2e66bf, frames source-stitched.web.*.

## F-118 · Update in place (5.12.0, ADR-172): the auto_update switch, Update from {Provider} in the Original section, the narrower Update-from-source confirm
- status: done 2026-10-17
- screen: reader-original-update
- route: /reader
- spec: spec/screens/sources.md §Sync settings panel; spec/screens/reader.md §Source freshness; spec/screens/reader.md §Supersession confirm; spec/decisions/ADR-172-a-changed-file-updates-its-document.md
- web: src/pages/reader/UpdateFromSourceBar.jsx; src/pages/reader/OriginalPanel.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/shared/SupersessionConfirm.jsx; src/api.js; scripts/theme-shots.mjs
- flutter: lib/pages/reader/update_from_source_bar.dart; lib/pages/reader/original_panel.dart; lib/pages/reader/supersession_confirm.dart; lib/pages/reader/source_freshness.dart; lib/pages/sources_page.dart; lib/pages/sources/sync_settings_panel.dart; lib/models/cloud_integration.dart; lib/services/api.dart; lib/state/cloud_notifier.dart; test/contract/update_in_place_test.dart; test/contract/supersession_confirm_test.dart; test/contract/cloud_sync_tandem_test.dart; test/contract/api_requests_test.dart
- folds: 5.12.0
- device_test: signs in and reaches the library
- shots: reader-original-update; sync-auto-update; sync-folders
- extra_gates: harness/screenshot_pair_check.py
- notes: Code, tests and pin landed by session update-in-place (b635ca54) with Tier 1 green (1523/1523 incl. pin). Pairs and device run proven 2026-10-17 by the flutter lane: the three pairs (web references reader-original-update / sync-auto-update new, sync-folders re-shot — the web panel is now taller than a laptop screen, so that frame crops to the chip group), with the 37 pairs a37f0e1 staled, every frame looked at in both themes; the whole device run 26/26 on a fresh boot. The original-update hold now scrolls only when the button is below the fold: pulled to 0.3 it framed Original under a lit Listen. `lib/build_info.dart` is off this list: it is the pin, which moves every version, and a `lib/` path here re-dated these three pairs at each pin bump (5aa reads `lib/`). Seen in these frames and booked as F-119, not fixed here: the auto-sync switch reads "Automatic sync" where spec and web say "Sync new files automatically". The Original-section button is beneath the panel intro, before the file; the switch row sits under the auto-sync row with its caption. Update from source no longer reads study membership (SupersessionConfirm.updateStudy = false).

## F-119 · Sync settings panel — the auto-sync switch's name, its last-sync line, and both switches from the kit (sources.md §Sync settings panel)
- status: done 2026-10-17
- screen: sync-auto-update
- route: /sources
- spec: spec/screens/sources.md §Sync settings panel; spec/component-kit.md
- web: src/pages/sources/SyncSettingsPanel.jsx
- flutter: lib/pages/sources/sync_settings_panel.dart; lib/models/cloud_integration.dart; test/contract/update_in_place_test.dart
- folds: none
- device_test: signs in and reaches the library
- shots: sync-auto-update; sync-folders
- extra_gates: harness/screenshot_pair_check.py
- notes: Seen by the flutter lane in F-118's frames; done 2026-10-17 (code 287bb16). The first switch reads "Sync new files automatically", the spec's and web's (it said "Automatic sync"). The group's last sync is the panel's OWN line, `lastSyncedLine()`: "Last synced Jul 3, 1:00 AM", web's fmtLastSync to the minute, with a no-break space before AM/PM, or "Never synced automatically". `CloudIntegration.lastSyncLabel` ("Synced Nd ago") is untouched, because it is also the connect card's subtitle, and retry-wait and sync-wait must not move unseen. Both switches are `KitSwitch` in web's `.src-toggle` rows: 9px vertical padding and a `--rule` above each row. Two fixes came from looking at the first frames: an Expanded AUTO-SYNC label had broken "1:00 / AM" over two lines, and web's rows carry a rule that Flutter's lacked. Re-shot: the 22 pairs the items naming these two files list. Only sync-auto-update and sync-folders moved; the other 20 differ from HEAD only in the clock and measured counts. Device run 26/26 on a fresh boot. Web's connect-card subtitle (invitation vs account) is booked separately as a spec/web item, not here.
- placed: after F-118

## F-120 · The support footer ends each screen's scroll (5.19.0, ADR-173, INV-22 placement)
- status: done 2026-10-18
- screen: support
- route: /support
- spec: spec/decisions/ADR-173-the-support-footer-ends-the-scroll.md; spec/invariants.md §INV-22; spec/component-kit.md §1.1; spec/component-kit.md §1.4; spec/component-kit.md §13; spec/screens/support.md §The footer
- web: src/shell/PrimaryScroll.jsx; src/App.jsx; src/styles/app-kit.css; tests/contract/support-footer.test.js
- flutter: lib/widgets/support_shell.dart; lib/widgets/kit/kit_frame.dart; lib/widgets/kit/kit_composer.dart; lib/widgets/kit/kit_support_footer.dart; lib/pages/chat_page.dart; lib/pages/support_page.dart; lib/pages/reader_page.dart; lib/pages/letter_settings_page.dart; test/contract/support_footer_test.dart; integration_test/device_run_test.dart
- folds: 5.18.0; 5.19.0
- device_test: the support footer ENDS every screen, reader included
- shots: support; ask-thread; activity; settings; reader-history; shelves-letter-chips
- extra_gates: harness/screenshot_pair_check.py
- notes: Xavier, 2026-10-17: the footer goes at the bottom of each screen's scroll, out of the way but present. The shell (SupportShell) composes it once and hands it down through KitShellFooter. The kit's primary scroll (KitPage, KitScrollView, KitLoadingPage, and the reader's KitShellFooterSliver) renders it last, in a body that fills the pane, so short content keeps it at the pane's bottom edge. Any other scroller is .secondary(reason:) or marked `// scroll-secondary:`. Ask and Support reserve their measured dock plus its 44px scrim, so the footer rests above the composer and the dock stays docked. All 65 authenticated pairs were re-shot 2026-10-18 and looked at in both themes. Web's 5.19.0 frames were not released when these were shot (web 5.17.0 at f7a0a0f): re-copy with tool/web_frames.sh once web pushes its frames, and look again at every pair whose web frame moved (5aa says STALE-WEB-FRAME). 5.18.0 is pin-only.

## F-121 · Resumable upload for large files (F-c): chunked Content-Range PUTs to resumableUrl instead of one bare PUT of the whole file in memory
- status: done 2026-10-18
- screen: sources
- route: /sources
- spec: spec/api/uploads.md; spec/invariants.md §INV-08; spec/decisions/ADR-050-large-uploads-are-resumable-sessions.md
- web: src/api.js
- flutter: lib/state/upload_notifier.dart; lib/services/api_service.dart; lib/services/resumable_upload.dart (new); test/contract/resumable_upload_test.dart (new)
- folds: none
- device_test: sources composes from the kit, in the contract order
- shots: none
- extra_gates: none
- notes: From the iOS inventory (reports/ios.md, 2026-10-18): Swift sent video/* through the resumable session (UploadViewModel.swift:26, ResumableUpload.swift); Flutter reads the whole file into memory and sends one bare PUT (upload_notifier.dart:169-175), so a long recording can fail or run out of memory. Port web api.js's resumable path: start the session at resumableUrl, PUT chunks with Content-Range, resume from the server's Range on a dropped chunk. Which sizes and kinds take it: web's rule, not a new one. About a day. Do it with or before the share extension's video branch.

## F-122 · Share extension on iOS (F-a): a native Share target that files a link, an image set or one file into the library, signed in through the app's own keychain group
- status: done 2026-10-18
- screen: share-extension
- route: none
- spec: spec/api/ingest.md; spec/api/uploads.md; spec/features/scroll-stitch.md; spec/features/audio-ingestion-and-closed-upload-set.md; spec/decisions/ADR-151-a-playlist-link-is-detected-as-a-playlist.md; spec/decisions/ADR-120-a-bare-address-is-a-link.md
- web: none
- flutter: ios/Share/ShareViewController.swift (new); ios/Share/ShareView.swift (new); ios/Share/EmulatorConfig.swift (new); ios/Share/Info.plist (new); ios/Share/Share.entitlements (new); ios/Runner/Runner.entitlements (new); ios/Runner/AppDelegate.swift; ios/Podfile; ios/Runner.xcodeproj/project.pbxproj; ios/RunnerTests/ShareActivationRuleTests.swift (new); ios/RunnerUITests/ShareActivationTests.swift (new); tool/add_share_target.rb (new); lib/services/share_config_channel.dart (new); lib/main.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Ruled first by Xavier (iOS retired 2026-10-17; fresh App Group and keychain group 2026-10-18). Port of NoteLetterShare, read-only from NoteLetter/: accepts one web link (never file://), 1-20 photos as one image set (the card carries sources.md's scroll-stitch sentence), or one file of the closed upload set; no selected text. iOS: target xp.NoteLetter.Flutter.Share (team 3SA8A2JP3T, -allowProvisioningUpdates, no vendor console); App Group group.xp.NoteLetter.Flutter and keychain group 3SA8A2JP3T.xp.NoteLetter.Flutter.shared on Runner and the extension; a Podfile target with FirebaseAuth; Runner's own GoogleService-Info.plist (the iOS API key has no bundle restriction, checked read-only 2026-10-18); useUserAccessGroup in AppDelegate before FlutterFire touches Auth, which signs every existing Flutter user out ONCE. Debug: the app writes its emulator config into the group's defaults and the extension reads it, so a Debug extension refuses prod as the app does. Swift to port: ShareViewController + ShareView (~400 lines) and what they compile (~1,500: APIClient, UploadClient, ResumableUpload, UploadTypes, URLContentType, PlaylistAnswer, EndpointBudgets, EmulatorConfig, KitFailure, KitWait, Theme, Typography, Spacing, FontLoader, AppCard, buttons). Lessons (TODO): a Files item is a FILE, never a link; the activation rule is the narrowed add943d one, verbatim (BETWEEN silently dropped the whole rule). SPEC GAP: the sheet's own copy exists only in Swift (Sign in required + its line; Couldn't read what you shared; Can't add this file; Nothing to share + This kind of content isn't supported yet.; Add to NoteLetter; Files as: {kind}; N photos selected; Title (optional); Upload Photos; Upload File; Uploaded N photo(s).; Uploaded {name}.; the It couldn't be read — {reason} prefix). Ported verbatim and reported; the spec should own them. Proof: a simulator device run driving the extension from Safari, Files and Photos (port of DeviceRun/ShareActivationTests), activation-rule tests in both directions, Tier 1, head_build_check. Real iPhone: the coordinator's. About 3 days.

## F-123 · Share on Android (F-a): SEND and SEND_MULTIPLE into a Dart share screen on upload_notifier
- status: blocked: device proof owed: the cloud VM has no KVM, so no emulator run of SEND (a link, one image, many images, one file of the closed set); built (debug APK from a clean HEAD) and widget-tested there — report ../.claude/cloud/reports/f-123.md
- screen: share-extension
- route: /share
- spec: spec/api/ingest.md; spec/api/uploads.md; spec/features/scroll-stitch.md
- web: none
- flutter: android/app/src/main/AndroidManifest.xml; android/app/src/main/kotlin/xp/NoteLetter/Flutter/MainActivity.kt; lib/services/share_intake.dart (new); lib/shared/share_content.dart (new); lib/pages/share_page.dart (new); lib/router.dart; lib/main.dart; lib/services/analytics.dart; lib/state/upload_notifier.dart; test/contract/share_page_test.dart (new); test/contract/support_footer_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: UNBLOCKED 2026-10-19 by Xavier: it was blocked only because the Mac had no Android SDK; the cloud VM has one (/opt/android-sdk), so it is built there (no KVM there: an emulator run is owed). Intent filters for a text/plain link, image/* (one and many, up to 20 as one image set) and the closed upload set's MIME types; a share-intent plugin (receive_sharing_intent or share_handler); a /share screen composed from the kit, same states and copy as the iOS extension (same SPEC GAP). BLOCKED for proof on this Mac: no Android SDK or emulator is installed (sdkmanager only), so the Android half can be written and widget-tested but not built or run until an SDK is installed (several GB; disk 12 GB free). About 1-2 days.

## F-124 · Original draws a PDF, and a device shares the original file out (F-d)
- status: done 2026-10-18
- screen: reader-original-update
- route: /reader
- spec: spec/component-kit.md §15.1; spec/screens/reader.md §Original
- web: src/shared/SourceFile.jsx; src/styles/app-source.css
- flutter: lib/widgets/kit/kit_overlay.dart; lib/widgets/kit/kit_pdf_stage.dart (new); lib/pages/reader/original_panel.dart; lib/pages/sources/source_sheet.dart; lib/shared/share_original.dart (new); pubspec.yaml; test/kit/pdf_stage_test.dart (new); CLAUDE.md
- folds: none
- device_test: the reader opens the source file
- shots: reader-original-update; source-file; source-file-stage; source-stitched
- extra_gates: harness/screenshot_pair_check.py
- notes: From the iOS inventory (reports/ios.md §4): Swift drew a PDF inline (PDFKit) and shared the original (ShareLink); Flutter named the PDF and drew nothing (CLAUDE.md's §15.1 deviation, F-82). (1) §15.1's stage draws a PDF as web's .pdf-stage does: pages on white sheets in a stage that scrolls, capped at 720, padding 18 on a phone. Rendered by pdfx (PDFKit on iOS, PdfRenderer on Android), page by page as they scroll in; the Flutter web build keeps the sentence. A PDF that cannot be opened falls back to rule 1's sentence. (2) The toolbar gains Share on iOS and Android, a device capability web lacks (recorded with 'Add an image set' in CLAUDE.md's deviations): the file itself, downloaded to a temp file under its own name, through share_plus, not the 15-minute signed URL Swift shared. Size: about a day of code. The re-shoot is about 23 pairs, because kit_overlay.dart and pubspec.yaml are listed by many done items; only four change on screen. Frames wait for the coordinator's Release build signal; the device run does not.

## F-125 · Camera-roll sweep (F-b, INV-14): S1 (native bridge), S2 (ledger and service), S3 (screens, foreground start) and S4 (background) done on iOS; S5 (Android) waits for F-123's SDK
- status: blocked: device proof owed: S1-S4 (iOS) and S5a-S5c (Android) are built; the Android half has run on no device (the cloud VM has no KVM) — notes say what to run
- screen: settings
- route: /settings
- spec: spec/features/camera-roll-sweep.md (§5 background time, 5.24.0); spec/screens/settings.md §Camera-roll sweep card; spec/screens/sources.md §Camera-roll sweep; spec/component-kit.md §23; spec/invariants.md §INV-14; spec/api/uploads.md
- web: none
- flutter: lib/services/camera_sweep_bridge.dart; ios/Runner/CameraSweep/; ios/Runner/AppDelegate.swift; ios/Runner/Info.plist; lib/services/api.dart (createCaptureSession); lib/services/sweep_ledger.dart; lib/services/camera_sweep_service.dart; lib/services/firestore_service.dart (findCapture); lib/state/camera_sweep_host.dart; lib/services/sweep_uploader.dart; lib/services/sweep_background.dart; ios/Runner/CameraSweep/CameraSweepUploader.swift; ios/Runner/CameraSweep/SweepBackgroundTask.swift; lib/pages/sources/camera_roll.dart (F-146 redrew S3 in D); lib/pages/settings_page.dart; lib/pages/sources_page.dart; lib/router.dart; lib/app_providers.dart; lib/services/analytics.dart; android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/AssetIdentity.kt (new); android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/CameraSweepChannel.kt (new); android/app/src/test/kotlin/xp/NoteLetter/Flutter/camerasweep/AssetIdentityTest.kt (new); android/app/src/main/kotlin/xp/NoteLetter/Flutter/MainActivity.kt; android/app/src/main/AndroidManifest.xml; android/app/build.gradle.kts; android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/SweepUploader.kt (new); android/app/src/test/kotlin/xp/NoteLetter/Flutter/camerasweep/SweepUploaderTest.kt (new); android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/SweepBackground.kt (new); lib/services/sweep_words.dart (new); lib/main.dart; lib/services/camera_sweep_service.dart; lib/services/sweep_ledger.dart; pubspec.yaml; test/contract/camera_sweep_android_wiring_test.dart (new); test/contract/camera_sweep_service_test.dart; test/contract/camera_sweep_screens_test.dart; test/contract/sweep_fakes.dart
- folds: none
- device_test: integration_test/sweep_bridge_test.dart via tool/sweep_bridge_test.sh (S1, no emulator); integration_test/sweep_service_test.dart via tool/sweep_service_test.sh (S2, emulator); ios/RunnerTests/CameraSweepBridgeTests.swift; integration_test/sweep_tray_test.dart via tool/sweep_tray_test.sh (S3, emulator: the screens driven by taps, the change observer, launch); integration_test/sweep_background_test.dart via tool/sweep_background_test.sh (S4, emulator + tool/sweep_hold_proxy.py: the task's run, its expiry with a session in flight, an upload that lands while the app is away); ios/RunnerTests/CameraSweepUploaderTests.swift
- shots: none
- extra_gates: harness/endpoint_reach_check.py
- notes: S5c DONE 2026-10-20 (contract 5.26.1; cloud lane, built and tested, device proof OWED): the sweep is ON for Android (CameraSweepBridge.isAvailable). The background pass is WorkManager periodic work xp.NoteLetter.Flutter.camerasweep.refresh with iOS's conditions (network, charging, first run an hour out), on the same channel (attach, setScheduled; run, expire). With the app alive the app engine's host runs it; with the app gone the job starts an engine on sweepBackgroundMain (lib/main.dart: _boot, then CameraSweepHost.forApp with observeLifecycle false, no widgets) and destroys it when the pass ENDS; a stop sends expire and 2 s. Android's ledger is its own SharedPreferences file (camera_sweep_ledger), never DataStore, which allows one instance per file per process and the background engine is a second. The three sentences naming iOS/iCloud are Android's own (SweepWords, chosen once in forApp; 5.26.1). camera_sweep_android_wiring_test reads the Kotlin: channel names, every method answered, the entrypoint kept, the permissions, the bundled model, the bare PUT (mutation-checked), the conditions. DEVICE (owed, an emulator with KVM or a phone, through tool/dev.sh): turn the sweep on and answer the prompt full and limited; a screenshot and a photographed page are candidates and a plain photo is not; approve one and see it land (and its row after killing the app mid-upload); adb shell cmd jobscheduler run -f xp.NoteLetter.Flutter <job id> (or WorkManager's diagnostics) with the app dead runs a pass in a background engine. DEBUG EDGE: if the background engine boots first, the app engine's useFirestoreEmulator may throw (settings already set) — debug only. - notes: S5b DONE 2026-10-20 (cloud lane, built and JVM-tested, device proof OWED): the uploads on Android, iOS's CameraSweepUploader on WorkManager, the same methods (stageUpload, startUpload, discardUpload, uploadsInFlight, finishedUploads, acknowledgeUploads) and events channel (xp.noteletter/camera_sweep/uploads). Staged by MOVING the rendered JPEG into filesDir before any session; one CoroutineWorker per upload (network required) doing the bare PUT; a failure is a RESULT, never a WorkManager retry (the Dart side re-requests the session, §5/§6); a stop by the system re-runs it; the result is written to SharedPreferences BEFORE the event and kept until acknowledged; inFlight reads the work tags (uploadId:, local:, key:), which survive process death. SweepUploaderTest: ok only for a 2xx with no error, every key fromWire requires. Still off on Android until S5c. - notes: S5a DONE 2026-10-20 (contract 5.26.0, ADR-180; cloud lane, built and JVM-tested, device proof OWED: the VM has no KVM): the Android library bridge on the SAME channel and wire shapes as iOS (android/.../camerasweep/CameraSweepChannel.kt): constants, access (READ_MEDIA_IMAGES full; READ_MEDIA_VISUAL_USER_SELECTED alone = limited, refused; READ_EXTERNAL_STORAGE <= API 32), requestAccess (MainActivity forwards the permission result), openSettings, fetchImages (MediaStore, DATE_TAKEN desc, cursor-paged), examine (a Screenshots-directory row is a candidate unread; else ML Kit BUNDLED Latin on a <=1024 px decode at 80 graphemes; an unopenable row deferred, an undecodable one noText), renderedJpeg (decoded upright, JPEG 90, cacheDir/camera-sweep), thumbnail (loadThumbnail), the changes event channel (a MediaStore ContentObserver). The key is iOS's v1 material from DATE_TAKEN|WIDTHxHEIGHT|DISPLAY_NAME (AssetIdentity.kt), the 13 iOS vectors byte for byte (AssetIdentityTest, ./gradlew :app:testDebugUnitTest; mutation-checked). No bursts on Android. CameraSweepBridge.isAvailable stays iOS-only until S5b (uploads: the stageUpload…acknowledgeUploads methods, WorkManager) and S5c (the background pass, WorkManager periodic, and the settings sentence that says 'iOS' — a contract copy change) land. DEVICE (owed): turn the sweep on, grant full and limited access, a screenshot and a photo of a page found, a plain photo rejected. Earlier, as before: S1-S4 S1 done 2026-10-18 (native bridge; report: ../.claude/burn-down-2026-10-14/reports/flutter.md §Follow-up: F-125 S1 (sweep native bridge)); S2 done 2026-10-18 (ledger and service; same report §Follow-up: F-125 S2 (sweep ledger and service)); S3 done 2026-10-18 (screens and the foreground start; same report §Follow-up: F-125 S3 (sweep screens)); S4 done 2026-10-18 (the background task and background uploads; same report §Follow-up: F-125 S4 (sweep in the background)); S5 waits for F-123's SDK. S4 DONE 2026-10-18 (contract 5.24.0): the BGProcessingTask xp.NoteLetter.Flutter.camerasweep.refresh (Info.plist UIBackgroundModes processing + BGTaskSchedulerPermittedIdentifiers; registered natively before launch ends, ios/Runner/CameraSweep/SweepBackgroundTask.swift; asked for only while the sweep is on; a native handler calls the ONE Flutter engine's CameraSweepHost.backgroundRun over xp.noteletter/camera_sweep/background, and the task completes when the pass ENDS — Swift's completed at once) and every sweep upload on a background URLSession xp.NoteLetter.Flutter.camerasweep.upload (CameraSweepUploader.swift: the rendered JPEG staged under Application Support BEFORE the session, the record in taskDescription, results written down until the Dart side acknowledges, handleEventsForBackgroundURLSession). Expiry: no session after the stop, a session in flight waited for (2 s) and its upload handed off, ingested only when the bytes LAND, in-flight photos never re-sent; leaving the foreground halts passes. A tray card stays until its upload lands. SIMULATOR: BGTaskScheduler.submit answers error 1 (unavailable), so iOS's own _simulateLaunch finds nothing; a debug stand-in task drives the handler. REAL PHONE (the coordinator's): that iOS accepts the request and runs the task (plug in, Wi-Fi, an hour+; or Xcode's debugger: e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"xp.NoteLetter.Flutter.camerasweep.refresh"]); a background upload to a REAL signed URL; a relaunch-for-events after the app was killed. S3 DONE 2026-10-18 (contract 5.23.0): Settings → Camera roll (/settings/camera-roll, a §2.2 sub-screen from a Camera roll section after Notifications: the switch that alone fires the photo prompt, the limited/denied refusals as §12 notices with Open Settings, Mode, Catch up with Photos in range, Status, Start over behind §18); the Sources tray (From your camera roll, closing Add to your library: §23 capture cards with thumbnails, Skip/Add, the §14.2 refusal on its card, Add all, "Already in NoteLetter" from one findCapture read per candidate entering the tray); lib/state/camera_sweep_host.dart runs a pass at launch (signed in, on, full access), on every library change (native PHPhotoLibraryChangeObserver over the event channel xp.noteletter/camera_sweep/changes, debounced, a change mid-pass runs one more pass) and on resume; a tray card is not re-examined on a later pass. Frames: screenshots/no-web-reference/ (pairs with NoteLetter/screenshots/sweep-tray*.ios.*; 5aa reads only web pairs). REAL PHONE (Release build): Settings → Camera roll → Sweep my camera roll, allow Full Access, then Sources: a photo the Swift app swept shows "Already in NoteLetter" under its card before anything is approved. S2 DONE 2026-10-18: the four-state ledger (ingested, dismissed, noText@version, deferredNotLocal; Swift's key names and Codable JSON) in Flutter's OWN App Group group.xp.NoteLetter.Flutter via SharedPreferencesAsync(suiteName), starting empty; CameraSweepService: the newest-first walk from the backfill start, 200 examined per pass with the cursor per asset, the ledger skip, the first backfill always to the in-memory tray, review vs automatic, approve/approveAll/dismiss (a card moves only when the call came back, D5), Api.createCaptureSession (fixtures api/uploads capture-session-*, 8 cases driven) + the bare PUT (ApiService.putBytes, foreground until S4), the duplicate rules (null uploadUrl = landed; present = re-PUT; no duplicate = DedupeUnsupported, the sweep stops); dryRun(): the same walk with every write removed, asking Firestore (user_id + source_capture.asset_key) whether a candidate is filed. endpoint_reach.json's owed fn_create_capture_session closed. NOT yet: the PHPhotoLibrary change observer and launch wiring (startIfEnabled has no caller until S3/S4). S1 DONE 2026-10-18: AssetIdentity, AssetPrefilter and PhotoLibraryAccess ported verbatim into ios/Runner/CameraSweep (two marked port changes in AssetPrefilter: examination(of:) reports the character count and thumbnail; recognizeText resumes once) behind the method channel xp.noteletter/camera_sweep (constants, access, requestAccess, fetchImages, examine, renderedJpeg; limited/denied refused natively); lib/services/camera_sweep_bridge.dart over it. The key is proven byte-identical to the original on 13 fixed vectors and on the simulator's real assets (report). SPEC GAP: the limited/denied sentences and the photo-library usage string exist only in Swift (ported verbatim). Port of the Swift sweep: CameraSweep/* (~1,000 lines) plus CameraSweepSettingsView and SweepReviewSection (~375), its tests (CameraSweepFailureTests, SweepTrayTests). S1 native bridge, iOS (~2 d): a method channel in Runner carrying AssetIdentity.swift, AssetPrefilter.swift and PhotoLibraryAccess.swift VERBATIM. That gives the key byte-identical (sha256 of v1|ms|WxH|originalFilename, PHAssetResource), Vision .fast over a 1024 thumbnail with no network at 80 characters, .limited refused, newest-first enumeration of representative stills, and a rendered JPEG. S2 ledger and service, Dart (~2-3 d): the tri-state ledger (ingested, no-text@version, deferred-not-local) in Flutter's own App Group (group.xp.NoteLetter.Flutter), starting fresh; the 200-per-pass newest-first backfill with a cursor; review vs automatic, the first backfill always through the tray; Api.createCaptureSession (fixtures api/uploads capture-session-*) and its bare PUT; the duplicate rules (null uploadUrl means landed, a present one means re-PUT; no `duplicate` STOPS the sweep). This closes endpoint_reach.json's owed fn_create_capture_session. S3 screens (~2 d): the Settings sweep card and the Sources review tray, from the kit. Copy is the spec's; where only Swift had it, it is a SPEC GAP to report. Web has no sweep, so these pairs have no web reference frame — a ruling is needed before frames. S4 background (~2-3 d): BGProcessingTask xp.NoteLetter.Flutter.camerasweep.refresh (Info.plist permitted identifier, the processing background mode, workmanager), and background URLSession uploads that survive suspension. S5 Android: MediaStore, ML Kit and WorkManager. Blocked with F-123 (no SDK). SIMULATOR proves: permissions (full, denied; limited only partly), enumeration, Vision on images with text, the rendered JPEG, the key against Swift's material function (vector tests), capture-session create, dedupe and stop against the emulator, the tray and settings, and a BG task simulated via _simulateLaunchForTaskWithIdentifier. NOT locally: a PUT to a real GCS signed URL (the shim's is a download URL; the device tests swap in the storage emulator's resumable PUT link), iCloud-only deferral, the real roll's precision, real BG scheduling (the simulator refuses BGTaskScheduler.submit). REAL PHONE (the coordinator's): byte-identical keys, proven when a photo the Swift app already swept answers `duplicate: true` on approve (Review mode, so nothing uploads unasked); iCloud deferral; the live precision gate; background runs. About 1.5-2 weeks for S1-S4. (2026-11-11, lane flutter: kit_capture.dart, which S3 built, was deleted by F-183 — retired by 5.43.0, ADR-198.)

## F-138 · Camera-roll sweep: the key only for a candidate, passes from a change token, the waiting verdict (5.40.0, ADR-195)
- status: done 2026-10-29
- screen: none
- route: none
- spec: spec/features/camera-roll-sweep.md §2 §4 §7; spec/decisions/ADR-195-a-sweep-pass-reads-only-what-changed.md
- web: none
- flutter: lib/services/camera_sweep_bridge.dart; lib/services/camera_sweep_service.dart; lib/services/sweep_ledger.dart; ios/Runner/CameraSweep/CameraSweepChannel.swift; android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/CameraSweepChannel.kt; android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/LibraryHistory.kt (new); test/contract/sweep_fakes.dart; test/contract/camera_sweep_service_test.dart; test/contract/camera_sweep_background_test.dart; test/contract/camera_sweep_bridge_test.dart; test/contract/camera_sweep_android_wiring_test.dart; ios/RunnerTests/CameraSweepBridgeTests.swift; android/app/src/test/kotlin/xp/NoteLetter/Flutter/camerasweep/LibraryHistoryTest.kt (new); integration_test/sweep_bridge_test.dart; integration_test/sweep_background_test.dart; integration_test/sweep_tray_test.dart; integration_test/hold_screen_test.dart
- folds: 5.40.0
- device_test: tool/sweep_bridge_test.sh (its 5.40.0 block: the named-photo fetch in the walk's order, a change token, an unreadable one); on a phone, a pass after a photo is taken lists only that photo (debug log 'from the change token')
- shots: none
- extra_gates: android: ./gradlew :app:testDebugUnitTest (LibraryHistoryTest, AssetIdentityTest, SweepUploaderTest); ios: RunnerTests CameraSweepBridgeTests (testAListingReadsNoResourceAndCarriesNoKey, testAnUnreadableTokenIsAWalk)
- notes: Built 2026-10-29 in the 5.40.0 run, out of queue order, at Xavier's word. No screen or copy changes. DEVICE 2026-10-29 (Xavier: "do what you need to test it"). iOS 26.5 simulator: RunnerTests 20/20, the 2 new included; tool/sweep_bridge_test.sh, all 3 phases PASS (a named fetch in the walk's order, a token read, a fresh token with 0 changes, an unreadable token nil); tool/sweep_service_test.sh PASS (pass 2 from the change token, nothing listed; a whole walk settles 20; a photo added by the script between passes is the ONLY photo examined; a relaunch brings its waiting card back). Android 15 emulator (API 35): tool/sweep_android_test.sh bridge and service, both PASS on a real MediaStore (generation tokens; the photo pushed between passes is the only one examined). The first Android device run of the sweep at all. NOT on iOS 27: a build from Xcode 27.1 is trapped at launch for not adopting UIScene (TODO). Found on the way and fixed: the Podfile raises pods below iOS 15 (Xcode 27.1 refuses them); Android debug builds may speak cleartext to the emulator host (they never could reach the suite); the device tests read the shim's own /__storage write route (aaede52), and _emu_defines.sh passes EMULATOR_STORAGE_PORT. Flutter on Xcode 27 needs FLUTTER_XCODE_ARCHS=arm64 for a simulator build (debug_unpack_ios refuses arm64+x86_64). Phone run still owed.
- placed: after F-125

## F-126 · Shelf map (5.25.0, ADR-177): the §24 Relationship map at /shelves/map, ported from 10MB-mobile
- status: done 2026-10-29
- screen: shelf-map
- route: /shelves/map
- spec: spec/screens/library.md §The shelf map; spec/component-kit.md §24; spec/decisions/ADR-177-the-shelf-map.md; spec/features/shelf-map.md
- web: src/pages/map/MapView.jsx; src/pages/map/RelMap.jsx; src/pages/map/relmapGraph.js; src/pages/map/relmapLayout.js; src/styles/app-map.css
- flutter: lib/widgets/kit/kit_relationship_map.dart (new); lib/widgets/kit/kit_frame.dart (the Canvas frame, kit §1.5); lib/pages/tags/shelf_map_page.dart (new); lib/shared/relmap_layout.dart (new); lib/router.dart; lib/pages/tags_page.dart; lib/pages/tags/shelf_page.dart; test/widgets/relmap_layout_test.dart (new)
- folds: 5.25.0
- device_test: shelf map composes from the kit, opens fitted, pans, pinches, selects
- shots: shelf-map; shelves; shelves-letter-chips; shelves-letter-off
- extra_gates: the layout over web's vitest cases, case for case
- notes: The shelves index gained a 'Shelf map' action in its chapter opening (web 19d3647 re-shot shelves, shelves-letter-chips and shelves-letter-off, so 5aa reads those three pairs STALE-WEB-FRAME until this item re-shoots them). Port 10MB-mobile/lib/screens/map/map_source.dart (pure: graph, layoutMapGraph, mapLinkGeometry, mapArrowHead) and map_screen.dart (InteractiveViewer + CustomPaint) into NoteLetter's kit, from the WEB reference (pages/map/*), not from 10MB. Do NOT carry 10MB's four defects (ADR-177 §Rationale): full screen opens fitted through a TransformationController; search matches draw the marker pair (--highlight fill, --border-strong ring); wires take the PARENT shelf's colour token; the wire geometry reads each chip's measured width, not a fixed 172. Entry points: 'Shelf map' on the shelves index head, 'See on map' on a shelf page (focus in navigation state, never the URL). At 5.25.0 parent_tag_id draws nothing. Cloud lane 2026-10-20 (cloud/f-126): built, every gate but the Mac's green; OWED on the Mac: the four pairs (shelf-map, shelves, shelves-letter-chips, shelves-letter-off), the device test, then done.

## F-127 · Plate I, the landing's hero film (5.25.1, ADR-178): the score ported 1:1, and the hero row the reference's
- status: done 2026-10-19
- screen: landing-actual
- route: /landing
- spec: spec/decisions/ADR-178-the-landing-hero-is-a-film.md; spec/design-tokens.md
- web: src/pages/landing/Reel.jsx; src/pages/landing/reelScore.js; src/pages/landing/reelMotion.js; src/styles/landing-actual.css; src/pages/LandingActual.jsx; tests/landing/reel.test.js
- flutter: lib/site/landing_reel.dart (new); lib/site/reel_score.dart (new); lib/site/reel_motion.dart (new); lib/theme/app_motion.dart (new); lib/site/landing_page.dart; test/contract/landing_reel_test.dart (new); test/contract/landing_test.dart; integration_test/hold_screen_test.dart
- folds: 5.25.1
- device_test: none
- shots: landing-actual
- extra_gates: harness/token_contrast_check.py --target flutter; harness/screenshot_pair_check.py
- notes: Built 2026-10-19 against web's 5.25.1 working tree (Reel.jsx, reelScore.js, reelMotion.js, the `.pl-*` CSS; not yet committed there). (1) The score is `reel_score.dart`, a pure `paintReel(t)` that returns every part's state by web's keys: mulberry32 bit for bit (Math.imul in 16-bit halves), buildField's 79 dots/88 wires (wide) and 57/57 (tall), JS's stable sort as an index tie-break, and positions at t = 23.7 and 29.3 equal to web's under node to 1e-6 (`landing_reel_test.dart`, 29 tests: token curves, PRNG, field, loop seam at 0 and 35.95, each chapter's key still, layout bounds, fit, wave split, the player). (2) `lib/theme/app_motion.dart` (new) mirrors --ease-out, --ease-quill and --ease-in-out (theme.css; design-tokens.md's motion line names only the first two) as Cubics; the film solves their control points with WebKit's UnitBezier as web does (Flutter's Cubic bisects to 0.001). (3) Paper is widgets, ink is painters; each part listens to its own slice of the frame, so a value that did not move rebuilds nothing. Every rule with no line-height takes the page's 24px (body --lh-base): card foot, slip kind, the Returning and 3-passages chips, strap, kicker, inbox and listen rows, measured on web's DOM. Departures (no SVG, no inner shadow, no mixed-colour rounded border, per-line highlight from the paragraph's boxes, visibility measured on scroll) are in landing_reel.dart's header. (4) Controls: play/pause; a track that taps and drags, a Semantics slider (a second a step) and arrow/Page/Home/End keys; five chapter buttons (paused: the key still; playing: the start); timecode; caption. Reduced motion opens paused on 05's key; the clock stops under 4% of the plate in the scroll viewport. (5) Hero row: headline beside stand and act above 1180, stacked under it below (act beside the stand 980-1180), the plate full width, to the sheet's edges on a phone; h1 4.6vw/5vw/10.5vw clamps; `.nl-micro` on 24px. The sheet now stops at 1336, not 1400 (`.ed { max-width: 1400px }` is border-box). _LetterStack deleted. (6) Frames: hold_screen_test drives /landing's plate to chapter 05's still, as theme-shots does. Looked at against web at 14 wide instants (light), 4 (dark) and 8 tall: the same frame; left: `text-wrap: pretty` has no Flutter counterpart, so a few card lines break one word differently. signin and signin-fail re-shot too (F-82 lists landing_page.dart): unchanged. Pin stays 5.24.0 until F-126 (5.25.0) lands.

## F-128 · Plate I's titles ink in whole lines (web 41ffd9a): one engine with cuts, eyebrows per chapter, and a scrub inside the segment
- status: done 2026-10-19
- screen: landing-actual
- route: /landing
- spec: spec/decisions/ADR-178-the-landing-hero-is-a-film.md; spec/design-tokens.md
- web: src/pages/landing/reelScore.js; src/pages/landing/Reel.jsx; src/styles/landing-actual.css; tests/landing/reel.test.js
- flutter: lib/site/reel_score.dart; lib/site/landing_reel.dart; test/contract/landing_reel_test.dart
- folds: none — UI-only, web 41ffd9a (no contract version)
- device_test: none
- shots: none
- extra_gates: harness/token_contrast_check.py --target flutter
- notes: Ported from web 41ffd9a (committed). The defect: titles rose word by word through line masks that cut glyphs mid-motion, left letter fragments on exit, and the outgoing title was still on the stage as the next rose. (1) Each LINE now inks in whole via `ink(t, tin, tout)`: opacity by --ease-out over 0.7s, a 12px rise by --ease-quill over 1.0s, blur 5px to 0 and tracking +0.06em to 0 (on the base -0.028em), and an exit that fades up 10px with 4px of blur over 0.45s by --ease-in-out. Line 2 starts 0.16s after line 1. In `landing_reel.dart` it is `_InkLine` (Transform.translate, Opacity, ImageFiltered with TileMode.decal, disabled at 0 blur). There are no masks, and a still costs no layer. Eyebrows are one per chapter (`EB:c`) at (title.x, title.y), and lines sit at title.y + title.eb (wide 24, tall 20; `title.size` is gone, the CSS sizes 46/31 are in the cast). (2) One engine with cuts: `ReelCut` with `makeBeats(at)` computing every beat from the chapter starts, and `paintReel(..., cut:)`, `chapterAt(cut, t)`, `cut.endOf(i)`. Only `reelPlate` is ported, with title in/out 0.15/5.85, 6.5/11.85, 12.5/18.4, 19/26.4 and 27/34.5. Web's HERO cut is NOT ported: Xavier picked it on 2026-10-19 and a follow-up ports it once its copy settles. The ink, eyebrow, makeBeats and scrub changes are shared by both cuts. (3) The tall vid card is at (304,174), slip p1 at (304,160) and the search at y 140. (4) The track maps a tap or drag within the segment under it (`reelTrackSeek`, `reelTrackSegments`), and a gap reads as the next chapter's start. Tests: `landing_reel_test.dart` has 34 tests. New ones: "never has two titles on the stage at once", sampled every 0.05s and proven red with the first title's out at 6.3 (t=6.55: titles [0, 1]); the beats equal web PLATE.beats exactly; the line ink at 0.4, 6.0, 6.2, 6.9 and 5.4; the moved layout numbers; and the segment scrub, red under the old linear map (00:05 for 00:06). The key-frame test asserts a fully inked title and eyebrow per chapter. Copy and layout are read from web 41ffd9a with `git show`, because web's working tree is cutting the plate. Frames: NOT re-shot, and the web frames NOT copied (coordinator, 2026-10-19: they would show the plate being removed). The landing-actual pair stays as F-127 shot it, so screenshot_pair_check reads STALE-WEB-FRAME (already) and F-127 STALE-PAIR until the hero port re-shoots it. The transition was looked at frame by frame from an in-test render (fonts loaded, no simulator) at 5.80-6.70 every 0.05s, wide and tall, plus dark at 0.4, 6.0 and 6.9. Whole glyphs blur and fade, the stage is empty from 6.35 to 6.50, there is no overlap, and the tall title clears the moved vid card. Blur cost on a device was not profiled. Pin stays 5.24.0.

## F-130 · Reader: Re-process, Mark as read, the halved dwell (5.27.0, ADR-183, ADR-184)
- status: done 2026-10-30
- screen: reader
- route: /reader/:docId
- spec: spec/screens/reader.md; spec/features/read-tracking.md; spec/api/documents.md; spec/decisions/ADR-183-re-process-a-source.md; spec/decisions/ADR-184-a-passage-reads-in-half-the-time-or-on-request.md
- web: src/pages/ReaderView.jsx; src/pages/reader/ManuscriptPanel.jsx; src/api.js
- flutter: lib/pages/reader/dwell.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader_page.dart; lib/pages/reader/reprocess_action.dart (new); test/contract/dwell_test.dart; test/contract/reprocess_action_test.dart (new); test/contract/mark_as_read_test.dart (new)
- folds: 5.27.0
- device_test: none
- shots: reader-reprocess-confirm; reader-mark-as-read
- extra_gates: none
- notes: Three reader changes from Xavier's 2026-10-20 ask, web first (reference). (1) dwell.dart: min(0.25 x words/220 x 60, 10) s, halved factor AND cap; the old spec examples were 10x too short (ADR-184). (2) Mark as read at the foot of every unread passage, always shown on touch: writes that passage's chunk_read at once through read_counters (the dwell write), cancels its timer, 'Marking...' while in flight, turns read only on commit, refusal 'This passage couldn't be marked read. Try again.' as 14.2 beside it. (3) Re-process ghost header action after the content-form action, for complete|error, not a passage, has gcs_path / gcs_paths / source_url; always a 18 Confirmation (danger) 'Re-process this source?' with the SupersessionBody consequences; Api.updateDocument(docId, {reprocess: true}); 202 then the subscription moves it. Mirror web's ReprocessAction exactly (web 05506cb + follow-up): update-in-place copy, edit consequence only, a busy label on the confirm. When Re-process lands, map it in ../NoteLetter-contracts/harness/confirm_required.json `re-process`: flutter calls [{name: updateDocument, args: reprocess}] and drop the `benign` entry. Mark as read's slot must keep its height when a passage turns read (no reflow while reading). Folded into F-142 (2026-10-30, Xavier's direction-D ruling): built in the D source page — Re-process is a row of the sheet's Also (after the content-form action, before Delete; §18 danger, busy Queuing…), Mark as read stands at the foot of every unread passage, the dwell is halved; harness confirm_required.json `re-process` maps flutter updateDocument {reprocess}. Pairs reader-reprocess-confirm and reader-mark-as-read (tool/seed_unread_doc.py writes the frame's document).

## F-131 · Nested shelves (5.28.0, ADR-185, INV-33): the shelf tree, roll-up, Move into, New sub-shelf, and the rail's tree
- status: done 2026-10-30
- screen: shelves; shelf; picker; rail
- route: /shelves; /shelves/{id}
- spec: spec/screens/library.md §Nested shelves; spec/invariants.md §INV-33; spec/component-kit.md §1.2 §20.1 §20.2 §21 §24; spec/decisions/ADR-185-shelves-nest.md
- web: src/shared/shelfTree.js; src/pages/ShelvesView.jsx; src/pages/LibraryHome.jsx; src/shell/AppShell.jsx; src/shared/ShelfPicker.jsx; src/shared/ShelfSelect.jsx; src/shared/ShelfForm.jsx; src/pages/map/MapView.jsx; tests/contract/shelf-tree.test.js
- flutter: lib/shared/shelf_tree.dart (new); lib/models/tag.dart; lib/services/api.dart; lib/state/tags_notifier.dart; lib/pages/tags_page.dart; lib/pages/library_page.dart; lib/pages/tags/shelf_page.dart; lib/pages/tags/shelf_parts.dart; lib/pages/tags/shelf_sheet.dart; lib/pages/tags/shelf_map_page.dart; lib/widgets/sidebar.dart; lib/widgets/kit/kit_shelf_chips.dart; lib/widgets/kit/kit_shell.dart; lib/widgets/kit/kit_shelf.dart; lib/shared/local_flags.dart; test/contract/shelf_tree_test.dart (new); test/kit/shelf_nesting_test.dart (new)
- folds: 5.25.1 … 5.26.2; 5.28.0 (5.27.0 is F-130's; pin stays 5.24.0: F-129 is held, and the pin moves with a green /conformance on the Mac)
- device_test: shelves List/Grid, a shelf's sheet, Search's filters sheet, Ask's composer growing to seven lines
- shots: shelves; shelf
- extra_gates: shelf_tree_test runs web's shelf-tree cases case for case
- notes: Cloud lane D (cloud/subshelves-b, replayed as cloud/subshelves-b2 2026-10-21), 2026-10-20, on top of F-126. `shelf_tree.dart` is web's `shelfTree.js` rule for rule (resolution with the 64-hop guard, subtree, path, tree order, inherited letter mode, `canHold` on the stored chain). `Tag.ownLetterMode` is the stored mode or null (inherits); `letterMode` keeps its old meaning. The index and Home list top-level shelves with subtree counts and "{n} sub-shelves"; a shelf page has the breadcrumb (kit `KitShelfCrumbs`), a Sub-shelves row (`KitSubShelfChip`) ending in New sub-shelf, Inside (Move into, a §20.2 select over `canHold` parents plus Top level), the inherited mode said as "Muted by {shelf}." with "Use the parent's setting" (letter_mode: null), and a delete confirm naming where the children go. The rail lists the tree (`KitRailShelfRow`, collapse state in `LocalFlags.shelfCollapsed`), which it never did before. §20.1/§20.2 rows are in tree order with a muted path prefix; matching reads the title alone. The map draws parent edges through the tree. Folded into F-143 (2026-10-30, direction D): its work was already on main (cc459aa, 75a8bc1); D rebuilt every surface it touched — the index's §42 listing holds each top-level shelf's subtree, a shelf page's crumb is All shelves then each ancestor (KitDBackControl.trail), Sub-shelves and New sub-shelf are the sheet's rows, Inside/Move into and the inherited mode ('{Mode} by {shelf}.') are Shelf settings, the map draws parent edges. The rail's shelf tree is retired by Xavier's D ruling 2 (the compact rail has none), and shelf-child / shelf-picker / rail have no web frame in D, so the pairs are F-143's shelves and shelf. Device proof in F-143's run: a sub-shelf opened from the sheet (crumb RECIPES), Move into Recipes and back to Top level (write before you move); the refusal and New sub-shelf landing inside stay widget-tested (shelf_nesting_test, shelves_index_create_test).

## F-132 · Reader: Listen playback speed, and dragging a passage boundary (UI-only, recorded at 5.28.0)
- status: done 2026-10-30
- screen: reader
- route: /reader/:docId
- spec: spec/screens/reader.md §Playback speed §Moving a passage boundary; spec/features/listen-playback-speed.md; spec/features/passage-boundary-drag.md; spec/component-kit.md §6.8
- web: src/pages/reader/ListenPanel.jsx; src/pages/reader/readerPrefs.js; src/pages/reader/ManuscriptPanel.jsx; src/pages/reader/passageBoundary.js; src/styles/app-source.css
- flutter: lib/pages/reader/listen_panel.dart; lib/pages/reader/reader_prefs.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader/passage_boundary.dart (new); test/contract/passage_boundary_test.dart (new)
- folds: none (UI-only)
- device_test: drag a passage's grip on the phone: the line follows, the page scrolls at the edge, the release re-cuts; Up/Down on a hardware keyboard
- shots: reader-listen; reader-edit-drag
- extra_gates: none
- notes: Speed: a KitSegmented (§6.8) named Speed under the player controls, 0.75/1/1.25/1.5/1.75/2, default 1, stored in reader_prefs beside text size; it sets the player's rate on change and on every load. Drag: passage_boundary.dart ports web's passageBoundary.js rule for rule (blocks, offeredCuts, currentCut, recut, stepCut) with its test over web's cases; the grip is a 22px handle at the start of every editing head after the first, named 'Move where passage {n} begins'. On a phone web's editing head wraps the shelf chips onto their own line, and the Speed track takes its own line under its label. Folded into F-142 (2026-10-30): Xavier ruled D in tandem, which lifts the approval hold. Speed is the kit §34 Switch (direction D), not §6.8; the boundary grip, drag, edge scroll and Up/Down are built and the device test is green; a cancelled pointer re-cuts nothing. Pairs reader-listen and reader-edit-drag. Flutter's edit head draws no per-passage shelf chips (never built here), so nothing wraps onto its own line.

## F-133 · The generative-AI switch: Settings, the wizard, and every surface it hides (5.29.0, ADR-186, INV-34); Video reading (5.33.0, ADR-190, INV-36)
- status: done 2026-10-30
- screen: settings
- route: /settings
- spec: spec/api/ai.md; spec/screens/settings.md §Generative AI section; spec/screens/onboarding.md §Endpoints used §Rules §States; spec/screens/reader.md §Sections; spec/screens/ask.md §While generative AI is off; spec/screens/search.md §Data / endpoints; spec/screens/library.md §Composition; spec/invariants.md §INV-34; spec/features/generative-ai-switch.md; spec/screens/settings.md §Video reading; spec/features/video-ai.md; spec/decisions/ADR-190-a-reader-chooses-which-ai-reads-their-short-videos.md
- web: src/api.js; src/shared/genAI.js (videoAIChoice); src/App.jsx; src/shell/AppShell.jsx; src/pages/SettingsView.jsx; src/pages/ReaderView.jsx; src/pages/SearchView.jsx; src/pages/ShelvesView.jsx; src/pages/ask/AskOff.jsx; src/shared/OnboardingChecklist.jsx; src/pages/onboarding/OnboardingWizard.jsx; src/pages/onboarding/steps.jsx
- flutter: lib/services/api.dart; lib/services/firestore_service.dart; lib/state/ai_settings_notifier.dart (new); lib/app_providers.dart; lib/pages/settings_page.dart; lib/pages/reader_page.dart; lib/pages/search_page.dart; lib/pages/tags/shelf_page.dart; lib/pages/library_page.dart; lib/widgets/sidebar.dart; lib/router.dart; lib/pages/chat_page.dart; lib/pages/onboarding/wizard.dart; lib/pages/onboarding/steps.dart; lib/services/endpoint_budgets.dart; test/contract/api_requests_test.dart
- folds: 5.29.0; 5.33.0
- device_test: switch AI off in Settings: Ask leaves the rail and the bottom bar (Letters takes its slot), the reader opens on Manuscript with no Summary, Search has no Cohesive; /ask shows the Notice; switch back on and all return; untick Use generative AI in the wizard and finish, and Settings reads Off
- shots: settings-ai-off; reader-ai-off; ask-off; onboarding-librarian
- extra_gates: none
- notes: Folded into F-144 (direction D's Settings, 2026-10-30): AiSettingsNotifier (lib/state/ai_settings_notifier.dart) is the one subscription; shellAiOn/shellAiUnread read it; /ask routes gate on it (AskOffPage, the kit skeleton while unread); the Generative AI section and Video reading are in D's Settings; the wizard's Use generative AI row and its fourth PUT; pairs settings-ai-off, reader-ai-off, ask-off, onboarding-librarian; device test in F-144's. Originally: One AiSettingsNotifier subscribes /users/{uid}/settings/ai once (absent = on; only a literal false is off; loading and failed hide every gated surface, as web's genAIState). Settings: a KitSettingRow + KitSwitch section above Summaries, write before you move (OrgNotifier's pattern), the off caption verbatim from settings.md, a §14.1 block when unreadable; Summaries and the letter section's Ask row absent while off. Reader: filter readerRailItems and the sections in step, default section the first remaining; hold the sections until the switch is read. Router: /ask, /ask/shelf/:tagId, /ask/thread/:id render the §12 Notice while off. Wizard: the Use generative AI check row on the Librarian step (ticked; a replay starts from the stored value), a fourth separate fn_ai_settings PUT on finish made once, its failure line 'Your AI choice could not be saved: {sentence}', and a Generative AI row on the done step. Add api/ai-settings to the request suite and fn_ai_settings to endpoint_budgets. 5.33.0 (ADR-190): a second row under the switch, Video reading, present whether AI is on or off: a KitSegmented OpenAI · Claude reading the same AiSettingsNotifier's videoAI (only a literal "claude" is Claude; absent and anything else is OpenAI), write before you move with fn_ai_settings PUT {videoAI} alone, busy while pending, a press on the selected segment sends nothing, a §14.2 rejection with the server's sentence; no control while loading or failed, and no failure block of its own (the switch row's is the section's one). Description copy verbatim from settings.md. Mirror web's VideoReadingRow and its tests in tests/contract/generative-ai-switch.test.js.

## F-134 · Ask: the written answer and its quotations (5.30.0, ADR-187, INV-35)
- status: done 2026-10-30
- screen: ask
- route: /ask
- spec: spec/api/ask.md §The written answer; spec/data-model.md §/ask_threads/{threadId}/messages/{messageId}; spec/screens/ask.md §States §Composition; spec/component-kit.md §25; spec/invariants.md §INV-35; spec/features/ask-hybrid-answer.md
- web: src/api.js; src/shared/AskAnswer.jsx; src/pages/AskView.jsx; src/styles/app-kit.css
- flutter: lib/models/ask_thread.dart; lib/services/firestore_service.dart; lib/widgets/kit/kit_ask_answer.dart (new); lib/pages/chat_page.dart; test/contract/firestore_shapes_test.dart
- folds: 5.30.0
- device_test: ask composes from the kit
- shots: ask-thread; ask-answer-note
- extra_gates: none
- notes: Map `answer` (paragraph/quote blocks; drop an unknown kind or a quote with no n; empty list is null) and `answer_note` on a library message, as web's askAnswer. KitAskAnswer (kit §25): paragraphs in the answer's serif face with each [n] a mono --accent-text chip carrying the pill's index (tap scrolls to the pill and marks it --accent-soft for 1.6 s); a quote block in serif italic set in from a 2px --accent rule, its text through KitMarkerInline, a sans meta line with the chip and the source title, no added quotation marks; answer_note as one italic sans --fg-muted line, never a §14 block. Copy from screens/ask.md §Copy (5.30.0) and the thinking line. The fn_ask_turn client budget is already 120 (moved with the backend at 5.30.0). Folded into F-143 (2026-10-30, Xavier's D-in-tandem ruling lifted the approval hold): AskMessage maps answer/answer_note as web's askAnswer (firestore_shapes_test +7, web's ask-written-answer cases); KitAskAnswer/KitAskRef in kit_ask_answer.dart (kit §25) above the D citations register; a marker scrolls to its citation and marks it 1.6s. Pairs ask-thread and ask-answer-note (the hold writes the backend's answer_note as the owner, as web's shot does); device proof in 'ask composes from the kit' (the answer above its citations, the [n] chip marking its citation, the mark gone after 1.6s).

## F-135 · A post on any other video platform is social_video (5.32.0, ADR-189): detection, the Video kind and link shape, the share sheet's "Video post"
- status: done 2026-10-26
- screen: share-extension
- route: /share
- spec: spec/api/ingest.md; spec/component-kit.md; spec/screens/share-sheet.md
- web: src/api.js; src/shared/FileBadge.jsx
- flutter: lib/state/upload_notifier.dart; lib/widgets/kit/kit_controls.dart; lib/shared/share_content.dart; lib/models/activity_item.dart; test/contract/epub_kind_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: doc_kind_check.py
- notes: Done in the 5.32.0 run itself, out of queue order: the shared url-detection table gained social_video cases, and a Flutter that did not know the hosts would have turned every lane's per-item gate red. No screen changes (the Video chip and badge already exist); the share sheet's Files-as line gains one label.

## F-136 · The six synchronous shelf builders retire (5.36.0): the reviews read only stored proposals
- status: done 2026-10-28
- screen: none
- route: none
- spec: spec/api/tags.md; spec/api/tasks.md; spec/api/study.md; spec/screens/library.md §Re-shelve review §Backfill review
- web: src/api.js; src/shared/ShelfForm.jsx
- flutter: lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/pages/tags/reshelve_sheet.dart; lib/pages/tags/shelf_sheet.dart; lib/pages/tags/split_shelf_sheet.dart; lib/pages/study/syllabus_plan_editor.dart; test/contract/api_requests_test.dart; test/kit/reshelve_review_test.dart; test/kit/shelf_backfill_test.dart; test/kit/shelves_index_create_test.dart; test/kit/shelf_delete_task_test.dart
- folds: 5.36.0
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/client_timeout_check.py --target flutter
- notes: Done in the 5.36.0 run itself, out of queue order. `fn_delete_tag`, `fn_suggest_reshelve`, `fn_suggest_shelf_backfill`, `fn_suggest_shelf_split`, `fn_split_shelf` and `fn_suggest_syllabus_plan` are retired. No runtime path reached them since F-72, which moved each to its background task. Their six builders and budget rows are gone. The re-shelve and backfill reviews now take `stored` as required and read nothing themselves. Removed as unreachable: the live read, its failure block, its "Finding…"/"Reading…" state, the per-shelf filing and its "Filed" label, `reshelveSlice`, the `SuggestReshelve`/`SuggestBackfill`/`ApplyBackfill` seams, and `BackfillFor.created`. No visible state the app could reach changed, so there is no pair. The kit tests now mount stored proposals. Dropped with the read: the failed-read, slices-of-150 and per-shelf-retry tests. Added: a refused stored apply stays with its sentence. `applyShelfBackfill` keeps its builder (`fn_apply_shelf_backfill` is not retired) but no longer has a runtime caller.

## F-137 · `applyShelfBackfill` retires, and a shelf delete can only be requestShelfDelete (5.37.0)
- status: done 2026-10-28
- screen: none
- route: none
- spec: spec/api/tags.md; spec/api/tasks.md; spec/screens/library.md §Deleting a shelf
- web: src/api.js
- flutter: lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/pages/tags/shelf_page.dart; lib/pages/tags/shelf_sheet.dart; lib/pages/reader_page.dart; lib/pages/study/program_editor.dart; test/contract/api_requests_test.dart
- folds: 5.37.0
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/client_timeout_check.py --target flutter; python3 ../NoteLetter-contracts/harness/confirm_check.py
- notes: Done in the 5.37.0 run itself, out of queue order. `fn_apply_shelf_backfill` is retired (Xavier, 2026-10-28: "just retire now"). Its builder and budget row are gone; nothing called it since F-136, because the reviews file through `resolveTask`. `requestTask(kind, fields)` is now library-private `_requestTask`, with one public method per kind: `requestShelfDelete(tagId, reshelve:)`, `requestShelfBackfill`, `requestShelfSplit`, `requestSyllabusPlan`, `requestReorgPlan`. Request bodies are byte-identical. A screen cannot call `_requestTask`, so the only way to delete a shelf is `requestShelfDelete`, which confirm_check (5ab) now binds to its §18 confirm in `shelf_page.dart`. Before this, the gate's shelf-delete entry named a builder nothing called, and the real delete was ungated. Five call sites moved. `api_requests_test` dispatches `fn_request_task` cases on their `kind`, and an unknown kind is refused locally. No visible state changed, so there is no pair.

## F-139 · Twenty shelf colours and dark palette B (5.41.0, ADR-196)
- status: done 2026-10-30
- screen: none (tokens)
- route: none
- spec: spec/design-tokens.md; spec/screens/library.md
- web: src/shared/shelfColor.js; src/styles/theme.css
- flutter: lib/theme/app_colors.dart; lib/theme/tokens.dart; test/contract/shelf_colors_test.dart
- folds: 5.41.0
- device_test: none (tokens; the D items re-shoot every screen)
- shots: none
- extra_gates: harness token_contrast_check.py (5l) SHELF, DARK-PARITY, MIRROR
- notes: Lane A of direction D. The ten new cloths and their dark pairs in wheel order with the picker labels; palette B's solid dark greys, brick-300 accent, critical #F37469. Lands at the held pin. Redesign lane, briefs and reports in ../.claude/redesign-d-2026/.

## F-140 · Direction D: the frame, the listing parts and the shell (5.42.0, ADR-197)
- status: done 2026-10-30
- screen: every screen (shell)
- route: all
- spec: spec/component-kit.md
- web: src/shell/AppShell.jsx; src/App.jsx
- flutter: lib/widgets/kit/kit.dart; lib/widgets/kit/kit_shell.dart; lib/widgets/kit/kit_frame.dart; lib/widgets/kit/kit_headers.dart; lib/widgets/kit/kit_rail.dart
- folds: 5.42.0
- device_test: integration_test: the app header, the tab bar's middle action, the running head opening and folding, the drawer's compact rail and Reader's card
- shots: none
- extra_gates: flutter test test/contract
- notes: Masthead, the one toolbar (moved to the app header and tab bar at 1024 and under), the settings panel dropping from the header, the sheet as a running head at 680 and under, register rows, covers (15 types incl. social_video), the List/Grid choice, sliding switches, shelf tags, row hover, D empty states, grow fields, 44px back controls; the compact rail and the Reader's card (Xavier 2026-10-30). Kit widgets by name, never inline per screen (ADR-041). In tandem with web (Xavier 2026-10-30). design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/.

## F-141 · Direction D: Home, the Library and Add a source (5.42.0, ADR-197)
- status: done 2026-10-30
- screen: library, sources, add
- route: /, /sources, /sources/add
- spec: spec/screens/library.md; spec/screens/sources.md; spec/component-kit.md
- web: src/pages/LibraryHome.jsx; src/pages/SourcesBrowse.jsx; src/pages/AddSource.jsx; src/kit/d/Catalogue.jsx; src/kit/d/Shelves.jsx; src/kit/d/LetterQuick.jsx
- flutter: lib/pages/library_page.dart; lib/pages/sources_page.dart; lib/pages/sources/browse_section.dart; lib/pages/sources/source_facets.dart (new); lib/pages/add_source_page.dart (new); lib/widgets/kit/kit_d_home.dart (new); lib/widgets/kit/kit_d_library.dart (new); lib/widgets/kit/kit_d_shelves.dart (new); lib/widgets/kit/kit_d_catalogue.dart (new); lib/widgets/kit/kit_d_letter.dart (new)
- folds: 5.42.0
- device_test: integration_test: Home's sections, the Library's facets and List/Grid, empty and first-reading states
- shots: library; sources; sources-empty; add
- extra_gates: flutter test test/contract
- notes: HomeHybrid and LibHybrid. Needs F-140. Ports from web's phone frames (isMobile). design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/.

## F-153 · Home's study band: the newest session, under the letter (5.49.0)
- status: done 2026-11-02
- screen: library
- route: /
- spec: spec/screens/library.md §Data; spec/screens/library.md §Composition (item 4); spec/features/study-entry-points.md (new)
- web: src/pages/LibraryHome.jsx; src/kit/d/letter.js; src/kit/d/index.js; src/styles/app-home.css; src/App.jsx; tests/contract/study-entry.test.js (new)
- flutter: lib/widgets/kit/kit_d_home.dart; lib/widgets/kit/kit_d_letter.dart; lib/pages/library_page.dart; test/kit/study_entry_test.dart (new); test/contract/home_harness.dart; integration_test/device_run_test.dart; integration_test/hold_screen_test.dart; tool/seed_study_band.py (new)
- folds: 5.49.0
- device_test: tool/device_test.sh "Home's study band opens its session, and Study this opens the pre-filled editor that writes nothing (F-153, F-154)"
- shots: home-study-band; home-study-band-started
- extra_gates: flutter test test/contract; flutter test test/kit/study_entry_test.dart
- notes: Xavier 2026-11-02 (ruling 9): 'keep both, do whatever you need to implement it'. The design's HomeStudyBand (.hm-due), built on every client: a card 28 under the letter, above Recently added — the cards mark on accent-soft, the eyebrow 'Deep study · sent {when}' (time today, 'yesterday', else 'Mon, Nov 2'), the program title, one line of counts (QUESTIONS, never items; new/review by item kind; 'started' = a response) and the brick Start the session / Resume session, which opens THAT session (/study/session/{id}). Drawn only on the ledger's rule (kitStudyDue: sent or email_failed, a question left); nothing while the read is out or refused. The standfirst's desk sentence and the ledger's row stay. kitStudyDue now carries the session's whole reading. At 720 and under (web's breakpoint, not this client's 768) the button runs the full width under the text. Pairs: python3 tool/seed_study_band.py [--started], hold state study-band on /, then --remove. Web lane studyentry, branch c/studyentry (9e353b0); brief and report in ../.claude/calls-2026-11-01/.
- placed: after F-141

## F-142 · Direction D: the source page (5.42.0, ADR-197)
- status: done 2026-10-30
- screen: reader
- route: /reader/{id}
- spec: spec/screens/reader.md; spec/component-kit.md
- web: src/pages/ReaderView.jsx; src/kit/d/Masthead.jsx; src/kit/d/Sheet.jsx; src/kit/d/SectionHead.jsx; src/kit/d/Skeleton.jsx; src/styles/app-source.css
- flutter: lib/pages/reader_page.dart; lib/pages/reader/reader_ui.dart; lib/pages/reader/summary_panel.dart; lib/pages/reader/source_priority.dart; lib/pages/reader/content_form_action.dart; lib/pages/reader/delete_source.dart; lib/widgets/kit/kit_d_reader.dart (new); lib/widgets/kit/kit_d_frame.dart; lib/widgets/kit/kit_d_parts.dart; lib/widgets/kit/kit_shelf_chips.dart; lib/widgets/kit/kit_confirm.dart; lib/models/chunk.dart; test/kit/d_reader_kit_test.dart (new); tool/seed_unread_doc.py (new)
- folds: 5.42.0; F-130; F-132
- device_test: integration_test: the six sections, the running head '§ II · Manuscript · 2 of 6' and its progress rule, Source details in the panel
- shots: reader; reader-manuscript
- extra_gates: flutter test test/contract
- notes: ReaderHybrid + SecD. Folds F-130 (Re-process, Mark as read, dwell) and F-132 (Listen speed, boundary drag): Xavier ruled D in tandem 2026-10-30, which lifts F-132's approval hold. Needs F-140. design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/.

## F-154 · Study this on the source page: the new-program editor, pre-filled, writing nothing (5.49.0)
- status: done 2026-11-02
- screen: reader, study-new
- route: /reader/{docId}, /study/new
- spec: spec/screens/reader.md §Study this (new); spec/screens/reader.md §Composition; spec/screens/study.md §Create / edit a program; spec/screens/study.md §Composition (the program editor); spec/component-kit.md §39; spec/features/study-entry-points.md (new)
- web: src/pages/ReaderView.jsx; src/pages/StudyView.jsx; src/pages/study/ProgramEditor.jsx; src/shell/useRoute.js; src/App.jsx; src/kit/d/BackControl.jsx; src/styles/app-redesign-d.css; src/styles/app-study.css
- flutter: lib/pages/reader_page.dart; lib/pages/study/program_editor.dart; lib/router.dart; test/kit/study_entry_test.dart; integration_test/device_run_test.dart; integration_test/hold_screen_test.dart
- folds: 5.49.0
- device_test: tool/device_test.sh "Home's study band opens its session, and Study this opens the pre-filled editor that writes nothing (F-153, F-154)"
- shots: reader-study-this; study-new-from-source
- extra_gates: flutter test test/contract; flutter test test/kit/study_entry_test.dart
- notes: Xavier 2026-11-02 (ruling 9). The August design's Study this: an Also row between Ask about this and Reorganize, the stack glyph (web IcoLayers = IcoStack), only for a source complete with chunk_count > 0 (studyThisOffered), AI on or off. The tap writes nothing: it PUSHES /study/new with a StudySeed as go_router extra (never the address, INV-25b), so the crumb (the source's title, one line with an ellipsis), Cancel and the platform back all pop to the very source page, its own way back intact; with no stack behind it the crumb goes to /reader/{id}. The editor: the source chosen (drawn from the source page's record when outside the listing), the name its title cut to 120, the standfirst 'Started from this document. Add to it, reorder it, or leave it as it is.'; Create program closes to /study as any create. Also here: the running head says '1 document' (was '1 documents'), and the picker lists only complete sources with a counted passage (was complete only; the endpoint refuses the rest), as web's completeDocs. Web lane studyentry (9e353b0).
- placed: after F-142

## F-155 · A picture already in the library: the copy row, Added again, and the camera roll's check before upload (5.50.0)
- status: in-progress
- screen: sources
- route: /sources
- spec: spec/features/picture-dedupe.md; spec/features/camera-roll-sweep.md §6; spec/screens/sources.md §Document processing (+ §Compare); spec/screens/review.md §Sources that need you; spec/screens/reader.md §History; spec/screens/activity.md §The merge; spec/picture-hash.json; spec/decisions/ADR-202-a-picture-already-in-the-library.md; spec/api/uploads.md §fn_create_upload_session (origin); spec/data-model.md (upload_origin)
- web: src/pages/sources/proc.jsx; src/pages/sources/useDocActions.jsx; src/shared/activityKinds.jsx; src/shared/sourceHistory.js; src/api.js; src/styles/app-library.css; tests/contract/picture-copy-row.test.js; src/shared/pictureCopy.js; src/overlays/CompareCopySheet.jsx; src/styles/app-responsive.css; tests/contract/upload-rejection.test.js
- flutter: lib/models/document.dart; lib/pages/sources/browse_section.dart; lib/pages/sources/camera_roll.dart; lib/widgets/kit/kit_d_library.dart; lib/pages/activity_page.dart; lib/services/source_history.dart; lib/services/activity_merge.dart; lib/services/camera_sweep_service.dart; lib/services/camera_sweep_bridge.dart; lib/services/sweep_ledger.dart; lib/services/api.dart; ios/Runner/CameraSweep/AssetPrefilter.swift; ios/Runner/CameraSweep/CameraSweepChannel.swift; ios/Runner/CameraSweep/PictureHash.swift (new); ios/RunnerTests/PictureHashTests.swift (new); ios/Runner.xcodeproj/project.pbxproj; android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/CameraSweepChannel.kt; android/app/src/main/kotlin/xp/NoteLetter/Flutter/camerasweep/PictureHash.kt (new); android/app/src/test/kotlin/xp/NoteLetter/Flutter/camerasweep/PictureHashTest.kt (new); test/contract/picture_copy_row_test.dart (new); test/contract/camera_sweep_service_test.dart; test/contract/camera_sweep_bridge_test.dart; test/contract/sweep_fakes.dart; test/contract/api_requests_test.dart; test/contract/source_history_test.dart; integration_test/sweep_emulator_upload.dart; lib/pages/sources/compare_sheet.dart (new); lib/shared/picture_copy.dart (new); lib/widgets/kit/kit_compare.dart (new); lib/widgets/kit/kit.dart; lib/widgets/kit/kit_overlay.dart; lib/widgets/kit/kit_proc.dart; lib/services/firestore_service.dart; lib/state/upload_notifier.dart; lib/pages/share_page.dart; test/kit/quick_add_test.dart
- folds: 5.50.0; 5.50.1; 5.51.0
- device_test: a real-iPhone run of the camera roll over photos already uploaded from a computer: every pre-upload match and miss logged with its hash distance (PRECHECK_RADIUS is held to it, ADR-202 §Calibration) — needs Xavier's phone
- shots: sources-copy-row
- extra_gates: flutter test test/contract test/kit; iOS RunnerTests and Android unit tests: the bridge hash against spec/picture-hash.json
- notes: Xavier 2026-11-02: duplicates are listed, never dropped (row + the original's History), and the camera roll checks before it reads a photo off iCloud. Row: skip_reason already_in_library / already_in_library_not_uploaded → muted (web's Opacity 0.55, the import's duplicate row), pill and stamp 'Already in your library' tone wait, no alert glyph, View opens duplicate_of, Add anyway (already_in_library: Api.retryDocument(force: true); _not_uploaded: only on the phone whose ledger holds the asset key — fn_create_capture_session force:true then the normal render/stage/upload), never Index it anyway. doc_duplicate: chip 'Added again' (family processing), History label 'Added again', merge covers metadata.duplicate_id. Sweep: hash the pre-filter's 1024 thumbnail (screenshots: read one, network off), precheck:true with capturedAt/width/height/pictureHash before renderedJpeg; ledger verdict duplicate (terminal, keeps assetKey). Built 2026-11-02 (in-progress): Document.duplicateOf / captureAssetKey / isPictureCopy; ProcessingRow draws a copy muted at 0.55 (copyRowOpacity, every look), stage/pill/stamp 'Already in your library' tone wait, no glyph, KitArrivalSlip.muted (stamp --fg-muted, no spine), View → /reader/{duplicate_of}, Add anyway (already_in_library: runSourcePrimary copy words; _not_uploaded: CameraSweepService.addAnyway when this phone's ledger holds the key, render → stage → force session → upload, waiting until it lands), 'Adding…' while held. doc_duplicate in _kinds (Icons.layers_outlined) and sourceEventLabels; mergeActivity covers duplicate_id. Sweep: SweepExamination/SweepAsset.pictureHash, LedgerVerdict.duplicate(assetKey) (terminal), SweepLedger.holdingCopy/duplicateCount/inLibraryCount (the camera roll's Filed / in-your-library figures), precheck before renderedJpeg when all four values exist, the session carries them again, SweepPass.duplicates. Natives: PictureHash.swift (+ AssetPrefilter PORT CHANGE 3, screenshots read their thumbnail) and PictureHash.kt (+ examine), each against spec/picture-hash.json (RunnerTests/PictureHashTests.swift, app/src/test/.../PictureHashTest.kt). Remains: the device run (pre-upload match/miss distances, PRECHECK_RADIUS) and the sources-copy-row pair (needs web's frame); RunnerTests not run on a simulator (memory pressure) — the hash ran 48/48 under Mac Catalyst UIKit instead. 5.51.0 folded 2026-11-02 (ADR-202 addendum 1): Compare replaces View — CompareCopySheet (KitOverlaySheet, mark:false, phone sheet; kit_compare.dart: KitCompareColumns/Column/Stage/Foot) with This one / Already in your library, each picture read only on open via fn_get_raw_document_url (holding phone: the bridge's own thumbnail), Added {when}, how, {w} × {h}, every state of §Compare, foot Open the original / Remove this copy / Add anyway (the row's own, each closing first). The row's line KitProcOriginLine 'In your library since {date} · {how}' from OriginalRecords (shared/picture_copy.dart: one read per original, failures and removals not kept). The original is read by FirestoreService.findOwnDocument — a user_id-scoped query, because the documents rule denies a GET on a removed document (permission-denied), so a get can never say 'no longer in your library'. Uploads send origin: UploadOrigin.app ('phone'; 'computer' only for a desktop browser build) from the picker and quick add, 'share_sheet' from the share screen.
- placed: after F-154

## F-143 · Direction D: Shelves, a shelf, the shelf map, Search and Ask (5.42.0, ADR-197)
- status: done 2026-10-30
- screen: shelves, search, ask
- route: /shelves, /shelves/{id}, /shelves/map, /search, /ask
- spec: spec/screens/library.md; spec/screens/search.md; spec/screens/ask.md; spec/api/ask.md; spec/component-kit.md
- web: src/pages/ShelvesView.jsx; src/pages/map/MapView.jsx; src/pages/SearchView.jsx; src/pages/AskView.jsx; src/shared/AskAnswer.jsx; src/shared/SuggestShelves.jsx; src/kit/d/Shelves.jsx; src/kit/d/Catalogue.jsx; src/kit/d/Skeleton.jsx
- flutter: lib/pages/tags_page.dart; lib/pages/tags/shelf_page.dart; lib/pages/tags/shelf_map_page.dart; lib/pages/tags/suggest_shelves.dart; lib/pages/search_page.dart; lib/pages/search/result_d.dart (new); lib/pages/search/search_field.dart; lib/pages/search/cohesive_column.dart; lib/pages/chat_page.dart; lib/models/ask_thread.dart; lib/state/chat_notifier.dart; lib/widgets/kit/kit_d_shelf.dart (new); lib/widgets/kit/kit_ask_answer.dart (new); lib/widgets/kit/kit_d_frame.dart; lib/widgets/kit/kit_d_parts.dart; lib/widgets/kit/kit_d_library.dart; lib/widgets/kit/kit_d_shelves.dart; lib/widgets/kit/kit_relationship_map.dart; test/kit/d_shelves_test.dart (new); test/kit/d_search_test.dart (new); test/kit/d_ask_test.dart (new)
- folds: 5.42.0; F-131; F-134
- device_test: integration_test: shelves List/Grid, a shelf's sheet, Search's filters sheet, Ask's composer growing to seven lines
- shots: shelves; shelf; shelf-map; search; ask; ask-thread; ask-answer-note; ask-rail; ask-turn-failed; shelf-color-picker; shelf-letter; shelf-letter-error
- extra_gates: flutter test test/contract
- notes: Folds F-134 (Ask's written answer and quotes; its approval hold lifted by Xavier's D-in-tandem ruling) and whatever of F-131 is still open. Needs F-140. design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/. Built 2026-10-30 (b08ac93, 5b05296 + this): Shelves / a shelf / the map on KitDPage (sheet rows KitShelfRow, the crumb's ancestors via KitDBackControl.trail, Shelf settings in the panel, Delete last in Also behind §18, the map's Go to a shelf re-centring via focusN), Search (its own field, the Filters sheet, SearchResultD rows read in place; result_card/reading_pane retired) and Ask (the conversation is the page, the conversations its running head, the composer docked via KitDPage.dock) by two sub-lanes; shared kit: kitFolioText (no-break space before every folio's ·), Contents chips on --hover-strong, the wide rail's lead at its own width, KitSectionHead's wrap, KitGrowField borderless, new kit_d_shelf.dart and kit_ask_answer.dart. The device run found a shelf opened in place kept the shelf-left's state (order; the Name field would have renamed it): reset on a new shelfId (test red without it). Web 22f9461's /ask skeleton lives in F-144's AskOffPage (its test/kit/ask_off_test.dart). Folds F-134 and F-131 (both done with it).

## F-144 · Direction D: Letters, a letter, Letter settings, Settings, Notifications and Support (5.42.0, ADR-197)
- status: done 2026-10-30
- screen: letters, settings, notifications, support
- route: /letters, /letters/settings, /settings, /settings/notifications, /support
- spec: spec/screens/letters.md; spec/screens/settings.md; spec/screens/notifications.md; spec/screens/support.md
- web: src/pages/LettersView.jsx; src/pages/letters/LetterRead.jsx; src/pages/letters/ReadingsQuick.jsx; src/pages/letters/ScriptureDayView.jsx; src/pages/LetterSettings.jsx; src/pages/SettingsView.jsx; src/pages/NotificationSettings.jsx; src/pages/SupportView.jsx; src/pages/ask/AskOff.jsx; src/shared/genAI.js; src/kit/d/LetterQuick.jsx; src/kit/d/LetterPassages.jsx
- flutter: lib/app_providers.dart; lib/models/newsletter_settings.dart; lib/pages/ask/ask_off_page.dart; lib/pages/letter_settings_page.dart; lib/pages/letters_page.dart; lib/pages/letters/letter_host.dart; lib/pages/letters/letter_preview.dart; lib/pages/letters/letter_reader.dart; lib/pages/letters/pinned_sources.dart; lib/pages/letters/readings_letter.dart; lib/pages/letters/scripture_day_page.dart; lib/pages/notification_settings_page.dart; lib/pages/onboarding/steps.dart; lib/pages/onboarding/wizard.dart; lib/pages/reader_page.dart; lib/pages/settings_page.dart; lib/pages/settings/sources_section.dart; lib/pages/settings/summaries_section.dart; lib/pages/support_page.dart; lib/router.dart; lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/services/firestore_service.dart; lib/state/ai_settings_notifier.dart; lib/state/support_notifier.dart; lib/widgets/kit/kit_cards.dart; lib/widgets/kit/kit_config.dart; lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_d_frame.dart; lib/widgets/kit/kit_d_home.dart; lib/widgets/kit/kit_d_letter.dart; lib/widgets/kit/kit_d_letters.dart; lib/widgets/kit/kit_d_settings.dart; lib/widgets/kit/kit_d_shelf.dart; lib/widgets/kit/kit_d_support.dart; lib/widgets/kit/kit_letter.dart; lib/widgets/kit/kit_rows.dart; lib/widgets/kit/kit.dart; lib/widgets/sidebar.dart; lib/widgets/support_shell.dart
- folds: 5.42.0; F-133
- device_test: Letters' Contents jump to each section, Send now is held while it sends, Support's composer grows; generative AI off and back on
- shots: letters; letter-reader; letter-settings; settings; notifications; support; settings-ai-off; reader-ai-off; ask-off; onboarding-librarian
- extra_gates: flutter test test/contract
- notes: Folds F-133 (the generative-AI switch and Video reading) into D's Settings. Needs F-140. design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/.

## F-145 · Direction D: Deep study, Activity and For your review (5.42.0, ADR-197)
- status: done 2026-10-30
- screen: study, activity, review
- route: /study, /study/session/{id}, /activity, /review
- spec: spec/screens/study.md; spec/screens/activity.md; spec/screens/review.md
- web: src/pages/StudyView.jsx; src/pages/study/ProgramEditor.jsx; src/pages/study/SessionPlayer.jsx; src/pages/ActivityView.jsx; src/pages/ReviewView.jsx; src/kit/d/Ledger.jsx; src/styles/app-d-pages.css; src/styles/app-study.css
- flutter: lib/pages/study_page.dart; lib/pages/study/session_player.dart; lib/pages/study/program_editor.dart; lib/pages/activity_page.dart; lib/pages/review_page.dart; lib/widgets/kit/kit_d_study.dart (new); lib/widgets/kit/kit_d_pages.dart (new); lib/widgets/kit/kit_d_home.dart; lib/widgets/kit/kit_d_frame.dart; lib/widgets/kit/kit_d_library.dart; lib/widgets/kit/kit_headers.dart; lib/widgets/kit/kit_form.dart; lib/widgets/kit/kit_program_card.dart; lib/widgets/kit/kit_rows.dart; lib/widgets/kit/kit_empty.dart; test/kit/d_study_review_activity_test.dart (new)
- folds: 5.42.0
- device_test: integration_test: study programs and a session's sheet, Activity's When filter, the review empty state
- shots: study; activity; review; review-empty
- extra_gates: flutter test test/contract
- notes: Needs F-140. design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/. Built 2026-10-30 on web redesign-d (W5) and the released 5.42.0 (web 22f9461: Activity's empty All says 'No activity yet.', a chosen kind 'Nothing of that kind yet.'). How Deep Study Works is not built (study.md: design-only, no entry point). The session player now carries web's column (marks, reveal, grades held while written, the server's return, excerpts batched per document) and binds Space / 1-4, so the sheet's Keys figure is true. Pairs also re-shot here because these screens changed under them: study-new, study-edit (F-108), study-wait (F-110), activity-stalled, activity-retry-error. Report: ../.claude/redesign-d-2026/reports/F-145.md.

## F-146 · Direction D: the camera roll's setup, review and settings, on today's signals (5.43.0, ADR-198)
- status: done 2026-10-30
- screen: sources, settings
- route: /sources, /settings/camera-roll
- spec: spec/features/camera-roll-sweep.md; spec/screens/sources.md; spec/screens/settings.md
- web: none
- flutter: lib/pages/sources/camera_roll.dart (new); lib/widgets/kit/kit_d_camera.dart (new); lib/widgets/kit/kit_d_frame.dart; lib/widgets/kit/kit_d_library.dart; lib/widgets/kit/kit.dart; lib/pages/sources_page.dart; lib/pages/settings_page.dart; lib/router.dart; lib/services/camera_sweep_service.dart; lib/services/sweep_ledger.dart; lib/services/sweep_words.dart; lib/services/camera_sweep_bridge.dart; lib/state/camera_sweep_host.dart; test/contract/camera_sweep_screens_test.dart; test/contract/camera_sweep_service_test.dart; test/kit/d_camera_kit_test.dart; integration_test/sweep_tray_test.dart; integration_test/hold_screen_test.dart; tool/sweep_tray_test.sh
- folds: 5.43.0
- device_test: tool/sweep_service_test.sh plus an integration test of the four-step setup, Looking back, one-at-a-time review and 'Everything Is Filed' on a simulator photo library
- shots: none
- extra_gates: flutter test test/contract
- notes: Xavier 2026-10-30: D's look on today's signals. Offer only what the pre-filter measures (screenshot, or 80+ chars of on-device text; Automatic vs Review). The six kind switches, 'people, faces and IDs always passed over' and Cautious/Balanced/Trusting are declined on the record in ADR-198 and booked as a follow-up; 'cards or IDs never uploaded' would be false today. Web has no camera roll, so there is no web frame to pair: the reference is the prototype (Camera Roll Setup.html direction A, app-camera.jsx). Needs F-140. design handoff NoteLetter-design/handoff-d/README.md (mirror 2a4dd23). Redesign lane, briefs and reports in ../.claude/redesign-d-2026/.

## F-147 · A source's History folds in its Activity, matched by metadata.doc_id (5.44.0, ADR-199)
- status: done 2026-11-02
- screen: reader-history
- route: /reader/{id}
- spec: spec/screens/reader.md §History; spec/screens/reader.md §Composition; spec/decisions/ADR-199-a-sources-history-folds-in-its-activity.md; spec/data-model.md
- web: src/pages/reader/HistoryPanel.jsx; src/shared/sourceHistory.js (new); src/api.js; src/styles/app-source.css
- flutter: lib/pages/reader/history_panel.dart; lib/services/source_history.dart (new); lib/services/firestore_service.dart; test/contract/source_history_test.dart (new); integration_test/hold_screen_test.dart; integration_test/device_run_test.dart; tool/seed_history.py (new)
- folds: 5.44.0
- device_test: integration_test: the History section mounts and its All / Reading / Activity switch filters the rows
- shots: reader-history; reader-history-activity; reader-history-refused; reader-history-empty
- extra_gates: flutter test test/contract
- notes: Xavier's ruling 2 of 2026-11-01 (W2's XAVIER 1). Two reads: read_events (one-shot, limit 50) and a doc-scoped onSnapshot of activity_events (user_id == + metadata.doc_id ==, created_at desc, limit 50) over the composite index created in prod 2026-11-01. Never a title match, never the account's latest-200 window. No count; a half at its limit is labelled; a failed half is KitFailureBlock above the rows that loaded. Lane `history`, briefs and reports in ../.claude/calls-2026-11-01/.

## F-148 · How Deep Study Works, inside Study; a session's key hints hidden below 1024 (5.45.0)
- status: done 2026-11-02
- screen: study, study-how
- route: /study, /study/how-it-works, /study/session/{id}
- spec: spec/screens/study.md
- web: src/pages/study/StudyHow.jsx (new); src/pages/StudyView.jsx; src/pages/study/SessionPlayer.jsx; src/styles/app-study.css; src/styles/app-d-pages.css
- flutter: lib/pages/study/study_how.dart (new); lib/pages/study_page.dart; lib/pages/study/session_player.dart; lib/widgets/kit/kit_d_study.dart; lib/widgets/kit/kit_d_frame.dart; lib/router.dart; lib/services/analytics.dart; test/kit/d_study_review_activity_test.dart; integration_test/device_run_test.dart; CLAUDE.md
- folds: 5.45.0
- device_test: integration_test: Study's masthead link and the empty state's button open How Deep Study Works; its New program opens the editor; a session at phone width draws no key hint
- shots: study; study-how
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-01 (rulings 3 and 4): the page is built inside Study, reached from the programs masthead's standfirst link and the empty state (never onboarding); its copy is the spec's, corrected claim by claim against area_study.py (ten documents, not fifty). The references open in the system browser. Key hints (space, 1-4, the keys note, the sheet's Keys) hide below 1024; the keys stay bound. CLAUDE.md's touch-copy deviation line said 'no keys bound', false since F-145.

## F-149 · Your librarian in Letter settings, as the spec writes it (5.48.0)
- status: done 2026-11-02
- screen: letter-settings
- route: /letters/settings
- spec: spec/screens/letters.md §Your librarian; spec/screens/letters.md §Composition; spec/screens/onboarding.md; spec/api/newsletter.md
- web: src/pages/LetterSettings.jsx; src/pages/onboarding/steps.jsx; src/api.js; src/styles/app-letters.css
- flutter: lib/pages/letter_settings_page.dart; lib/pages/onboarding/steps.dart; lib/state/settings_notifier.dart; lib/services/api.dart; test/kit/d_letter_settings_support_test.dart; integration_test/device_run_test.dart; integration_test/hold_screen_test.dart
- folds: 5.48.0
- device_test: tool/device_test.sh "Your librarian: a mission typed in Letter settings is stored trimmed and read back on the next visit (F-149)"
- shots: letter-settings; letter-settings-librarian
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-02 (ruling 2d, superseding ruling 6's 'to Settings'): web's Letter settings gets the field, where this client has it and where onboarding says it is; nothing moves to Settings, whose Your librarian row stays the way into Ask on both clients. 5.48.0 (contracts 70c101a) specifies it: Composition's last field, strings verbatim from F-05 (label Your librarian; placeholder 'e.g. Help me connect ideas across philosophy readings…'; sub 'What you want to learn or achieve. Your letter weights passages by it.'). Re-scoped here to match the spec: the face mono → sans (§6.9), maxLength missionMax (1000, the endpoint's silent cut; onboarding's mission box too), held while Save is out, purposeText sent only when it differs from the last value read or accepted (it rode every Save, re-embedding each time, so an embedder failure could refuse a delivery-hour change); a refused Save keeps the draft with the server's sentence beside Save. The comment saying web edits the key in Settings is corrected. Web lane librarian, branch c/librarian (c5974ab). Briefs and reports in ../.claude/calls-2026-11-01/.

## F-151 · The OAuth return page and File under (5.46.0, ADR-201)
- status: done 2026-11-02
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-201-the-oauth-return-page-and-file-under-a-shelf.md (new); spec/screens/sources.md §The OAuth return; spec/api/cloud-storage.md; spec/features/cloud-oauth-return.md
- web: src/pages/sources/OAuthReturn.jsx (new); src/pages/sources/FileUnder.jsx (new); src/styles/app-oauth-return.css (new); src/pages/SourcesBrowse.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/intake.jsx; src/shared/cloudClaim.js; src/api.js; tests/contract/oauth-return.test.js (new)
- flutter: lib/pages/sources/oauth_return.dart (new); lib/pages/sources/file_under.dart (new); lib/pages/sources_page.dart; lib/pages/sources/cloud_sync_copy.dart; lib/state/cloud_notifier.dart; lib/state/org_notifier.dart; lib/shared/cloud_return.dart; lib/services/api.dart; lib/widgets/kit/kit_d_library.dart; test/contract/oauth_return_test.dart (new); test/contract/cloud_return_test.dart; test/contract/api_requests_test.dart
- folds: 5.46.0
- device_test: tool/device_test.sh — feed noteletter://cloud-connect?… to the app on iOS 26.5 against the emulator (run by the lane)
- shots: oauth-granted; oauth-granted-picked; oauth-already; oauth-empty; oauth-denied; oauth-expired; oauth-failed
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-01 (ruling 8): the connect flow fully implemented before he tests it. The return page renders in place of the Library on /sources while a return is open (no route); claiming, {Provider}, Connected (root listing + Manifest: two measured tallies, File under, Keep in sync, Bring in / Not now), Nothing to Bring In, and the notices Nothing Was Shared / The Link Expired (ten minutes) / Already Connected / Not Connected. org: enabled and insufficient_scope stay Library notices; the Library nudge and the auto-opened picker are retired. One connect entry point (CloudNotifier.connect), which quick add (F-152) calls; it remembers the provider it sent to consent (the session fills an error return's; a web build also keeps nl-cloud-connecting in prefs for the state's ten minutes). File under also on the import picker; Api.importFromCloud(tagIds:) sends tag_ids only when non-empty. The connect card's line is provider_email once connected. Web stacks the cards and notice actions at 860; here at the one breakpoint, 768. Android owed (no KVM).

## F-152 · Quick add: web's Add to your library overlay, from every button web opens it with
- status: done 2026-11-02
- screen: quickadd
- route: / (overlay; also /sources, every tab-bar page)
- spec: spec/screens/sources.md §Quick add; spec/screens/sources.md §Endpoints used; spec/component-kit.md §15; spec/component-kit.md §30; spec/screens/library.md §Composition
- web: src/overlays/QuickAdd.jsx; src/shared/ImageSetChoice.jsx; src/uploadTypes.js; src/App.jsx; src/pages/LibraryHome.jsx; src/pages/SourcesBrowse.jsx; src/kit/d/PhoneChrome.jsx; src/styles/app-responsive.css
- flutter: lib/widgets/quick_add.dart (new); lib/widgets/kit/kit_quick_add.dart (new); lib/widgets/kit/kit_empty.dart; lib/widgets/kit/kit_overlay.dart; lib/widgets/kit/kit.dart; lib/widgets/app_layout.dart; lib/pages/library_page.dart; lib/pages/sources_page.dart; lib/pages/add_source_page.dart; lib/router.dart; lib/state/upload_notifier.dart; lib/shared/upload_types.dart; lib/services/resumable_upload.dart; lib/widgets/file_uploader.dart; test/kit/quick_add_test.dart (new); integration_test/device_run_test.dart; integration_test/hold_screen_test.dart; integration_test/fake_picker.dart (new)
- folds: 5.47.0
- device_test: tool/device_test.sh "quick add opens from every entry point, files a link, asks the one-source question, and More options → is Add a source (F-152)" (a throwaway account; one real fn_ingest_url through the shim)
- shots: quickadd-image-set
- extra_gates: flutter test test/contract; flutter test test/kit/quick_add_test.dart
- notes: Xavier 2026-11-01 (ruling 8, 2nd round): Flutter gets web's quick-add overlay. Entry points as web's: Home's Add a source (the tab bar's centre on a phone), the Library's, the tab bar's default Add, Home's checklist Add your first source, an empty Home's Paste a link and drop zone (picks first, then opens quick add filing it); only More options → opens Add a source (/sources/add; the Add page's pick flag is gone). Anatomy and strings verbatim from web; touch copy (Drop files, or tap to add one); this client's Add an image set row kept under the link row (KitImageSetRow, one spelling for its three surfaces). The one-source question (KitImageSetChoice, ADR-170) is asked here for 2+ images in one pick — 5.47.0 (contracts 2d974c5) specifies quick add (sources.md §Quick add) and widens 'Web asks' to Flutter's quick add. Rows are UploadNotifier's own (onRow gives the id before any request; a refusal at the door has no row and is drawn here); uploads outlive the sheet. Connect is CloudNotifier.connect (F-151) awaited: a refusal is KitFailureInline '{name} — {sentence}' under the chips, a cancelled session leaves the chip pressable, a held return closes the sheet and goes to /sources. On a phone (KitD.phone, 680) the §15 sheet rises from the foot (KitOverlaySheet phoneSheet: grab handle, swipe, scrim or ×) — a recorded deviation; wider it is web's 540/82% dialog with §15's foot. The link field takes focus on open only on a desktop/web build. Error chip drawn on --critical-text (web's falls through to the positive chip: reported). No flight animation (the kit has no motion; ruling 5). Lane quickadd, brief and report in ../.claude/calls-2026-11-01/.

## F-156 · The connect page's own route, Notion arrives ticked, and no File under (5.52.0, ADR-203)
- status: done 2026-11-03
- screen: sources
- route: /connect/:provider
- spec: spec/decisions/ADR-203-the-connect-page-has-its-own-address.md (new); spec/screens/sources.md §The OAuth return; spec/screens/sources.md §Cloud import; spec/api/cloud-storage.md; spec/features/cloud-oauth-return.md; spec/clients/flutter.md
- web: src/pages/ConnectReturn.jsx (new); src/shared/connectHandoff.js (new); src/shell/useRoute.js; src/pages/sources/OAuthReturn.jsx; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/SourcesBrowse.jsx; src/App.jsx; tests/contract/oauth-return.test.js
- flutter: lib/router.dart; lib/pages/sources/oauth_return.dart; lib/pages/sources_page.dart; lib/state/cloud_notifier.dart; lib/shared/cloud_return.dart; lib/services/api.dart; lib/services/analytics.dart; lib/widgets/quick_add.dart; lib/pages/settings/sources_section.dart; lib/widgets/kit/kit_d_chrome.dart; lib/widgets/sidebar.dart; test/contract/oauth_return_test.dart; test/contract/cloud_return_test.dart; test/contract/sources_harness.dart; integration_test/device_run_test.dart; integration_test/hold_screen_test.dart
- folds: 5.52.0
- device_test: tool/device_test.sh "the connect page: an app return for Notion opens /connect/notion, every page arrives ticked, no File under, and Bring in lands on Sources with its notice (F-156)"
- shots: oauth-granted-notion-ticked
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-02, connecting Notion on web the day after F-151: everything Notion shared should arrive ticked, there should be no File under, and the return should be its own URL. (1) The app's noteletter://cloud-connect return opens the return page as its own go_router route, /connect/:provider (or /connect with no provider named), never in place on /sources; Back leaves for /sources; Bring in / Not now / Back to library go to /sources with the notice (web hands it over through shared/connectHandoff.js). org: enabled and insufficient_scope still land on the Sources notices. (2) Notion only: every item the root listing returns is ticked as it arrives, the first page and each Load more, up to the caps (50 pages, 20 databases); when a cap leaves items unticked, the line 'The first {50 pages | 20 databases} are ticked — one import takes {50 | 20} at a time. Bring these in, then choose the rest from the Library.' Drive/OneDrive/Dropbox: nothing ticked (unchanged). Web's tickOffer/capLines in OAuthReturn.jsx are the reference. (3) Delete file_under.dart; remove File under from the return page's Manifest (and the shelf from its peek) and from the import picker; Api.importFromCloud keeps tagIds (the endpoint still accepts it) but nothing passes it. Flutter route row in spec/clients/flutter.md says queued — flip it to composed when done. Built 2026-11-03 (b55bd82); its device run and pair waited until the machine had memory headroom. The app shell (ConnectOnReturn, around AppLayout's pages) goes to /sources and pushes /connect/{provider} a frame after a return is held; an open ConnectPage answers a return in place. A web build's /connect?cloud_connect=… (and the old /sources?…) is held by the routes' redirect (holdConnectReturn) and leaves the address. Leaving hands note / org enabled / insufficient_scope to the Library through ConnectHandoff (the kickoff is CloudNotifier's already). Tab bar and rail light Library on /connect. screen_name is 'connect' for both patterns: keyed on the pattern, the provider is a :parameter (web sends connect-{provider}). The device test and the hold state stand in for Notion's root listing (an adapter over fn_list_cloud_files?provider=notion): the shim's Notion workspace lists nothing. Bring in's real fn_import_from_cloud took those ids: 202, 1 folder and 2 files queued, and the shim dropped the three tasks (one database discovery, two pages) as it drops every enqueue. Web's reference is theme-shots' oauth-granted-notion-ticked (web c263593, oauth-notion's state); oauth-notion.web.* (11-01) predates 5.52.0 and still shows the offer unticked. 11-03 12:08 attempt stopped before the build: "NL Flutter agent 17 Pro" (432E0C97, moved to /Volumes/DevCache and symlinked back) does not boot — CoreSimulatorService gets EPERM (NSCocoaErrorDomain 513) writing data/Deleting-… through the symlink, while a user shell can write there; a temporary internal sim's first boot ran 20+ min under load up to 337 while swap grew 29.7→38.9 GB and free disk fell 18.0→5.7 GB, so it was shut down and deleted at the 6 GB alarm. DONE 13:07: on the fresh internal "NL Flutter agent 17 Pro" (E37D2F70, iOS 26.5) the device test passed ("3 of 3 ticked, no File under", "Bring in → /sources with its notice"); the pair shot at load 19.8 and looked at. The first 13:00 build failed to link (undefined _OBJC_CLASS_$_FlutterAppDelegate…): build/ios/Debug-iphonesimulator/Flutter.framework and App.framework had lost their binaries in build/'s move to DevCache, and the copy step does not replace a framework directory that exists — removing those two directories fixed it (never flutter clean: build/ is a symlink).
- placed: after F-152

## F-157 · Cloud import batches: no 50-file cap, Notion's offer listed to its end (5.56.0, ADR-208)
- status: done 2026-11-04
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-208-an-import-is-not-one-request.md (new); spec/features/cloud-import-batches.md (new); spec/screens/sources.md §Cloud import; spec/screens/sources.md §The OAuth return; spec/screens/sources.md §Import job status; spec/api/cloud-storage.md
- web: src/api.js; src/pages/sources/CloudFilePicker.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/OAuthReturn.jsx; tests/contract/cloud-import-batches.test.js; tests/contract/oauth-return.test.js
- flutter: lib/services/api.dart; lib/state/cloud_notifier.dart; lib/pages/sources/cloud_picker.dart; lib/pages/sources/oauth_return.dart; lib/pages/sources_page.dart; lib/services/firestore_service.dart; test/contract/cloud_import_batches_test.dart (new); test/contract/oauth_return_test.dart; test/contract/api_requests_test.dart
- folds: 5.56.0
- device_test: tool/device_test.sh "the import picker ticks past 50 files and Bring in on the connect page sends 50 to a request, the folders in the first; Notion's offer lists to its end with Bring in held (F-157)"
- shots: oauth-granted-notion-ticked
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-03: the 50-item limit should not make a reader come back and remember to import the rest. Web is the reference (api.js importFromCloud, IMPORT_FILE_BATCH, importJobsWindow; OAuthReturn.jsx tickOffer/capLines/load/bringIn; CloudFilePicker.jsx partialImportSentence). (1) Api.importFromCloud sends more than 50 fileIds as consecutive requests of <=50 in tick order, ONE AT A TIME: the first carries folder_ids, folder_names and any settings with the first 50; each later one carries provider + file_ids only (tag_ids on every batch if sent: none is). <=50 is one request, byte-identical. Returns the 202s' sums; an onProgress(sent, total) after each 202; a refusal after an accepted batch is thrown carrying partial {queued_folders, queued_files, sent, unsent}, a refused first request carries none. (2) No file cap on the import picker (kMaxImportFiles goes; folders stay 20, never split: each folder request replaces sync_config.folder_ids); counter '{f}/20 folders · {n} files'; the 50-file cap note goes, the 20-folder one stays. (3) Progress: 'Queuing… {sent} of {n} files' (picker) / 'Bringing in… {sent} of {n} {files|pages}' (connect page) only when more than one request. (4) Partial outcome: the surface stays open, the unsent files stay ticked and the folders untick; failure slot 'Queued {q} of {n} files. The other {r} were not sent — {sentence}' ('Queued {f} folder(s)|database(s) and …' when folders went); the confirm sends the rest; the picker's kickoff joins the rest (one import, one notice with the sums; the completion notice keyed on start + sums); the connect page's Not now after a partial still hands the Library the queued note. (5) Connect page, Notion only: every listed page ticked (databases up to 20); the listing follows nextPageToken itself, up to 20 listing pages a run (Load more starts another run; Try again after a failed later page continues from its token and keeps unticks); Bring in held as 'Listing what Notion shared…' while it follows; capLines only the databases' line. Drive/OneDrive/Dropbox not followed. (6) subscribeCloudImportJobs limit = max(50, queued_files + 50), at most 500, while a kickoff is held; the history footer says 'Showing the most recent {limit} import jobs.'
- placed: after F-156

## F-158 · A duplicate row draws its sentence; the Notion note; Keep in sync survives a refused batch (5.57.0, ADR-209 + ADR-210)
- status: done 2026-11-04
- screen: sources
- route: /sources
- spec: spec/decisions/ADR-209-a-direct-import-asks-whether-the-file-is-already-in-the-library.md (new); spec/decisions/ADR-210-a-notion-page-keeps-what-it-links-to.md (new); spec/screens/sources.md §Trust & feedback; spec/screens/sources.md §Cloud import; spec/api/cloud-storage.md
- web: src/pages/sources/CloudImportPanel.jsx; src/pages/sources/OAuthReturn.jsx; tests/contract/update-from-source-row.test.js; tests/contract/oauth-return.test.js
- flutter: lib/pages/sources_page.dart; lib/state/cloud_notifier.dart; lib/pages/sources/oauth_return.dart; test/contract/cloud_sync_tandem_test.dart; test/contract/oauth_return_test.dart; test/contract/cloud_import_batches_test.dart
- folds: 5.57.0
- device_test: tool/device_test.sh "a duplicate import row shows its sentence; the Notion picker shows the note (F-158)"
- shots: none
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-04, after the 61-page Notion import: re-ticks must not duplicate, and Notion pages keep images and links. Backend 5.57.0 (fn_sync_cloud_storage 00035-jom) makes a direct import's duplicate a skipped row with a sentence; web 543861d. Flutter, built 2026-11-04 in the main session: (1) a duplicate row draws its error_message under Already imported (sources_page.dart: !job.isDuplicate removed); (2) the Notion note above the import picker, web's word for word (read from web's source by cloud_import_batches_test); (3) CloudNotifier.bringIn applies Keep in sync on a refused batch whose first request carried folders, since the folders untick and the next Bring in has none (found by the F-157 port, fixed on web the same hour). Tests: tandem +1, oauth_return +1, batches +1; flutter test test/contract test/kit -x pin 2383 pass; analyze clean.
- placed: after F-157

## F-159 · The documents window is 2,000 and a full one says so; a Notion page link opens the library's copy (5.58.0, ADR-211 + ADR-212)
- status: done 2026-11-04
- screen: reader
- route: /reader/{docId}
- spec: spec/decisions/ADR-211-the-library-reads-the-whole-library.md (new); spec/decisions/ADR-212-a-link-to-a-notion-page-in-the-library-opens-it-there.md (new); spec/screens/reader.md §A link to a Notion page in the library; spec/screens/reader.md §The way back; spec/screens/sources.md §Library reading summary; spec/screens/library.md §Composition (Folio)
- web: src/shared/documentWindow.js; src/shared/plural.js; src/App.jsx; src/pages/SourcesBrowse.jsx; src/pages/LibraryHome.jsx; src/pages/map/relmapGraph.js; src/shared/notionLinks.js; src/api.js; src/pages/reader/ManuscriptPanel.jsx; src/pages/ReaderView.jsx; src/shell/backOrigin.js; tests/contract/library-window.test.js; tests/contract/library-window-folios.test.js; tests/contract/notion-page-links.test.js
- flutter: lib/services/firestore_service.dart; lib/shared/relmap_layout.dart; lib/pages/sources_page.dart; lib/pages/library_page.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader_page.dart; lib/shared/reader_origin.dart
- folds: 5.58.0
- device_test: tool/device_test.sh "the Library and Home folios over a full documents window read 2,000+; a Notion sub-page link in a page opens the sub-page in the Reader, and Back names the parent (F-159)"
- shots: none
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-04: 'How come my library count didn't increase when I connected all those documents from notion?' — the window was the newest 200 and the folios printed it as the library (551 complete volumes read '200'). And, on ADR-210's sub-page links, 'the links should point to the subpages.' Web reference built 2026-11-04. Flutter, built 2026-11-04 (lane): ADR-211 — documentWindow 2000 is ONE const, lib/shared/document_window.dart (relmap_layout re-exports it; subscribeDocuments defaults to it), windowFull() counted over every row; the Library folio draws 'N+ volumes' (kitCountedFloor), Home's 'N+ sources · N+ passages', the reading figures' line keyed on the whole window and printing 'Of your most recent 2,000.'; the shelves standfirst and the map legend print the window with separators; the test doubles' limit = 200 went with it. ADR-212 — lib/shared/notion_links.dart (the id rule, the dashed id, the drawn rewrite, the lookup rule resolveNotionPagesWith) under FirestoreService.resolveNotionPages (notionImportJobs: user_id ==, provider_file_id in, at most 30 a query; getDocument for a candidate the subscription does not hold). ManuscriptPanel looks up when drawn, once per set of linked pages and only when it can open a source; redraws a resolved anchor at rest only (href /reader/{id}, data-nl-doc, no target), never in c.html; onLinkTap opens a resolved one through onOpenSource (ReaderPage pushes /reader/{id}?from=/reader/{parent}) and any other http(s) link outside through onOpenLink. Manuscript links were DEAD taps on this client until now (no onLinkTap), so every manuscript web link now opens, as web's target=_blank. readerOrigin names /reader/{docId} by the title the documents subscription holds, else Source; a pushed reader pops back. Tests: notion_page_links_test 17, library_window_test 5 (a REAL 2,000-row window: a Dart const cannot be mocked as web's 12; each pump ~15 s under load); 24 mutations, all red; flutter test test/contract test/kit -x pin 2405 pass; analyze clean.

## F-160 · A connected service has its own page; an import row says where it landed (5.59.0, ADR-213)
- status: done 2026-11-04
- screen: service-page
- route: /sources/:provider
- spec: spec/decisions/ADR-213-a-connected-service-has-its-own-page.md (new); spec/screens/sources.md §A service's page, §Cloud import, §Trust & feedback, §Sync control; spec/component-kit.md §33 Cover lead; spec/screens/settings.md §Sources section
- web: src/pages/ServicePage.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/sources/intake.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/shared/ProviderLogo.jsx; src/kit/d/Cover.jsx; src/shell/useRoute.js; src/shell/backOrigin.js; tests/contract/service-page.test.js
- flutter: lib/pages/sources/service_page.dart (new); lib/pages/sources/cloud_imports.dart (new); lib/pages/sources_page.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/import_review_queue.dart; lib/pages/sources/cloud_picker.dart; lib/widgets/kit/kit_provider_logo.dart; lib/widgets/kit/kit_d_covers.dart; lib/shared/reader_origin.dart; lib/router.dart
- folds: 5.59.0
- device_test: tool/device_test.sh "Manage opens a service's page; a row shows its shelves and opens its source; Disconnect confirms there and returns to the Library (F-160)"
- shots: service-page; service-notion; service-notion-types; library-services; import-activity; import-activity-failed
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-04, on the Library's cloud section: shelves on the rows, a row that opens its source, the new note icons, a white Notion mark in dark mode, Manage instead of Disconnect with the service's controls on a page of their own, and the unclear type control. Web RELEASED first. Also owed by this item: Settings' link to organized folders goes to the service's page, the connect page's fine print says Manage, and an expired row on the Library says Sign-in expired with Reconnect beside Manage. KitProviderLogo's Notion mark is black on a dark page today, so check every bare mark, not only the plates. Xavier approved the look 2026-11-04. Cloud brief: umbrella `.claude/cloud/README.md` lane F.

## F-161 · A sheet's controls come first; its way back follows the scroll (5.60.0, ADR-214)
- status: done 2026-11-04
- screen: reader-way-back
- route: every page with a KitDSheet; the order on /sources, /search, /shelves/map
- spec: spec/decisions/ADR-214-a-sheets-controls-come-first-and-its-way-back-follows-the-scroll.md; spec/features/sheet-controls-and-way-back.md; spec/component-kit.md; spec/screens/sources.md; spec/screens/search.md; spec/screens/library.md
- web: src/kit/d/Sheet.jsx; src/kit/d/Page.jsx; src/kit/d/Masthead.jsx; src/pages/SourcesBrowse.jsx; src/pages/SearchView.jsx; src/pages/map/MapView.jsx; src/styles/app-redesign-d.css
- flutter: lib/widgets/kit/kit_d_frame.dart; lib/widgets/kit/kit_d_parts.dart; lib/pages/sources_page.dart; lib/pages/search_page.dart; lib/pages/tags/shelf_map_page.dart
- folds: 5.60.0
- device_test: tool/device_test.sh "scrolled past the crumb, the sheet opens on the way back and a tap goes where the crumb goes; the Library's sheet leads with Order (F-161)"
- shots: reader-way-back; sources-sheet; search; shelf-map
- extra_gates: flutter test test/contract
- notes: Xavier 2026-11-04: 'In the side panels, all sort/filter options should be near the top. Also, if there is a back button, when the page is scrolled it should be at the top of the side panel, so the user doesn't have to scroll up to get to it.' He approved the look on web the same day. Web is the reference: Sheet.jsx useCrumbGone (the masthead crumb outside the page's primary scroller) and SheetBack; Page.jsx hands the sheet its back, so no page names it. Order: the Library KitLibOrder, then Kind, then Shelf; Search Read as, Breadth, then Kind; the map Go to a shelf, then On the map, then Also (and its header comment at shelf_map_page.dart). The row is drawn only while the crumb is off screen, so a page at its top has one back control; it carries a sub-shelf's whole trail (KitDBackControl's trail); it stays pinned when the sheet scrolls inside itself, and on web that needed a sticky offset, which a Flutter layout that pins it above the scrolling body does not. On a phone it heads the running head's dropped sheet, never the line. A stacked (static) sheet draws no row. Web's real-gesture proof is npm run gate:sheet-back.
- placed: after F-160

## F-162 · Letters sent counts the letters that were sent; Ask's Try again is text weight (5.60.1)
- status: done 2026-11-04
- screen: letters
- route: /letters; /ask
- spec: spec/screens/letters.md; spec/screens/ask.md
- web: src/pages/LettersView.jsx; src/pages/AskView.jsx
- flutter: lib/pages/letters_page.dart; lib/pages/chat_page.dart; lib/services/api.dart
- folds: 5.60.1
- device_test: tool/device_test.sh "Letters sent counts sent letters; a refused Ask turn offers Try again at text weight (F-162)"
- shots: letters; ask-turn-failed
- extra_gates: flutter test test/contract
- notes: 5.60.1 is web's cloud lane W, taken as 5.59.1 on the lane. Web's tests are the acceptance list: letters-sent-figure.test.js, ask-refused-turn.test.js. Also correct the stale comment above missionMax in lib/services/api.dart: since 5.61.0 the endpoint refuses past the bound (fn_newsletter_settings).

## F-170 · The letter's host holds the paper at 680 (5.66.0, ADR-235)
- status: done 2026-11-04
- screen: letters
- route: /letters
- spec: spec/api/newsletter.md; spec/screens/letters.md
- web: src/styles/app-kit.css
- flutter: lib/widgets/kit/kit_letter.dart; test/kit/kit_smoke_test.dart
- folds: 5.66.0
- device_test: none
- shots: letter-reader
- extra_gates: flutter test test/kit/kit_smoke_test.dart --plain-name "a letterheaded body is wrapped"
- notes: The renderer moved, so every new letter reaches this host wider. The host's cap goes 640 to 680 and its prose stops describing a fixed sheet. A phone never reaches the cap, so the frame is about the letter, not the rule: re-seed with tool/seed_letters.py (the real renderer), then shoot and look at a passage's column at phone width. Number held for local work by TODO's round 3 line, so it is not max+1.

## F-171 · A control whose request is in flight says it is working (5.72.0, ADR-237)
- status: done 2026-11-05
- screen: all
- route: /letters
- spec: spec/component-kit.md
- web: src/shared/BusyMark.jsx
- flutter: lib/widgets/kit/kit_busy_mark.dart; test/kit/busy_mark_test.dart
- folds: 5.72.0
- device_test: none
- shots: none
- extra_gates: python3 ../NoteLetter-contracts/harness/busy_mark_check.py --only flutter
- notes: KitBusyMark is the one drawing, and every kit control that sends takes a `busy`. The pressed control draws it; its held siblings stay plain. Built with web in one run, and drawn in a widget-test image in both themes. It has not been seen on a simulator or a phone.

## F-172 · Shelves at add: quick add, Add a source, the share sheet on both platforms (5.73.0, ADR-238)
- status: done 2026-11-05
- screen: sources
- route: /share
- spec: spec/component-kit.md; spec/screens/share-sheet.md; spec/screens/sources.md; spec/features/shelves-at-add.md
- web: src/shared/AddShelves.jsx; src/overlays/QuickAdd.jsx; src/api.js
- flutter: lib/services/api.dart; lib/state/upload_notifier.dart; lib/widgets/quick_add.dart; lib/pages/add_source_page.dart; lib/pages/share_page.dart; ios/Share/UploadViewModel.swift; ios/Share/ShareView.swift
- folds: 5.73.0
- device_test: none
- shots: none
- extra_gates: none
- notes: Kit §20.3 over a local choice on quick add, Add a source and /share; the iOS extension reads tags over Firestore REST and holds the create form in SwiftUI. Nothing is written until the host adds; every add carries tagIds, with no key when none is chosen. See spec/features/shelves-at-add.md.

## F-173 · A confirmation stands where web's does: 11vh from the top, 8vh at 680 wide or narrower (5.74.0)
- status: done 2026-11-05
- screen: summary-reset-confirm
- route: /settings
- spec: spec/component-kit.md §18
- web: src/styles/app-responsive.css
- flutter: lib/widgets/kit/kit_confirm.dart; test/kit/confirm_placement_test.dart
- folds: 5.74.0
- device_test: none
- shots: summary-reset-confirm; reader-reprocess-confirm
- extra_gates: none
- notes: Material's AlertDialog stood halfway down; web's panel sits on §15's scrim padding since 4.56.0. Found twice (TODO's burn-down and F3's frames), and §18 said only 'centred', which both clients could claim. Widget test at 390, 680, 1024 and 320, red on three mutants. Frames re-shot 2026-11-05 after F-172 on the simulator and looked at: both panels stand near the top, in the place the widget test measures.

## F-174 · A passage's own h2 in a letter already sent is not a card (5.74.0, ADR-087 addendum 1)
- status: done 2026-11-05
- screen: letters
- route: /letters
- spec: spec/api/newsletter.md §The letterhead
- web: src/kit/d/letter.js
- flutter: lib/widgets/kit/kit_d_letter.dart; lib/widgets/kit/kit_letter.dart; test/contract/letter_sections_built_test.dart
- folds: 5.74.0
- device_test: none
- shots: none
- extra_gates: none
- notes: kitLetterSections and the letter page's own script took every h2 as a card, so a stored passage's heading read as one more passage with no source, on 4 of 44 real letters, and on Home could push a real one out of the first three. The renderer steps them down from 5.74.0; this reads what was already mailed. The script runs in a web view, so a device run owes it: its source is held to the rule by a string test.

## F-175 · A page changes plainly, on web's paper
- status: done 2026-11-06
- screen: library
- route: /
- spec: spec/component-kit.md §40; spec/component-kit.md §1.1; spec/design-tokens.md
- web: src/styles/theme.css; src/styles/app-kit.css
- flutter: lib/theme/app_page_transitions.dart (new); lib/theme/app_theme.dart; lib/widgets/kit/kit_ground.dart; lib/main.dart; lib/pages/onboarding/wizard.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader/speed_read_panel.dart; lib/site/landing_page.dart; lib/site/landing_reel.dart; test/kit/page_change_plain_test.dart (new); test/kit/ground_test.dart (new); test/kit/split_review_test.dart; tool/bake_grain.cjs (new); assets/paper/grain.png (new); integration_test/hold_screen_test.dart; pubspec.yaml
- folds: Xavier 2026-11-05
- device_test: none
- shots: library; sources; letters; letter-reader; letter-settings; scripture-day; notifications; settings; support; study; shelves; shelf-create-sheet; shelf-color-picker; proc-affordances; source-file; source-set; recipe; reader; reader-history; reader-manuscript; reader-speed-read; reader-listen; reader-shelves; shelf-picker-search; reader-reprocess-confirm; reader-edit-drag; reader-mark-as-read; ask-thread; onboarding; onboarding-librarian; settings-ai-off; reader-ai-off; ask-off; signin; signin-fail; landing-actual
- extra_gates: flutter test test/kit/page_change_plain_test.dart test/kit/ground_test.dart
- notes: Xavier: weird animations opening a page; the paper is not web's. A recording showed each route change sliding 430ms with the new page's text over the old, since a shell page has no background of its own; §40 already said a client without view transitions changes plainly. Durations went to zero in the theme, keeping the platform builders, so iOS's edge swipe and Android's predictive back still move a page. The paper: KitGround was a 48px ink speckle averaging 245 on white where web averages 250. Grain is now web's own pixels (tool/bake_grain.cjs), the lattice computed at screen pixels: 250.0 on both. A zero-length pop finishes inline, so a test that popped a navigator's ONLY route now asserts; split_review_test hosts its sheet as the app does. Three holds (scripture-day, source-file, source-set) had not run since direction D: they looked for KitProcCard and an uncapped back label.

## F-176 · The app icon: bookcloth, white, pressed (Xavier 2026-11-06)
- status: done 2026-11-06
- screen: app-icon
- route: none
- spec: spec/features/app-icon.md
- web: scripts/build-favicons.mjs; public/favicon.svg; public/favicon.ico; public/apple-touch-icon.png
- flutter: tool/app_icons.mjs; ios/Runner/AppIcon.icon/icon.json; ios/Runner.xcodeproj/project.pbxproj; ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json; android/app/src/main/res/drawable/ic_launcher_foreground.xml; android/app/src/main/res/drawable/ic_launcher_monochrome.xml; android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml; test/contract/app_icon_test.dart
- folds: Xavier 2026-11-06
- device_test: none
- shots: none
- extra_gates: flutter test test/contract/app_icon_test.dart
- notes: Taken out of order at Xavier's request: the icon is the handoff's first surface. No screen, so no pair; the proof is a home screen. A stub app holding the compiled catalog on the iOS 26.5 simulator showed a bitmap lose its weave and pressed edge to Liquid Glass and its quill turn pink, hence AppIcon.icon with every effect off. Every iOS below 26 reads bitmaps Xcode flattens from it: extracted from the .car, Any and Dark are the master pixel for pixel, Tinted a white quill on black. Not yet seen on Xavier's iPhone 12 (iOS 18.1.1) or on an Android launcher.

## F-177 · Echoes: a source's nearest passages in your other sources (5.83.0, ADR-255)
- status: done 2026-11-09
- screen: reader
- route: /reader/:docId
- spec: spec/api/echoes.md; spec/screens/reader.md §Echoes; spec/component-kit.md §43; spec/features/analytics-events.md
- web: src/pages/reader/EchoesPanel.jsx; src/pages/ReaderView.jsx; src/api.js; src/analytics.js; src/styles/app-source.css
- flutter: lib/pages/reader/echoes_panel.dart; lib/widgets/kit/kit_d_echoes.dart; lib/models/echo.dart; lib/pages/reader_page.dart; lib/pages/reader/manuscript_panel.dart; lib/widgets/kit/kit_d_parts.dart; lib/widgets/kit/kit.dart; lib/services/api.dart; lib/services/endpoint_budgets.dart; lib/services/analytics.dart; test/kit/d_echoes_test.dart; test/contract/api_requests_test.dart; integration_test/device_run_test.dart
- folds: 5.83.0
- device_test: none run; device_run_test.dart's reader tests now name seven sections and expect EchoesPanel to mount
- shots: none
- extra_gates: flutter test test/kit/d_echoes_test.dart
- notes: The seventh section, third, mounted on approach and present with generative AI off: one fn_find_echoes {docId} per mount, Try again the only second call. Kit §43 is KitEchoStandfirst / KitEchoList / KitEchoPair / KitEchoNote (kit_d_echoes.dart); KitRowHover gained a builder so the echo's arrow reads the row's hover. An echo opens /reader/{docId}?p={chunkId}&from=/reader/{this} by push and fires echo_opened. The passage head rides the Manuscript's own ?p= anchor through PassageJumps (scroll and 2.6 s flash, no navigation). On a source that is not complete Echoes draws the same Still processing state as every non-Summary section and makes no call. api_requests_test drives api/echoes (8 of 10 cases; GET 405 and the preflight are not builder calls). Frames are shot later.
## F-180 · Ledger: seven tandems that landed with no queue item to fold them (lane F4 audit, 5.25.0 to 5.80.0)
- status: done 2026-11-06
- screen: none
- route: none
- spec: CHANGELOG.md
- web: src/api.js
- flutter: lib/state/upload_notifier.dart; lib/pages/tags/shelf_page.dart; lib/pages/chat_page.dart; test/contract/letter_sections_built_test.dart; lib/services/analytics.dart; lib/pages/reader/delete_source.dart; lib/widgets/kit/kit_d_covers.dart
- folds: 5.32.0; 5.37.1; 5.63.0; 5.63.1; 5.63.2; 5.68.0; 5.69.0
- device_test: none
- shots: none
- extra_gates: none
- notes: A record, not work: lane F4 (2026-11-06) walked every CHANGELOG Flutter tandem from 5.25.0 to 5.80.0 and opened the code for each. These seven are built, but no item folds them (F-135's folds say none; the rest landed in lanes with no item), so folded-through could not pass them truthfully. Evidence, read at a0404c7: 5.32.0 F-135 b61126a, upload_notifier.dart social_video hosts = web api.js; 5.37.1 a41364d, shelf_page.dart _notFound draws KitFailureBlock *This shelf could not be read.*, test/kit/shelf_read_failure_test.dart; 5.63.0 308ad07 chat_page.dart Open wears openSource's book, 9028f52 letter_sections_built_test.dart; 5.63.1 0526ad2 analytics.dart service-{provider}; 5.63.2 66a5ff7 delete_source.dart deleteSourceBody, web's words; 5.68.0 d0e3994/436fb4e kit_d_covers.dart dim 0.94; 5.69.0 a9fc5a3 the Library file drop and the `web` dependency gone. Full table: .claude/cloud/reports/f4.md (umbrella).

## F-181 · fn_list_cloud_files: its query is built in api.dart, not at four call sites
- status: done 2026-11-11
- screen: none
- route: none
- spec: spec/api/cloud-storage.md §fn_list_cloud_files
- web: src/api.js
- flutter: lib/services/api.dart; lib/state/cloud_notifier.dart; lib/pages/sources/sync_folder_picker.dart; test/contract/api_requests_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: `Api.listCloudFiles` (api.dart:714) takes a ready-made `params` map; the keys are assembled at cloud_notifier.dart:583, :604, :756 and sync_folder_picker.dart:121. Web builds them in the builder (api.js:2258-2261). The keys are right today, but CLAUDE.md's rule is that every request is built in api.dart, because that is what api_requests_test asserts: a misspelt key at a call site would pass the suite and the picker would quietly list the provider's root. Move the keys into named parameters; the request suite then reads them. Done (lane flutter, 2026-11-11): Api.listCloudFiles(provider, {folderId, pageToken}) builds the query, each optional key sent only with a value (web api.js); the four call sites pass parameters, and SyncFolderPicker's list seam takes the builder's signature. api_requests_test drives every captured fn_list_cloud_files case through the builder and asserts its query key for key (the loop skips GETs), plus a page-token case; red until the parameters existed.

## F-182 · A document status this build does not know stays in progress, never Failed
- status: done 2026-11-11
- screen: sources
- route: /sources
- spec: spec/data-model.md §documents
- web: src/pages/sources/proc.jsx
- flutter: lib/models/document.dart; lib/pages/sources/browse_section.dart; lib/state/review_inbox.dart; test/contract/document_status_open_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: `DocumentStatus.fromString` (document.dart:11-26) maps a missing or unknown status to `error`. Web fails only a literal `error` or `skipped` (proc.jsx:70) and draws anything else as in progress; data-model.md's status is an open vocabulary (web CLAUDE.md: open vocabularies stay open). A phone user would see such a source as Failed with Retry (browse_section.dart:354), counted in For your review (review_inbox.dart:24), and the retry refused with a 409. Latent: today's backend writes only known values. Add an unknown case that reads as in progress, with a test red on the old default. Done (lane flutter, 2026-11-11): DocumentStatus.unknown takes a missing or unrecognised token (error only on a literal 'error'); it reads Processing on the work tone in every ProcessingRow look, is not in For your review, not stallable, offers no Retry and is not counted as incoming, as on web. document_status_open_test.dart was red on the old default (5 failures: Error + Retry).

## F-183 · Dead code: kit_capture.dart (owed since 5.43.0), KitRailShelfRow, ActivityItem.typeLabel, importFromCloud's tag_ids
- status: done 2026-11-11
- screen: none
- route: none
- spec: spec/component-kit.md; spec/api/cloud-storage.md
- web: src/api.js
- flutter: lib/widgets/kit/kit_capture.dart; lib/widgets/kit/kit.dart; lib/widgets/kit/kit_shell.dart; lib/models/activity_item.dart; lib/services/api.dart
- folds: 5.43.0
- device_test: none
- shots: none
- extra_gates: none
- notes: (1) 5.43.0's Flutter tandem deletes lib/widgets/kit/kit_capture.dart with kit §23 (CHANGELOG.md:1806 says deleted). F-146 is done, but the file is there, exported at kit.dart:21, and nothing uses KitCaptureCard or KitCaptureRail. (2) KitRailShelfRow (kit_shell.dart:910) lost its last caller when direction D retired the rail's shelf tree (web AppShell.jsx:73-75). (3) ActivityItem.typeLabel (activity_item.dart:94) ends `default: return type`, the shape CLAUDE.md forbids; nothing calls it. (4) `Api.importFromCloud` still takes `tagIds` and would send `tag_ids` (api.dart:733-787), which the server refuses with 400 UNKNOWN_KEYS since 5.62.0 (cloud-storage.md:265); its comment says the endpoint still accepts it. No caller passes it. Web tandem: the same dead parameter at api.js:2300 (not edited here). No user sees any of this; it is what the next reader trusts. Done (lane flutter, 2026-11-11): each verified unreferenced first. (1) kit_capture.dart and its kit.dart export deleted; QUEUE's retired-paths names it for F-125. (2) KitRailShelfRow deleted; its one reference was device_run_test's findsNothing, now a comment (nothing can draw it). (3) ActivityItem.typeLabel deleted (statusLabel's default is a neutral phrase, not the token). (4) importFromCloud takes no tagIds and sends no tag_ids; cloud_import_batches_test asserts no batch carries it; api_requests_test's adapter drops the key, so cloud:import-tag-ids-retired is asserted only as a 400 the builder does not resolve on. The web tandem (api.js:2300's same dead parameter) is not edited here.

## F-184 · Listen plays the user's own recording: an uploaded audio or video file is never offered narration
- status: open
- screen: reader
- route: /reader/:id
- spec: spec/screens/reader.md §Listen
- web: src/pages/reader/ListenPanel.jsx
- flutter: lib/pages/reader/listen_panel.dart; lib/services/api.dart; lib/widgets/kit/kit_empty.dart; test/contract/listen_load_test.dart
- folds: none
- device_test: an uploaded recording plays itself in Listen and is never offered narration
- shots: none
- extra_gates: none
- notes: Bug. listen_panel.dart:66-67 and :113-121 take the source audio from `source_audio_url` alone. An uploaded recording (type `audio`, ADR-046) or video (`video`, ADR-049) has that field null BY DESIGN; its URL is minted per request by fn_get_raw_document_url. Web tests type-or-field and fetches it (ListenPanel.jsx:29-79), drawing *Loading the recording…* (:166). Flutter draws *No narration yet.* and Generate audio (:278-290): the phone user is offered a synthesized voice reading the transcript of their own recording, which reader.md forbids ("never offer TTS for a document that has its own audio"). Api.getRawDocumentUrl exists (api.dart:417). Built (lane flutter, 2026-11-11, the commit naming F-184): an uploaded audio or video (hasOwnAudio, type OR field) asks fn_get_raw_document_url on mount and plays the signed URL; until it answers Listen says Loading the recording… and never offers Generate audio; a URL that does not come back says This recording could not be loaded., a refusal its own sentence. listen_load_test drives both types and the missing URL (red on the old panel); its audio plugin's global scope now starts in setUpAll, as listen_speed_test's does. Web's eyebrow and note stay keyed to source_audio_url, so an uploaded recording reads '· narration' on both clients (booked as a web finding, not changed here). OPEN only for its device_test: no device in this wave.

## F-185 · Original shows the extraction beside the file: the captured page, the embed or poster, the text as read
- status: done 2026-11-11
- screen: reader
- route: /reader/:id
- spec: spec/screens/reader.md §Original; spec/component-kit.md §15.1
- web: src/pages/reader/OriginalPanel.jsx
- flutter: lib/pages/reader/original_panel.dart; lib/widgets/kit/kit_overlay.dart; lib/pages/reader_page.dart; CLAUDE.md; test/kit/original_extraction_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Gap. original_panel.dart:136-184 and :243-272 draw the stored file, or a button for a link, under the line *NoteLetter keeps the original alongside the text it extracted.* (:178), and then never shows that text. Web's panel (OriginalPanel.jsx:249-397) also draws what was extracted: *The page as we captured it* / *The document as we read it* / *The article it resolved to*, a YouTube/Instagram/TikTok embed or the provider's poster (embedFor, :86-110), and the raw extraction. component-kit §15.1 rule 3: the extraction belongs to the panel that composes the renderer, which is why the reader shows both. Port the parts a phone can draw; an embed is a web view, so decide it inside the item and record any deviation in CLAUDE.md. The intro copy differs too. Done (lane flutter, 2026-11-11): every shape now draws what was read beside the source, from the chunks the reader holds (ADR-004): The page as we captured it (a link), The document as we read it (a file or set), The article it resolved to (a screenshot), The full text, before the recipe (a recipe, fetched from original_content_url; a failed fetch says so and keeps the link). The raw text, collapsed with its word count, where the render is not the text (a screenshot, a recipe). Three kit parts beside §15.1's viewer in kit_overlay.dart: KitExtractionPreview (.pdf-viewer + .orig-render), KitRawText (.orig-raw), KitPoster (.orig-poster; gone when the image does not load). Intro copy is web's. The decision the item asked for: web's live iframe (YouTube, Instagram, TikTok) is NOT ported — a link draws the provider's poster (thumbnail_url, else the page's lead image) beside Open on {host}; recorded in CLAUDE.md's deviations as 'Original: poster, not embed (F-185)'. original_extraction_test (red first: the panel took no chunks) covers link, file, screenshot with raw text, a video's poster and a 390 phone. No frame pair was asked or taken.

## F-186 · Three sentences in web's words: the sign-in link, the import status, an apostrophe
- status: done 2026-11-11
- screen: sources
- route: /sources
- spec: spec/screens/sources.md
- web: src/pages/sources/intake.jsx; src/overlays/QuickAdd.jsx; src/pages/sources/OAuthReturn.jsx; src/pages/sources/CloudImportPanel.jsx; src/pages/reader/ManuscriptPanel.jsx
- flutter: lib/state/cloud_notifier.dart; lib/state/org_notifier.dart; lib/pages/sources/cloud_imports.dart; lib/pages/reader/manuscript_panel.dart; lib/shared/cloud_return.dart; lib/pages/sources_page.dart; lib/pages/sources/service_page.dart; test/contract/cloud_return_test.dart; test/contract/stream_builder_failure_test.dart; test/kit/quick_add_test.dart; test/contract/manuscript_copy_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: (1) When connect returns no sign-in link, Flutter says *No authorization URL returned.* (cloud_notifier.dart:449, org_notifier.dart:186), developer wording on the Library rows, quick add and the connect page. Web and sources.md:876-878: *The sign-in link did not come back. Try connecting again.* (2) An import-status read that fails draws only the raw error (cloud_imports.dart:105-116); web says *Import status could not be read — {detail}* (CloudImportPanel.jsx:793-794). (3) manuscript_panel.dart:1199 writes "it's" with a straight apostrophe; web's is curly (ManuscriptPanel.jsx:1051). Done (lane flutter, 2026-11-11): (1) signInLinkMissing() (shared/cloud_return.dart) says The sign-in link did not come back. Try connecting again. — or Try reconnecting. where the reader pressed Reconnect (CloudNotifier.connect again:, from the Library row's Reconnect and the service page, as web's intake.jsx and CloudImportPanel do); OrgNotifier.enableOrganization says the connect form (web's enable says nothing at all). (2) importStatusUnread: Import status could not be read — {detail}, in both of cloud_imports.dart's failure slots. (3) the manuscript's it’s is curly (a source read: manuscript_copy_test). Each test was red first.

## F-187 · Read the syllabus says it is reading in the background, and where the plan will be
- status: done 2026-11-11
- screen: study
- route: /study
- spec: spec/screens/study.md
- web: src/pages/study/ProgramEditor.jsx
- flutter: lib/pages/study/program_editor.dart; test/kit/program_editor_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Gap. On fn_request_task's 202, study.md:110-112 has the picker close and the client say *Reading the syllabus for “{program}” in the background* / *You'll find it in For your review.* Web announces it (ProgramEditor.jsx:353-356). Flutter's `_suggest` (program_editor.dart:1065-1090) closes the picker and says nothing, so the phone user cannot tell the request was taken. Every other background-task request in Flutter shows its toast (tags/shelf_page.dart:301, :322, :347; tags/suggest_shelves.dart:368-386). Done (lane flutter, 2026-11-11): on the 202 the editor toasts Reading the syllabus for “{program}” in the background. You'll find it in For your review. (web's announce title and line joined, as this client's other background requests are; 'this program' when untitled). With no syllabus attached the picker stays, as web's (!syl || attaching), its choice spent. program_editor_test drives the picker and was red on the missing toast.

## F-188 · Activity: a refused read is the failure alone, not the failure over the feed it could not refresh
- status: done 2026-11-11
- screen: activity
- route: /activity
- spec: spec/screens/activity.md; spec/invariants.md §INV-24
- web: src/pages/ActivityView.jsx
- flutter: lib/pages/activity_page.dart; test/contract/activity_failure_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Bug, low. activity_page.dart:217-225 draws §14.1 *Your activity could not be loaded.* above rows that loaded earlier, and :237-296 keeps drawing them (its comment calls this C1). The folio meanwhile reads *— events* (:143-147), so the masthead says unmeasured while day sections below give exact counts. Web draws the failure block alone (ActivityView.jsx:385-390); activity.md's Refused state is §14.1 *in the column*, and INV-24 puts it in the region the collection would have filled. C1 is recorded nowhere in CLAUDE.md, so it is drift, not a deviation: follow web, or record it there by ruling. Done (lane flutter, 2026-11-11): followed web, not a ruling — a refused feed draws §14.1 alone in the column; no rows, no day sections, so nothing counts under the — events folio. The sheet's facets are web's (they still list what loaded). activity_failure_test's ORDER case became ALONE and was red on the old page (KitTimeline found).

## F-189 · The readings letter: the opt-in card in web's order, with its caption, and a save that says Saved.
- status: done 2026-11-11
- screen: letter-settings
- route: /letters/settings
- spec: spec/screens/letters.md §The readings letter; spec/screens/letters.md §Letter settings
- web: src/pages/letters/ReadingsLetter.jsx; src/pages/LetterSettings.jsx; src/styles/app-scripture.css
- flutter: lib/pages/letters/readings_letter.dart; lib/pages/letter_settings_page.dart; lib/state/scripture_letter_notifier.dart; lib/widgets/kit/kit_d_letters.dart; test/kit/d_letters_test.dart; test/kit/d_letter_settings_support_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: (1) Composition. Web's Off card (ReadingsLetter.jsx:69-99, phone stacking app-scripture.css:67-71, :171) puts Turn on under the paragraph, then the small-caps caption *What it carries* over the three readings, Gospel first, on a sunken panel. Flutter (readings_letter.dart:340-377) puts the button last, has no caption (it survives as the comment at :359) and draws the readings as plain eyebrows on an ordinary card. letters.md:29 and :367-369. (2) Gap. Web's readings save ends on *Saved.* (ReadingsLetter.jsx:252-258, set from LetterSettings.jsx:172, :204); Flutter's foot (letter_settings_page.dart:887-891) has only *Saving…* or its default line, and the notifier keeps no saved state, so a save that landed looks like one that never started. letters.md §Letter settings names no such state; web is the reference. Done (lane flutter, 2026-11-11): (1) the Off card composes two new letters-kit parts, KitOptInPanel (.rl-optin: sunken, r-lg, body and a 300-wide side; stacked under 768) and KitLectList (.rl-optin-side: the What it carries caption, the labels in a bordered --surface list with Gospel the lead in --accent-text, the calendar note). The body is web's: eyebrow, serif 25 title, upright serif 16/26 paragraph, Turn on under it. Web's order is First reading, Responsorial, Gospel — Gospel is the LEAD, not first; this follows web. (2) Letter settings' readings foot says Saved. once a write landed, until the next starts (page state, as web's rlSaved is the component's). Tests red first: d_letters_test (wide and phone), d_letter_settings_support_test. No frame pair was asked or taken.

## F-190 · Onboarding: In your library stands over what it counts, and an upload row says web's words
- status: done 2026-11-11
- screen: onboarding
- route: /onboarding
- spec: spec/screens/onboarding.md
- web: src/pages/onboarding/steps.jsx
- flutter: lib/pages/onboarding/steps.dart; lib/widgets/file_uploader.dart; lib/widgets/kit/kit_rows.dart; test/kit/onboarding_sources_test.dart; test/contract/playlist_link_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Composition. Web (steps.jsx:131-160) draws the label *In your library* with *{indexed} indexed · {total} total* and the rows under it. Flutter (steps.dart:133-151) draws the uploader first and the label after it, so on a first run the count stands below the uploads it counts, and on a replay with an existing library it stands over nothing. A finished upload reads *Queued for processing* with a remove ✕ (file_uploader.dart:280-288, :471-485); web says *added — indexing continues in the background*, with Uploading / Added / Failed. onboarding.md:25 and :49-54. Done (lane flutter, 2026-11-11): In your library heads the rows this run added, inside the uploader's panel look (FileUploader.addedTotal: {indexed} indexed · {total} total), and only when there is a row — a replay with a library and nothing added draws no count. The box and rows are the rows kit's new KitAddedList / KitAddedRow (.ob-added, .ob-urow): badge, name, web's words (uploading…, the refusal or could not be added, added — indexing continues in the background) and the Uploading / Added / Failed pill; the bar is the client's own PUT, web's still 35% until measured. No remove ✕ (web's has none; the panel look is onboarding's alone). onboarding_sources_test was red first; playlist_link_test takes web's words. No frame pair was asked or taken.

## F-191 · Two pages compose their own parts: the connect page's Keep in sync row and type sizes, History's Activity tag
- status: done 2026-11-11
- screen: none
- route: none
- spec: spec/component-kit.md; spec/screens/reader.md §History
- web: src/pages/sources/OAuthReturn.jsx; src/pages/reader/HistoryPanel.jsx
- flutter: lib/pages/sources/oauth_return.dart; lib/pages/reader/history_panel.dart; lib/widgets/kit/kit_controls.dart; lib/widgets/kit/kit_d_reader.dart; lib/widgets/kit/kit_text.dart; test/contract/oauth_return_test.dart; test/contract/source_history_test.dart
- folds: none
- device_test: none
- shots: none
- extra_gates: none
- notes: Composition (ADR-041: a client composes from a named kit, never inline). oauth_return.dart builds its Keep in sync row in the page (:1158-1186) and hard-codes font sizes 13.5 and 14.5 (:1176, :1353), beside 14 EdgeInsets and 3 copyWith; history_panel.dart:319-333 builds the History *Activity* tag pill itself (reader.md:870-877). Move each into the kit role web's CSS names, so no pixel moves. The other high EdgeInsets counts (service_page, manuscript_panel, sync_settings_panel, 16 each) were found to be spacing inside kit roles or one-off paddings handed to a kit part, and are not booked. Done (lane flutter, 2026-11-11): the connect page's Keep in sync row is the controls kit's KitSyncSwitch (.or-switch: the switch, 11 apart from sans 13.5/500 and sans 12/17 at --fg-subtle); an offered item's name is KitText.offerName (.or-name, 14.5/600) — no font size is written in the page now; History's Activity tag is the reader kit's KitOriginTag (.history-origin). The values moved unchanged, so no pixel should move (no frame pair was asked or taken). oauth_return_test and source_history_test assert the kit parts.

## F-192 · Plate I's later cuts (the port TODO and ADR-178 call F-129): web's 5.25.2 to 5.26.2 film in place of 5.25.1's
- status: blocked: HELD until Xavier approves the film (TODO "Flutter F-129: HELD"); its partial port is a stash on the Mac
- screen: landing-actual
- route: /landing
- spec: spec/decisions/ADR-178-the-landing-hero-is-a-film.md
- web: src/pages/landing/Reel.jsx; src/pages/landing/reelScore.js; src/pages/landing/handwriting.js
- flutter: lib/site/landing_reel.dart; lib/site/reel_score.dart
- folds: 5.25.2; 5.25.3; 5.25.4; 5.25.5; 5.25.6; 5.25.7; 5.25.8; 5.25.9; 5.26.2
- device_test: none
- shots: landing-actual
- extra_gates: none
- notes: F-129 was named in the CHANGELOG, ADR-178 and TODO but never had a block here, so the one thing holding the pin was invisible to the queue. The phone DOES draw the film: a signed-out user is sent to /landing (router.dart:80, :141), whose hero is Plate I (landing_page.dart:869). It plays 5.25.1's five-chapter cut, opening on "Everything / you kept." (reel_score.dart:137-143), plus F-128's titles (5e29c03). Web's is 5.26.2's (e0997dc). Missing, one beat each: the film-only hero (reelScore.js:11), Psych 101 (:361), the handwritten note (handwriting.js:4), "you saved it for nothing" (:18), typed titles, "the video … watch later" (:89), the heap (:14), the envelope (:232), the split-flap board (:9). 5.25.2's F-128 part landed. Port after approval, against web's frames; the stash predates 5.25.5.

## F-193 · A refused letter-settings read says web's words and §14.3's sentence, not a constant
- status: done 2026-11-11
- screen: letters
- route: /letters
- spec: spec/component-kit.md §14.3; spec/decisions/ADR-111-a-failure-with-no-envelope-still-owes-a-move.md
- web: src/kit/d/LetterQuick.jsx; src/pages/LettersView.jsx
- flutter: lib/state/settings_notifier.dart; lib/widgets/kit/kit_d_letter.dart; lib/pages/library_page.dart; lib/pages/letters_page.dart; lib/pages/letter_settings_page.dart; test/contract/letter_settings_read_refused_test.dart
- folds: web bd/web 2026-11-11: thirteen read and subscription failures said the SDK's own .message; all take failureDetail now
- device_test: none (a widget test: SettingsNotifier given a permission-denied read, the Letters and Library settings panels say web's line)
- shots: none
- extra_gates: none
- notes: Web's lane W4 found nine web lines printing a Firestore read's raw `.message` after the dash (Missing or insufficient permissions. in prod); the 2026-11-11 web lane fixed them and four more. Their Flutter equivalents are ALREADY §14.3 and owe nothing: documents_notifier.dart:60, tags_notifier.dart:40 and scripture_letter_notifier.dart:45 store describeSdkError(e), so sources_page.dart:345, library_page.dart (kit_d_home.dart:1610), tags_page.dart:210, shelf_page.dart:479, letters_page.dart:600 and letter_settings_page.dart:731 read §14.3 already, and letter_settings_page.dart:189 (the latest letter) does too. The one gap is the newsletter-settings read: settings_notifier.dart:44 swallows the error into the constant 'Could not load newsletter settings.', which kit_d_letter.dart:614 draws as readError in Letters' and Library's settings panels. Web now says `Your letter settings could not be read — ` + §14.3's sentence (LetterQuick.jsx:50); make Flutter say the same, from describeSdkError(e). `_error` is shared with the save path (settings_notifier.dart:175): keep the read's sentence to the read. Done (lane flutter2, 2026-11-11): SettingsNotifier keeps the read's refusal apart as readError = describeSdkError(e) (the save path keeps error); KitLetterQuick draws 'Your letter settings could not be read — ' + it (web LetterQuick.jsx:50), and Letter settings' §14.1 block takes it as its detail (web FailureBlock's failureDetail). letter_settings_read_refused_test (real notifier over a permission-denied read; Home's and Letters' panels) and the page's refused-read case were red on the old constant (5 failures).

## F-194 · A refusal under a control comes into view when it arrives: Add's rejection row, the reader's Update from source line
- status: open
- screen: add
- route: /sources/add
- spec: spec/component-kit.md §14.2
- web: src/pages/sources/intake.jsx; src/pages/reader/UpdateFromSourceBar.jsx; src/shared/Failure.jsx
- flutter: lib/widgets/kit/kit_failure.dart; lib/widgets/file_uploader.dart; lib/state/upload_notifier.dart; lib/pages/reader/update_from_source_bar.dart; test/contract/refusal_into_view_test.dart
- folds: web bd/web 2026-11-11 (lane W4 + the burn-down's web lane): gate:rejection add-link @390 and update-from-source @390
- device_test: a phone: a refused link on Add a source, and a refused Update from Google Drive on a reader scrolled so the bar sits at the foot, each draw their sentence on screen above the tab bar
- shots: none
- extra_gates: none
- notes: On a 390 phone web's refusals drew below the page scroller's edge, under the tab bar: Add's rejection row (its Shelves block, 5.73.0, pushed it below the fold; W4) and the Original panel's Update from {provider} line (the scroller ends where the tab bar starts, so a line under a bar at the foot is clipped; found on the Mac). Web now brings each into view when it arrives, once per arrival and never on a remount (intake.jsx useIntoView; UpdateFromSourceBar.jsx errRef, via FailureInline's lineRef). Flutter has neither: file_uploader.dart:101 `_reject` sets `_rejection` (drawn at :277) with no Scrollable.ensureVisible, AddAnswered's KitRefusedNotices likewise, and update_from_source_bar.dart:69 sets `_error` (drawn through kitRefusalSlot at :86) with none. The Notifications channel-list tandem W4 named is already true (notification_settings_page.dart:123 uses describeSdkError), so it has no item. Built (lane flutter2, 2026-11-11), left OPEN for its device run only: new kit part KitIntoView (kit_failure.dart, with kitRevealNearest = web's scrollIntoView block nearest; KitSendLine now calls it) brings a refusal into view once per ARRIVAL — one Object per refusal, remembered in an Expando as web's WeakSet, so a remount never scrolls back. Hosts: AddAnswered's KitRefusedNotices (UploadNotifier.refusedArrival, new per refuse/_fail, null on clear), the panel look's _rejection, and UpdateFromSourceBar's refusal slot. refusal_into_view_test (Add at 390 with shelves; a remount then a new arrival; onboarding's panel; the reader bar at the scroller's foot) was red on the old hosts (4 of 4) and its remount case red against a per-mount KitIntoView. Owed: the device run above (no simulator this wave).

## F-195 · Wait out fn_suggest_tags' 180 s deadline: its client budget follows the recipe
- status: open
- screen: none
- route: none
- spec: spec/api/tags.md
- web: none
- flutter: lib/services/endpoint_budgets.dart
- folds: backend bd/backend 2026-11-11 (ADR-259): fn_suggest_tags --timeout 60s -> 180s
- device_test: none
- shots: none
- extra_gates: client_timeout_check --target flutter
- notes: ADR-259 (lands with this contract version). fn_suggest_tags answered 504 on a cold start: its 60 s deadline held the instance's start, about a minute. It deploys at 180 s now (the model call stays bounded at 40 s, the meaning check's embedding at 17 s), so a client that waits 60 + 15 s gives up on a request the server may still answer. Set 'fn_suggest_tags': 180 in endpoint_budgets.dart (line 79); client_timeout_check reads DRIFT and TOO-TIGHT until it does. Web sets no client timeout. The endpoint saves nothing, so the interim loses nothing; the reader's Retry is the same request.

## F-196 · A refused tags read is §14, never *No shelves yet.*: the shelf picker, Shelves at add and the reader's Filing row say so
- status: open
- screen: add
- route: /sources/add
- spec: spec/invariants.md §INV-24; spec/component-kit.md §20.1 §20.3 §14.3; spec/decisions/ADR-071-a-subscription-failure-is-a-failure-state.md
- web: src/shared/shelvesRead.js; src/shared/shelfPick.js; src/shared/ShelfPicker.jsx; src/shared/AddShelves.jsx; src/pages/ReaderView.jsx
- flutter: lib/shared/shelf_pick.dart; lib/widgets/kit/kit_shelf_chips.dart; lib/state/tags_notifier.dart; lib/pages/reader_page.dart
- folds: web 97b4b85 2026-11-11 (lane web2): a refused tags read said No shelves yet. in every §20 host; gate:rejection shelves-pick-read
- device_test: none (widget tests: pickState with read failed/loading; KitShelfChipEditor's panel, KitShelfSelect, KitAddShelves and the reader's Filing row under a TagsNotifier holding a permission-denied error say web's line)
- shots: shelves-read-refused
- extra_gates: none
- notes: Web 97b4b85: App's tags subscription handed every §20 host [] when refused and each read it as an answer. Flutter has the same hole: TagsNotifier (tags_notifier.dart:40) stores describeSdkError(e) in its error, but pickState (shelf_pick.dart:122, its callers kit_shelf_chips.dart:777 and :907) knows nothing of it, so the panel says 'No shelves yet.' (shelf_pick.dart:150) or 'No shelf matches …' of a library nobody read; KitAddShelves (kit_shelf_chips.dart:284) keeps its 'Optional. NoteLetter still adds its own as it reads.'; the reader's Filing row shows no chips and its folio and identity say 'Unshelved' (reader_page.dart:132, :447) for a shelved source. Port web's rule: pickState takes read ('answered' | 'loading' | 'failed'); while loading no §20.1 sentence (the create row stays); refused, no sentence and NO create row (a name cannot be checked against shelves nobody read), rows read before the refusal kept, and the panel draws KitFailureInline 'Your shelves could not be read — ' + describeSdkError's sentence where the sentence would be; with no option at all nothing is active and Enter chooses nothing. KitAddShelves: the same line in its sentence's place. Reader: the Filing row carries the line; the folio/identity say '—' for a source whose tag_ids are non-empty while the read is refused (the document says whether it is shelved; the read only names it), 'Unshelved' only for one with none. The extension already does the panel half (ShelfPanel readFailed/loading, 5.73.0).

## F-197 · The iOS share extension's upload says where it came from: origin share_sheet, as the app's own share screen does
- status: done 2026-11-11
- screen: share
- route: /share
- spec: spec/data-model.md §upload_origin; spec/features/picture-dedupe.md; spec/decisions/ADR-202-a-picture-already-in-the-library.md
- web: src/api.js
- flutter: ios/Share/UploadViewModel.swift; tool/share_body_check.sh; tool/share_body_check/main.swift; tool/share_body_check/stubs.swift
- folds: TODO 'Flutter: … the iOS upload sends no origin' (5.73.0 round, booked 2026-11-11 by lane web2)
- device_test: none (no simulator this wave; the body is asserted where the extension builds it, and read back from the created document's upload_origin on the next device run)
- shots: none
- extra_gates: tool/share_body_check.sh
- notes: fn_create_upload_session takes a closed origin (computer · phone · share_sheet; 5.51.0, ADR-202 addendum 1), read back only by a copy's Compare ('Uploaded from …'). The Dart share screen sends UploadOrigin.shareSheet (share_page.dart:198 → api.dart:15), but the iOS Share extension builds its own body at ios/Share/UploadViewModel.swift:53 with filename, mimeType and size only, so every file shared into NoteLetter on iOS is stored upload_origin: null and its Compare says nothing of where it came from. Add "origin": "share_sheet" there (beside ShelfRead.adding's tagIds). The multi-image path (fn_create_multi_image_session) carries no origin by contract; leave it. Done (lane flutter2, 2026-11-11): UploadViewModel.uploadSingleFile sends "origin": "share_sheet" beside filename, mimeType, size (and ShelfRead.adding's tagIds); the image set's body is unchanged. Proved with no simulator by tool/share_body_check.sh: a plain macOS swiftc build of UploadViewModel.swift with the extension's own Foundation-only helpers and a stand-in APIClient (the real one imports FirebaseAuth) that records each body and refuses; red on the old body (origin missing), green after (9 assertions: origin, the closed key set, tagIds only when chosen, the image set carries none). The extension itself was not built (no Xcode build this wave), and upload_origin read back from a created document is the next device run's.

## F-198 · /share's buttons say they are working: Add, Upload photos and Upload file carry the busy ring while the add runs
- status: done 2026-11-11
- screen: share
- route: /share
- spec: spec/component-kit.md §6.1; spec/decisions/ADR-237-a-control-says-it-is-working.md
- web: src/shared/BusyMark.jsx
- flutter: lib/pages/share_page.dart; test/contract/share_page_test.dart
- folds: TODO "Flutter: … /share's button has no ring" (5.73.0 round, booked 2026-11-11 by lane web2)
- device_test: none (a widget test: the share page with its add held open shows one KitBusyMark on the pressed KitButton and the others held)
- shots: none
- extra_gates: none
- notes: §6.1 State — Busy (5.72.0, ADR-237): a control whose own request is in flight is held and draws the ring, one view per client (Flutter KitBusyMark, through KitButton's busy:). share_page.dart holds every action on _busy (idle = !_busy && !_done, :267) but passes no busy: to the KitButton.primary at :283 (Add), :307 (Upload photos) and :319 (Upload file), so a press greys the button with no ring. Pass busy: _busy on the pressed one (the page has one action at a time, so it is that one). Done (lane flutter2, 2026-11-11): busy: _busy on all three KitButton.primary (each card has one action, so it is the pressed one); share_page_test drives each card with its request (the link) or its copy out of the sharing app (photos, file; the share channel held by the test) and asserts one KitBusyMark, inside the pressed button, the button held, and none once it answers — red on the old page; the held-shelf case's 'no ring' became 'the ring is Add's'. Not seen on a device (no simulator this wave).

## F-199 · Listen says whose audio it is: an uploaded recording is 'The recording itself', never narration
- status: open
- screen: reader
- route: /reader/:docId
- spec: spec/screens/reader.md §Listen follow-along
- web: src/pages/reader/ListenPanel.jsx; src/pages/reader/docAudio.js
- flutter: lib/pages/reader/listen_panel.dart; lib/pages/reader/reading_cost.dart
- folds: web eca03fc 2026-11-11 (lane web2): ListenPanel keyed its eyebrow and note to source_audio_url
- device_test: none (a widget test: an audio and a video upload read 'Listen · {d}' and 'The recording itself, at your pace…'; a podcast 'The original episode…'; a narrated source '… narration' / 'Hear the source read aloud…')
- shots: none
- extra_gates: none
- notes: Lane flutter's FOUND 3 (reports/flutter.md): web keyed the eyebrow and note to source_audio_url, which an UPLOADED recording carries as null by design, and F-184 mirrored it — listen_panel.dart:300-302 (_note) and :354 (the eyebrow's ' narration'). Web eca03fc keys both to hasOwnAudio (already imported here, reading_cost.dart): eyebrow 'Listen · {d}' with ' narration' only when the audio is TTS; note: podcast (source_audio_url set) 'The original episode, at your pace. The transcript follows along — tap any line to jump there.'; an uploaded audio/video 'The recording itself, at your pace. The transcript follows along — tap any line to jump there.'; otherwise 'Hear the source read aloud, …'.

## F-200 · Original's 'The full text, before the recipe' is the full text or says where it is, never the recipe's own chunks
- status: open
- screen: reader
- route: /reader/:docId
- spec: spec/invariants.md §INV-20 (20b); spec/screens/reader.md §Sections (Original row)
- web: src/pages/reader/OriginalPanel.jsx
- flutter: lib/pages/reader/original_panel.dart
- folds: web eca03fc 2026-11-11 (lane web2): OriginalPanel's previewHtml fell back to chunkHtml for a distilled document
- device_test: none (a widget test: a recipe with its original_content_url fetch held reads 'Loading the full original text…', refused reads 'The full original text couldn’t be loaded here — open it with the link below.', and neither shows a chunk's text; fetched shows the fetched HTML)
- shots: none
- extra_gates: none
- notes: Lane flutter's FOUND 4: web drew a recipe's chunks — the recipe itself — under 'The full text, before the recipe' while the full text loaded or after its fetch failed, and F-185 mirrored it: original_panel.dart:141-142 (_previewHtml falls back to _chunkHtml), drawn at :299 and :317. Web eca03fc: a distilled document's preview is the fetched HTML or nothing; until it has loaded the section holds one panel-note — 'Loading the full original text…' while out, 'The full original text couldn’t be loaded here — open it with the link below.' when refused (the separate failure note above the section went: one sentence, in the section) — and the raw-text block waits for the text. Non-distilled documents are unchanged.
