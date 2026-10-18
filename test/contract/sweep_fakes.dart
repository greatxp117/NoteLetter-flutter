// The camera-roll sweep's test fakes (F-125): the bridge, the endpoints and a
// store that can fail. Shared by the service's tests (S2) and the screens' and
// the host's (S3), so the two cannot drift into two fakes of one bridge.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/firestore_service.dart' show CaptureMatch;
import 'package:flutter_app/services/sweep_ledger.dart';

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
  final List<(String, Uint8List, String)> puts = [];
  final Map<String, CaptureMatch?> filed = {};
  final List<String> finds = [];
  int? putFailsWith;
  Object? findThrows;

  @override
  Future<Map<String, dynamic>> openSession({
    required String assetKey,
    required String filename,
    required String mimeType,
    required int size,
    DateTime? capturedAt,
  }) async {
    sessions.add(SessionCall(assetKey, filename, mimeType, size, capturedAt));
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
  Future<void> putSigned(String url, Uint8List bytes, String mimeType) async {
    if (putFailsWith != null) {
      throw ApiException(putFailsWith!, 'Storage upload failed. Please try again.');
    }
    puts.add((url, bytes, mimeType));
  }

  @override
  Future<CaptureMatch?> findCapture(String assetKey) async {
    finds.add(assetKey);
    if (findThrows != null) throw findThrows!;
    return filed[assetKey];
  }
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
  return (
    CameraSweepService(bridge: bridge, ledger: ledger, endpoints: endpoints),
    ledger,
    bridge,
    endpoints,
    s,
  );
}

Map<String, Object?> snapshot(MemoryLedgerStore s) => Map.of(s.values);

