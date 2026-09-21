import 'package:flutter/foundation.dart';

import '../models/scripture_newsletter_settings.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import 'schedule.dart';
import '../services/error_text.dart';

/// `/users/{uid}/settings/scripture_newsletter` — the readings letter's own
/// settings document (2.24.0, ADR-029; 4.24.0, ADR-061).
///
/// **Read through the Firestore SDK, written through the endpoint.**
/// `fn_scripture_newsletter_settings` answers `GET` with a deliberate 410, and
/// this client used to call it anyway — so the readings panel resolved to a
/// failure on every single render and the opt-in card could never appear at
/// all.
///
/// Every write here is a PUT of the whole document, and it goes out **before**
/// any control moves (ADR-022).
class ScriptureLetterNotifier extends ChangeNotifier {
  ScriptureNewsletterSettings? _settings;
  String? _error;
  String? _saveError;
  bool _isSaving = false;

  /// Null while unread. An absent document is `const
  /// ScriptureNewsletterSettings()` — never opted in, which is a real answer
  /// — and is not the same thing as a read that failed.
  ScriptureNewsletterSettings? get settings => _settings;

  /// INV-24: a failed read of this document, kept separate from a rejected
  /// write. A screen that renders the defaults on a read failure tells a reader
  /// who has the letter ON that it is off.
  String? get error => _error;
  String? get saveError => _saveError;
  bool get isSaving => _isSaving;

  Future<void> load() async {
    try {
      _settings =
          await FirestoreService.instance.getScriptureNewsletterSettings();
      _error = null;
    } catch (e) {
      _error = describeFirestoreError(e);
    }
    notifyListeners();
  }

  /// Opting in writes the whole starting document in one PUT — every key comes
  /// from the closed set, so nothing here can 400 on an unknown key.
  Future<void> turnOn() => save((_settings ?? const ScriptureNewsletterSettings())
      .copyWith(
        enabled: true,
        deliveryTime: (_settings?.deliveryTime.isNotEmpty ?? false)
            ? _settings!.deliveryTime
            : '06:30',
        // 2.29.0 — a client that sends `deliveryTime` sends `timezone` in the
        // SAME call, or the orchestrator reads the stored hour as UTC.
        timezone: (_settings?.timezone.isNotEmpty ?? false)
            ? _settings!.timezone
            : deviceTimezone(),
      ));

  /// Write, THEN move (ADR-022). Local state is adopted only once the PUT has
  /// answered: an optimistic switch that reverts on reload is indistinguishable
  /// from one that worked, which is how a colour change appeared to save for
  /// months.
  Future<void> save(ScriptureNewsletterSettings next) async {
    _isSaving = true;
    _saveError = null;
    notifyListeners();
    try {
      await Api.instance.updateScriptureNewsletterSettings(next.toJson());
      _settings = next;
    } on ApiException catch (e) {
      _saveError = e.message;
    } catch (e) {
      _saveError = describeFirestoreError(e);
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
