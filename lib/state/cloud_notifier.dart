import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/cloud_file.dart';
import '../models/cloud_integration.dart';
import '../models/import_job.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';

/// Import caps enforced by the picker (mirror `fn_import_from_cloud`).
const int kMaxImportFolders = 20;
const int kMaxImportFiles = 50;

/// One level in the picker breadcrumb.
class CloudCrumb {
  final String id; // provider-native folder id ('root' for the top)
  final String label;
  const CloudCrumb(this.id, this.label);
}

/// Drives the Sources cloud section: integrations, the live import-jobs
/// subscription (INV-02), the file picker, and the import/retry/sync actions.
class CloudNotifier extends ChangeNotifier {
  List<CloudIntegration> _integrations = [];
  bool _loadingIntegrations = false;

  List<ImportJob> _jobs = [];
  StreamSubscription<List<ImportJob>>? _jobsSub;

  // Picker state (single provider open at a time).
  String? _browseProvider;
  final List<CloudCrumb> _crumbs = [];
  CloudFileListing? _listing;
  bool _browsing = false;
  bool _loadingMore = false;
  String? _browseError;
  final Set<String> _selectedFolders = {};
  final Set<String> _selectedFiles = {};

  List<CloudIntegration> get integrations => List.unmodifiable(_integrations);
  bool get loadingIntegrations => _loadingIntegrations;
  List<ImportJob> get jobs => List.unmodifiable(_jobs);

  String? get browseProvider => _browseProvider;
  List<CloudCrumb> get crumbs => List.unmodifiable(_crumbs);
  CloudFileListing? get listing => _listing;
  bool get browsing => _browsing;
  bool get loadingMore => _loadingMore;
  String? get browseError => _browseError;
  Set<String> get selectedFolders => Set.unmodifiable(_selectedFolders);
  Set<String> get selectedFiles => Set.unmodifiable(_selectedFiles);
  bool get hasSelection =>
      _selectedFolders.isNotEmpty || _selectedFiles.isNotEmpty;

  CloudIntegration? integrationFor(String provider) {
    for (final i in _integrations) {
      if (i.provider == provider) return i;
    }
    return null;
  }

  /// Jobs for one provider (already newest-first from the subscription).
  List<ImportJob> jobsFor(String provider) =>
      _jobs.where((j) => j.provider == provider).toList();

  void start() {
    _jobsSub ??= FirestoreService.instance
        .subscribeCloudImportJobs()
        .listen((list) {
      _jobs = list;
      notifyListeners();
    });
    loadIntegrations();
  }

  Future<void> loadIntegrations() async {
    _loadingIntegrations = true;
    notifyListeners();
    try {
      final data = await ApiService.instance.get('/fn_get_cloud_integrations');
      final raw = (data['integrations'] as List?) ?? const [];
      _integrations = raw
          .map((e) => CloudIntegration.fromJson(e as Map<String, dynamic>))
          .toList();
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException {
      // Non-fatal — leave the prior list.
    } finally {
      _loadingIntegrations = false;
      notifyListeners();
    }
  }

  /// Start (or re-start, for reconnect) the OAuth flow. Returns an error string
  /// or null. The callback returns to /sources with `cloud_connect` params.
  Future<String?> connect(String provider) async {
    try {
      final data = await ApiService.instance
          .post('/fn_connect_cloud_storage', data: {'provider': provider});
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
      return 'Failed to start the connection.';
    }
  }

  Future<String?> disconnect(String provider) async {
    try {
      await ApiService.instance
          .post('/fn_disconnect_cloud_storage', data: {'provider': provider});
      _integrations.removeWhere((i) => i.provider == provider);
      if (_browseProvider == provider) closePicker();
      notifyListeners();
      return null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return 'Session expired.';
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      return 'Failed to disconnect.';
    }
  }

  // ── Picker ────────────────────────────────────────────────────────────────

  Future<void> openPicker(String provider) async {
    _browseProvider = provider;
    _crumbs
      ..clear()
      ..add(const CloudCrumb('root', 'Root'));
    _selectedFolders.clear();
    _selectedFiles.clear();
    await _fetchListing('root');
  }

  void closePicker() {
    _browseProvider = null;
    _crumbs.clear();
    _listing = null;
    _browseError = null;
    _selectedFolders.clear();
    _selectedFiles.clear();
    notifyListeners();
  }

  Future<void> enterFolder(CloudFile folder) async {
    _crumbs.add(CloudCrumb(folder.id, folder.name));
    await _fetchListing(folder.id);
  }

  Future<void> jumpToCrumb(int index) async {
    if (index < 0 || index >= _crumbs.length) return;
    final target = _crumbs[index];
    _crumbs.removeRange(index + 1, _crumbs.length);
    await _fetchListing(target.id);
  }

  Future<void> _fetchListing(String folderId) async {
    final provider = _browseProvider;
    if (provider == null) return;
    _browsing = true;
    _browseError = null;
    _listing = null;
    notifyListeners();
    try {
      final params = <String, dynamic>{'provider': provider};
      if (folderId != 'root') params['folderId'] = folderId;
      final data = await ApiService.instance
          .get('/fn_list_cloud_files', queryParameters: params);
      _listing = CloudFileListing.fromJson(data);
    } on ApiException catch (e) {
      _browseError = e.message;
    } catch (_) {
      _browseError = 'Could not list files.';
    } finally {
      _browsing = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    final provider = _browseProvider;
    final token = _listing?.nextPageToken;
    if (provider == null || token == null || _loadingMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final params = <String, dynamic>{'provider': provider, 'pageToken': token};
      final folderId = _crumbs.isNotEmpty ? _crumbs.last.id : 'root';
      if (folderId != 'root') params['folderId'] = folderId;
      final data = await ApiService.instance
          .get('/fn_list_cloud_files', queryParameters: params);
      final next = CloudFileListing.fromJson(data);
      _listing = CloudFileListing(
        items: [...?_listing?.items, ...next.items],
        nextPageToken: next.nextPageToken,
        folderId: next.folderId,
        provider: next.provider,
      );
    } on ApiException catch (e) {
      _browseError = e.message;
    } catch (_) {
      _browseError = 'Could not load more files.';
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// Toggle selection; returns a note when a cap blocks the toggle (else null).
  String? toggleFolder(String id) {
    if (_selectedFolders.contains(id)) {
      _selectedFolders.remove(id);
    } else {
      if (_selectedFolders.length >= kMaxImportFolders) {
        return 'Up to $kMaxImportFolders folders per import.';
      }
      _selectedFolders.add(id);
    }
    notifyListeners();
    return null;
  }

  String? toggleFile(String id) {
    if (_selectedFiles.contains(id)) {
      _selectedFiles.remove(id);
    } else {
      if (_selectedFiles.length >= kMaxImportFiles) {
        return 'Up to $kMaxImportFiles files per import.';
      }
      _selectedFiles.add(id);
    }
    notifyListeners();
    return null;
  }

  /// Kick off the import of the current selection. Returns (message, isError).
  Future<(String, bool)> importSelection() async {
    final provider = _browseProvider;
    if (provider == null || !hasSelection) {
      return ('Nothing selected.', true);
    }
    try {
      final data = await ApiService.instance.post('/fn_import_from_cloud', data: {
        'provider': provider,
        'folder_ids': _selectedFolders.toList(),
        'file_ids': _selectedFiles.toList(),
      });
      final f = (data['queued_folders'] as num?)?.toInt() ?? 0;
      final n = (data['queued_files'] as num?)?.toInt() ?? 0;
      closePicker();
      return ('Queued $f folder(s) and $n file(s).', false);
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return ('Session expired.', true);
    } on ApiException catch (e) {
      return (e.message, true);
    } catch (_) {
      return ('Import failed. Please try again.', true);
    }
  }

  Future<String?> retryJob(String jobId) async {
    try {
      await ApiService.instance
          .post('/fn_retry_import_job', data: {'job_id': jobId});
      return null; // subscription reflects the new status
    } on ApiException catch (e) {
      return e.message; // 409/429 copy is user-facing
    } catch (_) {
      return 'Retry failed. Please try again.';
    }
  }

  /// Manual "sync now" over the provider's configured sync folders.
  Future<(String, bool)> syncNow(String provider) async {
    try {
      final data = await ApiService.instance
          .post('/fn_request_cloud_sync', data: {'provider': provider});
      final f = (data['queued_folders'] as num?)?.toInt() ?? 0;
      return ('Checking $f folder(s)…', false);
    } on ApiException catch (e) {
      return (e.message, true); // 400 no-folders / 409 reconnect / 429 cooldown
    } catch (_) {
      return ('Sync failed. Please try again.', true);
    }
  }

  /// Validated partial update of a provider's auto-sync config (1.4.0). Only
  /// the provided keys are sent; the returned `integration` replaces the local
  /// copy (no optimistic state). Returns an error string or null.
  Future<String?> syncSettings(
    String provider, {
    bool? autoSyncEnabled,
    String? syncFrequency,
    int? syncPreferredHour,
    List<String>? folderIds,
    List<String>? includeTypes,
    List<String>? excludePatterns,
  }) async {
    final body = <String, dynamic>{'provider': provider};
    if (autoSyncEnabled != null) body['auto_sync_enabled'] = autoSyncEnabled;
    if (syncFrequency != null) body['sync_frequency'] = syncFrequency;
    if (syncPreferredHour != null) body['sync_preferred_hour'] = syncPreferredHour;
    if (folderIds != null) body['folder_ids'] = folderIds;
    if (includeTypes != null) body['include_types'] = includeTypes;
    if (excludePatterns != null) body['exclude_patterns'] = excludePatterns;
    try {
      final data =
          await ApiService.instance.post('/fn_sync_settings', data: body);
      final updated =
          CloudIntegration.fromJson(data['integration'] as Map<String, dynamic>);
      final i = _integrations.indexWhere((x) => x.provider == provider);
      if (i >= 0) {
        _integrations[i] = updated;
      } else {
        _integrations.add(updated);
      }
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message; // 400 validation copy is user-facing
    } catch (_) {
      return 'Could not update sync settings.';
    }
  }

  /// On-demand freshness check for a cloud-imported document (1.4.0). Returns
  /// the raw comparison map, or null on failure / non-cloud docs. Call at most
  /// once per reader open — never poll (INV-02).
  Future<Map<String, dynamic>?> checkSourceFreshness(String docId) async {
    try {
      return await ApiService.instance
          .get('/fn_check_source_freshness', queryParameters: {'docId': docId});
    } catch (_) {
      return null;
    }
  }

  /// Re-import the provider's current version into the same document (1.4.0).
  /// Progress rides the document's own subscription + the jobs subscription.
  Future<String?> updateFromSource(String documentId) async {
    try {
      await ApiService.instance
          .post('/fn_update_from_source', data: {'document_id': documentId});
      return null;
    } on ApiException catch (e) {
      return e.message; // 409/429 cooldown copy is user-facing
    } catch (_) {
      return 'Update failed. Please try again.';
    }
  }

  @override
  void dispose() {
    _jobsSub?.cancel();
    super.dispose();
  }
}
