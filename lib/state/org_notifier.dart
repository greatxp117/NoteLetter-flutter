import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/organization_settings.dart';
import '../models/organization_suggestion.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Drives the auto-organization surface (INV-13): the pending suggestion queue
/// (live subscription), org settings, and the resolve/enable/scan actions.
/// Clients never execute a reorg by approving a suggestion — the backend owns
/// write-backs (ADR-005).
class OrgNotifier extends ChangeNotifier {
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
      notifyListeners();
    });
    loadSettings();
  }

  Future<void> loadSettings() async {
    try {
      _settings = await FirestoreService.instance.getOrganizationSettings();
      notifyListeners();
    } catch (_) {
      // Non-fatal — keep defaults.
    }
  }

  /// Approve/decline pending suggestions (≤20 per call). On success the rows
  /// transition on the subscription — render pessimistically.
  Future<String?> resolve(List<String> ids, String action) async {
    _resolving.addAll(ids);
    notifyListeners();
    try {
      await ApiService.instance.post('/fn_resolve_organization_suggestions',
          data: {'suggestion_ids': ids, 'action': action});
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
  Future<String?> updateSettings(Map<String, dynamic> partial) async {
    try {
      final data = await ApiService.instance
          .put('/fn_organization_settings', data: partial);
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
      final data = await ApiService.instance
          .post('/fn_enable_organization', data: {'provider': provider});
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
      await ApiService.instance.post('/fn_set_organized_folders',
          data: {'provider': provider, 'root_folder_ids': rootFolderIds});
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not set organized folders.';
    }
  }

  /// Manual rescan. 409 COOLDOWN copy (5-minute window) is user-facing.
  Future<String?> scan(String provider, {String? folderId}) async {
    final body = <String, dynamic>{'provider': provider};
    if (folderId != null) body['folder_id'] = folderId;
    try {
      await ApiService.instance.post('/fn_scan_organization', data: body);
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
    final body = <String, dynamic>{'folder_id': folderId};
    if (regenerate) {
      body['regenerate'] = true;
    } else {
      body['charter_text'] = charterText ?? '';
    }
    try {
      await ApiService.instance.post('/fn_update_folder_charter', data: body);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Could not update the charter.';
    }
  }

  /// Build a reorganization plan for a document (1.2.0). Returns the raw plan
  /// map, or null on failure. Execution is a separate explicit step.
  Future<Map<String, dynamic>?> analyzeReorganization(String documentId) async {
    try {
      return await ApiService.instance.post('/fn_analyze_reorganization',
          data: {'document_id': documentId});
    } catch (_) {
      return null;
    }
  }

  Future<String?> executeReorganization(
      String planId, List<dynamic> operations) async {
    try {
      await ApiService.instance.post('/fn_execute_reorganization',
          data: {'plan_id': planId, 'operations': operations});
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
