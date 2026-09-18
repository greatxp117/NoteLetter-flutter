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

## F-19 · Shelf letter weight — a control the backend cannot store
- status: open
- screen: shelves
- route: /shelves/seed-tag-recipes
- spec: spec/screens/library.md §Shelf color; spec/api/tags.md; spec/component-kit.md §8
- web: src/pages/ShelvesView.jsx
- flutter: lib/pages/tags/shelf_page.dart
- folds: none
- device_test: shelves composes from the kit
- shots: shelf-color-picker
- extra_gates: none
- notes: STOP AND ASK first. The reference's shelf page carries a "Feed today's letter" switch, a Lead/Mixed weight picker and an "In your letter" stat, and NOTHING persists any of them: `/tags` has no such field and no endpoint accepts one, so on the web they reset on every reload while claiming to steer the letter. F-08 deliberately did not port them (only measured figures reach a screen). Either the field is a /contract-change (backend first, then every client), or the web control comes OUT and a flutter.md §Out of scope row records it. Not a Flutter-only decision.

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
- status: open
- screen: sources
- route: /sources
- spec: spec/screens/sources.md §Folder contents; spec/api/cloud-storage.md §`fn_scan_cloud_folder`; spec/features/cloud-folder-scan.md
- web: src/pages/sources/CloudFilePicker.jsx; src/pages/sources/SyncSettingsPanel.jsx; src/api.js
- flutter: lib/services/api.dart; lib/pages/sources/sync_settings_panel.dart; lib/pages/sources/browse_section.dart
- folds: 4.59.0
- device_test: a folder row in the sync-folder chooser expands and reports its contents
- shots: sources
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
- status: open
- screen: none
- route: none
- spec: fixtures/normalization.md (rule 3); fixtures/tokens.json
- web: tests/contract/helpers/match.js; tests/contract/fixture-tokens.test.js
- flutter: test/contract/api_requests_test.dart
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
- status: open
- screen: support · notifications · reader (Summary)
- route: /support · /settings/notifications · /reader/{id}
- spec: spec/component-kit.md §How to read a pattern ("a pattern may not be scoped to its first host") · §2
- web: src/pages/SupportView.jsx; src/pages/NotificationSettings.jsx; src/pages/reader/SummaryPanel.jsx
- flutter: lib/pages/support_page.dart; lib/pages/notification_settings_page.dart; lib/pages/reader/summary_panel.dart
- folds: none
- device_test: none
- shots: support; notifications; reader
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
- status: open
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
- status: open
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
- status: open
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
- status: open
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
