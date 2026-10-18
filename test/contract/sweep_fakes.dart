// The camera-roll sweep's test fakes (F-125): the bridge, the endpoints, the
// background uploader and task (S4), and a store that can fail. Shared by the
// service's tests (S2), the screens' and the host's (S3) and the background's
// (S4), so they cannot drift into two fakes of one bridge.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/firestore_service.dart' show CaptureMatch;
import 'package:flutter_app/services/sweep_background.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/services/sweep_uploader.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

SweepAsset asset(
  String id, {
  double? seconds,
  String? name = 'IMG_0001.HEIC',
  bool representative = true,
  bool screenshot = false,
}) =>
    SweepAsset(
      localIdentifier: id,
      assetKey: 'v1:${id.hashCode.toRadixString(16).padLeft(64, '0')}',
      creationSeconds: seconds ?? 1759568400.0,
      pixelWidth: 1600,
      pixelHeight: 1200,
      originalFilename: name,
      isScreenshot: screenshot,
      isRepresentative: representative,
    );

class FakeBridge implements CameraSweepBridge {
  FakeBridge(this.assets, {this.verdicts = const {}, this.version = 1});

  /// Newest first, as the native fetch answers.
  final List<SweepAsset> assets;
  final Map<String, SweepVerdict> verdicts;
  int version;
  SweepAccess accessNow = SweepAccess.granted;
  final Set<String> notRenderable = {};
  final List<String> examinedIds = [];
  final List<String> renderedPaths = [];
  final Directory tmp = Directory.systemTemp.createTempSync('sweep-test');

  void _guard() {
    if (accessNow == SweepAccess.limited) throw SweepAccessRefused.limited;
    if (accessNow == SweepAccess.denied) throw SweepAccessRefused.denied;
  }

  @override
  Future<SweepConstants> constants() async => SweepConstants(
      schemeVersion: 'v1', prefilterVersion: version, minimumCharacters: 80);

  @override
  Future<SweepAccess> access() async {
    accessReads++;
    return accessNow;
  }

  @override
  Future<SweepAccess> requestAccess() async {
    accessRequests++;
    if (promptAnswers != null) accessNow = promptAnswers!;
    return accessNow;
  }

  @override
  Future<SweepPage> fetchImages({
    DateTime? since,
    DateTime? until,
    int offset = 0,
    int limit = CameraSweepBridge.defaultPageSize,
  }) async {
    _guard();
    final inWindow = assets
        .where((a) =>
            since == null ||
            a.creationDate == null ||
            !a.creationDate!.isBefore(since))
        .toList();
    return SweepPage(
      total: inWindow.length,
      assets: inWindow.skip(offset).take(limit).toList(),
    );
  }

  /// When set, every examination waits on it — a pass held mid-flight.
  Future<void>? examineGate;

  @override
  Future<SweepExamination> examine(String localIdentifier) async {
    _guard();
    if (examineGate != null) await examineGate;
    examinedIds.add(localIdentifier);
    final v = verdicts[localIdentifier] ?? SweepVerdict.candidate;
    return SweepExamination(
      verdict: v,
      characters: v == SweepVerdict.candidate ? 242 : 3,
      thumbnailWidth: 1024,
      thumbnailHeight: 768,
      prefilterVersion: version,
    );
  }

  // ── S3: what the screens and the host use ──────────────────────────────────

  int accessReads = 0;
  int accessRequests = 0;

  /// What [requestAccess] answers (the prompt's outcome); [accessNow] follows.
  SweepAccess? promptAnswers;
  final List<String> thumbnailsAsked = [];
  int settingsOpened = 0;
  /// The native change observer: listened to while the host watches.
  late final StreamController<void> changes = StreamController<void>.broadcast(
      onListen: () => watched = true, onCancel: () => watched = false);
  bool watched = false;

  @override
  Future<Uint8List?> thumbnail(String localIdentifier,
      {int width = 216, int height = 280}) async {
    _guard();
    thumbnailsAsked.add(localIdentifier);
    return null;
  }

  @override
  Future<bool> openSettings() async {
    settingsOpened++;
    return true;
  }

  @override
  Stream<void> libraryChanges() {
    if (accessNow == SweepAccess.limited) {
      return Stream.error(SweepAccessRefused.limited);
    }
    if (accessNow == SweepAccess.denied) {
      return Stream.error(SweepAccessRefused.denied);
    }
    return changes.stream;
  }

  @override
  Future<SweepRendered?> renderedJpeg(String localIdentifier) async {
    _guard();
    if (notRenderable.contains(localIdentifier)) return null;
    final f = File('${tmp.path}/${localIdentifier.replaceAll('/', '_')}.jpg')
      ..writeAsBytesSync([0xFF, 0xD8, ...utf8.encode(localIdentifier), 0xFF, 0xD9]);
    renderedPaths.add(f.path);
    return SweepRendered(path: f.path, bytes: f.lengthSync());
  }
}

class SessionCall {
  SessionCall(this.assetKey, this.filename, this.mimeType, this.size, this.capturedAt);
  final String assetKey, filename, mimeType;
  final int size;
  final DateTime? capturedAt;
}

class FakeEndpoints implements SweepEndpoints {
  /// What the next session call answers, by asset key; the default is a
  /// fresh 201.
  final Map<String, Object> answers = {};
  final List<SessionCall> sessions = [];
  final Map<String, CaptureMatch?> filed = {};
  final List<String> finds = [];
  Object? findThrows;

  /// The signed PUT is the background uploader's since S4; it lives here so
  /// a test that asks "what was PUT" reads the same rig it always did.
  final FakeUploader uploader = FakeUploader();

  /// Every upload handed off: (url, the staged bytes, Content-Type).
  List<(String, Uint8List, String)> get puts =>
      [for (final s in uploader.starts) (s.url, s.bytes, s.mimeType)];

  /// What each upload's result says: an HTTP status that did not land.
  set putFailsWith(int? status) => uploader.failWith = status;

  /// When set, every session call waits on it — a session in flight.
  Future<void>? sessionGate;

  /// Called as each session call STARTS (before [sessionGate]).
  void Function(SessionCall call)? onSession;

  @override
  Future<Map<String, dynamic>> openSession({
    required String assetKey,
    required String filename,
    required String mimeType,
    required int size,
    DateTime? capturedAt,
  }) async {
    final call = SessionCall(assetKey, filename, mimeType, size, capturedAt);
    sessions.add(call);
    onSession?.call(call);
    if (sessionGate != null) await sessionGate;
    final a = answers[assetKey];
    if (a is Exception) throw a;
    return (a as Map<String, dynamic>?) ??
        {
          'docId': 'cam-$assetKey',
          'duplicate': false,
          'uploadUrl': 'https://storage.example/put/$assetKey',
          'gcsPath': 'raw/u/camera/cam-$assetKey',
        };
  }

  @override
  Future<CaptureMatch?> findCapture(String assetKey) async {
    finds.add(assetKey);
    if (findThrows != null) throw findThrows!;
    return filed[assetKey];
  }
}

class UploadStart {
  UploadStart(this.uploadId, this.url, this.bytes, this.mimeType, this.localIdentifier,
      this.assetKey);
  final String uploadId, url, mimeType, localIdentifier, assetKey;
  final Uint8List bytes;
}

/// The background uploader, faked: it stages by MOVING the rendered file, as
/// the native one does, and each started upload's result is written to
/// [waiting] (as the native side writes it down) and signalled — at once,
/// or when the test says ([hold], [land]).
class FakeUploader implements SweepUploader {
  /// What a result says: null lands it, an int is the bucket's status, a
  /// String URLSession's own failure.
  Object? failWith;

  /// Results wait for [land] — an upload still on its way.
  bool hold = false;

  /// [start] refuses, as the native side does for a file no longer staged.
  bool refuseStart = false;

  final List<UploadStart> starts = [];
  final List<String> discarded = [];
  final List<String> acknowledged = [];

  /// Results written down and not yet acknowledged.
  final List<SweepUploadResult> waiting = [];

  /// Uploads an earlier launch started that the system still holds.
  final List<SweepUploadInFlight> elsewhere = [];

  bool failAcknowledge = false;
  int finishedReads = 0;

  final Map<String, File> _staged = {};
  final Set<String> _running = {};
  final StreamController<void> _signal = StreamController<void>.broadcast();
  final Directory _dir = Directory.systemTemp.createTempSync('sweep-uploads');
  int _n = 0;

  /// Every upload id staged and neither started nor discarded.
  Iterable<String> get stagedNotStarted => _staged.keys.where((id) =>
      !_running.contains(id) && !starts.any((s) => s.uploadId == id));

  @override
  Future<SweepStaged> stage(String renderedPath) async {
    final id = 'u${++_n}';
    final f = File(renderedPath).renameSync('${_dir.path}/$id.jpg');
    _staged[id] = f;
    return SweepStaged(uploadId: id, bytes: f.lengthSync());
  }

  @override
  Future<void> start({
    required String uploadId,
    required String url,
    required String mimeType,
    required String localIdentifier,
    required String assetKey,
  }) async {
    final f = _staged[uploadId];
    if (f == null || refuseStart) {
      throw PlatformException(code: 'uploadFailed', message: 'not staged: $uploadId');
    }
    starts.add(UploadStart(
        uploadId, url, f.readAsBytesSync(), mimeType, localIdentifier, assetKey));
    _running.add(uploadId);
    if (!hold) scheduleMicrotask(() => land(uploadId));
  }

  /// The result of [uploadId] arrives, saying what [failWith] says.
  void land(String uploadId) {
    if (!_running.remove(uploadId)) return;
    final s = starts.firstWhere((s) => s.uploadId == uploadId);
    final f = failWith;
    _staged.remove(uploadId)?.deleteSync();
    waiting.add(SweepUploadResult(
      uploadId: uploadId,
      localIdentifier: s.localIdentifier,
      assetKey: s.assetKey,
      ok: f == null,
      statusCode: f is int ? f : (f == null ? 200 : 0),
      error: f is String ? f : null,
    ));
    _signal.add(null);
  }

  /// Every upload still on its way lands.
  void landAll() {
    for (final id in List.of(_running)) {
      land(id);
    }
  }

  /// A result from an earlier launch, written down while nobody listened.
  void resultFromEarlierLaunch(SweepUploadResult r) => waiting.add(r);

  Iterable<String> get running => _running;

  @override
  Future<void> discard(String uploadId) async {
    discarded.add(uploadId);
    _staged.remove(uploadId)?.deleteSync();
  }

  @override
  Future<List<SweepUploadInFlight>> inFlight() async => [
        ...elsewhere,
        for (final s in starts)
          if (_running.contains(s.uploadId))
            SweepUploadInFlight(
                uploadId: s.uploadId, localIdentifier: s.localIdentifier, assetKey: s.assetKey),
      ];

  @override
  Future<List<SweepUploadResult>> finished() async {
    finishedReads++;
    return List.of(waiting);
  }

  @override
  Future<void> acknowledge(Iterable<String> uploadIds) async {
    if (failAcknowledge) throw PlatformException(code: 'uploadFailed', message: 'defaults');
    final ids = uploadIds.toSet();
    acknowledged.addAll(ids);
    waiting.removeWhere((r) => ids.contains(r.uploadId));
  }

  @override
  Stream<void> get resultsWaiting => _signal.stream;
}

/// The BGProcessingTask, faked: the test plays iOS, calling [launch] and
/// [expire] as the system would.
class FakeBackground implements SweepBackground {
  Future<Map<String, Object?>> Function()? _onRun;
  Future<void> Function()? _onExpire;
  final List<bool> scheduledCalls = [];
  SweepSchedule answer = const SweepSchedule(scheduled: true);
  bool attached = false;

  @override
  Future<void> attach({
    required Future<Map<String, Object?>> Function() onRun,
    required Future<void> Function() onExpire,
  }) async {
    _onRun = onRun;
    _onExpire = onExpire;
    attached = true;
  }

  @override
  void detach() => attached = false;

  @override
  Future<SweepSchedule> setScheduled(bool on) async {
    scheduledCalls.add(on);
    return on ? answer : const SweepSchedule(scheduled: false);
  }

  /// iOS launches the task; completes when the Dart side answers.
  Future<Map<String, Object?>> launch() => _onRun!();

  /// iOS takes the time back.
  Future<void> expire() => _onExpire!();
}

/// A store whose writes can be made to fail, to prove write-before-move.
class FlakyStore extends MemoryLedgerStore {
  bool failWrites = false;

  @override
  Future<void> write(String key, Object? value) async {
    if (failWrites) throw StateError('disk full');
    return super.write(key, value);
  }
}

Future<(CameraSweepService, SweepLedger, FakeBridge, FakeEndpoints, MemoryLedgerStore)>
    rig(List<SweepAsset> assets,
        {Map<String, SweepVerdict> verdicts = const {},
        MemoryLedgerStore? store}) async {
  final s = store ?? MemoryLedgerStore();
  final ledger = await SweepLedger.load(s, now: () => DateTime(2026, 10, 18, 12));
  // The fixtures' dates are 2025/2026; reach back far enough for all.
  await ledger.setBackfillStart(DateTime.utc(2020));
  final bridge = FakeBridge(assets, verdicts: verdicts);
  final endpoints = FakeEndpoints();
  final service = CameraSweepService(
      bridge: bridge, ledger: ledger, endpoints: endpoints, uploader: endpoints.uploader);
  await service.attachUploads();
  return (
    service,
    ledger,
    bridge,
    endpoints,
    s,
  );
}

Map<String, Object?> snapshot(MemoryLedgerStore s) => Map.of(s.values);

