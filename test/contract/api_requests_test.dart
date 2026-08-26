import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'fixtures.dart';

/// api/* request construction (INV-01 and the per-suite invariants): every
/// Flutter [Api] builder must send the exact {endpoint, method, body} the
/// fixtures captured, attach the Bearer token, and map the standard error
/// envelope onto [ApiException]. Mirrors the web reference
/// `tests/contract/api-request.test.js`: we swap the Dio adapter to capture the
/// outgoing request and return the captured response, invoke the builder with
/// inputs derived from the fixture request, and assert request + resolve/throw.
///
/// The 2xx fixture request is the canonical client request — its body is
/// asserted exactly (token-aware). Error cases exist to pin the envelope;
/// Flutter maps 401 to [UnauthorizedException] by design (its errorCode is
/// `UNAUTHORIZED`, not the envelope's), so errorCode equality is asserted only
/// for non-401 errors — asserting it on 401 would blame the client for a
/// deliberate session-expiry mapping.

// ── Dio capture adapter ─────────────────────────────────────────────────────
class _CaptureAdapter implements HttpClientAdapter {
  RequestOptions? lastOptions;
  dynamic lastBody;
  int status = 200;
  dynamic responseBody;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    lastOptions = options;
    if (requestStream != null) {
      final bytes = <int>[];
      await for (final part in requestStream) {
        bytes.addAll(part);
      }
      final text = utf8.decode(bytes);
      lastBody = text.isEmpty ? null : jsonDecode(text);
    } else {
      lastBody = null;
    }
    final text = responseBody == null ? '{}' : jsonEncode(responseBody);
    return ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ── «uuid#N» request-input decoding ─────────────────────────────────────────
// The client sends a real uuid where a fixture request carries the «uuid#N»
// identity sentinel; decode so the builder emits a uuid that [match] then
// validates against the token in the expected body.
final _uuidTok = RegExp(r'^«uuid#(\d+)»$');
dynamic _decodeUuids(dynamic v) {
  if (v is String) {
    final m = _uuidTok.firstMatch(v);
    if (m != null) {
      final d = m.group(1)![0];
      return '${d * 8}-${d * 4}-4${d * 3}-8${d * 3}-${d * 12}';
    }
    return v;
  }
  if (v is List) return v.map(_decodeUuids).toList();
  if (v is Map) return v.map((k, val) => MapEntry(k, _decodeUuids(val)));
  return v;
}

// ── token-aware deep match (port of contracts/harness match.js) ──────────────
final _reUuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
double _round6(num n) => (n * 1e6).round() / 1e6;

void _fail(String path, Object? expected, Object? actual, [String why = '']) {
  throw TestFailure('mismatch at $path${why.isNotEmpty ? ' ($why)' : ''}: '
      'expected ${jsonEncode(expected)}, got ${jsonEncode(actual)}');
}

void match(dynamic actual, dynamic expected,
    [String path = r'$', Map<String, String>? uuids]) {
  uuids ??= {};
  if (expected is String && expected.startsWith('«')) {
    if (expected.startsWith('«uuid#')) {
      if (actual is! String || !_reUuid.hasMatch(actual)) {
        _fail(path, expected, actual);
      }
      if (uuids.containsKey(expected) && uuids[expected] != actual) {
        _fail(path, '$expected=${uuids[expected]}', actual, 'uuid identity');
      }
      uuids[expected] = actual as String;
    } else {
      // Request bodies only carry uuid tokens; any other token is unexpected.
      throw TestFailure('unexpected token $expected at $path');
    }
    return;
  }
  if (expected is List) {
    if (actual is! List || actual.length != expected.length) {
      _fail(path, expected, actual, 'array length');
    }
    for (var i = 0; i < expected.length; i++) {
      match(actual[i], expected[i], '$path[$i]', uuids);
    }
    return;
  }
  if (expected is Map) {
    if (actual is! Map) _fail(path, expected, actual, 'object');
    final ek = expected.keys.map((e) => e.toString()).toList()..sort();
    final ak = (actual as Map).keys.map((e) => e.toString()).toList()..sort();
    if (ek.join(',') != ak.join(',')) _fail(path, ek, ak, 'key set');
    for (final k in ek) {
      match(actual[k], expected[k], '$path.$k', uuids);
    }
    return;
  }
  if (expected is num && actual is num) {
    if (_round6(actual) != _round6(expected)) _fail(path, expected, actual);
    return;
  }
  if (actual != expected) _fail(path, expected, actual);
}

// ── endpoint → builder invocation, args read from the fixture body ───────────
List<String>? _strs(dynamic v) => (v as List?)?.map((e) => e as String).toList();
List<Map<String, dynamic>> _maps(dynamic v) =>
    (v as List).map((e) => (e as Map).cast<String, dynamic>()).toList();

final Map<String, Future<dynamic> Function(Map<String, dynamic> b)> adapters = {
  'fn_create_upload_session': (b) =>
      Api.instance.createUploadSession(b['filename'], b['mimeType'], b['size']),
  'fn_create_multi_image_session': (b) =>
      Api.instance.createMultiImageSession(_maps(b['files']), b['title']),
  'fn_signal_uploads_complete': (b) =>
      Api.instance.signalUploadsComplete(b['docId']),
  'fn_ingest_url': (b) => Api.instance.ingestUrl(b['url'], b['type']),
  'fn_update_document': (b) => Api.instance
      .updateDocument(b['docId'], Map<String, dynamic>.of(b)..remove('docId')),
  'fn_delete_document': (b) => Api.instance.deleteDocument(b['docId']),
  'fn_request_study_session': (b) =>
      Api.instance.requestStudySession(b['programId']),
  'fn_submit_study_answer': (b) => Api.instance.submitStudyAnswer(
      b['sessionId'], b['qid'], b['grade'],
      answerText: b['answerText']),
  'fn_study_advance_unit': (b) => Api.instance.advanceStudyUnit(b['programId'],
      positions: (b['positions'] as Map?)?.cast<String, dynamic>()),
  'fn_suggest_syllabus_plan': (b) =>
      Api.instance.suggestSyllabusPlan(b['programId'], b['documentId']),
  'fn_scripture_lookup': (b) =>
      Api.instance.scriptureLookup(b['reference'], translation: b['translation']),
  'fn_set_read_state': (b) =>
      Api.instance.setReadState(b['docId'], b['finished'] as bool),
  'fn_update_chunk_tags': (b) =>
      Api.instance.updateChunkTags(b['documentId'], _maps(b['overrides'])),
  'fn_suggest_shelf_split': (b) => Api.instance.suggestShelfSplit(b['tagId']),
  'fn_split_shelf': (b) =>
      Api.instance.splitShelf(b['tagId'], _maps(b['parts'])),
  'fn_cancel_document': (b) => Api.instance.cancelDocument(b['docId']),
  'fn_retry_document': (b) => Api.instance.retryDocument(b['docId']),
  'fn_update_content': (b) =>
      Api.instance.updateContent(b['docId'], chunks: _maps(b['chunks'])),
  'fn_search_notes': (b) => Api.instance.searchNotes(b['query'],
      sourceTypes: _strs(b['sourceTypes']), limit: b['limit'] ?? 10),
  'fn_create_tag': (b) => Api.instance
      .createTag(b['title'], description: b['description'], color: b['color']),
  'fn_update_tag': (b) => Api.instance
      .updateTag(b['tagId'], Map<String, dynamic>.of(b)..remove('tagId')),
  'fn_delete_tag': (b) => Api.instance.deleteTag(b['tagId']),
  'fn_suggest_tags': (b) => Api.instance.suggestTags(b['purposeText']),
  'fn_approve_tags': (b) => Api.instance.approveTags(_maps(b['tags'])),
  'fn_newsletter_settings': (b) => Api.instance.updateNewsletterSettings(b),
  // Closed key set: the builder can only express `summaryPrompt`, which is why
  // the unknown-key case can only be pinned as a server rejection here.
  'fn_summary_settings': (b) =>
      Api.instance.updateSummarySettings(b['summaryPrompt'] as String?),
  'fn_regenerate_summary': (b) =>
      Api.instance.regenerateSummary(b['documentId'] as String),
  'fn_request_newsletter': (b) => Api.instance.requestNewsletter(),
  'fn_connect_cloud_storage': (b) =>
      Api.instance.connectCloudStorage(b['provider']),
  'fn_disconnect_cloud_storage': (b) =>
      Api.instance.disconnectCloudStorage(b['provider']),
  'fn_import_from_cloud': (b) => Api.instance.importFromCloud(b['provider'],
      folderIds: _strs(b['folder_ids']),
      fileIds: _strs(b['file_ids']),
      includeTypes: _strs(b['include_types']),
      excludePatterns: _strs(b['exclude_patterns'])),
  'fn_retry_import_job': (b) => Api.instance.retryImportJob(b['job_id']),
  'fn_request_cloud_sync': (b) => Api.instance.requestCloudSync(b['provider']),
  'fn_sync_settings': (b) => Api.instance.syncSettings(b['provider'],
      autoSyncEnabled: b['auto_sync_enabled'],
      syncFrequency: b['sync_frequency'],
      syncPreferredHour: b['sync_preferred_hour'],
      folderIds: _strs(b['folder_ids']),
      includeTypes: _strs(b['include_types']),
      excludePatterns: _strs(b['exclude_patterns'])),
  'fn_update_from_source': (b) =>
      Api.instance.updateFromSource(b['document_id']),
  'fn_organization_settings': (b) =>
      Api.instance.updateOrganizationSettings(b),
  'fn_enable_organization': (b) =>
      Api.instance.enableOrganization(b['provider']),
  'fn_set_organized_folders': (b) => Api.instance
      .setOrganizedFolders(b['provider'], _strs(b['root_folder_ids'])!),
  'fn_scan_organization': (b) =>
      Api.instance.scanOrganization(b['provider'], folderId: b['folder_id']),
  'fn_resolve_organization_suggestions': (b) => Api.instance
      .resolveOrganizationSuggestions(_strs(b['suggestion_ids'])!, b['action']),
  'fn_analyze_reorganization': (b) =>
      Api.instance.analyzeReorganization(b['document_id']),
  // Support (4.18.0, ADR-054). `platform` is passed through from the fixture —
  // the captures were taken from the web reference, so they carry
  // `platform: "web"`; the live app defaults to `flutter`. Both are members of
  // the endpoint's closed vocabulary.
  //
  // There is no `fn_reply_support_message` adapter: replying is the support
  // console's endpoint and this client has no console (CHANGELOG 4.19.0 —
  // "Flutter · iOS — pending: no console"). Its four fixture cases are skipped
  // by the loop below, which is the same treatment every not-yet-implemented
  // endpoint gets.
  'fn_send_support_message': (b) => Api.instance.sendSupportMessage(
        body: b['body'],
        route: b['route'],
        clientVersion: b['clientVersion'],
        platform: b['platform'] ?? 'flutter',
      ),
  'fn_mark_support_read': (b) => Api.instance.markSupportRead(),
  'fn_execute_reorganization': (b) => Api.instance
      .executeReorganization(b['plan_id'], b['operations'] as List),
};

const _suites = [
  'api/uploads',
  'api/ingest',
  'api/documents',
  'api/update-content',
  'api/search',
  'api/tags',
  'api/newsletter',
  'api/cloud-storage',
  'api/organization',
  'api/notification-channels',
  'api/device-registration',
  // 4.0.0 realignment — the suites this client now implements.
  'api/read-state',
  'api/chunk-tags',
  // The two verticals, built 2026-08-15.
  'api/study-programs',
  'api/study-review',
  'api/study-syllabus',
  'api/study-units',
  'api/scripture-lookup',
  'api/scripture-newsletter',
  // 4.3.0 (ADR-040).
  'api/summary-settings',
  // 4.18.0 (ADR-054) — the support thread.
  'api/support',
];

// Endpoints whose builder needs the request METHOD (and possibly query) — the
// single-arg [adapters] map can't express these, so they dispatch here.
const _methodAware = {
  'fn_notification_channels',
  'fn_register_device',
  'fn_unregister_device',
  'fn_study_programs',
  'fn_apply_syllabus_plan',
  'fn_scripture_newsletter_settings',
};

Future<dynamic> _invokeMethodAware(
    String endpoint, String method, Map<String, dynamic> b) {
  switch (endpoint) {
    case 'fn_notification_channels':
      if (method == 'PUT') {
        final rest = Map<String, dynamic>.of(b)..remove('channelId');
        return Api.instance.updateNotificationChannel(b['channelId'], rest);
      }
      if (method == 'DELETE') {
        return Api.instance.deleteNotificationChannel(b['channelId']);
      }
      return Api.instance.createNotificationChannel(
        type: b['type'],
        levels: _strs(b['levels'])!,
        label: b['label'],
        destination: b['destination'],
        enabled: b['enabled'],
      );
    // `b` is the body merged with the query, so a DELETE's identifier arrives
    // here too. Both builders take fid and token as NAMED optionals because
    // each is optional and at least one is required (ADR-044): the positional
    // `registerDevice(b['token'], …)` this replaces could not express an
    // install that has a fid and no token yet, so `device:register-fid-only`
    // built no request at all rather than the wrong one.
    case 'fn_register_device':
      return Api.instance.registerDevice(
        token: b['token'],
        fid: b['fid'],
        platform: b['platform'] ?? 'web',
      );
    case 'fn_unregister_device':
      return Api.instance.unregisterDevice(token: b['token'], fid: b['fid']);
    case 'fn_study_programs':
      if (method == 'PUT') {
        final rest = Map<String, dynamic>.of(b)..remove('programId');
        return Api.instance.updateStudyProgram(b['programId'], rest);
      }
      if (method == 'DELETE') {
        return Api.instance.deleteStudyProgram(b['programId']);
      }
      return Api.instance.createStudyProgram(b);
    case 'fn_apply_syllabus_plan':
      // DELETE detaches; POST applies. 3.0.0 sends `assessments`, never
      // `exams`, and there is no `unitIndexes` any more.
      if (method == 'DELETE') {
        return Api.instance.detachSyllabusPlan(b['programId']);
      }
      return Api.instance.applySyllabusPlan(
        b['programId'],
        b['documentId'],
        _maps(b['units']),
        _maps(b['assessments']),
      );
    case 'fn_scripture_newsletter_settings':
      if (method == 'GET') {
        return Api.instance.getScriptureNewsletterSettings();
      }
      return Api.instance.updateScriptureNewsletterSettings(b);
  }
  throw StateError('no method-aware dispatch for $endpoint');
}

void main() {
  final capture = _CaptureAdapter();

  setUpAll(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    ApiService.instance.httpClientAdapter = capture;
  });

  for (final suiteId in _suites) {
    final suite = loadSuite(suiteId);
    group(suiteId, () {
      test('captured', () => expect(suite, isNotNull));
      for (final c in (suite?['cases'] as List? ?? [])) {
        final req = (c['request'] as Map).cast<String, dynamic>();
        final endpoint = req['endpoint'] as String?;
        final method = req['method'] as String?;
        final adapter = endpoint == null ? null : adapters[endpoint];
        final methodAware = endpoint != null && _methodAware.contains(endpoint);
        final id = c['id'] as String;
        // Only cases with a builder we can drive from the request body/query.
        if (adapter == null && !methodAware) continue;
        if (method == 'OPTIONS' || method == 'GET') continue;
        if (id.contains('mismatch') || id.contains('missing-url')) continue;

        test(id, () async {
          final resp = (c['response'] as Map).cast<String, dynamic>();
          final status = resp['status'] as int;
          capture
            ..lastOptions = null
            ..lastBody = null
            ..status = status
            ..responseBody = resp['body'];

          // Body may be absent (DELETE); id/token then arrives via the query.
          final b = <String, dynamic>{
            if (req['body'] is Map)
              ...(_decodeUuids(req['body']) as Map).cast<String, dynamic>(),
            if (req['query'] is Map)
              ...(_decodeUuids(req['query']) as Map).cast<String, dynamic>(),
          };
          Object? threw;
          try {
            await (methodAware
                ? _invokeMethodAware(endpoint, method!, b)
                : adapter!(b));
          } catch (e) {
            threw = e;
          }

          void assertShape() {
            expect(capture.lastOptions, isNotNull, reason: 'adapter was called');
            expect(capture.lastOptions!.uri.path.endsWith('/$endpoint'), isTrue,
                reason: '${capture.lastOptions!.uri} ends with /$endpoint');
            expect(capture.lastOptions!.method, method);
            expect(capture.lastOptions!.headers['Authorization'],
                'Bearer test-token');
          }

          if (status < 400) {
            // Success: the request must go out with the canonical shape/body
            // (INV-01 token attached) and the builder must resolve.
            assertShape();
            if (req['body'] != null) {
              match(capture.lastBody, req['body'], '$id.body');
            }
            expect(threw, isNull, reason: threw?.toString());
          } else {
            // Error: the builder must NOT resolve. It may either send a
            // well-formed request the server rejects (→ ApiException carrying
            // the envelope), or reject locally when the fixture omits a
            // required field (an input the client would never construct — these
            // pin server-side validation, not client request construction).
            expect(threw, isNotNull, reason: 'builder rejects on error status');
            if (capture.lastOptions != null) {
              assertShape();
              expect(threw, isA<ApiException>());
              final err = threw as ApiException;
              expect(err.statusCode, status);
              final body = resp['body'];
              if (status != 401 && body is Map && body['error_code'] != null) {
                expect(err.errorCode, body['error_code']);
              }
            }
          }
        });
      }
    });
  }
}
