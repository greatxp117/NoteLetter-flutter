import 'package:flutter/foundation.dart';

/// The camera roll's sentences that name a platform (5.26.1, ADR-180;
/// `screens/sources.md` §Camera roll, D's since 5.43.0, ADR-198). Every
/// other sentence is the same on both.
///
/// Chosen ONCE, by `CameraSweepHost.forApp`, and handed down; nothing below
/// reads the platform itself, so a test is iOS unless it says otherwise —
/// `flutter test` runs as Android by default, and a getter on the platform
/// would have quietly turned every iOS assertion into an Android one.
///
/// Until 5.43.0 this also held the Automatic mode's note, which named the
/// platform ("when iOS gives us a moment"). D's note says "your phone" on
/// both, so it is one sentence and lives with the camera roll's other copy.
class SweepWords {
  const SweepWords._({
    required this.deferredTitle,
    required this.deferredFigure,
    required this.deferredSentence,
  });

  /// The panel's deferred line, before its count ("Waiting for iCloud · 3").
  final String deferredTitle;

  /// Looking back's third figure, under its count ("waiting for iCloud").
  final String deferredFigure;

  /// A waiting photo's refusal when it is not readable here yet.
  final String deferredSentence;

  /// The retired iOS app's words, "sweep" made "look" in D (5.43.0).
  static const ios = SweepWords._(
    deferredTitle: 'Waiting for iCloud',
    deferredFigure: 'waiting for iCloud',
    deferredSentence:
        'This photo hasn’t finished downloading from iCloud. '
        'It stays here and the next look will try again.',
  );

  /// Android's (5.26.1): no iCloud — a deferred photo is a file that would
  /// not open.
  static const android = SweepWords._(
    deferredTitle: 'Couldn’t be opened yet',
    deferredFigure: 'couldn’t be opened yet',
    deferredSentence:
        'This photo couldn’t be opened on this phone. '
        'It stays here and the next look will try again.',
  );

  static SweepWords forPlatform(TargetPlatform p) =>
      p == TargetPlatform.android ? android : ios;
}
