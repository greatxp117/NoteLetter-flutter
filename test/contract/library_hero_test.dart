/// Home's letter (library.md §The letter, ADR-131/132; direction D,
/// §Composition — the letter AS IT IS SENT, a paper card under its
/// letterhead). The record is the NEWEST BUILT daily letter (web
/// getLatestLetter): never a record still being built, never a readings
/// letter, `kind != 'scripture'` (never `== 'daily'`). It names its day — *This
/// morning* when built on the device's calendar day, the date otherwise — and
/// its count comes only from `chunk_ids` (ADR-109: no figure, never 0). A read
/// in flight says nothing; a refused read says so and never claims there is
/// no letter (INV-24). Web: `tests/contract/library-letter-hero.test.js`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/newsletter_notifier.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'home_harness.dart';

final _readings = homeLetter('r1', {
  'kind': 'scripture',
  'status': 'sent',
  'generated_at': 1758800000000,
});
final _generating = homeLetter('g1', {
  'kind': 'daily',
  'status': 'generating',
  'generated_at': 1758700000000,
});
final _legacy = homeLetter('l1', {
  // pre-2.24.0: no `kind` at all; pre-2.0.0: `html`, no `html_body`.
  'status': 'sent',
  'html': '<p>An old card list.</p>',
  'chunk_ids': ['c1', 'c2'],
  'generated_at': 1757500000000,
});
// Local morning on a fixed day, so the day named does not move with the
// machine's time zone.
final _sep22 = DateTime(2026, 9, 22, 9).millisecondsSinceEpoch;
const _subject = 'Your NoteLetter — The long view';
final _kindless = homeLetter('k1', {
  // No `kind` (pre-2.24.0), a body, no `chunk_ids`.
  'status': 'sent',
  'subject': _subject,
  'html_body': '<p>A plain body.</p>',
  'generated_at': _sep22,
});
final _earlier = homeLetter('e1', {
  'kind': 'daily',
  'status': 'sent',
  'subject': _subject,
  'chunk_ids': ['a', 'b', 'c'],
  'html_body': '<p>x</p>',
  'generated_at': _sep22,
});
Newsletter _today({List<String>? chunks, String status = 'sent'}) =>
    homeLetter('t1', {
      'kind': 'daily',
      'status': status,
      'subject': _subject,
      'chunk_ids': ?chunks,
      'html_body': '<p>Built.</p>',
      'generated_at': DateTime.now().millisecondsSinceEpoch,
    });

String _card(int n, String title, String body, String docId, String src) =>
    '<tr><td><div><div><span>&sect; 0$n</span></div><h2>$title</h2>'
    '<div><p>$body</p></div><div><a href="https://noteletter.com/reader/'
    '$docId?p=c$n">Read &ldquo;$src&rdquo; in context &rarr;</a></div></div>'
    '</td></tr>';

final _complete = [homeDoc('d1', title: 'A source', chunks: 4)];

Future<NewsletterNotifier> _load(List<Newsletter> all) async {
  FirestoreService.instance = HomeReads(letters: all);
  final n = NewsletterNotifier();
  await n.load();
  return n;
}

Future<void> _pump(
  WidgetTester tester,
  List<Newsletter> letters, {
  List<Document>? docs,
  bool fail = false,
  bool hang = false,
  NewsletterSettings? settings = const NewsletterSettings(enabled: false),
}) => pumpHome(
  tester,
  HomeReads(
    docs: docs ?? _complete,
    letters: letters,
    failLetters: fail,
    hangLetters: hang,
  ),
  settings: HomeSettings(settings),
);

String _stand(WidgetTester tester) {
  final m = tester.widget<KitMasthead>(find.byType(KitMasthead));
  return m.stand ?? '';
}

Finder _inCard(Finder f) =>
    find.descendant(of: find.byType(KitEditionLetter), matching: f);

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({'nl-onboard-dismissed': true});
    LocalFlags.resetForTest();
    LocalFlags.onboardDismissed.value = true;
  });
  tearDown(FirestoreService.resetInstance);

  group('the letter is the newest BUILT daily letter', () {
    test('never a record still being built, never a readings letter', () async {
      final n = await _load([_readings, _generating, _earlier]);
      expect(n.latest?.id, 'e1');
    });

    test(
      'a kindless record counts (`!= scripture`, never `== daily`)',
      () async {
        final n = await _load([_readings, _kindless]);
        expect(n.latest?.id, 'k1');
      },
    );

    test(
      'a pre-2.0.0 record (`html`, no `html_body`) is not a built letter',
      () async {
        final n = await _load([_readings, _legacy]);
        expect(n.latest, isNull);
      },
    );
  });

  group('Home’s letter, as it is sent', () {
    testWidgets('with no letter yet and a ready library: no false claim, no '
        'failure', (tester) async {
      await _pump(tester, const []);
      expect(
        _inCard(find.text('Your first letter is being written')),
        findsOneWidget,
      );
      expect(find.textContaining('could not be read'), findsNothing);
      expect(find.byType(KitFailureInline), findsNothing);
      // The library is READY (its source is complete): nothing is "being read".
      expect(_stand(tester), 'No letter has been built yet.');
    });

    testWidgets('no letter, the first sources still being read, delivery off: '
        'the being-read standfirst and no letter promised', (tester) async {
      await _pump(
        tester,
        const [],
        docs: [homeDoc('p', status: DocumentStatus.processing, chunks: null)],
      );
      expect(
        _inCard(find.text('Your first letter is being written')),
        findsOneWidget,
      );
      expect(_stand(tester), 'Your library is being read.');
      expect(find.textContaining('Tomorrow'), findsNothing);
      expect(
        _inCard(find.textContaining('Scheduled delivery is off')),
        findsOneWidget,
      );
    });

    testWidgets('the figures a letter carries, from chunk_ids', (tester) async {
      await _pump(tester, [
        _today(chunks: ['a', 'b', 'c']),
      ]);
      expect(_inCard(find.text('The long view')), findsOneWidget);
      expect(
        _inCard(find.textContaining('THREE PASSAGES · 4 MIN READ')),
        findsOneWidget,
      );
      expect(
        _stand(tester),
        'Today’s letter, “The long view,” is ready — three passages from your '
        'library.',
      );
    });

    testWidgets('no chunk_ids: no figure — not 0 (ADR-109)', (tester) async {
      await _pump(tester, [_today()]);
      expect(_inCard(find.text('The long view')), findsOneWidget);
      expect(_inCard(find.textContaining('PASSAGE')), findsNothing);
      expect(_inCard(find.textContaining('MIN READ')), findsNothing);
      expect(_stand(tester), 'Today’s letter, “The long view,” is ready.');
    });

    testWidgets('built today: This morning, one passage', (tester) async {
      await _pump(tester, [
        _today(chunks: ['a']),
      ]);
      expect(_inCard(find.textContaining('THIS MORNING')), findsOneWidget);
      expect(
        _stand(tester),
        'Today’s letter, “The long view,” is ready — one passage from your '
        'library.',
      );
    });

    testWidgets(
      'built earlier: the letterhead and the standfirst name the day',
      (tester) async {
        await _pump(tester, [_earlier]);
        expect(
          _inCard(find.textContaining('TUESDAY, SEPTEMBER 22')),
          findsOneWidget,
        );
        expect(
          _stand(tester),
          'Your latest letter, “The long view,” is from Tuesday, September 22 — '
          'three passages from your library.',
        );
        expect(find.textContaining('This morning'), findsNothing);
        expect(_inCard(find.textContaining('THIS MORNING')), findsNothing);
      },
    );

    testWidgets('an earlier letter with no chunk_ids drops the count clause', (
      tester,
    ) async {
      await _pump(tester, [_kindless]);
      expect(
        _stand(tester),
        'Your latest letter, “The long view,” is from Tuesday, September 22.',
      );
    });

    testWidgets('no Sent figure, for any status', (tester) async {
      await _pump(tester, [
        _today(chunks: ['a'], status: 'generating'),
      ]);
      expect(_inCard(find.text('The long view')), findsOneWidget);
      expect(_inCard(find.textContaining('Sent')), findsNothing);
      expect(_inCard(find.textContaining('SENT')), findsNothing);
    });

    testWidgets('a letterheaded letter’s passages, as text, each linked to '
        'its source', (tester) async {
      await _pump(tester, [
        homeLetter('h1', {
          'status': 'sent',
          'subject': _subject,
          'chunk_ids': ['a', 'b'],
          'generated_at': DateTime.now().millisecondsSinceEpoch,
          'text_body': 'NOTELETTER\nVol. I · No. 12 · Thursday · 2 passages',
          'html_body':
              '<div data-nl-letterhead="1"><p data-nl-lede="1">Two '
              'passages found each other today.</p><table>'
              '${_card(1, 'On attention', 'Attention is <b>the</b> rarest gift.', 'doc-1', 'Simone Weil')}'
              '${_card(2, 'Slow work', '<img src="x" onerror="alert(1)">Work slowly.', 'doc-2', 'A Notebook')}'
              '</table></div>',
        }),
      ]);
      expect(_inCard(find.textContaining('VOL. I · NO. 12')), findsOneWidget);
      expect(_inCard(find.text('On attention')), findsOneWidget);
      expect(_inCard(find.text('Slow work')), findsOneWidget);
      expect(
        _inCard(find.text('Two passages found each other today.')),
        findsOneWidget,
        reason: 'the lede is the marked note',
      );
      expect(find.textContaining('onerror'), findsNothing);
      expect(_inCard(find.text('Simone Weil')), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Simone Weil'),
          matching: find.byWidgetPredicate(
            (w) => w is KitSourceLink && w.docId == 'doc-1',
          ),
        ),
        findsOneWidget,
        reason: 'the source is a link to the reader (§6.4.3)',
      );
    });

    testWidgets('before the read answers: a skeleton, and the standfirst says '
        'nothing about the letter', (tester) async {
      await pumpHome(
        tester,
        HomeReads(docs: _complete, hangLetters: true),
        settings: HomeSettings(const NewsletterSettings(enabled: true)),
        preloadLetters: false,
      );
      expect(_inCard(find.byType(KitSkeletonLines)), findsOneWidget);
      expect(find.textContaining('Your library is being read'), findsNothing);
      expect(_stand(tester), isNot(contains('letter')));
    });

    testWidgets('a refused read says so, never "tomorrow\'s letter"', (
      tester,
    ) async {
      await _pump(tester, const [], fail: true);
      expect(_stand(tester), 'Your latest letter could not be read.');
      expect(
        _inCard(find.text('The letter could not be read')),
        findsOneWidget,
      );
      expect(_inCard(find.byType(KitFailureInline)), findsOneWidget);
      expect(find.textContaining('Tomorrow’s letter'), findsNothing);
      expect(_inCard(find.text('Go to Letters')), findsOneWidget);
    });

    testWidgets('the next letter while the schedule is measured on', (
      tester,
    ) async {
      await _pump(
        tester,
        [_earlier],
        settings: const NewsletterSettings(
          enabled: true,
          deliveryTime: '23:59',
          frequency: 'daily',
        ),
      );
      final next = kitNextAt('23:59')!;
      expect(
        _inCard(
          find.text('Next letter ${next[0].toLowerCase()}${next.substring(1)}'),
        ),
        findsOneWidget,
      );
      await _pump(tester, [_earlier], settings: null);
      expect(
        _inCard(find.text('Letter settings')),
        findsOneWidget,
        reason: 'an unread schedule claims no next letter',
      );
    });
  });
}
