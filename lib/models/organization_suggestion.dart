import 'document.dart' show tsMs;

/// `/organization_suggestions/{id}` — realtime-subscribed, read-only. Clients
/// resolve only via `fn_resolve_organization_suggestions` (INV-13). The pending
/// queue drives the review cards; other statuses are the audit trail.
class OrganizationSuggestion {
  final String id;
  final String provider;
  final String type; // move | placement | readme | reorganize
  final double confidence;
  final String reason;
  final String status;
  final Map<String, dynamic> payload;
  final int? createdAt;
  final int? expiresAt;

  /// `resolution.error` — the worker's sentence on a `failed` approval (e.g.
  /// 4.92.0's "interrupted — check the file's location", ADR-126 §7).
  final String? resolutionError;

  const OrganizationSuggestion({
    required this.id,
    required this.provider,
    required this.type,
    required this.confidence,
    required this.reason,
    required this.status,
    this.payload = const {},
    this.createdAt,
    this.expiresAt,
    this.resolutionError,
  });

  /// The same suggestion at another status — how an approval this session
  /// made is drawn before its first snapshot arrives.
  OrganizationSuggestion withStatus(String status, {String? resolutionError}) =>
      OrganizationSuggestion(
        id: id,
        provider: provider,
        type: type,
        confidence: confidence,
        reason: reason,
        status: status,
        payload: payload,
        createdAt: createdAt,
        expiresAt: expiresAt,
        resolutionError: resolutionError ?? this.resolutionError,
      );

  factory OrganizationSuggestion.fromJson(String id, Map<String, dynamic> json) {
    return OrganizationSuggestion(
      id: id,
      provider: json['provider'] as String? ?? '',
      type: json['type'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      createdAt: tsMs(json['created_at']),
      expiresAt: tsMs(json['expires_at']),
      resolutionError: (json['resolution'] as Map?)?['error'] as String?,
    );
  }

  String get _fileName => payload['file_name'] as String? ?? 'this file';
  String? get documentId => payload['document_id'] as String?;
  String? get toPath => payload['to_path'] as String?;
  String? get fromPath => payload['from_path'] as String?;

  /// The README text a `readme` card proposes as the folder's charter.
  String? get proposedCharter {
    final t = payload['proposed_charter_text'];
    return t is String && t.trim().isNotEmpty ? t : null;
  }

  /// What approving a `readme` card does, said on the card (4.92.0,
  /// ADR-126 §3): the charter changes, and nothing at the provider does.
  String get adoptionNote =>
      'Approving makes your README this folder’s charter — nothing in '
      '${_providerNames[provider] ?? 'your storage'} is changed.';

  static const _providerNames = {
    'google_drive': 'Google Drive',
    'onedrive': 'OneDrive',
    'notion': 'Notion',
    'dropbox': 'Dropbox',
  };

  /// The one line an approval this session made is followed under — the card
  /// is gone from the queue by then (it reads `pending` only).
  String get outcomeTitle => type == 'readme'
      ? 'Adopt README edits as the charter'
      : detail.isNotEmpty
          ? detail
          : 'Suggestion';

  /// Human title for the card. Notion `move` is a copy (ADR-005 §3).
  String get title {
    switch (type) {
      case 'move':
        return provider == 'notion' ? 'Copy to a folder' : 'Move a file';
      case 'placement':
        return 'File a new document';
      // The adoption suggestion (ADR-005 §4): the reader edited the folder's
      // README, and approving ADOPTS that text as the charter — 4.92.0
      // (ADR-126 §3), since every such approval failed until then. It never
      // proposed adding a README; the web names it the same.
      case 'readme':
        return 'Adopt README edits';
      case 'reorganize':
        return 'Reorganize a document';
      default:
        return type;
    }
  }

  /// Type-specific one-liner shown under the reason.
  String get detail {
    switch (type) {
      case 'move':
        final verb = provider == 'notion' ? 'Copy' : 'Move';
        return '$verb "$_fileName" → ${toPath ?? '(folder)'}';
      case 'placement':
        return 'File into ${toPath ?? '(folder)'}';
      case 'readme':
        final text = proposedCharter;
        return text != null ? '“$text”' : '';
      case 'reorganize':
        return 'Review a reorganization plan';
      default:
        return '';
    }
  }
}
