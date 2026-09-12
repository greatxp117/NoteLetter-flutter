/// Study-program copy and pure logic (contract 2.34.0 ADR-033 · 4.7.0
/// ADR-043), mirroring the reference's `pages/study/schedule.js`.
///
/// The `state/schedule.dart` pattern: everything a screen would otherwise
/// inline lives here, so the rules that are easy to get wrong are testable
/// without a renderer — and the copy obligations (state what a switch will do
/// BEFORE it is touched, report the outcome from the response, never assume)
/// have one home.
library;

import '../models/study.dart';

/// Program status is **stored, not derived**, and the vocabulary is OPEN.
/// Anything this build does not recognise renders in the same neutral shell,
/// humanised — never as active, never as an error, and **never as the raw
/// token**.
String studyStatusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Active';
    case 'maintenance':
      return 'Maintenance';
    case 'complete':
      // A statement about TODAY, not a terminal state — more may fall due
      // tomorrow, so it must not read like an ending.
      return 'Complete';
    default:
      final s = status.replaceAll(RegExp(r'[_-]+'), ' ').trim();
      if (s.isEmpty) return 'Unknown';
      return s[0].toUpperCase() + s.substring(1);
  }
}

/// What turning a program ON does, said BEFORE the switch is touched
/// (ADR-031's copy obligation, applied per ADR-033 §6).
const studyActivationHint =
    'Turning this on sends the first session right away — unless one is '
    'already coming today — and then keeps to its schedule.';

/// The outcome, read from the response's `activationSend`, never assumed.
/// `reason` is an open vocabulary; anything unrecognised takes the neutral
/// wording. Null when the request did not turn the program on.
String? studyActivationMessage(Map<String, dynamic>? response) {
  final send = response?['activationSend'];
  if (send is! Map) return null;
  if (send['queued'] == true) {
    return 'The first session is on its way — it shows up here, and in your '
        'inbox, in a minute or two.';
  }
  switch (send['reason']) {
    case 'scheduled_today':
      return 'On. Today’s session was already scheduled for later today, so '
          'nothing extra was sent.';
    case 'already_sent_today':
      return 'On. A session for this program already went out today — the '
          'next one follows its schedule.';
    case 'empty_program':
      return 'On. This program’s documents hold nothing to study right now, '
          'so no session was sent.';
    default:
      return 'On. Nothing was sent just now; the next session follows its '
          'schedule.';
  }
}

const _cadence = {
  'daily': 'Daily',
  'weekdays': 'Weekdays',
  'weekly': 'Weekly',
};

/// One line describing the program's delivery, rendered from what was READ,
/// never assumed (the 2.29.0 rule).
String programScheduleSentence(StudyProgram p) {
  final when = _cadence[p.frequency] ?? 'Daily';
  final at = p.deliveryTime.isEmpty ? '07:00' : p.deliveryTime;
  final zone = p.timezone.split('/').last.replaceAll('_', ' ');
  final delivery = p.emailEnabled
      ? (p.emailAddress.isNotEmpty
          ? 'by email to ${p.emailAddress}'
          : 'by email')
      : 'in the app only';
  return '$when at $at${zone.isEmpty ? '' : ' · $zone'} · $delivery';
}

/// "back in 6 days", from the grade response's `item.due_at`. **The schedule's
/// own answer**, never computed from a grade here (INV-17). Null when there is
/// nothing to say.
String? returnLabel(int? dueAt, {DateTime? now}) {
  if (dueAt == null) return null;
  final from = now ?? DateTime.now();
  final days =
      (DateTime.fromMillisecondsSinceEpoch(dueAt).difference(from).inHours / 24)
          .round();
  if (days <= 0) return 'back later today';
  if (days == 1) return 'back tomorrow';
  return 'back in $days days';
}

/// The §12 Notice a program card carries when it is running low on material
/// (4.7.0, ADR-043) — or null, which is the answer far more often.
class RunwayNotice {
  /// The condition **and the figure it was measured from** — a notice states
  /// both or it is not this pattern.
  final String text;
  final String cta;

  /// `edit` opens the program's own settings (where the reading position is);
  /// `new` starts a new program, because `documentIds` is fixed once a program
  /// starts.
  final String action;

  const RunwayNotice(this.text, this.cta, this.action);
}

/// Below this many sessions of new material left, the card says so.
const runwayLow = 3;

/// Everything here is READ. Two rules this must not break:
///
///  1. **Never recompute the runway** — see [StudyProgram.materialRunway].
///  2. **Absent is not zero.** The field exists only once a program has built,
///     so defaulting it would put "no new material left" on every new program.
///
/// The reason vocabulary is open: an unrecognised value renders the generic
/// line and a neutral action, never an error.
RunwayNotice? runwayNotice(StudyProgram p) {
  final n = p.materialRunway;
  if (n == null || n >= runwayLow) return null;

  final left = n == 0
      ? 'No new material left'
      : n == 1
          ? 'About one more session of new material'
          : 'About $n more sessions of new material';

  switch (p.lowMaterialReason) {
    case 'awaiting_position':
      return RunwayNotice(
          '$left — the rest of your reading is waiting behind the position '
          'you set.',
          'Set your position',
          'edit');
    case 'exhausted':
      // NOT a failure and not `complete`: reviews continue on schedule, so the
      // copy must not imply the program stopped.
      return RunwayNotice(
          '$left. This program has worked through its sources; they are fixed '
          'once it starts, so more material means a new program.',
          'New program',
          'new');
    default:
      return RunwayNotice('$left.', 'Open settings', 'edit');
  }
}
