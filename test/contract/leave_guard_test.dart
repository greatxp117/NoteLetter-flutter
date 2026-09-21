import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:flutter_app/models/chunk.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/manuscript_panel.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/shared/leave_guard.dart';
import 'package:flutter_app/theme/app_theme.dart';

/// **C10 — leaving the reader with unsaved edits.**
///
/// The manuscript editor holds every edit in local state until Save &
/// re-index. Nothing asked before throwing that away, and nothing could have
/// gone red: the app did exactly what it was told, by every exit it has.
///
/// The gate is in three parts because one mount cannot answer all of it.
///
///  1. **Structural** — the REAL route table carries `onExit` on
///     `/reader/:docId`. A hand-written router in this file would reproduce
///     inside the test the exact thing the test exists to prevent: the wire
///     nobody connected. This is `support_footer_test`'s argument, and it is
///     the same route table.
///  2. **Behavioural** — a real `GoRouter` over a stand-in screen, driven by
///     the three exits the reader actually has: a `go()` that replaces the
///     stack, a `pop()` (what the back control does), and the platform's back
///     button through `routerDelegate.popRoute()`. Every one of them must ask,
///     must stay put on a refusal, and must leave on a confirmation. A stand-in
///     screen is used because `ReaderPage` constructs notifiers that reach
///     `FirebaseFirestore.instance` and there is no Firebase app in a plain
///     widget test (the same split `support_footer_test` records).
///  3. **The registration** — the real `ManuscriptPanel`, mounted, typed into,
///     answering the guard's question for itself. That is the half that would
///     otherwise be a claim: a route with an `onExit` nobody registers against
///     is a guard that says yes to everything.
///
/// `LeaveGuard` is a static, so every test here clears it — a registration
/// that outlives its test makes the NEXT file red, which is the direction
/// `test_isolation_test` exists for.

Document _doc() => Document.fromJson('doc-1', {
      'user_id': 'u1',
      'title': 'A document',
      'type': 'document',
      'status': 'complete',
    });

List<Chunk> _chunks() => [
      Chunk.fromJson({
        'chunk_id': 'c1',
        'document_id': 'doc-1',
        'chunk_index': 0,
        'text': 'The first passage.',
        'html': '<p>The first passage.</p>',
      }),
      Chunk.fromJson({
        'chunk_id': 'c2',
        'document_id': 'doc-1',
        'chunk_index': 1,
        'text': 'The second passage.',
        'html': '<p>The second passage.</p>',
      }),
    ];

/// Every `GoRoute` in the tree, as (full path, route).
List<(String, GoRoute)> _routes(RouteBase route, String prefix) {
  final out = <(String, GoRoute)>[];
  if (route is GoRoute) {
    final path =
        route.path.startsWith('/') ? route.path : '$prefix/${route.path}';
    out.add((path, route));
    for (final child in route.routes) {
      out.addAll(_routes(child, path));
    }
  } else {
    for (final child in route.routes) {
      out.addAll(_routes(child, prefix));
    }
  }
  return out;
}

/// A router shaped like the app's: a guarded screen carrying the same `onExit`
/// the reader's route carries, and somewhere to leave to.
GoRouter _router() => GoRouter(
      initialLocation: '/guarded',
      routes: [
        GoRoute(path: '/elsewhere', builder: (_, __) => const Text('elsewhere')),
        GoRoute(
          path: '/guarded',
          onExit: (context, state) => LeaveGuard.mayLeave(context),
          builder: (_, __) => const Text('guarded'),
          routes: [
            GoRoute(path: 'deeper', builder: (_, __) => const Text('deeper')),
          ],
        ),
      ],
    );

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(MaterialApp.router(
    theme: AppTheme.light,
    routerConfig: router,
  ));
  await tester.pumpAndSettle();
}

/// Registers a guard that always asks, and reports what the caller answered.
void _registerAsking(List<bool> answers) {
  LeaveGuard.register((context) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Discard your edits?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay and keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard and leave'),
          ),
        ],
      ),
    );
    answers.add(ok == true);
    return ok == true;
  });
}

void main() {
  // The manuscript's dwell counters ride `VisibilityDetector`, whose default
  // 500ms coalescing timer outlives a disposed tree and fails the test on an
  // invariant that has nothing to do with the subject.
  setUpAll(() =>
      VisibilityDetectorController.instance.updateInterval = Duration.zero);

  tearDown(LeaveGuard.clear);

  test('the reader route carries the guard — the REAL table, not a copy', () {
    final all = <(String, GoRoute)>[];
    for (final r in appRoutes()) {
      all.addAll(_routes(r, ''));
    }
    expect(all.length, greaterThan(10),
        reason: 'read ${all.length} route(s) — an unread table is not a '
            'guarded one (4.34.7)');

    final reader =
        all.where((e) => e.$1 == '/reader/:docId').map((e) => e.$2).toList();
    expect(reader, hasLength(1), reason: 'the reader route moved');
    expect(reader.single.onExit, isNotNull,
        reason: 'without onExit every exit from the reader is silent again');
  });

  test('with nothing registered the guard says yes, so no other route pays',
      () async {
    expect(LeaveGuard.isGuarded, isFalse);
    expect(await LeaveGuard.mayLeave(_FakeContext()), isTrue);
  });

  test('a disposer that is no longer the registered guard clears nothing',
      () async {
    final first = LeaveGuard.register((_) async => false);
    LeaveGuard.register((_) async => true); // a second screen takes over
    first(); // the first screen tears down LATE
    expect(LeaveGuard.isGuarded, isTrue,
        reason: 'a late teardown must not unguard the screen that replaced it');
    expect(await LeaveGuard.mayLeave(_FakeContext()), isTrue);
  });

  testWidgets('a go() that replaces the stack asks, and a refusal stays',
      (tester) async {
    final router = _router();
    await _pumpRouter(tester, router);
    final answers = <bool>[];
    _registerAsking(answers);

    router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(find.text('Discard your edits?'), findsOneWidget);
    expect(find.text('guarded'), findsOneWidget);

    await tester.tap(find.text('Stay and keep editing'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
    expect(find.text('guarded'), findsOneWidget,
        reason: 'a refusal that navigates anyway is not a refusal');
    expect(find.text('elsewhere'), findsNothing);

    router.go('/elsewhere');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard and leave'));
    await tester.pumpAndSettle();
    expect(answers, [false, true]);
    expect(find.text('elsewhere'), findsOneWidget,
        reason: 'a confirmation that does not leave is a screen with no exit');
  });

  testWidgets('a pop() — what the back control does — asks the same question',
      (tester) async {
    final router = _router();
    await _pumpRouter(tester, router);
    router.push('/guarded/deeper');
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('guarded'), findsOneWidget);

    final answers = <bool>[];
    _registerAsking(answers);
    router.go('/elsewhere');
    await tester.pumpAndSettle();
    expect(find.text('Discard your edits?'), findsOneWidget);
    await tester.tap(find.text('Stay and keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('guarded'), findsOneWidget);
  });

  testWidgets('the platform back button asks too — the exit nobody writes code '
      'for', (tester) async {
    final router = _router();
    await _pumpRouter(tester, router);
    final answers = <bool>[];
    _registerAsking(answers);

    // What Android's back and the iOS swipe both arrive as. `popRoute` is the
    // Router API's own entry point, so this is the real path and not a stand-in
    // for it.
    final handled = router.routerDelegate.popRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard your edits?'), findsOneWidget,
        reason: 'the back button left without asking');

    await tester.tap(find.text('Stay and keep editing'));
    await tester.pumpAndSettle();
    expect(answers, [false]);
    expect(find.text('guarded'), findsOneWidget);
    await handled;
  });

  testWidgets('the manuscript panel registers, answers, and unregisters',
      (tester) async {
    // The panel flushes its dwell counters on unmount, which reaches Firebase.
    // The harness that swaps the singleton puts it back — an assignment with no
    // reset is what `test_isolation_test` refuses.
    FirestoreService.instance = _QuietFirestore();
    addTearDown(FirestoreService.resetInstance);
    expect(LeaveGuard.isGuarded, isFalse);

    Future<void> pump({bool mounted = true}) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SingleChildScrollView(
            child: mounted
                ? ManuscriptPanel(
                    docId: 'doc-1',
                    doc: _doc(),
                    chunks: _chunks(),
                    onSaved: () async {},
                  )
                : const Text('gone'),
          ),
        ),
      ));
      await tester.pump();
    }

    await pump();
    expect(LeaveGuard.isGuarded, isTrue, reason: 'nothing registered the guard');

    // Clean: the reader is asked nothing, and no frame of a dialog is drawn.
    final ctx = tester.element(find.byType(ManuscriptPanel));
    expect(await LeaveGuard.mayLeave(ctx), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Discard your edits?'), findsNothing);

    // Dirty: switch editing on and type one character into a passage.
    await tester.tap(find.text('Edit text'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'The first passage!!');
    await tester.pumpAndSettle();
    expect(find.text('Text edited'), findsOneWidget,
        reason: 'typing did not mark the passage dirty, so nothing to guard');

    final asked = LeaveGuard.mayLeave(ctx);
    await tester.pumpAndSettle();
    expect(find.text('Discard your edits?'), findsOneWidget);
    expect(find.text('Stay and keep editing'), findsOneWidget);
    expect(find.text('Discard and leave'), findsOneWidget);
    await tester.tap(find.text('Stay and keep editing'));
    await tester.pumpAndSettle();
    expect(await asked, isFalse);

    // Gone: the panel must take its guard with it, or the next screen is
    // guarded by a screen that no longer exists.
    await pump(mounted: false);
    await tester.pumpAndSettle();
    expect(LeaveGuard.isGuarded, isFalse);
  });
}

/// Reads nothing and writes nothing: this file's subject is the guard, and the
/// dwell counters are `read_counters_test`'s.
class _QuietFirestore extends FirestoreService {
  _QuietFirestore() : super.stub();

  @override
  Future<void> logChunksRead(String documentId, List<String> chunkIds) async {}
}

/// `mayLeave` must not touch the context when nothing is registered — that is
/// what makes it safe on a route whose screen is usually clean.
class _FakeContext implements BuildContext {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('mayLeave touched the context with no guard registered');
}
