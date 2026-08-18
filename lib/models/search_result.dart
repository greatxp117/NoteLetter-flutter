import 'chunk.dart';
export 'chunk.dart' show Chunk;

/// Epoch ms from an **HTTP** timestamp (INV-06 at the `fn_*` boundary).
///
/// Not [tsMs], which is the *Firestore* read boundary: it converts a
/// `Timestamp` and returns null for anything else, exactly as the web
/// reference's does. An endpoint serializes through `_firestore_safe`, so the
/// same field arrives as an **ISO 8601 string** — and this model used to read
/// it with `as int?`, which threw on every response that carried one (all of
/// them). `SearchNotifier` catches everything into "Search failed. Please try
/// again.", so a healthy backend and a 200 response read to the user as an
/// outage: **search had never returned a single result on this client.**
/// Found by the 4.5.4 device run; gated by `test/contract/search_response_test.dart`.
int? _httpTsMs(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) return DateTime.tryParse(value)?.millisecondsSinceEpoch;
  return null;
}

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

  /// The shelves this source sits on. Present in every `fn_search_notes`
  /// response (the payload is the stored document minus `summary`) and unread
  /// by this client until 4.5.4 — which is why a result card could not say
  /// which shelf its source came from.
  ///
  /// Note what is **not** here: an `id`. The backend returns `snap.to_dict()`,
  /// and a Firestore document's id is not in its data, so the document id of a
  /// result comes from `chunk.document_id` — the only place it exists.
  final List<String> tagIds;

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
    this.tagIds = const [],
  });

  factory SearchResultDocument.fromJson(Map<String, dynamic> json) {
    return SearchResultDocument(
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled',
      type: json['type'] as String? ?? 'unknown',
      status: json['status'] as String? ?? '',
      sourceUrl: json['source_url'] as String?,
      createdAt: _httpTsMs(json['created_at']),
      chunkCount: json['chunk_count'] as int?,
      wordCount: json['word_count'] as int?,
      themes: (json['themes'] as List?)?.cast<String>() ?? [],
      thumbnailUrl: json['thumbnail_url'] as String?,
      tagIds: (json['tag_ids'] as List?)?.cast<String>() ?? const [],
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
