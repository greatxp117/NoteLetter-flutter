import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/state/activity_notifier.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The rail's unread badge (`spec/screens/activity.md` §Toasts and unread,
/// 2.5.0/ADR-014).
///
/// The badge itself is furniture, but the RULE behind it is contract: which
/// items count, what a null timestamp means, and what the reader is told when
/// there are more than the pill can hold. Each of those is a place the three
/// clients could quietly disagree, and none of them is visible to the merge
/// suite — `mergeActivity` is asked what the feed contains, never what of it
/// is new.
ActivityItem _item(String kind, int? createdAt, {String id = 'x'}) =>
    ActivityItem(
      kind: kind,
      id: id,
      type: 'doc_indexed',
      status: 'complete',
      level: 'info',
      title: 'A source',
      createdAt: createdAt,
    );

void main() {
  group('unread = events newer than last seen', () {
    test('counts only what arrived after the mark', () {
      final items = [
        _item('event', 300, id: 'a'),
        _item('event', 200, id: 'b'),
        _item('event', 100, id: 'c'),
      ];
      expect(activityUnread(items, 0), 3);
      expect(activityUnread(items, 150), 2);
      expect(activityUnread(items, 300), 0);
    });

    test('the mark is exclusive — an event AT it has been seen', () {
      // The feed marks itself with the newest event it is showing, so that
      // event is on screen by definition. A `>=` here would re-count it on
      // every visit and leave a badge nothing can clear.
      expect(activityUnread([_item('event', 200)], 200), 0);
      expect(activityUnread([_item('event', 201)], 200), 1);
    });

    test('document rows never count', () {
      // The merge's document half is the fallback for documents that predate
      // the events feature. Counting them would badge a library that has
      // simply never produced an event, permanently: nothing new ever arrives
      // to clear a row that is older than the feature.
      final items = [
        _item('document', 900, id: 'd1'),
        _item('document', 800, id: 'd2'),
        _item('event', 700, id: 'e1'),
      ];
      expect(activityUnread(items, 0), 1);
    });

    test('a null created_at is 0, not now', () {
      // INV-06's null-safe order treats a missing timestamp as oldest; an item
      // that sorts oldest cannot be the news. Read as "now" it would be
      // permanently unread instead.
      expect(activityUnread([_item('event', null)], 0), 0);
    });
  });

  group('the badge label', () {
    test('caps at 9+', () {
      expect(kitBadgeLabel(1), '1');
      expect(kitBadgeLabel(9), '9');
      expect(kitBadgeLabel(10), '9+');
      expect(kitBadgeLabel(127), '9+');
    });
  });

  group('the mark the feed writes', () {
    test('is the newest EVENT on screen, and 0 when there is none', () {
      final n = ActivityNotifier();
      expect(n.newestEventAt, 0);
      expect(n.unreadSince(0), 0);
    });
  });
}
