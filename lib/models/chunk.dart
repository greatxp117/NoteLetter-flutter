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
    );
  }
}
