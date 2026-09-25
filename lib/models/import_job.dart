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

  /// Why the job is held: `type` or `size` (4.45.0, ADR-083). Rendered as the
  /// row's reason, and **never as a length** — `over_mb` is a proxy for length,
  /// not a measure of one, because no provider reports a page count.
  final String? reviewReason;
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
    this.reviewReason,
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
      reviewReason: json['review_reason'] as String?,
      mimeType: json['mime_type'] as String? ?? '',
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      createdAt: tsMs(json['created_at']),
      startedAt: tsMs(json['started_at']),
      completedAt: tsMs(json['completed_at']),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 4.45.0 (ADR-083) — held, waiting on the user. **Non-terminal**: no worker
  /// is enqueued and nothing has been downloaded, extracted or charged for.
  bool get isAwaitingReview => status == 'awaiting_review';

  /// Dismissed by the reader (4.45.0). Reversed by **Import again**, which is
  /// `fn_retry_import_job` — since 1.3.0 that already means "import it anyway"
  /// for a skipped job.
  bool get isDismissed => skipReason == 'dismissed';

  static const _terminal = {'complete', 'error', 'skipped', 'cancelled'};

  bool get isTerminal => _terminal.contains(status);
  static bool isTerminalStatus(String s) => _terminal.contains(s);
  bool get isWorking => status == 'downloading' || status == 'processing';

  bool get isDuplicate => skipReason == 'duplicate';
  bool get isSizeLimited => skipReason == 'size_limit';

  /// A plan-limit hold (4.79.0, ADR-113): the server's sentence is in
  /// `error_message`, and **Import again** is how the file comes in once there
  /// is room.
  bool get isPlanLimited => skipReason == 'plan_limit';

  /// The skips whose control is **Import again** — the explicit override, not a
  /// retry of a failure (`screens/sources.md` §Trust & feedback).
  bool get isImportAgain =>
      status == 'skipped' && (isDuplicate || isDismissed || isPlanLimited);

  /// Which rows carry a control at all. `error`/`cancelled` retry; of the
  /// skips, only the three [isImportAgain] names do. **Not every `skipped`**:
  /// a `size_limit` retry would skip identically, and a pre-1.3.0 skip (no
  /// `skip_reason`) is spec'd action-less — "any skipped" put Retry on both.
  bool get canRetry =>
      status == 'error' || status == 'cancelled' || isImportAgain;

  /// The provider MIME as the review-rule/type key (`pdf`, `docx`, `pptx`,
  /// `notion`) — the vocabulary of `include_types` and `review_rules`. Null for
  /// anything else. Web: `cloudTypeKey`.
  String? get typeKey => _typeKeyByMime[mimeType];

  static const _typeKeyByMime = <String, String>{
    'application/pdf': 'pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        'docx',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation':
        'pptx',
    'application/x-notion-page': 'notion',
  };

  /// The document `type` this file becomes, for the plate — which is keyed by
  /// **type**, never by MIME (`kitDocKind`). Feeding it a MIME answered `note`
  /// for everything, and a hardcoded `'web'` plate said every PDF was a page.
  /// Web: `mimeKind` (pdf · epub · html → web · everything else → note).
  String get docType {
    final m = mimeType;
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('epub')) return 'epub';
    if (m.contains('html')) return 'article';
    return typeKey ?? 'plain';
  }
}
