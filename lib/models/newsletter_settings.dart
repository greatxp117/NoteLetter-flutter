/// `/users/{uid}/settings/newsletter` — fields per contract data-model.md.
/// `purposeEmbedding` is never read/rendered (INV-05); it isn't modeled here.
///
/// Canonical field names (contract 2.0.0, ADR-009): `emailAddress` and
/// `dateRangeDays`. The pre-2.0.0 names `email`/`lookbackDays` are gone — the
/// backend now rejects them with a 400 (the write is all-or-nothing), so this
/// model must both read and send only the canonical keys.
class NewsletterSettings {
  final bool enabled;
  final String emailAddress;
  final String deliveryTime;
  final String timezone;
  final String frequency;
  final String purposeText;
  final List<String> sourceTypes;
  final int dateRangeDays;

  /// Suppress chunks included in a newsletter this recently, so the daily
  /// letter doesn't echo itself (2.2.0 surfaces this as an editable control).
  final int excludeRecentDays;

  const NewsletterSettings({
    this.enabled = true,
    this.emailAddress = '',
    this.deliveryTime = '07:00',
    // A hardcoded default zone is a wrong promise for everyone outside it —
    // 2.29.0's whole point. Callers building fresh settings pass
    // `deviceTimezone()`; this constant only survives where nothing supplied
    // one, and an empty string would be worse (the orchestrator would read the
    // stored time as UTC).
    this.timezone = 'America/New_York',
    this.frequency = 'daily',
    this.purposeText = '',
    this.sourceTypes = const [],
    this.dateRangeDays = 30, // contract default (rolling window)
    this.excludeRecentDays = 7, // contract default
  });

  factory NewsletterSettings.fromJson(Map<String, dynamic> json) {
    return NewsletterSettings(
      enabled: json['enabled'] as bool? ?? true,
      emailAddress: json['emailAddress'] as String? ?? '',
      deliveryTime: json['deliveryTime'] as String? ?? '07:00',
      timezone: json['timezone'] as String? ?? 'America/New_York',
      frequency: json['frequency'] as String? ?? 'daily',
      purposeText: json['purposeText'] as String? ?? '',
      sourceTypes: (json['sourceTypes'] as List?)?.cast<String>() ?? [],
      dateRangeDays: json['dateRangeDays'] as int? ?? 30,
      excludeRecentDays: json['excludeRecentDays'] as int? ?? 7,
    );
  }

  /// Partial update body for `fn_newsletter_settings` PUT — any subset of the
  /// accepted set, and nothing else (2.0.0: unknown keys are rejected).
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'deliveryTime': deliveryTime,
      'timezone': timezone,
      'frequency': frequency,
      if (emailAddress.isNotEmpty) 'emailAddress': emailAddress,
      if (purposeText.isNotEmpty) 'purposeText': purposeText,
      if (sourceTypes.isNotEmpty) 'sourceTypes': sourceTypes,
      'dateRangeDays': dateRangeDays,
      'excludeRecentDays': excludeRecentDays,
    };
  }

  NewsletterSettings copyWith({
    bool? enabled,
    String? emailAddress,
    String? deliveryTime,
    String? timezone,
    String? frequency,
    String? purposeText,
    List<String>? sourceTypes,
    int? dateRangeDays,
    int? excludeRecentDays,
  }) {
    return NewsletterSettings(
      enabled: enabled ?? this.enabled,
      emailAddress: emailAddress ?? this.emailAddress,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      timezone: timezone ?? this.timezone,
      frequency: frequency ?? this.frequency,
      purposeText: purposeText ?? this.purposeText,
      sourceTypes: sourceTypes ?? this.sourceTypes,
      dateRangeDays: dateRangeDays ?? this.dateRangeDays,
      excludeRecentDays: excludeRecentDays ?? this.excludeRecentDays,
    );
  }
}
