class CloudIntegration {
  final String provider;
  final bool tokenValid;
  final int? connectedAt;
  final String? providerEmail;
  final bool autoSyncEnabled;
  final String syncFrequency;
  final int? lastSyncAt;

  const CloudIntegration({
    required this.provider,
    required this.tokenValid,
    this.connectedAt,
    this.providerEmail,
    this.autoSyncEnabled = false,
    this.syncFrequency = 'daily',
    this.lastSyncAt,
  });

  factory CloudIntegration.fromJson(Map<String, dynamic> json) {
    return CloudIntegration(
      provider: json['provider'] as String? ?? '',
      tokenValid: json['token_valid'] as bool? ?? false,
      connectedAt: json['connected_at'] as int?,
      providerEmail: json['provider_email'] as String?,
      autoSyncEnabled: json['auto_sync_enabled'] as bool? ?? false,
      syncFrequency: json['sync_frequency'] as String? ?? 'daily',
      lastSyncAt: json['last_sync_at'] as int?,
    );
  }

  String get displayName {
    switch (provider) {
      case 'google_drive': return 'Google Drive';
      case 'onedrive': return 'OneDrive';
      case 'dropbox': return 'Dropbox';
      case 'notion': return 'Notion';
      default: return provider;
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
