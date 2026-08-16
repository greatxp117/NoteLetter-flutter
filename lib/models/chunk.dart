import 'document.dart' show tsMs;

/// `/chunks/{chunkId}` — `embedding` (1536-dim vector) is ALWAYS stripped
/// client-side (INV-05), never rendered/cached/re-written. `html`/`userEdited`
/// are populated by direct reader reads; `fn_search_notes` responses omit them.
class Chunk {
  final String chunkId;
  final String documentId;
  final int chunkIndex;
  final String text;
  final String? html;
  final String sourceType;
  final double? sourcePriority;
  final bool userEdited;
  final int? createdAt;

  /// INV-03b — READ. Since 4.0.0 bumped by `chunk_read` ONLY, so reading
  /// coverage means passages actually read and can no longer be moved by a
  /// newsletter delivery or a search glance.
  final int viewCount;
  final int? lastViewedAt;

  /// 4.0.0 (ADR-039 §Amendment) — bumped by exactly `chunk_viewed`: expanding
  /// this passage out of a search result or an Ask citation. **Absent on every
  /// pre-4.0.0 chunk; absent means 0, never unknown.**
  final int searchViewCount;

  /// 2.24.0 — stamped by the newsletter build. This IS the newsletter-exposure
  /// record (what `excludeRecentDays` reads); `chunk_newsletter_included` moves
  /// no counter, so do not expect one.
  final int? lastIncludedInNewsletter;

  /// 2.35.0 (ADR-034) — the reader's explicit per-chunk shelf deviations,
  /// `{added: [tagId], removed: [tagId]}`, written only by
  /// `fn_update_chunk_tags`. A chunk INHERITS its document's shelves; effective
  /// shelves are computed at read as `(document.tag_ids - removed) + added`,
  /// never stored, because a stored list goes stale the moment the document's
  /// shelves change. Dangling ids are inert, never an error.
  final Map<String, dynamic>? tagOverrides;

  const Chunk({
    required this.chunkId,
    required this.documentId,
    required this.chunkIndex,
    required this.text,
    this.html,
    required this.sourceType,
    this.sourcePriority,
    this.userEdited = false,
    this.createdAt,
    this.viewCount = 0,
    this.lastViewedAt,
    this.searchViewCount = 0,
    this.lastIncludedInNewsletter,
    this.tagOverrides,
  });

  factory Chunk.fromJson(Map<String, dynamic> json) {
    return Chunk(
      chunkId: json['chunk_id'] as String? ?? '',
      documentId: json['document_id'] as String? ?? '',
      chunkIndex: json['chunk_index'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      html: json['html'] as String?,
      sourceType: json['source_type'] as String? ?? 'unknown',
      sourcePriority: (json['source_priority'] as num?)?.toDouble(),
      userEdited: json['user_edited'] as bool? ?? false,
      createdAt: tsMs(json['created_at']),
      viewCount: json['view_count'] as int? ?? 0,
      lastViewedAt: tsMs(json['last_viewed_at']),
      // Absent on every pre-4.0.0 chunk — absent means 0.
      searchViewCount: json['search_view_count'] as int? ?? 0,
      lastIncludedInNewsletter: tsMs(json['last_included_in_newsletter']),
      tagOverrides:
          (json['tag_overrides'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
