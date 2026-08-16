import 'package:cloud_firestore/cloud_firestore.dart';

enum DocumentStatus {
  pendingUpload,
  queued,
  processing,
  complete,
  error,
  skipped;

  static DocumentStatus fromString(String? s) {
    switch (s) {
      case 'pending_upload':
        return DocumentStatus.pendingUpload;
      case 'queued':
        return DocumentStatus.queued;
      case 'processing':
        return DocumentStatus.processing;
      case 'complete':
        return DocumentStatus.complete;
      case 'skipped':
        return DocumentStatus.skipped;
      default:
        return DocumentStatus.error;
    }
  }
}

/// Epoch-ms conversion at the read boundary (INV-06) — null-safe, never
/// passes a raw Firestore Timestamp into UI/state.
int? tsMs(dynamic value) {
  if (value == null) return null;
  if (value is Timestamp) return value.millisecondsSinceEpoch;
  if (value is int) return value;
  return null;
}

/// `/documents/{docId}` — field skeleton per contract data-model.md.
/// `embedding` is not a document field (only chunks carry it); nothing to
/// strip here (INV-05 applies to chunk/tag reads).
///
/// Tags are read from `tag_ids` (data-model.md) — the 1.0.0 spec named this
/// `tags`, which was extraction drift; the backend has always written
/// `tag_ids`. Docs created before 1.1.0 also carry a vestigial empty `tags`
/// field, so reading `tags` would drop their real tags — read `tag_ids` only.
///
/// Deliberately absent: `display_html` (1.1.0, ADR-002 — no longer stored;
/// clients assemble reading content from chunks) and `questions` (1.5.0,
/// ADR-008 — deprecated; summaries are free-structured prose, no client
/// renders "Questions to consider").
class Document {
  final String id;
  final String userId;
  final String title;
  final String type;
  final String? mimeType;
  final DocumentStatus status;
  final String? sourceUrl;
  final String? gcsPath;
  final int? createdAt;
  final int? processedAt;
  final int? chunkCount;
  final int? wordCount;
  final String? summary;
  final List<String> keyPoints;
  final List<String> themes;
  final List<String> tagIds;
  final String? thumbnailUrl;

  /// podcast only (2.7.0, ADR-016): the resolved RSS `<enclosure>` MP3 URL, so
  /// the reader can play the real episode against the transcript's real
  /// timestamps. Null for every other type and every pre-2.7.0 doc.
  final String? sourceAudioUrl;

  /// article-from-screenshot only (2.8.0, ADR-017): a durable, directly
  /// renderable URL to the captured screenshot, carried as the document's
  /// SECOND source alongside [sourceUrl]. Provenance, not content — never in
  /// chunk HTML. Null for every other document and every pre-2.8.0 doc.
  final String? sourceImageUrl;

  /// 2.13.0 (ADR-020) — the source's own byline. Extracted on every URL ingest
  /// since 1.0.0 and persisted by nobody until 2.13.0, so null on every older
  /// document and on every source with no byline (pdf/docx/image/plain).
  final String? author;

  /// 2.13.0 — an ISO `YYYY-MM-DD` **string**, deliberately NOT a Timestamp:
  /// INV-06 does not apply. It is the source's claim about itself, not an
  /// instant we observed, and converting it renders an article published
  /// "January 3" as "January 2" for every reader west of UTC. Format it as a
  /// calendar date with no timezone conversion, and never substitute
  /// [createdAt] — "when you saved it" and "when it was published" differ.
  final String? publishDate;

  /// 2.19.0 (ADR-024) — which half of the pipeline is running. Meaningful ONLY
  /// while [status] is processing, cleared at every terminal write. Open
  /// vocabulary (`extraction` | `embedding` today): render an unknown value
  /// neutrally, never as an error, and never render the raw token to a user.
  final String? processingStage;

  /// 3.1.0 (ADR-039) — the reader finished this document. Written ONLY by
  /// `fn_set_read_state`, never by a client, and reversible. Deliberately not
  /// derivable from chunk coverage: reading every passage and declaring
  /// yourself done are different claims, and only the second is reversible.
  final int? finishedAt;

  /// 2.31.2 (ADR-032, INV-16) — the reader pinned this source for the next
  /// letter. A Timestamp rather than a boolean so overflow beyond the per-letter
  /// cap is carried oldest-first rather than dropped. Cleared only by a letter
  /// that actually carried the document.
  final int? nextLetterRequestedAt;

  final String? errorMessage;
  final double sourcePriority;

  /// INV-03a — OPENED. Bumped by `doc_opened` and, since 4.0.0, by nothing
  /// else: expanding a search hit no longer clears a source's unread dot.
  final int viewCount;
  final int? lastViewedAt;

  /// `{ job_id, provider }` when this document was imported from a cloud
  /// provider (data-model.md). Drives the Reader source-freshness check (1.4.0).
  final Map<String, dynamic>? sourceIntegration;

  const Document({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.status,
    this.mimeType,
    this.sourceUrl,
    this.gcsPath,
    this.createdAt,
    this.processedAt,
    this.chunkCount,
    this.wordCount,
    this.summary,
    this.keyPoints = const [],
    this.themes = const [],
    this.tagIds = const [],
    this.thumbnailUrl,
    this.sourceAudioUrl,
    this.sourceImageUrl,
    this.author,
    this.publishDate,
    this.processingStage,
    this.finishedAt,
    this.nextLetterRequestedAt,
    this.errorMessage,
    this.sourcePriority = 0.5,
    this.viewCount = 0,
    this.lastViewedAt,
    this.sourceIntegration,
  });

  /// Apply an `fn_regenerate_summary` response (4.3.0, ADR-040).
  ///
  /// Deliberately narrow rather than a general `copyWith`: regeneration moves
  /// **exactly** `summary`, `key_points` and `themes`. The title never changes
  /// (it ripples into lists, letters and activity), and neither do passages,
  /// shelves or any counter. A general copyWith here would make it possible to
  /// carry a field the endpoint never returned, and the reader document is a
  /// one-shot fetch with no subscription to correct it.
  Document withRegeneratedSummary(Map<String, dynamic> res) {
    return Document(
      id: id,
      userId: userId,
      title: title,
      type: type,
      status: status,
      mimeType: mimeType,
      sourceUrl: sourceUrl,
      gcsPath: gcsPath,
      createdAt: createdAt,
      processedAt: processedAt,
      chunkCount: chunkCount,
      wordCount: wordCount,
      summary: res['summary'] as String? ?? summary,
      keyPoints: (res['keyPoints'] as List?)?.cast<String>() ?? keyPoints,
      themes: (res['themes'] as List?)?.cast<String>() ?? themes,
      tagIds: tagIds,
      thumbnailUrl: thumbnailUrl,
      sourceAudioUrl: sourceAudioUrl,
      sourceImageUrl: sourceImageUrl,
      author: author,
      publishDate: publishDate,
      processingStage: processingStage,
      finishedAt: finishedAt,
      nextLetterRequestedAt: nextLetterRequestedAt,
      errorMessage: errorMessage,
      sourcePriority: sourcePriority,
      viewCount: viewCount,
      lastViewedAt: lastViewedAt,
      sourceIntegration: sourceIntegration,
    );
  }

  factory Document.fromJson(String id, Map<String, dynamic> json) {
    return Document(
      id: id,
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'unknown',
      mimeType: json['mime_type'] as String?,
      status: DocumentStatus.fromString(json['status'] as String?),
      sourceUrl: json['source_url'] as String?,
      gcsPath: json['gcs_path'] as String?,
      createdAt: tsMs(json['created_at']),
      processedAt: tsMs(json['processed_at']),
      chunkCount: json['chunk_count'] as int?,
      wordCount: json['word_count'] as int?,
      summary: json['summary'] as String?,
      keyPoints: (json['key_points'] as List?)?.cast<String>() ?? [],
      themes: (json['themes'] as List?)?.cast<String>() ?? [],
      tagIds: (json['tag_ids'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      sourceAudioUrl: json['source_audio_url'] as String?,
      sourceImageUrl: json['source_image_url'] as String?,
      author: json['author'] as String?,
      // NOT tsMs(): publish_date is an ISO date STRING, not a Timestamp.
      publishDate: json['publish_date'] as String?,
      processingStage: json['processing_stage'] as String?,
      finishedAt: tsMs(json['finished_at']),
      nextLetterRequestedAt: tsMs(json['next_letter_requested_at']),
      errorMessage: json['error_message'] as String?,
      sourcePriority: (json['source_priority'] as num?)?.toDouble() ?? 0.5,
      viewCount: json['view_count'] as int? ?? 0,
      lastViewedAt: tsMs(json['last_viewed_at']),
      sourceIntegration: (json['source_integration'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
