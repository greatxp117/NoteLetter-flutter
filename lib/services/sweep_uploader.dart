import 'package:flutter/services.dart';

import 'camera_sweep_bridge.dart' show CameraSweepBridge;

/// The camera-roll sweep's uploads (F-125 S4): the bare signed PUT (INV-08 —
/// no Authorization header, the declared Content-Type) on a BACKGROUND
/// `URLSession`, so an upload survives the app being suspended, and its
/// result reaches the ledger even when it lands while the app is dead.
///
/// Native: `ios/Runner/CameraSweep/CameraSweepUploader.swift`, ported from the
/// retired Swift app's. The order is what keeps the server consistent:
///  1. [stage] the rendered JPEG — before any request, so nothing between a
///     capture session and its upload can fail on the disk;
///  2. open the capture session (the caller's);
///  3. [start] the upload against the session's link, or [discard] the staged
///     file when there is nothing to send.
///
/// A result is WRITTEN DOWN natively before anyone is told, and stays in
/// [finished] until [acknowledge]d: the ledger records `ingested` from it, and
/// a result nobody was listening for is still there at the next launch.
abstract class SweepUploader {
  /// Moves the rendered JPEG at [renderedPath] into the uploader's keeping.
  Future<SweepStaged> stage(String renderedPath);

  /// Hands the staged file to the background session. Returns once the
  /// system has the task, NOT when the bytes land — that is a [finished]
  /// result, whenever it comes.
  Future<void> start({
    required String uploadId,
    required String url,
    required String mimeType,
    required String localIdentifier,
    required String assetKey,
  });

  /// Deletes a staged file nothing will send.
  Future<void> discard(String uploadId);

  /// The uploads the system still holds — including ones an earlier launch
  /// started — by what they are for.
  Future<List<SweepUploadInFlight>> inFlight();

  /// Results not yet acknowledged, oldest first.
  Future<List<SweepUploadResult>> finished();

  Future<void> acknowledge(Iterable<String> uploadIds);

  /// One event whenever a result is waiting in [finished].
  Stream<void> get resultsWaiting;
}

class SweepStaged {
  const SweepStaged({required this.uploadId, required this.bytes});
  final String uploadId;

  /// The size the capture session declares.
  final int bytes;
}

class SweepUploadInFlight {
  const SweepUploadInFlight({
    required this.uploadId,
    required this.localIdentifier,
    required this.assetKey,
  });
  final String uploadId;
  final String localIdentifier;
  final String assetKey;

  factory SweepUploadInFlight.fromWire(Map<Object?, Object?> m) => SweepUploadInFlight(
        uploadId: _str(m, 'uploadId'),
        localIdentifier: _str(m, 'localIdentifier'),
        assetKey: _str(m, 'assetKey'),
      );
}

/// One upload's outcome. Only a 2xx with no transport error LANDED.
class SweepUploadResult {
  const SweepUploadResult({
    required this.uploadId,
    required this.localIdentifier,
    required this.assetKey,
    required this.ok,
    required this.statusCode,
    this.error,
    this.finishedAtMs,
    this.appState,
  });

  final String uploadId;
  final String localIdentifier;
  final String assetKey;
  final bool ok;

  /// The bucket's answer; 0 when there was none ([error] says why).
  final int statusCode;

  /// URLSession's own failure, in its words (`localizedDescription`).
  final String? error;

  /// When the result arrived, and `UIApplication.applicationState` then (2 is
  /// background) — what the device test reads.
  final double? finishedAtMs;
  final int? appState;

  factory SweepUploadResult.fromWire(Map<Object?, Object?> m) => SweepUploadResult(
        uploadId: _str(m, 'uploadId'),
        localIdentifier: _str(m, 'localIdentifier'),
        assetKey: _str(m, 'assetKey'),
        ok: _bool(m, 'ok'),
        statusCode: _int(m, 'statusCode'),
        error: _strOrNull(m, 'error'),
        finishedAtMs: (m['finishedAtMs'] as num?)?.toDouble(),
        appState: m['appState'] as int?,
      );

  @override
  String toString() => 'SweepUploadResult($uploadId $localIdentifier '
      '${ok ? 'landed' : 'failed $statusCode${error == null ? '' : ' $error'}'}'
      '${appState == null ? '' : ' appState $appState'})';
}

/// The real one, over the sweep's method channel.
class NativeSweepUploader implements SweepUploader {
  NativeSweepUploader({MethodChannel? channel, EventChannel? events})
      : _channel = channel ?? const MethodChannel(CameraSweepBridge.channelName),
        _events = events ?? const EventChannel(eventsName);

  static const eventsName = 'xp.noteletter/camera_sweep/uploads';

  final MethodChannel _channel;
  final EventChannel _events;

  @override
  Future<SweepStaged> stage(String renderedPath) async {
    final m = _map(await _channel.invokeMethod<Object?>('stageUpload', {'path': renderedPath}));
    return SweepStaged(uploadId: _str(m, 'uploadId'), bytes: _int(m, 'bytes'));
  }

  @override
  Future<void> start({
    required String uploadId,
    required String url,
    required String mimeType,
    required String localIdentifier,
    required String assetKey,
  }) =>
      _channel.invokeMethod<void>('startUpload', {
        'uploadId': uploadId,
        'url': url,
        'mimeType': mimeType,
        'localIdentifier': localIdentifier,
        'assetKey': assetKey,
      });

  @override
  Future<void> discard(String uploadId) =>
      _channel.invokeMethod<void>('discardUpload', {'uploadId': uploadId});

  @override
  Future<List<SweepUploadInFlight>> inFlight() async =>
      _list(await _channel.invokeMethod<Object?>('uploadsInFlight'))
          .map((e) => SweepUploadInFlight.fromWire(_map(e)))
          .toList();

  @override
  Future<List<SweepUploadResult>> finished() async =>
      _list(await _channel.invokeMethod<Object?>('finishedUploads'))
          .map((e) => SweepUploadResult.fromWire(_map(e)))
          .toList();

  @override
  Future<void> acknowledge(Iterable<String> uploadIds) =>
      _channel.invokeMethod<void>('acknowledgeUploads', {'uploadIds': uploadIds.toList()});

  @override
  Stream<void> get resultsWaiting =>
      _events.receiveBroadcastStream().map<void>((_) {});
}

// Closed decoding, as the bridge's: a shape the native side never sends is a
// failure, never a default.

List<Object?> _list(Object? raw) {
  if (raw is List) return raw;
  throw FormatException('camera sweep uploads: expected a list, got ${raw.runtimeType}');
}

Map<Object?, Object?> _map(Object? raw) {
  if (raw is Map) return raw;
  throw FormatException('camera sweep uploads: expected a map, got ${raw.runtimeType}');
}

Object? _req(Map<Object?, Object?> m, String key) {
  if (!m.containsKey(key)) throw FormatException('camera sweep uploads: "$key" missing');
  return m[key];
}

String _str(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v is String) return v;
  throw FormatException('camera sweep uploads: "$key" is not a string');
}

String? _strOrNull(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v == null || v is String) return v as String?;
  throw FormatException('camera sweep uploads: "$key" is not a string');
}

int _int(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v is int) return v;
  throw FormatException('camera sweep uploads: "$key" is not an int');
}

bool _bool(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v is bool) return v;
  throw FormatException('camera sweep uploads: "$key" is not a bool');
}
