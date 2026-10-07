import 'package:flutter/foundation.dart';

import '../services/api_service.dart';

/// A cooldown's wait, as a NUMBER (4.107.0, ADR-140; component-kit §6.1
/// Waiting). The port of web `src/shared/cooldown.js`.
///
/// Every cooldown refusal the backend writes — a 429 `RATE_LIMITED` or the
/// organization scan's 409 `COOLDOWN` — carries `retry_after_s`, the whole
/// seconds until the same request would be accepted. C11 made the SENTENCE the
/// server's; this makes the wait something a control can act on. Before it, a
/// screen could only say "Please wait 43 seconds" and leave the button live,
/// so a second tap earned a second refusal.
///
/// One registry for the whole app, keyed by the endpoint and the thing its
/// cooldown is scoped to (a document, a job, a provider, a program — or
/// nothing, for the per-caller ones). A process-wide singleton and not widget
/// state, because the same document's Retry is drawn on the Sources tray and
/// on For your review, and a wait the server measured does not end because a
/// screen was rebuilt or left.
///
/// Armed ONLY from a refusal that arrived (write before you move): nothing
/// here is set before the request answers, and a refusal with no number arms
/// nothing — the seconds are never parsed out of the sentence.
class Cooldowns extends ChangeNotifier {
  Cooldowns._();

  static final Cooldowns instance = Cooldowns._();

  /// The clock a wait is measured on. A seam: `testWidgets` fakes timers but
  /// not `DateTime.now`, so a suite that steps through a wait moves both.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  /// key → (epoch ms the wait ends, the server's sentence or null).
  final Map<String, ({int until, String? sentence})> _waits = {};

  int get _now => clock().millisecondsSinceEpoch;

  /// Arm the wait [e] carried. Returns true when it armed — the caller then
  /// leaves the sentence to the control's wait rather than holding a copy of
  /// it that outlives the wait.
  bool arm(String key, ApiException e) {
    final s = e.retryAfterS;
    if (s == null || s < 1) return false;
    final sentence =
        e.serverSentence && e.message.trim().isNotEmpty ? e.message.trim() : null;
    _waits[key] = (until: _now + s * 1000, sentence: sentence);
    notifyListeners();
    return true;
  }

  /// Whole seconds left on [key]'s wait, 0 when there is none. Rounded UP, so
  /// the last fraction of a second still reads `0:01` and the control comes
  /// back exactly when the server would accept it.
  int left(String? key) {
    final w = key == null ? null : _waits[key];
    if (w == null) return 0;
    final ms = w.until - _now;
    if (ms > 0) return (ms + 999) ~/ 1000;
    // Forgotten, never resurrected. No notify: this runs inside a build.
    _waits.remove(key);
    return 0;
  }

  /// True while [key] is waiting — how a caller learns that the refusal it
  /// just received was a wait, and that the wait now owns its sentence.
  bool waiting(String? key) => left(key) > 0;

  /// The wait on [key] as one value: the seconds, and the server's sentence
  /// for as long as they run.
  CooldownWait of(String? key) {
    final n = left(key);
    return n > 0 ? CooldownWait(n, _waits[key]?.sentence) : CooldownWait.none;
  }

  /// How long until [key]'s whole-second figure next changes, or null when it
  /// is not waiting. A control ticks on this boundary rather than on a
  /// free-running second, so `0:01` turns into the idle label at the moment
  /// the wait ends and not up to a second later.
  Duration? untilNextSecond(String? key) {
    final w = key == null ? null : _waits[key];
    if (w == null) return null;
    final ms = w.until - _now;
    if (ms <= 0) return null;
    final rem = ms % 1000;
    return Duration(milliseconds: rem == 0 ? 1000 : rem);
  }

  /// For tests: forget every wait and put the real clock back.
  @visibleForTesting
  void resetForTest() {
    _waits.clear();
    clock = DateTime.now;
    notifyListeners();
  }
}

/// One control's wait: the seconds left, and the server's sentence while they
/// run. [none] is the idle state — no suffix, no sentence, the control live.
@immutable
class CooldownWait {
  final int left;
  final String? sentence;

  const CooldownWait(this.left, this.sentence);

  static const none = CooldownWait(0, null);

  bool get waiting => left > 0;

  /// ` · m:ss`, or '' when not waiting.
  String get suffix => waitSuffix(left);
}

/// The registry key: the endpoint, and what its cooldown is scoped to.
String cooldownKey(String endpoint, [String? target]) =>
    '$endpoint:${target ?? ''}';

/// The wait each cooldown-scoped request reads, keyed by what the SERVER
/// scopes its cooldown to (`api/endpoints.md` §Error shape). A control asks
/// `Cooldowns.instance.of(WaitKey.x(id))`; the [Api] builder arms the same key.
///
/// `fn_update_from_source` is keyed by the document it was pressed on; the
/// server measures the linked job's stamp, so a Retry on that job is a
/// separate key and its own refusal arms it (web `waitKey`).
abstract final class WaitKey {
  static String documentRetry(String docId) =>
      cooldownKey('fn_retry_document', docId);
  static String summaryRegen(String docId) =>
      cooldownKey('fn_regenerate_summary', docId);
  static String importJobRetry(String jobId) =>
      cooldownKey('fn_retry_import_job', jobId);
  static String cloudSync(String provider) =>
      cooldownKey('fn_request_cloud_sync', provider);
  static String sourceRefresh(String docId) =>
      cooldownKey('fn_update_from_source', docId);

  /// The PROVIDER's, whichever folder was asked for — a folder's rescan and
  /// Rescan all wait on one clock.
  static String orgScan(String provider) =>
      cooldownKey('fn_scan_organization', provider);

  /// The caller's: Send now on Letters and on Letter settings, one clock.
  static String letterSend() => cooldownKey('fn_request_newsletter');
  static String supportSend() => cooldownKey('fn_send_support_message');
  static String studySession(String programId) =>
      cooldownKey('fn_request_study_session', programId);
}

/// The label suffix of a waiting control: ` · 0:42`, ` · 4:58`; '' at zero.
String waitSuffix(int left) {
  if (left < 1) return '';
  final m = left ~/ 60;
  final s = (left % 60).toString().padLeft(2, '0');
  return ' · $m:$s';
}

/// Run a cooldown-scoped call, arming the wait its refusal carried (web
/// `withCooldown`). The refusal is rethrown untouched: arming is a fact the
/// registry records, never a change to what the caller is told.
Future<T> withCooldown<T>(String key, Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (e) {
    Cooldowns.instance.arm(key, e);
    rethrow;
  }
}
