/// The program editor composes web's `ProgramEditor.jsx` from the kit
/// (2026-10-14; it was plain Material, TODO 2026-10-13 "Found by Flutter").
///
/// What it must do that the Material screen could not: order and remove the
/// chosen sources (the order IS the curriculum), send the email settings, say
/// what each source is, and delete a program behind §18 — and it must do it
/// with the kit's pieces, not Material's form controls.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/study/program_editor.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

class _Router implements HttpClientAdapter {
  _Router(this.reply);
  (int, Object) Function() reply;
  final List<RequestOptions> sent = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    sent.add(options);
    final r = reply();
    return ResponseBody.fromString(jsonEncode(r.$2), r.$1, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });
  }

  @override
  void close({bool force = false}) {}
}

Document _doc(String id, String title, String type, int chunks,
        {String? author}) =>
    Document.fromJson(id, {
      'user_id': 'u1',
      'title': title,
      'type': type,
      'status': 'complete',
      'chunk_count': chunks,
      if (author != null) 'author': author,
    });

final _docs = [
  _doc('d-pdf', 'Quarterly Tax Summary', 'pdf', 15, author: 'A. Clerk'),
  _doc('d-web', 'Espresso Basics', 'article', 2),
  _doc('d-note', 'Kitchen notebook', 'note', 6),
];

const _program = StudyProgram(
  id: 'p1',
  title: 'Cooking fundamentals',
  documentIds: ['d-web', 'd-pdf'],
  enabled: true,
  status: 'active',
  unitNumber: 1,
  sources: {
    'd-web': {'kind': 'notes'},
  },
);

class _Stub extends FirestoreService {
  _Stub() : super.stub();

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<Document>> subscribeDocuments({int limit = 200}) =>
      Stream.value(_docs);

  @override
  Stream<List<StudyProgram>> subscribeStudyPrograms() =>
      Stream.value(const [_program]);
}

Future<GoRouter> _pump(WidgetTester tester, String at) async {
  tester.view.physicalSize = const Size(1206, 2622);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: at, routes: [
    GoRoute(path: '/study', builder: (_, __) => const Text('Study list')),
    GoRoute(path: '/study/new', builder: (_, __) => const Scaffold(
        body: ProgramEditorPage())),
    GoRoute(
        path: '/study/:id',
        builder: (_, s) => Scaffold(
            body: ProgramEditorPage(programId: s.pathParameters['id']))),
  ]);
  await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

Map<String, dynamic> _body(RequestOptions o) =>
    (o.data is String ? jsonDecode(o.data as String) : o.data)
        as Map<String, dynamic>;

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    ApiService.instance.tokenProvider = () async => 'test-token';
    FirestoreService.instance = _Stub();
  });
  tearDown(() {
    ApiService.instance.resetTestSeams();
    FirestoreService.resetInstance();
  });

  testWidgets('a new program: the kit\'s sections, no Material form controls',
      (tester) async {
    await _pump(tester, '/study/new');
    expect(find.text('A New Program'), findsOneWidget);
    // Direction D: each group's eyebrow is its serif head (F-145,
    // screens/study.md §Composition — the program editor).
    for (final s in [
      'Name',
      'Sources for this subject',
      'Delivery',
      'Session length',
    ]) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    // The crumb back, and the sheet's figures read from the form as it
    // stands — on a phone, the running head: the cards glyph, the title,
    // `{n} documents`.
    expect(
        tester.widget<KitDBackControl>(find.byType(KitDBackControl)).label,
        'Study programs');
    expect(find.text('DEEP STUDY\u00a0· NEW PROGRAM'), findsOneWidget);
    expect(find.text('Untitled program'), findsWidgets);
    expect(find.byType(KitFormSection), findsNWidgets(4));
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.byType(KitCapCard), findsNWidgets(2));
    expect(find.byType(KitStepper), findsNWidgets(2));
    expect(find.text('0 of 10 chosen'), findsOneWidget);
    // Nothing chosen and no name: Create is held.
    final create = find.widgetWithText(KitButton, 'Create program');
    expect(tester.widget<KitButton>(create).onPressed, isNull);
  });

  testWidgets('the chosen sources are ordered, and the create sends them in '
      'that order with the email settings', (tester) async {
    final rec = _Router(() => (201, {'programId': 'p9'}));
    ApiService.instance.httpClientAdapter = rec;
    await _pump(tester, '/study/new');

    // Add the article, then the PDF; move the PDF to first.
    Finder addFor(String title) => find.descendant(
        of: find.ancestor(
            of: find.text(title), matching: find.byType(KitFormRow)),
        matching: find.widgetWithText(KitRowTextButton, 'Add'));
    await _tapVisible(tester, addFor('Espresso Basics'));
    await _tapVisible(tester, addFor('Quarterly Tax Summary'));
    expect(find.text('2 of 10 chosen'), findsOneWidget);
    // The PDF's row carries its author and its count — on a phone in one
    // line under the title (the count folds there beside three controls).
    expect(find.text('A. Clerk · 15 passages'), findsOneWidget);
    final earlier = find.descendant(
        of: find.ancestor(
            of: find.text('Quarterly Tax Summary'),
            matching: find.byType(KitFormRow)),
        matching: find.byWidgetPredicate(
            (w) => w is KitRowIconButton && w.label == 'Move earlier'));
    await _tapVisible(tester, earlier);

    await tester.enterText(
        find.descendant(
            of: find.byType(KitFormSection).first,
            matching: find.byType(TextField)),
        'Cooking');
    await tester.pumpAndSettle();
    await _tapVisible(tester, find.widgetWithText(KitButton, 'Create program'));

    final post = rec.sent.single;
    expect(post.method, 'POST');
    expect(post.path, endsWith('/fn_study_programs'));
    final body = _body(post);
    expect(body['documentIds'], ['d-pdf', 'd-web']);
    expect(body['title'], 'Cooking');
    expect(body['emailEnabled'], true);
    expect(body['emailAddress'], '');
    expect(body['deliveryTime'], '07:00');
    expect(body.containsKey('timezone'), isTrue,
        reason: 'deliveryTime travels with timezone (2.29.0)');
  });

  testWidgets('an existing program says what each source is, and asks for '
      'the one not answered', (tester) async {
    final rec = _Router(() => (200, {'ok': true}));
    ApiService.instance.httpClientAdapter = rec;
    await _pump(tester, '/study/p1');
    expect(find.text('Program Settings'), findsOneWidget);
    expect(find.text('What each source is'), findsOneWidget);
    expect(find.text('Where you are'), findsOneWidget);
    expect(find.text('Syllabus'), findsOneWidget);
    expect(find.text('Your notes — always available'), findsOneWidget);
    expect(find.text('Not answered yet'), findsOneWidget);
    expect(find.textContaining('One source still needs an answer'),
        findsOneWidget);

    final reading = find.descendant(
        of: find.ancestor(
            of: find.text('Not answered yet'),
            matching: find.byType(KitFormRow)),
        matching: find.widgetWithText(KitChoiceChip, 'A reading'));
    await _tapVisible(tester, reading);
    final put = rec.sent.single;
    expect(put.method, 'PUT');
    expect(_body(put), {
      'programId': 'p1',
      'sources': {
        'd-pdf': {'kind': 'reading'},
      },
    });
  });

  testWidgets('Delete program asks first (§18), and sends only on the confirm',
      (tester) async {
    final rec = _Router(() => (200, {'ok': true}));
    ApiService.instance.httpClientAdapter = rec;
    await _pump(tester, '/study/p1');
    // Direction D: Delete is the sheet's Also — last, in the critical ink —
    // and the form's foot no longer carries it. On a phone the sheet is the
    // running head: drop it, then Delete folds it before the confirm opens.
    expect(find.byType(KitFormDangerButton), findsNothing);
    await tester.tap(find.byKey(const ValueKey('d-peek')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.widgetWithText(KitAlsoButton, 'Delete program'));
    await tester.pumpAndSettle();
    expect(find.byType(KitConfirm), findsOneWidget);
    expect(rec.sent, isEmpty);
    await tester.tap(find.descendant(
        of: find.byType(KitConfirm),
        matching: find.widgetWithText(KitButton, 'Delete program')));
    await tester.pumpAndSettle();
    expect(rec.sent.single.method, 'DELETE');
    expect(rec.sent.single.uri.queryParameters['programId'], 'p1');
    expect(find.text('Study list'), findsOneWidget);
  });
}
