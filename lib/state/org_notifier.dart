import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/organization_settings.dart';
import '../models/organization_suggestion.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../shared/cooldown.dart';
import '../services/error_text.dart';

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
      _suggestionsError = describeSdkError(e);
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
      _settingsError = describeSdkError(e);
    }
    notifyListeners();
  }

  /// Approvals this session made, followed one document at a time until they
  /// land (4.92.0, ADR-126): id → the latest document, or the card at
  /// `approved` until its first snapshot. `applied` (or gone) leaves — the
  /// change is made; `failed` stays with the worker's sentence until cleared.
  final Map<String, OrganizationSuggestion> _outcomes = {};
  final Map<String, StreamSubscription<OrganizationSuggestion?>> _outcomeSubs =
      {};
  List<OrganizationSuggestion> get outcomes =>
      List.unmodifiable(_outcomes.values);

  void _follow(OrganizationSuggestion card) {
    final id = card.id;
    _outcomes[id] = card.withStatus('approved');
    _outcomeSubs[id]?.cancel();
    _outcomeSubs[id] = FirestoreService.instance
        .subscribeOrganizationSuggestion(id)
        .listen((doc) {
      if (!_outcomes.containsKey(id)) return;
      if (doc == null || doc.status == 'applied') {
        clearOutcome(id);
        return;
      }
      _outcomes[id] = doc;
      notifyListeners();
    }, onError: (e) {
      // An unreadable outcome is a hole, never a success: say so on the row.
      if (!_outcomes.containsKey(id)) return;
      _outcomes[id] = _outcomes[id]!
          .withStatus('failed', resolutionError: describeSdkError(e));
      notifyListeners();
    });
  }

  void clearOutcome(String id) {
    _outcomeSubs.remove(id)?.cancel();
    if (_outcomes.remove(id) != null) notifyListeners();
  }

  /// Approve/decline pending suggestions (≤20 per call). On success the rows
  /// transition on the subscription — render pessimistically.
  Future<String?> resolve(List<String> ids, String action) async {
    _resolving.addAll(ids);
    notifyListeners();
    try {
      final res = await Api.instance.resolveOrganizationSuggestions(ids, action);
      if (action == 'approve') {
        // Only what the server approved is followed; `skipped` ids were not
        // pending any more and are not this tap's outcome.
        final skipped = {
          for (final x in (res['skipped'] as List?) ?? const []) '$x'
        };
        for (final id in ids) {
          if (skipped.contains(id)) continue;
          final card = _suggestions.where((x) => x.id == id).firstOrNull ??
              OrganizationSuggestion(
                  id: id,
                  provider: '',
                  type: '',
                  confidence: 0,
                  reason: '',
                  status: 'approved');
          _follow(card);
        }
      }
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

  /// The sentence of a scan cooldown that carried NO number (a pre-4.107.0
  /// backend), per provider. It is still a WAIT, so it is said in the same calm
  /// slot over the provider's folders as one with a number — web's `waitNote`
  /// (23d21a8). With a number, the provider's `WaitKey.orgScan` carries the
  /// sentence instead and clears it at zero.
  final Map<String, String> _scanWaitNote = {};
  String? scanWaitNote(String provider) => _scanWaitNote[provider];

  /// Manual rescan. 409 COOLDOWN copy (5-minute window) is user-facing.
  ///
  /// A cooldown arrives here as a `409`, not a `429`, and its sentence names
  /// the exact remaining wait — so it is rendered verbatim, and our own
  /// 5-minute phrasing stands in only for a refusal that carried no sentence
  /// at all (C11; the reference does the same in `OrganizationPanel`).
  ///
  /// A cooldown is a wait, not a failure: it is calm copy, never §14.2's
  /// `--critical-text`, as Summary's Regenerate and Study say theirs
  /// (screens/reader.md, screens/study.md; web 23d21a8). Any other refusal is
  /// returned for the caller to say as one.
  Future<String?> scan(String provider, {String? folderId}) async {
    _scanning.add(provider);
    _scanWaitNote.remove(provider);
    notifyListeners();
    try {
      await Api.instance.scanOrganization(provider, folderId: folderId);
      return null;
    } on ApiException catch (e) {
      if (e.errorCode != 'COOLDOWN') return e.message;
      final said =
          cooldownSentence(e, 'Scanned recently — try again in a few minutes.');
      if (e.retryAfterS == null) _scanWaitNote[provider] = said;
      return said;
    } catch (_) {
      return 'Could not start a rescan.';
    } finally {
      _scanning.remove(provider);
      notifyListeners();
    }
  }

  /// A scan of [provider] is in flight — Rescan all's or one folder's. Every
  /// rescan of the provider is held for it and Rescan all reads "Scanning…",
  /// as the reference's one `rescanning` flag holds every rescan control in
  /// its panel (OrganizationPanel.jsx). Write before you move: nothing else
  /// changes until the answer arrives.
  final Set<String> _scanning = {};
  bool isScanning(String provider) => _scanning.contains(provider);

  /// Whether [scan]'s last refusal for [provider] was its cooldown — said in
  /// the calm slot over the folders, so the caller says nothing more.
  bool scanIsWaiting(String provider) =>
      _scanWaitNote.containsKey(provider) ||
      Cooldowns.instance.waiting(WaitKey.orgScan(provider));

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
    for (final sub in _outcomeSubs.values) {
      sub.cancel();
    }
    super.dispose();
  }
}
