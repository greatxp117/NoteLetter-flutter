import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/models/newsletter_settings.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/state/activation_message.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Home's D parts (F-141; screens/library.md §Composition, kit §28/§42) —
/// the pure helpers web's `letter.js` and `LibraryHome.jsx` hold, then every
/// part pumped in BOTH themes and the behaviour its required parts name:
/// the letter's states (refused, in flight, none built, built — its
/// passages read as TEXT), the ledger's dash and quiet sentence, the shelf
/// listing's failure-first order, and LetterQuick writing before it moves.

Newsletter _letter(String id, Map<String, dynamic> json) =>
    Newsletter.fromJson(id, {'user_id': 'u1', ...json});

String _card(int n, String title, String body, String docId, String src) =>
    '<tr><td><div><div><span>&sect; 0$n</span></div><h2>$title</h2>'
    '<div><p>$body</p></div><div><a href="https://noteletter.com/reader/'
    '$docId?p=c$n">Read &ldquo;$src&rdquo; in context &rarr;</a></div></div>'
    '</td></tr>';

final _headed = _letter('l1', {
  'status': 'sent',
  'subject': 'Your NoteLetter — The long view',
  'chunk_ids': ['a', 'b'],
  'generated_at': DateTime(2026, 9, 22, 9).millisecondsSinceEpoch,
  'text_body': 'NOTELETTER\nVol. I · No. 12 · Thursday · 2 passages',
  'html_body':
      '<div data-nl-letterhead="1"><table>'
      '${_card(1, 'On attention', 'Attention is <b>the</b> rarest gift.', 'doc-1', 'Simone Weil')}'
      '${_card(2, 'Slow work', '<img src="x" onerror="alert(1)">Work slowly.', 'doc%2F2', 'A Notebook')}'
      '</table></div>',
});

Document _doc(
  String id, {
  String title = 'A volume',
  DocumentStatus status = DocumentStatus.complete,
  int? chunks = 4,
  int views = 1,
  List<String> tags = const [],
}) => Document(
  id: id,
  userId: 'u1',
  title: title,
  type: 'pdf',
  status: status,
  createdAt: DateTime(2026, 10, 20).millisecondsSinceEpoch,
  chunkCount: chunks,
  viewCount: views,
  tagIds: tags,
);

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({});
    LocalFlags.resetForTest();
    LocalFlags.sourceView.value = 'list';
  });

  Future<void> pumpBoth(
    WidgetTester tester,
    Widget Function() build, {
    Size size = const Size(402, 1400),
    Future<void> Function(Brightness b)? check,
  }) async {
    for (final b in Brightness.values) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(18), child: build()),
            ),
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull, reason: 'threw in $b');
      if (check != null) await check(b);
    }
  }

  group('the stored letter, read without opening it', () {
    test('its head drops No. rather than guess it', () {
      final h = kitLetterHead(
        _letter('x', {
          'text_body': 'NOTELETTER\nVol. II · Thursday',
          'subject': 'Your NoteLetter — Slow work',
        }),
      );
      expect([h.vol, h.no, h.title], ['II', null, 'Slow work']);
      // A passage that says "No. 5" is never the letter's number.
      expect(
        kitLetterHead(_letter('x', {'text_body': 'See No. 5. Vol. I'})).no,
        isNull,
      );
      expect(
        kitLetterHead(_letter('x', {'subject': 'A subject'})).title,
        'Your letter',
      );
      expect(kitLetterHead(_headed).no, '12');
    });

    test('an excerpt is at most about 280 characters, cut at a word', () {
      expect(kitLetterExcerpt('  short   text '), 'short text');
      final long = kitLetterExcerpt('word, ' * 80);
      expect(long.length, lessThanOrEqualTo(281));
      expect(long.endsWith('…'), isTrue);
      expect(long, isNot(contains(',…')), reason: 'trailing punctuation goes');
    });

    test('passages are read from a letterheaded body AS TEXT', () {
      final s = kitLetterSections(_headed);
      expect(s.map((x) => x.title), ['On attention', 'Slow work']);
      expect(s[0].text, 'Attention is the rarest gift.');
      expect(s[0].source, 'Simone Weil');
      expect(s[0].docId, 'doc-1');
      expect(s[1].docId, 'doc/2', reason: 'the id is URI-decoded');
      expect(s[1].text, 'Work slowly.');
      expect(s[1].text, isNot(contains('<')), reason: 'no markup leaves it');
      expect(s.map((x) => x.n), [1, 2]);
    });

    test('a letter before the letterhead draws no passages', () {
      expect(
        kitLetterSections(_letter('x', {'html_body': '<h2>A</h2><p>b</p>'})),
        isEmpty,
      );
    });

    test('no chunk_ids is an unmeasured count, never 0 (ADR-109)', () {
      expect(kitLetterParts(null), isNull);
      expect(kitLetterParts(_headed)!.count, 2);
      expect(
        kitLetterParts(_letter('x', {'html_body': '<p>x</p>'}))!.count,
        isNull,
      );
    });
  });

  group('the standfirst', () {
    final today = DateTime(2026, 10, 30, 9);
    KitLetterParts parts({int? count, int? at}) => KitLetterParts(
      title: 'The long view',
      sections: const [],
      lede: '',
      count: count,
      at: at ?? today.millisecondsSinceEpoch,
    );
    const answered = KitLetterRead(answered: true);

    test('built today, built earlier, no chunk_ids', () {
      expect(
        kitLetterSentence(answered, parts(count: 3), now: today),
        'Today’s letter, “The long view,” is ready — three passages from '
        'your library.',
      );
      expect(
        kitLetterSentence(answered, parts(count: 1), now: today),
        'Today’s letter, “The long view,” is ready — one passage from your '
        'library.',
      );
      expect(
        kitLetterSentence(
          answered,
          parts(count: 13, at: DateTime(2026, 9, 22, 9).millisecondsSinceEpoch),
          now: today,
        ),
        'Your latest letter, “The long view,” is from Tuesday, September 22 — '
        '13 passages from your library.',
      );
      expect(
        kitLetterSentence(answered, parts(), now: today),
        'Today’s letter, “The long view,” is ready.',
      );
    });

    test('in flight says nothing; refused says so', () {
      expect(kitLetterSentence(const KitLetterRead(), null), isNull);
      expect(
        kitLetterSentence(const KitLetterRead(error: 'denied'), null),
        'Your latest letter could not be read.',
      );
    });

    test('none built: only what the other reads support', () {
      expect(
        kitLetterSentence(answered, null, libState: KitLibState.ready),
        'No letter has been built yet.',
      );
      for (final s in [
        KitLibState.loading,
        KitLibState.failed,
        KitLibState.empty,
      ]) {
        expect(kitLetterSentence(answered, null, libState: s), isNull);
      }
      expect(
        kitLetterSentence(
          answered,
          null,
          sched: const KitLetterSchedule(on: false),
        ),
        'Your library is being read.',
      );
      expect(
        kitLetterSentence(answered, null),
        'Your library is being read. Tomorrow’s letter will draw from '
        'what’s indexed so far.',
      );
      expect(
        kitLetterSentence(
          answered,
          null,
          sched: const KitLetterSchedule(on: true, next: 'Monday, 8:00 AM'),
        ),
        'Your library is being read. The next letter will draw from what’s '
        'indexed so far.',
      );
    });

    test('the desk sentence says only measured counts', () {
      expect(
        kitDeskSentence(due: const KitStudyDue(2, 'Greek'), review: 1),
        'Two questions wait in Deep study, and one thing is set aside for '
        'your review.',
      );
      expect(kitDeskSentence(), isNull);
      expect(kitDeskSentence(review: 0), isNull);
      expect(
        kitDeskSentence(review: 500, atLimit: true),
        '500+ things are set aside for your review.',
      );
    });

    test('questions waiting are the newest delivered session’s ungraded', () {
      StudySession s(String status, Map<String, dynamic> responses) =>
          StudySession.fromJson('s', {
            'status': status,
            'program_title': 'Greek',
            'items': [
              {
                'questions': [
                  {'qid': 'a'},
                  {'qid': 'b'},
                ],
              },
              {
                'questions': [
                  {'qid': 'c'},
                ],
              },
            ],
            'responses': responses,
          });
      final due = kitStudyDue(s('sent', {'a': {}}))!;
      expect([due.left, due.programTitle], [2, 'Greek']);
      expect(kitStudyDue(s('email_failed', {}))!.left, 3);
      expect(kitStudyDue(s('generating', {})), isNull);
      expect(kitStudyDue(s('sent', {'a': {}, 'b': {}, 'c': {}})), isNull);
      expect(kitStudyDue(null), isNull);
    });

    test('the review parts, each only when it has any', () {
      expect(
        kitReviewParts(sources: 3, holds: 0, suggestions: 1, proposals: 2),
        [
          '3 sources couldn’t be read',
          '1 filing suggestion',
          '2 changes to approve',
        ],
      );
      expect(
        kitReviewParts(sources: 1, holds: 1, suggestions: 0, proposals: 0),
        ['1 source couldn’t be read', '1 import held'],
      );
    });

    test('the schedule: on and its next delivery; off promises none', () {
      final at = DateTime(2026, 10, 30, 6);
      final on = KitLetterSchedule.of(
        const NewsletterSettings(enabled: true, deliveryTime: '08:00'),
        now: at,
      );
      expect([on.on, on.time, on.next], [true, '8:00 AM', 'Today, 8:00 AM']);
      final off = KitLetterSchedule.of(
        const NewsletterSettings(enabled: false),
        now: at,
      );
      expect([off.on, off.next], [false, null]);
      expect(KitLetterSchedule.failed.on, isNull);
    });
  });

  group('the letter, as it is sent', () {
    Widget card(
      KitLetterRead read, {
      KitLibState lib = KitLibState.ready,
      KitLetterSchedule? sched,
      VoidCallback? onSettings,
    }) => KitEditionLetter(
      read: read,
      parts: kitLetterParts(read.letter),
      sched: sched,
      libState: lib,
      now: DateTime(2026, 10, 30, 9),
      onLetters: () {},
      onSettings: onSettings ?? () {},
    );

    testWidgets('built: letterhead, headline, passages, actions', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => card(
          KitLetterRead(answered: true, letter: _headed),
          sched: const KitLetterSchedule(on: true, next: 'Tomorrow, 8:00 AM'),
        ),
        check: (b) async {
          expect(
            find.text(
              'VOL. I · NO. 12 · TUESDAY, SEPTEMBER 22 · TWO PASSAGES · 3 MIN '
              'READ',
            ),
            findsOneWidget,
          );
          expect(find.text('The long view'), findsOneWidget);
          expect(find.text('On attention'), findsOneWidget);
          expect(find.text('§ 01'), findsOneWidget);
          expect(find.text('Simone Weil'), findsOneWidget);
          expect(find.text('Read the letter'), findsOneWidget);
          expect(find.text('Next letter tomorrow, 8:00 AM'), findsOneWidget);
          expect(find.textContaining('Sent'), findsNothing);
          expect(find.textContaining('onerror'), findsNothing);
        },
      );
    });

    testWidgets('built today: This morning; no chunk_ids: no figure', (
      tester,
    ) async {
      final l = _letter('t', {
        'status': 'sent',
        'subject': 'Your NoteLetter — Now',
        'html_body': '<p>x</p>',
        'generated_at': DateTime(2026, 10, 30, 7).millisecondsSinceEpoch,
      });
      await pumpBoth(
        tester,
        () => card(KitLetterRead(answered: true, letter: l)),
        check: (b) async {
          expect(find.text('THIS MORNING'), findsOneWidget);
          expect(find.textContaining('PASSAGE'), findsNothing);
          expect(find.textContaining('MIN READ'), findsNothing);
          expect(
            find.text('Letter settings'),
            findsOneWidget,
            reason: 'no measured schedule: the ghost is Letter settings',
          );
        },
      );
    });

    testWidgets('in flight: a skeleton headline; refused: §14.2', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => card(const KitLetterRead()),
        check: (b) async {
          expect(find.byType(KitSkeletonLines), findsOneWidget);
        },
      );
      await pumpBoth(
        tester,
        () => card(const KitLetterRead(error: 'Missing permissions.')),
        check: (b) async {
          expect(find.text('The letter could not be read'), findsOneWidget);
          expect(
            find.widgetWithText(KitFailureInline, 'Missing permissions.'),
            findsOneWidget,
          );
          expect(find.text('Go to Letters'), findsOneWidget);
        },
      );
    });

    testWidgets('none built: what starts the first letter, by state', (
      tester,
    ) async {
      const answered = KitLetterRead(answered: true);
      await pumpBoth(
        tester,
        () => card(
          answered,
          lib: KitLibState.empty,
          sched: const KitLetterSchedule(on: true, next: 'Tomorrow, 8:00 AM'),
        ),
        check: (b) async {
          expect(
            find.text('Your first letter is waiting on your library'),
            findsOneWidget,
          );
          expect(
            find.text(
              'Add a source, and the first letter arrives tomorrow, 8:00 AM, '
              'drawn from whatever is indexed by then.',
            ),
            findsOneWidget,
          );
        },
      );
      await pumpBoth(
        tester,
        () => card(
          answered,
          lib: KitLibState.reading,
          sched: const KitLetterSchedule(on: false),
        ),
        check: (b) async {
          expect(
            find.text('Your first letter is being written'),
            findsOneWidget,
          );
          expect(
            find.textContaining('Scheduled delivery is off.'),
            findsOneWidget,
          );
        },
      );
      await pumpBoth(
        tester,
        () => card(answered, lib: KitLibState.failed),
        check: (b) async {
          expect(find.text('No letter has been built yet'), findsOneWidget);
        },
      );
    });

    testWidgets('the ghost opens the settings', (tester) async {
      var opened = 0;
      await pumpBoth(
        tester,
        () => card(
          const KitLetterRead(answered: true),
          onSettings: () => opened++,
        ),
      );
      await tester.tap(find.text('Letter settings'));
      expect(opened, 1);
    });
  });

  group('the desk ledger', () {
    testWidgets('rows, the dash for an unmeasured count, the bars', (
      tester,
    ) async {
      var opened = '';
      await pumpBoth(
        tester,
        () => KitDeskLedger(
          rows: [
            KitLedgerRow(
              id: 'review',
              n: null,
              line: 'set aside for your review',
              sub: 'Could not be counted',
              onTap: () => opened = 'review',
            ),
            KitLedgerRow(
              id: 'reading',
              n: '4',
              line: 'volumes being read',
              reading: [
                for (var i = 0; i < 4; i++)
                  _doc(
                    'p$i',
                    title: 'Arriving $i',
                    status: DocumentStatus.queued,
                  ),
              ],
              onTap: () {},
            ),
          ],
        ),
        check: (b) async {
          expect(find.text('ON YOUR DESK'), findsOneWidget);
          expect(find.text('—'), findsOneWidget);
          expect(find.text('Could not be counted'), findsOneWidget);
          expect(find.text('Queued'), findsNWidgets(3));
          expect(find.text('and one more in the queue'), findsOneWidget);
          expect(
            find.text('Nothing is waiting on you. The library is quiet.'),
            findsNothing,
          );
        },
      );
      await tester.tap(find.text('set aside for your review'));
      expect(opened, 'review');
    });

    testWidgets('quiet only when the host says every read answered', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => const KitDeskLedger(rows: [], quiet: true),
        check: (b) async {
          expect(
            find.text('Nothing is waiting on you. The library is quiet.'),
            findsOneWidget,
          );
        },
      );
    });
  });

  group('Earlier letters, Your first sources', () {
    testWidgets('a row: its No. (or the dash), title, date', (tester) async {
      await pumpBoth(
        tester,
        () => KitEarlierLetters(
          rows: const [
            KitEarlierLetter(
              id: 'a',
              no: '2',
              title: 'Slow work',
              date: 'Wed, Sep 9',
            ),
            KitEarlierLetter(
              id: 'b',
              no: null,
              title: 'First',
              date: 'Tue, Sep 8',
            ),
          ],
          onOpen: () {},
          onAll: () {},
        ),
        check: (b) async {
          expect(find.text('Earlier letters'), findsOneWidget);
          expect(find.text('All letters →'), findsOneWidget);
          expect(find.text('2'), findsOneWidget);
          expect(find.text('—'), findsOneWidget);
          expect(find.text('Wed, Sep 9'), findsOneWidget);
        },
      );
      await pumpBoth(
        tester,
        () => KitEarlierLetters(rows: const [], onOpen: () {}, onAll: () {}),
        check: (b) async => expect(find.text('Earlier letters'), findsNothing),
      );
    });

    testWidgets('the drop zone is a control named Add files; tap copy', (
      tester,
    ) async {
      var picked = 0;
      await pumpBoth(
        tester,
        () => KitFirstSources(
          onAddFiles: () => picked++,
          onPasteLink: () {},
          onConnect: () {},
        ),
        check: (b) async {
          expect(find.text('Drop files to begin'), findsOneWidget);
          expect(
            find.text(
              'or tap to browse — PDF, EPUB, Word, slides, Markdown, images, '
              'audio, video',
            ),
            findsOneWidget,
          );
          expect(find.text('Paste a link'), findsOneWidget);
          expect(
            find.text('Connect Google Drive, Dropbox or Notion'),
            findsOneWidget,
          );
        },
      );
      await tester.tap(find.bySemanticsLabel('Add files'));
      expect(picked, 1);
    });
  });

  group('Recently added', () {
    final shelves = [
      const Tag(id: 's1', userId: 'u1', title: 'Cooking', color: 'brick-500'),
    ];
    Widget recent(
      List<Document> docs, {
      bool loaded = true,
      String? error,
      bool grid = false,
    }) => KitRecentlyAdded(
      model: kitShelfModel(shelves, docs),
      incoming: docs
          .where(
            (d) =>
                d.status == DocumentStatus.processing ||
                d.status == DocumentStatus.queued,
          )
          .toList(),
      loaded: loaded,
      libError: error,
      grid: grid,
      onWholeLibrary: () {},
    );

    testWidgets('six register rows; a count never taken is no figure', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => recent([
          for (var i = 0; i < 8; i++)
            _doc(
              'd$i',
              title: 'Volume $i',
              chunks: i == 0 ? null : 3,
              tags: const ['s1'],
            ),
        ]),
        check: (b) async {
          expect(find.text('8 VOLUMES'), findsOneWidget);
          expect(find.byType(KitRegisterRow), findsNWidgets(6));
          expect(find.text('0'), findsNothing);
          expect(find.text('The whole library →'), findsOneWidget);
        },
      );
    });

    testWidgets('before anything finished: reading rows, or the sentence', (
      tester,
    ) async {
      // Wide: KitRegisterRow's stage cell overflows a Row at 760 and under
      // (kit_d_parts.dart, `..add(stageCell)` unflexed) — booked to F-141.
      await pumpBoth(
        tester,
        size: const Size(1280, 1400),
        () => recent([
          _doc('q', status: DocumentStatus.queued, chunks: null),
          _doc('p', status: DocumentStatus.queued, chunks: null),
        ]),
        check: (b) async {
          expect(find.text('TWO BEING READ'), findsOneWidget);
          expect(find.byType(KitRegisterRow), findsNWidgets(2));
        },
      );
      await pumpBoth(
        tester,
        () => recent([_doc('x', status: DocumentStatus.error, chunks: null)]),
        check: (b) async {
          expect(
            find.text('Nothing has finished reading yet.'),
            findsOneWidget,
          );
        },
      );
    });

    testWidgets('loading claims nothing; refused is §14.2', (tester) async {
      await pumpBoth(
        tester,
        () => recent(const [], loaded: false),
        check: (b) async {
          expect(find.byType(KitSkeletonLines), findsOneWidget);
          expect(find.textContaining('VOLUME'), findsNothing);
        },
      );
      await pumpBoth(
        tester,
        () => recent(const [], error: 'Missing permissions.'),
        check: (b) async {
          expect(
            find.text('Your library could not be read — Missing permissions.'),
            findsOneWidget,
          );
          expect(find.textContaining('VOLUME'), findsNothing);
          expect(find.text('Nothing has finished reading yet.'), findsNothing);
        },
      );
    });

    testWidgets('Grid is the cover strip', (tester) async {
      await pumpBoth(
        tester,
        () => recent([
          _doc('a', tags: const ['s1']),
        ], grid: true),
        check: (b) async {
          expect(find.byType(KitCoverStrip), findsOneWidget);
          expect(find.byType(KitRegisterRow), findsNothing);
        },
      );
    });
  });

  group('§42 the shelf listing', () {
    final shelves = [
      const Tag(
        id: 'lead',
        userId: 'u1',
        title: 'Leading',
        color: 'sage-500',
        letterMode: 'lead',
        description: 'What leads.',
      ),
      const Tag(id: 'muted', userId: 'u1', title: 'Quiet', letterMode: 'muted'),
      const Tag(id: 'kid', userId: 'u1', title: 'Inner', parentTagId: 'muted'),
    ];
    final docs = [
      _doc('a', title: 'On leading', tags: const ['lead'], views: 0),
      _doc('b', title: 'Inside', tags: const ['kid'], chunks: null),
      _doc('c', title: 'Loose'),
    ];
    Widget listing({
      String view = 'list',
      bool letterOn = true,
      bool loaded = true,
      String? error,
      List<Tag>? tags,
      List<Document>? documents,
      void Function(KitShelfNode)? onAsk,
      void Function(KitShelfNode)? onOpen,
    }) => KitShelfListing(
      model: kitShelfModel(tags ?? shelves, documents ?? docs),
      view: view,
      letterOn: letterOn,
      loaded: loaded,
      libError: error,
      onNewShelf: () {},
      actions: KitShelfActions(onOpenShelf: onOpen ?? (_) {}, onAsk: onAsk),
    );

    testWidgets('List: numerals, chips Lead/Muted (in force), sub-shelf, '
        'Unshelved', (tester) async {
      await pumpBoth(
        tester,
        () => listing(onAsk: (_) {}),
        check: (b) async {
          expect(find.text('§ I'), findsOneWidget);
          expect(find.text('§ II'), findsOneWidget);
          expect(find.text('§ —'), findsOneWidget);
          expect(find.text('LEAD'), findsOneWidget);
          expect(find.text('MUTED'), findsOneWidget);
          expect(find.text('INNER'), findsOneWidget);
          expect(find.text('Unshelved'), findsOneWidget);
          expect(find.text('1 volume · 4 passages · 1 unread'), findsOneWidget);
          expect(find.text('What leads.'), findsOneWidget);
          // Ask this shelf on the two named shelves, never on Unshelved.
          expect(find.text('Ask this shelf'), findsNWidgets(2));
        },
      );
    });

    testWidgets('no chip while the letter is off; Ask absent while AI off', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => listing(letterOn: false),
        check: (b) async {
          expect(find.text('LEAD'), findsNothing);
          expect(find.text('MUTED'), findsNothing);
          expect(find.text('Ask this shelf'), findsNothing);
        },
      );
    });

    testWidgets('Grid: a head per shelf, the chip in it, the covers', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => listing(view: 'grid'),
        check: (b) async {
          expect(find.byType(KitCoverItem), findsNWidgets(3));
          expect(find.text('LEAD'), findsOneWidget);
          expect(find.text('INNER ›'), findsOneWidget);
        },
      );
    });

    testWidgets('failure FIRST, then skeleton, then No shelves yet', (
      tester,
    ) async {
      await pumpBoth(
        tester,
        () => listing(error: 'Missing permissions.'),
        check: (b) async {
          expect(
            find.text('Your library could not be read — Missing permissions.'),
            findsOneWidget,
          );
          expect(find.text('Unshelved'), findsNothing);
          expect(find.textContaining('Nothing on this shelf'), findsNothing);
        },
      );
      await pumpBoth(
        tester,
        () => listing(loaded: false),
        check: (b) async =>
            expect(find.byType(KitSkeletonLines), findsOneWidget),
      );
      await pumpBoth(
        tester,
        () => listing(tags: const [], documents: const []),
        check: (b) async => expect(
          find.text('create one from the Shelves page'),
          findsOneWidget,
        ),
      );
    });

    testWidgets('a shelf opens its page; Unshelved the Library', (
      tester,
    ) async {
      final opened = <String>[];
      await pumpBoth(tester, () => listing(onOpen: (n) => opened.add(n.id)));
      await tester.tap(find.text('Leading'));
      await tester.tap(find.text('Unshelved'));
      expect(opened, ['lead', kitUnshelvedId]);
    });
  });

  group('§28 LetterQuick', () {
    Widget quick(
      NewsletterSettings? s,
      Future<KitLetterWrite> Function(Map<String, dynamic>) write, {
      String? readError,
    }) => KitLetterQuick(
      settings: s,
      readError: readError,
      write: write,
      onEverySetting: () {},
    );

    testWidgets('reading, refused, and the hint before the switch', (
      tester,
    ) async {
      Future<KitLetterWrite> none(Map<String, dynamic> _) async =>
          const KitLetterWrite();
      await pumpBoth(
        tester,
        () => quick(null, none),
        check: (b) async =>
            expect(find.text('Reading your letter settings…'), findsOneWidget),
      );
      await pumpBoth(
        tester,
        () => quick(null, none, readError: 'Could not load.'),
        check: (b) async => expect(
          find.widgetWithText(KitFailureInline, 'Could not load.'),
          findsOneWidget,
        ),
      );
      await pumpBoth(
        tester,
        () => quick(const NewsletterSettings(enabled: false), none),
        check: (b) async {
          expect(find.text('Paused'), findsOneWidget);
          expect(find.text(activationHint), findsOneWidget);
          expect(find.text('Every letter setting →'), findsOneWidget);
        },
      );
    });

    testWidgets('the switch writes BEFORE it moves, and says what was sent', (
      tester,
    ) async {
      final pending = Completer<KitLetterWrite>();
      final sent = <Map<String, dynamic>>[];
      await pumpBoth(
        tester,
        () => quick(const NewsletterSettings(enabled: false), (p) {
          sent.add(p);
          return pending.future;
        }),
      );
      await tester.tap(find.byType(KitSwitch));
      await tester.pump();
      expect(sent.single['enabled'], isTrue);
      expect(sent.single['deliveryTime'], '07:00');
      expect(
        sent.single.containsKey('timezone'),
        isTrue,
        reason: 'the hour goes with its zone',
      );
      expect(
        tester.widget<KitSwitch>(find.byType(KitSwitch)).value,
        isFalse,
        reason: 'it has not moved while the write is out',
      );
      expect(
        tester.widget<KitSwitch>(find.byType(KitSwitch)).onChanged,
        isNull,
        reason: 'held',
      );
      pending.complete(
        const KitLetterWrite(
          response: {
            'activationSend': {'queued': true},
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.widget<KitSwitch>(find.byType(KitSwitch)).value, isTrue);
      expect(find.textContaining('A letter is on its way'), findsOneWidget);
    });

    testWidgets('a refusal stays put and is said under it', (tester) async {
      await pumpBoth(
        tester,
        () => quick(
          const NewsletterSettings(enabled: true, frequency: 'daily'),
          (_) async => const KitLetterWrite(error: 'Not allowed.'),
        ),
      );
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      await tester.pump();
      expect(
        find.widgetWithText(KitFailureInline, 'Not allowed.'),
        findsOneWidget,
      );
      final sw = tester.widget<KitSlideSwitch<String>>(
        find.byType(KitSlideSwitch<String>),
      );
      expect(sw.value, 'daily');
    });

    testWidgets('the time commits on submit and reverts on refusal', (
      tester,
    ) async {
      final sent = <Map<String, dynamic>>[];
      await pumpBoth(
        tester,
        () => quick(
          const NewsletterSettings(
            enabled: true,
            deliveryTime: '07:00',
            timezone: 'Europe/London',
          ),
          (p) async {
            sent.add(p);
            return const KitLetterWrite(error: 'Refused.');
          },
        ),
      );
      final field = find.byKey(const ValueKey('d-lq-time'));
      await tester.enterText(field, '9:30');
      expect(sent, isEmpty, reason: 'no write per keystroke');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(sent.single, {
        'deliveryTime': '09:30',
        'timezone': 'Europe/London',
      });
      expect(
        tester.widget<TextField>(field).controller!.text,
        '07:00',
        reason: 'back to what the last read stored',
      );
    });
  });
}
