import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_spacing.dart';

/// The reader's typography, its detailed-stats toggle and where the reader
/// stopped — web `pages/reader/readerPrefs.js`.
///
/// **Client-local and explicitly NOT contract state** (reader.md §Reading state
/// & typography, ADR-020): no Firestore field, no endpoint, no sync, and no
/// read event — where the viewport sits is continuous, per-device and
/// meaningless to anyone else. A position is never a `view_count`.
///
/// **One store, one writer.** Web learned this when its stats toggle put a
/// second `useState` on the same `localStorage` key and whichever moved last
/// clobbered the other's field; here every reader of these preferences
/// listens to [current], and only [set] writes.
@immutable
class ReaderPrefs {
  final String size;
  final String face;
  final String measure;

  /// The detailed breakdown under the stats (reader.md §Detailed reading
  /// stats) — off by default; it lives with the typography because it is the
  /// same kind of thing: a display choice, per device, never synced.
  final bool stats;

  const ReaderPrefs({
    this.size = 'md',
    this.face = 'serif',
    this.measure = 'normal',
    this.stats = false,
  });

  /// `TYPE_SIZES` — id, label, px. Medium is the pre-2.13.0 fixed value.
  static const sizes = [
    ('sm', 'Small', 17.0),
    ('md', 'Medium', 19.0),
    ('lg', 'Large', 21.0),
    ('xl', 'X-large', 24.0),
  ];

  /// `TYPE_FACES`.
  static const faces = [('serif', 'Serif'), ('sans', 'Sans')];

  /// `TYPE_MEASURES`, in `ch`: Narrow 54ch, Normal `--measure` (68ch), Wide
  /// 84ch. This client spells `--measure` as [AppSpacing.measure] points, so
  /// the other two scale from it.
  static const measures = [
    ('narrow', 'Narrow', 54.0),
    ('normal', 'Normal', 68.0),
    ('wide', 'Wide', 84.0),
  ];

  /// The reading size in points (`--ms-size`).
  double get px =>
      sizes.firstWhere((s) => s.$1 == size, orElse: () => sizes[1]).$3;

  /// `--ms-leading`: looser at small sizes, tighter at large — a constant
  /// multiplier reads cramped small and airy large.
  double get leading => px <= 17 ? 1.75 : (px >= 24 ? 1.55 : 1.68);

  bool get sans => face == 'sans';

  /// `--ms-measure` — the body's max width.
  double get measureWidth {
    final ch = measures
        .firstWhere((m) => m.$1 == measure, orElse: () => measures[1])
        .$3;
    return AppSpacing.measure * ch / 68;
  }

  ReaderPrefs copyWith(
          {String? size, String? face, String? measure, bool? stats}) =>
      ReaderPrefs(
        size: size ?? this.size,
        face: face ?? this.face,
        measure: measure ?? this.measure,
        stats: stats ?? this.stats,
      );

  Map<String, Object> toJson() =>
      {'size': size, 'face': face, 'measure': measure, 'stats': stats};

  /// An unknown or missing value falls back to the default, per field — as
  /// web's `read()` validates each against its table.
  static ReaderPrefs fromJson(Object? raw, {bool? legacyStats}) {
    final m = raw is Map ? raw : const {};
    String oneOf(Object? v, List<String> ids, String fallback) =>
        v is String && ids.contains(v) ? v : fallback;
    return ReaderPrefs(
      size: oneOf(m['size'], [for (final s in sizes) s.$1], 'md'),
      face: oneOf(m['face'], [for (final f in faces) f.$1], 'serif'),
      measure: oneOf(m['measure'], [for (final x in measures) x.$1], 'normal'),
      stats: m['stats'] is bool ? m['stats'] as bool : (legacyStats ?? false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderPrefs &&
      other.size == size &&
      other.face == face &&
      other.measure == measure &&
      other.stats == stats;

  @override
  int get hashCode => Object.hash(size, face, measure, stats);

  // ── The store ─────────────────────────────────────────────────────────────

  static const storeKey = 'nl-reader-prefs';

  /// Where the stats toggle lived before it joined the typography (F-74).
  /// Read once, as the default when the store has no `stats` of its own.
  static const legacyStatsKey = 'reader_detailed_stats';

  static final ValueNotifier<ReaderPrefs> current =
      ValueNotifier(const ReaderPrefs());

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= () async {
        try {
          final p = await SharedPreferences.getInstance();
          Object? raw;
          try {
            raw = jsonDecode(p.getString(storeKey) ?? '{}');
          } catch (_) {
            raw = null;
          }
          current.value =
              fromJson(raw, legacyStats: p.getBool(legacyStatsKey));
          final at = p.getString(posKey);
          if (at != null) {
            try {
              final m = jsonDecode(at);
              if (m is Map) _positions.addAll(m.cast<String, dynamic>());
            } catch (_) {}
          }
        } catch (_) {
          // No store (a test without the plugin mocked): the defaults stand.
        }
      }();

  /// Sets one field and persists the whole value. A preference write that
  /// fails is not a failure to show anyone — the choice still applies here.
  static Future<void> set(ReaderPrefs next) async {
    if (next == current.value) return;
    current.value = next;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(storeKey, jsonEncode(next.toJson()));
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTest() {
    _loading = null;
    current.value = const ReaderPrefs();
    _positions.clear();
    _flush?.cancel();
    _flush = null;
  }

  // ── Where the reader stopped ──────────────────────────────────────────────

  static const posKey = 'nl-reader-pos';

  /// Keep the last N documents, not an unbounded map.
  static const posMax = 60;

  /// Don't "resume" someone to where they already are.
  static const posMinResume = 0.04;

  /// Finished — start them at the top next time.
  static const posDone = 0.97;

  static final Map<String, dynamic> _positions = {};
  static Timer? _flush;

  /// The resume offer's fraction, or null when there is nothing to offer.
  static double? positionOf(String docId) {
    final at = (_positions[docId] as Map?)?['ratio'];
    return at is num && at > posMinResume && at < posDone
        ? at.toDouble()
        : null;
  }

  /// Records the fraction of the sheet scrolled. Kept in memory at once and
  /// written behind a short debounce: the reference writes on every frame,
  /// and a platform-channel write per scroll frame is not a convenience.
  static void savePosition(String docId, double ratio, {DateTime? at}) {
    if (docId.isEmpty || ratio.isNaN) return;
    _positions[docId] = {
      'ratio': ratio,
      'at': (at ?? DateTime.now()).millisecondsSinceEpoch,
    };
    if (_positions.length > posMax) {
      final keep = (_positions.entries.toList()
            ..sort((a, b) => ((b.value as Map)['at'] as int)
                .compareTo((a.value as Map)['at'] as int)))
          .take(posMax)
          .map((e) => e.key)
          .toSet();
      _positions.removeWhere((k, _) => !keep.contains(k));
    }
    _flush?.cancel();
    _flush = Timer(const Duration(milliseconds: 400), flushPositions);
  }

  static Future<void> flushPositions() async {
    _flush?.cancel();
    _flush = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(posKey, jsonEncode(_positions));
    } catch (_) {}
  }
}
