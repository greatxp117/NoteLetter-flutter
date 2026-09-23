// The Plan row's words are the endpoint's figures and nothing else (4.79.0,
// ADR-113, INV-28; screens/settings.md §Plan row). The helper is EXECUTED over
// the captured `fn_plan_status` fixtures, so a client that started counting its
// own documents, or drew zeros for an unanswered status, fails here. The
// reference's twin is `tests/contract/plan-row.test.js` — same cases, same
// expected strings, because the words are the contract's and not each client's.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/shared/plan.dart';

import 'fixtures.dart';

void main() {
  final suite = loadSuite('api/plans');
  final byId = <String, Map<String, dynamic>>{
    for (final c in ((suite?['cases'] as List?) ?? const [])
        .cast<Map<String, dynamic>>())
      c['id'] as String: c,
  };

  Map<String, dynamic> bodyOf(String id) =>
      (byId[id]!['response'] as Map)['body'] as Map<String, dynamic>;

  group('Plan row (INV-28)', () {
    test('the suite is captured', () => expect(suite, isNotNull));

    test('an unanswered status draws the title and NO figures — unread is not zero', () {
      for (final s in <Map<String, dynamic>?>[null, {'plan': 'free'}]) {
        final r = planSummary(s);
        expect(r.title, 'Plan');
        expect(r.description, isNull);
        expect(r.notice, isNull);
      }
    });

    test('a free account under its caps: measured figures, the reset, no notice', () {
      final s = planSummary(bodyOf('plans:status-free-empty'));
      expect(s.title, 'Free plan');
      expect(s.description, '0 of 2 sources · 0 of 40 added this month · resets 1 October');
      expect(s.notice, isNull);
    });

    test('at the library cap: the §12 notice names the plan and the figure', () {
      final s = planSummary(bodyOf('plans:status-free-at-cap'));
      expect(s.description, '2 of 2 sources · 2 of 40 added this month · resets 1 October');
      expect(s.notice,
          "Your library is at the free plan's 2 sources — new sources are held until one is removed.");
    });

    test('at the month cap: the notice names the reset the endpoint reported', () {
      final base = bodyOf('plans:status-free-at-cap');
      final s = planSummary({
        ...base,
        'limits': {
          ...(base['limits'] as Map).cast<String, dynamic>(),
          'max_documents': 10,
          'max_ingests_per_month': 2,
        },
      });
      expect(s.notice,
          "You've added the free plan's 2 sources this month — new sources are held until 1 October.");
    });

    test('a paid account: unlimited reads as words, Listen is named, no notice', () {
      final s = planSummary(bodyOf('plans:status-paid'));
      expect(s.title, 'Paid plan');
      expect(s.description, 'Unlimited sources · Listen included');
      expect(s.notice, isNull);
    });

    test('the reset is the UTC day of period_end, never a local one', () {
      expect(resetLabel(1790812800000), '1 October');
      expect(resetLabel(null), isNull);
    });

    test('the refusal envelope reaches the client as PLAN_LIMIT, with the sentence intact', () {
      for (final id in ['passage:over-cap-403', 'upload:over-cap-403', 'audio:free-403']) {
        final res = byId[id]!['response'] as Map;
        expect(res['status'], 403);
        expect((res['body'] as Map)['error_code'], 'PLAN_LIMIT');
        expect(((res['body'] as Map)['error'] as String).length, greaterThan(20));
      }
    });
  });
}
