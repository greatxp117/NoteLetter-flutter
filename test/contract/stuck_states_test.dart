import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/upload_file.dart';
import 'package:flutter_app/pages/reader/source_freshness.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/upload_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// **C9 — stuck and misleading states.**
///
/// Four sites where this client told the reader something that was not so, and
/// nothing could go red for any of them: every one is a branch the happy path
/// never reaches, so a suite that drives the happy path sees nothing.
///
///  1. `file_uploader` matched its finished row with `lastWhere(name)`. Two
///     drops of the same filename are two rows; the name is not an identity,
///     so a failed upload read as complete the moment a later one of the same
///     name succeeded — the toast said "added" for a file that was not.
///  2. `source_freshness` cached a FAILED check as `null` for the life of the
///     process. A cached `null` is indistinguishable from "checked, nothing to
///     say", so one dropped request meant that document could never show its
///     "newer at provider" banner again until the app restarted.
///  3. `listen_panel` wrote "Audio is being generated — check back shortly."
///     into `_error` when a 200 carried no URL: a success sentence in the
///     failure slot, for a state the synchronous backend cannot produce.
///  4. `reorganize_sheet` subscribed with no `onError`, so a broken stream left
///     the sheet reading "Reorganizing…" forever for a plan that may well have
///     finished.
///
/// 1 and 2 are driven for real. 3 and 4 are single sentences inside widgets
/// whose real dependencies (an audio player, a Firestore stream on a plan this
/// suite cannot write) are not mountable here — they are asserted over the
/// source, and the assertion is written so that reading NOTHING fails, because
/// a gate that reads nothing reports PASS on the silence (4.34.7).

/// Answers the `fn_*` transport by path, so one upload can be refused while
/// the next succeeds.
class _RouteAdapter implements HttpClientAdapter {
  _RouteAdapter(this.answer);

  /// path → (status, body). Called once per request, in order.
  final List<(int, Object)> answer;
  int _i = 0;

  /// How many requests this adapter actually answered — the only way to prove
  /// a cache HELD rather than merely looked right on screen.
  int get calls => _i;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final (status, body) = answer[_i < answer.length ? _i : answer.length - 1];
    _i++;
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The GCS direct PUT (INV-08). Always accepts — the failure under test is the
/// session call, and a bare PUT that went to the real network is the reason
/// this seam had to exist at all.
class _OkPutAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString('', 200);

  @override
  void close({bool force = false}) {}
}

Document _cloudDoc() => Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'A cloud file',
      'type': 'document',
      'status': 'complete',
      'source_integration': {'provider': 'dropbox', 'file_id': 'f1'},
    });

/// A fresh MOUNT of the banner — the "reader opens this document" event.
///
/// Pumping the same widget in place would only update the existing element, so
/// `initState` (where the check lives) would never run a second time and the
/// test would be asserting nothing.
Future<void> _pumpFreshness(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SourceFreshness(docId: 'doc-1', doc: _cloudDoc()),
    ),
  ));
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump();
}

String _read(String path) {
  final f = File(path);
  expect(f.existsSync(), isTrue, reason: '$path moved — this gate reads nothing');
  final src = f.readAsStringSync();
  expect(src.length, greaterThan(500), reason: '$path read empty');
  return src;
}

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(ApiService.instance.resetTestSeams);

  test('two drops of one filename are two rows, and each reports its own fate',
      () async {
    // First session call is refused; the second succeeds and its PUT lands.
    ApiService.instance.httpClientAdapter = _RouteAdapter([
      (500, {'error': 'Storage is unavailable right now.'}),
      (200, {'docId': 'doc-b', 'uploadUrl': 'https://storage.test/put'}),
    ]);
    ApiService.instance.rawClientAdapter = _OkPutAdapter();

    final notifier = UploadNotifier();
    final bytes = Uint8List.fromList([1, 2, 3]);
    final idA =
        await notifier.addFile('notes.pdf', 3, bytes, 'application/pdf');
    final idB =
        await notifier.addFile('notes.pdf', 3, bytes, 'application/pdf');

    expect(idA, isNot(idB), reason: 'two rows, two identities');

    UploadFile row(String id) => notifier.files.firstWhere((f) => f.id == id);
    expect(row(idA).status, UploadStatus.error);
    expect(row(idA).errorMessage, 'Storage is unavailable right now.');
    expect(row(idB).status, UploadStatus.completed);

    // The defect, stated as the thing the old lookup would have answered: by
    // name, the failed drop reports the LATER row — "added", for a file that
    // was refused.
    final byName = notifier.files.lastWhere((f) => f.name == 'notes.pdf');
    expect(byName.id, idB);
    expect(byName.status, UploadStatus.completed);
  });

  test('the uploader looks its row up by id, never by name or shape', () {
    final src = _read('lib/widgets/file_uploader.dart');
    expect(RegExp(r'lastWhere\(\s*\(f\)\s*=>\s*f\.name').hasMatch(src), isFalse,
        reason: 'a filename is not a row identity');
    expect(RegExp(r'f\.mimeType\s*==\s*.image/\*').hasMatch(src), isFalse,
        reason: 'an image-set shape is not a row identity either');
    expect(src.contains('f.id == rowId'), isTrue);
  });

  testWidgets('a failed freshness check is not cached as "nothing to say"',
      (tester) async {
    SourceFreshness.resetCacheForTest();

    ApiService.instance.httpClientAdapter =
        _RouteAdapter([(503, {'error': 'Dropbox is unreachable.'})]);
    await _pumpFreshness(tester);
    expect(find.textContaining('newer version'), findsNothing,
        reason: 'a failed check degrades silently — that half was right');

    // Same document, same session, second open. The check must be asked again:
    // caching the failure as `null` made this banner unreachable for the rest
    // of the process.
    ApiService.instance.httpClientAdapter = _RouteAdapter([
      (200, {'provider': 'dropbox', 'newer_at_provider': true}),
    ]);
    await _pumpFreshness(tester);
    expect(find.textContaining('A newer version of this file exists in Dropbox'),
        findsOneWidget);
  });

  testWidgets('a successful check is still asked ONCE per session (INV-02)',
      (tester) async {
    SourceFreshness.resetCacheForTest();
    final adapter = _RouteAdapter([
      (200, {'provider': 'dropbox', 'newer_at_provider': true}),
    ]);
    ApiService.instance.httpClientAdapter = adapter;

    await _pumpFreshness(tester);
    expect(SourceFreshness.debugCacheHas('doc-1'), isTrue);
    await _pumpFreshness(tester);

    // The rule the fix must not have traded away: not caching a FAILURE is not
    // the same as not caching. A success is answered from the cache, so a
    // reader opening the same document twice makes one request, never a poll.
    expect(adapter.calls, 1);
    expect(find.textContaining('A newer version of this file exists in Dropbox'),
        findsOneWidget);
  });

  test('no client offers to generate audio later — the backend is synchronous',
      () {
    // api/audio.md: a 200 always carries `audio_url`. A 200 without one is a
    // failure, and it used to be written into the failure slot as a SUCCESS.
    const fiction = 'Audio is being generated';
    for (final path in const [
      'lib/pages/reader/listen_panel.dart',
      '../NoteLetter-web/src/pages/reader/ListenPanel.jsx',
      '../NoteLetter/NoteLetter/Views/Reader/ListenPanelView.swift',
    ]) {
      final src = _read(path);
      expect(src.contains(fiction), isFalse,
          reason: '$path still promises a queue the backend never opens');
      expect(src.contains('Narration could not be generated'), isTrue,
          reason: '$path must say the 200-without-a-URL is a failure');
    }
  });

  test('the reorganize subscription reports its own failure', () {
    final src = _read('lib/pages/reader/reorganize_sheet.dart');
    final listen = RegExp(r'subscribeReorgPlan\([\s\S]{0,600}?onError:');
    expect(listen.hasMatch(src), isTrue,
        reason: 'without onError the sheet sits on "executing" forever');
    // And once it has failed it stops claiming progress it can no longer see.
    expect(src.contains('if (_error == null) ui.note(msg)'), isTrue);
  });
}
