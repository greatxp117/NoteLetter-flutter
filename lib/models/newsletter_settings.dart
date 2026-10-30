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

  /// How many items a letter carries. Contract-accepted since 2.0.0 and never
  /// modelled here. **Half of it is the per-letter pin cap** (INV-16), which is
  /// why the pinned block reads this rather than guessing: a control that
  /// states a number the letter does not honour is a wrong promise.
  final int itemsPerNewsletter;

  /// Suppress chunks included in a newsletter this recently, so the daily
  /// letter doesn't echo itself (2.2.0 surfaces this as an editable control).
  final int excludeRecentDays;

  /// Shelf **titles**, not ids — they bias chunk scoring by topic rather than
  /// scoping to a shelf (letters.md; web `topicFilters` in LetterSettings).
  final List<String> topicFilters;

  const NewsletterSettings({
    this.enabled = true,
    this.emailAddress = '',
    this.deliveryTime = '07:00',
    // Empty means NONE IS STORED — the build then reads `deliveryTime` as UTC
    // (area_letter.py `s.get("timezone", "UTC")`). Every reader of this field
    // offers the device's zone in its place (`deviceTimezone()`), as web does
    // (`data.timezone || deviceTimezone()`), and every writer sends one. Until
    // F-144 this was `America/New_York`, so those empty-branches never ran:
    // Letter settings drew New York for a reader whose zone was never stored
    // and its Save then stored New York.
    this.timezone = '',
    this.frequency = 'daily',
    this.purposeText = '',
    this.sourceTypes = const [],
    this.dateRangeDays = 30, // contract default (rolling window)
    this.itemsPerNewsletter = 5, // contract default
    this.excludeRecentDays = 7, // contract default
    this.topicFilters = const [],
  });

  /// A key the stored document does not carry reads as what the BUILD uses
  /// for it (area_letter.py: `frequency` "daily", `deliveryTime` "07:00",
  /// `itemsPerNewsletter` 5, `excludeRecentDays` 7; screens/letters.md
  /// §Composition, *Letter settings*), and an empty value reads the same, as
  /// web's `||` reads it. `excludeRecentDays` 0 is a real value — passages
  /// never rest — and stays 0. A zone that is not stored stays empty (see
  /// [timezone]).
  factory NewsletterSettings.fromJson(Map<String, dynamic> json) {
    String text(String key, String fallback) {
      final v = json[key];
      return v is String && v.isNotEmpty ? v : fallback;
    }

    int? count(String key) => (json[key] as num?)?.toInt();
    final items = count('itemsPerNewsletter');
    return NewsletterSettings(
      // Absent is OFF (screens/library.md §The letter chip: "absent is off,
      // as on Letter settings"; web reads `Boolean(data.enabled)` — the
      // orchestrator requires `enabled`). This read said `?? true`, so a doc
      // without the key — or no doc at all — drew the letter as ON.
      enabled: json['enabled'] == true,
      emailAddress: json['emailAddress'] as String? ?? '',
      deliveryTime: text('deliveryTime', '07:00'),
      timezone: text('timezone', ''),
      frequency: text('frequency', 'daily'),
      purposeText: json['purposeText'] as String? ?? '',
      sourceTypes: (json['sourceTypes'] as List?)?.cast<String>() ?? [],
      dateRangeDays: json['dateRangeDays'] as int? ?? 30,
      itemsPerNewsletter: items == null || items == 0 ? 5 : items,
      excludeRecentDays: count('excludeRecentDays') ?? 7,
      topicFilters: (json['topicFilters'] as List?)?.cast<String>() ?? const [],
    );
  }

  /// Partial update body for `fn_newsletter_settings` PUT — any subset of the
  /// accepted set, and nothing else (2.0.0: unknown keys are rejected).
  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'deliveryTime': deliveryTime,
      // An empty zone is "none stored", never a value to send (2.29.0).
      if (timezone.isNotEmpty) 'timezone': timezone,
      'frequency': frequency,
      if (emailAddress.isNotEmpty) 'emailAddress': emailAddress,
      if (purposeText.isNotEmpty) 'purposeText': purposeText,
      if (sourceTypes.isNotEmpty) 'sourceTypes': sourceTypes,
      'dateRangeDays': dateRangeDays,
      'itemsPerNewsletter': itemsPerNewsletter,
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
    int? itemsPerNewsletter,
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
      itemsPerNewsletter: itemsPerNewsletter ?? this.itemsPerNewsletter,
      excludeRecentDays: excludeRecentDays ?? this.excludeRecentDays,
    );
  }
}
