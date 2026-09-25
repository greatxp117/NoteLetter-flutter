import 'package:flutter_test/flutter_test.dart';

import 'token_match.dart';

/// The comparator contract of `fixtures/normalization.md`, over this client's
/// port (`token_match.dart`) — the same seven cases the reference pins in
/// `tests/contract/fixture-tokens.test.js` (QUEUE F-28).
///
/// 1. `«seconds»` — a rate-limit countdown is `int(window - elapsed)`, so the
///    number is a measurement of how long the capture took; the sentence
///    around it is asserted verbatim.
/// 2. An EMBEDDED token — `…?«sig»`, a gcs path carrying `«uuid#1»`, this
///    countdown — never reached a predicate here: the dispatch tested
///    `startsWith('«')`, so such a value fell through to string equality
///    against the token TEXT.
void main() {
  const uuid = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
  const other = '3f2504e0-4f89-11d3-9a0c-000000000000';
  void fails(void Function() f) => expect(f, throwsA(isA<TestFailure>()));

  group('«seconds» — the countdown is a token, the sentence is not', () {
    const expected = 'Please wait «seconds» seconds before regenerating again.';

    test('accepts any countdown the clock produces', () {
      for (final n in [0, 1, 58, 59, 60]) {
        match('Please wait $n seconds before regenerating again.', expected);
      }
    });

    test('still asserts the copy around it', () {
      fails(() => match('Please wait 59 seconds before retrying.', expected));
      fails(() => match(
          'Please wait 59 seconds before regenerating again!', expected));
    });

    test('is a number, not any word', () {
      fails(() => match(
          'Please wait a few seconds before regenerating again.', expected));
    });
  });

  group('an embedded token is matched, not compared as text', () {
    const path = 'https://s/raw/u1/pdfs/«uuid#1»_paper.pdf?«sig»';
    const actual =
        'https://s/raw/u1/pdfs/${uuid}_paper.pdf?X-Goog-Signature=deadbeef';

    test('matches a signed url whose path carries a uuid', () {
      match(actual, path);
    });

    test('fails when the literal part differs', () {
      fails(() => match(actual.replaceFirst('pdfs', 'slides'), path));
    });

    test('fails when the token span is not what the token means', () {
      fails(() => match(actual.replaceFirst(uuid, 'not-a-uuid'), path));
    });

    test('holds «uuid#N» identity across an embedded and a whole-value use',
        () {
      final uuids = <String, String>{};
      match(actual, path, r'$', uuids);
      match(uuid, '«uuid#1»', r'$', uuids);
      fails(() => match(other, '«uuid#1»', r'$', uuids));
    });
  });
}
