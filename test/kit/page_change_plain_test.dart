import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// A page change is plain (component-kit §40): the next frame is the new page.
///
/// The default slid every route sideways for 430ms, and the shell's pages have
/// no background of their own, so the new page's text crossed the old page's.
/// The fake here is the app's own theme over the app's router package, so this
/// fails the day a theme stops carrying [AppTheme]'s transitions.
void main() {
  for (final theme in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    test(
      '${theme.$1} theme: no platform has a page transition with a length',
      () {
        final builders = theme.$2.pageTransitionsTheme.builders;
        for (final p in TargetPlatform.values) {
          expect(builders[p], isNotNull, reason: '$p falls back to a default');
          expect(builders[p]!.transitionDuration, Duration.zero, reason: '$p');
          expect(
            builders[p]!.reverseTransitionDuration,
            Duration.zero,
            reason: '$p',
          );
        }
      },
    );
  }

  Widget page(String text, {VoidCallback? onTap}) => Center(
    child: GestureDetector(onTap: onTap, child: Text(text)),
  );

  GoRouter shell() => GoRouter(
    initialLocation: '/a',
    routes: [
      ShellRoute(
        builder: (context, state, child) => Scaffold(body: child),
        routes: [
          GoRoute(path: '/a', builder: (c, s) => page('page a')),
          GoRoute(path: '/b', builder: (c, s) => page('page b')),
        ],
      ),
      GoRoute(
        path: '/over',
        builder: (c, s) => Scaffold(body: page('page over')),
      ),
    ],
  );

  Future<GoRouter> boot(WidgetTester tester) async {
    final router = shell();
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.pump();
    return router;
  }

  final phones = TargetPlatformVariant(const {
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  testWidgets('go() is the new page on the next frame, alone', (tester) async {
    final router = await boot(tester);
    final at = tester.getCenter(find.text('page a'));
    router.go('/b');
    await tester.pump();
    await tester.pump();
    expect(find.text('page a'), findsNothing);
    expect(find.text('page b'), findsOneWidget);
    expect(tester.getCenter(find.text('page b')).dx, closeTo(at.dx, 40));
    expect(tester.hasRunningAnimations, isFalse);
  }, variant: phones);

  testWidgets('push() and pop() are plain both ways', (tester) async {
    final router = await boot(tester);
    router.push('/over');
    await tester.pump();
    await tester.pump();
    expect(find.text('page over'), findsOneWidget);
    expect(find.text('page a'), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    router.pop();
    await tester.pump();
    await tester.pump();
    expect(find.text('page over'), findsNothing);
    expect(find.text('page a'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  }, variant: phones);

  testWidgets('iOS: the edge swipe still takes a pushed page back', (
    tester,
  ) async {
    final router = await boot(tester);
    router.push('/over');
    await tester.pump();
    await tester.pump();

    final gesture = await tester.startGesture(
      const Offset(4, 300),
      kind: PointerDeviceKind.touch,
    );
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump();
    // The finger holds the page: it is moved, with the page beneath it showing.
    expect(find.text('page a'), findsOneWidget);
    expect(find.text('page over'), findsOneWidget);
    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('page over'), findsNothing);
    expect(find.text('page a'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
