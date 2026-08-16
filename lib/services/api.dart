import 'api_service.dart';

/// Canonical request-builder layer — the Flutter mirror of the web reference
/// `src/api.js` and iOS `Networking/`. One thin method per contracted endpoint
/// that builds the exact `{endpoint, method, body}` the contract fixtures pin
/// (canonical field names, conditional keys) and delegates to [ApiService].
///
/// These builders NEVER swallow errors — an [ApiException] propagates so the
/// caller (a notifier) can surface copy. State notifiers call through here so
/// the app's live requests are byte-identical to what `test/contract/
/// api_requests_test.dart` verifies against `fixtures/api/*`.
class Api {
  static final Api instance = Api._();
  Api._();

  final ApiService _http = ApiService.instance;

  // ── Uploads (INV-08) ──────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createUploadSession(
          String filename, String mimeType, int size) =>
      _http.post('/fn_create_upload_session',
          data: {'filename': filename, 'mimeType': mimeType, 'size': size});

  /// Multi-image note: one session over N image parts (contract 1.1.0).
  Future<Map<String, dynamic>> createMultiImageSession(
          List<Map<String, dynamic>> files, String title) =>
      _http.post('/fn_create_multi_image_session',
          data: {'files': files, 'title': title});

  Future<Map<String, dynamic>> signalUploadsComplete(String docId) =>
      _http.post('/fn_signal_uploads_complete', data: {'docId': docId});

  // ── Ingest (INV-07) ───────────────────────────────────────────────────────

  /// The single URL-ingest endpoint; `type` is client-detected (INV-07).
  Future<Map<String, dynamic>> ingestUrl(String url, String type) =>
      _http.post('/fn_ingest_url', data: {'url': url, 'type': type});

  // ── Documents (INV-04) ────────────────────────────────────────────────────

  /// Metadata edit (tag assignment, source priority). `updates` carries only
  /// the changed fields (`tagIds`, `sourcePriority`); PATCH, mirroring web.
  Future<Map<String, dynamic>> updateDocument(
          String docId, Map<String, dynamic> updates) =>
      _http.patch('/fn_update_document', data: {'docId': docId, ...updates});

  /// Pin / unpin a source for the next letter (2.31.2, ADR-032, INV-16).
  /// `includeInNextLetter` is the request key; the stored field is
  /// `next_letter_requested_at`, a Timestamp rather than a boolean so overflow
  /// beyond the per-letter cap is CARRIED oldest-first rather than dropped.
  Future<Map<String, dynamic>> setNextLetter(String docId, bool on) =>
      updateDocument(docId, {'includeInNextLetter': on});

  // ── Study programs (2.34.0 ADR-033; reshaped 3.0.0 ADR-038) ─────────────
  Future<Map<String, dynamic>> createStudyProgram(Map<String, dynamic> body) =>
      _http.post('/fn_study_programs', data: body);

  Future<Map<String, dynamic>> updateStudyProgram(
          String programId, Map<String, dynamic> partial) =>
      _http.put('/fn_study_programs', data: {'programId': programId, ...partial});

  /// DELETE by query param, never PATCH.
  Future<Map<String, dynamic>> deleteStudyProgram(String programId) =>
      _http.delete('/fn_study_programs?programId=$programId');

  /// 429 is a COOLDOWN, not an error — render it as copy.
  Future<Map<String, dynamic>> requestStudySession(String programId) =>
      _http.post('/fn_request_study_session', data: {'programId': programId});

  /// `item.due_at` (epoch ms) in the response is the schedule's answer —
  /// RENDER it, never compute it. `alreadyGraded` and `itemRetired` (INV-18)
  /// are informational and must read as recorded, never as errors.
  Future<Map<String, dynamic>> submitStudyAnswer(
          String sessionId, String qid, String grade,
          {String? answerText}) =>
      _http.post('/fn_submit_study_answer', data: {
        'sessionId': sessionId,
        'qid': qid,
        'grade': grade,
        if (answerText != null && answerText.isNotEmpty) 'answerText': answerText,
      });

  /// Start a new unit (3.0.0, ADR-038). **The reader holds the pointer** — this
  /// is always an explicit action, available with or without a syllabus, and
  /// it snapshots the coverage frontier BEFORE the new positions land.
  ///
  /// [positions] is `{documentId: chunkIndex|null}`, asked once per `reading`
  /// source at the moment of advancing; a position on a `notes` source is a
  /// 400. **Deliberately not idempotent — confirm before calling.**
  Future<Map<String, dynamic>> advanceStudyUnit(String programId,
          {Map<String, dynamic>? positions}) =>
      _http.post('/fn_study_advance_unit', data: {
        'programId': programId,
        if (positions != null && positions.isNotEmpty) 'positions': positions,
      });

  /// Stateless parse of an ordinary ingested syllabus document. Saves nothing.
  Future<Map<String, dynamic>> suggestSyllabusPlan(
          String programId, String documentId) =>
      _http.post('/fn_suggest_syllabus_plan',
          data: {'programId': programId, 'documentId': documentId});

  /// 3.0.0: takes **`assessments`** where 2.x took `exams`, and `unitIndexes`
  /// is gone — coverage is positional, so there is no index to be wrong about.
  Future<Map<String, dynamic>> applySyllabusPlan(
          String programId,
          String documentId,
          List<Map<String, dynamic>> units,
          List<Map<String, dynamic>> assessments) =>
      _http.post('/fn_apply_syllabus_plan', data: {
        'programId': programId,
        'documentId': documentId,
        'units': units,
        'assessments': assessments,
      });

  Future<Map<String, dynamic>> detachSyllabusPlan(String programId) =>
      _http.delete('/fn_apply_syllabus_plan?programId=$programId');

  // ── Scripture (2.23.0 / 2.24.0 / 2.26.0) ────────────────────────────────
  /// Resolve a citation to the passages the library holds (`fn_scripture_lookup`).
  /// The CLIENT parses the citation (ADR-027 §2); this asks what is behind it.
  Future<Map<String, dynamic>> scriptureLookup(String reference,
          {String? translation}) =>
      _http.post('/fn_scripture_lookup', data: {
        'reference': reference,
        if (translation != null) 'translation': translation,
      });

  /// `/users/{uid}/settings/scripture_newsletter` — its OWN closed key set,
  /// deliberately separate from the daily letter's (ADR-029). Sending a daily
  /// key here is a 400, and vice versa.
  Future<Map<String, dynamic>> updateScriptureNewsletterSettings(
          Map<String, dynamic> partial) =>
      _http.put('/fn_scripture_newsletter_settings', data: partial);

  Future<Map<String, dynamic>> getScriptureNewsletterSettings() =>
      _http.get('/fn_scripture_newsletter_settings');

  /// Per-chunk shelf overrides (2.35.0, ADR-034).
  ///
  /// A chunk INHERITS its document's shelves; this records the reader's
  /// explicit deviations. Effective shelves are computed at read as
  /// `(document.tag_ids - removed) + added` — storing the computed list would
  /// go stale the moment the document's shelves change.
  ///
  /// Each entry REPLACES that chunk's overrides wholesale; both lists empty
  /// clears it, since pure inheritance is the absence of the field.
  Future<Map<String, dynamic>> updateChunkTags(
          String documentId, List<Map<String, dynamic>> overrides) =>
      _http.post('/fn_update_chunk_tags',
          data: {'documentId': documentId, 'overrides': overrides});

  /// Mark a document finished, or un-mark it (3.1.0, ADR-039).
  ///
  /// An endpoint rather than a client write because **un-finish has to be
  /// possible**: `read_events` is append-only and the rules permit a client
  /// only a `+1`, so nothing client-side could ever undo a mark. Sole writer of
  /// `finished_at` AND of the `doc_finished` event, so the automatic
  /// scroll-to-end finish and the manual control take one path.
  ///
  /// [finished] is a required boolean, never a toggle — a toggle makes the
  /// result depend on state the client may have read seconds ago, and two
  /// surfaces set it.
  Future<Map<String, dynamic>> setReadState(String docId, bool finished) =>
      _http.post('/fn_set_read_state',
          data: {'docId': docId, 'finished': finished});

  Future<Map<String, dynamic>> deleteDocument(String docId) =>
      _http.post('/fn_delete_document', data: {'docId': docId});

  Future<Map<String, dynamic>> cancelDocument(String docId) =>
      _http.post('/fn_cancel_document', data: {'docId': docId});

  Future<Map<String, dynamic>> retryDocument(String docId) =>
      _http.post('/fn_retry_document', data: {'docId': docId});

  /// Signed GET URL for the original uploaded file (Reader → Original panel).
  /// Response: `{ signed_url, mime_type, doc_type, display_html }`.
  Future<Map<String, dynamic>> getRawDocumentUrl(String docId) =>
      _http.post('/fn_get_raw_document_url', data: {'docId': docId});

  /// TTS MP3 for the whole document (Reader → Listen panel). Response:
  /// `{ audio_url, duration_seconds, cached }`. 413 = too long, 422 = no text.
  Future<Map<String, dynamic>> generateAudio(String docId) =>
      _http.post('/fn_generate_audio', data: {'docId': docId});

  // ── Content editing (INV-04 / INV-10 / INV-11) ────────────────────────────

  /// Edit chunk content. Each `chunks` entry carries exactly one of `html`
  /// (1.1.0 shape, sanitized server-side) or `text` (legacy). Only the provided
  /// keys are sent — `docHtml`/`deleteChunkIds` are omitted when null.
  Future<Map<String, dynamic>> updateContent(
    String docId, {
    String? docHtml,
    List<Map<String, dynamic>>? chunks,
    List<String>? deleteChunkIds,
  }) {
    final body = <String, dynamic>{'docId': docId};
    if (docHtml != null) body['docHtml'] = docHtml;
    if (chunks != null) body['chunks'] = chunks;
    if (deleteChunkIds != null) body['deleteChunkIds'] = deleteChunkIds;
    return _http.post('/fn_update_content', data: body);
  }

  // ── Search (INV-01 / INV-05) ──────────────────────────────────────────────

  Future<Map<String, dynamic>> searchNotes(
    String query, {
    List<String>? sourceTypes,
    int limit = 10,
  }) {
    final body = <String, dynamic>{'query': query};
    if (sourceTypes != null) body['sourceTypes'] = sourceTypes;
    body['limit'] = limit;
    return _http.post('/fn_search_notes', data: body);
  }

  // ── Tags (INV-04) ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> createTag(String title,
      {String? description, String? color}) {
    final body = <String, dynamic>{'title': title};
    if (description != null) body['description'] = description;
    if (color != null) body['color'] = color;
    return _http.post('/fn_create_tag', data: body);
  }

  Future<Map<String, dynamic>> updateTag(
          String tagId, Map<String, dynamic> updates) =>
      _http.post('/fn_update_tag', data: {'tagId': tagId, ...updates});

  /// Propose how one shelf could be divided (2.20.0, ADR-025). **Stateless —
  /// saves nothing**, the `fn_suggest_tags` shape, which is what keeps the LLM
  /// call out of the write path.
  ///
  /// 400 below 5 documents (a split has nothing to divide), and `parts: []` is
  /// a 200 meaning the shelf does not divide cleanly — not an error.
  Future<Map<String, dynamic>> suggestShelfSplit(String tagId) =>
      _http.post('/fn_suggest_shelf_split', data: {'tagId': tagId});

  /// Execute a split the user has REVIEWED. The parent shelf is never deleted,
  /// even when every document moves — a parent deleted the moment it empties
  /// would be silently re-created by the auto-tagger the next time a document
  /// fits none of the children.
  Future<Map<String, dynamic>> splitShelf(
          String tagId, List<Map<String, dynamic>> parts) =>
      _http.post('/fn_split_shelf', data: {'tagId': tagId, 'parts': parts});

  Future<Map<String, dynamic>> deleteTag(String tagId) =>
      _http.post('/fn_delete_tag', data: {'tagId': tagId});

  Future<Map<String, dynamic>> suggestTags(String purposeText) =>
      _http.post('/fn_suggest_tags', data: {'purposeText': purposeText});

  Future<Map<String, dynamic>> approveTags(List<Map<String, dynamic>> tags) =>
      _http.post('/fn_approve_tags', data: {'tags': tags});

  // ── Newsletter (INV-09) ───────────────────────────────────────────────────

  /// Partial settings update; the caller supplies canonical keys
  /// (`emailAddress`, `dateRangeDays`, …). Backend rejects unknown keys (2.0.0).
  Future<Map<String, dynamic>> updateNewsletterSettings(
          Map<String, dynamic> partial) =>
      _http.put('/fn_newsletter_settings', data: partial);

  Future<Map<String, dynamic>> requestNewsletter() =>
      _http.post('/fn_request_newsletter', data: const {});

  // ── Notification channels (2.5.0, ADR-014) + push devices (2.6.0, ADR-015) ──

  /// Create a channel. Only provided keys are sent (mirrors web/backend closed
  /// key set); `type`/`levels` required.
  Future<Map<String, dynamic>> createNotificationChannel({
    required String type,
    required List<String> levels,
    String? label,
    String? destination,
    bool? enabled,
  }) {
    final body = <String, dynamic>{'type': type, 'levels': levels};
    if (label != null) body['label'] = label;
    if (destination != null) body['destination'] = destination;
    if (enabled != null) body['enabled'] = enabled;
    return _http.post('/fn_notification_channels', data: body);
  }

  Future<Map<String, dynamic>> updateNotificationChannel(
          String channelId, Map<String, dynamic> partial) =>
      _http.put('/fn_notification_channels',
          data: {'channelId': channelId, ...partial});

  /// DELETE carries channelId as a query param (a DELETE body is not portable).
  Future<Map<String, dynamic>> deleteNotificationChannel(String channelId) =>
      _http.delete('/fn_notification_channels',
          queryParameters: {'channelId': channelId});

  Future<Map<String, dynamic>> registerDevice(String token,
          [String platform = 'web']) =>
      _http.post('/fn_register_device',
          data: {'token': token, 'platform': platform});

  Future<Map<String, dynamic>> unregisterDevice(String token) =>
      _http.delete('/fn_unregister_device', queryParameters: {'token': token});

  // ── Cloud storage (INV-01) ────────────────────────────────────────────────

  Future<Map<String, dynamic>> getCloudIntegrations() =>
      _http.get('/fn_get_cloud_integrations');

  Future<Map<String, dynamic>> connectCloudStorage(String provider) =>
      _http.post('/fn_connect_cloud_storage', data: {'provider': provider});

  Future<Map<String, dynamic>> disconnectCloudStorage(String provider) =>
      _http.post('/fn_disconnect_cloud_storage', data: {'provider': provider});

  Future<Map<String, dynamic>> listCloudFiles(Map<String, dynamic> params) =>
      _http.get('/fn_list_cloud_files', queryParameters: params);

  /// Kick off an import. `folder_ids`/`file_ids` are always present (default
  /// empty, mirroring web); `include_types`/`exclude_patterns` only when given.
  Future<Map<String, dynamic>> importFromCloud(
    String provider, {
    List<String>? folderIds,
    List<String>? fileIds,
    List<String>? includeTypes,
    List<String>? excludePatterns,
  }) {
    final body = <String, dynamic>{
      'provider': provider,
      'folder_ids': folderIds ?? const [],
      'file_ids': fileIds ?? const [],
    };
    if (includeTypes != null) body['include_types'] = includeTypes;
    if (excludePatterns != null) body['exclude_patterns'] = excludePatterns;
    return _http.post('/fn_import_from_cloud', data: body);
  }

  Future<Map<String, dynamic>> retryImportJob(String jobId) =>
      _http.post('/fn_retry_import_job', data: {'job_id': jobId});

  Future<Map<String, dynamic>> requestCloudSync(String provider) =>
      _http.post('/fn_request_cloud_sync', data: {'provider': provider});

  /// Validated partial auto-sync update (1.4.0) — only provided keys are sent.
  Future<Map<String, dynamic>> syncSettings(
    String provider, {
    bool? autoSyncEnabled,
    String? syncFrequency,
    int? syncPreferredHour,
    List<String>? folderIds,
    List<String>? includeTypes,
    List<String>? excludePatterns,
  }) {
    final body = <String, dynamic>{'provider': provider};
    if (autoSyncEnabled != null) body['auto_sync_enabled'] = autoSyncEnabled;
    if (syncFrequency != null) body['sync_frequency'] = syncFrequency;
    if (syncPreferredHour != null) body['sync_preferred_hour'] = syncPreferredHour;
    if (folderIds != null) body['folder_ids'] = folderIds;
    if (includeTypes != null) body['include_types'] = includeTypes;
    if (excludePatterns != null) body['exclude_patterns'] = excludePatterns;
    return _http.post('/fn_sync_settings', data: body);
  }

  Future<Map<String, dynamic>> checkSourceFreshness(String docId) =>
      _http.get('/fn_check_source_freshness', queryParameters: {'docId': docId});

  Future<Map<String, dynamic>> updateFromSource(String documentId) =>
      _http.post('/fn_update_from_source', data: {'document_id': documentId});

  // ── Organization (INV-13) ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> updateOrganizationSettings(
          Map<String, dynamic> partial) =>
      _http.put('/fn_organization_settings', data: partial);

  Future<Map<String, dynamic>> enableOrganization(String provider) =>
      _http.post('/fn_enable_organization', data: {'provider': provider});

  Future<Map<String, dynamic>> setOrganizedFolders(
          String provider, List<String> rootFolderIds) =>
      _http.post('/fn_set_organized_folders',
          data: {'provider': provider, 'root_folder_ids': rootFolderIds});

  Future<Map<String, dynamic>> scanOrganization(String provider,
      {String? folderId}) {
    final body = <String, dynamic>{'provider': provider};
    if (folderId != null) body['folder_id'] = folderId;
    return _http.post('/fn_scan_organization', data: body);
  }

  Future<Map<String, dynamic>> resolveOrganizationSuggestions(
          List<String> suggestionIds, String action) =>
      _http.post('/fn_resolve_organization_suggestions',
          data: {'suggestion_ids': suggestionIds, 'action': action});

  Future<Map<String, dynamic>> updateFolderCharter(
    String folderId, {
    String? charterText,
    bool regenerate = false,
  }) {
    final body = <String, dynamic>{'folder_id': folderId};
    if (regenerate) {
      body['regenerate'] = true;
    } else {
      body['charter_text'] = charterText ?? '';
    }
    return _http.post('/fn_update_folder_charter', data: body);
  }

  Future<Map<String, dynamic>> analyzeReorganization(String documentId) =>
      _http.post('/fn_analyze_reorganization',
          data: {'document_id': documentId});

  Future<Map<String, dynamic>> executeReorganization(
          String planId, List<dynamic> operations) =>
      _http.post('/fn_execute_reorganization',
          data: {'plan_id': planId, 'operations': operations});
}
