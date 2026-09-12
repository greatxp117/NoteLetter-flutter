import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/newsletter_settings.dart';
import '../models/cloud_integration.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

class SettingsNotifier extends ChangeNotifier {
  NewsletterSettings? _newsletter;
  List<CloudIntegration> _integrations = [];
  bool _isLoading = false;
  bool _isSaving = false;
  String? _error;

  NewsletterSettings? get newsletter => _newsletter;
  List<CloudIntegration> get integrations =>
      List.unmodifiable(_integrations);
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get error => _error;

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([_loadNewsletter(), _loadIntegrations()]);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Settings are a direct one-shot Firestore read, not a function call
  // (spec/api/newsletter.md — only the PUT re-embeds purposeText and needs
  // a function).
  Future<void> _loadNewsletter() async {
    try {
      _newsletter = await FirestoreService.instance.getNewsletterSettings();
    } catch (_) {
      _error = 'Could not load newsletter settings.';
    }
  }

  Future<void> loadIntegrations() async {
    await _loadIntegrations();
    notifyListeners();
  }

  Future<void> _loadIntegrations() async {
    try {
      final data = await Api.instance.getCloudIntegrations();
      final rawList = data['integrations'] as List? ?? [];
      _integrations = rawList
          .map((e) =>
              CloudIntegration.fromJson(e as Map<String, dynamic>))
          .toList();
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException {
      // Non-fatal
    } catch (_) {
      // Ignore
    }
  }

  /// The raw body of the last `fn_newsletter_settings` PUT, so the screen can
  /// read `activationSend` (2.30.0). Null until a save happens.
  Map<String, dynamic>? lastActivation;

  /// The letter form's Save — every editable key **except `enabled`**.
  ///
  /// The switch owns `enabled` and writes it on its own ([setScheduledDelivery]).
  /// Two writers for one field is how a screen starts disagreeing with itself:
  /// a Save that carried the switch's value would also re-send `enabled: true`
  /// on every unrelated edit, and 2.30.0's activation send is keyed on the
  /// TRANSITION, so a client that includes the key in an unrelated partial save
  /// is one deploy away from mailing its user for a typo fix.
  Future<String?> saveLetterSettings({
    required String emailAddress,
    required String frequency,
    required String deliveryTime,
    required String timezone,
    required String purposeText,
    required int itemsPerNewsletter,
    required int excludeRecentDays,
    List<String>? topicFilters,
  }) =>
      _put({
        'emailAddress': emailAddress,
        'frequency': frequency,
        'deliveryTime': deliveryTime,
        // 2.29.0 — sent in the SAME call as `deliveryTime`, always. An hour
        // with no zone is UTC, which is nobody's morning by choice.
        'timezone': timezone,
        'purposeText': purposeText,
        'itemsPerNewsletter': itemsPerNewsletter,
        'excludeRecentDays': excludeRecentDays,
        if (topicFilters != null) 'topicFilters': topicFilters,
      });

  /// Scheduled delivery, from wherever the reader is (2.29.0 rule 1). Off is a
  /// **pause**: it keeps every other setting, and "Send now" keeps working.
  ///
  /// Turning it ON stores the zone too, because `deliveryTime` alone is read as
  /// UTC by the orchestrator.
  Future<String?> setScheduledDelivery({
    required bool enabled,
    required String deliveryTime,
    required String timezone,
  }) =>
      _put(enabled
          ? {
              'enabled': true,
              'deliveryTime': deliveryTime,
              'timezone': timezone,
            }
          : {'enabled': false});

  /// One PUT path, so `activationSend` is captured and the stored document is
  /// re-read the same way whatever wrote it.
  Future<String?> _put(Map<String, dynamic> partial) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      final res = await Api.instance.updateNewsletterSettings(partial);
      // 2.30.0 (ADR-031): present only when this request TRANSITIONED delivery
      // on. Kept so the screen can state what the backend decided instead of
      // inferring it — the reason vocabulary is open.
      lastActivation = res;
      // Response echoes only the applied partial update — re-read the full
      // doc from Firestore rather than assume its shape.
      _newsletter = await FirestoreService.instance.getNewsletterSettings();
      return null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return 'Session expired.';
    } on ApiException catch (e) {
      _error = e.message;
      return e.message;
    } catch (_) {
      const msg = 'Failed to save settings. Please try again.';
      _error = msg;
      return msg;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<String?> connectProvider(String provider) async {
    try {
      final data = await Api.instance.connectCloudStorage(provider);
      final authUrl = data['authUrl'] as String?;
      if (authUrl == null) return 'No auth URL returned from server.';
      final uri = Uri.parse(authUrl);
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) return 'Could not open the browser for authorization.';
      return null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return 'Session expired.';
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to start cloud storage connection.';
    }
  }

  Future<String?> disconnectProvider(String provider) async {
    try {
      await Api.instance.disconnectCloudStorage(provider);
      _integrations.removeWhere((i) => i.provider == provider);
      notifyListeners();
      return null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return 'Session expired.';
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to disconnect. Please try again.';
    }
  }

  bool isConnected(String provider) =>
      _integrations.any((i) => i.provider == provider && i.tokenValid);

  CloudIntegration? integrationFor(String provider) {
    try {
      return _integrations.firstWhere((i) => i.provider == provider);
    } catch (_) {
      return null;
    }
  }
}
