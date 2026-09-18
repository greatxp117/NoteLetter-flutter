/// The readings day view (F-33, ADR-029 §5, component-kit §14.1).
///
/// A reading that could not be searched answered NOTHING; it did not answer
/// zero. The reference shipped this screen mapping one rejection to an empty
/// result list with a `failed` flag that was true only when EVERY reading
/// failed — so one failed row drew §7's offer ("Nothing on your shelves
/// answers this reading yet"), an assertion about the library made from a
/// request that never completed, and its zero went into the live tally, so the
/// banner read the library as having SHRUNK since the letter was sent.
///
/// Both halves are asserted here, plus the two the reference's own text suite
/// could not see and a screenshot did: the form is **§14.1**, so the block
/// carries the server's `request_id` — which is what its 500 sentence tells
/// the reader to quote — and it carries §14.1's one action, which re-runs
/// **that one reading**.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/search_result.dart';
import 'package:flutter_app/pages/letters/scripture_day_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The server's own sentence and its own id. Neither is a constant this screen
/// writes; the id is the part every client parses and none rendered before
/// 4.33.0.
const _refused = 'An unexpected error occurred. Contact support with your '
    'request ID.';
const _reqId = 'req-7f3a91';
const _refusal = ApiException(500, _refused, requestId: _reqId);

const _isaiah = 'Isaiah 55:1-11';
const _psalm = 'Psalm 42';
const _john = 'John 6:1-15';

SearchResult _hit(String id, String text) => SearchResult(
      chunk: Chunk(
          chunkId: id,
          documentId: 'doc-1',
          chunkIndex: 0,
          text: text,
          sourceType: 'pdf'),
      document: const SearchResultDocument(
          userId: 'u1', title: 'Confessions', type: 'pdf', status: 'complete'),
      score: 0.8,
    );

Newsletter _day({int passagesFound = 3}) => Newsletter(
      id: 'nl-1',
      userId: 'u1',
      generatedAt: 1758000000000,
      kind: 'scripture',
      trigger: 'scheduled',
      status: 'sent',
      passagesFound: passagesFound,
      liturgicalDay: const LiturgicalDay(name: 'Friday of week 18'),
      readings: const [
        LetterReading(label: 'First reading', ref: _isaiah),
        LetterReading(label: 'Psalm', ref: _psalm),
        LetterReading(label: 'Gospel', ref: _john),
      ],
    );

/// Every `ref` this run will be asked, and what it answers. Recorded in order
/// so a retry can be shown to re-run ONE reading and not the day.
class _Answers {
  final Map<String, Object> byRef;
  final List<String> asked = [];
  _Answers(this.byRef);

  Future<List<SearchResult>> call(String ref) async {
    asked.add(ref);
    final a = byRef[ref];
    if (a is ApiException) throw a;
    return (a as List<SearchResult>?) ?? const [];
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Answers answers, {
  Newsletter? letter,
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(
      body: ScriptureDayView(
        letter: letter ?? _day(),
        onBack: () {},
        onLibrary: () {},
        search: answers.call,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The §7 offer — the thing the hole replaced.
final _offer = find.text('Nothing on your shelves answers this reading yet.');

String _bannerText(WidgetTester tester) {
  // The banner is the one place the counts are stated; read every Text under
  // it rather than matching a sentence this file wrote.
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((w) => w.data ?? '')
      .where((s) => s.contains('passages') || s.contains('count') ||
          s.contains('could not be searched') || s.contains('answered'));
  return texts.join(' ');
}

void main() {
  group('one reading that could not be searched', () {
    _Answers answers() => _Answers({
          _isaiah: [_hit('c1', 'Come to the waters.'), _hit('c2', 'Seek him.')],
          _psalm: _refusal,
          _john: [_hit('c3', 'Five barley loaves.')],
        });

    testWidgets('draws §14.1 with the server sentence AND its request id',
        (tester) async {
      await _pump(tester, answers());

      expect(find.byType(KitFailureBlock), findsOneWidget);
      final block = tester.widget<KitFailureBlock>(find.byType(KitFailureBlock));
      expect(block.sentence, 'This reading could not be searched.');
      // Verbatim — the screen does not write this sentence or summarise it.
      expect(block.detail, _refused);
      // The part §14.2 cannot draw, and the part this sentence asks for.
      expect(block.requestId, _reqId);
      expect(block.onRetry, isNotNull);
      // …and the offer is not also on the page.
      expect(_offer, findsNothing);
    });

    testWidgets('shows no count for the row it could not count',
        (tester) async {
      await _pump(tester, answers());
      expect(find.text('2 PASSAGES'), findsOneWidget);
      expect(find.text('1 PASSAGE'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
      // The reading did not answer zero.
      expect(find.text('0 PASSAGES'), findsNothing);
    });

    testWidgets('keeps the failed row out of the tally and claims no drift',
        (tester) async {
      // 3 sent; the two readings that answered give 3.
      await _pump(tester, answers());
      final banner = _bannerText(tester);
      expect(banner, contains('One reading could not be searched just now'));
      expect(banner, contains('the readings that did answer give 3'));
      // The false decline the zero used to produce.
      expect(banner, isNot(contains('now answers with')));
    });

    testWidgets('retries ONE reading, not the day', (tester) async {
      final a = answers();
      await _pump(tester, a);
      expect(a.asked, [_isaiah, _psalm, _john]);

      a.byRef[_psalm] = [_hit('c9', 'Why are you cast down, my soul?')];
      // The block sits below the 800×600 test viewport, and a tap at an
      // off-screen offset lands on whatever IS there — silently, with the
      // assertion after it then failing for the wrong reason.
      await tester.ensureVisible(find.text('Try again'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.byType(KitFailureBlock), findsNothing);
      // The two that answered were not asked again.
      expect(a.asked, [_isaiah, _psalm, _john, _psalm]);
      // The row rejoins the tally, so the day is comparable again: 2 + 1 + 1
      // against the 3 the letter counted — a drift claim the screen was
      // correctly refusing to make while the hole was there.
      expect(_bannerText(tester), contains('now answers with 4'));
    });
  });

  group('the control directions', () {
    testWidgets('a reading that genuinely found nothing still gets §7',
        (tester) async {
      // 2 live against 3 sent — a real decline, and one empty reading.
      await _pump(
        tester,
        _Answers({
          _isaiah: [_hit('c1', 'a')],
          _psalm: <SearchResult>[],
          _john: [_hit('c3', 'b')],
        }),
      );
      expect(find.byType(KitFailureBlock), findsNothing);
      expect(_offer, findsOneWidget);
      expect(find.text('0 PASSAGES'), findsOneWidget);
      expect(_bannerText(tester), contains('now answers with 2'));
    });

    testWidgets('every reading failing keeps its own sentence',
        (tester) async {
      await _pump(
        tester,
        _Answers({_isaiah: _refusal, _psalm: _refusal, _john: _refusal}),
      );
      expect(find.byType(KitFailureBlock), findsNWidgets(3));
      expect(_offer, findsNothing);
      expect(_bannerText(tester),
          contains('Your library could not be searched just now'));
    });

    testWidgets('a day where every reading answers exactly what was sent',
        (tester) async {
      await _pump(
        tester,
        _Answers({
          _isaiah: [_hit('c1', 'a')],
          _psalm: [_hit('c2', 'b')],
          _john: [_hit('c3', 'c')],
        }),
      );
      expect(_bannerText(tester),
          contains('the same number your letter counted'));
    });

    // Both themes: §14.1's ground and its critical text flip together, and a
    // half-flipped pair renders perfectly in the one it was written in.
    testWidgets('the failed row renders in dark too', (tester) async {
      await _pump(
        tester,
        _Answers({
          _isaiah: [_hit('c1', 'Come to the waters.')],
          _psalm: _refusal,
          _john: [_hit('c3', 'Five barley loaves.')],
        }),
        brightness: Brightness.dark,
      );
      expect(find.byType(KitFailureBlock), findsOneWidget);
      expect(_offer, findsNothing);
    });
  });
}
