// F-145 — Deep study, Activity and For your review in direction D
// (screens/study.md, activity.md, review.md §Composition; kit §26–§37): the
// pages in the D frame, every figure a measurement (the ellipsis while a read
// is out, the dash when it was refused, never a zero), the sheets' leads, the
// running heads' lines, and the new kit parts in both themes.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/activity_page.dart';
import 'package:flutter_app/pages/study/session_player.dart';
import 'package:flutter_app/pages/study_page.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

// ── Stubs ────────────────────────────────────────────────────────────────

/// A read: [data] answers, [error] refuses, neither never answers.
class _Read<T> {
  final T? data;
  final bool error;
  const _Read.answers(this.data) : error = false;
  const _Read.refused() : data = null, error = true;
  const _Read.out() : data = null, error = false;

  Stream<T> stream() => error
      ? Stream<T>.error(Exception('permission-denied'))
      : data == null
      ? StreamController<T>().stream
      : Stream<T>.value(data as T);
}

class _Study extends FirestoreService {
  _Study({
    this.programs = const _Read.answers([]),
    this.sessions = const _Read.answers([]),
    this.session = const _Read.out(),
  }) : super.stub();

  final _Read<List<StudyProgram>> programs;
  final _Read<List<StudySession>> sessions;
  final _Read<StudySession?> session;
  int sessionReads = 0;
  final List<(String, List<String>)> logged = [];

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => programs.stream();

  @override
  Stream<List<StudySession>> subscribeStudySessions({
    String? programId,
    int limit = 30,
  }) => sessions.stream();

  @override
  Stream<StudySession?> subscribeStudySession(String sessionId) {
    sessionReads++;
    return session.stream();
  }

  @override
  Future<List<String>> logChunksRead(
    String documentId,
    List<String> chunkIds,
  ) async {
    logged.add((documentId, chunkIds));
    return chunkIds;
  }
}

class _Http implements HttpClientAdapter {
  _Http(this.reply);
  Future<(int, Object)> Function() reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    final r = await reply();
    return ResponseBody.fromString(
      jsonEncode(r.$2),
      r.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

StudyProgram _program(String id, {bool enabled = true}) =>
    StudyProgram.fromJson(id, {
      'title': 'Cooking fundamentals',
      'document_ids': ['d1'],
      'enabled': enabled,
      'status': 'active',
      'unit_count': 5,
      'introduced_count': 2,
    });

final _at = DateTime(2026, 10, 30, 9).millisecondsSinceEpoch;

StudySession _session({
  String status = 'sent',
  Map<String, dynamic> responses = const {},
  String program = 'Cooking fundamentals',
}) => StudySession.fromJson('s1', {
  'program_title': program,
  'status': status,
  'generated_at': _at,
  'new_count': 2,
  'review_count': 1,
  'responses': responses,
  'items': [
    {
      'item_id': 'i1',
      'chunk_id': 'c1',
      'document_id': 'd1',
      'kind': 'new',
      'title': 'Pasta Fundamentals',
      'excerpt_html': '<p>Salt the water before the pasta goes in.</p>',
      'questions': [
        {'qid': 'q1', 'question': 'When is the water salted?', 'answer': 'Before.'},
        {'qid': 'q2', 'question': 'How salty?', 'answer': 'Like the sea.'},
      ],
    },
    {
      'item_id': 'i2',
      'chunk_id': 'c2',
      'document_id': 'd2',
      'kind': 'review',
      'title': 'Household budget 2026',
      'excerpt_html': '<p>Keep a month ahead.</p>',
      'questions': [
        {'qid': 'q3', 'question': 'How far ahead?', 'answer': 'A month.'},
      ],
    },
  ],
});

Future<void> _settle(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(1280, 1800),
  Brightness brightness = Brightness.light,
  List<SingleChildWidget> providers = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = MaterialApp(
    theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
    home: Scaffold(body: page),
  );
  await tester.pumpWidget(
    providers.isEmpty ? app : MultiProvider(providers: providers, child: app),
  );
  await _settle(tester, 6);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

const _phone = Size(402, 874);

void main() {
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({});
    ApiService.instance.tokenProvider = () async => 'test-token';
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  // ── Study programs ─────────────────────────────────────────────────────

  group('Study programs (study.md §Composition)', () {
    testWidgets('a read that is out is the ellipsis and skeleton lines; no '
        'offer, no zero', (tester) async {
      FirestoreService.instance = _Study(
        programs: const _Read.out(),
        sessions: const _Read.out(),
      );
      await _pumpPage(tester, const StudyPage());
      expect(find.text('DEEP STUDY\u00a0· …'), findsOneWidget);
      expect(find.byType(KitSkeletonLines), findsNWidgets(2),
          reason: 'the programs register and Today, each while its read is out');
      expect(find.text('Go deeper on one subject'), findsNothing);
      expect(find.text('Nothing is waiting today.'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('a refused programs read: the dash and §14.1, never the offer',
        (tester) async {
      FirestoreService.instance = _Study(programs: const _Read.refused());
      await _pumpPage(tester, const StudyPage());
      expect(find.text('DEEP STUDY\u00a0· — PROGRAMS'), findsOneWidget);
      expect(find.text('Your study programs could not be read.'), findsOneWidget);
      expect(find.text('Go deeper on one subject'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('none yet: §37 in the column with its moves ruled, the '
        'masthead and the sheet stay, New program is the page\'s action',
        (tester) async {
      FirestoreService.instance = _Study();
      for (final b in Brightness.values) {
        KitPageTools.instance.reset();
        await _pumpPage(tester, const StudyPage(), brightness: b);
        expect(find.text('DEEP STUDY\u00a0· 0 PROGRAMS'), findsOneWidget);
        expect(find.text('Study Programs'), findsOneWidget);
        expect(find.text('Go deeper on one subject'), findsOneWidget);
        expect(find.text('One subject at a time'), findsOneWidget);
        expect(find.byType(KitNumberedMove), findsNothing,
            reason: 'the moves are a ruled list in D, not three cards');
        expect(find.text('Nothing is waiting today.'), findsOneWidget);
        await tester.pump();
        expect(KitPageTools.instance.action?.short, 'New program');
        await _unmount(tester);
      }
    });

    testWidgets('a program and a session: the folio counts, Today is the '
        'newest session\'s ungraded questions, the register is ruled',
        (tester) async {
      FirestoreService.instance = _Study(
        programs: _Read.answers([_program('p1'), _program('p2', enabled: false)]),
        sessions: _Read.answers([
          _session(responses: {'q1': {'grade': 'good'}}),
        ]),
      );
      await _pumpPage(tester, const StudyPage());
      expect(find.text('DEEP STUDY\u00a0· 2 PROGRAMS\u00a0· 1 ON'), findsOneWidget);
      expect(find.text('2 PROGRAMS · 1 ON'), findsOneWidget,
          reason: 'the Programs head\'s meta');
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('questions waiting'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(KitDeskLedger),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(find.byType(KitProgramCard), findsNWidgets(2));
      expect(
        find.ancestor(
          of: find.byType(KitProgramCard).first,
          matching: find.byType(KitCard),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(KitProgramCard).first,
          matching: find.byType(KitCard),
        ),
        findsNothing,
        reason: 'a program is a ruled register entry in D, not a card',
      );
      expect(find.byType(KitStudyHistoryRow), findsOneWidget);
      expect(find.text('1 of 3 answered'), findsOneWidget);
      // The sheet's Contents: Programs and Sessions, each counted.
      final contents = find.byType(KitContents);
      expect(
        find.descendant(of: contents, matching: find.text('Sessions')),
        findsOneWidget,
      );
      await _unmount(tester);
    });

    testWidgets('a refused sessions read: Today is absent, the register '
        'says so, Sessions keeps its row without a count', (tester) async {
      FirestoreService.instance = _Study(
        programs: _Read.answers([_program('p1')]),
        sessions: const _Read.refused(),
      );
      await _pumpPage(tester, const StudyPage());
      expect(find.text('TODAY'), findsNothing);
      expect(find.text('Nothing is waiting today.'), findsNothing);
      expect(find.text('Your recent sessions could not be read.'), findsOneWidget);
      final rows = tester
          .widget<KitContents>(find.byType(KitContents))
          .items;
      expect([for (final r in rows) (r.label, r.count)], [
        ('Programs', '1'),
        ('Sessions', null),
      ]);
      await _unmount(tester);
    });

    testWidgets('the newest session all graded: nothing is waiting today',
        (tester) async {
      FirestoreService.instance = _Study(
        programs: _Read.answers([_program('p1')]),
        sessions: _Read.answers([
          _session(responses: {
            'q1': {'grade': 'good'},
            'q2': {'grade': 'hard'},
            'q3': {'grade': 'easy'},
          }),
        ]),
      );
      await _pumpPage(tester, const StudyPage());
      expect(find.text('Nothing is waiting today.'), findsOneWidget);
      await _unmount(tester);
    });
  });

  // ── A session ──────────────────────────────────────────────────────────

  group('A session (study.md §Composition)', () {
    testWidgets('every state opens on the masthead with the crumb', (
      tester,
    ) async {
      FirestoreService.instance = _Study(session: const _Read.out());
      await _pumpPage(tester, const SessionPlayerPage(sessionId: 's1'));
      expect(find.text('A Study Session'), findsOneWidget);
      expect(find.text('Reading the session…'), findsOneWidget);
      expect(find.byType(KitDBackControl), findsOneWidget);
      await _unmount(tester);

      final refused = _Study(session: const _Read.refused());
      FirestoreService.instance = refused;
      await _pumpPage(tester, const SessionPlayerPage(sessionId: 's1'));
      expect(find.text('This Session Couldn’t Be Loaded'), findsOneWidget);
      expect(find.textContaining('nothing you graded has been lost'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(KitButton, 'Reload'));
      await _settle(tester, 4);
      expect(refused.sessionReads, 2, reason: 'Reload subscribes again');
      await _unmount(tester);
    });

    testWidgets('not here: its own title, and the way back', (tester) async {
      FirestoreService.instance = _NullSession();
      await _pumpPage(tester, const SessionPlayerPage(sessionId: 's1'));
      expect(find.text('This Session Isn’t Here'), findsOneWidget);
      expect(find.widgetWithText(KitButton, 'Back to study programs'),
          findsOneWidget);
      await _unmount(tester);
    });

    testWidgets('the sheet: Answered with its meter, the questions with the '
        'NEXT one marked, the keys; the running head is № 2 over a rule at '
        'the answered fraction', (tester) async {
      FirestoreService.instance = _Study(
        session: _Read.answers(_session(responses: {'q1': {'grade': 'good'}})),
      );
      for (final b in Brightness.values) {
        KitPageTools.instance.reset();
        await _pumpPage(
          tester,
          const SessionPlayerPage(sessionId: 's1'),
          size: _phone,
          brightness: b,
        );
        await _settle(tester, 10);
        expect(find.text('SESSION\u00a0· FRIDAY, OCTOBER 30'), findsOneWidget);
        expect(find.text('Cooking fundamentals'), findsOneWidget);
        expect(find.text('2 new, 1 for review.'), findsOneWidget);
        final peek = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
        expect((peek.title, peek.count, peek.tail),
            ('Pasta Fundamentals', '1', ' of 3'));
        expect((peek.mark as KitPeekMark).text, '№ 2');
        final bar = tester.widget<KitPeekBar>(find.byType(KitPeekBar));
        expect(bar.fraction, closeTo(1 / 3, 1e-9),
            reason: 'measured by what was answered, not by the scroll');
        final qs = tester.widget<KitStudyQuestions>(
          find.byType(KitStudyQuestions),
        );
        expect(qs.marked, 1, reason: 'the question to answer next');
        expect([for (final q in qs.items) q.grade], ['Good', null, null]);
        expect(find.text('SPACE'), findsNothing);
        expect(find.text('Space'), findsOneWidget, reason: 'the keys figure');
        expect(find.text('1 OF 3 ANSWERED'), findsOneWidget);
        await _unmount(tester);
      }
    });

    testWidgets('a grade is never optimistic: every grade is held until the '
        'write answers, and the return is the server\'s', (tester) async {
      FirestoreService.instance = _Study(
        session: _Read.answers(_session(responses: {'q1': {'grade': 'good'}})),
      );
      final gate = Completer<(int, Object)>();
      final http = _Http(() => gate.future);
      ApiService.instance.httpClientAdapter = http;
      await _pumpPage(tester, const SessionPlayerPage(sessionId: 's1'));
      await tester.tap(find.text('Show answer').first);
      await _settle(tester, 4);
      expect(find.text('Like the sea.'), findsOneWidget);
      await tester.tap(find.text('Good').last);
      await _settle(tester, 4);
      expect(http.sent.single.path, endsWith('/fn_submit_study_answer'));
      final held = tester
          .widgetList<Opacity>(
            find.ancestor(
              of: find.text('Easy'),
              matching: find.byType(Opacity),
            ),
          )
          .first;
      expect(held.opacity, lessThan(1), reason: 'held while the write runs');
      expect(find.text('Saving your grade…'), findsOneWidget);
      final due = DateTime.now()
          .add(const Duration(days: 6))
          .millisecondsSinceEpoch;
      gate.complete((200, {'ok': true, 'item': {'due_at': due}}));
      await _settle(tester, 6);
      expect(find.text('Saving your grade…'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('while it is being made: no questions anywhere, the panel '
        'says so', (tester) async {
      FirestoreService.instance = _Study(
        session: _Read.answers(_session(status: 'generating')),
      );
      await _pumpPage(tester, const SessionPlayerPage(sessionId: 's1'));
      expect(find.text('This session is still being made'), findsOneWidget);
      expect(find.text('Its questions are still being assembled.'),
          findsOneWidget);
      expect(find.byType(KitStudyQuestions), findsNothing);
      expect(find.byType(KitStudyQuestionCard), findsNothing);
      await _unmount(tester);
    });

    testWidgets('an excerpt shown is a read, batched per document; a review '
        'keeps its excerpt behind a disclosure', (tester) async {
      final svc = _Study(session: _Read.answers(_session()));
      FirestoreService.instance = svc;
      await _pumpPage(tester, const SessionPlayerPage(sessionId: 's1'));
      // The new unit's excerpt stands beside its questions at once.
      expect(find.text('FROM PASTA FUNDAMENTALS'), findsNWidgets(2));
      expect(find.text('FROM HOUSEHOLD BUDGET 2026'), findsNothing);
      await tester.ensureVisible(find.text('Show answer').last);
      await tester.tap(find.text('Show answer').last);
      await _settle(tester, 4);
      await tester.ensureVisible(find.text('Show the excerpt'));
      await tester.tap(find.text('Show the excerpt'));
      await _settle(tester, 4);
      expect(find.text('FROM HOUSEHOLD BUDGET 2026'), findsOneWidget);
      await _unmount(tester);
      expect([for (final l in svc.logged) '${l.$1}:${l.$2.join(',')}'], [
        'd1:c1',
        'd2:c2',
      ], reason: 'once per passage, one batch per document, on leaving');
    });
  });

  // ── Activity ───────────────────────────────────────────────────────────

  group('Activity (activity.md §Composition)', () {
    ActivityItem item(String id, String type, int at) => ActivityItem(
      kind: 'event',
      id: id,
      type: type,
      status: 'success',
      title: 'Event $id',
      createdAt: at,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;

    Future<void> pump(
      WidgetTester tester,
      _Activity a, {
      Size size = const Size(1280, 1800),
    }) => _pumpPage(
      tester,
      const ActivityPage(),
      size: size,
      providers: [
        ChangeNotifierProvider<ActivityNotifier>.value(value: a),
        ChangeNotifierProvider<DocumentsNotifier>(create: (_) => _Docs()),
      ],
    );

    testWidgets('while the feed is out: the ellipsis and skeleton lines, '
        'never "Nothing of that kind yet."', (tester) async {
      await pump(tester, _Activity(loading: true));
      expect(find.text('ACTIVITY\u00a0· …'), findsOneWidget);
      expect(find.byType(KitSkeletonLines), findsOneWidget);
      expect(find.text('Nothing of that kind yet.'), findsNothing);
      expect(find.text('No activity yet.'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('Kind: the families held at zero, Other only when used; '
        'When: the days that hold rows', (tester) async {
      final a = _Activity(items: [
        item('a', 'doc_indexed', now),
        item('b', 'service_connected', old),
        item('c', 'doc_indexed', old),
      ]);
      await pump(tester, a);
      expect(find.text('ACTIVITY\u00a0· 3 EVENTS'), findsOneWidget);
      final facet = tester.widget<KitFacet>(find.byType(KitFacet));
      expect(
        [for (final i in facet.items) (i.id, i.count, i.disabled)],
        [
          ('all', '3', false),
          ('sources', '1', false),
          ('processing', '2', false),
          ('letters', '0', true),
          ('study', '0', true),
          ('library', '0', true),
        ],
      );
      final when = tester
          .widgetList<KitContents>(find.byType(KitContents))
          .single;
      expect([for (final w in when.items) (w.label, w.count)], [
        ('Today', '1'),
        ('Earlier', '2'),
      ]);
      expect(find.byType(KitSectionHead), findsNWidgets(2));
      await _unmount(tester);
    });

    testWidgets('an empty feed under All says No activity yet.; a kind the '
        'reader chose, emptied, says Nothing of that kind yet. (web 22f9461, '
        'activity.md §Composition 5.42.0)', (tester) async {
      final a = _Activity();
      await pump(tester, a);
      expect(find.text('No activity yet.'), findsOneWidget);
      expect(find.text('Nothing of that kind yet.'), findsNothing,
          reason: 'it names a filter nobody chose');
      await _unmount(tester);

      final b = _Activity(items: [
        item('a', 'doc_indexed', now),
        item('b', 'service_connected', old),
      ]);
      await pump(tester, b);
      await tester.tap(find.descendant(
          of: find.byType(KitFacet), matching: find.text('Sources')));
      await _settle(tester, 6);
      expect(find.text('Event b'), findsOneWidget);
      // The reader's kind empties under them (the event aged out).
      b.set([item('a', 'doc_indexed', now)]);
      await _settle(tester, 6);
      expect(find.text('Nothing of that kind yet.'), findsOneWidget);
      expect(find.text('No activity yet.'), findsNothing);
      await _unmount(tester);
    });

    testWidgets('choosing a kind narrows the feed and its days; the running '
        'head says what is shown of all', (tester) async {
      final a = _Activity(items: [
        item('a', 'doc_indexed', now),
        item('b', 'service_connected', old),
        item('c', 'doc_indexed', old),
      ]);
      await pump(tester, a, size: _phone);
      var peek = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
      expect((peek.title, peek.count, peek.tail), ('All activity', '3', null));
      await tester.tap(find.byKey(const ValueKey('d-peek')));
      await _settle(tester, 12);
      await tester.tap(find.text('Sources').last);
      await _settle(tester, 12);
      peek = tester.widget<KitLibPeek>(find.byType(KitLibPeek));
      expect((peek.title, peek.count, peek.tail), ('Sources', '1', ' of 3'));
      expect(find.text('Event b'), findsOneWidget);
      expect(find.text('Event a'), findsNothing);
      await _unmount(tester);
    });
  });

  // ── The kit parts ──────────────────────────────────────────────────────

  group('kit parts (F-145)', () {
    Future<void> both(
      WidgetTester tester,
      Widget child,
      Future<void> Function() check,
    ) async {
      for (final b in Brightness.values) {
        tester.view.physicalSize = const Size(900, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ));
        await tester.pump();
        await check();
      }
    }

    testWidgets('the ledger takes its label and its quiet sentence, and '
        'draws skeleton lines while its read is out', (tester) async {
      await both(
        tester,
        const Column(children: [
          KitDeskLedger(
            label: 'Today',
            rows: [],
            quiet: true,
            quietText: 'Nothing is waiting today.',
          ),
          KitDeskLedger(label: 'Today', rows: [], loading: true, quiet: true),
        ]),
        () async {
          expect(find.text('TODAY'), findsNWidgets(2));
          expect(find.text('Nothing is waiting today.'), findsOneWidget);
          expect(find.byType(KitSkeletonLines), findsOneWidget);
        },
      );
    });

    testWidgets('a section header asked for a D group head draws one; '
        'the first opens at the top', (tester) async {
      await both(
        tester,
        const Column(children: [
          KitDGroupHeads(
            first: true,
            child: SectionHeader('Sources that need you · 3',
                actionLabel: 'Dismiss all'),
          ),
          KitDGroupHeads(child: SectionHeader('Proposals · 1')),
          SectionHeader('Elsewhere'),
        ]),
        () async {
          final heads = tester
              .widgetList<KitDGroupHead>(find.byType(KitDGroupHead))
              .toList();
          expect([for (final h in heads) (h.title, h.top)], [
            ('Sources that need you · 3', 0.0),
            ('Proposals · 1', 56.0),
          ]);
          expect(find.text('Dismiss all'), findsOneWidget);
          expect(find.text('ELSEWHERE'), findsOneWidget,
              reason: 'outside the scope the header is unchanged');
        },
      );
    });

    testWidgets('in the D frame a form group is a D head, a timeline subject '
        'is serif', (tester) async {
      await both(
        tester,
        const KitDScope(
          child: Column(children: [
            KitFormSection(eyebrow: 'Name', first: true),
            KitTimeline(rows: [
              KitTimelineRow(
                icon: Icons.check,
                chip: 'Indexed',
                subject: 'A source',
                time: '5:00 AM',
              ),
            ]),
          ]),
        ),
        () async {
          expect(tester.widget<KitDGroupHead>(find.byType(KitDGroupHead)).top,
              0);
          final subject = tester.widget<Text>(find.text('A source'));
          expect(subject.style?.fontFamily, AppTheme.fontSerif);
          expect(subject.style?.fontSize, 16.5);
        },
      );
    });

    testWidgets('the peek bar fills to the fraction it is given', (
      tester,
    ) async {
      await both(
        tester,
        const SizedBox(width: 300, height: 2, child: KitPeekBar(0.5)),
        () async {
          await _settle(tester, 10);
          final f = tester.widget<FractionallySizedBox>(
            find.byKey(const ValueKey('d-peek-bar')),
          );
          expect(f.widthFactor, closeTo(0.5, 1e-6));
        },
      );
    });
  });
}

class _NullSession extends FirestoreService {
  _NullSession() : super.stub();
  @override
  String? get currentUid => 'u1';
  @override
  Stream<StudySession?> subscribeStudySession(String sessionId) =>
      Stream<StudySession?>.value(null);
}

class _Activity extends ActivityNotifier {
  _Activity({List<ActivityItem> items = const [], bool loading = false})
    : _items = items,
      _loading = loading;
  List<ActivityItem> _items;
  final bool _loading;

  /// A new snapshot.
  void set(List<ActivityItem> items) {
    _items = items;
    notifyListeners();
  }

  @override
  void start({int limit = 100}) {}
  @override
  List<ActivityItem> get items => _items;
  @override
  bool get isLoading => _loading;
  @override
  String? get error => null;
  @override
  int get newestEventAt => 0;
}

class _Docs extends DocumentsNotifier {
  @override
  void start() {}
  @override
  List<Document> get documents => const [];
}
