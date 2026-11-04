// F-157 — an import is not one request (5.56.0, ADR-208; screens/sources.md
// §Cloud import, Batches). Mirrors web `tests/contract/cloud-import-batches.test.js`:
// fn_import_from_cloud's 50 is per request, so the client sends more files as
// consecutive requests of ≤50, one at a time, the folders and settings in the
// first; on a refusal after an accepted batch it says how far it got and keeps
// the rest. Tier-1 asserts request CONSTRUCTION, so this drives the real Api
// and the real notifier through a transport that answers like the endpoint.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/cloud_integration.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';

import 'sources_harness.dart';

List<String> _ids(int n, [int from = 0]) => [for (var i = 0; i < n; i++) 'f${from + i}'];

Map<String, dynamic> _pdf(String id) => {
      'id': id,
      'name': '$id.pdf',
      'type': 'file',
      'mime_type': 'application/pdf',
      'size': 1000,
      'modified_at': '',
    };

/// The endpoint, canned. Every import POST body is recorded in order; the
/// i-th is answered by [replies] (0-based) or, by default, a 202 counting what
/// it was sent, as the endpoint counts. [listing] is the picker's root.
class _Endpoint implements HttpClientAdapter {
  _Endpoint({this.listing = const [], this.replies = const {}});

  final List<Map<String, dynamic>> listing;
  final Map<int, FutureOr<(int, Object)> Function(Map body)> replies;
  final posts = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final fn = options.path.split('/').last;
    final (int, Object) reply;
    if (fn == 'fn_list_cloud_files') {
      reply = (200, {'items': listing, 'nextPageToken': null});
    } else if (fn == 'fn_import_from_cloud') {
      final body = (options.data as Map).cast<String, dynamic>();
      final i = posts.length;
      posts.add(body);
      final custom = replies[i];
      reply = custom != null
          ? await custom(body)
          : (
              202,
              {
                'queued_folders':
                    ((body['folder_ids'] as List?) ?? const []).length,
                'queued_files': (body['file_ids'] as List).length,
              }
            );
    } else {
      reply = (404, {'error': 'not stubbed: $fn'});
    }
    return ResponseBody.fromString(jsonEncode(reply.$2), reply.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

/// The real notifier, its integrations read quieted and Google Drive connected.
class _Connected extends QuietCloud {
  static const _drive = CloudIntegration(
      provider: 'google_drive', tokenValid: true, autoSyncEnabled: false);
  @override
  CloudIntegration? integrationFor(String provider) =>
      provider == 'google_drive' ? _drive : null;
}

(int, Object) _refused(int status, String error, String code) =>
    (status, {'error': error, 'error_code': code, 'request_id': 'req-1'});

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() => ApiService.instance.resetTestSeams());

  group('importFromCloud — request construction', () {
    test('sends 50 or fewer files as the one request it always was', () async {
      for (final n in [1, 50]) {
        final e = _Endpoint();
        ApiService.instance.httpClientAdapter = e;
        await Api.instance.importFromCloud('google_drive', fileIds: _ids(n));
        expect(e.posts, [
          {'provider': 'google_drive', 'folder_ids': <String>[], 'file_ids': _ids(n)}
        ]);
      }
    });

    test('sends 51 as two: the folders, their names and the settings only in '
        'the first', () async {
      final e = _Endpoint();
      ApiService.instance.httpClientAdapter = e;
      final res = await Api.instance.importFromCloud(
        'google_drive',
        folderIds: ['d1', 'd2'],
        fileIds: _ids(51),
        folderNames: {'d1': 'Finance'},
        includeTypes: ['pdf'],
        excludePatterns: ['*.tmp'],
      );
      expect(e.posts, [
        {
          'provider': 'google_drive',
          'folder_ids': ['d1', 'd2'],
          'file_ids': _ids(50),
          'include_types': ['pdf'],
          'exclude_patterns': ['*.tmp'],
          'folder_names': {'d1': 'Finance'},
        },
        {'provider': 'google_drive', 'file_ids': ['f50']},
      ]);
      // ADR-103 §5: the figures are the 202s', summed.
      expect(res, {'queued_folders': 2, 'queued_files': 51});
    });

    test('sends 130 as 50 · 50 · 30 in the order given, reporting what each '
        '202 accepted', () async {
      final e = _Endpoint();
      ApiService.instance.httpClientAdapter = e;
      final seen = <(int, int)>[];
      final res = await Api.instance.importFromCloud('notion',
          fileIds: _ids(130), onProgress: (s, t) => seen.add((s, t)));
      expect([for (final b in e.posts) b['file_ids']],
          [_ids(50), _ids(50, 50), _ids(30, 100)]);
      expect(seen, [(50, 130), (100, 130), (130, 130)]);
      expect(res, {'queued_folders': 0, 'queued_files': 130});
    });

    test('sums what the server counted, not what was sent', () async {
      ApiService.instance.httpClientAdapter = _Endpoint(replies: {
        0: (_) => (202, {'queued_folders': 0, 'queued_files': 49}),
        1: (_) => (202, {'queued_folders': 0, 'queued_files': 10}),
      });
      expect(await Api.instance.importFromCloud('dropbox', fileIds: _ids(60)),
          {'queued_folders': 0, 'queued_files': 59});
    });

    test('carries tag_ids on every batch, because it rides every job',
        () async {
      final e = _Endpoint();
      ApiService.instance.httpClientAdapter = e;
      await Api.instance
          .importFromCloud('google_drive', fileIds: _ids(51), tagIds: ['t1']);
      expect([for (final b in e.posts) b['tag_ids']], [
        ['t1'],
        ['t1']
      ]);
    });

    test('sends one request at a time', () async {
      final release = Completer<void>();
      final e = _Endpoint(replies: {
        0: (_) async {
          await release.future;
          return (202, {'queued_folders': 0, 'queued_files': 50});
        },
      });
      ApiService.instance.httpClientAdapter = e;
      final run = Api.instance.importFromCloud('google_drive', fileIds: _ids(80));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(e.posts.length, 1, reason: 'the second waits for the first 202');
      release.complete();
      await run;
      expect(e.posts.length, 2);
    });

    test('stops at a refused batch and says how far it got', () async {
      final e = _Endpoint(replies: {
        1: (_) => _refused(
            403, 'Your free plan imports 60 documents a month.', 'PLAN_LIMIT'),
      });
      ApiService.instance.httpClientAdapter = e;
      Object? err;
      try {
        await Api.instance
            .importFromCloud('google_drive', folderIds: ['d1'], fileIds: _ids(130));
      } catch (x) {
        err = x;
      }
      expect(e.posts.length, 2, reason: 'the third was never sent');
      expect(err, isA<ImportPartialException>());
      final p = err as ImportPartialException;
      expect(p.message, 'Your free plan imports 60 documents a month.');
      expect(p.errorCode, 'PLAN_LIMIT');
      expect(p.statusCode, 403);
      expect(p.partial.queuedFolders, 1);
      expect(p.partial.queuedFiles, 50);
      expect(p.partial.sent, _ids(50));
      expect(p.partial.unsent, _ids(80, 50));
    });

    test('a refused first request is the plain refusal — nothing queued, no '
        'partial', () async {
      final e = _Endpoint(replies: {
        0: (_) => _refused(409,
            'Reconnect google_drive first — its sign-in has expired.', 'REQUEST_ERROR'),
      });
      ApiService.instance.httpClientAdapter = e;
      Object? err;
      try {
        await Api.instance.importFromCloud('google_drive', fileIds: _ids(130));
      } catch (x) {
        err = x;
      }
      expect(e.posts.length, 1);
      expect(err, isA<ApiException>());
      expect(err, isNot(isA<ImportPartialException>()));
    });
  });

  group('the jobs window', () {
    test('is 50, widened to cover a kickoff: max(50, queued_files + 50), at '
        'most 500', () {
      expect(importJobsWindow(null), 50);
      expect(importJobsWindow(0), 50);
      expect(importJobsWindow(30), 80);
      expect(importJobsWindow(130), 180);
      expect(importJobsWindow(1000), 500);
    });
  });

  group('the import picker (notifier)', () {
    test('files are uncapped; a refused second batch keeps exactly the unsent '
        'ticked, says so, and the rest joins one kickoff', () async {
      final e = _Endpoint(
        listing: [for (final id in _ids(60)) _pdf(id)],
        replies: {
          1: (_) => _refused(500, 'Could not start the import. Try again.', 'INTERNAL'),
        },
      );
      ApiService.instance.httpClientAdapter = e;
      final cloud = QuietCloud();
      await cloud.openPicker('google_drive');
      for (final id in _ids(60)) {
        expect(cloud.toggleFile(id), isNull, reason: 'no file cap (5.56.0)');
      }
      expect(cloud.selectedFiles.length, 60);

      final (msg, isErr) = await cloud.importSelection();
      expect(isErr, isTrue);
      expect(msg,
          'Queued 50 of 60 files. The other 10 were not sent — Could not start '
          'the import. Try again.');
      expect(cloud.importError, msg);
      expect(cloud.selectedFiles.toList(), _ids(10, 50));
      expect(cloud.kickoff!.partial, isTrue);
      expect(cloud.kickoff!.queuedFiles, 50);
      final startedAt = cloud.kickoff!.at;
      expect(cloud.jobsWindow, 100);

      final (msg2, isErr2) = await cloud.importSelection();
      expect(isErr2, isFalse);
      expect(e.posts.last,
          {'provider': 'google_drive', 'folder_ids': <String>[], 'file_ids': _ids(10, 50)});
      // One import: the rest joined the kickoff the refusal left.
      expect(cloud.kickoff!.at, startedAt);
      expect(cloud.kickoff!.queuedFiles, 60);
      expect(cloud.kickoff!.partial, isFalse);
      expect(cloud.jobsWindow, 110);
      expect(msg2, 'Queued 0 folder(s) and 60 file(s).');
      cloud.dispose();
    });

    test('the folder cap stands, with its note', () async {
      ApiService.instance.httpClientAdapter = _Endpoint(listing: [
        for (var i = 0; i < 21; i++)
          {'id': 'd$i', 'name': 'D$i', 'type': 'folder', 'mime_type': '', 'size': 0}
      ]);
      final cloud = QuietCloud();
      await cloud.openPicker('google_drive');
      for (var i = 0; i < 20; i++) {
        expect(cloud.toggleFolder('d$i'), isNull);
      }
      expect(cloud.toggleFolder('d20'),
          '20-folder limit reached — import these first, then pick more.');
      cloud.dispose();
    });
  });

  group('the import picker (screen)', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> tap(WidgetTester tester, Finder f) async {
      await tester.ensureVisible(f);
      await tester.pump();
      await tester.tap(f);
      await settle(tester);
    }

    testWidgets('counts files without a cap, says the measured count while the '
        'batches go, and keeps the unsent ticked on a refusal', (tester) async {
      tester.view.physicalSize = const Size(1200, 9000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final release = Completer<void>();
      final e = _Endpoint(
        listing: [for (final id in _ids(60)) _pdf(id)],
        replies: {
          1: (_) async {
            await release.future;
            return _refused(403, 'Refused for the plan.', 'PLAN_LIMIT');
          },
        },
      );
      ApiService.instance.httpClientAdapter = e;
      await pumpSources(tester, SourcesStubService(),
          cloud: _Connected());
      await tap(tester, find.text('Browse files…'));
      for (final id in _ids(60)) {
        await tester.tap(find.text('$id.pdf'));
      }
      await settle(tester);
      expect(find.text('0/20 folders · 60 files'), findsOneWidget);
      expect(find.textContaining('limit reached'), findsNothing);
      await tap(tester, find.text('Import 60 items'));
      expect(find.text('Queuing… 50 of 60 files'), findsOneWidget);
      release.complete();
      await settle(tester);
      expect(
          find.text('Queued 50 of 60 files. The other 10 were not sent — '
              'Refused for the plan.'),
          findsOneWidget);
      expect(find.text('0/20 folders · 10 files'), findsOneWidget);
      expect(find.text('Import 10 items'), findsOneWidget);
      await tester.pump(const Duration(seconds: 61));
    });
  });
}
