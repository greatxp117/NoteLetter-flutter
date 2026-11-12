/// A shelf backfill's sentence counts what the model READ (5.92.0, ADR-117
/// addendum 1; screens/library.md §Backfill review, screens/review.md
/// §Proposals; web `shared/backfillSentence.js`, F-204).
///
/// Over 150 eligible sources the backend shows the model the 150 that lean
/// hardest toward the shelf and stores `asked` beside `scanned` (every
/// eligible source); "14 of your 494 sources look like they belong" claimed a
/// verdict on all 494. A result stored before 5.92.0 has no `asked` and read
/// at most 150, so it is read as min(scanned, 150). The words are the
/// backend's `_backfill_note` (area_tasks.py), byte for byte.
library;

import 'dart:math' as math;

import '../widgets/kit/kit_d_format.dart' show kitCounted;

/// The most sources one proposal shows the model (the backend's
/// `_BACKFILL_POOL_MAX`).
const int backfillPoolMax = 150;

/// `scanned` (every eligible source), `asked` (what the model read) and
/// `rest` (what it did not) from a stored `shelf_backfill` result.
({int scanned, int asked, int rest}) backfillCounts(
    Map<String, dynamic>? result) {
  final scanned = (result?['scanned'] as num?)?.toInt() ?? 0;
  final a = result?['asked'];
  final asked =
      a is num ? a.toInt() : math.min(scanned, backfillPoolMax);
  return (scanned: scanned, asked: asked, rest: math.max(0, scanned - asked));
}

/// *your other 1 source was not checked.* / *your other 344 sources were not
/// checked.*
String uncheckedTail(int rest) =>
    'your other ${kitCounted(rest, 'source')} '
    '${rest == 1 ? 'was' : 'were'} not checked.';

/// The sentence as one string (For your review's line): [n] candidates over
/// [result], on the shelf [title].
String backfillSentence(int n, Map<String, dynamic>? result, String title) {
  final c = backfillCounts(result);
  if (c.rest <= 0) {
    return n > 0
        ? '$n of your ${kitCounted(c.scanned, 'source')} look like they '
            'belong on $title.'
        : 'Nothing in your library looks like it belongs on $title yet.';
  }
  return n > 0
      ? '$n of the ${kitCounted(c.asked, 'source')} most like $title look '
          'like they belong on it; ${uncheckedTail(c.rest)}'
      : 'Nothing among the ${kitCounted(c.asked, 'source')} most like $title '
          'looks like it belongs on it yet; ${uncheckedTail(c.rest)}';
}
