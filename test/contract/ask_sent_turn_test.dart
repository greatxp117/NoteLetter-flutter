import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/ask_thread.dart';
import 'package:flutter_app/state/sent_turn.dart';

/// ADR-097 §3 as amended by ADR-102 — when a sent turn leaves the screen.
///
/// The rule shipped with the right answer for the case it was written for and
/// no answer at all for the case that happened: `fn_ask_turn` 504'd at 60s on
/// 2026-09-15, the handler kept running, and the turn was stored 4m11s later.
/// The transcript then held the answered turn AND a refused copy of the same
/// question offering to ask again. Nothing was red; there was no test, on this
/// client or on the reference.
void main() {
  AskMessage user(String text) =>
      AskMessage(id: 'u-$text', role: AskRole.user, text: text);
  AskMessage library() =>
      const AskMessage(id: 'l', role: AskRole.library, text: null);

  bool retires(String q, int asked, List<AskMessage> messages,
          {String? error}) =>
      retiresSentTurn(
          question: q, asked: asked, messages: messages, error: error);

  group('a sent turn retires on its own stored message', () {
    test('stays while nothing has been stored', () {
      expect(retires('are there more options?', 0, const []), isFalse);
    });

    test('retires when its stored message arrives', () {
      expect(
        retires('are there more options?', 0,
            [user('are there more options?'), library()]),
        isTrue,
      );
    });

    test('KEEPS a refusal that stored nothing — ADR-097 §3', () {
      // A turn that genuinely failed wrote no document, so the §14.2 sentence
      // and the retry stay. This is the half the amendment must not break.
      expect(
        retires('what did I read about grace?', 0, const [],
            error: 'Ask failed. Contact support with your request ID.'),
        isFalse,
      );
    });

    test('RETIRES a refusal whose record arrives anyway — ADR-102', () {
      // The 504 case. The deadline ended the response, not the handler; the
      // endpoint is the record (INV-04) and it committed this turn.
      expect(
        retires('are there more options?', 0,
            [user('are there more options?'), library()],
            error: 'Ask failed. Contact support with your request ID.'),
        isTrue,
      );
    });

    test('does not retire against an EARLIER copy of the same question', () {
      expect(retires('more?', 1, [user('more?'), library()]), isFalse);
      expect(
        retires('more?', 1,
            [user('more?'), library(), user('more?'), library()]),
        isTrue,
      );
    });

    test('ignores a library message carrying the same text', () {
      expect(
        retires('grace', 0,
            [const AskMessage(id: 'l', role: AskRole.library, text: 'grace')]),
        isFalse,
      );
    });
  });
}
