# Flutter realignment plan — Milestone 2

Actionable checklist from `/parity flutter` against **contract 1.0.0** (`../NoteLetter-contracts/VERSION`).
This is the execution doc: work tasks **top to bottom**, gate each with `/conformance`. When a task lands, check its box and note the commit. Do NOT reorder — later tasks depend on earlier ones (config unblocks everything; the Firestore layer must exist before the reader; models must match the contract before screens consume them).

> Source of truth is always the contract, not this file. If they disagree, the contract wins — re-run `/parity flutter` and update this doc.

Legend for severity: **FATAL** (nothing works until fixed) · **BROKEN** (calls a nonexistent endpoint) · **BUG** (silent key mismatch) · **INV** (invariant violation) · **GAP** (missing feature) · **STYLE**.

**Status (2026-07-05): Tasks 1–7 landed.** `flutter analyze` and `flutter build web` are clean. Native iOS/Android Firebase registration and a handful of lower-impact gaps are deliberately deferred — see "Deferred / not built" at the bottom.

---

## Task 1 — Config (FATAL, unblocks everything) ✅

- [x] `lib/firebase_options.dart` — web target repointed to `noteletter-7a111` (real values from `NoteLetter-web/.env.local`: apiKey, appId, messagingSenderId, authDomain, storageBucket).
- [x] `lib/services/api_service.dart` — `_baseUrl` → `https://us-central1-noteletter-7a111.cloudfunctions.net`.
- **Deferred by user decision:** native iOS/Android `FirebaseOptions` still throw `UnsupportedError`. Registering those apps means creating new entries in the live Firebase console (`flutterfire configure`), which wasn't authorized this pass. Web/Chrome/macOS-via-web is the dev target until that happens.

## Task 2 — API layer (BROKEN + BUG + INV-01/07) ✅

- [x] `activity_notifier.dart` — `fn_list_activity` removed; now backed by `FirestoreService.subscribeActivity()` (Task 4).
- [x] `settings_notifier.dart` — `GET /fn_settings/newsletter` removed, replaced by `FirestoreService.getNewsletterSettings()`; `PUT` renamed to `fn_newsletter_settings`, and re-reads Firestore after save instead of trusting the partial-echo response.
- [x] `upload_notifier.dart` — `fn_ingest_youtube` removed; all URLs go through `fn_ingest_url {url, type}` with a client-side detection table (`_detectUrlType`, mirrors web `detectUrlType()`) and handle both `docId` and playlist `docIds` (added `UploadFile.docIds`).
- [x] `api_service.dart` `ApiException` — now carries `errorCode`/`requestId` parsed from the standard envelope.

## Task 3 — Models (BUG + INV-06) ✅

- [x] `models/newsletter_settings.dart` — full rewrite: `email`, `lookbackDays` added; `itemsPerNewsletter`/`dateRangeMode`/`dateRangeDays`/`excludeRecentDays`/`topicFilters` deleted. `settings_page.dart` updated to match (lookback slider 1–30 days replaces the items-per-newsletter slider).
- [x] `models/chunk.dart` (new, shared by search + reader) — contract fields only (`chunk_id/document_id/chunk_index/text/html/source_type/source_priority/user_edited/created_at`); `topics`/`page_number`/`timestamp_*` removed. `dashboard_page.dart`'s topic chips switched to `document.themes` (the closest real contract field).
- [x] `models/document.dart` — expanded to the full contract skeleton (`mime_type`, `source_priority`, `display_html`, `view_count`, `last_viewed_at`, `questions`, etc.) since it now backs the live Firestore document list.
- [x] `tsMs()` helper in `models/document.dart` — null-safe `Timestamp → epoch ms`, used by every model built from a Firestore read (INV-06).
- [x] Embedding stripping (INV-05) — done at the `FirestoreService` query boundary (`data.remove('embedding')`) for documents/tags/chunks, and settings reads strip `purposeEmbedding`.

## Task 4 — Firestore layer (INV-02) ✅

New `lib/services/firestore_service.dart`, mirrors web `api.js` query-for-query:

- [x] `subscribeDocuments()` — `onSnapshot`, `user_id ==`, `created_at desc`, limit 200.
- [x] `subscribeActivity()` — the canonical two-subscription merge (`activity_events` + `documents`, `metadata.doc_id` coverage rule) per `spec/screens/activity.md`. Backs `ActivityNotifier` (library/dashboard).
- [x] `subscribeTags()` — realtime, `created_at desc`. **Not yet wired to a Tags UI** (no tags screen exists — see deferred list).
- [x] `getNewsletterSettings()` / `listNewsletters()` / `getLatestNewsletter()` — one-shot reads, INV-09 recency query, never construct `{uid}_{date}` IDs.
- [x] `getReaderDocument()` / `getChunkContext()` — one-shot doc+chunks reads backing the new Reader screen.
- Cloud import status query — **not built** (no cloud-import UI consumes it yet; low priority per the original audit ranking).

## Task 5 — Read tracking (INV-03) ✅

- [x] `FirestoreService.logReadEvent()` — the one sanctioned transaction: `view_count +1` + `last_viewed_at` on the document (and chunk, if `chunkId` given), plus a `read_events` doc (`doc_opened`/`chunk_viewed`). Fire-and-forget via `unawaited()` — never blocks the UI, matches web `logReadEvent()` exactly.
- [x] Wired into `getReaderDocument()` (`doc_opened`) and `getChunkContext()` (`chunk_viewed`).

## Task 6 — Screens (GAP) — partial ✅, see deferred list

- [x] **Reader** (`pages/reader_page.dart`, route `/reader/:docId`) — one-shot doc + chunks in `chunk_index` order, fires `logReadEvent`. Renders chunk `text` (plain, not `html`/`display_html` — no HTML view here yet, see deferred). Wired from the library row's "Open" action (enabled only when `status == complete`).
- [x] **Letters** (`pages/letters_page.dart`, route `/letters`, added to both nav lists) — newsletter history via `NewsletterNotifier` (INV-09 query), renders selected newsletter's `html` via `flutter_html`, "Send now" → `fn_request_newsletter` with cooldown/error surfaced as a toast.
- [x] Document mutations — `fn_delete_document` (with confirm dialog), `fn_retry_document`, `fn_cancel_document` added to `ActivityNotifier` and wired into the library row's context menu (status-conditional: retry only on `error`, cancel only on `queued`/`processing`).
- [ ] **Deferred:** `fn_update_document` (tags/sourcePriority), `fn_update_content`, `fn_get_raw_document_url` — no UI surface for these yet (tag editing, raw-file view).
- [ ] **Deferred:** Tags screen + `fn_create/update/delete/suggest/approve_tags` — `subscribeTags()` exists in `FirestoreService` but nothing consumes it.
- [ ] **Deferred:** Multi-image upload (`fn_create_multi_image_session` + `fn_signal_uploads_complete`), `fn_generate_audio`, Sources screen (`fn_list_cloud_files`/`fn_import_from_cloud`).

These were the lowest-ranked items in the original `/parity` gap table (below Reader/Letters/mutations) — genuinely not built, not stubbed.

## Task 7 — Theming (STYLE) ✅

- [x] `theme/app_colors.dart` rewritten from `design-tokens.md`'s semantic layer (paper/ink/brick/plum/sage raws → `--bg`/`--fg`/`--accent`/etc. semantics), keeping existing field names so call sites didn't need a rename sweep. Primary now brick `#9D352D` (dark `#E97D39`), bg paper `#FAFAF7`, plus a `secondaryAccent` (plum-500) and `positive`/`critical` semantic pair.
- [x] `branding_page.dart` stray hex (`#10B981`/`#8B5CF6`/`#F59E0B`) replaced with `AppColors.positive`/`secondaryAccent`/`primary`; the swatch hex *labels* corrected to match (they'd drifted from the actual constants).
- [x] Fonts: every `GoogleFonts.libreBaskerville` → `GoogleFonts.sourceSerif4` (repo-wide sed, 13 files) for display/headline text.
- **Partial:** body/UI font is still `GoogleFonts.inter`, not Geist — **Geist isn't on Google Fonts**, so the `google_fonts` package can't serve it. Inter is the nearest existing stand-in (same grotesque-sans class); true fidelity needs Geist/Geist Mono bundled as font assets (`pubspec.yaml` `fonts:` + `.ttf` files), which is a follow-up, not something fakeable via `google_fonts`.
- **Not attempted:** full "chrome" (plum sidebar) redesign — `design-tokens.md`'s `--chrome: plum-600` implies the sidebar is plum-tinted in *both* themes, but `Sidebar`/`NavDrawer` text-contrast logic assumes a light-ish surface in light mode. Recoloring the chrome without also reworking that contrast logic would make light-mode nav text unreadable, so it was left as a semantic-surface tone instead. Flag this explicitly if `/design-fidelity` is run on this screen.

---

## Deferred / not built (tracked here so it isn't lost)

1. Native iOS/Android Firebase app registration (Task 1) — needs `flutterfire configure` against the live project, explicitly deferred pending a decision to actually register those apps.
2. Tags UI + tag mutation endpoints — `FirestoreService.subscribeTags()` exists, unconsumed.
3. Document tag/priority editing (`fn_update_document`), content editing (`fn_update_content`), raw-file view (`fn_get_raw_document_url`).
4. Multi-image upload, audio generation, Sources/cloud-file-picker screen.
5. Cloud import job status query (`cloud_import_jobs`).
6. Reader renders chunk `text`, not the richer `html`/`document.display_html` — an HTML-rendering upgrade (same `flutter_html` package already added for Letters) would close this.
7. Geist/Geist Mono as bundled font assets (currently Inter stands in).
8. Full plum "chrome" sidebar fidelity (see Task 7 note above).

Re-run `/parity flutter` for an updated audit once any of the above lands, or if contract VERSION bumps.

---

*Regenerate this file any time with `/parity flutter`. Execution goes through `/feature` per the umbrella law; every client change is "done" only when `/conformance` is green.*
