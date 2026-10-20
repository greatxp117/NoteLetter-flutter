import 'package:flutter/foundation.dart';

/// The camera-roll sweep's sentences that name a platform (5.26.1, ADR-180;
/// `screens/settings.md` §Camera-roll sweep card, `screens/sources.md`
/// §Camera-roll sweep). Every other sentence is the same on both.
///
/// Chosen ONCE, by `CameraSweepHost.forApp`, and handed down; nothing below
/// reads the platform itself, so a test is iOS unless it says otherwise —
/// `flutter test` runs as Android by default, and a getter on the platform
/// would have quietly turned every iOS assertion into an Android one.
class SweepWords {
  const SweepWords._({
    required this.automaticNote,
    required this.deferredTitle,
    required this.deferredSentence,
  });

  /// The Automatic mode's description once the first catch-up is done.
  final String automaticNote;

  /// The status row counting deferred photos.
  final String deferredTitle;

  /// A tray card's refusal for a photo that is not readable here yet.
  final String deferredSentence;

  /// The retired iOS app's words, verbatim.
  static const ios = SweepWords._(
    automaticNote:
        'Automatic still means "next time the app runs, or when iOS gives us a '
        'moment in the background" — there’s no way to wake an app the instant '
        'a photo is taken.',
    deferredTitle: 'Waiting for iCloud',
    deferredSentence:
        'This photo hasn’t finished downloading from iCloud. '
        'It stays here and the next sweep will try again.',
  );

  /// Android's (5.26.1): no iCloud — a deferred photo is a file that would
  /// not open.
  static const android = SweepWords._(
    automaticNote:
        'Automatic still means "next time the app runs, or when Android gives '
        'us a moment in the background" — there’s no way to wake an app the '
        'instant a photo is taken.',
    deferredTitle: 'Couldn’t be opened yet',
    deferredSentence:
        'This photo couldn’t be opened on this phone. '
        'It stays here and the next sweep will try again.',
  );

  static SweepWords forPlatform(TargetPlatform p) =>
      p == TargetPlatform.android ? android : ios;
}
