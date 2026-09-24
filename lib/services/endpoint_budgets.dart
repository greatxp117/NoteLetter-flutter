/// **Each endpoint's DEPLOYED deadline, in seconds** (C5).
///
/// `ApiService` applied a flat 30s `receiveTimeout` to every `fn_*`, and every
/// one of the 60 endpoints this client calls is deployed with a deadline
/// LONGER than that — 47 at 60s and 13 above it, up to 300s. So the client
/// gave up first on every slow request and reported a failure the backend
/// never had: a 35s Ask rendered "Request timed out" and then the answer
/// landed underneath it through the thread subscription, beside a Retry that
/// asked the same question again; a shelf split completed server-side while
/// the sheet invited a second one. The web reference sets no timeout at all.
///
/// These are the values in each `fn_*`'s own deploy recipe in `main.py`, which
/// is what `deploy_check.py` already compares to the live revision — so this
/// is a mirror of a fact that is checked at its source, not a second opinion
/// about it. `client_timeout_check.py` compares the two tables both ways,
/// because a hand-copied table of 60 numbers is a table that drifts (the
/// lesson of every vocabulary gate in this repo).
///
/// A timeout the client sets must be ABOVE the deadline it is waiting on, not
/// below: the server's own deadline is what produces a real answer, and a
/// client that gives up first converts an answer into a fabricated failure.
/// That is INV-26/ADR-102 read from the other end — there the rule is that an
/// upstream call must be bounded BELOW the deadline hosting it.
const Map<String, int> kEndpointDeadlineSeconds = {
  'fn_analyze_reorganization': 300,
  'fn_apply_syllabus_plan': 120,
  'fn_approve_tags': 120,
  'fn_ask_threads': 60,
  'fn_ask_turn': 60,
  'fn_cancel_document': 60,
  'fn_check_source_freshness': 60,
  'fn_connect_cloud_storage': 60,
  'fn_create_multi_image_session': 60,
  'fn_create_tag': 60,
  'fn_create_upload_session': 60,
  'fn_delete_document': 60,
  'fn_delete_tag': 120,
  'fn_disconnect_cloud_storage': 60,
  'fn_enable_organization': 60,
  'fn_execute_reorganization': 300,
  'fn_generate_audio': 120,
  'fn_get_cloud_integrations': 60,
  'fn_get_raw_document_url': 60,
  'fn_import_from_cloud': 60,
  'fn_ingest_url': 60,
  'fn_list_cloud_files': 60,
  'fn_mark_support_read': 60,
  'fn_newsletter_settings': 60,
  'fn_notification_channels': 60,
  'fn_organization_settings': 60,
  'fn_regenerate_summary': 120,
  'fn_register_device': 60,
  'fn_request_cloud_sync': 60,
  'fn_request_newsletter': 60,
  'fn_request_study_session': 60,
  'fn_resolve_organization_suggestions': 60,
  'fn_retry_document': 60,
  'fn_retry_import_job': 60,
  'fn_review_import_jobs': 60,
  'fn_plan_status': 60,
  'fn_scan_organization': 60,
  'fn_scripture_lookup': 60,
  'fn_scripture_newsletter_settings': 60,
  'fn_search_notes': 60,
  'fn_send_support_message': 60,
  'fn_set_organized_folders': 60,
  'fn_set_read_state': 60,
  'fn_signal_uploads_complete': 60,
  'fn_split_shelf': 300,
  'fn_study_advance_unit': 60,
  'fn_study_programs': 60,
  'fn_submit_study_answer': 60,
  'fn_suggest_shelf_split': 120,
  'fn_suggest_shelf_backfill': 120,
  'fn_apply_shelf_backfill': 60,
  'fn_suggest_syllabus_plan': 120,
  'fn_suggest_tags': 60,
  'fn_summary_settings': 60,
  'fn_sync_settings': 60,
  'fn_synthesize_search': 300,
  'fn_unregister_device': 60,
  'fn_update_chunk_tags': 60,
  'fn_update_content': 60,
  'fn_update_document': 60,
  'fn_update_folder_charter': 120,
  'fn_update_from_source': 300,
  'fn_update_tag': 60,
};

/// What the client waits, on top of the server's own deadline: the request has
/// to cross the network twice and may wake a cold instance, and a margin of
/// zero would race the very deadline it is meant to outlast.
const Duration kTimeoutMargin = Duration(seconds: 15);

/// The fallback for a path with no entry. 60s is the fleet norm, so an
/// endpoint added without being listed here still gets the common deadline
/// rather than the old 30s — and `client_timeout_check.py` fails on the
/// omission, so the default is a floor rather than a way of not deciding.
const Duration kDefaultTimeout = Duration(seconds: 60 + 15);

/// The budget for one request path (`/fn_foo`, with or without a query).
Duration clientTimeoutFor(String path) {
  final name = path.split('?').first.split('/').where((s) => s.isNotEmpty);
  if (name.isEmpty) return kDefaultTimeout;
  final seconds = kEndpointDeadlineSeconds[name.first];
  if (seconds == null) return kDefaultTimeout;
  return Duration(seconds: seconds) + kTimeoutMargin;
}
