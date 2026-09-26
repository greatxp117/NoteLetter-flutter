// F-44a — the signed-out surfaces against the reference: one error
// vocabulary, the letter opt-in's replay body, the router's two signed-out
// routes, and the Google button on a build that is not set up for it.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/auth_errors.dart';
import 'package:flutter_app/services/google_sign_in_setup.dart';
import 'package:flutter_app/site/signin_page.dart';
import 'package:flutter_app/state/pending_letter_setup.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// The BUNDLED faces — the test font draws every glyph a full em wide, and
/// would overflow what the real type fits at a phone's width.
Future<void> _loadFonts() async {
  const faces = {
    'Geist': ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf'],
    'Geist Mono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
    'Source Serif 4': [
      'SourceSerif4-Variable.ttf',
      'SourceSerif4-Italic-Variable.ttf',
    ],
  };
  for (final e in faces.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await loader.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  group('auth errors', () {
    // Client against client: the reference's MAP, read from its source, must
    // be this client's sentence for sentence. A copy that is only compared to
    // itself drifts the day either side is edited.
    test('every reference code has the reference sentence', () {
      final js =
          File('../NoteLetter-web/src/shared/authErrors.js').readAsStringSync();
      final pairs = RegExp(r"'auth/([a-z-]+)':\s*'([^']*)'").allMatches(js);
      expect(pairs.length, greaterThanOrEqualTo(11));
      for (final m in pairs) {
        expect(humanizeAuthCode(m.group(1)), m.group(2),
            reason: 'auth/${m.group(1)}');
      }
      final fallback = RegExp(r"\|\|\s*'([^']*)'").firstMatch(js)!.group(1);
      expect(humanizeAuthCode('something-new'), fallback);
    });

    test('the SDK exception reaches the same sentence', () {
      expect(humanizeAuthError(FirebaseAuthException(code: 'wrong-password')),
          'Incorrect password.');
      expect(humanizeAuthError(const GoogleSignInNotSetUp()),
          'Google sign-in is not set up on this build.');
      expect(humanizeAuthError(StateError('x')),
          'Something went wrong. Please try again.');
    });
  });

  group('pending letter setup', () {
    final now = DateTime(2026, 9, 26, 12);
    String stored(Map<String, dynamic> m) => jsonEncode(m);

    test('replays the closed key set — never tone', () {
      final body = PendingLetterSetup.bodyFor(
        stored({
          'deliveryTime': '07:00',
          'tone': 'curious',
          'timezone': 'America/Chicago',
          'ts': now.millisecondsSinceEpoch,
        }),
        email: 'a@b.test',
        now: now,
      );
      expect(body, {
        'enabled': true,
        'emailAddress': 'a@b.test',
        'deliveryTime': '07:00',
        'timezone': 'America/Chicago',
      });
    });

    test('a key is present only with a value', () {
      final body = PendingLetterSetup.bodyFor(
          stored({'ts': now.millisecondsSinceEpoch}),
          email: null,
          now: now);
      expect(body, {'enabled': true});
    });

    test('older than seven days, unreadable or absent: nothing to send', () {
      final old = now.subtract(const Duration(days: 8)).millisecondsSinceEpoch;
      expect(PendingLetterSetup.bodyFor(stored({'ts': old}), now: now), isNull);
      expect(PendingLetterSetup.bodyFor('{not json', now: now), isNull);
      expect(PendingLetterSetup.bodyFor(stored({}), now: now), isNull);
      expect(PendingLetterSetup.bodyFor(null, now: now), isNull);
    });

    test('times read as the reference formats them', () {
      expect(PendingLetterSetup.times.map(PendingLetterSetup.formatTime),
          ['6:00am', '6:30am', '7:00am', '8:00am']);
      expect(PendingLetterSetup.formatTime('12:05'), '12:05pm');
      expect(PendingLetterSetup.formatTime('00:30'), '12:30am');
    });
  });

  test('the router lets a signed-out reader stay on both signed-out routes', () {
    expect(signedOutRoutes, {'/landing', '/signin'});
  });

  testWidgets(
      'Continue with Google on an unconfigured build says so, and does not '
      'crash', (tester) async {
    // `flutter test` runs as Android, whose OAuth client does not exist yet.
    expect(GoogleSignInSetup.available, isFalse);
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SignInPage()));
    await tester.pump();
    final google = find.text('Continue with Google');
    await tester.ensureVisible(google);
    await tester.tap(google);
    await tester.pump();
    await tester.pump();
    expect(find.text(GoogleSignInSetup.notSetUp), findsOneWidget);
  });

  testWidgets('/signin draws the reference\'s parts, in order', (tester) async {
    tester.view.physicalSize = const Size(402 * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const SignInPage()));
    await tester.pump();
    final order = [
      '← Back to the site',
      '§ SIGN IN',
      'EMAIL',
      'PASSWORD',
      'Sign in',
      'OR',
      'Continue with Google',
      'WHY NOTELETTER',
    ];
    double y(String s) => tester.getTopLeft(find.text(s).first).dy;
    for (var i = 1; i < order.length; i++) {
      expect(find.text(order[i]), findsWidgets, reason: order[i]);
      expect(y(order[i]), greaterThanOrEqualTo(y(order[i - 1])),
          reason: '${order[i]} after ${order[i - 1]} — on a phone the form '
              'comes first and the case under it');
    }
    // `.si-pw-row`: "Forgot it?" shares the password label's row.
    expect(
        (tester.getBottomLeft(find.text('Forgot it?')).dy -
                tester.getBottomLeft(find.text('PASSWORD')).dy)
            .abs(),
        lessThan(4));
    // Nothing the reference deliberately left out.
    expect(find.textContaining('sign-in link'), findsNothing);
  });
}
