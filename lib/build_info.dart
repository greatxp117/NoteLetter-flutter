/// Who this build says it is.
///
/// `clientVersion` is triage context on a support message
/// (`spec/api/support.md` §Validation) — the answer to "which build was this
/// reported from", which is the first question anyone answering a bug report
/// asks.
///
/// [contractPin] is a **second copy** of the pin declared in `CLAUDE.md`, and
/// the workspace's standing lesson about second copies applies: a vocabulary
/// written in two places with nothing comparing them drifts, silently, in the
/// direction nothing renders. So it is compared — `test/contract/
/// build_info_test.dart` parses the same line `pin_check_test.dart` does and
/// fails the moment these disagree.
class BuildInfo {
  BuildInfo._();

  /// The contract this client is pinned to. Advance with the CLAUDE.md pin,
  /// never on its own.
  static const String contractPin = '4.4.0';

  static const String platform = 'flutter';

  /// What a support message carries. Deliberately not a build timestamp: the
  /// pin is the fact that tells you what the client can and cannot do.
  static const String clientVersion = 'flutter/$contractPin';
}
