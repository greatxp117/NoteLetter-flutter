/// Epoch ms from whatever this endpoint's JSON actually carries.
///
/// **`fn_get_cloud_integrations` returns ISO-8601 strings, not epoch ms.** It
/// serialises the raw Firestore document through `_firestore_safe`, which calls
/// `datetime.isoformat()` — INV-06's epoch-ms rule is about the *Firestore*
/// read boundary, and this endpoint does not go through it (contract 4.5.4).
///
/// The web reference survives it by accident: `new Date(x)` takes both a number
/// and an ISO string, so nobody noticed. Dart does not coerce, so the direct
/// port threw `type 'String' is not a subtype of type 'int?'` out of
/// `loadIntegrations` — and because that call builds the whole list, **one
/// connected account with a `connected_at` (all of them) took out the entire
/// cloud section**: no connect cards, no picker, no sync. Tier-1 could not see
/// it — every captured fixture has these fields `null`.
int? _tsMs(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return DateTime.tryParse(v)?.millisecondsSinceEpoch;
  return null;
}

/// `/integrations/{provider}` item shape from `fn_get_cloud_integrations`
/// (tokens always stripped by the backend). Timestamps are normalised to epoch
/// ms here by [_tsMs] — see its note; they do **not** arrive that way.
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
      connectedAt: _tsMs(json['connected_at']),
      providerEmail: json['provider_email'] as String?,
      autoSyncEnabled: json['auto_sync_enabled'] as bool? ?? false,
      syncFrequency: json['sync_frequency'] as String? ?? 'daily',
      syncPreferredHour: json['sync_preferred_hour'] is int
          ? json['sync_preferred_hour'] as int
          : int.tryParse('${json['sync_preferred_hour'] ?? ''}'),
      folderIds: (syncConfig['folder_ids'] as List?)?.cast<String>() ?? const [],
      includeTypes:
          (syncConfig['include_types'] as List?)?.cast<String>() ?? const [],
      excludePatterns:
          (syncConfig['exclude_patterns'] as List?)?.cast<String>() ?? const [],
      lastSyncAt: _tsMs(json['last_sync_at']),
      lastManualSyncAt: _tsMs(json['last_manual_sync_at']),
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
