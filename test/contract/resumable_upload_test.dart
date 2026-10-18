/// F-121 — a single file goes up through the GCS resumable session, chunked,
/// as web's `uploadResumable` sends it (INV-08, ADR-050; web src/api.js).
///
/// The fake below is a GCS session in miniature: it opens on a signed POST
/// with `x-goog-resumable: start`, answers a status query with 308 and the
/// `Range` it has COMMITTED, takes chunks by `Content-Range`, and finalizes on
/// the last byte. Each rule web holds is a test here, so a port that drifts
/// from it goes red rather than uploading corrupt content that then indexes
/// as `complete`.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/upload_file.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/resumable_upload.dart';
import 'package:flutter_app/state/upload_notifier.dart';

const _start = 'https://storage.test/upload?signed=start';
const _session = 'https://storage.test/session/abc';

class _Gcs implements HttpClientAdapter {
  _Gcs(this.total, {this.dropChunk, this.failFirstChunkWith, this.stall = false,
      this.refuseWith, this.commitShort = 0, this.loseFirst = false});

  final int total;

  /// Drop the connection on this chunk index (once).
  final int? dropChunk;

  /// Answer the first chunk with this 5xx (once).
  final int? failFirstChunkWith;

  /// Report no forward movement on every chunk.
  final bool stall;

  /// Answer every chunk with this 4xx.
  final int? refuseWith;

  /// Commit this many bytes fewer than each chunk carried (a partial write).
  final int commitShort;

  /// Keep nothing of the first chunk and say so the GCS way: 308, no Range.
  final bool loseFirst;
  bool _lost = false;

  final List<String> log = [];
  final List<int> received = [];
  int committed = 0;
  int _chunks = 0;
  bool _dropped = false;
  bool _failed = false;

  ResponseBody _reply(int status, {Map<String, List<String>> headers = const {}}) =>
      ResponseBody.fromString('', status, headers: headers);

  Map<String, List<String>> get _range =>
      committed == 0 ? {} : {'range': ['bytes=0-${committed - 1}']};

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    final h = o.headers.map((k, v) => MapEntry(k.toLowerCase(), '$v'));
    if (o.method == 'POST' && o.uri.toString() == _start) {
      log.add('POST start ${h['x-goog-resumable']} ${h['content-type']}');
      return _reply(200, headers: {'location': [_session]});
    }
    if (o.method == 'PUT' && o.uri.toString() == _session) {
      final cr = h['content-range'] ?? '';
      if (cr.startsWith('bytes */')) {
        log.add('PUT status $cr');
        await body?.drain<void>();
        if (committed >= total) return _reply(200);
        return _reply(308, headers: _range);
      }
      final m = RegExp(r'bytes (\d+)-(\d+)/(\d+)').firstMatch(cr)!;
      final from = int.parse(m[1]!), to = int.parse(m[2]!);
      final bytes = <int>[];
      if (body != null) {
        await for (final b in body) {
          bytes.addAll(b);
        }
      }
      final i = _chunks++;
      log.add('PUT chunk $from-$to (${bytes.length})');
      expect(bytes.length, to - from + 1, reason: 'Content-Range matches the body');
      if (dropChunk == i && !_dropped) {
        _dropped = true;
        throw DioException(
            requestOptions: o, type: DioExceptionType.connectionError,
            message: 'connection reset');
      }
      if (failFirstChunkWith != null && !_failed) {
        _failed = true;
        return _reply(failFirstChunkWith!);
      }
      if (refuseWith != null) return _reply(refuseWith!);
      if (loseFirst && !_lost) {
        _lost = true;
        return _reply(308, headers: _range);
      }
      if (stall) return _reply(308, headers: _range);
      expect(from, committed,
          reason: 'a chunk starts where the session says it stopped');
      final keep = (bytes.length - commitShort).clamp(1, bytes.length);
      received.addAll(bytes.take(keep));
      committed += keep;
      if (committed >= total) return _reply(200);
      return _reply(308, headers: _range);
    }
    log.add('UNEXPECTED ${o.method} ${o.uri}');
    return _reply(404);
  }

  @override
  void close({bool force = false}) {}
}

Uint8List _bytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (i) => (i * 31 + 7) & 0xff));

Future<List<double>> _upload(_Gcs gcs, Uint8List data,
    {String docId = 'doc-1'}) async {
  ApiService.instance.rawClientAdapter = gcs;
  ApiService.instance.uploadSleep = (_) async {};
  final progress = <double>[];
  await ApiService.instance.putResumable(
    resumableUrl: _start,
    docId: docId,
    filename: 'talk.m4a',
    mimeType: 'audio/mp4',
    source: ChunkSource.bytes(data),
    onProgress: progress.add,
  );
  return progress;
}

class _Fn implements HttpClientAdapter {
  final List<String> paths = [];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    paths.add(o.path);
    return ResponseBody.fromString(
        jsonEncode({
          'docId': 'doc-9',
          'uploadUrl': 'https://storage.test/bare-put',
          'resumableUrl': _start,
        }),
        201,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(ApiService.instance.resetTestSeams);

  test('the chunk is a 256 KiB multiple, between 256 KiB and 8 MiB, ~50 a file',
      () {
    expect(chunkSizeFor(0), 256 * 1024);
    expect(chunkSizeFor(1000), 256 * 1024);
    expect(chunkSizeFor(100 * 1024 * 1024), 2 * 1024 * 1024);
    expect(chunkSizeFor(2 * 1024 * 1024 * 1024), 8 * 1024 * 1024);
    for (final n in [1, 300000, 13 * 1024 * 1024, 999999999]) {
      expect(chunkSizeFor(n) % (256 * 1024), 0, reason: '$n');
    }
  });

  test('a session is opened by a signed POST, then the bytes go up in '
      'Content-Range chunks, byte for byte', () async {
    final data = _bytes(700 * 1024); // three chunks of 256 KiB
    final gcs = _Gcs(data.length);
    final progress = await _upload(gcs, data);
    expect(gcs.log.first, 'POST start start audio/mp4',
        reason: 'x-goog-resumable: start and the type the URL was signed for');
    expect(gcs.log[1], 'PUT status bytes */${data.length}',
        reason: 'what the session holds is ASKED before anything is sent');
    expect(gcs.log.where((l) => l.startsWith('PUT chunk')).length, 3);
    expect(gcs.received, data, reason: 'the object is exactly the file');
    expect(progress.first, 0);
    expect(progress.last, 1);
    for (var i = 1; i < progress.length; i++) {
      expect(progress[i], greaterThanOrEqualTo(progress[i - 1]),
          reason: 'committed progress never goes backwards');
    }
  });

  test('a dropped chunk resumes from what the session COMMITTED, not from '
      'what was sent', () async {
    final data = _bytes(700 * 1024);
    final gcs = _Gcs(data.length, dropChunk: 1);
    await _upload(gcs, data);
    expect(gcs.received, data);
    final queries = gcs.log.where((l) => l.startsWith('PUT status')).length;
    expect(queries, 2, reason: 'the drop is followed by a status query');
  });

  test('a session that keeps only part of a chunk is resumed from its Range',
      () async {
    final data = _bytes(600 * 1024);
    final gcs = _Gcs(data.length, commitShort: 1000);
    await _upload(gcs, data);
    expect(gcs.received, data,
        reason: 'the next chunk starts at the Range, so nothing is skipped');
  });

  test('a 308 with no Range means the session kept NOTHING — the chunk is '
      'sent again, never skipped', () async {
    final data = _bytes(600 * 1024);
    final gcs = _Gcs(data.length, loseFirst: true);
    await _upload(gcs, data);
    expect(gcs.received, data,
        reason: 'reading a missing Range as "kept" would leave a hole');
    expect(gcs.log.where((l) => l.startsWith('PUT chunk 0-')).length, 2);
  });

  test('a 5xx is retried; a 4xx is never looped on', () async {
    final data = _bytes(300 * 1024);
    final ok = _Gcs(data.length, failFirstChunkWith: 503);
    await _upload(ok, data);
    expect(ok.received, data);

    final refused = _Gcs(data.length, refuseWith: 403);
    await expectLater(_upload(refused, data, docId: 'doc-2'),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'Upload failed: HTTP 403')));
    expect(refused.log.where((l) => l.startsWith('PUT chunk')).length, 1);
  });

  test('a session that stops moving fails, rather than stalling forever',
      () async {
    final data = _bytes(300 * 1024);
    final gcs = _Gcs(data.length, stall: true);
    await expectLater(_upload(gcs, data),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            'Upload failed: the session stopped accepting data.')));
    expect(gcs.log.where((l) => l.startsWith('PUT chunk')).length, 5);
  });

  test('a zero-byte file is finalized by the status query alone', () async {
    final gcs = _Gcs(0);
    final progress = await _upload(gcs, Uint8List(0));
    expect(gcs.log.where((l) => l.startsWith('PUT chunk')), isEmpty);
    expect(progress.last, 1);
  });

  test('the Upload notifier sends a file through the resumable session, '
      'never the bare PUT', () async {
    final fn = _Fn();
    ApiService.instance.httpClientAdapter = fn;
    final data = _bytes(300 * 1024);
    final gcs = _Gcs(data.length);
    ApiService.instance.rawClientAdapter = gcs;
    ApiService.instance.uploadSleep = (_) async {};

    final notifier = UploadNotifier();
    final id = await notifier.addFile(
        'talk.m4a', data.length, data, 'audio/mp4');
    final row = notifier.files.firstWhere((f) => f.id == id);
    expect(fn.paths, ['/fn_create_upload_session']);
    expect(row.status, UploadStatus.completed);
    expect(gcs.received, data);
    expect(gcs.log.any((l) => l.contains('bare-put')), isFalse);
  });
}
