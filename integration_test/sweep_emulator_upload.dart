// The camera-roll sweep's device tests' one way to land a signed PUT against
// the EMULATOR (F-125 S2, S4). Not shipped: integration_test/ only.
//
// dev_server.py signs a capture session with the storage emulator's DOWNLOAD
// url (`/storage/v1/b/<bucket>/o/<object>?alt=media`), which answers a PUT
// with 501 (S2's FOUND; the fix is the backend's). The emulator does take the
// GCS JSON API's resumable upload: a POST opens a session for the SAME object,
// and its `location` takes the bytes as one bare PUT with a Content-Type — the
// request a real signed URL takes. [EmulatorPutStandIn] swaps the session's
// link for that one, so the app's own uploader (S4: the native background
// URLSession) sends the bytes exactly as it would to GCS.
//
// Since backend aaede52 (2026-10-20) the shim names its OWN write route
// instead, `/__storage/<bucket>/<object>`, which takes the bare PUT and writes
// the bytes into the storage emulator. That link is passed through as it is,
// and only its host moves on Android (the host's loopback is 10.0.2.2 there).
// The resumable swap stays for a shim older than that.
//
// Only the host's loopback: anything else is refused, so nothing here can
// send bytes to a real bucket.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/firestore_service.dart' show CaptureMatch;

class StandInUpload {
  StandInUpload(this.assetKey, this.downloadUrl, this.putUrl, this.size, this.openedAt);
  final String assetKey;

  /// The shim's link: where the object is read back.
  final String downloadUrl;

  /// What the app was given to PUT to.
  final String putUrl;

  /// The size the session declared.
  final int size;
  final DateTime openedAt;
}

class EmulatorPutStandIn implements SweepEndpoints {
  EmulatorPutStandIn(this.live);
  final SweepEndpoints live;

  /// When set, every upload goes through this localhost proxy
  /// (tool/sweep_hold_proxy.py), which holds it [holdMs] before passing it
  /// on — so it can finish after the app has left the foreground.
  String? via;
  int holdMs = 0;

  /// When set, each session call waits this long first — a session in
  /// flight, for an expiry to land on.
  Duration? sessionDelay;

  /// Called as each session call STARTS.
  void Function(String assetKey)? onSessionStart;

  final List<(String, DateTime)> sessions = [];
  final List<StandInUpload> uploads = [];
  final List<String> finds = [];

  static final _dio = Dio();

  @override
  Future<Map<String, dynamic>> openSession({
    required String assetKey,
    required String filename,
    required String mimeType,
    required int size,
    DateTime? capturedAt,
  }) async {
    sessions.add((assetKey, DateTime.now()));
    onSessionStart?.call(assetKey);
    final delay = sessionDelay;
    if (delay != null) await Future<void>.delayed(delay);
    final r = await live.openSession(
        assetKey: assetKey,
        filename: filename,
        mimeType: mimeType,
        size: size,
        capturedAt: capturedAt);
    final url = r['uploadUrl'];
    if (url is! String) return r;
    final String put, readBack;
    final write = shimWrite(url);
    if (write != null) {
      final (bucket, object) = write;
      put = Platform.isAndroid ? Uri.parse(url).replace(host: '10.0.2.2').toString() : url;
      readBack = '$storageOrigin/storage/v1/b/$bucket/o/${Uri.encodeComponent(object)}?alt=media';
    } else {
      put = await resumable(url, mimeType);
      readBack = url;
    }
    uploads.add(StandInUpload(assetKey, readBack, put, size, DateTime.now()));
    final via = this.via;
    return {
      ...r,
      'uploadUrl': via == null
          ? put
          : Uri.parse(via).replace(queryParameters: {'to': put, 'ms': '$holdMs'}).toString(),
    };
  }

  @override
  Future<CaptureMatch?> findCapture(String assetKey) {
    finds.add(assetKey);
    return live.findCapture(assetKey);
  }

  /// The storage emulator, as this device reaches it.
  static String get storageOrigin =>
      'http://${ApiService.emulatorHost}:${const int.fromEnvironment('EMULATOR_STORAGE_PORT', defaultValue: 9199)}';

  static bool _loopback(String host) =>
      host == 'localhost' || host == '127.0.0.1' || host == '10.0.2.2';

  /// The shim's own write route, `http://<loopback>/__storage/<bucket>/<object>`
  /// → (bucket, object); null for any other link.
  static (String, String)? shimWrite(String url) {
    final u = Uri.parse(url);
    final s = u.pathSegments;
    if (!_loopback(u.host) || s.length != 3 || s[0] != '__storage') return null;
    return (s[1], s[2]);
  }

  /// `http://localhost:<port>/storage/v1/b/<bucket>/o/<object>?alt=media`
  /// (dev_server.py's stand-in) → (origin, bucket, object).
  static (String, String, String) parse(String url) {
    final u = Uri.parse(url);
    final s = u.pathSegments;
    if (!_loopback(u.host) ||
        s.length != 6 ||
        s[0] != 'storage' ||
        s[1] != 'v1' ||
        s[2] != 'b' ||
        s[4] != 'o') {
      throw StateError('not the storage emulator\'s URL: $url');
    }
    return ('${u.scheme}://${u.host}:${u.port}', s[3], s[5]);
  }

  /// Opens a resumable upload on the emulator for the object [downloadUrl]
  /// names; its `location` takes the bytes as one bare PUT.
  static Future<String> resumable(String downloadUrl, String mimeType) async {
    final (origin, bucket, object) = parse(downloadUrl);
    final r = await _dio.post<Object?>(
      '$origin/upload/storage/v1/b/$bucket/o',
      queryParameters: {'uploadType': 'resumable', 'name': object},
      data: '{}',
      options: Options(
        headers: {'Content-Type': 'application/json', 'x-upload-content-type': mimeType},
        validateStatus: (_) => true,
      ),
    );
    final location = r.headers.value('location');
    if (r.statusCode != 200 || location == null) {
      throw StateError('the storage emulator opened no upload (${r.statusCode})');
    }
    final u = Uri.parse(location);
    if (!_loopback(u.host)) {
      throw StateError('not the storage emulator: $location');
    }
    return location;
  }

  /// The stored object's size, or null when there is none.
  static Future<int?> storedSize(String downloadUrl) async {
    final (origin, bucket, object) = parse(downloadUrl);
    final r = await _dio.get<Object?>(
      '$origin/storage/v1/b/$bucket/o/${Uri.encodeComponent(object)}',
      options: Options(validateStatus: (_) => true),
    );
    if (r.statusCode != 200) return null;
    final m = r.data is String ? jsonDecode(r.data as String) : r.data;
    return int.tryParse('${(m as Map)['size']}');
  }
}
