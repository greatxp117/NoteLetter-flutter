import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_providers.dart';

/// The cloud-connect return (5.0.0, ADR-158, INV-32; 5.1.0, ADR-159 —
/// `api/cloud-storage.md` §Return target). Mirrors web `shared/cloudClaim.js`.
///
/// The callback no longer says a connection happened. It parks the consent
/// and returns `cloud_connect=claim&claim=…&provider=…` (or
/// `cloud_connect=error&reason=…`), and only the account that STARTED the
/// connection can finish it, by sending the claim to
/// `fn_claim_cloud_connection` signed in. `cloud_connect=success` in a URL is
/// believed by nobody.
///
/// Where the return arrives:
/// * **this app on a phone** (`return: "app"`) — the consent runs in an
///   in-app auth session waiting for [appReturnScheme], and the session hands
///   back `noteletter://cloud-connect?…` with exactly the callback's params;
/// * **a web build** — the browser lands on `/connect?…` (`/sources?…` until
///   5.51.x, which the router forwards), whose redirect holds it here.
/// Either way the return is HELD here and the connect page takes it exactly
/// once ([take]): a claim is spent by its first request, so a second reader
/// must find nothing rather than send it again. Since 5.52.0 (ADR-203) that
/// page is its own route, [location] — until then it drew in place on Sources.
class CloudReturn {
  final String result;
  final String? claim;
  final String? provider;
  final String? reason;

  const CloudReturn(this.result, {this.claim, this.provider, this.reason});

  /// The return's params, from a `noteletter://cloud-connect?…` URL or a
  /// `/connect?…` route alike. Null when it carries no `cloud_connect`.
  static CloudReturn? fromParams(Map<String, String> q) {
    final result = q['cloud_connect'];
    if (result == null || result.isEmpty) return null;
    return CloudReturn(result,
        claim: q['claim'], provider: q['provider'], reason: q['reason']);
  }

  /// The scheme registered in the app binaries (`APP_RETURN_URL`'s, a
  /// constant: it moves only with an app release).
  static const appReturnScheme = 'noteletter';

  /// The connect page's address for [provider] (5.52.0, ADR-203;
  /// `screens/sources.md` §The OAuth return): `/connect/{provider}` by the
  /// stored id — never a second spelling of the four — or `/connect` when the
  /// return names none this client knows.
  static String location(String? provider) =>
      provider != null && cloudProviders.containsKey(provider)
          ? '/connect/$provider'
          : '/connect';

  /// Whether [path] is the connect page's (`/connect`, `/connect/{provider}`).
  static bool isConnectPath(String path) =>
      path == '/connect' || path.startsWith('/connect/');

  /// A claim's own lifetime (`api/cloud-storage.md`); a held return older
  /// than this can only answer 404, so it is dropped.
  static const _ttl = Duration(minutes: 10);

  /// The held return, and when it was held. The app shell and an open
  /// connect page listen (`pages/sources/oauth_return.dart`).
  static final ValueNotifier<CloudReturn?> pending = ValueNotifier(null);
  static DateTime? _heldAt;

  static void hold(CloudReturn r) {
    _heldAt = DateTime.now();
    pending.value = r;
  }

  /// The return, removed as it is read.
  static CloudReturn? take() {
    final r = pending.value;
    final at = _heldAt;
    pending.value = null;
    _heldAt = null;
    if (r == null) return null;
    if (at != null && DateTime.now().difference(at) > _ttl) return null;
    return r;
  }

  /// Whether this build asks for its own return: only a build that runs the
  /// consent in an in-app auth session sends `return: "app"` — a browser
  /// cannot receive `noteletter://`, and web is already the default.
  static bool get appReturn => !kIsWeb;

  /// The auth session — the plugin's, unless a test stands in for the
  /// consent (it answers the URL the session returns, or throws its
  /// `PlatformException`).
  @visibleForTesting
  static Future<String> Function(String url)? session;

  /// Runs the consent at [authUrl] in an in-app auth session and HOLDS what
  /// it returns. Null when it returned (or was cancelled — a cancelled session
  /// parked nothing and says nothing; Connect stays actionable), or the
  /// sentence for a session that could not run at all.
  ///
  /// [provider] is the one this session sent to consent (5.46.0, ADR-201): an
  /// error return carries no `provider` (`api/cloud-storage.md` §Result
  /// params), so the return page could only say *the service* when a reader
  /// declines at Google. The session that ran knows, and fills it in; a
  /// provider the return DID carry is never overwritten.
  static Future<String?> runSession(String authUrl, {String? provider}) async {
    try {
      final back = await (session ??
          (url) => FlutterWebAuth2.authenticate(
              url: url, callbackUrlScheme: appReturnScheme))(authUrl);
      final r = CloudReturn.fromParams(Uri.parse(back).queryParameters);
      if (r != null) {
        hold(r.provider == null && provider != null
            ? CloudReturn(r.result,
                claim: r.claim, provider: provider, reason: r.reason)
            : r);
      }
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      return e.message ?? 'The sign-in window could not be opened.';
    }
  }

  // ── The remembered provider (5.46.0, ADR-201) ──────────────────────────────
  // Which provider this client last sent to a consent screen, for the
  // state's ten minutes. Written by the one connect entry point
  // (`CloudNotifier.connect`) before the handoff, and read when an error
  // return names none. An app's session fills the return itself
  // ([runSession]); a WEB build leaves the page for the provider and comes
  // back as a fresh load, so there it is also kept in the platform store
  // (web: `sessionStorage` `nl-cloud-connecting`, `shared/cloudClaim.js`).
  // Read, never cleared: a reader may decline and try the same one again.

  static const connectingKey = 'nl-cloud-connecting';
  static String? _connecting;
  static DateTime? _connectingAt;

  static void noteConnecting(String provider) {
    final at = DateTime.now();
    _connecting = provider;
    _connectingAt = at;
    if (kIsWeb) unawaited(_keepConnecting(provider, at));
  }

  static Future<void> _keepConnecting(String provider, DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(connectingKey, jsonEncode(
          {'provider': provider, 'at': at.millisecondsSinceEpoch}));
    } catch (_) {
      // No store: an error return then names no provider, and says *the
      // service* — true, and no worse than before 5.46.0.
    }
  }

  /// The provider sent to consent within the ten minutes, from this run's
  /// memory; null when none (or it is older).
  static String? get connectingProvider {
    final at = _connectingAt;
    if (_connecting == null || at == null) return null;
    return DateTime.now().difference(at) > _ttl ? null : _connecting;
  }

  /// [connectingProvider], or — on a web build that came back as a fresh
  /// load — the one the page that left for consent stored.
  static Future<String?> recallConnecting() async {
    final mem = connectingProvider;
    if (mem != null || !kIsWeb) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(connectingKey);
      if (raw == null) return null;
      final v = jsonDecode(raw);
      if (v is! Map || v['provider'] is! String) return null;
      final at = DateTime.fromMillisecondsSinceEpoch(
          (v['at'] as num?)?.toInt() ?? 0);
      if (DateTime.now().difference(at) > _ttl) return null;
      return v['provider'] as String;
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void forgetConnecting() {
    _connecting = null;
    _connectingAt = null;
  }
}

/// What the connect page hands the Library as it leaves (5.52.0, ADR-203;
/// web `shared/connectHandoff.js`): the sentence *Bring in* earned, and the
/// two answers about organization rather than a connection — `org:
/// "enabled"` and `insufficient_scope` — which have always been the Library's
/// notices. The page has its own route now, so they cross a navigation. The
/// import's kickoff does not ride here: it is [CloudNotifier]'s, which the
/// Library already reads.
typedef LibraryHandoff = ({
  String? note,
  String? orgEnabled,
  ({String? provider, String reason})? connectError,
});

class ConnectHandoff {
  ConnectHandoff._();

  /// The Library listens (it may be mounted under the connect page) and reads
  /// it on mount; whichever comes first takes it, once.
  static final ValueNotifier<LibraryHandoff?> pending = ValueNotifier(null);

  /// Merged, never replaced. Nothing to say is no handoff: *Not now* leaves
  /// the Library exactly as it was.
  static void handOff({
    String? note,
    String? orgEnabled,
    ({String? provider, String reason})? connectError,
  }) {
    if (note == null && orgEnabled == null && connectError == null) return;
    final p = pending.value;
    pending.value = (
      note: note ?? p?.note,
      orgEnabled: orgEnabled ?? p?.orgEnabled,
      connectError: connectError ?? p?.connectError,
    );
  }

  /// The handoff, removed as it is read.
  static LibraryHandoff? take() {
    final v = pending.value;
    pending.value = null;
    return v;
  }
}
