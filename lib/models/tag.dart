import 'document.dart' show tsMs;

/// `/tags/{tagId}` — read-only for clients; `embedding` stripped (INV-05).
class Tag {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? color;
  final String? source;
  final int? createdAt;
  final int? updatedAt;

  /// Volumes on this shelf. Drives the >= 5 gate on "Split this shelf" — the
  /// endpoint 400s below that, so the control is ABSENT rather than disabled.
  final int documentCount;

  /// 2.20.0 (ADR-025) — the shelf this one was split out of. **Provenance
  /// only**: no roll-up, no transitive filter, and child shelves are not nested
  /// in the index. A half-honoured hierarchy makes the same shelf report two
  /// sizes depending on which screen you look at. Dangling ids are inert.
  final String? parentTagId;

  const Tag({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.color,
    this.source,
    this.createdAt,
    this.updatedAt,
    this.documentCount = 0,
    this.parentTagId,
  });

  factory Tag.fromJson(String id, Map<String, dynamic> json) {
    return Tag(
      id: id,
      userId: json['user_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      color: json['color'] as String?,
      source: json['source'] as String?,
      createdAt: tsMs(json['created_at']),
      updatedAt: tsMs(json['updated_at']),
      documentCount: json['document_count'] as int? ?? 0,
      parentTagId: json['parent_tag_id'] as String?,
    );
  }
}
