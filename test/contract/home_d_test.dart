/// Home in direction D (F-141; screens/library.md §Composition, web
/// `pages/LibraryHome.jsx`). The library's state, read once from the
/// documents read, chooses the standfirst, the letter's text, the Contents
/// and the lower sections — and `loading` / `failed` are not states of the
/// library at all: they draw the dash and the skeleton or §14.2 and claim
/// nothing (INV-24). The desk ledger shows only measured numbers: the review
/// count is the shell's one inbox (INV-30), unmeasured is the dash, and the
/// quiet sentence needs every read behind it to have answered with nothing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'home_harness.dart';

List<String> _contents(WidgetTester tester) => [
  for (final i in tester.widget<KitContents>(find.byType(KitContents)).items)
    i.label,
];

String _folio(WidgetTester tester) =>
    tester.widget<KitMasthead>(find.byType(KitMasthead)).folio;

String? _stand(WidgetTester tester) =>
    tester.widget<KitMasthead>(find.byType(KitMasthead)).stand;

const _quiet = 'Nothing is waiting on you. The library is quiet.';

final _shelves = [
  const Tag(id: 's1', userId: 'u1', title: 'Cooking', color: 'brick-500'),
];

StudySession _session(String status) => StudySession.fromJson('ss', {
  'status': status,
  'program_title': 'Greek',
  'items': [
    {
      'questions': [
        {'qid': 'a'},
        {'qid': 'b'},
      ],
    },
  ],
  'responses': {},
});

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({'nl-onboard-dismissed': true});
    LocalFlags.resetForTest();
    LocalFlags.onboardDismissed.value = true;
    LocalFlags.sourceView.value = 'list';
  });
  tearDown(FirestoreService.resetInstance);

  group('the state table', () {
    testWidgets('empty: the empty sentence, first sources, the letter waiting', (
      tester,
    ) async {
      await pumpHome(tester, HomeReads(), inbox: homeInbox());
      expect(_folio(tester), endsWith(' · 0 sources · 0 passages'));
      expect(
        _stand(tester),
        'Your library is empty for now. Bring in what you’ve read, and '
        'NoteLetter makes it searchable and starts writing you a daily letter '
        'from it.',
      );
      expect(_contents(tester), ['Your first sources', 'The letter']);
      expect(find.byType(KitFirstSources), findsOneWidget);
      expect(
        find.text('Your first letter is waiting on your library'),
        findsOneWidget,
      );
      expect(find.byType(KitRecentlyAdded), findsNothing);
      expect(find.text('The shelves'), findsNothing);
      expect(find.byType(KitHomeLower), findsNothing);
    });

    testWidgets('reading: being read, reading rows, the letter being written', (
      tester,
    ) async {
      await pumpHome(
        tester,
        HomeReads(
          docs: [
            homeDoc(
              'q',
              title: 'Arriving',
              status: DocumentStatus.queued,
              chunks: null,
            ),
          ],
        ),
        inbox: homeInbox(),
      );
      expect(_folio(tester), endsWith(' · 0 sources · 0 passages'));
      expect(
        _stand(tester),
        'Your library is being read. Tomorrow’s letter will draw from '
        'what’s indexed so far.',
      );
      expect(_contents(tester), [
        'The letter',
        'Recently added',
        'The shelves',
      ]);
      expect(find.text('Your first letter is being written'), findsOneWidget);
      expect(find.text('ONE BEING READ'), findsOneWidget);
      expect(find.byType(KitFirstSources), findsNothing);
      // The desk: one volume being read, with its stage.
      expect(find.text('volume being read'), findsOneWidget);
      expect(find.text('Queued'), findsWidgets);
      expect(find.text(_quiet), findsNothing);
    });

    // A reading row in a column 760 or narrower is web's `auto` stage track
    // beside the title: its first cut threw (a Flexible in an unbounded
    // cell), so a phone drew no Recently added while nothing had finished.
    testWidgets('reading, on a phone: the reading row draws', (tester) async {
      await pumpHome(
        tester,
        HomeReads(
          docs: [
            homeDoc(
              'q',
              title: 'Arriving',
              status: DocumentStatus.queued,
              chunks: null,
            ),
          ],
        ),
        inbox: homeInbox(),
        size: const Size(402, 2400),
      );
      expect(tester.takeException(), isNull);
      final row = find.byType(KitRegisterRow);
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('QUEUED')),
        findsOneWidget,
      );
      expect(tester.getSize(row).width, lessThanOrEqualTo(402));
    });

    testWidgets('ready: figures, letter + desk sentences, Earlier letters', (
      tester,
    ) async {
      final at = DateTime(2026, 9, 22, 9).millisecondsSinceEpoch;
      await pumpHome(
        tester,
        HomeReads(
          docs: [
            homeDoc('a', tags: const ['s1'], chunks: 1200),
            homeDoc('b', chunks: null),
          ],
          tags: _shelves,
          sessions: [_session('sent')],
          letters: [
            homeLetter('l1', {
              'status': 'sent',
              'subject': 'Your NoteLetter — The long view',
              'chunk_ids': ['a'],
              'html_body': '<p>x</p>',
              'generated_at': at,
            }),
            // Not the one shown, sent: listed.
            homeLetter('l0', {
              'status': 'sent',
              'subject': 'Your NoteLetter — Slow work',
              'text_body': 'Vol. I · No. 2',
              'html_body': '<p>x</p>',
              'generated_at': at - 86400000,
            }),
            // A readings letter and an unsent one: never listed.
            homeLetter('r', {
              'kind': 'scripture',
              'status': 'sent',
              'subject': 'Readings',
              'generated_at': at - 2 * 86400000,
            }),
            homeLetter('x', {
              'status': 'error',
              'subject': 'Your NoteLetter — Failed',
              'generated_at': at - 3 * 86400000,
            }),
          ],
        ),
        inbox: homeInbox(
          sources: [homeDoc('e', status: DocumentStatus.error, chunks: null)],
        ),
      );
      expect(_folio(tester), endsWith(' · 2 sources · 1,200 passages'));
      expect(
        _stand(tester),
        'Your latest letter, “The long view,” is from Tuesday, September 22 — '
        'one passage from your library. Two questions wait in Deep study, and '
        'one thing is set aside for your review.',
      );
      expect(_contents(tester), [
        'The letter',
        'Recently added',
        'Earlier letters',
        'The shelves',
      ]);
      expect(find.text('2 VOLUMES'), findsOneWidget);
      expect(find.text('1 SHELF'), findsOneWidget);
      expect(find.text('Slow work'), findsOneWidget);
      expect(find.text('Readings'), findsNothing);
      expect(find.text('Failed'), findsNothing);
      // The ledger: study, then review, each a measured row.
      expect(find.text('questions waiting'), findsOneWidget);
      expect(find.text('Deep study · Greek'), findsOneWidget);
      expect(find.text('set aside for your review'), findsOneWidget);
      expect(find.text('1 source couldn’t be read'), findsOneWidget);
      expect(find.text(_quiet), findsNothing);
    });

    testWidgets('failed: the dash, §14.2, never the empty state', (
      tester,
    ) async {
      await pumpHome(tester, HomeReads(failTags: true), inbox: homeInbox());
      expect(_folio(tester), endsWith(' · — sources · — passages'));
      expect(find.byType(KitFirstSources), findsNothing);
      expect(
        find.textContaining('Your library could not be read — '),
        findsNWidgets(2),
      );
      expect(find.textContaining('No shelves yet'), findsNothing);
      expect(find.textContaining('Nothing has finished'), findsNothing);
      expect(
        find.text('No letter has been built yet'),
        findsOneWidget,
        reason: 'with the library refused it says only that',
      );
      expect(
        find.text(_quiet),
        findsNothing,
        reason: 'a refused read is not "nothing waiting"',
      );
    });

    testWidgets('loading: the dash and the skeleton, claiming nothing', (
      tester,
    ) async {
      await pumpHome(
        tester,
        HomeReads(docsStream: const Stream.empty()),
        inbox: homeInbox(),
      );
      expect(_folio(tester), endsWith(' · — sources · — passages'));
      expect(find.byType(KitFirstSources), findsNothing);
      expect(find.byType(KitSkeletonLines), findsNWidgets(2));
      expect(find.textContaining('VOLUME'), findsNothing);
      expect(find.text(_quiet), findsNothing);
    });
  });

  group('the desk ledger', () {
    testWidgets('quiet only when every read answered with nothing', (
      tester,
    ) async {
      final ready = [homeDoc('a')];
      await pumpHome(tester, HomeReads(docs: ready), inbox: homeInbox());
      expect(find.text(_quiet), findsOneWidget);
      // No inbox in the shell: the count is unmeasured, so not quiet.
      await pumpHome(tester, HomeReads(docs: ready));
      expect(find.text(_quiet), findsNothing);
      // The study read still out: not quiet.
      await pumpHome(
        tester,
        HomeReads(docs: ready, sessions: null),
        inbox: homeInbox(),
      );
      expect(find.text(_quiet), findsNothing);
    });

    testWidgets('an unmeasured review count is the dash, Could not be '
        'counted — and the standfirst says nothing of it', (tester) async {
      await pumpHome(
        tester,
        HomeReads(docs: [homeDoc('a')]),
        inbox: homeInbox(fail: true),
      );
      expect(find.text('Could not be counted'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('ledger-review')),
          matching: find.text('—'),
        ),
        findsOneWidget,
      );
      expect(_stand(tester), isNot(contains('review')));
      expect(find.text(_quiet), findsNothing);
    });

    testWidgets('an undelivered session asks nothing', (tester) async {
      await pumpHome(
        tester,
        HomeReads(docs: [homeDoc('a')], sessions: [_session('generating')]),
        inbox: homeInbox(),
      );
      expect(find.text('questions waiting'), findsNothing);
      expect(find.text(_quiet), findsOneWidget);
    });
  });

  group('on a phone (402 × 874)', () {
    for (final b in Brightness.values) {
      testWidgets('ready, ${b.name}: the running head carries the sheet', (
        tester,
      ) async {
        await pumpHome(
          tester,
          HomeReads(
            docs: [
              homeDoc('a', tags: const ['s1']),
            ],
            tags: _shelves,
          ),
          settings: HomeSettings(
            const NewsletterSettings(enabled: true, deliveryTime: '08:00'),
          ),
          inbox: homeInbox(),
          size: const Size(402, 874),
          brightness: b,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(KitRunningHead), findsOneWidget);
        expect(find.byType(KitSheetCard), findsNothing);
        expect(find.byType(KitEditionLetter), findsOneWidget);
        // The page's tools go to the chrome at this width.
        expect(KitPageTools.instance.action?.short, 'Add');
        expect(find.byType(KitActionButton), findsNothing);
      });
    }

    testWidgets('empty, dark: no exception', (tester) async {
      await pumpHome(
        tester,
        HomeReads(),
        inbox: homeInbox(),
        size: const Size(402, 874),
        brightness: Brightness.dark,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(KitFirstSources), findsOneWidget);
    });
  });
}
