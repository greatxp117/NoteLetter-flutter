/// `/users/{uid}/settings/newsletter` — fields per contract data-model.md.
/// `purposeEmbedding` is never read/rendered (INV-05); it isn't modeled here.
class NewsletterSettings {
  final bool enabled;
  final String email;
  final String deliveryTime;
  final String timezone;
  final String frequency;
  final String purposeText;
  final List<String> sourceTypes;
  final int lookbackDays;

  const NewsletterSettings({
    this.enabled = true,
    this.email = '',
    this.deliveryTime = '07:00',
    this.timezone = 'America/New_York',
    this.frequency = 'daily',
    this.purposeText = '',
    this.sourceTypes = const [],
    this.lookbackDays = 7,
  });

  factory NewsletterSettings.fromJson(Map<String, dynamic> json) {
    return NewsletterSettings(
      enabled: json['enabled'] as bool? ?? true,
      email: json['email'] as String? ?? '',
      deliveryTime: json['deliveryTime'] as String? ?? '07:00',
      timezone: json['timezone'] as String? ?? 'America/New_York',
      frequency: json['frequency'] as String? ?? 'daily',
      purposeText: json['purposeText'] as String? ?? '',
      sourceTypes: (json['sourceTypes'] as List?)?.cast<String>() ?? [],
      lookbackDays: json['lookbackDays'] as int? ?? 7,
    );
  }

  /// Partial update body for `fn_newsletter_settings` PUT — any subset.
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'deliveryTime': deliveryTime,
      'timezone': timezone,
      'frequency': frequency,
      if (email.isNotEmpty) 'email': email,
      if (purposeText.isNotEmpty) 'purposeText': purposeText,
      if (sourceTypes.isNotEmpty) 'sourceTypes': sourceTypes,
      'lookbackDays': lookbackDays,
    };
  }

  NewsletterSettings copyWith({
    bool? enabled,
    String? email,
    String? deliveryTime,
    String? timezone,
    String? frequency,
    String? purposeText,
    List<String>? sourceTypes,
    int? lookbackDays,
  }) {
    return NewsletterSettings(
      enabled: enabled ?? this.enabled,
      email: email ?? this.email,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      timezone: timezone ?? this.timezone,
      frequency: frequency ?? this.frequency,
      purposeText: purposeText ?? this.purposeText,
      sourceTypes: sourceTypes ?? this.sourceTypes,
      lookbackDays: lookbackDays ?? this.lookbackDays,
    );
  }
}
