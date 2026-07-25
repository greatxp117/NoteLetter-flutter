/// `/users/{uid}/settings/organization` — read directly (INV-02), write via
/// `fn_organization_settings` PUT (whitelist merge). No embeddings here.
class OrgProviderConfig {
  final bool enabled;
  final bool readmesEnabled;
  final bool outOfPlaceEnabled;
  final bool autoPlacementEnabled;

  const OrgProviderConfig({
    this.enabled = false,
    this.readmesEnabled = false,
    this.outOfPlaceEnabled = false,
    this.autoPlacementEnabled = false,
  });

  factory OrgProviderConfig.fromJson(Map<String, dynamic> json) {
    return OrgProviderConfig(
      enabled: json['enabled'] as bool? ?? false,
      readmesEnabled: json['readmes_enabled'] as bool? ?? false,
      outOfPlaceEnabled: json['out_of_place_enabled'] as bool? ?? false,
      autoPlacementEnabled: json['auto_placement_enabled'] as bool? ?? false,
    );
  }
}

class OrganizationSettings {
  final double confidenceThreshold; // [0.5, 0.95], default 0.75
  final String defaultReorgMode; // split | copy
  final Map<String, OrgProviderConfig> providers;

  const OrganizationSettings({
    this.confidenceThreshold = 0.75,
    this.defaultReorgMode = 'split',
    this.providers = const {},
  });

  factory OrganizationSettings.fromJson(Map<String, dynamic> json) {
    final rawProviders =
        (json['providers'] as Map?)?.cast<String, dynamic>() ?? const {};
    return OrganizationSettings(
      confidenceThreshold:
          (json['confidence_threshold'] as num?)?.toDouble() ?? 0.75,
      defaultReorgMode: json['default_reorg_mode'] as String? ?? 'split',
      providers: rawProviders.map((k, v) => MapEntry(
          k, OrgProviderConfig.fromJson((v as Map).cast<String, dynamic>()))),
    );
  }

  OrgProviderConfig configFor(String provider) =>
      providers[provider] ?? const OrgProviderConfig();
}
