import '../models/ask_thread.dart';

/// The sent turn's retirement rule (ADR-097 §3, amended 4.67.0 by ADR-102).
///
/// A top-level predicate rather than a private method on `ChatNotifier`, for the
/// same reason web extracted `retires()`: the rule it encodes went wrong in
/// exactly the way an untested predicate does — correct about the case it was
/// written for, silently wrong about a case nobody had seen yet — and a rule
/// reachable only through a notifier is a rule no test asserts.
///
/// [asked] is how many copies of [question] the thread ALREADY held when the
/// turn was sent, so "its own message has arrived" means one MORE than that.
/// Counting is what makes asking the same question twice work: without it the
/// new turn clears against the old one's message, before its answer exists.
///
/// **A refusal is retired too, and only by a record.** A refusal is a claim that
/// nothing was stored; an arriving record disproves it, and the record is the
/// one that is true — clients do not write `ask_threads` (INV-04), so a stored
/// turn is one the endpoint committed. A platform deadline ends the RESPONSE and
/// not the handler: `fn_ask_turn` was 504'd at 60s on 2026-09-15 and stored the
/// turn 4m11s later, leaving the answered turn and a refused copy of the same
/// question on screen together (ADR-102).
///
/// The asymmetry is what makes that safe. A turn that genuinely failed wrote
/// nothing, so [stored] never passes [asked] and its §14.2 sentence stays put.
/// [error] is taken and deliberately NOT consulted. It is a parameter so that
/// the whole decision lives in one place a test can reach: the rule that a
/// refusal is retired like any other turn is only enforceable where the refusal
/// is visible, and a caller that filtered refusals out before calling would put
/// the rule back where no test can see it — which is how it was wrong.
bool retiresSentTurn({
  required String question,
  required int asked,
  required List<AskMessage> messages,
  String? error,
}) {
  var stored = 0;
  for (final m in messages) {
    if (m.role == AskRole.user && m.text == question) stored++;
  }
  return stored > asked;
}
