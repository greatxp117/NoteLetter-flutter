import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

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
///   back `noteletter://cloud-connect?…` with exactly the /sources params;
/// * **a web build** — the browser lands on `/sources?…`, which the router
///   reads.
/// Either way the return is HELD here and Sources takes it exactly once
/// ([take]): a claim is spent by its first request, so a second reader must
/// find nothing rather than send it again.
class CloudReturn {
  final String result;
  final String? claim;
  final String? provider;
  final String? reason;

  const CloudReturn(this.result, {this.claim, this.provider, this.reason});

  /// The return's params, from a `noteletter://cloud-connect?…` URL or a
  /// `/sources?…` route alike. Null when it carries no `cloud_connect`.
  static CloudReturn? fromParams(Map<String, String> q) {
    final result = q['cloud_connect'];
    if (result == null || result.isEmpty) return null;
    return CloudReturn(result,
        claim: q['claim'], provider: q['provider'], reason: q['reason']);
  }

  /// The scheme registered in the app binaries (`APP_RETURN_URL`'s, a
  /// constant: it moves only with an app release).
  static const appReturnScheme = 'noteletter';

  /// A claim's own lifetime (`api/cloud-storage.md`); a held return older
  /// than this can only answer 404, so it is dropped.
  static const _ttl = Duration(minutes: 10);

  /// The held return, and when it was held. Sources listens.
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
  static Future<String?> runSession(String authUrl) async {
    try {
      final back = await (session ??
          (url) => FlutterWebAuth2.authenticate(
              url: url, callbackUrlScheme: appReturnScheme))(authUrl);
      final r = CloudReturn.fromParams(Uri.parse(back).queryParameters);
      if (r != null) hold(r);
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      return e.message ?? 'The sign-in window could not be opened.';
    }
  }
}
