/// Copy for the newsletter activation send (contract 2.30.0, ADR-031).
///
/// Turning scheduled delivery ON enqueues a letter immediately, unless one is
/// already coming today or there would be nothing to say. Before 2.30.0 the
/// first independent evidence that scheduling worked was up to a day away — a
/// WEEK on `weekly` — and everything visible before then was the client
/// reporting its own state back to itself.
///
/// The BACKEND owns the decision. A client must not call `requestNewsletter()`
/// to reproduce it: deciding whether a letter is already coming today is window
/// arithmetic in the reader's own timezone, and four client copies of it is four
/// chances to double-mail someone with nothing failing.
library;

/// Shown BEFORE the switch is touched. Unannounced mail seconds after a
/// settings change reads as a bug, so the reader is told first.
const activationHint =
    'Turning this on sends a letter right away — unless one already went out '
    'today, or one is due later today — and then keeps to your schedule.';

/// Renders the outcome from the response's `activationSend`, never from an
/// assumption about what the backend decided.
///
/// `reason` is an OPEN vocabulary: an unrecognised value must take the neutral
/// wording rather than be shown raw or treated as an error.
String? activationMessage(Map<String, dynamic>? response) {
  final send = response?['activationSend'];
  if (send is! Map) return null;

  if (send['queued'] == true) {
    // Same rule as the manual send: this screen may promise what it can see
    // (the letter arriving on the live subscription) and not what it cannot
    // (a receiver's inbox). INV-23.
    return 'A letter is on its way — it shows up here in a few minutes. The '
        'email leaves with it; the letter’s row shows what happened to it.';
  }

  switch (send['reason']) {
    case 'scheduled_today':
      return 'Scheduled. Today’s letter is already due later today, so nothing '
          'was sent now.';
    case 'already_sent_today':
      return 'Scheduled. Today’s letter has already gone out — the next one '
          'follows your schedule.';
    case 'empty_library':
      return 'Scheduled. There is nothing to put in a letter yet — add a '
          'source, and the next one follows your schedule.';
    default:
      return 'Scheduled. Nothing was sent just now; the next letter follows '
          'your schedule.';
  }
}
