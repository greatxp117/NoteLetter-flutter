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

  /// Whether `document_count` was actually STORED. [documentCount] reads 0 when
  /// it is absent, which is right for the split gate (the endpoint refuses
  /// below 5 either way) and wrong for a figure: §20.1's picker draws the count
  /// only when this is true, as the reference does (`Number.isFinite`), because
  /// an unread count is not zero (ADR-109).
  final bool documentCountStored;

  /// The shelf this one sits inside — the nesting edge from 5.28.0 (ADR-185,
  /// INV-33; provenance only since 2.20.0, which is why every split already
  /// nests). A stored id is a claim: `lib/shared/shelf_tree.dart` resolves it,
  /// and a dangling one reads as top-level.
  final String? parentTagId;

  /// 4.88.0 (ADR-122) — the shelf's place in the daily letter: `lead`,
  /// `mixed` or `muted`. Absent (every shelf before 4.88.0) and anything
  /// unrecognised read as `mixed` — an open read of a closed write, never an
  /// error.
  final String letterMode;

  /// The shelf's OWN mode, or null when it has none and inherits the nearest
  /// one above it (5.28.0, ADR-185) — what [ShelfTree.letterMode] walks.
  /// `fromJson` passes it as stored; a `Tag` built in code with a lead or
  /// muted [letterMode] owns that mode.
  final String? ownLetterMode;

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
    this.documentCountStored = true,
    this.parentTagId,
    this.letterMode = 'mixed',
    String? ownLetterMode,
  }) : ownLetterMode =
            ownLetterMode ?? (letterMode == 'mixed' ? null : letterMode);

  static const letterModes = ['lead', 'mixed', 'muted'];

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
      documentCountStored: json['document_count'] is int,
      parentTagId: json['parent_tag_id'] as String?,
      letterMode: letterModes.contains(json['letter_mode'])
          ? json['letter_mode'] as String
          : 'mixed',
      ownLetterMode: letterModes.contains(json['letter_mode'])
          ? json['letter_mode'] as String
          : null,
    );
  }
}
