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
  final List<String> questions;
  final List<String> tags;
  final String? thumbnailUrl;
  final String? errorMessage;
  final double sourcePriority;
  final String? displayHtml;
  final int viewCount;
  final int? lastViewedAt;

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
    this.questions = const [],
    this.tags = const [],
    this.thumbnailUrl,
    this.errorMessage,
    this.sourcePriority = 0.5,
    this.displayHtml,
    this.viewCount = 0,
    this.lastViewedAt,
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
      questions: (json['questions'] as List?)?.cast<String>() ?? [],
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      errorMessage: json['error_message'] as String?,
      sourcePriority: (json['source_priority'] as num?)?.toDouble() ?? 0.5,
      displayHtml: json['display_html'] as String?,
      viewCount: json['view_count'] as int? ?? 0,
      lastViewedAt: tsMs(json['last_viewed_at']),
    );
  }
}
