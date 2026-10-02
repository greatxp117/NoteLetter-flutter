// screens/review.md §Composition §States, mirroring web
// tests/contract/review-view.test.js: the folio is the inbox's count (the dash
// unmeasured, "Nothing waiting" at zero), groups appear in order and only when
// they have rows, a failed subscription is a §14.1 block in its group's place
// while the others render, and the §7 empty state speaks only when nothing
// failed. The §22 row's actions follow the task's status.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/background_task.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/organization_suggestion.dart';
import 'package:flutter_app/pages/review/task_copy.dart';
import 'package:flutter_app/pages/review_page.dart';
import 'package:flutter_app/pages/sources/browse_section.dart' show ProcessingRow;
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/state/cloud_notifier.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/org_notifier.dart';
import 'package:flutter_app/state/review_inbox.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart' show QuietCloud, StubActivity, StubTags;

final _now = DateTime.now();
final _later = _now.millisecondsSinceEpoch + 3600 * 1000;
final _earlier = _now.millisecondsSinceEpoch - 1000;

BackgroundTask _task(String id, String status,
        {String kind = 'shelf_delete',
        int? stalls,
        Map<String, dynamic>? result,
        String? applyError,
        String? error}) =>
    BackgroundTask.fromJson(id, {
      'kind': kind,
      'status': status,
      'stalls_at': stalls,
      'subject': {'type': 'shelf', 'id': 't', 'title': 'Misc', 'color': 'sage-500'},
      'capture': {'member_count': 4, 'sources': []},
      'result': result,
      'apply_error': applyError,
      'error_message': error,
    });

Future<void> _pump(
  WidgetTester tester, {
  Stream<List<Document>>? docs,
  Stream<List<ImportJob>>? holds,
  Stream<List<OrganizationSuggestion>>? suggestions,
  Stream<List<BackgroundTask>>? tasks,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final inbox = ReviewInbox(
    docs: () => docs ?? Stream.value(const []),
    holds: () => holds ?? Stream.value(const []),
    suggestions: () => suggestions ?? Stream.value(const []),
    tasks: () => tasks ?? Stream.value(const []),
  );
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ReviewInbox>(create: (_) => inbox),
      ChangeNotifierProvider<CloudNotifier>(create: (_) => QuietCloud()),
      ChangeNotifierProvider<OrgNotifier>(create: (_) => OrgNotifier()),
      ChangeNotifierProvider<ActivityNotifier>(create: (_) => StubActivity()),
      ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags()),
      ChangeNotifierProvider<DocumentsNotifier>(create: (_) => DocumentsNotifier()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ReviewPage()),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

/// Unmounts inside the test body, so the providers dispose their notifiers —
/// the inbox's 15s clock included — before the pending-timer check runs.
Future<void> _done(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

Document _doc(String id, String status) => Document.fromJson(id, {
      'user_id': 'u',
      'title': 'Doc $id',
      'type': 'pdf',
      'status': status,
      'error_message': 'No readable text was found.',
    });

void main() {
  testWidgets('nothing anywhere: the §7 empty state, folio "Nothing waiting"',
      (tester) async {
    await _pump(tester);
    expect(find.text('NOTHING WAITING'), findsOneWidget);
    expect(find.text('Nothing waiting for you'), findsOneWidget);
    expect(find.text('Add to your library'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('a failed part: its §14.1 block, the dash, the rest still render',
      (tester) async {
    await _pump(tester,
        holds: Stream.error(Exception('denied')),
        docs: Stream.value([_doc('a', 'error')]));
    expect(find.text('The files waiting to import could not be read.'), findsOneWidget);
    expect(find.text('— WAITING'), findsOneWidget);
    expect(find.text('Sources that need you · 1'.toUpperCase()), findsOneWidget);
    expect(find.text('Nothing waiting for you'), findsNothing,
        reason: 'a failure is never an empty state');
    await _done(tester);
  });

  testWidgets('groups in order, each with its count; running is drawn, not counted',
      (tester) async {
    await _pump(
      tester,
      docs: Stream.value([_doc('a', 'error'), _doc('b', 'skipped')]),
      holds: Stream.value(const [
        ImportJob(id: 'j1', provider: 'dropbox', status: 'awaiting_review',
            providerFileName: 'Report.pdf', mimeType: 'application/pdf'),
      ]),
      tasks: Stream.value([
        _task('t1', 'awaiting_review', result: {'scanned': 4, 'shelves': 2, 'proposals': []}),
        _task('t2', 'running', stalls: _later),
      ]),
    );
    expect(find.text('4 WAITING'), findsOneWidget);
    final order = [
      'SOURCES THAT NEED YOU · 2',
      'FILES WAITING TO IMPORT · 1',
      'PROPOSALS · 1',
      'RUNNING · 1',
    ];
    final ys = [for (final e in order) tester.getTopLeft(find.text(e)).dy];
    expect(ys, [...ys]..sort(), reason: 'the spec order');
    expect(find.textContaining('Dropbox'), findsOneWidget,
        reason: 'a held row names its provider here');
    expect(find.text('Dismiss'), findsWidgets);
    await _done(tester);
  });

  group('§22 row actions follow the status', () {
    Future<void> row(WidgetTester tester, BackgroundTask t,
        {List<String>? calls}) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: TaskReviewRow(
            task: t,
            now: _now,
            onReview: (_) => calls?.add('review'),
            resolve: (id, a) async => calls?.add(a),
          ),
        ),
      ));
    }

    testWidgets('waiting: Review beside Dismiss; the proposal is the sentence',
        (tester) async {
      final calls = <String>[];
      await row(
          tester,
          _task('t', 'awaiting_review',
              result: {'scanned': 3, 'shelves': 1, 'proposals': [{'documentId': 'd1', 'tagId': 'x'}]}),
          calls: calls);
      expect(find.text('NEEDS YOU'), findsOneWidget);
      expect(find.text('1 of 3 sources from Misc have a suggested shelf.'), findsOneWidget);
      await tester.tap(find.text('Review'));
      await tester.tap(find.text('Dismiss'));
      await tester.pump();
      expect(calls, ['review', 'dismiss']);
    });

    testWidgets('an apply_error carries Run again', (tester) async {
      await row(tester,
          _task('t', 'awaiting_review', result: {'scanned': 1, 'shelves': 1, 'proposals': []},
              applyError: 'Applying this was interrupted.'));
      expect(find.text('Applying this was interrupted.'), findsOneWidget);
      expect(find.text('Run again'), findsOneWidget);
    });

    testWidgets('failed: Try again and Dismiss, with its sentence', (tester) async {
      await row(tester, _task('t', 'failed', error: 'The shelf could not be deleted.'));
      expect(find.text('FAILED'), findsOneWidget);
      expect(find.text('The shelf could not be deleted.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
    });

    testWidgets('stalled: Try again only', (tester) async {
      await row(tester, _task('t', 'running', stalls: _earlier));
      expect(find.text('STALLED'), findsOneWidget);
      expect(find.text(taskStalledSentence), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Dismiss'), findsNothing);
    });

    testWidgets('running: no strip, no actions', (tester) async {
      await row(tester, _task('t', 'running', stalls: _later));
      expect(find.byType(KitButton), findsNothing);
    });

    testWidgets('an unknown kind is still a row with Dismiss', (tester) async {
      await row(tester, _task('t', 'awaiting_review', kind: 'shelf_merge', result: {'x': 1}));
      expect(find.text('Misc'), findsOneWidget);
      expect(find.text('Review'), findsNothing);
      expect(find.text('Dismiss'), findsOneWidget);
    });
  });

  group('task copy', () {
    test('the proposal lines, per kind', () {
      BackgroundTask k(String kind, Map<String, dynamic> r, [Map<String, dynamic>? params]) =>
          BackgroundTask.fromJson('x', {
            'kind': kind,
            'status': 'awaiting_review',
            'subject': {'title': 'Basketball'},
            'params': params ?? {},
            'result': r,
          });
      expect(proposalLine(k('shelf_backfill', {'scanned': 12, 'candidates': [1, 2, 3]})),
          '3 of your 12 sources look like they belong on Basketball.');
      expect(proposalLine(k('shelf_split', {'parts': [1, 2]})),
          'Basketball could become 2 shelves.');
      expect(
          proposalLine(k('syllabus_plan', {'units': [1], 'assessments': []},
              {'document_title': 'Syllabus.pdf'})),
          '1 topic and 0 assessments read from Syllabus.pdf.');
      expect(proposalLine(k('syllabus_plan', {'units': [], 'assessments': []})),
          'Nothing usable was read from the syllabus.');
      expect(proposalLine(k('reorg_plan', {'sections': [1, 2, 3]})),
          'Basketball could be divided into 3 sections.');
      expect(proposalLine(k('shelf_delete', {'scanned': 5, 'proposals': []})),
          'None of your shelves looked like a clear fit for the sources from Basketball.');
    });

    test('the detail line is measured values only', () {
      final t = BackgroundTask.fromJson('x', {
        'kind': 'shelf_delete',
        'status': 'running',
        'progress': {'phase': 'stripping', 'done': 2, 'total': 9},
      });
      expect(taskDetail(t), 'Deleting a shelf · 2 of 9 sources taken off');
      expect(taskPill(t, _now).$2, 'Deleting');
    });
  });

  testWidgets('the rail attention count: 9+ past nine, the muted dash unmeasured',
      (tester) async {
    expect(kitAttentionLabel(0), isNull);
    expect(kitAttentionLabel(12), '9+');
    expect(kitAttentionLabel(null), '—');
    Future<Color?> pill(bool unmeasured) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            child: KitNavItem(
                icon: Icons.inbox_outlined,
                label: 'For your review',
                badge: unmeasured ? '—' : '3',
                badgeUnmeasured: unmeasured),
          ),
        ),
      ));
      final box = tester.widget<Container>(find
          .ancestor(of: find.text(unmeasured ? '—' : '3'), matching: find.byType(Container))
          .first);
      return (box.decoration as BoxDecoration?)?.color;
    }

    final t = Tokens.light;
    expect(await pill(false), t.chromeAccentBar);
    expect(await pill(true), t.chromeBorder,
        reason: 'a failed read is not work waiting: no accent fill');
  });

  testWidgets('a source row Dismisses only where it is dismissible; a refusal stays on the row',
      (tester) async {
    final calls = <String>[];
    Future<void> mount(bool dismissible) => tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<ActivityNotifier>(create: (_) => StubActivity()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ProcessingRow(
                doc: _doc('a', 'error'),
                dismissible: dismissible,
                dismiss: (id) async {
                  calls.add(id);
                  throw const ApiException(400, 'Unknown document a.');
                },
              ),
            ),
          ),
        ));
    await mount(false);
    expect(find.text('Dismiss'), findsNothing, reason: 'the Library shows every source');
    await mount(true);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pump();
    expect(calls, ['a']);
    expect(find.text('Unknown document a.'), findsOneWidget);
  });
}
