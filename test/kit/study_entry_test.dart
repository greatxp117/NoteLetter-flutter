// F-153 / F-154 — Study's two ways in (5.49.0, spec/features/
// study-entry-points.md; Xavier's ruling 9 of 2026-11-02): Home's study band
// (screens/library.md §Composition item 4) and the source page's *Study this*
// (screens/reader.md §Study this), with the pre-filled new-program editor it
// opens (screens/study.md). Web's twin is tests/contract/study-entry.test.js.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_app/shared/document_window.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/study/program_editor.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/local_flags.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import '../contract/home_harness.dart';

Map<String, dynamic> _q(String id) => {
  'qid': id,
  'question': '?',
  'answer': '!',
};

// Two items (one new, one review), three questions: counts are QUESTIONS.
StudySession _session({
  String status = 'sent',
  Map<String, dynamic> responses = const {},
  List<Map<String, dynamic>>? items,
  int? at,
}) => StudySession.fromJson('ses-1', {
  'status': status,
  'program_title': 'Stoic ethics',
  'generated_at': ?at,
  'items':
      items ??
      [
        {
          'kind': 'new',
          'questions': [_q('a'), _q('b')],
        },
        {
          'kind': 'review',
          'questions': [_q('c')],
        },
      ],
  'responses': responses,
});

class _Http implements HttpClientAdapter {
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    sent.add(options);
    return ResponseBody.fromString(
      jsonEncode({'id': 'p-new'}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Document _doc(
  String id,
  String title, {
  int? chunks = 4,
  String status = 'complete',
}) => Document.fromJson(id, {
  'user_id': 'u1',
  'title': title,
  'type': 'pdf',
  'status': status,
  'chunk_count': chunks,
});

class _Docs extends FirestoreService {
  _Docs(this.docs) : super.stub();
  final List<Document> docs;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribeDocuments({int limit = documentWindow}) =>
      Stream.value(docs);

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() => Stream.value(const []);
}

/// A stand-in source page that does what the reader's *Study this* does: it
/// PUSHES the editor with the source as its seed. (`ReaderPage` builds
/// notifiers that reach Firebase, which a plain widget test has none of —
/// leave_guard_test records the same split.)
Future<GoRouter> _pumpFromSource(
  WidgetTester tester,
  Document source, {
  Size size = const Size(1280, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/reader/${source.id}',
    routes: [
      GoRoute(
        path: '/reader/:id',
        builder: (context, s) => Scaffold(
          body: Center(
            child: GestureDetector(
              onTap: () => context.push('/study/new', extra: StudySeed(source)),
              child: const Text('The source page'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/study',
        builder: (_, _) => const Text('Study programs list'),
      ),
      GoRoute(
        path: '/study/new',
        builder: (_, s) => Scaffold(
          body: ProgramEditorPage(
            seed: s.extra is StudySeed ? s.extra as StudySeed : null,
          ),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('The source page'));
  await tester.pumpAndSettle();
  return router;
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  late _Http http;
  setUp(() {
    KitPageTools.instance.reset();
    SharedPreferences.setMockInitialValues({'nl-onboard-dismissed': true});
    LocalFlags.resetForTest();
    LocalFlags.onboardDismissed.value = true;
    LocalFlags.sourceView.value = 'list';
    ApiService.instance.tokenProvider = () async => 'test-token';
    http = _Http();
    ApiService.instance.httpClientAdapter = http;
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  group('the one reading of the newest session', () {
    test(
      'counts questions, never items, and splits new and review by kind',
      () {
        final due = kitStudyDue(_session())!;
        expect(
          [
            due.id,
            due.total,
            due.left,
            due.answered,
            due.started,
            due.fresh,
            due.review,
          ],
          ['ses-1', 3, 3, 0, false, 2, 1],
        );
      },
    );

    test('an exam-ramp review is a review; an unknown kind counts toward the '
        'total only', () {
      final due = kitStudyDue(
        _session(
          items: [
            {
              'kind': 'review',
              'ramp': true,
              'questions': [_q('a')],
            },
            {
              'kind': 'mystery',
              'questions': [_q('b')],
            },
          ],
        ),
      )!;
      expect([due.total, due.fresh, due.review], [2, 0, 1]);
    });

    test('started means at least one response', () {
      final due = kitStudyDue(
        _session(
          responses: {
            'a': {'grade': 'good'},
          },
        ),
      )!;
      expect([due.started, due.left, due.answered], [true, 2, 1]);
    });

    test('null when the session was not delivered, or nothing is left', () {
      expect(kitStudyDue(_session(status: 'generating')), isNull);
      expect(kitStudyDue(_session(status: 'empty')), isNull);
      expect(
        kitStudyDue(_session(responses: {'a': {}, 'b': {}, 'c': {}})),
        isNull,
      );
      expect(kitStudyDue(_session(status: 'email_failed'))!.left, 3);
    });
  });

  group('the band’s words', () {
    final now = DateTime(2026, 11, 2, 15);
    test(
      'when it was sent: the time today, yesterday, else the short date',
      () {
        expect(
          kitSentPhrase(DateTime(2026, 11, 2, 7).millisecondsSinceEpoch, now),
          'sent 7:00 AM',
        );
        expect(
          kitSentPhrase(
            DateTime(2026, 11, 1, 22, 30).millisecondsSinceEpoch,
            now,
          ),
          'sent yesterday',
        );
        expect(
          kitSentPhrase(DateTime(2026, 10, 31, 7).millisecondsSinceEpoch, now),
          'sent Sat, Oct 31',
        );
        expect(kitSentPhrase(null, now), isNull);
      },
    );

    test('before a response: the total waiting, new and due for review', () {
      expect(
        kitStudyBandLine(
          const KitStudyDue(3, 'x', total: 3, fresh: 2, review: 1),
        ),
        ('3', ' questions waiting — 2 new, 1 due for review'),
      );
      expect(kitStudyBandLine(const KitStudyDue(1, 'x', total: 1, fresh: 1)), (
        '1',
        ' question waiting — 1 new, 0 due for review',
      ));
    });

    test('after one: what is left of the total, and what was answered', () {
      expect(
        kitStudyBandLine(
          const KitStudyDue(2, 'x', total: 5, answered: 3, fresh: 2, review: 3),
        ),
        ('2', ' of 5 questions left — 3 answered already'),
      );
    });
  });

  group('Home’s study band (F-153)', () {
    final docs = [homeDoc('a', title: 'A volume')];

    testWidgets('under the letter and above Recently added, with the session’s '
        'words', (tester) async {
      await pumpHome(
        tester,
        HomeReads(
          docs: docs,
          sessions: [_session(at: DateTime.now().millisecondsSinceEpoch)],
        ),
        inbox: homeInbox(),
      );
      final band = find.byKey(const ValueKey('hm-due'));
      expect(band, findsOneWidget);
      expect(
        find.descendant(
          of: band,
          matching: find.textContaining('DEEP STUDY · SENT '),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: band, matching: find.text('Stoic ethics')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: band,
          matching: find.text(
            '3 questions waiting — 2 new, 1 due for review',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: band, matching: find.text('Start the session')),
        findsOneWidget,
      );
      // Under the letter, above Recently added.
      final letterY = tester
          .getTopLeft(find.byKey(const ValueKey('ed-letter')))
          .dy;
      final bandY = tester.getTopLeft(band).dy;
      final recentY = tester.getTopLeft(find.text('Recently added').last).dy;
      expect(letterY < bandY && bandY < recentY, isTrue);
      // The standfirst and the ledger still count the same questions.
      expect(
        find.textContaining('Three questions wait in Deep study'),
        findsOneWidget,
      );
      expect(find.text('Deep study · Stoic ethics'), findsOneWidget);
    });

    testWidgets('once started: Resume session, and what is left of the total', (
      tester,
    ) async {
      await pumpHome(
        tester,
        HomeReads(
          docs: docs,
          sessions: [
            _session(
              responses: {
                'a': {'grade': 'good'},
              },
            ),
          ],
        ),
        inbox: homeInbox(),
      );
      final band = find.byKey(const ValueKey('hm-due'));
      expect(
        find.descendant(of: band, matching: find.text('Resume session')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: band,
          matching: find.text(
            '2 of 3 questions left — 1 answered already',
            findRichText: true,
          ),
        ),
        findsOneWidget,
      );
      // No generated_at: the eyebrow is Deep study alone.
      expect(
        find.descendant(of: band, matching: find.text('DEEP STUDY')),
        findsOneWidget,
      );
    });

    testWidgets('nothing for a session not delivered, or with nothing left', (
      tester,
    ) async {
      await pumpHome(
        tester,
        HomeReads(
          docs: docs,
          sessions: [_session(status: 'generating')],
        ),
        inbox: homeInbox(),
      );
      expect(find.byKey(const ValueKey('hm-due')), findsNothing);
      await pumpHome(
        tester,
        HomeReads(
          docs: docs,
          sessions: [
            _session(responses: {'a': {}, 'b': {}, 'c': {}}),
          ],
        ),
        inbox: homeInbox(),
      );
      expect(find.byKey(const ValueKey('hm-due')), findsNothing);
    });

    testWidgets(
      'nothing while the read is out, and nothing when it was refused',
      (tester) async {
        await pumpHome(
          tester,
          HomeReads(docs: docs, sessions: null),
          inbox: homeInbox(),
        );
        expect(find.byKey(const ValueKey('hm-due')), findsNothing);
        await pumpHome(
          tester,
          HomeReads(docs: docs, failSessions: true),
          inbox: homeInbox(),
        );
        expect(find.byKey(const ValueKey('hm-due')), findsNothing);
      },
    );

    testWidgets(
      'its button opens the session; on a phone it runs the full width',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var opened = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: KitStudyBand(
                  due: kitStudyDue(_session())!,
                  onOpen: () => opened++,
                ),
              ),
            ),
          ),
        );
        final band = tester.getSize(find.byKey(const ValueKey('hm-due')));
        final button = tester.getSize(find.byType(KitButton));
        // The card's 20px padding and 1px edge each side.
        expect(button.width, closeTo(band.width - 42, 1));
        await tester.tap(find.text('Start the session'));
        expect(opened, 1);
      },
    );
  });

  group('Study this and the editor it opens (F-154)', () {
    test('offered only for a source a program may hold', () {
      expect(studyThisOffered(_doc('d', 'x')), isTrue);
      expect(studyThisOffered(_doc('d', 'x', chunks: 0)), isFalse);
      expect(studyThisOffered(_doc('d', 'x', chunks: null)), isFalse);
      expect(studyThisOffered(_doc('d', 'x', status: 'processing')), isFalse);
    });

    test('the name is the title, trimmed, cut to the endpoint’s 120', () {
      expect(studySeedTitle(_doc('d', '  Meditations  ')), 'Meditations');
      expect(studySeedTitle(_doc('d', 'x' * 130)).length, 120);
    });

    testWidgets('pre-filled — the source chosen, named after it — and nothing '
        'written', (tester) async {
      // Outside the listing's window: still drawn, from the source's record.
      FirestoreService.instance = _Docs([_doc('d-other', 'Espresso Basics')]);
      final source = _doc('d-med', 'Meditations');
      await _pumpFromSource(tester, source);
      expect(find.text('A New Program'), findsOneWidget);
      expect(find.text(studyStartedFrom), findsOneWidget);
      expect(find.text('MEDITATIONS'), findsOneWidget); // the crumb
      final name = tester.widget<EditableText>(find.byType(EditableText).first);
      expect(name.controller.text, 'Meditations');
      expect(find.text('1 of 10 chosen'), findsOneWidget);
      expect(find.text('Meditations'), findsWidgets);
      expect(http.sent, isEmpty);
    });

    testWidgets(
      'its crumb and Cancel go back to the source page, writing nothing',
      (tester) async {
        FirestoreService.instance = _Docs([_doc('d-med', 'Meditations')]);
        final source = _doc('d-med', 'Meditations');
        await _pumpFromSource(tester, source);
        await _tapVisible(tester, find.text('MEDITATIONS'));
        expect(find.text('The source page'), findsOneWidget);
        await tester.tap(find.text('The source page'));
        await tester.pumpAndSettle();
        await _tapVisible(tester, find.text('Cancel'));
        expect(find.text('The source page'), findsOneWidget);
        expect(http.sent, isEmpty);
      },
    );

    testWidgets('only Create program creates, with this source and its name; '
        'it closes to the programs', (tester) async {
      FirestoreService.instance = _Docs([_doc('d-med', 'Meditations')]);
      await _pumpFromSource(tester, _doc('d-med', 'Meditations'));
      await _tapVisible(tester, find.text('Create program'));
      expect(http.sent, hasLength(1));
      final body =
          (http.sent.single.data is String
                  ? jsonDecode(http.sent.single.data as String)
                  : http.sent.single.data)
              as Map<String, dynamic>;
      expect(body['title'], 'Meditations');
      expect(body['documentIds'], ['d-med']);
      expect(find.text('Study programs list'), findsOneWidget);
    });

    testWidgets(
      'on a phone the running head counts one document in the singular',
      (tester) async {
        FirestoreService.instance = _Docs([_doc('d-med', 'Meditations')]);
        await _pumpFromSource(
          tester,
          _doc('d-med', 'Meditations'),
          size: const Size(402, 874),
        );
        expect(find.text(' document', findRichText: true), findsNothing);
        expect(find.textContaining('1 document'), findsWidgets);
        expect(find.textContaining('1 documents'), findsNothing);
      },
    );
  });
}
