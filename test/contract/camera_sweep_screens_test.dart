// F-125 S3, F-146: the camera roll's screens and what starts it in the
// foreground — lib/state/camera_sweep_host.dart and, since 5.43.0 (ADR-198),
// direction D's row, flow and panel in lib/pages/sources/camera_roll.dart over
// lib/widgets/kit/kit_d_camera.dart — against the fakes the service's own
// tests use (sweep_fakes.dart). Until 5.43.0 the screens were Settings →
// Camera roll and Sources' tray (the retired Swift app's
// CameraSweepSettingsView and SweepReviewSection).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/pages/sources/camera_roll.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/firestore_service.dart' show CaptureMatch;
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/services/sweep_words.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_app/theme/app_theme.dart';

import 'sweep_fakes.dart';

/// Recent enough for the ledger's default 90-day window.
double _recent(int minutesAgo) =>
    DateTime.now().subtract(Duration(minutes: minutesAgo)).millisecondsSinceEpoch / 1000;

class _Session extends ChangeNotifier {
  bool signedIn;
  _Session(this.signedIn);
  void set(bool v) {
    signedIn = v;
    notifyListeners();
  }
}

typedef _Rig = ({
  CameraSweepHost host,
  FakeBridge bridge,
  FakeEndpoints endpoints,
  MemoryLedgerStore store,
  _Session session,
  FakeBackground background,
});

Future<_Rig> _rig(
  List<SweepAsset> assets, {
  bool enabled = true,
  bool signedIn = true,
  SweepAccess access = SweepAccess.granted,
  Map<String, SweepVerdict> verdicts = const {},
  Map<String, Object?> stored = const {},
}) async {
  final store = MemoryLedgerStore({
    if (enabled) SweepLedger.kEnabled: true,
    ...stored,
  });
  final bridge = FakeBridge(assets, verdicts: verdicts)..accessNow = access;
  final endpoints = FakeEndpoints();
  final session = _Session(signedIn);
  final background = FakeBackground();
  final host = CameraSweepHost(
    session: session,
    isSignedIn: () => session.signedIn,
    bridge: bridge,
    store: store,
    endpoints: endpoints,
    uploader: endpoints.uploader,
    background: background,
    debounce: const Duration(milliseconds: 20),
    observeLifecycle: false,
  );
  await host.ready;
  return (
    host: host,
    bridge: bridge,
    endpoints: endpoints,
    store: store,
    session: session,
    background: background,
  );
}

/// Lets every queued microtask and short timer run.
Future<void> _settle([int ms = 60]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 100 && !done(); i++) {
    await _settle(10);
  }
}

void main() {
  // ── What starts a pass ─────────────────────────────────────────────────────

  group('foreground start', () {
    test('at launch, signed in and on: a pass runs and the library is watched',
        () async {
      final r = await _rig([asset('p1', seconds: _recent(5))]);
      await _until(() => r.host.service!.candidates.isNotEmpty);
      expect(r.host.service!.candidates.single.localIdentifier, 'p1');
      expect(r.bridge.watched, isTrue, reason: 'the change observer is listened to');
      expect(r.bridge.accessRequests, 0, reason: 'NEVER prompts at launch (spec §1)');
    });

    test('off: nothing reads the library, nothing prompts', () async {
      final r = await _rig([asset('p1', seconds: _recent(5))], enabled: false);
      await _settle();
      expect(r.bridge.examinedIds, isEmpty);
      expect(r.bridge.accessReads, 0);
      expect(r.bridge.accessRequests, 0);
      expect(r.bridge.watched, isFalse);
    });

    test('on, but access was taken away: no pass, no watch, no prompt', () async {
      final r = await _rig([asset('p1', seconds: _recent(5))],
          access: SweepAccess.limited);
      await _settle();
      expect(r.bridge.examinedIds, isEmpty);
      expect(r.bridge.watched, isFalse);
      expect(r.bridge.accessRequests, 0);
      expect(r.host.access, SweepAccess.limited);
    });

    test('signed out at launch: waits for the sign-in, then runs', () async {
      final r = await _rig([asset('p1', seconds: _recent(5))], signedIn: false);
      await _settle();
      expect(r.bridge.examinedIds, isEmpty, reason: 'no account to file into yet');
      r.session.set(true);
      await _until(() => r.host.service!.candidates.isNotEmpty);
      expect(r.bridge.examinedIds, ['p1']);
    });

    test('a library change runs another pass, settled into one', () async {
      final assets = [asset('p1', seconds: _recent(5))];
      final r = await _rig(assets);
      await _until(() => !r.host.service!.isSweeping && r.host.service!.candidates.isNotEmpty);
      // A photo is taken with the app open: three change events in a row.
      assets.insert(0, asset('p2', seconds: _recent(1)));
      r.bridge.examinedIds.clear();
      r.bridge.changes
        ..add(null)
        ..add(null)
        ..add(null);
      await _until(() => r.host.service!.candidates.length == 2);
      await _settle();
      expect(r.bridge.examinedIds, ['p2'],
          reason: 'one pass for the burst; the waiting card is not examined again');
    });

    test('a change during a pass is not dropped: one more pass after it', () async {
      final assets = [asset('p1', seconds: _recent(5))];
      final r = await _rig(assets, enabled: false);
      final gate = Completer<void>();
      r.bridge.examineGate = gate.future;
      await r.host.enable();
      await _until(() => r.host.service!.isSweeping);
      assets.insert(0, asset('p2', seconds: _recent(1)));
      r.host.kick(); // the change, mid-pass
      gate.complete();
      await _until(() => r.host.service!.candidates.length == 2);
      expect(r.host.service!.candidates.map((a) => a.localIdentifier).toSet(),
          {'p1', 'p2'});
    });

    test('sign-out stops watching and forgets the tray', () async {
      final r = await _rig([asset('p1', seconds: _recent(5))]);
      await _until(() => r.host.service!.candidates.isNotEmpty);
      r.session.set(false);
      await _settle();
      expect(r.host.service!.candidates, isEmpty);
      expect(r.bridge.watched, isFalse);
    });
  });

  // ── The switch: permission on an affirmative action ────────────────────────

  group('enable', () {
    test('full access: the prompt, then on, then a pass', () async {
      final r = await _rig([asset('p1', seconds: _recent(5))], enabled: false)
        ..bridge.accessNow = SweepAccess.denied
        ..bridge.promptAnswers = SweepAccess.granted;
      await r.host.enable();
      expect(r.bridge.accessRequests, 1);
      expect(r.host.ledger!.enabled, isTrue);
      expect(r.store.values[SweepLedger.kEnabled], true, reason: 'written');
      await _until(() => r.host.service!.candidates.isNotEmpty);
      expect(r.bridge.watched, isTrue);
      expect(r.host.refused, isNull);
    });

    for (final (got, refusal) in [
      (SweepAccess.limited, SweepAccessRefused.limited),
      (SweepAccess.denied, SweepAccessRefused.denied),
    ]) {
      test('${got.name}: stays off, says why, sends and reads nothing', () async {
        final r = await _rig([asset('p1', seconds: _recent(5))], enabled: false)
          ..bridge.accessNow = SweepAccess.denied
          ..bridge.promptAnswers = got;
        await r.host.enable();
        expect(r.host.ledger!.enabled, isFalse);
        expect(r.store.values[SweepLedger.kEnabled], isNull, reason: 'nothing written');
        expect(r.host.refused, same(refusal));
        expect(r.bridge.examinedIds, isEmpty);
        expect(r.bridge.watched, isFalse);
      });
    }

    test('a ledger write that fails leaves the switch off and throws', () async {
      final store = FlakyStore();
      final bridge = FakeBridge([])..accessNow = SweepAccess.granted;
      final host = CameraSweepHost(
        session: _Session(true),
        isSignedIn: () => true,
        bridge: bridge,
        store: store,
        endpoints: FakeEndpoints(),
        uploader: FakeUploader(),
        background: null,
        observeLifecycle: false,
      );
      await host.ready;
      store.failWrites = true;
      await expectLater(host.enable(), throwsA(isA<StateError>()));
      expect(host.ledger!.enabled, isFalse);
      expect(bridge.watched, isFalse);
    });

    test('off: the pass stops and nothing watches', () async {
      final r = await _rig([asset('p1', seconds: _recent(5))]);
      await _until(() => r.bridge.watched);
      await r.host.disable();
      expect(r.host.ledger!.enabled, isFalse);
      expect(r.bridge.watched, isFalse);
    });

    test('photos in range: counted by the library from the start date', () async {
      final r = await _rig([
        asset('a', seconds: _recent(5)),
        asset('b', seconds: _recent(60)),
        asset('old', seconds: DateTime(2001).millisecondsSinceEpoch / 1000),
      ]);
      await r.host.refreshInRange();
      expect(r.host.inRange, 2);
      await r.host.setBackfillStart(DateTime(2000));
      expect(r.host.inRange, 3);
    });

    test('start over forgets the verdicts and keeps the setup', () async {
      final r = await _rig([asset('n1', seconds: _recent(5))],
          verdicts: {'n1': SweepVerdict.noText});
      await _until(() => r.host.ledger!.verdicts.isNotEmpty);
      expect(await r.host.startOver(), isNull);
      expect(r.host.ledger!.verdicts, isEmpty);
      expect(r.host.ledger!.enabled, isTrue);
    });
  });

  // ── Already in NoteLetter ──────────────────────────────────────────────────

  group('a candidate already filed', () {
    test('is asked about once, as it enters the tray, by its asset key', () async {
      final (svc, _, _, ep, _) = await rig([asset('done'), asset('stuck'), asset('new')]);
      ep.filed[asset('done').assetKey] =
          const CaptureMatch(docId: 'cam-1', status: 'complete');
      ep.filed[asset('stuck').assetKey] =
          const CaptureMatch(docId: 'cam-2', status: 'pending_upload');
      await svc.sweep();
      expect(ep.finds, [for (final id in ['done', 'stuck', 'new']) asset(id).assetKey]);
      expect(svc.alreadyIn('done'), isTrue, reason: 'its bytes landed');
      expect(svc.alreadyIn('stuck'), isFalse,
          reason: 'pending_upload: the bytes never landed, Add uploads them');
      expect(svc.alreadyIn('new'), isFalse);
      await svc.sweep();
      expect(ep.finds, hasLength(3), reason: 'not asked again for a waiting card');
      expect(ep.sessions, isEmpty, reason: 'asking is a read, never a session');
    });

    test('a read that fails says nothing — the card is still offered', () async {
      final (svc, _, _, ep, _) = await rig([asset('p1')]);
      ep.findThrows = StateError('permission-denied');
      await svc.sweep();
      expect(svc.candidates, hasLength(1));
      expect(svc.alreadyIn('p1'), isFalse);
    });

    test('Add on it: one session, NO upload, and it leaves the tray', () async {
      final (svc, ledger, _, ep, _) = await rig([asset('done')]);
      final key = asset('done').assetKey;
      ep.filed[key] = const CaptureMatch(docId: 'cam-1', status: 'complete');
      ep.answers[key] = {
        'docId': 'cam-1',
        'duplicate': true,
        'status': 'complete',
        'uploadUrl': null,
        'gcsPath': 'raw/u/camera/cam-1',
      };
      await svc.sweep();
      await svc.approve(svc.candidates.single);
      expect(ep.sessions, hasLength(1));
      expect(ep.puts, isEmpty, reason: 'the bytes already landed (spec §6)');
      expect(svc.candidates, isEmpty);
      expect(ledger.verdict('done'), LedgerVerdict.ingested);
    });
  });

  // ── The screens (direction D, 5.43.0, ADR-198) ─────────────────────────────

  Future<void> pump(WidgetTester tester, CameraSweepHost host, Widget child,
      {ThemeData? theme, Size size = const Size(402, 874)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider<CameraSweepHost>.value(
      value: host,
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Scaffold(body: child),
      ),
    ));
  }

  /// A few frames, never `pumpAndSettle`: the flow's bar eases.
  Future<void> frames(WidgetTester tester, [int n = 8]) async {
    for (var i = 0; i < n; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    final f = find.text(text);
    await tester.ensureVisible(f.last);
    await tester.tap(f.last);
  }

  /// The row, and a button that opens the flow at [step] — what the Library
  /// does.
  Widget library({VoidCallback? onSettings}) => Builder(
        builder: (context) => ListView(children: [
          CameraRollRow(onSettings: onSettings ?? () {}),
        ]),
      );

  group('the row', () {
    testWidgets('off: the D line and Connect', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))], enabled: false);
      });
      await pump(tester, r.host, library());
      expect(find.text(CameraRollCopy.name), findsOneWidget);
      expect(find.text(CameraRollCopy.rowOff), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('waiting: the tray\'s count and Review; on: what is taken in',
        (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1)), asset('b', seconds: _recent(2))]);
        await _until(() => r.host.service!.candidates.length == 2 &&
            !r.host.service!.isSweeping);
      });
      await pump(tester, r.host, library());
      expect(find.text('2 waiting for your review'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      await tester.runAsync(() async {
        for (final a in List.of(r.host.service!.candidates)) {
          await r.host.service!.dismiss(a);
        }
      });
      await tester.pump();
      expect(find.text('On · 0 taken in'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('a failure stands, in critical text; access lost; unreadable',
        (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))]);
        await _until(() => !r.host.service!.isSweeping &&
            r.host.service!.candidates.isNotEmpty);
        r.host.service!.presentFailure(DedupeUnsupported.message, stopsSweep: true);
      });
      await pump(tester, r.host, library());
      expect(find.text(CameraSweepService.stoppedTitle), findsOneWidget);
      r.host.service!.clearError();
      await tester.runAsync(() async {
        r.bridge.accessNow = SweepAccess.limited;
        await r.host.refreshAccess();
      });
      await tester.pump();
      expect(find.text(CameraRollCopy.rowNoAccess), findsOneWidget);

      final bad = CameraSweepHost(
        session: _Session(true),
        isSignedIn: () => true,
        bridge: FakeBridge([]),
        store: _Unreadable(),
        endpoints: FakeEndpoints(),
        uploader: FakeUploader(),
        background: null,
        observeLifecycle: false,
      );
      await tester.runAsync(() => bad.ready);
      await pump(tester, bad, library());
      expect(find.text(CameraRollCopy.rowUnreadable), findsOneWidget);
      expect(find.text('Connect'), findsNothing, reason: 'no action');
    });
  });

  group('the setup', () {
    testWidgets(
        'four steps: Connect, a refusal, full access, the reach counted, the mode, '
        'then on and Looking back', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([
          asset('new', seconds: _recent(60)),
          asset('older', seconds: _recent(60 * 24 * 40)),
          asset('oldest', seconds: _recent(60 * 24 * 500)),
        ], enabled: false)
          ..bridge.accessNow = SweepAccess.denied
          ..bridge.promptAnswers = SweepAccess.limited;
      });
      await pump(tester, r.host, library());
      await tester.tap(find.text('Connect'));
      await frames(tester);
      // 1 · what it does
      expect(find.text('CAMERA ROLL · 1 OF 4'), findsOneWidget);
      expect(find.text(CameraRollCopy.introTitle), findsOneWidget);
      for (final (t, d) in CameraRollCopy.introRows) {
        expect(find.text(t), findsOneWidget);
        expect(find.text(d), findsOneWidget);
      }
      expect(r.bridge.accessRequests, 0, reason: 'opening the setup asks nothing');
      await tapText(tester, CameraRollCopy.continueLabel);
      await frames(tester);
      // 2 · access: the prompt fires on Allow access, and only there
      expect(find.text('CAMERA ROLL · 2 OF 4'), findsOneWidget);
      expect(find.text(CameraRollCopy.accessStand), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text(CameraRollCopy.allowAccess));
        await _settle();
      });
      await frames(tester);
      expect(r.bridge.accessRequests, 1);
      expect(find.text(SweepAccessRefused.limitedSentence), findsOneWidget,
          reason: 'partial access is refused: the step stays, saying why');
      expect(find.text(CameraRollCopy.openSettings), findsOneWidget);
      expect(r.host.ledger!.enabled, isFalse);
      r.bridge.promptAnswers = SweepAccess.granted;
      await tester.runAsync(() async {
        await tester.tap(find.text(CameraRollCopy.allowAccess));
        await _settle(120);
      });
      await frames(tester);
      // 3 · what to take in: no kind switches; each reach counted
      expect(find.text('CAMERA ROLL · 3 OF 4'), findsOneWidget);
      expect(find.text(CameraRollCopy.keptCards), findsOneWidget);
      expect(find.textContaining('never uploaded'), findsOneWidget,
          reason: 'only the standfirst\'s "the rest are never uploaded"');
      expect(find.textContaining('cards or IDs'), findsNothing);
      expect(find.text('1 photo'), findsOneWidget, reason: 'the last month');
      expect(find.text('2 photos'), findsOneWidget, reason: 'the last year');
      expect(find.text('3 photos'), findsOneWidget, reason: 'everything');
      await tapText(tester, 'The last month');
      await tester.pump();
      await tapText(tester, CameraRollCopy.continueLabel);
      await frames(tester);
      // 4 · where it goes: the mode, never a confidence
      expect(find.text('CAMERA ROLL · 4 OF 4'), findsOneWidget);
      expect(find.text(CameraRollCopy.automatically), findsOneWidget);
      expect(find.text(CameraRollCopy.askFirst), findsOneWidget);
      expect(find.text(CameraRollCopy.askNote), findsOneWidget,
          reason: 'Ask me first until chosen (Swift\'s default)');
      expect(find.text(CameraRollCopy.lookBackNote), findsOneWidget);
      expect(find.text('Balanced'), findsNothing);
      await tapText(tester, CameraRollCopy.automatically);
      await tester.pump();
      expect(find.text(CameraRollCopy.automaticNote), findsOneWidget);
      expect(r.store.values[SweepLedger.kMode], isNull,
          reason: 'nothing is written before the last button');
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.startLooking);
        await _until(() => r.host.ledger!.enabled && !r.host.service!.isSweeping &&
            r.host.service!.candidates.isNotEmpty);
        await _settle();
      });
      await frames(tester);
      final ledger = r.host.ledger!;
      expect(ledger.enabled, isTrue);
      expect(ledger.mode, SweepMode.automatic);
      expect(ledger.reach, SweepReach.month);
      expect(r.store.values[SweepLedger.kReach], 'month');
      expect(r.host.service!.candidates.single.localIdentifier, 'new',
          reason: 'the look back waits for review even in Automatic mode');
      expect(r.endpoints.sessions, isEmpty, reason: 'nothing sent unreviewed');
      // Looking back, stopped: the figures and Review it now
      expect(find.text('CAMERA ROLL · LOOKING BACK'), findsOneWidget);
      expect(find.text('Looking Through the Last Month'), findsOneWidget);
      expect(find.text('THE LAST MONTH · 1 PHOTO'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('of 1 photos'), findsOneWidget);
      expect(find.text(CameraRollCopy.forReview), findsOneWidget);
      expect(find.text(CameraRollCopy.passedOver), findsOneWidget);
      expect(find.text('waiting for iCloud'), findsOneWidget);
      expect(find.text(CameraRollCopy.justFound.toUpperCase()), findsOneWidget);
      expect(find.text(CameraRollCopy.photoWithText), findsOneWidget);
      expect(find.text('taken in'), findsNothing,
          reason: 'a look back files nothing until it is reviewed');
      expect(find.text('Review it now'), findsOneWidget);
    });

    testWidgets('From now on: Turn it on, and the flow closes', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(60))], enabled: false);
      });
      await pump(tester, r.host, library());
      await tester.tap(find.text('Connect'));
      await frames(tester);
      await tapText(tester, CameraRollCopy.continueLabel);
      await frames(tester);
      await tester.runAsync(() async {
        await tester.tap(find.text(CameraRollCopy.allowAccess));
        await _settle(120);
      });
      await frames(tester);
      await tapText(tester, 'From now on');
      await tester.pump();
      await tapText(tester, CameraRollCopy.continueLabel);
      await frames(tester);
      expect(find.text(CameraRollCopy.lookBackNote), findsNothing);
      expect(find.text(CameraRollCopy.startLooking), findsNothing);
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.turnItOn);
        await _until(() => r.host.ledger!.enabled && !r.host.service!.isSweeping);
        await _settle();
      });
      await frames(tester, 12);
      expect(find.byType(CameraRollFlow), findsNothing);
      expect(r.host.ledger!.reach, SweepReach.fromNow);
      expect(r.host.service!.candidates, isEmpty, reason: 'nothing since now');
    });

    testWidgets('a refused write says so above the foot, and stays off', (tester) async {
      final store = FlakyStore();
      final bridge = FakeBridge([asset('a', seconds: _recent(60))]);
      final host = CameraSweepHost(
        session: _Session(true),
        isSignedIn: () => true,
        bridge: bridge,
        store: store,
        endpoints: FakeEndpoints(),
        uploader: FakeUploader(),
        background: null,
        observeLifecycle: false,
      );
      await tester.runAsync(() => host.ready);
      await pump(tester, host,
          const CameraRollFlow(start: CameraRollStep.where));
      store.failWrites = true;
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.startLooking);
        await _settle();
      });
      await frames(tester);
      expect(find.text(CameraSweepHost.notSaved), findsOneWidget);
      expect(host.ledger!.enabled, isFalse);
      expect(find.text('CAMERA ROLL · 4 OF 4'), findsOneWidget, reason: 'it did not move');
    });

    testWidgets('Escape closes the flow', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([], enabled: false);
      });
      await pump(tester, r.host, library());
      await tester.tap(find.text('Connect'));
      await frames(tester);
      expect(find.byType(CameraRollFlow), findsOneWidget);
      // The flow is a dialog route: its text must not fall back to the
      // framework's no-Material style (bold, yellow double underline), which
      // the first device frames showed.
      for (final t in [CameraRollCopy.introTitle, CameraRollCopy.introRows.first.$2]) {
        final rich = tester.widget<RichText>(
            find.descendant(of: find.text(t), matching: find.byType(RichText)));
        expect(rich.text.style?.decoration, isNot(TextDecoration.underline), reason: t);
        expect(rich.text.style?.fontWeight, isNot(FontWeight.w900), reason: t);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await frames(tester, 12);
      expect(find.byType(CameraRollFlow), findsNothing);
    });
  });

  group('the review', () {
    testWidgets(
        'one at a time: k of N, the summary, already in, pass over, file it, '
        'and Everything Is Filed', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([
          asset('a', seconds: _recent(1), screenshot: true),
          asset('b', seconds: _recent(2)),
          asset('n', seconds: _recent(3)),
        ], verdicts: {'n': SweepVerdict.noText});
        r.endpoints.filed[asset('b').assetKey] =
            const CaptureMatch(docId: 'cam-b', status: 'complete');
        r.endpoints.answers[asset('b').assetKey] = {
          'docId': 'cam-b',
          'duplicate': true,
          'status': 'complete',
          'uploadUrl': null,
        };
        await _until(() => r.host.service!.candidates.length == 2 &&
            !r.host.service!.isSweeping);
      });
      await pump(tester, r.host, library());
      await tester.tap(find.text('Review'));
      await frames(tester);
      expect(find.text('CAMERA ROLL · REVIEW · 1 OF 2'), findsOneWidget);
      expect(find.text('Filed 0 · Waiting 2 · Passed over 1'), findsOneWidget);
      expect(find.text('SCREENSHOT'), findsOneWidget);
      expect(find.textContaining('Taken on '), findsOneWidget);
      expect(find.text(CameraRollCopy.lookBackKeeps), findsOneWidget);
      expect(find.text(CameraRollCopy.filingLine), findsOneWidget);
      expect(find.text('File all 2'), findsOneWidget);
      expect(find.textContaining('File on'), findsNothing);
      expect(find.text('Another shelf'), findsNothing);
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.passOver);
        await _settle();
      });
      await frames(tester);
      expect(r.host.ledger!.verdict('a'), LedgerVerdict.dismissed);
      expect(r.endpoints.sessions, isEmpty, reason: 'passing over sends nothing');
      expect(find.text('CAMERA ROLL · REVIEW · 2 OF 2'), findsOneWidget);
      expect(find.text('Filed 0 · Waiting 1 · Passed over 2'), findsOneWidget);
      expect(find.text(CameraRollCopy.alreadyIn), findsOneWidget);
      expect(find.text('PHOTO WITH TEXT'), findsOneWidget);
      expect(find.text('File all 1'), findsNothing, reason: 'only while more than one waits');
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.fileIt);
        await _until(() => r.host.service!.candidates.isEmpty);
        await _settle();
      });
      await frames(tester);
      expect(r.endpoints.sessions, hasLength(1));
      expect(r.endpoints.puts, isEmpty, reason: 'already in: nothing uploads');
      expect(find.text(CameraRollCopy.endTitle), findsOneWidget);
      expect(find.text('CORRESPONDENCE · CAMERA ROLL · ON'), findsOneWidget);
      expect(
          find.text('1 photo is in your library and 2 were passed over. '
              '${CameraRollCopy.endAsk}'),
          findsOneWidget);
      await tapText(tester, CameraRollCopy.done);
      await frames(tester, 12);
      expect(find.byType(CameraRollFlow), findsNothing);
    });

    testWidgets('a refused filing stays, with its sentence in the note\'s slot',
        (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))]);
        r.endpoints.putFailsWith = 500;
        await _until(() => r.host.service!.candidates.isNotEmpty &&
            !r.host.service!.isSweeping);
      });
      await pump(tester, r.host,
          const CameraRollFlow(start: CameraRollStep.review));
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.fileIt);
        await _until(() => r.host.service!.candidateErrors.isNotEmpty);
        await _settle();
      });
      await frames(tester);
      expect(find.text('A photo could not be uploaded (HTTP 500). The next look tries again.'),
          findsOneWidget);
      expect(find.text(CameraRollCopy.lookBackKeeps), findsNothing);
      expect(r.host.service!.candidates, hasLength(1), reason: 'it stays');
    });
  });

  group('the panel', () {
    testWidgets('status, takes in, the mode written before it moves, the reach, '
        'and Turn off behind its confirm', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))], stored: {
          SweepLedger.kReach: 'month',
          SweepLedger.kMode: 'review',
        });
        await _until(() => !r.host.service!.isSweeping &&
            r.host.ledger!.lastLookedAt != null);
      });
      var closed = 0, further = 0;
      await pump(
          tester,
          r.host,
          SingleChildScrollView(
            child: CameraRollSettings(
              close: () => closed++,
              onLookFurther: () => further++,
            ),
          ));
      await frames(tester);
      expect(find.text('On · looked just now'), findsOneWidget);
      expect(find.text(CameraRollCopy.takesIn), findsOneWidget);
      expect(find.text(CameraRollCopy.takesInCards), findsOneWidget);
      expect(find.textContaining('always passed over'), findsNothing);
      expect(find.text('The last month · done'), findsOneWidget);
      expect(find.text(CameraRollCopy.lookFurther), findsOneWidget);
      expect(find.text(CameraRollCopy.startOver), findsOneWidget);
      expect(find.text(CameraRollCopy.lookNow), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.automatically);
        await _settle();
      });
      await frames(tester);
      expect(r.store.values[SweepLedger.kMode], 'automatic');
      expect(r.host.ledger!.mode, SweepMode.automatic);

      // Look further back: the start date moves, the done mark clears.
      await tester.runAsync(() async {
        await tapText(tester, CameraRollCopy.lookFurther);
        await _settle();
      });
      await frames(tester);
      expect(r.host.ledger!.reach, SweepReach.year);
      expect(r.store.values[SweepLedger.kReach], 'year');
      expect((closed, further), (1, 1));
      // Its pass ran; the walk to the new date is done again (the clearing
      // itself: camera_sweep_service_test, "a start date that moves").
      expect(find.textContaining('The last year'), findsOneWidget);

      await tapText(tester, CameraRollCopy.turnOff);
      await frames(tester);
      expect(find.text(CameraRollCopy.turnOffTitle), findsOneWidget);
      expect(find.text(CameraRollCopy.turnOffBody), findsOneWidget);
      expect(find.text(CameraRollCopy.keepItOn), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text(CameraRollCopy.turnOffConfirm));
        await _settle();
      });
      await frames(tester);
      expect(r.host.ledger!.enabled, isFalse);
      expect(r.host.ledger!.mode, SweepMode.automatic, reason: 'kept');
      expect(r.host.ledger!.reach, SweepReach.year, reason: 'kept');
      expect(closed, 2);
    });
  });

  // ── The sentences are the spec's ───────────────────────────────────────────

  group('copy', () {
    final contracts = Directory('../NoteLetter-contracts/spec');
    String read(String rel) => File('${contracts.path}/$rel').readAsStringSync();
    // Markdown wraps lines; compare on single spaces.
    String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

    test('the photo prompt says the feature spec\'s sentence, byte for byte', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final m = RegExp(r'<key>NSPhotoLibraryUsageDescription</key>\s*<string>([^<]*)</string>')
          .firstMatch(plist);
      expect(m, isNotNull);
      expect(flat(read('features/camera-roll-sweep.md')), contains(m!.group(1)!));
    });

    test('every sentence the camera roll draws is in the spec, verbatim', () {
      final spec = flat('${read('screens/sources.md')}'
          '\n${read('features/camera-roll-sweep.md')}');
      final at = DateTime(2026, 3, 14);
      for (final s in [
        CameraRollCopy.rowOff,
        CameraRollCopy.rowNoAccess,
        CameraRollCopy.rowUnreadable,
        CameraRollCopy.rowWaiting(7).replaceFirst('7', '{N}'),
        CameraRollCopy.rowOn(7).replaceFirst('7', '{N}'),
        CameraRollCopy.step(2).replaceFirst('2', '{n}'),
        CameraRollCopy.folio,
        CameraRollCopy.introTitle,
        CameraRollCopy.introStand,
        CameraRollCopy.introLabel,
        for (final (t, d) in CameraRollCopy.introRows) ...[t, d],
        CameraRollCopy.accessTitle,
        CameraRollCopy.accessStand,
        CameraRollCopy.allowAccess,
        CameraRollCopy.whatTitle,
        CameraRollCopy.whatStand,
        CameraRollCopy.keptLabel,
        CameraRollCopy.keptCards,
        CameraRollCopy.reachLabel,
        ...CameraRollCopy.reaches.values,
        CameraRollCopy.whereTitle,
        CameraRollCopy.whereStand,
        CameraRollCopy.modeLabel,
        CameraRollCopy.automatically,
        CameraRollCopy.askFirst,
        CameraRollCopy.automaticNote,
        CameraRollCopy.askNote,
        CameraRollCopy.lookBackNote,
        CameraRollCopy.startLooking,
        CameraRollCopy.turnItOn,
        CameraRollCopy.lookingHead,
        'Looking Through the Last Month',
        'Looking Through the Last Year',
        'Looking Through Everything',
        CameraRollCopy.lookingStand,
        CameraRollCopy.cappedStand,
        CameraRollCopy.trayFullStand,
        CameraRollCopy.forReview,
        CameraRollCopy.passedOver,
        CameraRollCopy.justFound,
        CameraRollCopy.screenshot,
        CameraRollCopy.photoWithText,
        CameraRollCopy.taken(at).replaceFirst('14 March', '{14 March}'),
        CameraRollCopy.takenOn(at).replaceFirst('14 March', '{14 March}'),
        CameraRollCopy.since(at).replaceFirst('14 March 2026', '{14 March 2026}'),
        CameraRollCopy.goToLibrary,
        CameraRollCopy.reviewNow(1),
        CameraRollCopy.reviewNow(2),
        CameraRollCopy.reviewHead(3, 9).replaceFirst('3', '{k}').replaceFirst('9', '{N}'),
        CameraRollCopy.summary(1, 2, 3)
            .replaceFirst('1', '{N}')
            .replaceFirst('2', '{N}')
            .replaceFirst('3', '{N}'),
        CameraRollCopy.alreadyIn,
        CameraRollCopy.lookBackKeeps,
        CameraRollCopy.youAsked,
        CameraRollCopy.filingLine,
        CameraRollCopy.fileIt,
        CameraRollCopy.fileAll(4).replaceFirst('4', '{N}'),
        CameraRollCopy.passOver,
        CameraRollCopy.endFolio,
        CameraRollCopy.endTitle,
        CameraRollCopy.endCounts(4, 5).replaceFirst('4', '{N}').replaceFirst('5', '{N}'),
        CameraRollCopy.endWalkLeft,
        CameraRollCopy.endAutomatic,
        CameraRollCopy.endAsk,
        CameraRollCopy.panelTitle,
        CameraRollCopy.takesInLabel,
        CameraRollCopy.takesIn,
        CameraRollCopy.takesInCards,
        CameraRollCopy.lookFurther,
        CameraRollCopy.startOver,
        CameraRollCopy.startOverTitle,
        CameraRollCopy.startOverBody,
        CameraRollCopy.startOverBody2,
        CameraRollCopy.keepProgress,
        CameraRollCopy.lookNow,
        CameraRollCopy.turnOff,
        CameraRollCopy.turnOffTitle,
        CameraRollCopy.turnOffBody,
        CameraRollCopy.turnOffConfirm,
        CameraRollCopy.keepItOn,
        CameraRollCopy.checkAgain,
        CameraRollCopy.openSettings,
        SweepAccessRefused.limitedSentence,
        SweepAccessRefused.deniedSentence,
        SweepAccessRefused.deniedAtSetupSentence,
        CameraSweepService.stoppedTitle,
        CameraSweepService.oneFailedTitle,
        CameraSweepService.iCloudSentence,
        SweepWords.android.deferredTitle,
        SweepWords.android.deferredSentence,
        DedupeUnsupported.message,
        CameraSweepHost.notSaved,
        CameraSweepService.uploadFailureSentence(statusCode: 403),
        CameraSweepService.uploadFailureSentence(statusCode: 501)
            .replaceFirst('501', '{status}'),
      ]) {
        expect(spec, contains(flat(s)), reason: s);
      }
    });

    test('never the claims D declined (feature §9)', () {
      final drawn = [
        CameraRollCopy.introStand,
        for (final (t, d) in CameraRollCopy.introRows) ...[t, d],
        CameraRollCopy.accessStand,
        CameraRollCopy.whatStand,
        CameraRollCopy.keptCards,
        CameraRollCopy.whereStand,
        CameraRollCopy.automaticNote,
        CameraRollCopy.askNote,
        CameraRollCopy.lookBackNote,
        CameraRollCopy.takesIn,
        CameraRollCopy.takesInCards,
        CameraRollCopy.endAutomatic,
        CameraRollCopy.endAsk,
      ].join(' ').toLowerCase();
      for (final no in [
        'cards or ids',
        'never uploaded: people',
        'always passed over',
        'faces',
        'is sure',
        'cautious',
        'trusting',
        'as you take them',
        'for your review',
        'sweep',
      ]) {
        expect(drawn, isNot(contains(no)), reason: no);
      }
    });
  });
}

/// A store whose read fails: the camera roll's settings could not be read.
class _Unreadable extends MemoryLedgerStore {
  @override
  Future<Map<String, Object?>> read(Set<String> keys) async =>
      throw StateError('unreadable');
}
