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

  Future<Map<String, dynamic>> deleteDocument(String docId) =>
      _http.post('/fn_delete_document', data: {'docId': docId});

  Future<Map<String, dynamic>> cancelDocument(String docId) =>
      _http.post('/fn_cancel_document', data: {'docId': docId});

  Future<Map<String, dynamic>> retryDocument(String docId) =>
      _http.post('/fn_retry_document', data: {'docId': docId});

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
