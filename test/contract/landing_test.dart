// F-68 (F-44b) — the landing against LandingActual.jsx: its computed dateline,
// Fig. 1 drawn from the reference's own path strings, and the edition's parts
// in the reference's order at a phone's width and a desktop's.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/site/landing_bits.dart';
import 'package:flutter_app/site/landing_page.dart';
import 'package:flutter_app/state/theme_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('dateline', () {
    test('Vol. counts from 2026, No. is the day of the year', () {
      final a = Dateline.of(DateTime(2026, 9, 25));
      expect(a.stamp, 'Vol. I · No. 268');
      expect(a.day, 'Friday');
      expect(a.date, 'September 25, 2026');
      expect(Dateline.of(DateTime(2026, 1, 1)).no, 'No. 1');
      expect(Dateline.of(DateTime(2028, 12, 31)).stamp, 'Vol. III · No. 366');
      expect(Dateline.of(DateTime(2035, 3, 1)).vol, 'Vol. X');
    });

    test('roman as the reference writes it', () {
      expect([1, 4, 9, 14, 0].map(roman), ['I', 'IV', 'IX', 'XIV', 'I']);
    });
  });

  group('Fig. 1', () {
    // The strings are the reference's, read from its source — a curve copied
    // by hand is a second drawing that drifts from the first.
    test('the paths are LandingActual.jsx\'s, verbatim', () {
      final jsx =
          File('../NoteLetter-web/src/pages/LandingActual.jsx').readAsStringSync();
      expect(jsx, contains("const decay = '$curveDecay'"));
      final lifted = RegExp(r"const lifted = \[([\s\S]*?)\]\.join\(' '\)")
          .firstMatch(jsx)!
          .group(1)!;
      final parts = RegExp(r"'([^']*)'").allMatches(lifted).map((m) => m.group(1));
      expect(parts.join(' '), curveLifted);
      for (final (x, l) in curveMarks) {
        expect(jsx, contains("[${x.toInt()}, '$l']"));
      }
    });

    test('both paths read, and end where the reference ends them', () {
      for (final d in [curveDecay, curveLifted]) {
        final m = svgPath(d).computeMetrics().single;
        final end = m.getTangentForOffset(m.length)!.position;
        expect(end.dx, closeTo(900, .01));
        expect(end.dy, closeTo(d == curveDecay ? 240 : 40, .01));
      }
    });

    test('a command it cannot read is an error, not a dropped segment', () {
      expect(() => svgPath('M0 0 Q 1 1, 2 2'), throwsFormatException);
    });
  });

  Future<void> pump(WidgetTester tester, double width) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(width * 3, 874 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ThemeNotifier(),
      child: MaterialApp(theme: AppTheme.light, home: const LandingPage()),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  // The parts, top to bottom, as the reference stacks them at a phone's width.
  const order = [
    'VOL. I',
    'Free to start · No card · Your library stays yours',
    // the departments, by their numbered chips
    '§ 01', '§ 02', '§ 03', '§ 04', '§ 05',
    '§ 06', '§ 07', '§ 08', '§ 09', '§ 10',
    'Tomorrow, at the hour you choose.',
    'Independent, and staying that way',
  ];

  for (final width in [402.0, 1440.0]) {
    testWidgets('the edition, in order, at $width', (tester) async {
      await pump(tester, width);
      double y(String s) {
        // Chips exactly: `§ 02 · LECTURE` in the hero letter also holds `§ 02`.
        final f = s.startsWith('§ ')
            ? find.text(s)
            : find.textContaining(s, findRichText: true);
        expect(f, findsWidgets, reason: s);
        return tester.getTopLeft(f.first).dy;
      }

      for (var i = 1; i < order.length; i++) {
        expect(y(order[i]), greaterThan(y(order[i - 1])),
            reason: '${order[i]} after ${order[i - 1]}');
      }
      // The contents rail exists only above 980; the burger only at or below 940.
      expect(find.text('IN THIS EDITION'), width > 980 ? findsOneWidget : findsNothing);
      expect(find.byIcon(Icons.menu), width <= 940 ? findsOneWidget : findsNothing);
      // The addressable sign-in page has its one link, in the footer.
      expect(find.text('Sign in'), findsWidgets);
      // Stop the retyping loop and the ticker before the frame is torn down.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}
