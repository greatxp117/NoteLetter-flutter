// screens/review.md §The needs-decision set (INV-30) and §Data, mirroring the
// reference's useReviewInbox (web tests/contract/review-inbox.test.js): one
// arithmetic for the rail's count and the page's rows, unmeasured whenever a
// part has not answered or has failed, and never a partial count.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/background_task.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/models/organization_suggestion.dart';
import 'package:flutter_app/state/review_inbox.dart';

final _now = DateTime.fromMillisecondsSinceEpoch(1800000000000);
final _past = _now.millisecondsSinceEpoch - 1000;
final _future = _now.millisecondsSinceEpoch + 60000;

Document _doc(String id, String status, {int? stalls, int? dismissed}) =>
    Document.fromJson(id, {
      'user_id': 'u',
      'title': id,
      'type': 'pdf',
      'status': status,
      'processing_stalls_at': stalls,
      'review_dismissed_at': dismissed,
    });

BackgroundTask _task(String id, String status, {int? stalls, String kind = 'shelf_delete'}) =>
    BackgroundTask.fromJson(id, {
      'kind': kind,
      'status': status,
      'stalls_at': stalls,
      'subject': {'type': 'shelf', 'id': 't', 'title': 'Misc'},
    });

const _job = ImportJob(id: 'j1', provider: 'google_drive', status: 'awaiting_review');
const _sugg = OrganizationSuggestion(
    id: 's1', provider: 'google_drive', type: 'move', confidence: 0.9, reason: '', status: 'pending');

InboxView _view({
  List<Document> docs = const [],
  List<ImportJob> holds = const [],
  List<OrganizationSuggestion> suggestions = const [],
  List<BackgroundTask> tasks = const [],
  String? docsError,
  bool tasksLoaded = true,
}) =>
    InboxView.compute(
      docs: InboxPart(data: docs, loaded: true, error: docsError),
      holds: InboxPart(data: holds, loaded: true),
      suggestions: InboxPart(data: suggestions, loaded: true),
      tasks: InboxPart(data: tasks, loaded: tasksLoaded),
      now: _now,
    );

void main() {
  group('sources that need you', () {
    test('error and skipped are in; a fresh processing run is not', () {
      expect(sourceNeedsReview(_doc('a', 'error'), _now), isTrue);
      expect(sourceNeedsReview(_doc('b', 'skipped'), _now), isTrue);
      expect(sourceNeedsReview(_doc('c', 'processing', stalls: _future), _now), isFalse);
      expect(sourceNeedsReview(_doc('d', 'processing'), _now), isFalse,
          reason: 'absent is not stalled');
    });

    test('a stalled run is in; a dismissed failure is out', () {
      expect(sourceNeedsReview(_doc('a', 'processing', stalls: _past), _now), isTrue);
      expect(sourceNeedsReview(_doc('b', 'error', dismissed: _past), _now), isFalse);
    });
  });

  group('tasks', () {
    test('waiting, failed and stalled are proposals; running is drawn, not counted', () {
      final v = _view(tasks: [
        _task('t1', 'awaiting_review'),
        _task('t2', 'failed'),
        _task('t3', 'running', stalls: _past),
        _task('t4', 'running', stalls: _future),
        _task('t5', 'queued'),
      ]);
      expect(v.proposals.map((t) => t.id), ['t1', 't2', 't3']);
      expect(v.running.map((t) => t.id), ['t4', 't5']);
      expect(v.count, 3);
    });

    test('an unknown kind is still counted', () {
      expect(_view(tasks: [_task('t', 'awaiting_review', kind: 'shelf_merge')]).count, 1);
    });
  });

  group('the count', () {
    test('is the size of exactly the set', () {
      final v = _view(
        docs: [_doc('a', 'error'), _doc('b', 'processing', stalls: _future)],
        holds: [_job],
        suggestions: [_sugg],
        tasks: [_task('t1', 'awaiting_review')],
      );
      expect(v.count, 4);
      expect(v.countText, '4');
      expect(v.empty, isFalse);
    });

    test('is unmeasured until every part answered, and when any failed', () {
      expect(_view(tasksLoaded: false).count, isNull);
      final failed = _view(docsError: 'Permission denied.', holds: [_job]);
      expect(failed.count, isNull, reason: 'never the parts that loaded');
      expect(failed.countText, isNull);
      expect(failed.empty, isFalse, reason: 'a failure is never an empty state');
    });

    test('at the read limit it reads 500+, never 500', () {
      final many = [for (var i = 0; i < reviewReadLimit; i++) _doc('d$i', 'error')];
      expect(_view(docs: many).countText, '$reviewReadLimit+');
    });

    test('empty only when nothing waits, nothing runs and nothing failed', () {
      expect(_view().empty, isTrue);
      expect(_view(tasks: [_task('t', 'running', stalls: _future)]).empty, isFalse);
    });
  });

  group('the notifier', () {
    test('opens four subscriptions once; a failed part makes the count unmeasured; '
        'retry opens them again', () async {
      final opens = <String, int>{};
      final ctl = <String, StreamController>{};
      Stream<List<T>> open<T>(String k) {
        opens[k] = (opens[k] ?? 0) + 1;
        final c = StreamController<List<T>>();
        ctl[k] = c;
        return c.stream;
      }

      final inbox = ReviewInbox(
        docs: () => open<Document>('docs'),
        holds: () => open<ImportJob>('holds'),
        suggestions: () => open<OrganizationSuggestion>('sugg'),
        tasks: () => open<BackgroundTask>('tasks'),
        clock: () => _now,
      );
      inbox.start();
      inbox.start();
      expect(opens, {'docs': 1, 'holds': 1, 'sugg': 1, 'tasks': 1});
      expect(inbox.view.count, isNull);

      (ctl['docs'] as StreamController<List<Document>>).add([_doc('a', 'error')]);
      (ctl['holds'] as StreamController<List<ImportJob>>).add(const []);
      (ctl['sugg'] as StreamController<List<OrganizationSuggestion>>).add(const []);
      (ctl['tasks'] as StreamController<List<BackgroundTask>>).add(const []);
      await Future<void>.delayed(Duration.zero);
      expect(inbox.view.count, 1);

      ctl['holds']!.addError(Exception('denied'));
      await Future<void>.delayed(Duration.zero);
      expect(inbox.view.count, isNull);
      expect(inbox.view.holdsError, isNotNull);
      expect(inbox.view.sources, hasLength(1), reason: 'the other groups still render');

      inbox.retry();
      expect(opens, {'docs': 2, 'holds': 2, 'sugg': 2, 'tasks': 2});
      expect(inbox.view.count, isNull);
      inbox.dispose();
    });
  });
}
