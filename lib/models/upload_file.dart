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
  String? errorMessage;

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
    this.errorMessage,
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
    String? errorMessage,
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
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
