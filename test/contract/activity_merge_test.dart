import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/activity_item.dart';
import 'package:flutter_app/services/activity_merge.dart';
import 'fixtures.dart';

/// activity-merge (INV-02, INV-06): the extracted pure mergeActivity over the
/// captured activity_events + documents inputs must produce the same feed
/// ORDER and coverage as the reference. (Full item-field equality is a
/// catch-up target; ordering + doc-coverage is the core INV-02 property.)
ActivityItem _event(String id, Map<String, dynamic> d) => ActivityItem(
      kind: 'event', id: id, type: d['type'] ?? '', status: d['status'] ?? '',
      title: d['title'] ?? '', provider: d['provider'],
      metadata: (d['metadata'] as Map?)?.cast<String, dynamic>(),
      createdAt: d['created_at'] is int ? d['created_at'] as int : null);

ActivityItem _doc(String id, Map<String, dynamic> d) => ActivityItem(
      kind: 'document', id: id, type: d['type'] ?? '', status: d['status'] ?? '',
      title: d['title'] ?? 'Untitled', createdAt:
          d['created_at'] is int ? d['created_at'] as int : null);

void main() {
  final suite = loadSuite('activity-merge');

  test('activity-merge suite is captured', () => expect(suite, isNotNull));

  for (final c in (suite?['cases'] as List? ?? [])) {
    test(c['id'], () {
      final req = c['request'] as Map<String, dynamic>;
      final events = [
        for (final e in req['events_input'])
          _event(e['id'], (decode(e['data']) as Map).cast<String, dynamic>())
      ];
      final docs = [
        for (final d in req['documents_input'])
          _doc(d['id'], (decode(d['data']) as Map).cast<String, dynamic>())
      ];
      final merged = mergeActivity(events, docs,
          maxItems: req['max_items'] as int? ?? 100);

      final expectedItems = (c['response']['body']['items'] as List);
      expect(merged.length, expectedItems.length);
      expect([for (final m in merged) m.id],
          [for (final e in expectedItems) e['id']]);
    });
  }
}
