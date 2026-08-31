import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/cloud_file.dart';
import '../models/cloud_integration.dart';
import '../models/import_job.dart';
import '../services/api.dart';
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
      _evaluateSession();
      _notify();
    });
    loadIntegrations();
  }

  // ── Completion notifications (1.4.0, ADR-007 — client-side, sources.md) ──────
  // A tracked session = jobs that arrive on the subscription after a kickoff
  // this app session (picker import / Sync now). When such a session goes from
  // having non-terminal jobs to all-terminal, publish a one-shot summary the UI
  // shows as a local notification. No backend surface (INV-02).

  /// Set to a summary string when a tracked session completes; the UI reads and
  /// resets it. Never persisted.
  final ValueNotifier<String?> completionMessage = ValueNotifier(null);
  int? _sessionStartAt;
  bool _sawWorking = false;

  void _beginSession() {
    _sessionStartAt = DateTime.now().millisecondsSinceEpoch;
    _sawWorking = false;
  }

  void _evaluateSession() {
    final start = _sessionStartAt;
    if (start == null) return;
    // Jobs created at/after kickoff (2s slack for clock skew) are this session.
    final tracked =
        _jobs.where((j) => (j.createdAt ?? 0) >= start - 2000).toList();
    if (tracked.isEmpty) return;
    if (tracked.any((j) => !j.isTerminal)) {
      _sawWorking = true;
      return;
    }
    if (!_sawWorking) return; // instant/all-terminal → no transition to report
    final imported = tracked.where((j) => j.status == 'complete').length;
    final failed = tracked.where((j) => j.status == 'error').length;
    final skipped = tracked
        .where((j) => j.status == 'skipped' || j.status == 'cancelled')
        .length;
    completionMessage.value =
        '$imported imported · $failed failed · $skipped already imported/skipped';
    _sessionStartAt = null;
    _sawWorking = false;
  }

  Future<void> loadIntegrations() async {
    _loadingIntegrations = true;
    _notify();
    try {
      final data = await Api.instance.getCloudIntegrations();
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
      _notify();
    }
  }

  /// Start (or re-start, for reconnect) the OAuth flow. Returns an error string
  /// or null. The callback returns to /sources with `cloud_connect` params.
  Future<String?> connect(String provider) async {
    try {
      final data = await Api.instance.connectCloudStorage(provider);
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
      await Api.instance.disconnectCloudStorage(provider);
      _integrations.removeWhere((i) => i.provider == provider);
      if (_browseProvider == provider) closePicker();
      _notify();
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
    _notify();
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
    _notify();
    try {
      final params = <String, dynamic>{'provider': provider};
      if (folderId != 'root') params['folderId'] = folderId;
      final data = await Api.instance.listCloudFiles(params);
      _listing = CloudFileListing.fromJson(data);
    } on ApiException catch (e) {
      _browseError = e.message;
    } catch (_) {
      _browseError = 'Could not list files.';
    } finally {
      _browsing = false;
      _notify();
    }
  }

  Future<void> loadMore() async {
    final provider = _browseProvider;
    final token = _listing?.nextPageToken;
    if (provider == null || token == null || _loadingMore) return;
    _loadingMore = true;
    _notify();
    try {
      final params = <String, dynamic>{'provider': provider, 'pageToken': token};
      final folderId = _crumbs.isNotEmpty ? _crumbs.last.id : 'root';
      if (folderId != 'root') params['folderId'] = folderId;
      final data = await Api.instance.listCloudFiles(params);
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
      _notify();
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
    _notify();
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
    _notify();
    return null;
  }

  /// Kick off the import of the current selection. Returns (message, isError).
  Future<(String, bool)> importSelection() async {
    final provider = _browseProvider;
    if (provider == null || !hasSelection) {
      return ('Nothing selected.', true);
    }
    try {
      final data = await Api.instance.importFromCloud(
        provider,
        folderIds: _selectedFolders.toList(),
        fileIds: _selectedFiles.toList(),
      );
      final f = (data['queued_folders'] as num?)?.toInt() ?? 0;
      final n = (data['queued_files'] as num?)?.toInt() ?? 0;
      _beginSession();
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
      await Api.instance.retryImportJob(jobId);
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
      final data = await Api.instance.requestCloudSync(provider);
      final f = (data['queued_folders'] as num?)?.toInt() ?? 0;
      _beginSession();
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
    try {
      final data = await Api.instance.syncSettings(
        provider,
        autoSyncEnabled: autoSyncEnabled,
        syncFrequency: syncFrequency,
        syncPreferredHour: syncPreferredHour,
        folderIds: folderIds,
        includeTypes: includeTypes,
        excludePatterns: excludePatterns,
      );
      final updated =
          CloudIntegration.fromJson(data['integration'] as Map<String, dynamic>);
      final i = _integrations.indexWhere((x) => x.provider == provider);
      if (i >= 0) {
        _integrations[i] = updated;
      } else {
        _integrations.add(updated);
      }
      _notify();
      return null;
    } on ApiException catch (e) {
      return e.message; // 400 validation copy is user-facing
    } catch (_) {
      return 'Could not update sync settings.';
    }
  }


  /// Re-import the provider's current version into the same document (1.4.0).
  /// Progress rides the document's own subscription + the jobs subscription.
  Future<String?> updateFromSource(String documentId) async {
    try {
      await Api.instance.updateFromSource(documentId);
      return null;
    } on ApiException catch (e) {
      return e.message; // 409/429 cooldown copy is user-facing
    } catch (_) {
      return 'Update failed. Please try again.';
    }
  }

  /// Every notify here goes through [_notify], which is silent after dispose.
  ///
  /// This notifier's work is asynchronous by construction — an integrations
  /// fetch, a jobs subscription, an OAuth round trip — so a request in flight
  /// routinely outlives the screen that started it, and `notifyListeners()` on
  /// a disposed notifier throws. It surfaced as a device run that failed in a
  /// test that had already passed, which is the least legible failure a gate
  /// can produce.
  bool _disposed = false;

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _jobsSub?.cancel();
    completionMessage.dispose();
    super.dispose();
  }
}
