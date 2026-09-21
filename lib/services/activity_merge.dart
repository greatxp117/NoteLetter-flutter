import 'dart:async';

import '../models/activity_item.dart';

/// Canonical activity-feed merge (INV-02, spec/screens/activity.md): the
/// activity_events plus the documents not already covered by an event's
/// `metadata['doc_id']`, sorted by `createdAt` descending, capped at
/// [maxItems]. Pure so it is unit-testable without a live Firestore
/// (contract harness: test/contract/activity_merge_test.dart).
List<ActivityItem> mergeActivity(
  List<ActivityItem> events,
  List<ActivityItem> docs, {
  int maxItems = 100,
}) {
  final coveredDocIds = events
      .map((e) => e.metadata?['doc_id'] as String?)
      .whereType<String>()
      .toSet();
  final combined = [
    ...events,
    ...docs.where((d) => !coveredDocIds.contains(d.id)),
  ]..sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
  return combined.take(maxItems).toList();
}

/// The fan-in the feed is actually built from: two live halves, one merged
/// stream, and one rule about what a failure does to it.
///
/// Separated from [FirestoreService.subscribeActivity] because this is where
/// C1 lived, and a Firestore query is exactly the part that cannot be pumped
/// in a widget test — there is no Firebase app in one and this client has no
/// fake Firestore, so for as long as the plumbing sat inside the query it was
/// gated by nothing. Over two plain streams it is an ordinary unit test
/// (`test/contract/activity_stream_test.dart`).
///
/// Three rules, and each of them was a defect once:
///
/// * **An error on either half errors the merged stream.** Both halves used to
///   answer `controller.add(const [])` — the empty library, said by the one
///   path that never read it — so `ActivityNotifier`'s `onError` was dead code
///   and the screen drew its §7 empty state on a rules or index failure.
/// * **It is terminal.** A snapshot error here is permission-denied or a
///   missing index, neither of which clears on the next tick; letting the
///   surviving half go on emitting draws a feed quietly missing every event,
///   or every document, with nothing on screen to say which. A merge of two
///   sources is only as true as its thinner half.
/// * **Nothing is emitted before both halves have spoken.** A first frame
///   built from one half is a feed that is briefly and confidently wrong, and
///   [mergeActivity]'s whole job — dropping the documents an event already
///   covers — cannot be done with half its input.
Stream<List<ActivityItem>> mergeActivityStreams({
  required Stream<List<ActivityItem>> events,
  required Stream<List<ActivityItem>> documents,
  int maxItems = 100,
}) {
  final controller = StreamController<List<ActivityItem>>.broadcast();
  List<ActivityItem>? eventRows;
  List<ActivityItem>? docRows;
  late final StreamSubscription<List<ActivityItem>> eventsSub;
  late final StreamSubscription<List<ActivityItem>> docsSub;
  var failed = false;

  void emitMerged() {
    if (failed || eventRows == null || docRows == null) return;
    controller.add(mergeActivity(eventRows!, docRows!, maxItems: maxItems));
  }

  void fail(Object e, StackTrace st) {
    if (failed) return;
    failed = true;
    controller.addError(e, st);
    eventsSub.cancel();
    docsSub.cancel();
  }

  eventsSub = events.listen((rows) {
    eventRows = rows;
    emitMerged();
  }, onError: fail);
  docsSub = documents.listen((rows) {
    docRows = rows;
    emitMerged();
  }, onError: fail);

  controller.onCancel = () {
    eventsSub.cancel();
    docsSub.cancel();
  };

  return controller.stream;
}
