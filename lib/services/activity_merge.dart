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
