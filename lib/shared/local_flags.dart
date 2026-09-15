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

  /// First-run onboarding, done or skipped (`spec/screens/onboarding.md`
  /// §When it is shown).
  ///
  /// **Client-local, not contract state, and deliberately so**: it is a
  /// per-device first-run experience, and mirroring it to Firestore would have
  /// a second device re-deciding what the first already did. Skipping sets it
  /// exactly as finishing does — skipping is a decision, not a deferral, and
  /// the flow stays reachable from Settings either way.
  static const String onboardedKey = 'nl-onboarded';

  static final ValueNotifier<bool> onboarded = ValueNotifier<bool>(false);

  /// The replay Settings asks for ("Run through setup again") — **not stored**.
  ///
  /// It outlives no launch by design: a replay is one trip through the flow,
  /// and a persisted one would put the reader back in the wizard the next time
  /// they open the app. Not a [SharedPreferences] key for the same reason.
  static final ValueNotifier<bool> onboardingReplay = ValueNotifier<bool>(false);

  /// When the reader last looked at the Activity feed, epoch ms
  /// (`spec/screens/activity.md` §Toasts and unread, 2.5.0/ADR-014).
  ///
  /// **Client-local by contract, not contract data** — the reference keeps it
  /// in `localStorage` under this exact key, beside theme and density, and it
  /// deliberately does not sync across devices in Phase A. A device that has
  /// not seen a run of events still has them to read.
  ///
  /// An `int` here where the reference stores the same number as a string:
  /// this is the platform store, not `localStorage`, and a string would be a
  /// transcription of a JS limitation. The VALUE is the contract; its
  /// encoding is the client's.
  static const String activityLastSeenKey = 'nl-activity-last-seen';

  /// A [ValueNotifier] for the same reason [scripture] is one: two surfaces
  /// read it (the rail's badge and the feed, which marks it), and a value each
  /// cached at mount would leave the badge lit on the screen that cleared it.
  static final ValueNotifier<int> activityLastSeen = ValueNotifier<int>(0);

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
    onboarded.value = prefs.getBool(onboardedKey) ?? false;
    activityLastSeen.value = prefs.getInt(activityLastSeenKey) ?? 0;
  }();

  /// Write before you move: the stored value lands first, then the notifier —
  /// a control that flips its own state before the write hides a failure
  /// completely and reverts only on reload.
  static Future<void> setScripture(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(scriptureKey, on);
    scripture.value = on;
  }

  /// Write before you move, as [setScripture] does — and here the write is the
  /// whole point: the flag is what stops the wizard reappearing, so a value
  /// adopted in memory before the store accepted it is a wizard that comes
  /// back on the next launch.
  static Future<void> setOnboarded(bool done) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(onboardedKey, done);
    onboarded.value = done;
  }

  /// The feed was looked at [atMs]. Never moves backwards: the reader is on
  /// the screen while events arrive, and a mark taken from an older frame
  /// would re-light the badge for events they are watching land.
  static Future<void> markActivitySeen(int atMs) async {
    if (atMs <= activityLastSeen.value) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(activityLastSeenKey, atMs);
    activityLastSeen.value = atMs;
  }
}
