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
    required bool backfillComplete,
    required ChangeMark? changeMark,
    required Map<String, LedgerVerdict> verdicts,
    required SweepReach? reach,
    required DateTime? lastLookedAt,
  })  : _enabled = enabled,
        _mode = mode,
        _backfillStart = backfillStart,
        _backfillComplete = backfillComplete,
        _changeMark = changeMark,
        _verdicts = verdicts,
        _reach = reach,
        _lastLookedAt = lastLookedAt;

  /// The Swift app's own key names, under this app's suite.
  static const kEnabled = 'sweep.enabled';
  static const kMode = 'sweep.mode';
  static const kBackfillStart = 'sweep.backfillStart';
  static const kBackfillComplete = 'sweep.backfillComplete';
  static const kVerdicts = 'sweep.verdicts';

  /// The change token a finished pass left (5.40.0, ADR-195); this app's own
  /// key, as Swift had no token.
  static const kChangeMark = 'sweep.changeMark';

  /// Which of the setup's reaches set the start date (5.43.0, ADR-198): the
  /// panel names the reach as set ("The last year · done"), and a date
  /// cannot say which reach it was once time has moved on. Absent for a
  /// date set before D, which the panel reads as "Since {date}".
  static const kReach = 'sweep.reach';

  /// When the last pass ended without an error (5.43.0, ADR-198 decision 7):
  /// the panel's "looked {ago}". Never drawn before one has.
  static const kLastLookedAt = 'sweep.lastLookedAt';
  static const keys = {
    kEnabled,
    kMode,
    kBackfillStart,
    kBackfillComplete,
    kVerdicts,
    kChangeMark,
    kReach,
    kLastLookedAt,
  };

  /// The backfill cursor until 5.40.0. Written after every examined photo and
  /// never read (spec §7: the verdicts are what resume a walk); Start over
  /// removes what an older build left.
  static const kRetiredCursor = 'sweep.cursor';

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
      backfillComplete: raw[kBackfillComplete] == true,
      changeMark: ChangeMark.decode(raw[kChangeMark]),
      verdicts: decodeVerdicts(raw[kVerdicts]),
      reach: SweepReach.fromStored(raw[kReach]),
      lastLookedAt: _date(raw[kLastLookedAt]),
    );
  }

  bool _enabled;
  SweepMode _mode;
  DateTime _backfillStart;
  bool _backfillComplete;
  ChangeMark? _changeMark;
  Map<String, LedgerVerdict> _verdicts;
  SweepReach? _reach;
  DateTime? _lastLookedAt;

  bool get enabled => _enabled;
  SweepMode get mode => _mode;

  /// How far back the user asked the catch-up pass to reach.
  DateTime get backfillStart => _backfillStart;

  bool get backfillComplete => _backfillComplete;

  /// Where the last pass that FINISHED left the library: a later pass reads
  /// only what changed since it (spec §7). null until a walk has finished
  /// on a platform that keeps a history.
  ChangeMark? get changeMark => _changeMark;

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

  /// The reach the start date was set by, or null for a date set before D
  /// (5.43.0).
  SweepReach? get reach => _reach;

  /// When the last pass ended without an error; null until one has.
  DateTime? get lastLookedAt => _lastLookedAt;

  /// A start date that MOVES clears the walk's done mark (5.43.0, ADR-198
  /// decision 4; feature §3): the whole walk §7 rule 4 then requires sets it
  /// again when it reaches the date, and until then every find waits for
  /// review — the first look back and each *Look further back* alike. Until
  /// 5.43.0 the mark stood, so a date moved earlier in Automatic mode filed
  /// its finds unreviewed. [reach] is what set it; null clears it (a date
  /// set any other way). Each value is written before any moves.
  Future<void> setBackfillStart(DateTime value, {SweepReach? reach}) async {
    final moved = value.millisecondsSinceEpoch != _backfillStart.millisecondsSinceEpoch;
    if (moved && _backfillComplete) {
      // First, so a store that takes this and refuses the date is left
      // walking (to review) rather than trusting a mark for another date.
      await _store.write(kBackfillComplete, false);
      _backfillComplete = false;
    }
    await _store.write(kBackfillStart, value.millisecondsSinceEpoch);
    await _store.write(kReach, reach?.name);
    _backfillStart = value;
    _reach = reach;
    notifyListeners();
  }

  Future<void> setLastLookedAt(DateTime value) async {
    await _store.write(kLastLookedAt, value.millisecondsSinceEpoch);
    _lastLookedAt = value;
    notifyListeners();
  }

  Future<void> setBackfillComplete(bool value) async {
    await _store.write(kBackfillComplete, value);
    _backfillComplete = value;
    notifyListeners();
  }

  Future<void> setChangeMark(ChangeMark? value) async {
    await _store.write(kChangeMark, value?.encode());
    _changeMark = value;
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

  /// With [ifNone], only a photo that has no verdict yet gets this one.
  Future<void> record(LedgerVerdict verdict, String localIdentifier, {bool ifNone = false}) =>
      _serialVerdicts(() async {
        if (ifNone && _verdicts.containsKey(localIdentifier)) return;
        final next = Map<String, LedgerVerdict>.of(_verdicts)
          ..[localIdentifier] = verdict;
        await _store.write(kVerdicts, encodeVerdicts(next));
        _verdicts = next;
        notifyListeners();
      });

  /// Verdict writes run one at a time, each on the map the last one left.
  /// Two at once (a pass recording one photo while an upload's result
  /// records another) each copied the same map, and the later write dropped
  /// the earlier verdict — a lost `waiting` is a photo no pass from a change
  /// token would offer again (5.40.0).
  Future<void> _verdictWrites = Future.value();

  Future<void> _serialVerdicts(Future<void> Function() write) {
    final done = _verdictWrites.then((_) => write());
    // A failed write fails its own caller, never the writes queued after it.
    _verdictWrites = done.catchError((Object _) {});
    return done;
  }

  /// An asset needs looking at unless a verdict that still stands was reached.
  /// A no-text verdict from an OLDER pre-filter is reconsidered, and a
  /// deferred or waiting one always is (Swift `needsExamination`).
  bool needsExamination(String localIdentifier, {required int prefilterVersion}) =>
      switch (_verdicts[localIdentifier]?.kind) {
        SweepVerdictKind.ingested || SweepVerdictKind.dismissed => false,
        SweepVerdictKind.noText =>
          _verdicts[localIdentifier]!.prefilterVersion! < prefilterVersion,
        SweepVerdictKind.deferredNotLocal || SweepVerdictKind.waiting || null => true,
      };

  /// The photos a pass from a change token reads although they did not
  /// change: deferred (they may be on the device now) and waiting (in a tray
  /// a relaunch forgot, or an upload that has not landed). Spec §7 rule 3.
  Set<String> get owedAnotherLook => {
        for (final e in _verdicts.entries)
          if (e.value.kind == SweepVerdictKind.deferredNotLocal ||
              e.value.kind == SweepVerdictKind.waiting)
            e.key,
      };

  int get ingestedCount =>
      _verdicts.values.where((v) => v.kind == SweepVerdictKind.ingested).length;
  int get deferredCount => _verdicts.values
      .where((v) => v.kind == SweepVerdictKind.deferredNotLocal)
      .length;

  /// "Passed over" (5.43.0, ADR-198): photos the pre-filter found no text in,
  /// and those the reader passed over in review.
  int get passedOverCount => _verdicts.values
      .where((v) =>
          v.kind == SweepVerdictKind.noText || v.kind == SweepVerdictKind.dismissed)
      .length;

  /// Forgets every verdict, the backfill's progress and the change mark, so
  /// the next pass walks the whole library; keeps the setup (enabled, mode,
  /// start date), as Swift's `reset()` did.
  Future<void> reset() => _serialVerdicts(() async {
        await _store.write(kVerdicts, null);
        await _store.write(kRetiredCursor, null);
        await _store.write(kChangeMark, null);
        await _store.write(kBackfillComplete, false);
        _verdicts = {};
        _changeMark = null;
        _backfillComplete = false;
        notifyListeners();
      });

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

/// The change token a finished pass left, and what that pass walked with
/// (spec §7 rule 4): it stands only for the same pre-filter version and the
/// same start date. Client-local, like the rest of the ledger.
@immutable
class ChangeMark {
  const ChangeMark({
    required this.token,
    required this.prefilterVersion,
    required this.backfillStartMs,
  });

  /// The platform's, opaque.
  final String token;
  final int prefilterVersion;
  final int backfillStartMs;

  bool standsFor({required int prefilterVersion, required DateTime backfillStart}) =>
      this.prefilterVersion == prefilterVersion &&
      backfillStartMs == backfillStart.millisecondsSinceEpoch;

  String encode() => jsonEncode({
        'token': token,
        'prefilterVersion': prefilterVersion,
        'backfillStartMs': backfillStartMs,
      });

  /// An unreadable mark costs a walk of the whole library, never a photo:
  /// it reads as none, and is said.
  static ChangeMark? decode(Object? raw) {
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw as String);
      if (m is Map &&
          m['token'] is String &&
          m['prefilterVersion'] is int &&
          m['backfillStartMs'] is int) {
        return ChangeMark(
          token: m['token'] as String,
          prefilterVersion: m['prefilterVersion'] as int,
          backfillStartMs: m['backfillStartMs'] as int,
        );
      }
    } catch (_) {}
    debugPrint('sweep ledger: the change mark is unreadable; the next pass '
        'walks the whole library');
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ChangeMark &&
      other.token == token &&
      other.prefilterVersion == prefilterVersion &&
      other.backfillStartMs == backfillStartMs;

  @override
  int get hashCode => Object.hash(token, prefilterVersion, backfillStartMs);
}

/// How far back the setup's look back reaches (5.43.0, ADR-198; sources.md
/// §Camera roll, setup step 3). Each is a start date when it is chosen: now,
/// a month ago, a year ago, or the oldest photo.
enum SweepReach {
  fromNow,
  month,
  year,
  everything;

  static SweepReach? fromStored(Object? raw) => switch (raw) {
        'fromNow' => fromNow,
        'month' => month,
        'year' => year,
        'everything' => everything,
        _ => null,
      };
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

enum SweepVerdictKind { ingested, dismissed, noText, deferredNotLocal, waiting }

/// One asset's standing verdict. **Never a boolean** (spec §2): with remote
/// fetch off the system hands back a low-resolution placeholder for an
/// iCloud-optimized photo, text recognition on it finds nothing, and a
/// boolean ledger would record a text-bearing photo as "no text" permanently.
/// So the ledger records WHY, and stamps the pre-filter version that decided.
///
/// Five states: the spec's three (ingested, no-text@version, deferred) plus
/// `dismissed`, the review tray's own "not this one", as in Swift — and
/// `waiting` (5.40.0, spec §2): a candidate found and not yet in or
/// dismissed. It decides nothing; it is what lets a pass that reads only what
/// changed find the photo again.
@immutable
class LedgerVerdict {
  const LedgerVerdict._(this.kind, [this.prefilterVersion]);

  const LedgerVerdict.noText(int prefilterVersion)
      : this._(SweepVerdictKind.noText, prefilterVersion);

  static const ingested = LedgerVerdict._(SweepVerdictKind.ingested);
  static const dismissed = LedgerVerdict._(SweepVerdictKind.dismissed);
  static const deferredNotLocal =
      LedgerVerdict._(SweepVerdictKind.deferredNotLocal);
  static const waiting = LedgerVerdict._(SweepVerdictKind.waiting);

  final SweepVerdictKind kind;

  /// Set exactly on [SweepVerdictKind.noText].
  final int? prefilterVersion;

  Map<String, Object?> toJson() => switch (kind) {
        SweepVerdictKind.noText => {
            'noText': {'prefilterVersion': prefilterVersion}
          },
        _ => {kind.name: <String, Object?>{}},
      };

  /// Closed: anything but one of the five shapes throws.
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
      case 'waiting' when value.isEmpty:
        return waiting;
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
