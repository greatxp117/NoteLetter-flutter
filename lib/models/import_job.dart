import 'document.dart' show tsMs;

/// `/cloud_import_jobs/{jobId}` — read-only; subscribe (`user_id ==`,
/// `created_at desc`, limit 50) and aggregate client-side (INV-02, 1.2.4).
/// `provider_modified_at` is a provider string, never `tsMs()`-d.
class ImportJob {
  final String id;
  final String provider;
  final String status;
  final String providerFileId;
  final String providerFileName;
  final String providerPath;
  final String? documentId;
  final String? errorMessage;

  /// 1.3.0 (ADR-006): `"duplicate" | "size_limit" | null` (missing pre-1.3.0).
  final String? skipReason;
  final String mimeType;
  final int fileSize;
  final int? createdAt;
  final int? startedAt;
  final int? completedAt;
  final int retryCount;

  const ImportJob({
    required this.id,
    required this.provider,
    required this.status,
    this.providerFileId = '',
    this.providerFileName = '',
    this.providerPath = '',
    this.documentId,
    this.errorMessage,
    this.skipReason,
    this.mimeType = '',
    this.fileSize = 0,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    this.retryCount = 0,
  });

  factory ImportJob.fromJson(String id, Map<String, dynamic> json) {
    return ImportJob(
      id: id,
      provider: json['provider'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      providerFileId: json['provider_file_id'] as String? ?? '',
      providerFileName: json['provider_file_name'] as String? ?? '',
      providerPath: json['provider_path'] as String? ?? '',
      documentId: json['document_id'] as String?,
      errorMessage: json['error_message'] as String?,
      skipReason: json['skip_reason'] as String?,
      mimeType: json['mime_type'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      createdAt: tsMs(json['created_at']),
      startedAt: tsMs(json['started_at']),
      completedAt: tsMs(json['completed_at']),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    );
  }

  static const _terminal = {'complete', 'error', 'skipped', 'cancelled'};

  bool get isTerminal => _terminal.contains(status);
  bool get isWorking => status == 'downloading' || status == 'processing';

  /// Terminal jobs are retryable; retrying `skipped` is the explicit "import
  /// again" override (cloud-storage.md, 1.3.0).
  bool get canRetry =>
      status == 'error' || status == 'cancelled' || status == 'skipped';

  bool get isDuplicate => skipReason == 'duplicate';
  bool get isSizeLimited => skipReason == 'size_limit';
}
