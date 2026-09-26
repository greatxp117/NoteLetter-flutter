import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../services/api.dart';
import 'schedule.dart';

/// The letter opt-in on the sign-up form — the reference's
/// `usePendingLetterSetup` plus `AuthModal.stashLetterSetup`.
///
/// Written BEFORE the auth call, because a successful sign-up leaves the
/// signed-out surface at once (the router redirects), so it is the
/// authenticated app that sends the PUT. Quiet by design: a failure keeps the
/// key and retries at the next sign-in or launch, and a payload older than
/// seven days is dropped rather than switching a letter on long after the
/// sign-up that asked for it.
class PendingLetterSetup {
  PendingLetterSetup._();

  static const key = 'nl-pending-letter-setup';
  static const maxAge = Duration(days: 7);

  /// The tones and times the form offers, in the reference's order.
  static const tones = <(String, String)>[
    ('quiet', 'Quiet'),
    ('curious', 'Curious'),
    ('terse', 'Terse'),
  ];
  static const times = <String>['06:00', '06:30', '07:00', '08:00'];

  /// `06:30` → `6:30am` — the reference's `fmtLetterTime`.
  static String formatTime(String t) {
    final parts = t.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')}${h < 12 ? 'am' : 'pm'}';
  }

  /// Stash (or clear) the opt-in. Only the sign-up form calls this.
  static Future<void> stash({
    required bool wanted,
    required String deliveryTime,
    required String tone,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!wanted) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(
      key,
      jsonEncode({
        'deliveryTime': deliveryTime,
        'tone': tone,
        'timezone': deviceTimezone(),
        'ts': (now ?? DateTime.now()).millisecondsSinceEpoch,
      }),
    );
  }

  /// The `fn_newsletter_settings` body a stored payload replays as, or null
  /// when there is nothing to send (absent, unreadable, or stale).
  ///
  /// Canonical keys only — the endpoint rejects the whole request on an
  /// unknown one (2.0.0, ADR-009) — and a key is present only with a value.
  /// `tone` is stashed, as the reference stashes it, and NOT sent: the closed
  /// key set has no such field, so sending it would 400 the whole opt-in.
  static Map<String, dynamic>? bodyFor(
    String? stored, {
    String? email,
    DateTime? now,
  }) {
    if (stored == null) return null;
    Map<String, dynamic> pending;
    try {
      pending = (jsonDecode(stored) as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
    final ts = pending['ts'];
    if (ts is! int) return null;
    final age = (now ?? DateTime.now()).difference(
      DateTime.fromMillisecondsSinceEpoch(ts),
    );
    if (age > maxAge) return null;
    final body = <String, dynamic>{'enabled': true};
    if (email != null && email.isNotEmpty) body['emailAddress'] = email;
    final time = pending['deliveryTime'];
    if (time is String && time.isNotEmpty) body['deliveryTime'] = time;
    final tz = pending['timezone'];
    if (tz is String && tz.isNotEmpty) body['timezone'] = tz;
    return body;
  }

  static bool _inFlight = false;

  /// Send a stashed opt-in, once, for the signed-in [email].
  static Future<void> replay(String? email) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(key);
      if (stored == null) return;
      final body = bodyFor(stored, email: email);
      if (body == null) {
        await prefs.remove(key); // stale or unreadable: discarded, not retried
        return;
      }
      await Api.instance.updateNewsletterSettings(body);
      await prefs.remove(key);
    } catch (_) {
      // key stays — retried at the next sign-in or launch
    } finally {
      _inFlight = false;
    }
  }
}
