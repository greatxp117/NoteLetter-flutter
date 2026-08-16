import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/pages/settings/summary_prompt.dart';

/// Summary-style composition (4.4.0, spec/screens/settings.md §Simple controls).
///
/// The contract pins the round trip as mutation-grade: `parse(compose(x)) == x`
/// for **all 27 combinations**. It matters because the toggles hold no state of
/// their own — positions are recovered from the stored `summaryPrompt` by exact
/// match, so a single edited fragment makes the controls stop recognising their
/// own output, and the failure is silent: the section just renders as Custom.
void main() {
  group('summary style composition', () {
    test('round-trips all 27 combinations', () {
      var n = 0;
      for (final b in styleDimensions[0].options) {
        for (final l in styleDimensions[1].options) {
          for (final t in styleDimensions[2].options) {
            final choices = {'balance': b.id, 'length': l.id, 'tone': t.id};
            final composed = composePrompt(choices);
            final parsed = parsePrompt(composed);
            expect(parsed, isNotNull,
                reason: 'composed prompt must parse back: $composed');
            expect(parsed, equals(choices), reason: 'round trip for $choices');
            n++;
          }
        }
      }
      expect(n, 27);
    });

    test('all-defaults composes to a reset, never stored default text', () {
      // null is the reset. A stored COPY of the default text would stop
      // tracking the default if it ever moved.
      expect(composePrompt(defaultChoices), isNull);
    });

    test('the default instruction text parses as all-defaults', () {
      // So a prompt saved verbatim from the 4.3.0 textarea round-trips into the
      // toggles rather than presenting as hand-authored.
      expect(parsePrompt(defaultSummaryPrompt), equals(defaultChoices));
      expect(parsePrompt(null), equals(defaultChoices));
      expect(parsePrompt('   '), equals(defaultChoices));
    });

    test('a hand-authored prompt does not map to positions', () {
      // It must render as free text, never be lossily snapped to the nearest
      // combination.
      expect(parsePrompt('Summarise it like a pirate.'), isNull);
      // A near-miss is still a miss — exact match over the composition space.
      final composed = composePrompt(
          {'balance': 'mixed', 'length': 'brief', 'tone': 'scholarly'})!;
      expect(parsePrompt('$composed Also mention the weather.'), isNull);
      expect(parsePrompt(composed.replaceFirst('two to four', 'three')), isNull);
    });

    test('every dimension has exactly one default (null fragment) option', () {
      for (final d in styleDimensions) {
        expect(d.options.where((o) => o.fragment == null).length, 1,
            reason: '${d.id} must have exactly one default position');
      }
    });

    test('sendablePrompt refuses empty and over-long drafts', () {
      // The contract has no "empty prompt" state — the empty string is a 400,
      // and a reset is its own control sending null.
      expect(sendablePrompt(''), isNull);
      expect(sendablePrompt('   '), isNull);
      expect(sendablePrompt('a' * (summaryPromptMaxChars + 1)), isNull);
      expect(sendablePrompt('  keep it short  '), 'keep it short');
    });
  });
}
