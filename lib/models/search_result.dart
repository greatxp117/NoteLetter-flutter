class Chunk {
  final String chunkId;
  final String documentId;
  final int chunkIndex;
  final String text;
  final List<String> topics;
  final String sourceType;
  final int? createdAt;
  final int? pageNumber;
  final double? timestampStart;
  final double? timestampEnd;

  const Chunk({
    required this.chunkId,
    required this.documentId,
    required this.chunkIndex,
    required this.text,
    required this.topics,
    required this.sourceType,
    this.createdAt,
    this.pageNumber,
    this.timestampStart,
    this.timestampEnd,
  });

  factory Chunk.fromJson(Map<String, dynamic> json) {
    return Chunk(
      chunkId: json['chunk_id'] as String? ?? '',
      documentId: json['document_id'] as String? ?? '',
      chunkIndex: json['chunk_index'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      topics: (json['topics'] as List?)?.cast<String>() ?? [],
      sourceType: json['source_type'] as String? ?? 'unknown',
      createdAt: json['created_at'] as int?,
      pageNumber: json['page_number'] as int?,
      timestampStart: (json['timestamp_start'] as num?)?.toDouble(),
      timestampEnd: (json['timestamp_end'] as num?)?.toDouble(),
    );
  }
}

class SearchResultDocument {
  final String userId;
  final String title;
  final String type;
  final String status;
  final String? sourceUrl;
  final int? createdAt;
  final int? chunkCount;
  final int? wordCount;
  final String? summary;
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
    this.summary,
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
      summary: json['summary'] as String?,
      themes: (json['themes'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
    );
  }
}

class SearchResult {
  final Chunk chunk;
  final SearchResultDocument document;

  const SearchResult({required this.chunk, required this.document});

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      chunk: Chunk.fromJson(json['chunk'] as Map<String, dynamic>),
      document: SearchResultDocument.fromJson(
          json['document'] as Map<String, dynamic>),
    );
  }
}
