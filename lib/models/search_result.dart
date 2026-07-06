import 'chunk.dart';
export 'chunk.dart' show Chunk;

/// `document.summary` is stripped server-side in search responses.
class SearchResultDocument {
  final String userId;
  final String title;
  final String type;
  final String status;
  final String? sourceUrl;
  final int? createdAt;
  final int? chunkCount;
  final int? wordCount;
  final List<String> themes;
  final String? thumbnailUrl;

  const SearchResultDocument({
    required this.userId,
    required this.title,
    required this.type,
    required this.status,
    this.sourceUrl,
    this.createdAt,
    this.chunkCount,
    this.wordCount,
    this.themes = const [],
    this.thumbnailUrl,
  });

  factory SearchResultDocument.fromJson(Map<String, dynamic> json) {
    return SearchResultDocument(
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'unknown',
      status: json['status'] as String? ?? '',
      sourceUrl: json['source_url'] as String?,
      createdAt: json['created_at'] as int?,
      chunkCount: json['chunk_count'] as int?,
      wordCount: json['word_count'] as int?,
      themes: (json['themes'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

class SearchResult {
  final Chunk chunk;
  final SearchResultDocument document;
  final double score;

  const SearchResult({
    required this.chunk,
    required this.document,
    this.score = 0,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      chunk: Chunk.fromJson(json['chunk'] as Map<String, dynamic>),
      document: SearchResultDocument.fromJson(
          json['document'] as Map<String, dynamic>),
      score: (json['score'] as num?)?.toDouble() ?? 0,
    );
  }
}
