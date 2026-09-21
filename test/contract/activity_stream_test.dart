import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/services/activity_merge.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/activity_notifier.dart';

/// **C1's other half — the plumbing, and what a notifier does with it.**
///
/// `activity_failure_test.dart` gates the SCREEN: given an error, §14 is drawn
/// and §7 is not. It cannot gate how the error gets there, because it replaces
/// the notifier with a stub — a test that asserts its own double. The two
/// seams this file uses are what closes that:
///
/// * [mergeActivityStreams] is the fan-in lifted out of the Firestore query,
///   so the rules C1 broke are asserted over two plain streams.
/// * [FirestoreService.instance] is settable, so [ActivityNotifier] can be
///   started against a stream that fails on command and the REAL notifier body
///   runs.
///
/// Neither seam makes a fake Firestore. The query itself — that a
/// permission-denied snapshot arrives as a stream error at all — is still the
/// device run's, and saying so is the point: an unstated gap reads as coverage.

class _StubService extends FirestoreService {
  _StubService(this.activity) : super.stub();

  final Stream<List<ActivityItem>> activity;
  int subscribed = 0;

  @override
  String? get currentUid => 'u1';

  @override
  Stream<List<ActivityItem>> subscribeActivity({int maxItems = 100}) {
    subscribed++;
    return activity;
  }
}

ActivityItem _event(String id, {int at = 2}) => ActivityItem(
      kind: 'event',
      id: id,
      type: 'document_added',
      status: 'success',
      level: 'info',
      title: 'event $id',
      createdAt: at,
    );

ActivityItem _doc(String id, {int at = 1}) => ActivityItem(
      kind: 'document',
      id: id,
      type: 'pdf',
      status: 'ready',
      level: 'info',
      title: 'doc $id',
      createdAt: at,
    );

void main() {
  group('mergeActivityStreams', () {
    late StreamController<List<ActivityItem>> events;
    late StreamController<List<ActivityItem>> docs;

    setUp(() {
      events = StreamController<List<ActivityItem>>();
      docs = StreamController<List<ActivityItem>>();
    });

    test('an error on either half ERRORS the merged stream', () async {
      final seen = <Object>[];
      mergeActivityStreams(events: events.stream, documents: docs.stream)
          .listen(seen.add, onError: seen.add);

      events.addError(StateError('permission-denied'));
      await pumpEventQueue();

      expect(seen.single, isA<StateError>(),
          reason: 'it answered `const []` — the empty library, said by the '
              'one path that never read it');
    });

    test('and the OTHER half is what makes it terminal', () async {
      final seen = <Object>[];
      mergeActivityStreams(events: events.stream, documents: docs.stream)
          .listen(seen.add, onError: seen.add);

      events.addError(StateError('permission-denied'));
      await pumpEventQueue();
      docs.add([_doc('d1')]);
      await pumpEventQueue();

      expect(seen.length, 1,
          reason: 'a feed quietly missing every event, with nothing on '
              'screen to say which half is gone, is worse than no feed');
      expect(events.hasListener, isFalse);
      expect(docs.hasListener, isFalse);
    });

    test('nothing is emitted until BOTH halves have spoken', () async {
      final seen = <List<ActivityItem>>[];
      mergeActivityStreams(events: events.stream, documents: docs.stream)
          .listen(seen.add);

      events.add([_event('e1')]);
      await pumpEventQueue();
      expect(seen, isEmpty,
          reason: 'a first frame built from one half is a feed that is '
              'briefly and confidently wrong');

      docs.add([_doc('d1')]);
      await pumpEventQueue();
      expect(seen.single.map((i) => i.id), ['e1', 'd1']);
    });

    test('later snapshots keep merging', () async {
      final seen = <List<ActivityItem>>[];
      mergeActivityStreams(events: events.stream, documents: docs.stream)
          .listen(seen.add);

      events.add([_event('e1')]);
      docs.add([_doc('d1')]);
      await pumpEventQueue();
      events.add([_event('e1'), _event('e2', at: 3)]);
      await pumpEventQueue();

      expect(seen.length, 2);
      expect(seen.last.map((i) => i.id), ['e2', 'e1', 'd1']);
    });
  });

  group('ActivityNotifier against a failing subscription', () {
    tearDown(FirestoreService.resetInstance);

    test('a stream error becomes the error state, with the server sentence',
        () async {
      final source = StreamController<List<ActivityItem>>.broadcast();
      FirestoreService.instance = _StubService(source.stream);

      final n = ActivityNotifier()..start();
      source.addError(StateError('permission-denied'));
      await pumpEventQueue();

      expect(n.error, contains('permission-denied'),
          reason: "§14 PARTS — the block draws this UNDER a sentence of ours, "
              'so a constant here quotes nothing');
      expect(n.isLoading, isFalse);
    });

    test('and Retry can actually re-subscribe', () async {
      final first = StreamController<List<ActivityItem>>.broadcast();
      final stub = _StubService(first.stream);
      FirestoreService.instance = stub;

      final n = ActivityNotifier()..start();
      expect(stub.subscribed, 1);

      first.addError(StateError('unavailable'));
      await pumpEventQueue();

      await n.refresh();
      expect(stub.subscribed, 2,
          reason: '`start` is idempotent on `_sub` and the subscription '
              'survives its own error, so leaving it in place made Retry a '
              'control that does nothing and says nothing');
    });

    test('a recovered feed clears the error', () async {
      final source = StreamController<List<ActivityItem>>.broadcast();
      FirestoreService.instance = _StubService(source.stream);

      final n = ActivityNotifier()..start();
      source.add([_event('e1')]);
      await pumpEventQueue();

      expect(n.error, isNull);
      expect(n.items.single.id, 'e1');
    });
  });
}
