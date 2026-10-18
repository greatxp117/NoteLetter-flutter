import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The camera-roll sweep's native bridge (F-125 S1; INV-14,
/// `spec/features/camera-roll-sweep.md`). iOS only, for now.
///
/// Everything the sweep decides on the device runs natively, in the retired
/// Swift app's own code ported verbatim (`ios/Runner/CameraSweep/`):
/// - the **asset key**, `sha256("v1|<ms>|<w>x<h>|<originalFilename>")` read
///   from `PHAssetResource` — byte-identical to the Swift app's, or every
///   photo it already swept would upload again. This side never recomputes it;
/// - the **text check**: Vision `.fast` on a ~1024 px thumbnail with the
///   network off, a candidate at 80 characters or more, or any screenshot;
/// - **enumeration**: images only, newest first.
///
/// This is the bridge and nothing above it: the ledger and the service are
/// S2's, the screens S3's (which added [thumbnail], [openSettings] and
/// [libraryChanges]), the background task S4's.
///
/// **Only full library access runs.** With partial (`limited`) or no access,
/// every library method throws [SweepAccessRefused] instead of answering, and
/// its [SweepAccessRefused.sentence] says why.
class CameraSweepBridge {
  CameraSweepBridge({MethodChannel? channel, EventChannel? changes})
      : _channel = channel ?? const MethodChannel(channelName),
        _changes = changes ?? const EventChannel(changesName);

  static const channelName = 'xp.noteletter/camera_sweep';

  /// One event per photo-library change while listened to (S3).
  static const changesName = 'xp.noteletter/camera_sweep/changes';

  final MethodChannel _channel;
  final EventChannel _changes;

  /// The backfill's page size in the Swift service (`backfillBatchLimit`).
  static const defaultPageSize = 200;

  /// Whether this platform has the bridge. Android's half is S5 (F-123's
  /// SDK ruling).
  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<SweepConstants> constants() async =>
      SweepConstants.fromWire(_map(await _channel.invokeMethod<Object?>('constants')));

  /// The current authorization, without asking.
  Future<SweepAccess> access() async =>
      SweepAccess.fromWire(await _channel.invokeMethod<Object?>('access'));

  /// Asks for library access — the system prompt fires here, so call this
  /// ONLY when the user turns the sweep on, never at launch (spec §1).
  Future<SweepAccess> requestAccess() async =>
      SweepAccess.fromWire(await _channel.invokeMethod<Object?>('requestAccess'));

  /// One page of the library: still images, newest first, each with its key.
  /// `since` is inclusive and `until` exclusive, as in the Swift fetch. Bursts
  /// are not filtered: skip any asset whose [SweepAsset.isRepresentative] is
  /// false.
  Future<SweepPage> fetchImages({
    DateTime? since,
    DateTime? until,
    int offset = 0,
    int limit = defaultPageSize,
  }) async {
    if (offset < 0 || limit <= 0) {
      throw ArgumentError('offset must be >= 0 and limit > 0 (got $offset, $limit)');
    }
    return SweepPage.fromWire(_map(await _guard(() => _channel.invokeMethod<Object?>(
          'fetchImages',
          <String, Object?>{
            'sinceMs': since?.millisecondsSinceEpoch,
            'untilMs': until?.millisecondsSinceEpoch,
            'offset': offset,
            'limit': limit,
          },
        ))));
  }

  /// The on-device text check for one asset. Never downloads an original.
  Future<SweepExamination> examine(String localIdentifier) async =>
      SweepExamination.fromWire(_map(await _guard(() => _channel.invokeMethod<Object?>(
            'examine',
            <String, Object?>{'localIdentifier': localIdentifier},
          ))));

  /// The bytes a sweep would upload: a rendered JPEG, never the original
  /// resource (spec §5), written to a temporary file. null when the system
  /// rendered nothing.
  Future<SweepRendered?> renderedJpeg(String localIdentifier) async {
    final raw = await _guard(() => _channel.invokeMethod<Object?>(
          'renderedJpeg',
          <String, Object?>{'localIdentifier': localIdentifier},
        ));
    return raw == null ? null : SweepRendered.fromWire(_map(raw));
  }

  /// A review card's picture: the asset drawn at [width]×[height] pixels, as
  /// JPEG bytes, with the network OFF — null when the
  /// photo is not on this device (an iCloud original is never fetched just to
  /// be looked at).
  Future<Uint8List?> thumbnail(String localIdentifier,
      {int width = 216, int height = 280}) async {
    final raw = await _guard(() => _channel.invokeMethod<Object?>(
          'thumbnail',
          <String, Object?>{
            'localIdentifier': localIdentifier,
            'width': width,
            'height': height,
          },
        ));
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    throw FormatException('camera sweep: thumbnail is ${raw.runtimeType}');
  }

  /// Opens this app's page in the system settings, where photo access is
  /// changed — the action both refusals carry (feature spec §1). true when
  /// the system opened it.
  Future<bool> openSettings() async =>
      await _channel.invokeMethod<bool>('openSettings') ?? false;

  /// The library changed: a photo taken, deleted or edited, by any app. Only
  /// with FULL access; with less, listening fails with [SweepAccessRefused].
  /// The native side registers with Photos while this is listened to.
  Stream<void> libraryChanges() => _changes
      .receiveBroadcastStream()
      .map<void>((_) {})
      .handleError((Object e) {
        if (e is PlatformException) {
          final refused = SweepAccessRefused.fromCode(e.code);
          if (refused != null) throw refused;
        }
        throw e;
      });

  static Future<Object?> _guard(Future<Object?> Function() call) async {
    try {
      return await call();
    } on PlatformException catch (e) {
      final refused = SweepAccessRefused.fromCode(e.code);
      if (refused != null) throw refused;
      rethrow;
    }
  }
}

/// The Swift app's `PhotoLibraryAccess.Access`. Anything but `.authorized`
/// and `.limited` — not yet asked, denied, restricted — is [denied], as there.
enum SweepAccess {
  granted,
  limited,
  denied;

  static SweepAccess fromWire(Object? raw) => switch (raw) {
        'granted' => granted,
        'limited' => limited,
        'denied' => denied,
        _ => throw FormatException('camera sweep: unknown access "$raw"'),
      };
}

/// A library method refused to run because access is not full.
class SweepAccessRefused implements Exception {
  const SweepAccessRefused._(this.access, this.sentence);

  /// [SweepAccess.limited] or [SweepAccess.denied]; full access never refuses.
  final SweepAccess access;

  /// Why, in the retired Swift app's words (`CameraSweepSettingsView.swift`),
  /// verbatim. The spec asks for an explanation (feature spec §1, settings
  /// §Camera-roll sweep card) but owns no sentence: a SPEC GAP, reported in
  /// F-125 S1, not invented here.
  final String sentence;

  static const limitedSentence =
      'NoteLetter has access to a few hand-picked photos, not your library. '
      'A sweep needs the whole library to be useful — otherwise it would '
      'quietly find nothing.';
  static const deniedSentence = 'Photo access is off, so nothing can be swept.';

  static const limited = SweepAccessRefused._(SweepAccess.limited, limitedSentence);
  static const denied = SweepAccessRefused._(SweepAccess.denied, deniedSentence);

  /// The refusal for a native error code; null for any other code.
  static SweepAccessRefused? fromCode(String code) => switch (code) {
        'limited' => limited,
        'denied' => denied,
        _ => null,
      };

  @override
  String toString() => 'SweepAccessRefused(${access.name}): $sentence';
}

class SweepConstants {
  const SweepConstants({
    required this.schemeVersion,
    required this.prefilterVersion,
    required this.minimumCharacters,
  });

  /// The key's scheme (`v1`).
  final String schemeVersion;

  /// Stamped into every no-text verdict (`AssetPrefilter.version`), so a
  /// better filter revisits what an older one rejected.
  final int prefilterVersion;

  /// The candidate threshold: the backend's `_FACE_TEXT_THRESHOLD`, 80.
  final int minimumCharacters;

  factory SweepConstants.fromWire(Map<Object?, Object?> m) => SweepConstants(
        schemeVersion: _str(m, 'schemeVersion'),
        prefilterVersion: _int(m, 'prefilterVersion'),
        minimumCharacters: _int(m, 'minimumCharacters'),
      );
}

class SweepPage {
  const SweepPage({required this.total, required this.assets});

  /// Images matching the date window, before paging.
  final int total;
  final List<SweepAsset> assets;

  factory SweepPage.fromWire(Map<Object?, Object?> m) {
    final raw = m['assets'];
    if (raw is! List) throw const FormatException('camera sweep: page without assets');
    return SweepPage(
      total: _int(m, 'total'),
      assets: [for (final a in raw) SweepAsset.fromWire(_map(a))],
    );
  }
}

/// One enumerated image. Every field is metadata; no pixel was read.
class SweepAsset {
  const SweepAsset({
    required this.localIdentifier,
    required this.assetKey,
    required this.creationSeconds,
    required this.pixelWidth,
    required this.pixelHeight,
    required this.originalFilename,
    required this.isScreenshot,
    required this.isRepresentative,
  });

  /// This device's id for the asset — a fast ledger key, never the durable
  /// one (INV-14).
  final String localIdentifier;

  /// The INV-14 key, `v1:` + 64 hex digits. Opaque: send it, never parse it.
  final String assetKey;

  /// `creationDate.timeIntervalSince1970` exactly as the key read it; null
  /// when the asset has no date.
  final double? creationSeconds;
  final int pixelWidth;
  final int pixelHeight;

  /// `PHAssetResource.originalFilename`, unnormalised; null with no resource.
  final String? originalFilename;

  /// Marked a screenshot by the system: a candidate without a text check.
  final bool isScreenshot;

  /// false for a burst frame the system did not pick; the sweep skips it.
  final bool isRepresentative;

  DateTime? get creationDate => creationSeconds == null
      ? null
      : DateTime.fromMicrosecondsSinceEpoch((creationSeconds! * 1e6).round(), isUtc: true);

  factory SweepAsset.fromWire(Map<Object?, Object?> m) => SweepAsset(
        localIdentifier: _str(m, 'localIdentifier'),
        assetKey: _str(m, 'assetKey'),
        creationSeconds: _doubleOrNull(m, 'creationSeconds'),
        pixelWidth: _int(m, 'pixelWidth'),
        pixelHeight: _int(m, 'pixelHeight'),
        originalFilename: _strOrNull(m, 'originalFilename'),
        isScreenshot: _bool(m, 'isScreenshot'),
        isRepresentative: _bool(m, 'isRepresentative'),
      );
}

/// The Swift app's `AssetPrefilter.Verdict`.
enum SweepVerdict {
  /// A screenshot, or 80+ characters of text: worth uploading.
  candidate,

  /// Examined and too little text. Recorded with the prefilter version.
  noText,

  /// Not on the device (iCloud-optimized). Deferred — never "no text", which
  /// would be a permanent wrong answer.
  notLocallyAvailable;

  static SweepVerdict fromWire(Object? raw) => switch (raw) {
        'candidate' => candidate,
        'noText' => noText,
        'notLocallyAvailable' => notLocallyAvailable,
        _ => throw FormatException('camera sweep: unknown verdict "$raw"'),
      };
}

class SweepExamination {
  const SweepExamination({
    required this.verdict,
    required this.characters,
    required this.thumbnailWidth,
    required this.thumbnailHeight,
    required this.prefilterVersion,
  });

  final SweepVerdict verdict;

  /// Characters Vision recognized; null when no recognition ran (a
  /// screenshot, or no local thumbnail).
  final int? characters;

  /// The thumbnail recognition read, in pixels; null when none was read.
  final int? thumbnailWidth;
  final int? thumbnailHeight;
  final int prefilterVersion;

  factory SweepExamination.fromWire(Map<Object?, Object?> m) => SweepExamination(
        verdict: SweepVerdict.fromWire(m['verdict']),
        characters: _intOrNull(m, 'characters'),
        thumbnailWidth: _intOrNull(m, 'thumbnailWidth'),
        thumbnailHeight: _intOrNull(m, 'thumbnailHeight'),
        prefilterVersion: _int(m, 'prefilterVersion'),
      );
}

class SweepRendered {
  const SweepRendered({required this.path, required this.bytes});

  /// A temporary JPEG file.
  final String path;
  final int bytes;

  factory SweepRendered.fromWire(Map<Object?, Object?> m) =>
      SweepRendered(path: _str(m, 'path'), bytes: _int(m, 'bytes'));
}

// A shape the native side never sends is a failure, not a default: a reader
// that fills in what is missing cannot tell a broken bridge from a working one.

Map<Object?, Object?> _map(Object? raw) {
  if (raw is Map) return raw;
  throw FormatException('camera sweep: expected a map, got ${raw.runtimeType}');
}

Object? _req(Map<Object?, Object?> m, String key) {
  if (!m.containsKey(key)) throw FormatException('camera sweep: "$key" missing');
  return m[key];
}

String _str(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v is String) return v;
  throw FormatException('camera sweep: "$key" is not a string');
}

String? _strOrNull(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v == null || v is String) return v as String?;
  throw FormatException('camera sweep: "$key" is not a string');
}

int _int(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v is int) return v;
  throw FormatException('camera sweep: "$key" is not an int');
}

int? _intOrNull(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v == null || v is int) return v as int?;
  throw FormatException('camera sweep: "$key" is not an int');
}

double? _doubleOrNull(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  throw FormatException('camera sweep: "$key" is not a number');
}

bool _bool(Map<Object?, Object?> m, String key) {
  final v = _req(m, key);
  if (v is bool) return v;
  throw FormatException('camera sweep: "$key" is not a bool');
}
