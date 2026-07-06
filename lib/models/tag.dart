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

  const Tag({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.color,
    this.source,
    this.createdAt,
    this.updatedAt,
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
    );
  }
}
