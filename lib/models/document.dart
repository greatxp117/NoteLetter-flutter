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

  final String? errorMessage;
  final double sourcePriority;
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
    this.errorMessage,
    this.sourcePriority = 0.5,
    this.viewCount = 0,
    this.lastViewedAt,
    this.sourceIntegration,
  });

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
      errorMessage: json['error_message'] as String?,
      sourcePriority: (json['source_priority'] as num?)?.toDouble() ?? 0.5,
      viewCount: json['view_count'] as int? ?? 0,
      lastViewedAt: tsMs(json['last_viewed_at']),
      sourceIntegration: (json['source_integration'] as Map?)?.cast<String, dynamic>(),
    );
  }
}
