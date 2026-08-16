/// Delivery schedule helpers (contract 2.29.0) — mirrors the web reference's
/// `pages/letters/schedule.js`.
///
/// `enabled` and `timezone` were accepted by `fn_newsletter_settings` from
/// 2.0.0 and written by almost nothing, so `deliveryTime` was rendered as a
/// local hour it had never been: with no timezone sent, the orchestrator read
/// every stored time as UTC, and a `07:00` shown to a New York reader meant
/// 03:00. **A client that sends `deliveryTime` sends `timezone` in the same
/// call** — that is the normative rule this file exists to keep true.
library;

/// The zones offered by name. Deliberately short: this is a convenience list,
/// not a claim to enumerate the world's timezones.
const timezones = <String>[
  'Europe/Dublin',
  'Europe/London',
  'America/New_York',
  'America/Chicago',
  'America/Los_Angeles',
  'Australia/Sydney',
];

/// The device's own IANA zone, or `UTC` when the platform will not say.
///
/// Dart has no `Intl.DateTimeFormat().resolvedOptions().timeZone`, so this
/// derives the zone from the current UTC offset. That is a NARROWER claim than
/// the browser's and is treated as such: it is only ever a default and a
/// leading suggestion, never a silent overwrite of a stored value.
String deviceTimezone() {
  final offset = DateTime.now().timeZoneOffset;
  // Exact-offset matches for the zones we offer, at either side of DST. An
  // offset is not a zone — several zones share one — so this is a best guess,
  // which is why the stored value always wins when one exists.
  const byOffsetMinutes = <int, String>{
    0: 'Europe/London',      // also Dublin in winter
    60: 'Europe/London',     // BST
    -300: 'America/New_York',
    -240: 'America/New_York',
    -360: 'America/Chicago',
    -420: 'America/Los_Angeles',
    -480: 'America/Los_Angeles',
    600: 'Australia/Sydney',
    660: 'Australia/Sydney',
  };
  return byOffsetMinutes[offset.inMinutes] ?? 'UTC';
}

/// The zones to offer, device zone first.
///
/// [current] is always included even when it is not one of the names above, so
/// **opening this screen can never drop a zone set elsewhere** — the failure
/// that clamping to the list alone would cause.
List<String> timezoneOptions(String? current) {
  final seen = <String>{};
  final out = <String>[];
  for (final tz in [deviceTimezone(), current, ...timezones]) {
    if (tz == null || tz.isEmpty) continue;
    if (seen.add(tz)) out.add(tz);
  }
  return out;
}

/// States the schedule from what was READ, never from an assumption. The web
/// reference hardcoded "Arrives tomorrow morning" under a live pulse for every
/// reader, including accounts that had no schedule at all.
String scheduleSentence({
  required bool enabled,
  required String deliveryTime,
  required String timezone,
  required String frequency,
}) {
  if (!enabled) return 'Scheduled delivery is off. You can still send a letter yourself.';
  final when = frequency == 'weekly' ? 'Every week' : 'Every day';
  return '$when at $deliveryTime ($timezone).';
}
