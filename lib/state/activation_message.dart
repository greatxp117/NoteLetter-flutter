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
    'Turning this on sends a letter now, unless one is already coming today.';

/// Renders the outcome from the response's `activationSend`, never from an
/// assumption about what the backend decided.
///
/// `reason` is an OPEN vocabulary: an unrecognised value must take the neutral
/// wording rather than be shown raw or treated as an error.
String? activationMessage(Map<String, dynamic>? response) {
  final send = response?['activationSend'];
  if (send is! Map) return null;

  if (send['queued'] == true) return 'Scheduled delivery is on — a letter is on its way now.';

  switch (send['reason']) {
    case 'scheduled_today':
      return "Scheduled delivery is on — today's letter is already on its way.";
    case 'already_sent_today':
      return "Scheduled delivery is on — today's letter has already been sent.";
    case 'empty_library':
      return 'Scheduled delivery is on. Your first letter arrives once you have '
          'added a source or two.';
    case 'enqueue_failed':
      // The save is never failed by the send, so this is informational.
      return 'Scheduled delivery is on. A letter could not be started just now; '
          'the next scheduled one is unaffected.';
    default:
      return 'Scheduled delivery is on. Nothing was sent just now.';
  }
}
