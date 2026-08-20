import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/router.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/support_shell.dart';

/// **INV-22 — the way to reach a human is composed once, by the shell.**
///
/// The rule's failure mode is silent and one-directional: the fourteenth screen
/// renders correctly and is simply the one with no way out. Nothing throws, no
/// test goes red, and the only person who finds out is a user who had a bug to
/// report and gave up. So the gate has to answer a structural question — *is
/// every authenticated route underneath the thing that draws the footer?* —
/// rather than check that some file contains some string.
///
/// It walks the **real route table** from [createRouter], not a list of its
/// own. A hand-written list here would reproduce, inside the test, the exact
/// defect the test exists to prevent: the route someone forgot to add.
///
/// The web reference gates this by mounting the shell at every route
/// (`tests/contract/support-footer.test.js`). This client cannot: every screen
/// constructs notifiers that reach `FirebaseFirestore.instance`, and there is
/// no Firebase app in a plain widget test (`test/widget_test.dart` records the
/// same limitation). So the gate is split — the route table is asserted here,
/// and the **rendered** footer is asserted here too, on the real
/// [SupportShell]; the two together say what one mount says on web. The device
/// run (`integration_test/device_run_test.dart`) closes it on a real renderer
/// against the emulator.

/// The routes INV-22 exempts, named so that each is a decision rather than an
/// oversight. Anything else outside the shell is a defect.
///
/// - `/landing` — pre-auth. Sending a message requires a signed-in caller
///   (INV-01), so there is nothing for the footer to link to.
/// - A first-run onboarding wizard would be the second exemption; this client
///   has none, so the set is one entry long. When it gets one it goes *outside*
///   the shell route, never behind a condition inside the footer.
const _exempt = {'/landing'};

/// Every `GoRoute` in the tree below [route], as full paths.
List<String> _goRoutePaths(RouteBase route, String prefix) {
  final out = <String>[];
  if (route is GoRoute) {
    final path = route.path.startsWith('/')
        ? route.path
        : '$prefix/${route.path}';
    out.add(path);
    for (final child in route.routes) {
      out.addAll(_goRoutePaths(child, path));
    }
  } else {
    for (final child in route.routes) {
      out.addAll(_goRoutePaths(child, prefix));
    }
  }
  return out;
}

/// The one `ShellRoute` that composes the footer, found by the navigator key it
/// owns — an identity, not a position. Guessing "the first ShellRoute" would
/// keep passing after someone nested another shell above it.
ShellRoute? _findSupportShell(List<RouteBase> routes) {
  for (final r in routes) {
    if (r is ShellRoute && r.navigatorKey == supportShellNavigatorKey) return r;
    final found = _findSupportShell(r.routes);
    if (found != null) return found;
  }
  return null;
}

/// A notifier that never touches Firestore. [SupportNotifier.start] is the only
/// thing that would, and it is lazy precisely so this is possible.
class _StubSupport extends SupportNotifier {
  _StubSupport(this._unread);
  final int _unread;

  @override
  void start() {}

  @override
  int get unreadForUser => _unread;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The table the app runs, not a copy of it. `createRouter` cannot be called
  // here — `AuthNotifier` reaches `FirebaseAuth.instance` in its constructor —
  // which is why the routes are a function of their own.
  final tableRoutes = appRoutes();

  group('INV-22 — the route table', () {
    test('exactly one shell composes the footer', () {
      expect(_findSupportShell(tableRoutes), isNotNull,
          reason: 'no ShellRoute carries supportShellNavigatorKey — the '
              'footer has no single composition point');
    });

    test('every authenticated route sits under it', () {
      final shell = _findSupportShell(tableRoutes)!;
      final inside = _goRoutePaths(shell, '').toSet();
      final all = tableRoutes
          .expand((r) => _goRoutePaths(r, ''))
          .toSet();
      final outside = all.difference(inside);

      expect(outside, _exempt,
          reason: 'These routes render with no way to reach a human. INV-22: '
              'a client that adds a screen must get the footer without '
              'editing that screen. Nest it under the SupportShell route '
              'rather than adding the footer to the screen.');
    });

    test('the reader is inside — it is the one outside the inner shell', () {
      // Named on its own because it is the route this client would have got
      // wrong: it sits outside AppLayout deliberately, so a footer composed
      // there would have left exactly one screen without an exit.
      final inside = _goRoutePaths(_findSupportShell(tableRoutes)!, '').toSet();
      expect(inside, contains('/reader/:docId'));
      expect(inside, contains(supportRoute));
    });
  });

  group('INV-22 — the footer renders', () {
    Future<void> pumpShell(
      WidgetTester tester, {
      int unread = 0,
      Brightness brightness = Brightness.light,
    }) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<SupportNotifier>.value(
          value: _StubSupport(unread),
          child: MaterialApp(
            theme: brightness == Brightness.dark
                ? AppTheme.dark
                : AppTheme.light,
            home: const SupportShell(
              route: '/reader/doc-1',
              child: Center(child: Text('a screen')),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the normative copy, in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await pumpShell(tester, brightness: brightness);
        expect(tester.takeException(), isNull, reason: 'threw in $brightness');
        // Copy is normative (screens/support.md §The footer). Both halves, in
        // this order, and the leading text is NOT part of the control.
        expect(find.textContaining('Bugs? Feature Requests?', findRichText: true),
            findsOneWidget);
        expect(find.text('Chat with support…'), findsOneWidget);
      }
    });

    testWidgets('the control is underlined', (tester) async {
      // The underline is the specification, not a suggestion: `--link` is
      // near-black ink in light mode, so a control distinguished only by colour
      // is invisible AS a control.
      await pumpShell(tester);
      final control = tester.widget<Text>(find.text('Chat with support…'));
      expect(control.style?.decoration, TextDecoration.underline);
      expect(control.style?.decorationColor, isNotNull);
    });

    testWidgets('the unread count shows only when there is one',
        (tester) async {
      await pumpShell(tester, unread: 0);
      expect(find.text('0'), findsNothing);
      await pumpShell(tester, unread: 3);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('it sits BELOW the routed view, never inside it',
        (tester) async {
      // Furniture, not content (§13): it does not scroll with the screen's body
      // and does not sit inside the page frame.
      await pumpShell(tester);
      final screen = tester.getRect(find.text('a screen'));
      final footer = tester.getRect(find.byType(KitSupportFooter));
      expect(footer.top, greaterThan(screen.bottom - screen.height));
      expect(footer.bottom, closeTo(600, 600),
          reason: 'the footer is laid out, not off-screen');
      expect(footer.top, greaterThan(screen.top));
    });
  });

  test('no screen renders its own copy of the footer', () {
    // The other half of the rule: shell-composed means NOT screen-composed. A
    // screen that renders its own would look correct and would make the
    // invariant meaningless the day the shell's copy moved.
    final offenders = <String>[];
    for (final entity in Directory('lib/pages').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final src = entity.readAsStringSync();
      if (src.contains('KitSupportFooter') ||
          src.contains('Chat with support')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'the footer belongs to the shell (lib/widgets/support_shell.dart)');
  });
}
