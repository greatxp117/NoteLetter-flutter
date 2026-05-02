import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/newsletter_settings.dart';
import '../models/cloud_integration.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

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

  Future<void> _loadNewsletter() async {
    try {
      final data =
          await ApiService.instance.get('/fn_settings/newsletter');
      _newsletter = NewsletterSettings.fromJson(data);
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException catch (e) {
      _error = e.message;
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
      final data =
          await ApiService.instance.get('/fn_get_cloud_integrations');
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

  Future<String?> saveNewsletter(NewsletterSettings settings) async {
    _isSaving = true;
    _error = null;
    notifyListeners();
    try {
      final data = await ApiService.instance.put(
        '/fn_settings/newsletter',
        data: settings.toJson(),
      );
      _newsletter =
          NewsletterSettings.fromJson(data['settings'] as Map<String, dynamic>);
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
      final data = await ApiService.instance.post(
        '/fn_connect_cloud_storage',
        data: {'provider': provider},
      );
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
      await ApiService.instance.post(
        '/fn_disconnect_cloud_storage',
        data: {'provider': provider},
      );
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
