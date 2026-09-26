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
- status: open
- screen: reader
- route: /reader/{id}
- spec: spec/screens/reader.md §Document shelves §Composition; spec/component-kit.md §20 §14.2; spec/api/documents.md §fn_update_document
- web: src/pages/ReaderView.jsx; src/shared/ShelfChipEditor.jsx; src/styles/app-source.css
- flutter: lib/pages/reader_page.dart; lib/pages/library/document_detail_sheet.dart; lib/widgets/kit/kit_shelf_chips.dart (new)
- folds: 4.83.0 (ADR-117)
- device_test: none
- shots: reader
- extra_gates: none
- notes: Contract 4.83.0. Under the reader's header, a mono caps `Shelves` label and a §20 Shelf chip editor over `doc.tag_ids`: × removes, `+ Shelf` opens a menu of the shelves not on it. Each change is one `updateDocument(docId, tagIds: …)` built from the list last READ ± one id; the row is busy meanwhile, chips move only when the call resolves, and a refusal is a dense §14.2 line beside the row with the chips unchanged. `document_detail_sheet.dart` already sends `tagIds` — reuse that call, not its all-at-once save. Build §20 as a kit widget: `chunk_shelves.dart` (the per-passage chips, not yet built here) is its second consumer. Shown when status == complete and at least one shelf exists.

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
- status: open
- screen: various
- route: various
- spec: spec/component-kit.md §How to read a pattern; spec/design-tokens.md §Type
- web: src/styles/app-source.css; src/styles/app-kit.css; src/pages/reader/ListenPanel.jsx; src/pages/reader/SpeedReadPanel.jsx; src/pages/reader/HistoryPanel.jsx; src/pages/reader/ManuscriptPanel.jsx
- flutter: lib/widgets/kit/kit_text.dart; test/kit/no_inline_composition_test.dart; lib/pages/reader/listen_panel.dart; lib/pages/reader/speed_read_panel.dart; lib/pages/reader/history_panel.dart; lib/pages/reader/manuscript_panel.dart; lib/pages/reader/reorganize_sheet.dart; lib/pages/library/document_detail_sheet.dart; lib/pages/chat_page.dart; lib/pages/search/scripture_results.dart; lib/pages/onboarding/wizard.dart
- folds: none — found by F-17's lint
- device_test: none
- shots: none
- extra_gates: none
- notes: F-17's lint left 9 `kit-ok: F-43` sites whose metric no kit role names, and pinned 63 `AppTheme.serif(`/`AppTheme.mono(` calls across 18 page files (the same inline type in another spelling) in a ratchet that only falls. Drive both to zero, then delete the ratchet. The reader panels are not only respelled — they DRIFT from the reference: web `.player-eyebrow` and `.pf-label` are MONO caps 10 at `--fg-subtle` (Flutter: sans 10/600 at 0.8); `.player-times` and `.history-when` are mono 11 subtle (Flutter: sans 12 muted); `.history-label` is sans 14 (Flutter 13); the manuscript panel is built as `.ms-chunk-head`/`.ms-editbadge` where Flutter has its own toolbar and pill. Recompose against the web, then shoot the panels. Also: `ReaderUi`'s colour getters return raw `AppColors` steps, not `Tokens` — check each against its semantic token while there.

## F-44 · The signed-out landing — the pre-redesign page is still what a new user sees
- status: open
- screen: landing-actual
- route: /landing
- spec: spec/decisions/ADR-041-composition-is-contract.md
- web: src/pages/LandingActual.jsx; src/pages/SignIn.jsx
- flutter: lib/pages/landing_page.dart; lib/router.dart
- folds: none — found by F-17's lint; the web's signed-out surfaces (2026-09-10) and landing redesign (cb6ee41) were UI-only, no contract version
- device_test: none
- shots: landing-actual; signin
- extra_gates: none
- notes: Every signed-out user of this client is redirected to `/landing` (router.dart), and it is the pre-redesign page: 'AI-Powered Knowledge Management', '© 2025', raw `AppColors` isDark branches, a Material dialog for sign-in. The web replaced it with LandingActual + a SignIn screen, with phone frames. No queue item named it, because no parity pass reads signed-out routes. Rebuild from the kit against `landing-actual` and `signin`; the 10 `kit-ok: F-44` marks and the file's 5 ratchet entries leave with the old file. (2026-09-25 sizing, nothing built: the reference is LandingActual.jsx 903 lines + landing-actual.css 507 — masthead with a computed dateline, a retyping hero, a fanned letter stack, ticker, ten numbered departments incl. a drawn SVG forgetting curve, a contents rail, colophon, footer, mobile drawer, theme toggle — plus SignIn.jsx 192 + signin.css 208 as a SECOND route `/signin` (router redirect, `analytics.dart` screen-name map and `support_footer_test` `_exempt` all name `/landing` only), plus AuthModal.jsx 342 for sign-up (its letter opt-in replays through usePendingLetterSetup). Two questions for Xavier before building: (1) both web sheets say the signed-out pages deliberately do NOT compose from the app kit ('site furniture, not app furniture'), while this item says 'rebuild from the kit' — which binds? (2) the web offers Continue with Google; this client has no google_sign_in dependency or native config — build it, or record an n/a. Flutter has email/password sign-in and sign-up only; 'Forgot it?' (sendPasswordResetEmail) is cheap. Split suggestion: F-44a /signin + sign-up, F-44b the landing.)

## F-45 · Sources — an import-activity row breaks its title across two lines
- status: open
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
- status: open
- screen: letter-settings
- route: /letters/settings
- spec: spec/screens/letters.md; spec/api/newsletter.md
- web: src/pages/LetterSettings.jsx; src/pages/letters/LetterDocument.jsx
- flutter: lib/pages/letter_settings_page.dart
- folds: none — found by the F-34/F-37 re-shoot pass
- device_test: none
- shots: letter-settings
- extra_gates: none
- notes: Left over after the form was recomposed (F-51). The reference puts the letter itself beside (desktop) or under (phone) the form: `.letter-preview-pane` — today's letter (getNewsletter) rendered through LetterDocument with the first `count` passages, a §14.2 line if it could not be read, and an actions row (`N passages · ~N+1 min read`, Copy, Send now with its sent/failed sentence). This client has no preview and no Send now on this screen. Also `Draw from`: a shelf list with switches whose titles save as `topicFilters` (titles, not ids) in the same PUT; SettingsNotifier.saveLetterSettings already accepts topicFilters. Build both from the kit (§11 Letter sheet for the preview).
  2026-09-25: not reached this sitting (disk, see F-61). Unchanged.

## F-54 · Library — the setup checklist, the search field row, and the spine views
- status: open
- screen: library
- route: /
- spec: spec/screens/library.md §Composition; spec/screens/onboarding.md; spec/component-kit.md §2.1 §5.3
- web: src/pages/LibraryHome.jsx; src/styles/app-kit.css
- flutter: lib/pages/library_page.dart; lib/state/newsletter_notifier.dart; lib/models/newsletter.dart; lib/widgets/kit/kit_cards.dart; test/contract/library_hero_test.dart (new)
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
- status: open
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Composition; spec/component-kit.md §6.6
- web: src/pages/SourcesBrowse.jsx; src/styles/app-sources-browse.css
- flutter: lib/pages/sources/browse_section.dart
- folds: none — found while folding web 9a84288 (F-64)
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: Web's `.browse-controls` holds `Order by` + the `.ltabs` sort AND a `.view-toggle` (32x30 `.vt-btn` icon segments: IcoRows list, IcoGrid cards, IcoShelf shelf; the choice persisted by `pickView`) that switches the volume list between rows, a `.src-cards` two-column card grid, and ShelfView (spines). This client's browse section has the sort only and always draws rows. On a phone the toggle wraps to its own line (9a84288). Read SourcesBrowse.jsx `view`/`pickView`/ShelfView and the card anatomy before building; F-54's Library spine view is the same ShelfView — build the spine once, in the kit, and let both screens compose it.

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
- status: open
- screen: sources
- route: /sources
- spec: spec/screens/sources.md; spec/component-kit.md §6
- web: src/pages/sources/CloudFilePicker.jsx
- flutter: lib/pages/sources/sync_folder_picker.dart
- folds: none — found while building F-61
- device_test: none
- shots: sources
- extra_gates: python3 ../NoteLetter-contracts/harness/screenshot_pair_check.py
- notes: The sync chooser is CloudFilePicker in `folders` mode on web — the same component F-61 rebuilt the import picker to match. sync_folder_picker.dart still draws caps crumbs (`ROOT`), the counter as its own line under them, and each folder as a boxed KitSourceRow with a folder icon. Recompose as F-61's `_PickerPanel` (KitSettingLink crumbs with the counter as a KitProcNote on the same row; checkbox + KitSettingLink name + chevron + FolderContents, unboxed; `Sync N folders` + Cancel). Consider lifting F-61's row and crumb row into one shared picker body so the two cannot drift again. No seed state opens the sync picker; widget tests (sync_folders_test.dart) are the proof.
