/// `/integrations/{provider}` item shape from `fn_get_cloud_integrations`
/// (tokens always stripped by the backend). Timestamps arrive as epoch ms at
/// the boundary (INV-06).
class CloudIntegration {
  final String provider;
  final bool tokenValid;
  final int? connectedAt;
  final String? providerEmail;
  final bool autoSyncEnabled;
  final String syncFrequency;
  final int? syncPreferredHour;
  final List<String> folderIds;
  final List<String> includeTypes;
  final List<String> excludePatterns;
  final int? lastSyncAt;
  final int? lastManualSyncAt;

  /// Connection health (1.3.0, ADR-006). `"connected" | "reconnect_required"`;
  /// a **missing** field reads as connected (pre-1.3.0 docs).
  final String status;
  final String? statusReason;

  const CloudIntegration({
    required this.provider,
    required this.tokenValid,
    this.connectedAt,
    this.providerEmail,
    this.autoSyncEnabled = false,
    this.syncFrequency = 'daily',
    this.syncPreferredHour,
    this.folderIds = const [],
    this.includeTypes = const [],
    this.excludePatterns = const [],
    this.lastSyncAt,
    this.lastManualSyncAt,
    this.status = 'connected',
    this.statusReason,
  });

  factory CloudIntegration.fromJson(Map<String, dynamic> json) {
    final syncConfig = (json['sync_config'] as Map?)?.cast<String, dynamic>() ??
        const {};
    return CloudIntegration(
      provider: json['provider'] as String? ?? '',
      tokenValid: json['token_valid'] as bool? ?? false,
      connectedAt: json['connected_at'] as int?,
      providerEmail: json['provider_email'] as String?,
      autoSyncEnabled: json['auto_sync_enabled'] as bool? ?? false,
      syncFrequency: json['sync_frequency'] as String? ?? 'daily',
      syncPreferredHour: json['sync_preferred_hour'] as int?,
      folderIds: (syncConfig['folder_ids'] as List?)?.cast<String>() ?? const [],
      includeTypes:
          (syncConfig['include_types'] as List?)?.cast<String>() ?? const [],
      excludePatterns:
          (syncConfig['exclude_patterns'] as List?)?.cast<String>() ?? const [],
      lastSyncAt: json['last_sync_at'] as int?,
      lastManualSyncAt: json['last_manual_sync_at'] as int?,
      // Missing status = connected (pre-1.3.0 docs).
      status: json['status'] as String? ?? 'connected',
      statusReason: json['status_reason'] as String?,
    );
  }

  bool get needsReconnect => status == 'reconnect_required';

  String get displayName {
    switch (provider) {
      case 'google_drive':
        return 'Google Drive';
      case 'onedrive':
        return 'OneDrive';
      case 'dropbox':
        return 'Dropbox';
      case 'notion':
        return 'Notion';
      default:
        return provider;
    }
  }

  String get lastSyncLabel {
    if (lastSyncAt == null) return 'Never synced';
    final dt = DateTime.fromMillisecondsSinceEpoch(lastSyncAt!);
    final diff = DateTime.now().difference(dt);
    if (diff.inHours < 1) return 'Synced ${diff.inMinutes}m ago';
    if (diff.inDays < 1) return 'Synced ${diff.inHours}h ago';
    return 'Synced ${diff.inDays}d ago';
  }
}
