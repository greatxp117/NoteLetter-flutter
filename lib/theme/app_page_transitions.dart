import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// A page change is plain: the next frame is the new page (`component-kit.md`
/// §40, *a client with no equivalent of view transitions conforms by changing
/// plainly; a half-built transition does not*).
///
/// Left to the platform default, every route change slid sideways for 430ms.
/// The pages in the shell draw no background of their own, because they lie on
/// the pane's ground, so the new page's text crossed over the old page's text
/// until the slide ended; a pushed Reader carried the app header and tab bar
/// across with it.
///
/// Only the DURATION is taken out. The builders stay the platform's, so the
/// back gestures live in them still (iOS's edge swipe, Android's predictive
/// back), and a finger still moves the page. Set here, on the theme, and not as
/// a `NoTransitionPage` per route: a new route cannot forget it.
const PageTransitionsTheme plainPageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.iOS: _PlainCupertino(),
    TargetPlatform.macOS: _PlainCupertino(),
    TargetPlatform.android: _PlainPredictiveBack(),
    TargetPlatform.fuchsia: _PlainPredictiveBack(),
    TargetPlatform.linux: _PlainPredictiveBack(),
    TargetPlatform.windows: _PlainPredictiveBack(),
  },
);

class _PlainCupertino extends CupertinoPageTransitionsBuilder {
  const _PlainCupertino();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}

class _PlainPredictiveBack extends PredictiveBackPageTransitionsBuilder {
  const _PlainPredictiveBack();

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;
}
