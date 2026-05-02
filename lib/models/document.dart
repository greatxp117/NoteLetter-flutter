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

class Document {
  final String id;
  final String userId;
  final String title;
  final String type;
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
  final List<String> tags;
  final String? thumbnailUrl;
  final String? errorMessage;

  const Document({
    required this.id,
    required this.userId,
    required this.title,
    required this.type,
    required this.status,
    this.sourceUrl,
    this.gcsPath,
    this.createdAt,
    this.processedAt,
    this.chunkCount,
    this.wordCount,
    this.summary,
    this.keyPoints = const [],
    this.themes = const [],
    this.tags = const [],
    this.thumbnailUrl,
    this.errorMessage,
  });

  factory Document.fromJson(String id, Map<String, dynamic> json) {
    return Document(
      id: id,
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'unknown',
      status: DocumentStatus.fromString(json['status'] as String?),
      sourceUrl: json['source_url'] as String?,
      gcsPath: json['gcs_path'] as String?,
      createdAt: json['created_at'] as int?,
      processedAt: json['processed_at'] as int?,
      chunkCount: json['chunk_count'] as int?,
      wordCount: json['word_count'] as int?,
      summary: json['summary'] as String?,
      keyPoints: (json['key_points'] as List?)?.cast<String>() ?? [],
      themes: (json['themes'] as List?)?.cast<String>() ?? [],
      tags: (json['tags'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      errorMessage: json['error_message'] as String?,
    );
  }
}
