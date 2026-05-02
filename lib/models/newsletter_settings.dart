class NewsletterSettings {
  final bool enabled;
  final String frequency;
  final String deliveryTime;
  final String timezone;
  final String purposeText;
  final List<String> topicFilters;
  final List<String> sourceTypes;
  final int itemsPerNewsletter;
  final String dateRangeMode;
  final int? dateRangeDays;
  final int? excludeRecentDays;
  final String emailAddress;

  const NewsletterSettings({
    this.enabled = true,
    this.frequency = 'daily',
    this.deliveryTime = '07:00',
    this.timezone = 'America/New_York',
    this.purposeText = '',
    this.topicFilters = const [],
    this.sourceTypes = const [],
    this.itemsPerNewsletter = 5,
    this.dateRangeMode = 'rolling',
    this.dateRangeDays,
    this.excludeRecentDays,
    this.emailAddress = '',
  });

  factory NewsletterSettings.fromJson(Map<String, dynamic> json) {
    return NewsletterSettings(
      enabled: json['enabled'] as bool? ?? true,
      frequency: json['frequency'] as String? ?? 'daily',
      deliveryTime: json['deliveryTime'] as String? ?? '07:00',
      timezone: json['timezone'] as String? ?? 'America/New_York',
      purposeText: json['purposeText'] as String? ?? '',
      topicFilters: (json['topicFilters'] as List?)?.cast<String>() ?? [],
      sourceTypes: (json['sourceTypes'] as List?)?.cast<String>() ?? [],
      itemsPerNewsletter: json['itemsPerNewsletter'] as int? ?? 5,
      dateRangeMode: json['dateRangeMode'] as String? ?? 'rolling',
      dateRangeDays: json['dateRangeDays'] as int?,
      excludeRecentDays: json['excludeRecentDays'] as int?,
      emailAddress: json['emailAddress'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'frequency': frequency,
      'deliveryTime': deliveryTime,
      'timezone': timezone,
      if (purposeText.isNotEmpty) 'purposeText': purposeText,
      if (topicFilters.isNotEmpty) 'topicFilters': topicFilters,
      if (sourceTypes.isNotEmpty) 'sourceTypes': sourceTypes,
      'itemsPerNewsletter': itemsPerNewsletter,
      'dateRangeMode': dateRangeMode,
      if (dateRangeDays != null) 'dateRangeDays': dateRangeDays,
      if (excludeRecentDays != null) 'excludeRecentDays': excludeRecentDays,
      if (emailAddress.isNotEmpty) 'emailAddress': emailAddress,
    };
  }

  NewsletterSettings copyWith({
    bool? enabled,
    String? frequency,
    String? deliveryTime,
    String? timezone,
    String? purposeText,
    List<String>? topicFilters,
    List<String>? sourceTypes,
    int? itemsPerNewsletter,
    String? dateRangeMode,
    int? dateRangeDays,
    int? excludeRecentDays,
    String? emailAddress,
  }) {
    return NewsletterSettings(
      enabled: enabled ?? this.enabled,
      frequency: frequency ?? this.frequency,
      deliveryTime: deliveryTime ?? this.deliveryTime,
      timezone: timezone ?? this.timezone,
      purposeText: purposeText ?? this.purposeText,
      topicFilters: topicFilters ?? this.topicFilters,
      sourceTypes: sourceTypes ?? this.sourceTypes,
      itemsPerNewsletter: itemsPerNewsletter ?? this.itemsPerNewsletter,
      dateRangeMode: dateRangeMode ?? this.dateRangeMode,
      dateRangeDays: dateRangeDays ?? this.dateRangeDays,
      excludeRecentDays: excludeRecentDays ?? this.excludeRecentDays,
      emailAddress: emailAddress ?? this.emailAddress,
    );
  }
}
