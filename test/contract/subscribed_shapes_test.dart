import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/notification_channel.dart';
import 'fixtures.dart';

/// firestore/channel-shapes and firestore/import-job-shapes (INV-02, INV-06)
/// against this client's read mappings. Both collections are SUBSCRIBED, never
/// listed by an endpoint, so no request-side suite can see their shape; until
/// this file nothing held `NotificationChannel.fromJson` or
/// `ImportJob.fromJson` to the captured documents.
///
/// What the two suites pin for a hand-mirrored client:
/// * channels — the CLOSED eight-key shape, and `enabled: false` surviving the
///   `?? true` default (a truthiness test re-enables a channel the user turned
///   off and looks correct);
/// * import jobs — the timestamps as epoch ms, and `provider_modified_at` the
///   provider's own string. This client's model is a typed projection: it
///   reads a subset, so every fixture key is accounted for below as read or
///   deliberately not read, and a key the capture adds is a red test that
///   forces the decision rather than a silent drop.
void main() {
  group('firestore/channel-shapes', () {
    final suite = loadSuite('firestore/channel-shapes');
    test('suite is captured', () => expect(suite, isNotNull));
    final cases = (suite?['cases'] as List? ?? []).cast<Map<String, dynamic>>();
    final docCases =
        cases.where((c) => c['request']['kind'] == 'firestore_doc').toList();

    Map<String, Object?> shape(NotificationChannel c) => {
          'id': c.id,
          'type': c.type,
          'label': c.label,
          'levels': c.levels,
          'destination': c.destination,
          'enabled': c.enabled,
          'created_at': c.createdAt,
          'updated_at': c.updatedAt,
        };

    for (final c in docCases) {
      test('${c['id']} maps to the captured eight keys', () {
        final req = c['request'] as Map<String, dynamic>;
        expect(req['collection'] as String, endsWith('/notification_channels'));
        final input = (decode(req['input']) as Map).cast<String, dynamic>();
        final mapped = shape(NotificationChannel.fromJson(req['id'] as String, input));
        final body = (c['response']['body'] as Map).cast<String, dynamic>();
        expect(mapped.keys.toSet(), body.keys.toSet(), reason: 'the shape is closed');
        expect(mapped, equals(body));
      });
    }

    test('a disabled channel reads back disabled', () {
      final off = docCases.where((c) => c['request']['input']['enabled'] == false);
      expect(off, isNotEmpty, reason: 'the seed must carry a disabled channel');
      for (final c in off) {
        final req = c['request'] as Map<String, dynamic>;
        final input = (decode(req['input']) as Map).cast<String, dynamic>();
        expect(NotificationChannel.fromJson(req['id'] as String, input).enabled, isFalse);
      }
    });

    test('subscription order is created_at desc, and the subscription asks for it', () {
      final q = cases.firstWhere((c) => c['request']['kind'] == 'firestore_query');
      final ms = (q['response']['body']['created_at_ms_in_order'] as List).cast<int>();
      expect(ms, [...ms]..sort((a, b) => b - a));
      expect((q['response']['body']['ids_in_order'] as List).length, docCases.length);
      // The Firestore plumbing is not harness-provable here (CLAUDE.md), so the
      // query is read from the source that builds it.
      final src = File('lib/services/firestore_service.dart').readAsStringSync();
      final body = RegExp(r"subscribeNotificationChannels\(\) \{([\s\S]*?)\n  \}")
          .firstMatch(src)
          ?.group(1);
      expect(body, isNotNull, reason: 'subscribeNotificationChannels not found');
      expect(body, contains(".orderBy('created_at', descending: true)"));
    });
  });

  group('firestore/import-job-shapes', () {
    final suite = loadSuite('firestore/import-job-shapes');
    test('suite is captured', () => expect(suite, isNotNull));
    final cases = (suite?['cases'] as List? ?? []).cast<Map<String, dynamic>>();

    // Every key the model reads, with the default its fromJson applies to an
    // absent or null value.
    final read = <String, (Object? Function(ImportJob), Object?)>{
      'job_id': ((j) => j.id, null),
      'provider': ((j) => j.provider, ''),
      'status': ((j) => j.status, 'pending'),
      'provider_file_id': ((j) => j.providerFileId, ''),
      'provider_file_name': ((j) => j.providerFileName, ''),
      'provider_path': ((j) => j.providerPath, ''),
      'document_id': ((j) => j.documentId, null),
      'error_message': ((j) => j.errorMessage, null),
      'skip_reason': ((j) => j.skipReason, null),
      'mime_type': ((j) => j.mimeType, ''),
      'file_size': ((j) => j.fileSize, 0),
      'created_at': ((j) => j.createdAt, null),
      'started_at': ((j) => j.startedAt, null),
      'completed_at': ((j) => j.completedAt, null),
      'retry_count': ((j) => j.retryCount, 0),
    };
    // Captured keys this client has no consumer for. The web reference spreads
    // `...data`, but no web screen reads any of these either. Not reading
    // `provider_modified_at` is also what keeps it from being tsMs()'d.
    const notRead = {
      'user_id', 'gcs_path', 'provider_parent_folder_id', 'provider_modified_at',
      'last_retry_at', 'exportable',
    };

    for (final c in cases) {
      test('${c['id']} — what the model reads is the captured value', () {
        final req = c['request'] as Map<String, dynamic>;
        expect(req['collection'], 'cloud_import_jobs');
        final input = (decode(req['input']) as Map).cast<String, dynamic>();
        final job = ImportJob.fromJson(req['id'] as String, input);
        final body = (c['response']['body'] as Map).cast<String, dynamic>();

        final unaccounted =
            body.keys.where((k) => !read.containsKey(k) && !notRead.contains(k));
        expect(unaccounted, isEmpty,
            reason: 'a captured key this client neither reads nor declares unread');

        for (final e in read.entries) {
          final (get, dflt) = e.value;
          expect(get(job), body[e.key] ?? dflt, reason: '${c['id']}: ${e.key}');
        }
        // INV-06: every timestamp the model carries is epoch ms or null.
        for (final ts in [job.createdAt, job.startedAt, job.completedAt]) {
          expect(ts == null || ts > 1000000000000, isTrue);
        }
      });
    }

    test('provider_modified_at stays the provider string in every capture', () {
      for (final c in cases) {
        expect(c['response']['body']['provider_modified_at'], isA<String>());
        expect(c['response']['body']['provider_modified_at'],
            c['request']['input']['provider_modified_at']);
      }
    });
  });
}
