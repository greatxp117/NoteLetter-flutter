import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/organization_settings.dart';
import '../models/organization_suggestion.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Drives the auto-organization surface (INV-13): the pending suggestion queue
/// (live subscription), org settings, and the resolve/enable/scan actions.
/// Clients never execute a reorg by approving a suggestion — the backend owns
/// write-backs (ADR-005).
class OrgNotifier extends ChangeNotifier {
  /// The suggestions subscription's failure (INV-24).
  String? _suggestionsError;
  String? get suggestionsError => _suggestionsError;

  List<OrganizationSuggestion> _suggestions = [];
  StreamSubscription<List<OrganizationSuggestion>>? _sub;
  OrganizationSettings _settings = const OrganizationSettings();
  final Set<String> _resolving = {};

  List<OrganizationSuggestion> get suggestions =>
      List.unmodifiable(_suggestions);
  OrganizationSettings get settings => _settings;
  bool isResolving(String id) => _resolving.contains(id);

  void start() {
    _sub ??= FirestoreService.instance
        .subscribeOrganizationSuggestions()
        .listen((list) {
      _suggestions = list;
      _suggestionsError = null;
      notifyListeners();
    // INV-24 (ADR-071): no suggestions and unreadable suggestions are the same
    // empty list downstream.
    }, onError: (e) {
      _suggestionsError = '$e';
      notifyListeners();
    });
    loadSettings();
  }

  /// Whether the stored settings have actually been READ (C4).
  ///
  /// This mattered more than the notice does. `_settings` starts at
  /// `const OrganizationSettings()` — the defaults — and a swallowed read left
  /// it there, indistinguishable from an account that really is on the
  /// defaults. The panel then drew those defaults as though they were stored,
  /// and `updateSettings` sends a PARTIAL: one nudge of the threshold slider
  /// wrote the default MODE over whatever the reader had chosen, from a screen
  /// that had never seen their settings. A read that cannot fail is
  /// indistinguishable from one that works, and here it silently destroyed the
  /// thing it was supposed to be showing.
  bool _settingsLoaded = false;
  bool get settingsLoaded => _settingsLoaded;

  String? _settingsError;
  String? get settingsError => _settingsError;

  Future<void> loadSettings() async {
    try {
      _settings = await FirestoreService.instance.getOrganizationSettings();
      _settingsError = null;
      _settingsLoaded = true;
    } catch (e) {
      _settingsError = '$e';
    }
    notifyListeners();
  }

  /// Approve/decline pending suggestions (≤20 per call). On success the rows
  /// transition on the subscription — render pessimistically.
  Future<String?> resolve(List<String> ids, String action) async {
    _resolving.addAll(ids);
    notifyListeners();
    try {
      await Api.instance.resolveOrganizationSuggestions(ids, action);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update. Please try again.';
    } finally {
      _resolving.removeAll(ids);
      notifyListeners();
    }
  }

  /// Partial update of org settings; returns the merged doc into local state.
  ///
  /// **Refuses before a successful read** (C4). The guard belongs here and not
  /// only on the screen: a partial write composed against unread state sends
  /// the DEFAULTS for every key the reader did not touch, and a screen that
  /// forgets the guard would do that damage silently. Two callers cannot each
  /// be trusted to remember; the writer can.
  Future<String?> updateSettings(Map<String, dynamic> partial) async {
    if (!_settingsLoaded) {
      return 'These settings have not been read yet, so saving would write '
          'defaults over what is stored. Reload and try again.';
    }
    try {
      final data = await Api.instance.updateOrganizationSettings(partial);
      _settings = OrganizationSettings.fromJson(data);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message; // 400 validation copy is user-facing
    } catch (_) {
      return 'Could not update organization settings.';
    }
  }

  /// Write-scope re-OAuth. The callback returns to /sources with
  /// `cloud_connect=success&org=enabled` on a full grant.
  Future<String?> enableOrganization(String provider) async {
    try {
      final data = await Api.instance.enableOrganization(provider);
      final authUrl = data['authUrl'] as String?;
      if (authUrl == null) return 'No authorization URL returned.';
      final ok = await launchUrl(Uri.parse(authUrl),
          mode: LaunchMode.externalApplication);
      return ok ? null : 'Could not open the browser for authorization.';
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return 'Session expired.';
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not start the upgrade.';
    }
  }

  Future<String?> setOrganizedFolders(
      String provider, List<String> rootFolderIds) async {
    try {
      await Api.instance.setOrganizedFolders(provider, rootFolderIds);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not set organized folders.';
    }
  }

  /// Manual rescan. 409 COOLDOWN copy (5-minute window) is user-facing.
  Future<String?> scan(String provider, {String? folderId}) async {
    try {
      await Api.instance.scanOrganization(provider, folderId: folderId);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not start a rescan.';
    }
  }

  /// Exactly one of charterText / regenerate.
  Future<String?> updateFolderCharter(String folderId,
      {String? charterText, bool regenerate = false}) async {
    try {
      await Api.instance.updateFolderCharter(folderId,
          charterText: charterText, regenerate: regenerate);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update the charter.';
    }
  }


  Future<String?> executeReorganization(
      String planId, List<dynamic> operations) async {
    try {
      await Api.instance.executeReorganization(planId, operations);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not execute the plan.';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
