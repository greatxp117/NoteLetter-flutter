import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import 'row_decode.dart';

/// Which photos this device has already dealt with, and how the sweep is set
/// up (F-125 S2; the retired Swift app's `SweepLedger.swift`, NoteLetter
/// 910864a).
///
/// **Client-local and per-device by design** (ADR-023; settings.md
/// §Client-local preferences): there is no settings endpoint and no Firestore
/// document. Which device sweeps is a property of the device, not the account.
/// Two devices agree on what is already ingested through the INV-14 asset key,
/// not through shared state, which is also what makes this ledger safely
/// disposable: a reinstall wipes it, the re-sweep recomputes identical keys,
/// and the backend answers every one `duplicate`.
///
/// Kept in THIS app's App Group, [sweepAppGroup] (the one F-122 added for the
/// share extension), never the Swift app's `group.xp.NoteLetter`. It starts
/// empty: the Swift app's verdicts are not carried over (Xavier, 2026-10-18,
/// "start fresh").
///
/// Every setter **writes before it moves**: the value is persisted first and
/// the in-memory state changes only once the write came back, so a failed
/// write leaves the ledger saying what the store holds.
class SweepLedger extends ChangeNotifier {
  SweepLedger._(
    this._store, {
    required bool enabled,
    required SweepMode mode,
    required DateTime backfillStart,
    required DateTime? cursor,
    required bool backfillComplete,
    required Map<String, LedgerVerdict> verdicts,
  })  : _enabled = enabled,
        _mode = mode,
        _backfillStart = backfillStart,
        _cursor = cursor,
        _backfillComplete = backfillComplete,
        _verdicts = verdicts;

  /// The Swift app's own key names, under this app's suite.
  static const kEnabled = 'sweep.enabled';
  static const kMode = 'sweep.mode';
  static const kBackfillStart = 'sweep.backfillStart';
  static const kCursor = 'sweep.cursor';
  static const kBackfillComplete = 'sweep.backfillComplete';
  static const kVerdicts = 'sweep.verdicts';
  static const keys = {
    kEnabled,
    kMode,
    kBackfillStart,
    kCursor,
    kBackfillComplete,
    kVerdicts,
  };

  /// How far back the catch-up pass reaches until the user picks a date: 90
  /// calendar days, recomputed on every load while nothing is stored, as in
  /// Swift (whose default was never persisted either).
  static const defaultBackfillDays = 90;

  final SweepLedgerStore _store;

  static Future<SweepLedger> load(
    SweepLedgerStore store, {
    DateTime Function() now = DateTime.now,
  }) async {
    final raw = await store.read(keys);
    final n = now();
    return SweepLedger._(
      store,
      enabled: raw[kEnabled] == true,
      // Review until the user chooses (Swift's default).
      mode: SweepMode.fromStored(raw[kMode]) ?? SweepMode.review,
      backfillStart: _date(raw[kBackfillStart]) ??
          DateTime(n.year, n.month, n.day - defaultBackfillDays, n.hour,
              n.minute, n.second, n.millisecond),
      cursor: _date(raw[kCursor]),
      backfillComplete: raw[kBackfillComplete] == true,
      verdicts: decodeVerdicts(raw[kVerdicts]),
    );
  }

  bool _enabled;
  SweepMode _mode;
  DateTime _backfillStart;
  DateTime? _cursor;
  bool _backfillComplete;
  Map<String, LedgerVerdict> _verdicts;

  bool get enabled => _enabled;
  SweepMode get mode => _mode;

  /// How far back the user asked the catch-up pass to reach.
  DateTime get backfillStart => _backfillStart;

  /// The oldest capture date the backfill has walked to. Persisted after
  /// every examined asset, so an interrupted sweep resumes rather than
  /// restarts. Progress reporting, not the skip mechanism: the verdicts are
  /// what prevent rework.
  DateTime? get cursor => _cursor;
  bool get backfillComplete => _backfillComplete;

  Future<void> setEnabled(bool value) async {
    await _store.write(kEnabled, value);
    _enabled = value;
    notifyListeners();
  }

  Future<void> setMode(SweepMode value) async {
    await _store.write(kMode, value.name);
    _mode = value;
    notifyListeners();
  }

  Future<void> setBackfillStart(DateTime value) async {
    await _store.write(kBackfillStart, value.millisecondsSinceEpoch);
    _backfillStart = value;
    notifyListeners();
  }

  Future<void> setCursor(DateTime? value) async {
    await _store.write(kCursor, value?.millisecondsSinceEpoch);
    _cursor = value;
    notifyListeners();
  }

  Future<void> setBackfillComplete(bool value) async {
    await _store.write(kBackfillComplete, value);
    _backfillComplete = value;
    notifyListeners();
  }

  // ── Verdicts, keyed on the LOCAL identifier ────────────────────────────────
  //
  // The local identifier is the right key HERE: it is the fastest way to skip
  // an asset this device has already handled, and losing it on restore costs
  // only a re-scan, which the server-side key then makes cheap. It is never
  // the durable key (INV-14; that is `SweepAsset.assetKey`).

  LedgerVerdict? verdict(String localIdentifier) => _verdicts[localIdentifier];

  /// A copy: the ledger is the only writer of its own map.
  Map<String, LedgerVerdict> get verdicts => Map.unmodifiable(_verdicts);

  Future<void> record(LedgerVerdict verdict, String localIdentifier) async {
    final next = Map<String, LedgerVerdict>.of(_verdicts)
      ..[localIdentifier] = verdict;
    await _store.write(kVerdicts, encodeVerdicts(next));
    _verdicts = next;
    notifyListeners();
  }

  /// An asset needs looking at unless a verdict that still stands was reached.
  /// A no-text verdict from an OLDER pre-filter is reconsidered, and a
  /// deferred one always is (Swift `needsExamination`).
  bool needsExamination(String localIdentifier, {required int prefilterVersion}) =>
      switch (_verdicts[localIdentifier]?.kind) {
        SweepVerdictKind.ingested || SweepVerdictKind.dismissed => false,
        SweepVerdictKind.noText =>
          _verdicts[localIdentifier]!.prefilterVersion! < prefilterVersion,
        SweepVerdictKind.deferredNotLocal || null => true,
      };

  int get ingestedCount =>
      _verdicts.values.where((v) => v.kind == SweepVerdictKind.ingested).length;
  int get deferredCount => _verdicts.values
      .where((v) => v.kind == SweepVerdictKind.deferredNotLocal)
      .length;

  /// Forgets every verdict and the backfill's progress; keeps the setup
  /// (enabled, mode, start date), as Swift's `reset()` did.
  Future<void> reset() async {
    await _store.write(kVerdicts, null);
    await _store.write(kCursor, null);
    await _store.write(kBackfillComplete, false);
    _verdicts = {};
    _cursor = null;
    _backfillComplete = false;
    notifyListeners();
  }

  // ── The stored shape ────────────────────────────────────────────────────────

  /// The Swift app's Codable shape, kept so the two ledgers read alike:
  /// `{"IMG-local-id": {"ingested": {}}, "other-id": {"noText":
  /// {"prefilterVersion": 1}}, …}`, keyed by local identifier, as one JSON
  /// string.
  static String encodeVerdicts(Map<String, LedgerVerdict> verdicts) =>
      jsonEncode({for (final e in verdicts.entries) e.key: e.value.toJson()});

  /// One verdict that cannot be read costs that verdict, never the ledger
  /// (Swift `decodeVerdicts`, after Flutter d93420f's rule for every list
  /// read). A whole-map decode would forget EVERY verdict over one entry in a
  /// shape this build does not know: each dismissed photo would come back to
  /// the review tray and each ingested one would be examined again, with
  /// nothing logged. Each entry decodes on its own; an unreadable one is
  /// dropped and logged by its key.
  static Map<String, LedgerVerdict> decodeVerdicts(Object? raw) {
    if (raw == null || (raw is String && raw.isEmpty)) return {};
    Object? rows;
    try {
      rows = raw is String ? jsonDecode(raw) : raw;
    } catch (e) {
      debugPrint('sweep ledger: unreadable as a whole (${raw.toString().length} '
          'chars): $e');
      return {};
    }
    if (rows is! Map) {
      debugPrint('sweep ledger: unreadable as a whole (not a map)');
      return {};
    }
    final kept = decodeRows<MapEntry<Object?, Object?>, MapEntry<String, LedgerVerdict>>(
      'sweep.verdicts',
      rows.entries,
      (e) => '${e.key}',
      (e) {
        final key = e.key;
        if (key is! String) throw const FormatException('key is not a string');
        return MapEntry(key, LedgerVerdict.fromJson(e.value));
      },
      onDropped: (_, id, error) => debugPrint(
          'sweep ledger: dropped the verdict for $id — it could not be read '
          '($error); the rest of the ledger stands.'),
    );
    return Map.fromEntries(kept);
  }

  static DateTime? _date(Object? raw) =>
      raw is int ? DateTime.fromMillisecondsSinceEpoch(raw) : null;
}

/// The user's autonomy choice (spec §3). Distinct from the service's dry run.
enum SweepMode {
  /// Candidates are ingested as they are found — once the first backfill is
  /// done, which always goes through the review tray.
  automatic,

  /// Candidates wait in a client-local tray and are ingested only on approval.
  review;

  static SweepMode? fromStored(Object? raw) => switch (raw) {
        'automatic' => automatic,
        'review' => review,
        _ => null,
      };
}

enum SweepVerdictKind { ingested, dismissed, noText, deferredNotLocal }

/// One asset's standing verdict. **Never a boolean** (spec §2): with remote
/// fetch off the system hands back a low-resolution placeholder for an
/// iCloud-optimized photo, text recognition on it finds nothing, and a
/// boolean ledger would record a text-bearing photo as "no text" permanently.
/// So the ledger records WHY, and stamps the pre-filter version that decided.
///
/// Four states, as in Swift: the spec's three (ingested, no-text@version,
/// deferred) plus `dismissed`, the review tray's own "not this one".
@immutable
class LedgerVerdict {
  const LedgerVerdict._(this.kind, [this.prefilterVersion]);

  const LedgerVerdict.noText(int prefilterVersion)
      : this._(SweepVerdictKind.noText, prefilterVersion);

  static const ingested = LedgerVerdict._(SweepVerdictKind.ingested);
  static const dismissed = LedgerVerdict._(SweepVerdictKind.dismissed);
  static const deferredNotLocal =
      LedgerVerdict._(SweepVerdictKind.deferredNotLocal);

  final SweepVerdictKind kind;

  /// Set exactly on [SweepVerdictKind.noText].
  final int? prefilterVersion;

  Map<String, Object?> toJson() => switch (kind) {
        SweepVerdictKind.noText => {
            'noText': {'prefilterVersion': prefilterVersion}
          },
        _ => {kind.name: <String, Object?>{}},
      };

  /// Closed: anything but one of the four shapes throws.
  static LedgerVerdict fromJson(Object? raw) {
    if (raw is! Map || raw.length != 1) {
      throw const FormatException('a verdict is a one-key map');
    }
    final MapEntry(:key, :value) = raw.entries.single;
    if (value is! Map) throw FormatException('"$key" carries no object');
    switch (key) {
      case 'ingested' when value.isEmpty:
        return ingested;
      case 'dismissed' when value.isEmpty:
        return dismissed;
      case 'deferredNotLocal' when value.isEmpty:
        return deferredNotLocal;
      case 'noText' when value.length == 1 && value['prefilterVersion'] is int:
        return LedgerVerdict.noText(value['prefilterVersion'] as int);
    }
    throw FormatException('unknown verdict "$key"');
  }

  @override
  bool operator ==(Object other) =>
      other is LedgerVerdict &&
      other.kind == kind &&
      other.prefilterVersion == prefilterVersion;

  @override
  int get hashCode => Object.hash(kind, prefilterVersion);

  @override
  String toString() => kind == SweepVerdictKind.noText
      ? 'noText@$prefilterVersion'
      : kind.name;
}

/// Where the ledger lives. Small on purpose: read the six keys, write one.
abstract class SweepLedgerStore {
  Future<Map<String, Object?>> read(Set<String> keys);

  /// `null` removes the key. Values are bool, int or String.
  Future<void> write(String key, Object? value);
}

/// This app's App Group: the one F-122 added for the share extension
/// (`ios/Runner/Runner.entitlements`), never the Swift app's.
const sweepAppGroup = 'group.xp.NoteLetter.Flutter';

/// Android's ledger file (S5c), the App Group's counterpart there.
const sweepAndroidStore = 'camera_sweep_ledger';

/// The App Group's shared defaults (`UserDefaults(suiteName:)`, as in Swift).
class AppGroupLedgerStore implements SweepLedgerStore {
  AppGroupLedgerStore()
      : _prefs = SharedPreferencesAsync(
          options: defaultTargetPlatform == TargetPlatform.android
              // Android has no App Group (its share target is in-app). The
              // classic SharedPreferences backend, in its own file: DataStore
              // allows ONE instance per file per process, and the background
              // pass (S5c) can run a second engine beside the app's.
              ? const SharedPreferencesAsyncAndroidOptions(
                  backend: SharedPreferencesAndroidBackendLibrary.SharedPreferences,
                  originalSharedPreferencesOptions:
                      AndroidSharedPreferencesStoreOptions(fileName: sweepAndroidStore),
                )
              : SharedPreferencesAsyncFoundationOptions(suiteName: sweepAppGroup),
        );

  final SharedPreferencesAsync _prefs;

  @override
  Future<Map<String, Object?>> read(Set<String> keys) =>
      _prefs.getAll(allowList: keys);

  @override
  Future<void> write(String key, Object? value) => switch (value) {
        null => _prefs.remove(key),
        bool v => _prefs.setBool(key, v),
        int v => _prefs.setInt(key, v),
        String v => _prefs.setString(key, v),
        _ => throw ArgumentError('sweep ledger: cannot store ${value.runtimeType}'),
      };
}

/// For tests, and anything that must not touch the device's ledger.
class MemoryLedgerStore implements SweepLedgerStore {
  MemoryLedgerStore([Map<String, Object?>? values]) : values = {...?values};

  final Map<String, Object?> values;

  @override
  Future<Map<String, Object?>> read(Set<String> keys) async =>
      {for (final k in keys) if (values.containsKey(k)) k: values[k]};

  @override
  Future<void> write(String key, Object? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}
