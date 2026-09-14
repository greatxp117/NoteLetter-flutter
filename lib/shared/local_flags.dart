import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Client-local flags under `nl-*` keys — the mirror of the reference's
/// `shared/useLocalFlag.js`, on platform prefs rather than `localStorage`.
///
/// **UI state only, never mirrored to Firestore.** `nl-scripture` is
/// client-local *by contract* (ADR-027 §7): the letter's mode is contract
/// state, because the letter is generated server-side and the backend must
/// know — but the Scripture shelf and the citation-search affordance are a
/// per-device preference, like ADR-023's camera-roll settings. A consequence
/// worth stating, because it is correct and not a bug: a reader may have
/// lectionary letters arriving while a second device shows no Scripture UI at
/// all. Saying so explicitly is what stops a client inventing a sync for it.
///
/// A [ValueNotifier] rather than a read per screen: two surfaces read this one
/// (Search decides which question it is asking; Settings sets it), and a value
/// each of them cached at mount would leave them disagreeing until a reload.
class LocalFlags {
  LocalFlags._();

  /// Verse search (`spec/screens/search.md` §Citation echo, ADR-027 §7).
  /// **Off until the reader asks for it**, exactly as the reference defaults
  /// it: a citation is only a different question for someone who reads
  /// scripture, and for everyone else `Job 3` is a search.
  static const String scriptureKey = 'nl-scripture';

  static final ValueNotifier<bool> scripture = ValueNotifier<bool>(false);

  static Future<void>? _loading;

  /// Read the stored values once, whoever asks first.
  ///
  /// **Called by every reader, not only by `main`.** The integration harnesses
  /// build the widget tree themselves and never run `main`, so a load that
  /// lived only there would leave every flag at its default in exactly the
  /// runs that are supposed to be evidence — and a default that happens to
  /// match is a test passing for the wrong reason.
  static Future<void> ensureLoaded() => _loading ??= () async {
    final prefs = await SharedPreferences.getInstance();
    scripture.value = prefs.getBool(scriptureKey) ?? false;
  }();

  /// Write before you move: the stored value lands first, then the notifier —
  /// a control that flips its own state before the write hides a failure
  /// completely and reverts only on reload.
  static Future<void> setScripture(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(scriptureKey, on);
    scripture.value = on;
  }
}
