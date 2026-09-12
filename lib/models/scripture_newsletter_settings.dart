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
    this.emailEnabled = true, // absent means TRUE (4.24.0)
    this.emailAddress = '',
    this.deliveryTime = '06:30',
    this.timezone = '',
    this.calendar = 'roman',
  });

  /// Whether the letter is BUILT at all. Off stops everything.
  final bool enabled;

  /// Whether it is also **mailed** (4.24.0, ADR-061).
  ///
  /// **Two controls, and a client must not merge them.** `enabled` off stops
  /// the letter being built; this one keeps the daily record and its live "see
  /// all" search and stops only the mail — which is exactly what the letter's
  /// own one-click unsubscribe link flips (`fn_scripture_unsubscribe`). A
  /// reader who used that link has to be able to find this and turn it back on,
  /// and merging the two would instead delete a feature they open every
  /// morning. **Absent means true**, so every document written before 4.24.0
  /// already says "email me", which is what its author meant.
  final bool emailEnabled;

  final String emailAddress;
  final String deliveryTime;
  final String timezone;

  /// **Shown, not chosen** (2.25.2). `roman` is the only calendar the shipped
  /// table answers completely — `rcl` is a Sunday-and-principal-feast
  /// lectionary by nature and `anglican` was deleted at 2.25.1 for being
  /// generated from the date rather than being a lectionary at all. The
  /// endpoint still accepts more, so this is a UI restraint, not a schema one.
  final String calendar;

  factory ScriptureNewsletterSettings.fromJson(Map<String, dynamic> json) =>
      ScriptureNewsletterSettings(
        enabled: json['enabled'] as bool? ?? false,
        // `??` and not `== true`: absent is TRUE here, and only here.
        emailEnabled: json['emailEnabled'] as bool? ?? true,
        emailAddress: json['emailAddress'] as String? ?? '',
        deliveryTime: json['deliveryTime'] as String? ?? '06:30',
        timezone: json['timezone'] as String? ?? '',
        calendar: json['calendar'] as String? ?? 'roman',
      );

  /// The whole document, for the PUT that opts in.
  ///
  /// **Six keys, and there are only six.** This used to send `frequency`,
  /// `itemsPerNewsletter` and `excludeRecentDays` as well — the daily letter's
  /// keys, which this endpoint rejects with a hard 400 that writes nothing. So
  /// every save this client has ever attempted for the readings letter failed,
  /// and nothing could see it: the contract suite drives the endpoint from the
  /// FIXTURE body, so it exercises the adapter and never what a screen puts in
  /// it (`scripture-newsletter:settings-unknown-keys` is those exact four keys,
  /// asserting the 400).
  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'emailEnabled': emailEnabled,
        'deliveryTime': deliveryTime,
        if (timezone.isNotEmpty) 'timezone': timezone,
        if (emailAddress.isNotEmpty) 'emailAddress': emailAddress,
        'calendar': calendar,
      };

  ScriptureNewsletterSettings copyWith({
    bool? enabled,
    bool? emailEnabled,
    String? emailAddress,
    String? deliveryTime,
    String? timezone,
    String? calendar,
  }) =>
      ScriptureNewsletterSettings(
        enabled: enabled ?? this.enabled,
        emailEnabled: emailEnabled ?? this.emailEnabled,
        emailAddress: emailAddress ?? this.emailAddress,
        deliveryTime: deliveryTime ?? this.deliveryTime,
        timezone: timezone ?? this.timezone,
        calendar: calendar ?? this.calendar,
      );
}
