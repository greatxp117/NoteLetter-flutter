import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';
import 'token_match.dart';

/// The comparator contract of `fixtures/normalization.md`, over this client's
/// port (`token_match.dart`) — the cases the reference pins in
/// `tests/contract/fixture-tokens.test.js` (QUEUE F-28).
///
/// 1. `«seconds»` — a rate-limit countdown is `ceil(window - elapsed)`
///    (`int()` until 4.107.0), so the number is a measurement of how long the
///    capture took; the sentence around it is asserted verbatim.
/// 3. `«retry_after_s»` (4.107.0, ADR-140) — the same measurement as a WHOLE
///    value: `retry_after_s` on a cooldown envelope, an integer of at least
///    one second, never a string of digits.
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

  group('«retry_after_s» — a cooldown’s wait is a whole value, and a number',
      () {
    test('accepts any whole second the clock produces', () {
      for (final n in [1, 42, 300]) {
        match(n, '«retry_after_s»');
      }
    });

    test('refuses zero, a fraction and a string of digits', () {
      fails(() => match(0, '«retry_after_s»'));
      fails(() => match(-3, '«retry_after_s»'));
      fails(() => match(4.5, '«retry_after_s»'));
      fails(() => match('42', '«retry_after_s»'));
      fails(() => match(null, '«retry_after_s»'));
    });

    test('is asserted inside the envelope like any key', () {
      const expected = {
        'error': 'Please wait «seconds» seconds before retrying.',
        'error_code': 'RATE_LIMITED',
        'request_id': '«request_id»',
        'retry_after_s': '«retry_after_s»',
      };
      match({
        'error': 'Please wait 43 seconds before retrying.',
        'error_code': 'RATE_LIMITED',
        'request_id': 'a1b2c3d4',
        'retry_after_s': 43,
      }, expected);
      // The key set compares in full: an envelope that lost the number fails.
      fails(() => match({
            'error': 'Please wait 43 seconds before retrying.',
            'error_code': 'RATE_LIMITED',
            'request_id': 'a1b2c3d4',
          }, expected));
    });

    test('every captured cooldown envelope satisfies it', () {
      // The token is not only a unit here: every captured case carrying it
      // must be one this predicate was written for (a key named
      // `retry_after_s`, never a token embedded in a string).
      final root = contractsRoot();
      final manifest = jsonDecode(
              File('$root/fixtures/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
      var seen = 0;
      for (final suite in (manifest['suites'] as List).cast<Map>()) {
        if (suite['status'] != 'captured') continue;
        final text =
            File('$root/fixtures/${suite['path']}').readAsStringSync();
        if (!text.contains('«retry_after_s»')) continue;
        for (final c in ((jsonDecode(text) as Map)['cases'] as List).cast<Map>()) {
          final body = (c['response'] as Map?)?['body'];
          if (body is! Map || !body.containsKey('retry_after_s')) continue;
          expect(body['retry_after_s'], '«retry_after_s»',
              reason: '${c['id']}: a captured wait is tokenized whole');
          seen++;
        }
      }
      // 4.107.0 moved exactly five captured cooldown cases (CHANGELOG).
      expect(seen, greaterThanOrEqualTo(5),
          reason: 'read $seen cooldown case(s) — a gate that reads nothing '
              'agrees with everything (4.34.7)');
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
