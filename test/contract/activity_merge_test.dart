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
      // Through eventLevel, exactly as firestore_service does — NOT the model
      // default. Until 4.42.0 this helper omitted `level` entirely, so every
      // event in this test carried 'info' and the field was unasserted: the
      // suite was green while the client drew 53 prod errors as ordinary rows.
      level: ActivityItem.eventLevel(
          d['level'] as String?, d['status'] as String?),
      title: d['title'] ?? '', provider: d['provider'],
      metadata: (d['metadata'] as Map?)?.cast<String, dynamic>(),
      createdAt: d['created_at'] is int ? d['created_at'] as int : null);

ActivityItem _doc(String id, Map<String, dynamic> d) => ActivityItem(
      kind: 'document', id: id, type: d['type'] ?? '', status: d['status'] ?? '',
      // Through docLevel, exactly as firestore_service does. Omitting it here
      // took the model default and made a completed document read 'info' — the
      // document half of the same unasserted-severity gap (4.42.0).
      level: ActivityItem.docLevel(d['status'] as String? ?? ''),
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

      // Severity, against the captured expectation. The seed carries
      // `seed-event-legacy-error` in the real pre-2.5.0 shape — no `level` key
      // at all, `status: "error"` — which is what 279 of the 497 events in prod
      // look like, 53 of them errors. A client that defaults to 'info' instead
      // of deriving from `status` fails here (4.42.0, ADR-080).
      expect([for (final m in merged) m.level],
          [for (final e in expectedItems) e['level']]);
    });
  }
}
