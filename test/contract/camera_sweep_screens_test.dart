// F-125 S3: the camera-roll sweep's screens and what starts it in the
// foreground — lib/state/camera_sweep_host.dart,
// lib/pages/settings/camera_sweep_page.dart, lib/pages/sources/sweep_tray.dart,
// lib/widgets/kit/kit_capture.dart — against the fakes the service's own
// tests use (sweep_fakes.dart). The retired Swift app's CameraSweepSettingsView
// and SweepReviewSection (NoteLetter 910864a) are the behaviour ported.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/pages/settings/camera_sweep_page.dart';
import 'package:flutter_app/pages/settings_page.dart';
import 'package:flutter_app/pages/sources/sweep_tray.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/firestore_service.dart' show CaptureMatch;
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

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

  // ── The screens ────────────────────────────────────────────────────────────

  Future<void> pump(WidgetTester tester, CameraSweepHost host, Widget child,
      {ThemeData? theme}) async {
    tester.view.physicalSize = const Size(402, 1400);
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

  group('the tray', () {
    testWidgets('cards, the count, already-in, a refusal, Add all', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([
          asset('a', seconds: _recent(1)),
          asset('b', seconds: _recent(2)),
          asset('c', seconds: _recent(3)),
        ]);
        r.endpoints.filed[asset('b').assetKey] =
            const CaptureMatch(docId: 'cam-b', status: 'complete');
        await _until(() => r.host.service!.candidates.length == 3);
        r.host.service!.record('Your library is full.', 'c');
      });
      await pump(tester, r.host, const SingleChildScrollView(child: SweepTraySection()));
      await tester.pump();
      expect(find.text('FROM YOUR CAMERA ROLL · 3'), findsOneWidget);
      expect(find.byType(KitCaptureCard), findsNWidgets(3));
      expect(find.text(KitCaptureCard.alreadyInLabel), findsOneWidget);
      expect(find.text('Your library is full.'), findsOneWidget);
      expect(find.text('Add all 3'), findsOneWidget);
      expect(find.byTooltip('Skip this photo'), findsNWidgets(3));
      expect(find.byTooltip('Add this photo'), findsNWidgets(3));
      expect(r.bridge.thumbnailsAsked.toSet(), {'a', 'b', 'c'});
    });

    testWidgets('Skip removes the card and sends nothing', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1)), asset('b', seconds: _recent(2))]);
        await _until(() => r.host.service!.candidates.length == 2);
      });
      await pump(tester, r.host, const SingleChildScrollView(child: SweepTraySection()));
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Skip this photo').first);
        await _settle();
      });
      await tester.pump();
      expect(find.byType(KitCaptureCard), findsOneWidget);
      expect(r.endpoints.sessions, isEmpty);
      expect(r.host.ledger!.verdict('a'), LedgerVerdict.dismissed);
    });

    testWidgets('hidden while off, and with nothing to show', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))], enabled: false);
      });
      await pump(tester, r.host, const SingleChildScrollView(child: SweepTraySection()));
      expect(find.textContaining('FROM YOUR CAMERA ROLL'), findsNothing);
    });

    testWidgets('a stopped sweep is said, with no retry', (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))]);
        await _until(() => r.host.service!.candidates.isNotEmpty);
        r.host.service!
            .presentFailure(DedupeUnsupported.message, stopsSweep: true);
      });
      await pump(tester, r.host, const SingleChildScrollView(child: SweepTraySection()));
      expect(find.text('Sweep stopped'), findsOneWidget);
      expect(find.text(DedupeUnsupported.message), findsOneWidget);
      expect(find.text('Check again'), findsNothing);
    });
  });

  group('the settings screen', () {
    testWidgets('off: the switch alone; turned on with full access, the rest',
        (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('a', seconds: _recent(1))], enabled: false)
          ..bridge.accessNow = SweepAccess.denied
          ..bridge.promptAnswers = SweepAccess.granted;
      });
      await pump(tester, r.host, const CameraSweepPage());
      await tester.runAsync(_settle);
      await tester.pump();
      expect(find.text(CameraSweepPage.switchTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.modeTitle), findsNothing);
      expect(find.text(SweepAccessRefused.deniedSentence), findsNothing,
          reason: 'never asked, never on: nothing to refuse yet');
      expect(r.bridge.accessRequests, 0, reason: 'opening the screen asks nothing');
      await tester.runAsync(() async {
        await tester.tap(find.byType(KitSwitch));
        await _until(() => r.host.ledger!.enabled);
      });
      await tester.pump();
      expect(r.bridge.accessRequests, 1);
      expect(find.text(CameraSweepPage.modeTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.automaticLabel), findsOneWidget);
      expect(find.text(CameraSweepPage.reviewLabel), findsOneWidget);
      expect(find.text(CameraSweepPage.firstCatchUpNote), findsOneWidget,
          reason: 'before the first catch-up, the review promise');
      expect(find.text(CameraSweepPage.goBackTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.addedTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.startOverTitle), findsOneWidget);
    });

    for (final (got, sentence) in [
      (SweepAccess.limited, SweepAccessRefused.limitedSentence),
      (SweepAccess.denied, SweepAccessRefused.deniedSentence),
    ]) {
      testWidgets('${got.name} at the prompt: the sentence, and Open Settings',
          (tester) async {
        late _Rig r;
        await tester.runAsync(() async {
          r = await _rig([], enabled: false)
            ..bridge.accessNow = SweepAccess.denied
            ..bridge.promptAnswers = got;
        });
        await pump(tester, r.host, const CameraSweepPage());
        await tester.runAsync(() async {
          await tester.tap(find.byType(KitSwitch));
          await _until(() => r.bridge.accessRequests == 1);
          await _settle();
        });
        await tester.pump();
        expect(find.text(sentence), findsOneWidget);
        expect(find.byType(KitNotice), findsOneWidget);
        expect(r.host.ledger!.enabled, isFalse);
        expect(find.text(CameraSweepPage.modeTitle), findsNothing);
        await tester.tap(find.text('Open Settings'));
        expect(r.bridge.settingsOpened, 1);
      });
    }

    testWidgets('Start over asks first (§18), naming what comes back',
        (tester) async {
      late _Rig r;
      await tester.runAsync(() async {
        r = await _rig([asset('n1', seconds: _recent(1))],
            verdicts: {'n1': SweepVerdict.noText});
        await _until(() => r.host.ledger!.verdicts.isNotEmpty);
      });
      await pump(tester, r.host, const CameraSweepPage());
      await tester.runAsync(_settle);
      await tester.pump();
      await tester.ensureVisible(find.byType(KitFormDangerButton));
      await tester.tap(find.byType(KitFormDangerButton));
      await tester.pumpAndSettle();
      expect(find.text(CameraSweepPage.confirmTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.keepLabel), findsOneWidget);
      expect(r.host.ledger!.verdicts, isNotEmpty, reason: 'nothing until confirmed');
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

    test('every sentence the two screens draw is in the spec, verbatim', () {
      final spec = flat('${read('screens/settings.md')}\n${read('screens/sources.md')}'
          '\n${read('features/camera-roll-sweep.md')}');
      for (final s in [
        CameraSweepPage.standfirst,
        CameraSweepPage.switchTitle,
        CameraSweepPage.modeTitle,
        CameraSweepPage.automaticLabel,
        CameraSweepPage.reviewLabel,
        CameraSweepPage.firstCatchUpNote,
        CameraSweepPage.automaticNote,
        CameraSweepPage.goBackTitle,
        CameraSweepPage.catchUpNote,
        CameraSweepPage.inRangeTitle,
        CameraSweepPage.addedTitle,
        CameraSweepPage.iCloudTitle,
        CameraSweepPage.waitingTitle,
        CameraSweepPage.checkTitle,
        CameraSweepPage.startOverTitle,
        CameraSweepPage.confirmTitle,
        ...CameraSweepPage.confirmBody.split('\n\n'),
        CameraSweepPage.keepLabel,
        SweepAccessRefused.limitedSentence,
        SweepAccessRefused.deniedSentence,
        SweepTraySection.looking,
        KitCaptureCard.alreadyInLabel,
        CameraSweepService.iCloudSentence,
        DedupeUnsupported.message,
        CameraSweepHost.notSaved,
        SettingsPage.cameraRollDescription,
        'Sweep stopped',
        'A photo couldn’t be added',
        'Open Settings',
        'Skip this photo',
        'Add this photo',
        'Open camera roll settings',
        'This phone’s sweep settings could not be read.',
        CameraSweepService.uploadFailureSentence(statusCode: 403),
        CameraSweepService.uploadFailureSentence(statusCode: 501)
            .replaceFirst('501', '{status}'),
      ]) {
        expect(spec, contains(flat(s)), reason: s);
      }
    });
  });
}
