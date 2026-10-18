// F-125 S4: the camera-roll sweep in the background — the background
// uploader's results reaching the ledger (lib/services/sweep_uploader.dart),
// background time running out mid-pass (CameraSweepService.expire), and the
// BGProcessingTask's run (CameraSweepHost.backgroundRun, over
// lib/services/sweep_background.dart) — against the fakes every sweep test
// shares (sweep_fakes.dart). Ported from the retired Swift app's
// SweepBackgroundTask.swift and CameraSweepUploader.swift (NoteLetter 910864a).
//
// The rule these hold: a photo is `ingested` only when its bytes LANDED, and
// a capture session is never opened unless its upload is handed off right
// after — so an expiry never marks a photo done and never leaves a document
// no upload is coming for (S2's rule stands too: a fresh session with no
// upload link is refused).
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show AppLifecycleState, ChangeNotifier;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/sweep_background.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/services/sweep_uploader.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';

import 'sweep_fakes.dart';

Future<void> _settle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _until(bool Function() done, [String what = 'the condition']) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await _settle(5);
  }
  if (!done()) fail('timed out waiting for $what');
}

/// Automatic mode after the first backfill: candidates are filed as found.
Future<void> _automatic(SweepLedger ledger) async {
  await ledger.setMode(SweepMode.automatic);
  await ledger.setBackfillComplete(true);
}

class _Session extends ChangeNotifier {
  _Session(this.signedIn);
  bool signedIn;
}

double _recent(int minutesAgo) =>
    DateTime.now().subtract(Duration(minutes: minutesAgo)).millisecondsSinceEpoch / 1000;

typedef _HostRig = ({
  CameraSweepHost host,
  FakeBridge bridge,
  FakeEndpoints endpoints,
  FakeBackground background,
  MemoryLedgerStore store,
  _Session session,
});

Future<_HostRig> _host(
  List<SweepAsset> assets, {
  bool enabled = true,
  bool signedIn = true,
  SweepAccess access = SweepAccess.granted,
  MemoryLedgerStore? store,
  FakeEndpoints? endpoints,
}) async {
  final s = store ?? MemoryLedgerStore();
  if (enabled) await s.write(SweepLedger.kEnabled, true);
  final bridge = FakeBridge(assets)..accessNow = access;
  final ep = endpoints ?? FakeEndpoints();
  final background = FakeBackground();
  final session = _Session(signedIn);
  final host = CameraSweepHost(
    session: session,
    isSignedIn: () => session.signedIn,
    bridge: bridge,
    store: s,
    endpoints: ep,
    uploader: ep.uploader,
    background: background,
    debounce: const Duration(milliseconds: 20),
    observeLifecycle: false,
  );
  await host.ready;
  return (
    host: host,
    bridge: bridge,
    endpoints: ep,
    background: background,
    store: s,
    session: session,
  );
}

void main() {
  // ── Background uploads ─────────────────────────────────────────────────────

  group('background uploads', () {
    test('a photo is recorded when its bytes LAND, never at the hand-off', () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await _automatic(ledger);
      ep.uploader.hold = true;
      var passDone = false;
      final pass = svc.sweep().whenComplete(() => passDone = true);
      await _until(() => ep.uploader.starts.isNotEmpty, 'the hand-off');
      expect(ledger.verdict('p1'), isNull, reason: 'handed off is not landed');
      expect(svc.ingestedThisSession, 0);
      expect(svc.uploadsInFlight, 1);
      await _settle();
      expect(passDone, isFalse, reason: 'an automatic pass ends with its uploads');
      ep.uploader.landAll();
      final p = await pass;
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
      expect((p.uploading, p.ingested), (1, 1));
      expect(svc.uploadsInFlight, 0);
      expect(ep.uploader.acknowledged, ['u1'], reason: 'recorded, then forgotten natively');
    });

    test('the upload carries the bytes the session declared, under INV-08', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      await _automatic(ledger);
      await svc.sweep();
      final s = ep.uploader.starts.single;
      expect(s.url, 'https://storage.example/put/${bridge.assets.single.assetKey}');
      expect(s.mimeType, 'image/jpeg');
      expect(s.assetKey, bridge.assets.single.assetKey);
      expect(ep.sessions.single.size, s.bytes.length,
          reason: 'the session declares the staged file\'s size');
      expect(File(bridge.renderedPaths.single).existsSync(), isFalse,
          reason: 'the rendered copy was MOVED into the uploader\'s keeping');
    });

    test('a tray card stays while its upload is on its way, and leaves when it lands',
        () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await svc.sweep();
      ep.uploader.hold = true;
      var settled = false;
      final add = svc.approve(svc.candidates.single).whenComplete(() => settled = true);
      await _until(() => ep.uploader.starts.isNotEmpty, 'the hand-off');
      await _settle();
      expect(settled, isFalse);
      expect(svc.candidates, hasLength(1), reason: 'not in yet: the card stays (D5)');
      expect(ledger.verdict('p1'), isNull);
      ep.uploader.landAll();
      await add;
      expect(svc.candidates, isEmpty);
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
      expect(svc.ingestedThisSession, 1);
    });

    test('an upload that did not land keeps its card, with the uploader\'s sentence',
        () async {
      for (final (fail, sentence) in [
        (
          403,
          'A photo’s upload link expired before the transfer finished. '
              'The next sweep starts it again.'
        ),
        (500, 'A photo could not be uploaded (HTTP 500). The next sweep tries again.'),
        (
          'The network connection was lost.',
          'A photo could not be uploaded — The network connection was lost. '
              'The next sweep tries again.'
        ),
      ]) {
        final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
        await svc.sweep();
        ep.uploader.failWith = fail;
        await svc.approve(svc.candidates.single);
        expect(svc.candidateErrors['p1'], sentence, reason: '$fail');
        expect(svc.candidates, hasLength(1));
        expect(ledger.verdict('p1'), isNull,
            reason: 'nothing recorded: the next pass re-requests a link');
        expect(svc.ingestedThisSession, 0);
        await _until(() => ep.uploader.acknowledged.isNotEmpty, 'the acknowledgement');
        expect(ep.uploader.acknowledged, ['u1'], reason: 'a failure is recorded too');
      }
    });

    test('Add all opens each session just before its upload, and they land side by side',
        () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1'), asset('p2'), asset('p3')]);
      await svc.sweep();
      ep.uploader.hold = true;
      final all = svc.approveAll();
      await _until(() => ep.uploader.starts.length == 3, 'three hand-offs');
      expect(ep.sessions, hasLength(3));
      expect(svc.candidates, hasLength(3), reason: 'none landed yet');
      ep.uploader.land('u2');
      await _until(() => svc.candidates.length == 2, 'one card to leave');
      expect(svc.candidates.map((c) => c.localIdentifier), ['p1', 'p3']);
      ep.uploader.landAll();
      await all;
      expect(svc.candidates, isEmpty);
      expect(ledger.ingestedCount, 3);
    });

    test('a card whose upload is on its way opens no second session', () async {
      final (svc, _, _, ep, _) = await rig([asset('p1')]);
      await svc.sweep();
      ep.uploader.hold = true;
      final card = svc.candidates.single;
      final first = svc.approve(card);
      await _until(() => ep.uploader.starts.isNotEmpty, 'the hand-off');
      final second = svc.approve(card);
      await _settle();
      expect(ep.sessions, hasLength(1));
      ep.uploader.landAll();
      await Future.wait([first, second]);
      expect(ep.uploader.starts, hasLength(1));
    });

    test('nothing to send: the staged bytes are discarded and the photo recorded', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      ep.answers[bridge.assets.single.assetKey] = {
        'docId': 'cam-1', 'duplicate': true, 'status': 'complete',
        'gcsPath': 'raw/x', 'uploadUrl': null,
      };
      await svc.sweep();
      await svc.approveAll();
      expect(ep.uploader.starts, isEmpty);
      expect(ep.uploader.discarded, ['u1']);
      expect(ep.uploader.stagedNotStarted, isEmpty);
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
    });

    test('a refused session discards what was staged, and records nothing', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      ep.answers[bridge.assets.single.assetKey] = {
        'docId': 'cam-1', 'duplicate': false, 'uploadUrl': null, 'gcsPath': 'raw/x',
      };
      await svc.sweep();
      await svc.approveAll();
      expect(svc.candidateErrors['p1'], isNotNull,
          reason: 'S2: a fresh session with no link is refused');
      expect(ep.uploader.discarded, ['u1']);
      expect(ledger.verdict('p1'), isNull);
    });

    test('an upload the system will not take keeps the card, and records nothing',
        () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await svc.sweep();
      ep.uploader.refuseStart = true;
      await svc.approve(svc.candidates.single);
      expect(svc.candidateErrors['p1'], 'not staged: u1');
      expect(ledger.verdict('p1'), isNull);
      expect(svc.uploadsInFlight, 0);
      expect(ep.uploader.discarded, ['u1']);
    });

    test('a result that came back while the app was away is recorded at the next attach',
        () async {
      final store = MemoryLedgerStore();
      final first = await rig([asset('p1')], store: store);
      final (svc, ledger, bridge, ep, _) = first;
      await _automatic(ledger);
      ep.uploader.hold = true;
      unawaited(svc.sweep());
      await _until(() => ep.uploader.starts.isNotEmpty, 'the hand-off');
      // The app is gone; the upload lands; the native side writes it down.
      await svc.close();
      ep.uploader.landAll();
      expect(ep.uploader.waiting, hasLength(1));

      final ledger2 = await SweepLedger.load(store);
      expect(ledger2.verdict('p1'), isNull);
      final next = CameraSweepService(
          bridge: bridge, ledger: ledger2, endpoints: ep, uploader: ep.uploader);
      await next.attachUploads();
      expect(ledger2.verdict('p1'), LedgerVerdict.ingested);
      expect(next.ingestedThisSession, 1);
      expect(ep.uploader.waiting, isEmpty, reason: 'acknowledged once recorded');
    });

    test('a failed result from an earlier launch is said on the alert, not lost', () async {
      final (svc, ledger, _, ep, _) = await rig([]);
      ep.uploader.resultFromEarlierLaunch(const SweepUploadResult(
        uploadId: 'old', localIdentifier: 'p9', assetKey: 'v1:x',
        ok: false, statusCode: 403,
      ));
      await svc.drainUploads();
      expect(svc.errorMessage,
          'A photo’s upload link expired before the transfer finished. '
          'The next sweep starts it again.');
      expect(svc.errorStoppedSweep, isFalse, reason: 'one photo, not the sweep');
      expect(ledger.verdict('p9'), isNull);
      expect(ep.uploader.acknowledged, ['old']);
    });

    test('a photo an earlier launch is still uploading is neither examined nor sent',
        () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1'), asset('p2')]);
      await _automatic(ledger);
      ep.uploader.elsewhere.add(const SweepUploadInFlight(
          uploadId: 'old', localIdentifier: 'p1', assetKey: 'v1:x'));
      final pass = await svc.sweep();
      expect(bridge.examinedIds, ['p2']);
      expect(pass.inFlight, 1);
      expect(ep.sessions.map((s) => s.assetKey), [bridge.assets[1].assetKey]);
      expect(ledger.verdict('p1'), isNull, reason: 'recorded when ITS result comes back');
      ep.uploader.elsewhere.clear();
      ep.uploader.resultFromEarlierLaunch(const SweepUploadResult(
          uploadId: 'old', localIdentifier: 'p1', assetKey: 'v1:x', ok: true, statusCode: 200));
      await svc.drainUploads();
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
    });

    test('a landed result whose ledger write fails stays, and is recorded (once) next time',
        () async {
      final store = FlakyStore();
      final (svc, ledger, _, ep, _) = await rig([asset('p1')], store: store);
      await svc.sweep();
      ep.uploader.hold = true;
      final add = svc.approve(svc.candidates.single);
      await _until(() => ep.uploader.starts.isNotEmpty, 'the hand-off');
      store.failWrites = true;
      ep.uploader.landAll();
      await add;
      expect(svc.candidates, isEmpty, reason: 'the photo IS in');
      expect(ep.uploader.acknowledged, isEmpty, reason: 'not recorded, so kept');
      expect(ep.uploader.waiting, hasLength(1));
      expect(svc.ingestedThisSession, 0);
      store.failWrites = false;
      await svc.drainUploads();
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
      expect(ep.uploader.acknowledged, ['u1']);
      expect(svc.ingestedThisSession, 1);
      await svc.drainUploads();
      expect(svc.ingestedThisSession, 1, reason: 'counted once');
    });

    test('an acknowledgement that fails is read again, and counted once', () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await svc.sweep();
      ep.uploader.failAcknowledge = true;
      await svc.approve(svc.candidates.single);
      expect(ep.uploader.waiting, hasLength(1));
      ep.uploader.failAcknowledge = false;
      await svc.drainUploads();
      expect(ep.uploader.waiting, isEmpty);
      expect(svc.ingestedThisSession, 1);
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
    });
  });

  // ── Background time running out ────────────────────────────────────────────

  group('expiry', () {
    test('before the session: nothing is opened, and the staged bytes are discarded',
        () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1'), asset('p2')]);
      await _automatic(ledger);
      final gate = Completer<void>();
      bridge.examineGate = gate.future;
      final pass = svc.sweep();
      await _settle();
      final expired = svc.expire();
      gate.complete();
      await expired;
      final p = await pass;
      expect(ep.sessions, isEmpty, reason: 'told to stop: no document is made');
      expect(ep.uploader.discarded, ['u1']);
      expect(ep.uploader.stagedNotStarted, isEmpty);
      expect(ledger.verdict('p1'), isNull);
      expect(ledger.verdict('p2'), isNull, reason: 'the pass stopped at the next photo');
      expect(bridge.examinedIds, ['p1']);
      expect(p.ingested, 0);
    });

    test('during a session: it waits, the upload is handed off, and nothing more opens',
        () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1'), asset('p2')]);
      await _automatic(ledger);
      final gate = Completer<void>();
      ep.sessionGate = gate.future;
      ep.uploader.hold = true;
      final pass = svc.sweep();
      await _until(() => ep.sessions.isNotEmpty, 'a session in flight');
      var expiredDone = false;
      final expired = svc.expire().whenComplete(() => expiredDone = true);
      await _settle();
      expect(expiredDone, isFalse, reason: 'never between a session and its upload');
      gate.complete();
      await expired;
      expect(ep.uploader.starts, hasLength(1),
          reason: 'the session that was opened got its upload — no empty document');
      expect(ep.sessions, hasLength(1), reason: 'and no other session opened');
      expect(ledger.verdict('p1'), isNull, reason: 'handed off is not landed');
      final p = await pass;
      expect(p.uploading, 1);
      // The upload outlives the pass that started it, and is recorded when it lands.
      ep.uploader.landAll();
      await _until(() => ledger.verdict('p1') != null, 'the landing');
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
      expect(ledger.verdict('p2'), isNull);
    });

    test('the wait is bounded: a session that never answers is left to the next pass',
        () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await _automatic(ledger);
      ep.sessionGate = Completer<void>().future; // never answers
      unawaited(svc.sweep());
      await _until(() => ep.sessions.isNotEmpty, 'a session in flight');
      final t = Stopwatch()..start();
      await svc.expire(grace: const Duration(milliseconds: 80));
      expect(t.elapsedMilliseconds, lessThan(1000));
      expect(ledger.verdict('p1'), isNull,
          reason: 'not recorded: the next pass asks again, and the replay hands back '
              'the link (spec §6)');
    });

    test('after expiry no pass runs until resume', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      await _automatic(ledger);
      await svc.expire();
      expect(svc.halted, isTrue);
      final p = await svc.sweep();
      expect(p.halted, isTrue);
      expect(bridge.examinedIds, isEmpty);
      svc.resume();
      final again = await svc.sweep();
      expect(again.halted, isFalse);
      expect(again.ingested, 1);
    });

    test('an expired pass does not call the backfill complete', () async {
      final (svc, ledger, bridge, _, _) = await rig([asset('p1'), asset('p2')]);
      final gate = Completer<void>();
      bridge.examineGate = gate.future;
      final pass = svc.sweep();
      await _settle();
      final expired = svc.expire();
      gate.complete();
      await expired;
      await pass;
      expect(ledger.backfillComplete, isFalse);
      expect(bridge.examinedIds, ['p1']);
    });

    test('an expired pass ends without waiting for its uploads, which land later', () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await _automatic(ledger);
      ep.uploader.hold = true;
      final pass = svc.sweep();
      await _until(() => ep.uploader.starts.isNotEmpty, 'the hand-off');
      await svc.expire();
      final p = await pass.timeout(const Duration(seconds: 2));
      expect((p.uploading, p.ingested), (1, 0));
      ep.uploader.landAll();
      await _until(() => ledger.verdict('p1') != null, 'the landing');
      expect(svc.ingestedThisSession, 1);
    });
  });

  // ── The BGProcessingTask ───────────────────────────────────────────────────

  group('background task', () {
    test('asked for while the sweep is on, withdrawn when it is off', () async {
      final on = await _host([]);
      expect(on.background.attached, isTrue);
      expect(on.background.scheduledCalls, [true]);
      await on.host.disable();
      await _settle();
      expect(on.background.scheduledCalls.last, isFalse);
      await on.host.enable();
      await _settle();
      expect(on.background.scheduledCalls.last, isTrue);

      final off = await _host([], enabled: false);
      expect(off.background.scheduledCalls, [false]);
    });

    test('a run ENDS when its pass does (Swift\'s reported done at once)', () async {
      final r = await _host([asset('p1', seconds: _recent(5))]);
      await _until(() => !r.host.service!.isSweeping, 'the launch pass');
      r.bridge.assets.insert(0, asset('p2', seconds: _recent(1)));
      final gate = Completer<void>();
      r.bridge.examineGate = gate.future;
      var ran = false;
      final run = r.background.launch().whenComplete(() => ran = true);
      await _until(() => r.host.service!.isSweeping, 'the run\'s pass');
      await _settle();
      expect(ran, isFalse, reason: 'the pass is still running');
      gate.complete();
      final answer = await run;
      expect(answer['ran'], isTrue);
      expect(r.bridge.examinedIds, contains('p2'));
    });

    test('a run under the sweep\'s settings: off, signed out, or partial access runs nothing',
        () async {
      final off = await _host([asset('p1', seconds: _recent(5))], enabled: false);
      expect((await off.background.launch())['why'], 'off');
      await _settle();
      expect(off.background.scheduledCalls.last, isFalse, reason: 'withdrawn');

      final out = await _host([asset('p1', seconds: _recent(5))], signedIn: false);
      expect((await out.background.launch())['why'], 'signedOut');

      final limited = await _host([asset('p1', seconds: _recent(5))],
          access: SweepAccess.limited);
      expect((await limited.background.launch())['why'], 'access limited');

      for (final r in [off, out, limited]) {
        expect(r.bridge.examinedIds, isEmpty);
        expect(r.endpoints.sessions, isEmpty);
      }
    });

    test('a run in Review mode fills the tray and uploads nothing', () async {
      final r = await _host([], enabled: true);
      r.bridge.assets.add(asset('p1', seconds: _recent(5)));
      final answer = await r.background.launch();
      expect(answer['ran'], isTrue);
      expect(r.host.service!.candidates.single.localIdentifier, 'p1');
      expect(r.endpoints.sessions, isEmpty);
    });

    test('an automatic run files and uploads, and answers once they landed', () async {
      final store = MemoryLedgerStore({
        SweepLedger.kMode: 'automatic',
        SweepLedger.kBackfillComplete: true,
      });
      final r = await _host([], store: store);
      r.bridge.assets.add(asset('p1', seconds: _recent(5)));
      final answer = await r.background.launch();
      expect(answer['ran'], isTrue);
      expect(r.endpoints.uploader.starts, hasLength(1));
      expect(r.host.ledger!.verdict('p1'), LedgerVerdict.ingested);
    });

    test('a run joins a pass already running, rather than starting a second', () async {
      final r = await _host([]);
      final gate = Completer<void>();
      r.bridge.examineGate = gate.future;
      r.bridge.assets.add(asset('p1', seconds: _recent(5)));
      r.host.kick();
      await _until(() => r.host.service!.isSweeping, 'a foreground pass');
      final run = r.background.launch();
      gate.complete();
      expect((await run)['ran'], isTrue);
      expect(r.bridge.examinedIds, ['p1'], reason: 'examined once');
    });

    test('expiry during a run: the pass stops, the run answers, nothing starts after',
        () async {
      final store = MemoryLedgerStore({
        SweepLedger.kMode: 'automatic',
        SweepLedger.kBackfillComplete: true,
      });
      final r = await _host([], store: store);
      r.bridge.assets
        ..add(asset('p1', seconds: _recent(5)))
        ..add(asset('p2', seconds: _recent(6)));
      final gate = Completer<void>();
      r.endpoints.sessionGate = gate.future;
      r.endpoints.uploader.hold = true;
      final run = r.background.launch();
      await _until(() => r.endpoints.sessions.isNotEmpty, 'a session in flight');
      final expired = r.background.expire();
      gate.complete();
      await expired;
      await run.timeout(const Duration(seconds: 2));
      expect(r.endpoints.sessions, hasLength(1));
      expect(r.endpoints.uploader.starts, hasLength(1), reason: 'its upload went');
      expect(r.host.ledger!.verdict('p1'), isNull);
      r.host.kick();
      await _settle();
      expect(r.endpoints.sessions, hasLength(1), reason: 'halted until the app is back');
      r.host.didChangeAppLifecycleState(AppLifecycleState.resumed);
      r.endpoints.uploader.hold = false;
      r.endpoints.uploader.landAll();
      await _until(() => r.host.ledger!.ingestedCount == 2, 'the next pass, in the foreground');
      expect(r.endpoints.sessions, hasLength(2));
    });

    test('leaving the foreground halts passes; a task\'s own pass is not halted by it',
        () async {
      final r = await _host([]);
      await _until(() => !r.host.service!.isSweeping, 'the launch pass');
      r.host.didChangeAppLifecycleState(AppLifecycleState.paused);
      await _settle();
      expect(r.host.service!.halted, isTrue);
      r.host.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _settle();
      expect(r.host.service!.halted, isFalse);

      final gate = Completer<void>();
      r.bridge.examineGate = gate.future;
      r.bridge.assets.add(asset('p1', seconds: _recent(5)));
      r.host.didChangeAppLifecycleState(AppLifecycleState.paused);
      final run = r.background.launch();
      await _until(() => r.host.service!.isSweeping, 'the run\'s pass');
      r.host.didChangeAppLifecycleState(AppLifecycleState.paused);
      gate.complete();
      expect((await run)['ran'], isTrue);
      expect(r.bridge.examinedIds, ['p1'], reason: 'the task\'s pass ran through');
    });

    test('a run records the results that came back while the app was away first',
        () async {
      final r = await _host([], enabled: true);
      r.bridge.assets.add(asset('p1', seconds: _recent(5)));
      r.endpoints.uploader.resultFromEarlierLaunch(SweepUploadResult(
          uploadId: 'old', localIdentifier: 'p1', assetKey: r.bridge.assets.single.assetKey,
          ok: true, statusCode: 200));
      final answer = await r.background.launch();
      expect(answer['ran'], isTrue);
      expect(r.host.ledger!.verdict('p1'), LedgerVerdict.ingested);
      expect(r.bridge.examinedIds, isEmpty, reason: 'recorded, so not examined again');
    });
  });

  // ── The native wiring, read ────────────────────────────────────────────────

  group('native wiring', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final task = File('ios/Runner/CameraSweep/SweepBackgroundTask.swift').readAsStringSync();
    final uploader = File('ios/Runner/CameraSweep/CameraSweepUploader.swift').readAsStringSync();
    final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    List<String> plistArray(String key) {
      final m = RegExp('<key>$key</key>\\s*<array>(.*?)</array>', dotAll: true).firstMatch(plist);
      if (m == null) return const [];
      return RegExp('<string>(.*?)</string>').allMatches(m.group(1)!).map((x) => x.group(1)!).toList();
    }

    test('Info.plist permits this app\'s OWN task identifier, and only it', () {
      expect(plistArray('BGTaskSchedulerPermittedIdentifiers'),
          [NativeSweepBackground.taskIdentifier]);
      expect(NativeSweepBackground.taskIdentifier, 'xp.NoteLetter.Flutter.camerasweep.refresh');
      expect(plist.contains('<string>xp.NoteLetter.camerasweep.refresh</string>'), isFalse,
          reason: 'the retired Swift app\'s');
      expect(plistArray('UIBackgroundModes'), contains('processing'));
    });

    test('the native task registers the identifier the plist permits', () {
      expect(task, contains('static let identifier = "${NativeSweepBackground.taskIdentifier}"'));
      expect(task, contains('static let channelName = "${NativeSweepBackground.channelName}"'));
      expect(task, contains('requiresExternalPower = true'));
      expect(task, contains('requiresNetworkConnectivity = true'));
    });

    test('registered before launch finishes, and the upload session reconnected', () {
      final launch = delegate.indexOf('didFinishLaunchingWithOptions');
      final register = delegate.indexOf('SweepBackgroundTask.register()');
      final session = delegate.indexOf('_ = CameraSweepUploader.shared.session');
      final ret = delegate.indexOf('return super.application(application, didFinishLaunchingWithOptions');
      expect(launch, greaterThan(0));
      expect(register, inExclusiveRange(launch, ret));
      expect(session, inExclusiveRange(launch, ret));
      expect(delegate, contains('handleEventsForBackgroundURLSession identifier: String'));
      expect(delegate, contains('CameraSweepUploader.shared.wokeForEvents(completionHandler)'));
    });

    test('the upload session is this app\'s own, a background one, and sends no Authorization',
        () {
      expect(uploader,
          contains('static let sessionIdentifier = "xp.NoteLetter.Flutter.camerasweep.upload"'));
      expect(uploader, contains('URLSessionConfiguration.background(withIdentifier:'));
      expect(uploader, contains('config.sessionSendsLaunchEvents = true'));
      expect(uploader, contains('request.httpMethod = "PUT"'));
      expect(uploader, contains('forHTTPHeaderField: "Content-Type"'));
      expect(uploader.contains('"Authorization"'), isFalse, reason: 'INV-08: a bare PUT');
      expect(RegExp(r'setValue\(').allMatches(uploader).length, 1,
          reason: 'one header is set, the Content-Type');
      expect(NativeSweepUploader.eventsName, 'xp.noteletter/camera_sweep/uploads');
      expect(uploader, contains('static let eventsName = "${NativeSweepUploader.eventsName}"'));
    });

    test('the debugger\'s simulate calls exist only in debug builds', () {
      final debug = task.indexOf('#if DEBUG');
      final end = task.indexOf('#endif', debug);
      for (final sel in [
        '_simulateLaunchForTaskWithIdentifier:',
        '_simulateExpirationForTaskWithIdentifier:',
      ]) {
        final at = task.indexOf(sel);
        expect(at, inExclusiveRange(debug, end), reason: sel);
        expect(task.indexOf(sel, at + 1), -1, reason: '$sel appears once');
      }
    });
  });
}
