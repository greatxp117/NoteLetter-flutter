/// The Plan row's words (4.79.0, ADR-113, INV-28 — screens/settings.md
/// §Plan row). The Flutter mirror of the reference's `src/shared/plan.js`,
/// word for word.
///
/// Every figure here is one `fn_plan_status` measured. This file never counts
/// documents, never reads a limit from anywhere else, and never rewrites a
/// server sentence — it only lays the endpoint's numbers into the row's
/// description and decides whether the §12 notice is showing. A null status
/// (not yet answered, or refused) draws the title `Plan` and NO figures:
/// unread is not zero (ADR-109).
library;

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// `period_end` is the first instant of the next UTC month — the reset. The
/// day is read in **UTC**: a local reading turns "1 October" into "30
/// September" for every reader west of Greenwich, and the endpoint's month is
/// a UTC one.
String? resetLabel(Object? periodEndMs) {
  if (periodEndMs is! num || !periodEndMs.toDouble().isFinite) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(periodEndMs.toInt(), isUtc: true);
  return '${d.day} ${_months[d.month - 1]}';
}

String _planLabel(Object? plan) => plan == 'paid' ? 'paid plan' : 'free plan';

/// What the row renders. [notice] is non-null only at a cap.
class PlanSummary {
  final String title;
  final String? description;
  final String? notice;
  const PlanSummary(this.title, this.description, this.notice);
}

PlanSummary planSummary(Map<String, dynamic>? status) {
  final limits = status?['limits'];
  final usage = status?['usage'];
  if (status == null || limits is! Map || usage is! Map) {
    return const PlanSummary('Plan', null, null);
  }
  final plan = status['plan'];
  final title = plan == 'paid' ? 'Paid plan' : 'Free plan';
  final parts = <String>[];
  final docCap = limits['max_documents'];
  final monthCap = limits['max_ingests_per_month'];
  final reset = resetLabel(usage['period_end']);

  parts.add(docCap == null
      ? 'Unlimited sources'
      : '${usage['documents']} of $docCap sources');
  if (monthCap != null) {
    parts.add('${usage['ingests_this_month']} of $monthCap added this month');
    if (reset != null) parts.add('resets $reset');
  }
  if (limits['audio_narration'] == true) parts.add('Listen included');

  // At a cap — the condition the backend measured, and the figure it was
  // measured from. One action, in the row (Ask about upgrading → support).
  String? notice;
  final docs = usage['documents'];
  final ingests = usage['ingests_this_month'];
  if (docCap is num && docs is num && docs >= docCap) {
    notice = "Your library is at the ${_planLabel(plan)}'s $docCap sources — "
        'new sources are held until one is removed.';
  } else if (monthCap is num && ingests is num && ingests >= monthCap) {
    notice = "You've added the ${_planLabel(plan)}'s $monthCap sources this "
        'month — new sources are held${reset != null ? ' until $reset.' : '.'}';
  }
  return PlanSummary(title, parts.join(' · '), notice);
}
