/// `/users/{uid}/settings/scripture_newsletter` — the second, opt-in readings
/// letter (contract 2.24.0, ADR-029).
///
/// **Its own closed key set**, deliberately separate from the daily letter's.
/// Sending a daily-only key here is a 400 and vice versa: two letters that
/// shared one settings document would make every change to one silently
/// reshape the other.
library;

class ScriptureNewsletterSettings {
  const ScriptureNewsletterSettings({
    this.enabled = false, // opt-IN: absent means off
    this.emailAddress = '',
    this.deliveryTime = '07:00',
    this.timezone = 'UTC',
    this.frequency = 'daily',
    this.calendar = 'roman',
    this.itemsPerNewsletter = 5,
    this.excludeRecentDays = 7,
  });

  final bool enabled;
  final String emailAddress;
  final String deliveryTime;
  final String timezone;
  final String frequency;

  /// **Shown, not chosen** (2.25.2). `roman` is the only calendar the shipped
  /// table answers completely — `rcl` is a Sunday-and-principal-feast
  /// lectionary by nature and `anglican` was deleted at 2.25.1 for being
  /// generated from the date rather than being a lectionary at all. The
  /// endpoint still accepts more, so this is a UI restraint, not a schema one.
  final String calendar;

  final int itemsPerNewsletter;
  final int excludeRecentDays;

  factory ScriptureNewsletterSettings.fromJson(Map<String, dynamic> json) =>
      ScriptureNewsletterSettings(
        enabled: json['enabled'] as bool? ?? false,
        emailAddress: json['emailAddress'] as String? ?? '',
        deliveryTime: json['deliveryTime'] as String? ?? '07:00',
        timezone: json['timezone'] as String? ?? 'UTC',
        frequency: json['frequency'] as String? ?? 'daily',
        calendar: json['calendar'] as String? ?? 'roman',
        itemsPerNewsletter: json['itemsPerNewsletter'] as int? ?? 5,
        excludeRecentDays: json['excludeRecentDays'] as int? ?? 7,
      );

  /// Partial update body — any subset of the accepted set and nothing else.
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'deliveryTime': deliveryTime,
        'timezone': timezone,
        'frequency': frequency,
        'calendar': calendar,
        if (emailAddress.isNotEmpty) 'emailAddress': emailAddress,
        'itemsPerNewsletter': itemsPerNewsletter,
        'excludeRecentDays': excludeRecentDays,
      };

  ScriptureNewsletterSettings copyWith({
    bool? enabled,
    String? emailAddress,
    String? deliveryTime,
    String? timezone,
    String? frequency,
    String? calendar,
    int? itemsPerNewsletter,
    int? excludeRecentDays,
  }) =>
      ScriptureNewsletterSettings(
        enabled: enabled ?? this.enabled,
        emailAddress: emailAddress ?? this.emailAddress,
        deliveryTime: deliveryTime ?? this.deliveryTime,
        timezone: timezone ?? this.timezone,
        frequency: frequency ?? this.frequency,
        calendar: calendar ?? this.calendar,
        itemsPerNewsletter: itemsPerNewsletter ?? this.itemsPerNewsletter,
        excludeRecentDays: excludeRecentDays ?? this.excludeRecentDays,
      );
}
