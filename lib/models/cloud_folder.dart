import 'document.dart' show tsMs;

/// `/cloud_folders/{id}` — realtime-subscribed snapshot of the organized
/// cloud-folder tree (1.2.0). Read-only; `charter.embedding` is stripped at the
/// read boundary (INV-05).
class CloudFolder {
  final String id;
  final String provider;
  final String providerPath;
  final String name;
  final bool organized;
  final String status; // active | missing | archived
  final int docCount;
  final String? charterText;
  final String? charterSource; // 'llm' | 'user'
  final String? readmeStatus; // pending | written | user_modified | error
  final int? lastScannedAt;

  const CloudFolder({
    required this.id,
    required this.provider,
    required this.providerPath,
    required this.name,
    this.organized = false,
    this.status = 'active',
    this.docCount = 0,
    this.charterText,
    this.charterSource,
    this.readmeStatus,
    this.lastScannedAt,
  });

  factory CloudFolder.fromJson(String id, Map<String, dynamic> json) {
    final charter = (json['charter'] as Map?)?.cast<String, dynamic>();
    return CloudFolder(
      id: id,
      provider: json['provider'] as String? ?? '',
      providerPath: json['provider_path'] as String? ?? '',
      name: json['name'] as String? ?? '',
      organized: json['organized'] as bool? ?? false,
      status: json['status'] as String? ?? 'active',
      docCount: (json['doc_count'] as num?)?.toInt() ?? 0,
      charterText: charter?['text'] as String?,
      charterSource: charter?['source'] as String?,
      readmeStatus: json['readme_status'] as String?,
      lastScannedAt: tsMs(json['last_scanned_at']),
    );
  }

  bool get isActive => status == 'active';
}
