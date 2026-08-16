class ActivityItem {
  final String kind;
  final String id;
  final String type;
  final String status;
  final String level;
  final String title;
  final String? provider;
  final String? errorMessage;
  final Map<String, dynamic>? metadata;
  final int? createdAt;

  const ActivityItem({
    required this.kind,
    required this.id,
    required this.type,
    required this.status,
    this.level = 'info',
    required this.title,
    this.provider,
    this.errorMessage,
    this.metadata,
    this.createdAt,
  });

  /// 2.19.0 (ADR-024) — the pipeline half currently running, meaningful ONLY
  /// while [status] is `processing`. Open vocabulary: an unrecognised value
  /// falls back to the generic label rather than being shown raw. Both server
  /// phases can run for minutes and used to be one opaque state.
  String? get processingStage => status == 'processing'
      ? (metadata?['processing_stage'] as String?)
      : null;

  /// Feed level for a document row (2.5.0, ADR-014) — mirrors web docItemLevel.
  static String docLevel(String status) {
    if (status == 'error') return 'error';
    if (status == 'complete') return 'success';
    return 'info';
  }

  String get formattedDate {
    if (createdAt == null) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(createdAt!);
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    }
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String get typeLabel {
    switch (type) {
      case 'pdf': return 'PDF';
      case 'docx': return 'Word';
      case 'youtube': return 'YouTube';
      case 'url': return 'Article';
      case 'image': return 'Image';
      case 'image_set': return 'Images';
      case 'instagram': return 'Instagram';
      case 'tiktok': return 'TikTok';
      case 'podcast': return 'Podcast';
      case 'service_connected': return 'Integration';
      default: return type;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'complete': return 'Indexed';
      case 'processing':
        // 2.19.0 — name WHICH half is running. Both take minutes, and while
        // they shared one label a reader could not tell an advancing document
        // from a stuck one.
        switch (processingStage) {
          case 'extraction': return 'Reading the source';
          case 'embedding': return 'Indexing passages';
          default: return 'Processing';       // absent, or an unknown value
        }
      case 'queued': return 'Queued';
      case 'pending_upload': return 'Waiting for upload';
      case 'error': return 'Error';
      case 'skipped': return 'Skipped';
      // NEVER `return status`. That is the 2.19.0 defect — it showed users the
      // literal tokens `pending_upload` and `queued`. `status` is an open
      // vocabulary, so an unknown value degrades to a neutral human phrase.
      default: return 'Processing';
    }
  }

  int? get wordCount => metadata?['word_count'] as int?;

  /// `max(1, ceil(word_count / 220))` — NORMATIVE (screens/reader.md §Header,
  /// ADR-020 §4), so every client says the same number. This read 200 wpm and
  /// therefore disagreed with the web reference on every document. 220 is also
  /// the constant the read-tracking dwell rule uses: a client must not carry
  /// two opinions about how fast people read.
  String get readTime {
    final wc = wordCount;
    if (wc == null || wc == 0) return '';
    final minutes = (wc / 220).ceil().clamp(1, 1 << 30);
    return '$minutes min read';
  }
}
