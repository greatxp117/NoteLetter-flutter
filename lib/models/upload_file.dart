enum UploadStatus { pending, uploading, completed, error }

class UploadFile {
  final String id;
  final String name;
  final int size;
  final String mimeType;
  UploadStatus status;
  double progress;
  String author;
  String description;
  String? docId;
  List<String>? docIds;
  String? errorMessage;

  /// A link's detected type (INV-07) — `youtube_playlist` included, which is
  /// no document's type. Null for a file.
  final String? linkType;

  /// What the answer said, when it said more than "queued": a playlist's
  /// "Added N videos from this playlist." (4.114.0, ADR-151). Null otherwise.
  String? note;

  UploadFile({
    required this.id,
    required this.name,
    required this.size,
    this.mimeType = 'application/octet-stream',
    this.status = UploadStatus.pending,
    this.progress = 0.0,
    this.author = '',
    this.description = '',
    this.docId,
    this.docIds,
    this.errorMessage,
    this.linkType,
    this.note,
  });

  String get sizeLabel {
    if (size <= 0) return '';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  UploadFile copyWith({
    UploadStatus? status,
    double? progress,
    String? author,
    String? description,
    String? docId,
    List<String>? docIds,
    String? errorMessage,
    String? note,
  }) {
    return UploadFile(
      id: id,
      name: name,
      size: size,
      mimeType: mimeType,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      author: author ?? this.author,
      description: description ?? this.description,
      docId: docId ?? this.docId,
      docIds: docIds ?? this.docIds,
      errorMessage: errorMessage ?? this.errorMessage,
      linkType: linkType,
      note: note ?? this.note,
    );
  }
}
