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
import '../services/analytics.dart';
import '../services/error_text.dart';

/// Import caps enforced by the picker (mirror `fn_import_from_cloud`).
const int kMaxImportFolders = 20;
const int kMaxImportFiles = 50;

/// Sentinel for "the disconnect response carried no `revoked` key" — distinct
/// from a JSON `null`, which is a claim (this provider has no revocation).
const Object revokedAbsent = _RevokedAbsent();

class _RevokedAbsent {
  const _RevokedAbsent();
}

/// One level in the picker breadcrumb.
class CloudCrumb {
  final String id; // provider-native folder id ('root' for the top)
  final String label;
  const CloudCrumb(this.id, this.label);
}

/// Drives the Sources cloud section: integrations, the live import-jobs
/// subscription (INV-02), the file picker, and the import/retry/sync actions.
class CloudNotifier extends ChangeNotifier {
  /// The import-jobs subscription's failure (INV-24).
  String? _jobsError;
  String? get jobsError => _jobsError;

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

  /// The held set (4.45.0, ADR-083) — jobs waiting on a judgement. Read off
  /// the one subscription the screen already holds; there is no second query
  /// and no count to keep in step.
  List<ImportJob> get heldJobs =>
      List.unmodifiable(_jobs.where((j) => j.isAwaitingReview));

  /// What the last triage batch did that the rows alone do not say (4.69.0,
  /// ADR-103 §4 amended). Null until a batch has answered. Kept HERE, not in
  /// the queue section: dismissing the last held file unmounts that section,
  /// and a line inside it about what just happened would vanish with it.
  ReviewOutcome? _reviewOutcome;
  ReviewOutcome? get reviewOutcome => _reviewOutcome;

  /// Triage held jobs. Returns a message on failure, null on success.
  ///
  /// **Renders pessimistically**: nothing is moved here. The rows leave the
  /// queue when the subscription says the write landed — a control that moves
  /// before the write hides the failure completely, and this one acts on files
  /// the reader may not be able to see.
  ///
  /// Chunked to the endpoint's 50-id cap. The 202 carries two id lists that
  /// mean opposite things, and BOTH are read into [reviewOutcome]: `skipped`
  /// is a judgement (already triaged elsewhere — not an error), `failed` is
  /// the task queue refusing, so the approve started nothing. The server stops
  /// at the first `failed` id, so the ids past it were never attempted and are
  /// still `awaiting_review`; this stops sending further chunks too, because
  /// the queue is down, not that file. Reading neither list put a queue outage
  /// under "success".
  Future<String?> reviewJobs(List<String> jobIds, String action) async {
    if (jobIds.isEmpty) return null;
    _reviewOutcome = null;
    _notify();
    var skipped = 0;
    final failed = <String>[];
    var attempted = 0;
    try {
      for (var i = 0; i < jobIds.length; i += 50) {
        final chunk = jobIds.sublist(
            i, i + 50 > jobIds.length ? jobIds.length : i + 50);
        final res = await Api.instance.reviewImportJobs(chunk, action);
        skipped += ((res['skipped'] as List?) ?? const []).length;
        final chunkFailed =
            ((res['failed'] as List?) ?? const []).map((e) => '$e').toList();
        failed.addAll(chunkFailed);
        attempted += chunk.length;
        if (chunkFailed.isNotEmpty) {
          // Everything after the first failed id in THIS chunk was not
          // attempted, and neither is any later chunk.
          final at = chunk.indexOf(chunkFailed.first);
          if (at >= 0) attempted -= chunk.length - (at + 1);
          break;
        }
      }
      _reviewOutcome = ReviewOutcome(
        skipped: skipped,
        failedNames: [for (final id in failed) _nameOf(id)],
        notAttempted: failed.isEmpty ? 0 : jobIds.length - attempted,
      );
      _notify();
      return null;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (_) {
      // Deliberate: `ApiException` above carries every reason the SERVER gave,
      // and this branch is what is left — a socket that never answered, a body
      // that would not parse. There is no rejection here to discard, so the
      // sentence is the only true thing that can be said, and it is still
      // rendered rather than swallowed.
      return action == 'approve'
          ? 'Those files could not be imported.'
          : 'Those files could not be dismissed.';
    }
  }

  String _nameOf(String jobId) {
    for (final j in _jobs) {
      if (j.id == jobId && j.providerFileName.isNotEmpty) {
        return j.providerFileName;
      }
    }
    return jobId;
  }

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
      _trackTransitions(list);
      _jobs = list;
      _jobsError = null;
      _evaluateSession();
      _notify();
    // INV-24 (ADR-071): an unread job list renders as "no imports running",
    // which is exactly what a reader watching an import wants to know is
    // false.
    }, onError: (e) {
      _jobsError = describeSdkError(e);
      _notify();
    });
    loadIntegrations();
  }

  // ── Progress section (screens/sources.md §Cloud import) ───────────────────
  // The section shows every non-terminal job plus THIS session's terminal
  // ones — never weeks-old history, which is §Import history's. A job is this
  // session's if it went terminal while this app watched it, or if it was
  // created since a kickoff made here.

  /// `created_at` is a SERVER stamp and the kickoff time is this device's
  /// clock. 2s of slack dropped a whole session whenever the server trailed
  /// the phone; the reference's two minutes is the tolerance (web
  /// `sinceKickoff`).
  static const int kKickoffSlackMs = 120000;

  /// How long folder discovery may keep adding jobs before a kickoff that
  /// produced none is called "already imported" (web: 60s).
  static const Duration kDiscoveryWindow = Duration(seconds: 60);

  ImportKickoff? _kickoff;
  ImportKickoff? get kickoff => _kickoff;
  bool _kickoffSettled = false;
  Timer? _settleTimer;
  final Set<String> _sessionIds = {};
  Map<String, String> _prevStatus = {};

  void _trackTransitions(List<ImportJob> next) {
    final prev = _prevStatus;
    final now = <String, String>{};
    for (final j in next) {
      now[j.id] = j.status;
      final before = prev[j.id];
      if (j.isTerminal && before != null && !ImportJob.isTerminalStatus(before)) {
        _sessionIds.add(j.id);
      }
    }
    _prevStatus = now;
  }

  bool _sinceKickoff(ImportJob j) {
    final k = _kickoff;
    final at = j.createdAt;
    return k != null && at != null && at >= k.at - kKickoffSlackMs;
  }

  /// The progress section's rows. `awaiting_review` is non-terminal but is
  /// NOT progress — it is the review queue's, and must not count twice.
  List<ImportJob> get progressJobs => [
        for (final j in _jobs)
          if (!j.isAwaitingReview &&
              (!j.isTerminal || _sessionIds.contains(j.id) || _sinceKickoff(j)))
            j,
      ];

  /// Terminal jobs, for §Import history (the whole subscription window).
  List<ImportJob> get historyJobs =>
      [for (final j in _jobs) if (j.isTerminal && j.createdAt != null) j];

  List<ImportJob> get _newJobs =>
      _kickoff == null ? const [] : progressJobs.where(_sinceKickoff).toList();

  /// Discovery is recursive and incremental, so M is not a total while a
  /// folder kickoff still has work in flight or has produced nothing yet.
  bool get discovering {
    final k = _kickoff;
    if (k == null || k.queuedFolders <= 0) return false;
    return progressJobs.any((j) => !j.isTerminal) ||
        (_newJobs.isEmpty && !_kickoffSettled);
  }

  /// A folder kickoff whose window closed with zero new jobs: everything
  /// there was already imported.
  bool get nothingNew {
    final k = _kickoff;
    return k != null &&
        k.queuedFolders > 0 &&
        _newJobs.isEmpty &&
        _kickoffSettled;
  }

  /// Kicked off, and no job has arrived yet — "Discovering files…".
  bool get awaitingFirstJob =>
      _kickoff != null && _newJobs.isEmpty && !_kickoffSettled;

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

  /// [queuedFolders] is the figure the 202 MEASURED, never the request's
  /// length — a kickoff's count is counted, not assumed (ADR-103).
  void _beginSession(int queuedFolders) {
    final at = DateTime.now().millisecondsSinceEpoch;
    _sessionStartAt = at;
    _sawWorking = false;
    _kickoff = ImportKickoff(at: at, queuedFolders: queuedFolders);
    _kickoffSettled = false;
    _settleTimer?.cancel();
    _settleTimer = Timer(kDiscoveryWindow, () {
      _kickoffSettled = true;
      _notify();
    });
  }

  void _evaluateSession() {
    final start = _sessionStartAt;
    if (start == null) return;
    // Jobs created since kickoff (server-clock slack) are this session. A held
    // job waits on the reader, not the pipeline, so it is not the session's to
    // finish — counting it kept a session open for ever.
    final tracked = _jobs
        .where((j) =>
            (j.createdAt ?? 0) >= start - kKickoffSlackMs &&
            !j.isAwaitingReview)
        .toList();
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

  /// The integrations read's failure (C4).
  ///
  /// It was swallowed as *"leave the prior list"* — true on a refresh and
  /// false on the only load that matters, because on first load the prior list
  /// is EMPTY. `integrationFor` then answers null for every provider and
  /// `_ProviderCard` draws each one as not connected, with a Connect button:
  /// a reader with a live Notion integration is invited to re-run OAuth
  /// against a service they are already connected to.
  String? _integrationsError;
  String? get integrationsError => _integrationsError;

  /// Whether the list on screen came from a read that SUCCEEDED. An empty list
  /// that was never read is not an account with nothing connected.
  bool _integrationsLoaded = false;
  bool get integrationsLoaded => _integrationsLoaded;

  Future<void> loadIntegrations() async {
    _loadingIntegrations = true;
    _notify();
    try {
      final data = await Api.instance.getCloudIntegrations();
      final raw = (data['integrations'] as List?) ?? const [];
      _integrations = raw
          .map((e) => CloudIntegration.fromJson(e as Map<String, dynamic>))
          .toList();
      _integrationsError = null;
      _integrationsLoaded = true;
    } on UnauthorizedException {
      await AuthService.instance.signOut();
    } on ApiException catch (e) {
      // The prior list is still shown — but the screen is told it is stale,
      // which is the half that was missing.
      _integrationsError = e.message;
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

  /// What the last disconnect did at the provider (4.89.0, ADR-123 §5):
  /// `(provider, revoked)`, where `revoked` is the response's `true · false ·
  /// null`, or [revokedAbsent] when the backend never asked. Kept HERE, not on
  /// the card: the card the reader tapped turns into "Not connected" the
  /// moment the write lands, and a sentence inside it would vanish with the
  /// state it is about. Cleared when the next disconnect starts.
  (String, Object?)? _lastDisconnect;
  (String, Object?)? get lastDisconnect => _lastDisconnect;

  void clearDisconnectNote() {
    if (_lastDisconnect == null) return;
    _lastDisconnect = null;
    _notify();
  }

  Future<String?> disconnect(String provider) async {
    try {
      final res = await Api.instance.disconnectCloudStorage(provider);
      // `containsKey`, not `res['revoked']`: an absent key and a JSON null are
      // two different claims, and only one of them is about the provider.
      _lastDisconnect =
          (provider, res.containsKey('revoked') ? res['revoked'] : revokedAbsent);
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

  /// The import's own refusal (§14.2), inline in the picker it came from —
  /// a 400 `UNKNOWN_KEYS` or cap (4.91.0, ADR-125 §2), a 403 `PLAN_LIMIT`, a
  /// 409 reconnect. It was a toast, gone before a sentence naming the cap
  /// could be read, over a picker that kept the same selection. Cleared when
  /// the picker opens, closes or tries again.
  String? _importError;
  String? get importError => _importError;

  Future<void> openPicker(String provider) async {
    _importError = null;
    _browseProvider = provider;
    _crumbs
      ..clear()
      ..add(const CloudCrumb('root', 'Root'));
    _selectedFolders.clear();
    _selectedFiles.clear();
    await _fetchListing('root');
  }

  void closePicker() {
    _importError = null;
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
    // The provider name is deliberately NOT a param: it is a closed set, but it
    // is also a fact about where this reader keeps their documents, and the
    // per-provider breakdown is already in activity_events where it belongs.
    // Neither are the folder or file ids, which are the reader's own tree.
    Analytics.track('capture_started', {'surface': 'cloud'});
    _importError = null;
    _notify();
    try {
      final data = await Api.instance.importFromCloud(
        provider,
        folderIds: _selectedFolders.toList(),
        fileIds: _selectedFiles.toList(),
      );
      Analytics.track('capture_completed', {'surface': 'cloud'});
      final f = (data['queued_folders'] as num?)?.toInt() ?? 0;
      final n = (data['queued_files'] as num?)?.toInt() ?? 0;
      _beginSession(f);
      closePicker();
      return ('Queued $f folder(s) and $n file(s).', false);
    } on UnauthorizedException {
      await AuthService.instance.signOut();
      return ('Session expired.', true);
    } on ApiException catch (e) {
      _importError = e.message;
      _notify();
      return (e.message, true);
    } catch (_) {
      _importError = 'Import failed. Please try again.';
      _notify();
      return (_importError!, true);
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
  ///
  /// A 429 is a WAIT, not a failure — the sentence is the server's, with its
  /// exact seconds, and it renders as a note; the 400 (no folders) and 409
  /// (reconnect) are refusals and render as §14.2.
  Future<(String, SyncNowResult)> syncNow(String provider) async {
    try {
      final data = await Api.instance.requestCloudSync(provider);
      final f = (data['queued_folders'] as num?)?.toInt() ?? 0;
      _beginSession(f);
      return ('Checking $f folder(s)…', SyncNowResult.queued);
    } on ApiException catch (e) {
      if (e.statusCode == 429) {
        return (
          cooldownSentence(e, 'A sync was requested moments ago.'),
          SyncNowResult.wait
        );
      }
      return (e.message, SyncNowResult.refused);
    } catch (_) {
      return ('Sync failed. Please try again.', SyncNowResult.refused);
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
    Map<String, dynamic>? reviewRules,
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
        reviewRules: reviewRules,
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
    _settleTimer?.cancel();
    _jobsSub?.cancel();
    completionMessage.dispose();
    super.dispose();
  }
}

/// A kickoff made on this device: when, and how many folders the 202 said it
/// queued (a kickoff is only "still discovering" when it queued folders).
class ImportKickoff {
  final int at;
  final int queuedFolders;
  const ImportKickoff({required this.at, required this.queuedFolders});
}

/// What a triage batch answered beyond the rows (4.69.0, ADR-103 §4).
class ReviewOutcome {
  /// Ids already triaged elsewhere — a measured count, not an error.
  final int skipped;

  /// Files the task queue refused to start, by NAME: the retry is per-row and
  /// the reader has to find it.
  final List<String> failedNames;

  /// Sent but never attempted — the server stopped at the first failure, so
  /// these are still waiting for review. Derived, never sent.
  final int notAttempted;

  const ReviewOutcome({
    required this.skipped,
    required this.failedNames,
    required this.notAttempted,
  });
}

/// What a Sync now answered: started, told to wait (429), or refused.
enum SyncNowResult { queued, wait, refused }
