class ActivityItem {
  final String kind;
  final String id;
  final String type;
  final String status;
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
    required this.title,
    this.provider,
    this.errorMessage,
    this.metadata,
    this.createdAt,
  });

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
      case 'service_connected': return 'Integration';
      default: return type;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'complete': return 'Indexed';
      case 'processing': return 'Processing';
      case 'queued': return 'Queued';
      case 'error': return 'Error';
      case 'skipped': return 'Skipped';
      default: return status;
    }
  }

  int? get wordCount => metadata?['word_count'] as int?;

  String get readTime {
    final wc = wordCount;
    if (wc == null || wc == 0) return '';
    final minutes = (wc / 200).ceil();
    return '$minutes min read';
  }
}
