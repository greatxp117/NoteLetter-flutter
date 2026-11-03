import '../models/activity_item.dart';
import '../models/chunk.dart';

/// A source's History (5.44.0, ADR-199; reader.md §History): the rows its two
/// reads become. Ported from the web reference `src/shared/sourceHistory.js`;
/// the reads themselves are [FirestoreService.getReadHistory] and
/// [FirestoreService.subscribeSourceActivity].

/// Each read is limited to this many rows. A half that returns all of them is
/// a WINDOW and the panel says so; neither is ever a total.
const sourceHistoryLimit = 50;

/// One entry per contracted read `event_type` (data-model.md §/read_events),
/// and the reference's neutral `Activity` for anything else. `chunk_read` and
/// `doc_finished` (3.1.0) were missing once, so this panel drew the raw token
/// `chunk_read (Passage 2)`. Read and viewed never share wording (ADR-039).
const historyEventLabels = {
  'doc_opened': 'Opened the source',
  'chunk_read': 'Read a passage',
  'chunk_viewed': 'Viewed a passage',
  'chunk_newsletter_included': 'Pulled into a letter',
  'doc_finished': 'Marked as finished',
};

String historyEventLabel(Object? eventType) =>
    historyEventLabels[eventType] ?? 'Activity';

/// The Activity types whose writer puts `doc_id` in metadata, and their
/// labels: the prototype's sentence where it names a real type; the Activity
/// feed's chip for the three whose `title` is the document's own name; and,
/// for the four whose title names the act (the organizer's and the
/// import's), the title itself. Chosen by TYPE, never by comparing a title
/// with the source's — that is a title match one step removed.
const sourceEventLabels = {
  'doc_indexed': 'Indexed into your library',
  'doc_processing_note': 'Note',
  'doc_processing_failed': 'Processing failed',
  'doc_indexing_failed': 'Indexing failed',
  'doc_skipped': 'Skipped at import',
  // 5.50.0 (ADR-202): written on the ORIGINAL when the same picture came in
  // again; its `note` (the detail line) says from where.
  'doc_duplicate': 'Added again',
  'doc_cancelled': 'Cancelled',
  'article_resolved': 'Article found',
  'organization_move': 'Moved in your cloud folder',
};
const sourceEventTitled = {
  'cloud_sync_failed',
  'organization_placement',
  'organization_error',
  'reorg_executed',
};

String sourceEventLabel(ActivityItem e) {
  final fixed = sourceEventLabels[e.type];
  if (fixed != null) return fixed;
  if (sourceEventTitled.contains(e.type) && e.title.isNotEmpty) return e.title;
  return 'Activity';
}

/// One row of the History, from either half.
class HistoryRow {
  final String id;

  /// `reading` or `activity`.
  final String origin;

  /// A reading row that names a passage (the search glyph, not the eye).
  final bool chunk;
  final String level;
  final String label;
  final String? detail;
  final int? createdAt;

  const HistoryRow({
    required this.id,
    required this.origin,
    required this.chunk,
    required this.level,
    required this.label,
    required this.detail,
    required this.createdAt,
  });

  bool get isActivity => origin == 'activity';
}

class SourceHistory {
  final List<HistoryRow> rows;

  /// Each half that returned its whole limit: the most recent N, not a total.
  final bool readingWindow;
  final bool activityWindow;

  const SourceHistory(this.rows,
      {required this.readingWindow, required this.activityWindow});
}

/// The reading half and the Activity half, each mapped to one row shape and
/// interleaved newest first. An Activity event belongs to the source by
/// `metadata.doc_id` and nothing else — the query already says so; this says
/// it again so no caller can hand in the account's feed and get a title match
/// back. A null half is one that failed.
SourceHistory sourceHistory({
  required String docId,
  List<Map<String, dynamic>>? reads,
  List<ActivityItem>? activity,
  List<Chunk> chunks = const [],
  int limit = sourceHistoryLimit,
}) {
  String? passageOf(String? chunkId) {
    if (chunkId == null) return null;
    for (final c in chunks) {
      if (c.chunkId == chunkId) return 'Passage ${c.chunkIndex + 1}';
    }
    return null;
  }

  final readList = reads ?? const <Map<String, dynamic>>[];
  final actList = activity ?? const <ActivityItem>[];
  final rows = <HistoryRow>[
    for (final e in readList)
      () {
        final chunkId = e['chunk_id'] as String?;
        final base = historyEventLabel(e['event_type']);
        final passage = passageOf(chunkId);
        return HistoryRow(
          id: 'read-${e['id']}',
          origin: 'reading',
          chunk: chunkId != null,
          level: 'info',
          label: passage != null ? '$base ($passage)' : base,
          detail: null,
          createdAt: e['created_at'] as int?,
        );
      }(),
    for (final e in actList)
      if (docId.isNotEmpty && e.metadata?['doc_id'] == docId)
        HistoryRow(
          id: 'act-${e.id}',
          origin: 'activity',
          chunk: false,
          level: e.level.isEmpty ? 'info' : e.level,
          label: sourceEventLabel(e),
          // ADR-105's closed pair, as the Activity feed reads it.
          detail: _sentence(e.metadata?['note']) ?? _sentence(e.metadata?['error']),
          createdAt: e.createdAt,
        ),
  ];
  // Stable, newest first: Dart's List.sort is not stable, so the index breaks
  // ties the way the reference's Array.prototype.sort (stable) does.
  final indexed = rows.asMap().entries.toList()
    ..sort((a, b) {
      final c = (b.value.createdAt ?? 0).compareTo(a.value.createdAt ?? 0);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return SourceHistory(
    [for (final e in indexed) e.value],
    readingWindow: readList.length >= limit,
    activityWindow: actList.length >= limit,
  );
}

String? _sentence(Object? v) => v is String && v.isNotEmpty ? v : null;
