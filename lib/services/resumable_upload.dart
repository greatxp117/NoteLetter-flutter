import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chunk_source_stub.dart'
    if (dart.library.io) 'chunk_source_io.dart' as platform;

/// The bytes of one upload, read a slice at a time.
///
/// A file is never read whole into memory to be uploaded (F-121): a long
/// recording could run the app out of memory before its first byte left, and
/// the single bare PUT that carried it had no way back from a dropped
/// connection. [ChunkSource.file] reads the slice it is asked for from disk;
/// [ChunkSource.bytes] is for bytes already in hand (a web pick, a test).
abstract class ChunkSource {
  int get length;
  Future<Uint8List> read(int start, int end);

  factory ChunkSource.bytes(Uint8List bytes) = _BytesSource;

  /// A file on disk. Unavailable on the web, where a pick carries bytes.
  factory ChunkSource.file(String path, int length) =>
      platform.fileChunkSource(path, length);
}

class _BytesSource implements ChunkSource {
  _BytesSource(this._bytes);
  final Uint8List _bytes;
  @override
  int get length => _bytes.length;
  @override
  Future<Uint8List> read(int start, int end) async =>
      Uint8List.sublistView(_bytes, start, end);
}

/// A resumable upload that could not finish. Its sentence is said as written.
class ResumableUploadException implements Exception {
  ResumableUploadException(this.message, {this.statusCode = 0});
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

// ── Resumable uploads (4.14.0, ADR-050; INV-08) — web `uploadResumable` ──────
//
// The whole of web's rule, ported, not a new one:
// - Every single-file upload goes through a GCS resumable session, whatever its
//   size: a path that only runs for rare large files is a path nobody
//   exercises.
// - There is NO fallback to the bare PUT. A fallback would make a broken session
//   invisible, small uploads working and large ones failing irreproducibly.
// - What the session has COMMITTED is asked, never inferred from what was sent.
//   Resuming from a wrong offset finalizes an object with corrupt content,
//   which then chunks, embeds and stores `complete` with nothing failing.
// - Progress is built only from committed bytes, so it never runs ahead of the
//   upload and never shows 100% on one still going.
const int _chunkMultiple = 256 * 1024; // GCS requires this granularity
const int _chunkMin = _chunkMultiple;
const int _chunkMax = 8 * 1024 * 1024;
const int _chunkTargetCount = 50; // ~50 committed progress updates
const int _maxAttempts = 5;
const Duration _sessionTtl = Duration(days: 6); // GCS keeps a session ~7 days

int chunkSizeFor(int total) {
  final target =
      ((total / _chunkTargetCount / _chunkMultiple).ceil()) * _chunkMultiple;
  if (target <= 0) return _chunkMin;
  return target.clamp(_chunkMin, _chunkMax);
}

String _sessionKey(String docId) => 'nl.upload.session.$docId';

/// Uploads [source] through the session [resumableUrl] opens.
///
/// [docId] keys the session URI, so an upload interrupted by the app going
/// away resumes where the session says it stopped — for the same file only:
/// a stored URI is usable only for the exact bytes it was opened for.
Future<void> uploadResumable({
  required Dio dio,
  required String resumableUrl,
  required String docId,
  required String filename,
  required String mimeType,
  required ChunkSource source,
  void Function(double fraction)? onProgress,
  Future<void> Function(Duration)? sleep,
}) async {
  if (resumableUrl.isEmpty) {
    throw ResumableUploadException(
        'Upload could not start: the server returned no resumable URL.');
  }
  final wait = sleep ?? Future<void>.delayed;
  final total = source.length;
  void report(int bytes) => onProgress?.call(total == 0 ? 1 : bytes / total);

  var uri = await _loadSession(docId, filename, total);
  if (uri == null) {
    uri = await _initiate(dio, resumableUrl, mimeType);
    await _saveSession(docId, filename, total, uri);
  }

  // A zero-byte file has no chunk to send; the status query finalizes it.
  var offset = await _committedOffset(dio, uri, total);
  report(offset);
  if (total == 0 || offset >= total) {
    await _clearSession(docId);
    return;
  }

  final chunk = chunkSizeFor(total);
  // One retry budget for the whole upload, reset whenever real progress is
  // committed. Per chunk, a connection that keeps failing would retry forever.
  var attempt = 0;

  while (offset < total) {
    final end = offset + chunk < total ? offset + chunk : total;
    final Response<dynamic> res;
    try {
      final body = await source.read(offset, end);
      res = await dio.put<dynamic>(
        uri,
        data: Stream<List<int>>.value(body),
        options: Options(
          headers: {
            Headers.contentLengthHeader: body.length,
            'Content-Range': 'bytes $offset-${end - 1}/$total',
          },
          validateStatus: (_) => true,
          followRedirects: false,
        ),
      );
    } on DioException catch (e) {
      // A dropped connection is the case this function exists for.
      if (++attempt >= _maxAttempts) {
        throw ResumableUploadException(
            'Upload failed: ${e.message ?? 'the connection dropped'}');
      }
      await wait(Duration(milliseconds: 500 * (1 << (attempt - 1))));
      offset = await _committedOffset(dio, uri, total);
      report(offset);
      continue;
    }

    final status = res.statusCode ?? 0;
    if (status == 200 || status == 201) {
      offset = total;
      break;
    }
    if (status == 308) {
      // The session's Range over our own arithmetic: it is the only authority
      // on what it kept. A 308 with NO Range means it kept nothing (GCS:
      // "no bytes have been persisted") — never "it kept this chunk", which
      // would skip the chunk and finalize an object with a hole in it. (Web's
      // loop reads a missing Range as `end`; reported, not copied.)
      final next = _rangeEnd(res.headers.value('range')) ?? 0;
      // A session that reports no forward movement would resend one chunk
      // forever and look like a stall.
      if (next <= offset && ++attempt >= _maxAttempts) {
        throw ResumableUploadException(
            'Upload failed: the session stopped accepting data.');
      }
      if (next > offset) attempt = 0;
      offset = next;
      report(offset);
      continue;
    }
    if (status >= 500) {
      if (++attempt >= _maxAttempts) {
        throw ResumableUploadException('Upload failed: HTTP $status',
            statusCode: status);
      }
      await wait(Duration(milliseconds: 500 * (1 << (attempt - 1))));
      continue;
    }
    // 4xx: the session is gone or the range was refused. Never loop on it.
    await _clearSession(docId);
    throw ResumableUploadException('Upload failed: HTTP $status',
        statusCode: status);
  }

  report(total);
  await _clearSession(docId);
}

/// Opens a session and returns its URI, from the Location header.
Future<String> _initiate(Dio dio, String resumableUrl, String mimeType) async {
  final Response<dynamic> res;
  try {
    res = await dio.post<dynamic>(
      resumableUrl,
      options: Options(
        headers: {'x-goog-resumable': 'start', 'Content-Type': mimeType},
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
  } on DioException catch (e) {
    throw ResumableUploadException(
        'Upload could not start: ${e.message ?? 'the connection failed'}');
  }
  final status = res.statusCode ?? 0;
  if (status != 200 && status != 201) {
    throw ResumableUploadException('Upload could not start: HTTP $status',
        statusCode: status);
  }
  final uri = res.headers.value('location');
  if (uri == null || uri.isEmpty) {
    throw ResumableUploadException(
        'Upload could not start: the storage service returned no session '
        'address.');
  }
  return uri;
}

/// Asks the session how much it has COMMITTED; returns the next byte offset.
Future<int> _committedOffset(Dio dio, String uri, int total) async {
  final Response<dynamic> res;
  try {
    res = await dio.put<dynamic>(
      uri,
      options: Options(
        headers: {
          Headers.contentLengthHeader: 0,
          'Content-Range': 'bytes */$total',
        },
        validateStatus: (_) => true,
        followRedirects: false,
      ),
    );
  } on DioException catch (e) {
    throw ResumableUploadException(
        'Upload could not resume: ${e.message ?? 'the connection failed'}');
  }
  final status = res.statusCode ?? 0;
  if (status == 200 || status == 201) return total; // already done
  if (status == 308) return _rangeEnd(res.headers.value('range')) ?? 0;
  throw ResumableUploadException('Upload could not resume: HTTP $status',
      statusCode: status);
}

/// `bytes=0-8388607` → 8388608; null when absent or unreadable.
int? _rangeEnd(String? range) {
  if (range == null || range.isEmpty) return null;
  final last = int.tryParse(range.split('-').last.trim());
  return last == null ? null : last + 1;
}

Future<String?> _loadSession(String docId, String name, int size) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey(docId));
    if (raw == null) return null;
    final s = jsonDecode(raw) as Map<String, dynamic>;
    if (s['size'] != size || s['name'] != name) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(s['at'] as int);
    if (DateTime.now().difference(at) > _sessionTtl) return null;
    return s['uri'] as String?;
  } catch (_) {
    // Resumption is a bonus, not a requirement.
    return null;
  }
}

Future<void> _saveSession(
    String docId, String name, int size, String uri) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _sessionKey(docId),
        jsonEncode({
          'uri': uri,
          'size': size,
          'name': name,
          'at': DateTime.now().millisecondsSinceEpoch,
        }));
  } catch (_) {/* resumption is a bonus */}
}

Future<void> _clearSession(String docId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey(docId));
  } catch (_) {/* nothing to clear */}
}
