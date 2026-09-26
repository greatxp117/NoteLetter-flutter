/// The owed confirms `confirm_check.py` found (NoteLetter-contracts@7635d61),
/// mirrored from web 71987f6:
///
/// * The Sources processing row's **Retry** and **Index it anyway** re-derive
///   the document, and reader.md §Supersession confirm names "retry of an
///   errored doc": an errored document CAN hold edited passages (a failed
///   RE-extraction keeps them) and be in a study program. Both sent
///   `fn_retry_document` on the first tap.
/// * Starting a study unit closed its §18 panel on `null` and called
///   afterwards, so a refusal landed outside the panel (§18 rule 1).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/study.dart';
import 'package:flutter_app/pages/sources/browse_section.dart';
import 'package:flutter_app/pages/study/program_editor.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// Records every request and answers with [reply].
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

Document _doc(String status, {bool forced = false}) =>
    Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'Field notes',
      'type': status == 'skipped' ? 'image' : 'pdf',
      'status': status,
      'chunk_count': 4,
      if (status == 'error') 'error_message': 'Extraction failed.',
      if (status == 'skipped') 'skip_reason': 'not_text',
      'force_process': forced,
    });

Future<void> _pumpRow(WidgetTester tester, Document doc,
    {bool? edited, bool? inStudy}) async {
  await tester.pumpWidget(ChangeNotifierProvider(
    create: (_) => ActivityNotifier(),
    child: MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ProcessingRow(
            doc: doc,
            editCheck: (_) async => edited,
            studyCheck: (_) async => inStudy,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _inPanel(Finder f) =>
    find.descendant(of: find.byType(KitConfirm), matching: f);

void main() {
  setUp(() => ApiService.instance.tokenProvider = () async => 'test-token');
  tearDown(() => ApiService.instance.resetTestSeams());

  group('Retry / Index it anyway: the §Supersession confirm', () {
    testWidgets('two definite noes: no confirm, sent on the tap',
        (tester) async {
      final rec = _Router(() => (200, {'ok': true}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _doc('error'), edited: false, inStudy: false);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(KitConfirm), findsNothing);
      expect(rec.sent.single.path, endsWith('/fn_retry_document'));
    });

    testWidgets(
        'an errored doc in a study program: the danger confirm names the '
        'document first; the refusal stays in the panel; success closes it',
        (tester) async {
      var status = 409;
      final rec = _Router(() => status == 409
          ? (409, {'error': 'Retry is cooling down — try again in 40 seconds.'})
          : (200, {'ok': true}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _doc('error'), edited: false, inStudy: true);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(rec.sent, isEmpty, reason: 'nothing leaves before the confirm');
      expect(find.text('Retry “Field notes”?'), findsOneWidget);
      expect(find.textContaining('processed again from its original'),
          findsOneWidget);
      expect(find.textContaining('This source is in a study program'),
          findsOneWidget);
      expect(find.textContaining('Your edits'), findsNothing);

      final confirm = _inPanel(find.widgetWithText(KitButton, 'Retry and replace'));
      expect(tester.widget<KitButton>(confirm).variant, KitButtonVariant.danger);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(_inPanel(find.textContaining('cooling down')), findsOneWidget,
          reason: '§18: the refusal is in the panel, which stays open');
      expect(find.byType(KitFailureInline), findsOneWidget,
          reason: 'only the panel\'s slot — not the row\'s as well');

      status = 200;
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(KitConfirm), findsNothing);
      expect(find.textContaining('cooling down'), findsNothing);
      expect(rec.sent.length, 2);
    });

    testWidgets('Index it anyway, edits unreadable: says so; Keep sends nothing',
        (tester) async {
      final rec = _Router(() => (200, {'ok': true}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _doc('skipped'), edited: null, inStudy: false);
      await tester.tap(find.text('Index it anyway'));
      await tester.pumpAndSettle();
      expect(find.text('Index “Field notes” anyway?'), findsOneWidget);
      expect(find.textContaining('read again as text'), findsOneWidget);
      expect(find.textContaining('could not check whether these passages'),
          findsOneWidget);
      await tester.tap(find.text('Keep it as it is'));
      await tester.pumpAndSettle();
      expect(rec.sent, isEmpty);
      final primary = find.widgetWithText(KitButton, 'Index it anyway');
      expect(tester.widget<KitButton>(primary).onPressed, isNotNull,
          reason: 'the control is given back');
    });

    testWidgets('Index it anyway confirmed sends {force: true}',
        (tester) async {
      final rec = _Router(() => (200, {'ok': true}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _doc('skipped'), edited: true, inStudy: false);
      await tester.tap(find.text('Index it anyway'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your edits to these passages'),
          findsOneWidget);
      await tester.tap(_inPanel(find.widgetWithText(KitButton, 'Index it anyway')));
      await tester.pumpAndSettle();
      expect(rec.sent.single.data, containsPair('force', true));
    });

    testWidgets('no confirm owed and refused: §14.2 under the row',
        (tester) async {
      final rec = _Router(() => (409, {'error': 'Already queued.'}));
      ApiService.instance.httpClientAdapter = rec;
      await _pumpRow(tester, _doc('error'), edited: false, inStudy: false);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(KitConfirm), findsNothing);
      expect(find.widgetWithText(KitFailureInline, 'Already queued.'),
          findsOneWidget);
    });
  });

  group('Start a new unit: the panel holds until the call resolves', () {
    const program = StudyProgram(
        id: 'p1',
        title: 'Files',
        documentIds: [],
        enabled: true,
        status: 'active',
        unitNumber: 2);

    testWidgets('a refusal is in the §18 slot; success closes, then refreshes',
        (tester) async {
      var status = 409;
      final rec = _Router(() => status == 409
          ? (409, {'error': 'A unit started less than a minute ago.'})
          : (200, {'ok': true}));
      ApiService.instance.httpClientAdapter = rec;
      var refreshed = 0;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: UnitPanel(
              program: program,
              docs: const [],
              onDone: () async => refreshed++),
        ),
      ));
      await tester.tap(find.text('Start a new unit'));
      await tester.pumpAndSettle();
      expect(rec.sent, isEmpty);

      final confirm = _inPanel(find.widgetWithText(KitButton, 'Start the unit'));
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(rec.sent.single.path, endsWith('/fn_study_advance_unit'));
      expect(_inPanel(find.textContaining('less than a minute ago')),
          findsOneWidget,
          reason: '§18 rule 1: the panel did not close before the call');
      expect(refreshed, 0);

      status = 200;
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.byType(KitConfirm), findsNothing);
      expect(refreshed, 1);
      expect(find.text('Unit 3 started.'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
