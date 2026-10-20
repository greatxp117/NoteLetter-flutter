import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/ask_thread.dart';
import 'package:flutter_app/pages/chat_page.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/state/support_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/support_shell.dart';

import 'sources_harness.dart' show StubTags;

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
/// - `/landing` and `/signin` — pre-auth (F-44a). Sending a message requires
///   a signed-in caller (INV-01), so there is nothing for the footer to link to.
/// - A first-run onboarding wizard would be the second exemption; this client
///   has none, so the set is one entry long. When it gets one it goes *outside*
///   the shell route, never behind a condition inside the footer.
/// - `/share` — Android's share sheet (F-123), over the app that shared and
///   open signed out ("Sign in required"), as iOS's share extension is; it
///   has no footer on iOS either, and nothing for one to link to signed out.
const _exempt = {'/landing', '/signin', '/share'};

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

/// Ask with nothing asked yet: no threads, no messages, no Firestore.
class _NoThreads extends FirestoreService {
  _NoThreads() : super.stub();
  @override
  Stream<List<AskThread>> subscribeAskThreads({int limit = 100}) =>
      Stream.value(const []);
  @override
  Stream<List<AskMessage>> subscribeAskMessages(String threadId) =>
      Stream.value(const []);
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
              child: KitPage(child: Text('a screen')),
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
  });

  // ── Placement (5.19.0, ADR-173; component-kit §1.4, §13) ──────────────────
  // The footer is the LAST element of the screen's PRIMARY scroll container,
  // reached at the end of the scroll and scrolled away with it. Each default
  // ADR-173 names is a test here, on the real SupportShell and the kit's real
  // scroll containers; the device run proves the same on real screens with a
  // real gesture. "Only a real gesture proves scrollability" — so every move
  // below is a `drag`, never a controller jump.
  group('INV-22 — the footer ends the primary scroll (ADR-173)', () {
    const pane = Size(1200, 900);

    Future<void> pumpIn(WidgetTester tester, Widget screen,
        {Size size = pane}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider<SupportNotifier>.value(
          value: _StubSupport(0),
          child: MaterialApp(
            theme: AppTheme.light,
            home: SupportShell(route: '/activity', child: screen),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Widget rows(int n, {String prefix = 'row', Widget? last}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < n; i++)
              SizedBox(height: 40, child: Text('$prefix $i')),
            ?last,
          ],
        );

    Future<void> dragToEnd(WidgetTester tester, Finder scrollable) async {
      for (var i = 0; i < 30; i++) {
        await tester.drag(scrollable, const Offset(0, -600),
            warnIfMissed: false);
        await tester.pumpAndSettle();
      }
    }

    Rect footer(WidgetTester tester) =>
        tester.getRect(find.byType(KitSupportFooter));

    testWidgets('the shell no longer draws it: no screen, no footer',
        (tester) async {
      // A screen with no primary scroll gets none — which is why every routed
      // screen scrolls through the kit (the source gates below).
      await pumpIn(tester, const Center(child: Text('bare')));
      expect(find.byType(KitSupportFooter), findsNothing);
    });

    testWidgets('content shorter than the pane: at the pane\'s bottom edge',
        (tester) async {
      await pumpIn(tester, const KitPage(child: Text('short')));
      expect(find.byType(KitSupportFooter), findsOneWidget);
      expect(footer(tester).bottom, pane.height,
          reason: 'never mid-screen under the last line');
      expect(footer(tester).width, pane.width,
          reason: 'it spans its scroll container');
      final pos = tester.state<ScrollableState>(find.byType(Scrollable)).position;
      expect(pos.maxScrollExtent, 0,
          reason: 'filling the pane does not make a short screen scroll');
    });

    testWidgets('a long screen: the last element, reached at the END',
        (tester) async {
      await pumpIn(tester, KitPage(child: rows(60)));
      expect(find.byType(KitSupportFooter), findsOneWidget);
      expect(footer(tester).top, greaterThan(pane.height),
          reason: 'out of the way: below the fold until the end');
      await dragToEnd(tester, find.byType(Scrollable).first);
      expect(footer(tester).bottom, pane.height,
          reason: 'present: at the end of the scroll');
      expect(footer(tester).top,
          greaterThanOrEqualTo(tester.getRect(find.text('row 59')).bottom),
          reason: 'after the last line of content');
    });

    testWidgets('a load-more list: after the last item AND its control',
        (tester) async {
      await pumpIn(
        tester,
        KitPage(
          child: rows(40,
              last: KitButton('Load more',
                  variant: KitButtonVariant.ghost, onPressed: () {})),
        ),
      );
      await dragToEnd(tester, find.byType(Scrollable).first);
      expect(footer(tester).top,
          greaterThanOrEqualTo(tester.getRect(find.text('Load more')).bottom));
      expect(footer(tester).bottom, pane.height);
    });

    testWidgets('more than one scroller: the primary column ends with it, '
        'the secondary never carries it', (tester) async {
      await pumpIn(
        tester,
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 440, child: KitPage(child: rows(3, prefix: 'form'))),
            Expanded(
              child: KitPage.secondary(
                reason: 'the letter preview beside the settings column',
                child: rows(60, prefix: 'preview'),
              ),
            ),
          ],
        ),
      );
      expect(find.byType(KitSupportFooter), findsOneWidget,
          reason: 'exactly once, though the screen has two scrollers');
      expect(footer(tester).left, 0);
      expect(footer(tester).right, 440,
          reason: 'in the primary column, not across the screen');
      expect(footer(tester).bottom, pane.height);
      await dragToEnd(tester, find.byType(Scrollable).last);
      expect(footer(tester).right, 440,
          reason: 'the secondary scroller ends with no footer');
    });

    testWidgets('a docked composer: the footer ends the content above the '
        'dock\'s reserve, and the dock stays docked', (tester) async {
      const dock = 120.0;
      await pumpIn(
        tester,
        Stack(
          children: [
            KitPage(
                anchorBottom: true,
                dockReserve: dock + KitComposerDock.scrimRise,
                child: rows(2, prefix: 'turn')),
            const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(height: dock, child: Text('dock')),
            ),
          ],
        ),
      );
      expect(footer(tester).bottom,
          pane.height - dock - KitComposerDock.scrimRise,
          reason: 'above the dock and clear of its scrim');
      expect(footer(tester).top,
          greaterThanOrEqualTo(tester.getRect(find.text('turn 1')).bottom),
          reason: 'a short transcript sits against the footer');
      expect(tester.getRect(find.text('dock')).bottom, pane.height,
          reason: 'the dock stays docked at the pane\'s bottom');
    });

    testWidgets('Ask, the real screen: the composer stays docked and the '
        'footer ends the scroll above it', (tester) async {
      for (final size in [pane, const Size(402, 874)]) {
        FirestoreService.instance = _NoThreads();
        addTearDown(FirestoreService.resetInstance);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<SupportNotifier>.value(
                value: _StubSupport(0)),
            ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
            ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags()),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SupportShell(
                route: '/ask', child: Scaffold(body: ChatPage())),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(find.byType(KitSupportFooter), findsOneWidget, reason: '$size');
        await dragToEnd(
            tester,
            find
                .ancestor(
                    of: find.byType(KitSupportFooter),
                    matching: find.byType(Scrollable))
                .first);
        final dock = tester.getRect(find.byType(KitComposerDock));
        expect(dock.bottom, size.height,
            reason: 'the dock stays docked at the bottom ($size)');
        expect(footer(tester).bottom,
            closeTo(dock.top - KitComposerDock.scrimRise, 0.5),
            reason: 'the footer rests above the dock, clear of its scrim '
                '($size)');
        expect(
            footer(tester).top,
            greaterThanOrEqualTo(
                tester.getRect(find.byType(KitEmptyState)).bottom),
            reason: 'after the screen\'s content ($size)');
      }
    });

    testWidgets('the reader: at the end of the document, as its last sliver',
        (tester) async {
      Widget reader(int n) => CustomScrollView(slivers: [
            SliverToBoxAdapter(child: rows(n, prefix: 'passage')),
            const KitShellFooterSliver(),
          ]);
      await pumpIn(tester, reader(3));
      expect(footer(tester).bottom, pane.height,
          reason: 'a short document keeps it at the pane\'s bottom edge');
      await pumpIn(tester, reader(80));
      expect(find.byType(KitSupportFooter).hitTestable(), findsNothing,
          reason: 'below the fold (a sliver that far out is not even built)');
      await dragToEnd(tester, find.byType(Scrollable).first);
      expect(footer(tester).bottom, pane.height);
      expect(footer(tester).top,
          greaterThanOrEqualTo(tester.getRect(find.text('passage 79')).bottom));
    });

    testWidgets('a screen still loading keeps its way out', (tester) async {
      await pumpIn(tester, const KitLoadingPage());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(footer(tester).bottom, pane.height);
    });

    testWidgets('on a phone it is inside the scroll, and reaches the bottom '
        'edge only at the end', (tester) async {
      const phone = Size(402, 874);
      await pumpIn(tester, KitPage(child: rows(60)), size: phone);
      expect(footer(tester).top, greaterThan(phone.height),
          reason: 'not a strip pinned over every phone screen');
      await dragToEnd(tester, find.byType(Scrollable).first);
      expect(footer(tester).bottom, phone.height);
    });
  });

  group('INV-22 — every screen scrolls through the kit (source)', () {
    // Mounting every routed screen needs Firebase, which a widget test does not
    // have (see the top of this file). So the gate reads the source: each
    // routed screen's file has a PRIMARY scroll container, and every other
    // scroller a page builds is declared secondary, with its reason — web's
    // `data-scroll-secondary`. The device run closes it on real screens.
    final primary = RegExp(
        r'KitPage\(|KitScrollView\(|KitLoadingPage\(|KitShellFooterSliver\(');

    test('every routed screen\'s file has a primary scroll container', () {
      final router = File('lib/router.dart').readAsStringSync();
      final classes = RegExp(r'=>\s*(?:const\s+)?([A-Z]\w*Page)\(')
          .allMatches(router)
          .map((m) => m.group(1)!)
          .toSet()
        // Outside the shell by decision (INV-22's exemptions above, and the
        // router's error page, which renders outside every route).
        ..removeAll({'NotFoundPage', 'LandingPage', 'SignInPage'});
      expect(classes, isNotEmpty);
      final files = Directory('lib/pages')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final missing = <String>[];
      for (final c in classes) {
        final file = files.firstWhere(
            (f) => f.readAsStringSync().contains(RegExp('class $c\\b')),
            orElse: () => File(''));
        if (file.path.isEmpty) {
          missing.add('$c (no file)');
        } else if (!primary.hasMatch(file.readAsStringSync())) {
          missing.add('$c (${file.path})');
        }
      }
      expect(missing, isEmpty,
          reason: 'a routed screen with no primary scroll has no footer '
              '(INV-22, ADR-173): scroll through KitPage / KitScrollView');
    });

    test('every other scroller a page builds is declared secondary', () {
      final raw = RegExp(r'(?<![A-Za-z0-9_.])(SingleChildScrollView|ListView|'
          r'CustomScrollView|GridView|PageView)(\.\w+)?\(');
      final mark = RegExp(r'scroll-secondary:(.*)$');
      final offenders = <String>[];
      for (final f in Directory('lib/pages').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        final src = lines.join('\n');
        for (var i = 0; i < lines.length; i++) {
          final m = raw.firstMatch(lines[i]);
          if (m == null || lines[i].trimLeft().startsWith('//')) continue;
          // The reader's sliver scroller ends with the footer itself.
          if (m.group(1) == 'CustomScrollView' &&
              src.contains('KitShellFooterSliver()')) {
            continue;
          }
          String? why;
          for (final l in [lines[i], if (i > 0) lines[i - 1]]) {
            final mm = mark.firstMatch(l);
            if (mm != null) why = mm.group(1);
          }
          if (why == null || why.replaceAll(RegExp(r'[^A-Za-z]'), '').length < 8) {
            offenders.add('${f.path}:${i + 1}');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'a raw scroller in a page is either the screen\'s primary '
              'one (then it must be KitPage / KitScrollView, which end with '
              'the footer) or a secondary one marked '
              '`// scroll-secondary: <why>`');
    });

    test('the reader\'s scroll ends with the footer sliver', () {
      final src = File('lib/pages/reader_page.dart').readAsStringSync();
      final last = src.lastIndexOf('KitShellFooterSliver()');
      expect(last, greaterThan(0));
      expect(src.indexOf('SliverToBoxAdapter', last), -1,
          reason: 'nothing after the footer: it ends the document');
    });

    test('only the shell hands the footer down', () {
      final offenders = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path.endsWith('support_shell.dart') ||
            f.path.endsWith('kit_frame.dart')) {
          continue;
        }
        if (f.readAsStringSync().contains('KitShellFooter(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
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
