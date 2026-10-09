import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/upload_file.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/shared/playlist.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/file_uploader.dart';

/// A YouTube playlist link (4.114.0, ADR-151 — api/ingest.md §A playlist link).
///
/// `fn_ingest_url` has expanded `youtube_playlist` into one queued document
/// per video since 1.x, and no client's detection table ever produced the
/// type: a pasted playlist was sent as `youtube` and refused. Detection is
/// gated by the shared `url-detection` cases (url_detection_test.dart). This
/// file is the other half — what the link-add surface SAYS about the `docIds`
/// answer: one success, with the measured count, and never yt-dlp's
/// `warnings`. Mirrors web `tests/contract/playlist-link.test.js`.

const _playlist = 'https://www.youtube.com/playlist?list=PLx9Ab_c-12';

Map<String, dynamic> _answerOf([Map<String, dynamic> o = const {}]) => {
      'docIds': ['a', 'b', 'c'],
      'enqueued': 3,
      'failed': <String>[],
      'notStarted': 0,
      'warnings': ['[youtube:tab] some yt-dlp text'],
      ...o,
    };

/// Answers `fn_ingest_url` with [body], after [gate] when given, and records
/// what each request sent.
class _IngestAdapter implements HttpClientAdapter {
  _IngestAdapter(this.body, {this.gate});

  final Object body;
  final Future<void>? gate;
  final sent = <Map<String, dynamic>>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final data = options.data;
    sent.add(data is String
        ? jsonDecode(data) as Map<String, dynamic>
        : Map<String, dynamic>.from(data as Map));
    if (gate != null) await gate;
    return ResponseBody.fromString(jsonEncode(body), 201, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

Future<UploadNotifier> _mountUploader(WidgetTester tester) async {
  final notifier = UploadNotifier();
  await tester.pumpWidget(ChangeNotifierProvider<UploadNotifier>.value(
    value: notifier,
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: SingleChildScrollView(child: FileUploader())),
    ),
  ));
  await tester.pump();
  return notifier;
}

Future<void> _paste(WidgetTester tester, String url) async {
  await tester.enterText(find.byType(TextField), url);
  await tester.pump();
  await tester.tap(find.text('Add link'));
  await tester.pump();
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(ApiService.instance.resetTestSeams);

  group('the sentence for a docIds answer', () {
    test('states the measured count, singular and plural', () {
      expect(playlistAdded(_answerOf()), 'Added 3 videos from this playlist.');
      expect(playlistAdded(_answerOf({'docIds': ['a'], 'enqueued': 1})),
          'Added 1 video from this playlist.');
    });

    test('reads `enqueued`, never `docIds.length`', () {
      // A disagreement the server would never send — which is what makes it
      // the test: the sentence follows the field the contract names.
      expect(playlistAdded(_answerOf({'enqueued': 2})),
          'Added 2 videos from this playlist.');
    });

    test('says what did not start, and what was never added', () {
      expect(
          playlistAdded(_answerOf({
            'docIds': ['a', 'b'],
            'enqueued': 2,
            'failed': ['c'],
            'notStarted': 4,
          })),
          'Added 2 videos from this playlist. One could not be started — '
          'retry it from your library. The 4 after it were not added.');
      expect(
          playlistAdded(_answerOf({
            'docIds': ['a'],
            'enqueued': 1,
            'failed': ['b'],
            'notStarted': 1,
          })),
          'Added 1 video from this playlist. One could not be started — '
          'retry it from your library. The 1 after it was not added.');
    });

    test('groups thousands as the reference’s toLocaleString does', () {
      expect(playlistAdded(_answerOf({'enqueued': 1200, 'notStarted': 1500})),
          'Added 1,200 videos from this playlist. The 1,500 after it were not added.');
    });

    test('is nothing for a single-document answer, and never renders `warnings`',
        () {
      expect(playlistAdded({'docId': 'd1'}), isNull);
      expect(playlistAdded(null), isNull);
      expect(playlistAdded(_answerOf()), isNot(contains('yt-dlp')));
    });

    test('a pending playlist draws the YouTube badge, not NOTE', () {
      expect(pendingBadgeKind('youtube_playlist'), 'youtube');
      expect(pendingBadgeKind('youtube'), 'youtube');
      expect(pendingBadgeKind('article'), 'web');
    });
  });

  group('the link row files a playlist as one', () {
    testWidgets('sends youtube_playlist, labels the row, and says the count',
        (tester) async {
      final release = Completer<void>();
      final adapter = _IngestAdapter(
          _answerOf({
            'docIds': [for (var i = 0; i < 12; i++) 'v$i'],
            'enqueued': 12,
          }),
          gate: release.future);
      ApiService.instance.httpClientAdapter = adapter;
      final notifier = await _mountUploader(tester);

      await _paste(tester, _playlist);
      await tester.pump();
      expect(find.text('YouTube playlist — uploading'), findsOneWidget);
      expect(find.text('YT'), findsOneWidget,
          reason: 'a playlist plates as YouTube, not NOTE');

      release.complete();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('Added 12 videos from this playlist.'), findsOneWidget);
      expect(adapter.sent.single['type'], 'youtube_playlist');
      expect(adapter.sent.single['url'], _playlist);
      expect(notifier.files.single.status, UploadStatus.completed);
      expect(find.textContaining('yt-dlp'), findsNothing);
    });

    testWidgets('a video inside a playlist keeps the row’s own line',
        (tester) async {
      final adapter = _IngestAdapter({'docId': 'd1'});
      ApiService.instance.httpClientAdapter = adapter;
      await _mountUploader(tester);

      await _paste(tester,
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('Queued for processing'), findsOneWidget);
      expect(find.textContaining('from this playlist'), findsNothing);
      expect(adapter.sent.single['type'], 'youtube');
    });
  });
}
