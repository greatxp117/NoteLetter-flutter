// The merged activity feed's first list is the WHOLE feed (round 3, item 2;
// web `toast-host-resubscribe.test.js`, TODO L3165). The feed is two listeners
// merged, the events and the documents. Web's merge called back on each, so
// its first callbacks carried only the half that had answered, and the toast
// host filed the late half as news: every old document toasted on load. This
// client's `mergeActivityStreams` emits nothing until BOTH have answered, so a
// consumer priming on its first list primes on the whole feed. This client
// has no toast host today; the rule is held here so one built later inherits
// it.
//
// Mutant run against it (red): emitting as soon as either listener answers.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/services/activity_merge.dart';

ActivityItem _item(String id, String kind) => ActivityItem(
    kind: kind,
    id: id,
    type: 'x',
    status: 'complete',
    title: id,
    createdAt: 1);

void main() {
  test('nothing is emitted until both listeners have answered', () async {
    final events = StreamController<List<ActivityItem>>();
    final docs = StreamController<List<ActivityItem>>();
    final got = <List<ActivityItem>>[];
    final sub = mergeActivityStreams(events: events.stream, documents: docs.stream)
        .listen(got.add);
    events.add([_item('e1', 'event')]);
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty, reason: 'half a feed is not the backlog');
    docs.add([_item('d1', 'document')]);
    await Future<void>.delayed(Duration.zero);
    expect(got, hasLength(1));
    expect(got.single.map((i) => i.id).toSet(), {'e1', 'd1'});
    await sub.cancel();
    await events.close();
    await docs.close();
  });
}
