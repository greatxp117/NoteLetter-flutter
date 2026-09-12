/// Letter badges — one table, both letters (contract 4.24.0, ADR-061).
///
/// `status` is the BUILD outcome and `delivery` is what happened to the mail
/// afterwards (4.22.0, ADR-059, INV-23) — two axes, so delivery is read FIRST
/// when it has something to say. **`status: 'sent'` means the mail provider
/// accepted the message and never that it arrived**; nothing here may say
/// "Delivered" on the strength of it. An absent `delivery` map means unknown,
/// not failed — every record written before 4.22.0 has none — so it falls
/// through silently.
///
/// One table rather than two, for the reason the `docKind()`/`KIND_ORDER` pair
/// is a trap: two tables of one vocabulary with nothing comparing them, where
/// the copy that goes stale is invisible because each renders perfectly alone.
library;

/// Whether the badge reads as settled (a neutral, positive-chip pill) or as
/// something still open. It is deliberately NOT a severity: `Not delivered` and
/// `Sending…` share it, because both are "this is not finished".
class LetterBadge {
  final String text;
  final bool settled;
  const LetterBadge(this.text, {this.settled = true});
}

/// The `delivery.state` half of the table.
const deliveryBadges = <String, LetterBadge>{
  'bounced': LetterBadge('Not delivered', settled: false),
  'dropped': LetterBadge('Not delivered', settled: false),
  'spam': LetterBadge('Marked as spam', settled: false),
  'deferred': LetterBadge('Still sending…', settled: false),
  'delivered': LetterBadge('Delivered'),
};

/// How the letter was sent, and what became of it.
///
/// `empty` (2.2.0, ADR-011) is informational, not a failure: a "Send now" that
/// found nothing new. It takes the settled pill, distinct from `error`.
LetterBadge letterBadge({
  required String status,
  String? deliveryState,
  String trigger = 'scheduled',
}) {
  if (status == 'error') return const LetterBadge('Failed', settled: false);
  if (status == 'empty') return const LetterBadge('Nothing new');
  if (status == 'generating') {
    return const LetterBadge('Sending…', settled: false);
  }
  // 4.24.0, ADR-061 — the two-surface case. The letter is complete and
  // readable; only the mail did not go, so this is not 'Failed'.
  if (status == 'email_failed') {
    return const LetterBadge('Email failed', settled: false);
  }
  final d = deliveryBadges[deliveryState];
  if (d != null) return d;
  if (trigger == 'manual') return const LetterBadge('Sent on request');
  return const LetterBadge('Scheduled');
}

/// The provider's own sentence about a delivery that went wrong — the SMTP
/// refusal or the suppression cause. Returned only for the states a reader can
/// act on: a delivered or still-unknown letter needs no explanation.
String? deliveryNote({
  String? state,
  String? detail,
  int attempts = 0,
}) {
  if (state == 'deferred') {
    final n = attempts > 0 ? ' ($attempts attempts so far)' : '';
    return 'The receiving mail server is asking us to slow down$n. It is '
        'still being retried.';
  }
  if (state == 'bounced' || state == 'dropped' || state == 'spam') {
    return (detail != null && detail.isNotEmpty)
        ? detail
        : 'The receiving mail server refused this message.';
  }
  return null;
}
