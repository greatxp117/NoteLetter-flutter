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
  });

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
    );
  }

  String get _fileName => payload['file_name'] as String? ?? 'this file';
  String? get documentId => payload['document_id'] as String?;
  String? get toPath => payload['to_path'] as String?;
  String? get fromPath => payload['from_path'] as String?;

  /// Human title for the card. Notion `move` is a copy (ADR-005 §3).
  String get title {
    switch (type) {
      case 'move':
        return provider == 'notion' ? 'Copy to a folder' : 'Move a file';
      case 'placement':
        return 'File a new document';
      case 'readme':
        return 'Add a folder README';
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
        return 'Propose a charter for ${payload['folder_id'] ?? 'a folder'}';
      case 'reorganize':
        return 'Review a reorganization plan';
      default:
        return '';
    }
  }
}
