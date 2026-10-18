// F-125 S2: the camera-roll sweep's ledger and service
// (lib/services/sweep_ledger.dart, lib/services/camera_sweep_service.dart),
// ported from the retired Swift app's SweepLedger / CameraSweepService /
// CameraSweepAPI / CameraSweepUploader (NoteLetter 910864a) and their tests
// (OneBadRowTests, CameraSweepFailureTests, ResponseMappingTests). The
// request itself is driven against the fixtures by api_requests_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/firestore_service.dart' show CaptureMatch;
import 'package:flutter_app/services/sweep_ledger.dart';

import 'fixtures.dart';
import 'sweep_fakes.dart';

void main() {
  // ── The ledger ─────────────────────────────────────────────────────────────

  group('ledger', () {
    test('starts empty: off, Review, 90 days back, no cursor, no verdicts', () async {
      final l = await SweepLedger.load(MemoryLedgerStore(),
          now: () => DateTime(2026, 10, 18, 12, 30));
      expect(l.enabled, isFalse);
      expect(l.mode, SweepMode.review);
      expect(l.backfillStart, DateTime(2026, 7, 20, 12, 30));
      expect(l.cursor, isNull);
      expect(l.backfillComplete, isFalse);
      expect(l.verdicts, isEmpty);
    });

    test('lives in THIS app\'s App Group, the one the entitlements grant', () {
      expect(sweepAppGroup, 'group.xp.NoteLetter.Flutter');
      expect(sweepAppGroup, isNot('group.xp.NoteLetter'),
          reason: 'the Swift app\'s group: ruled start fresh');
      final ent = File('ios/Runner/Runner.entitlements').readAsStringSync();
      expect(ent, contains('<string>$sweepAppGroup</string>'));
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(delegate, contains('"$sweepAppGroup"'));
    });

    test('what it writes it reads back, all four verdicts, in Swift\'s shape', () async {
      final store = MemoryLedgerStore();
      final l = await SweepLedger.load(store);
      await l.record(LedgerVerdict.ingested, 'a');
      await l.record(LedgerVerdict.dismissed, 'b');
      await l.record(const LedgerVerdict.noText(3), 'c');
      await l.record(LedgerVerdict.deferredNotLocal, 'd');
      await l.setEnabled(true);
      await l.setMode(SweepMode.automatic);
      await l.setCursor(DateTime.utc(2026, 10, 1));
      await l.setBackfillComplete(true);
      expect(jsonDecode(store.values[SweepLedger.kVerdicts] as String), {
        'a': {'ingested': {}},
        'b': {'dismissed': {}},
        'c': {
          'noText': {'prefilterVersion': 3}
        },
        'd': {'deferredNotLocal': {}},
      });
      final again = await SweepLedger.load(store);
      expect(again.verdicts, l.verdicts);
      expect(again.enabled, isTrue);
      expect(again.mode, SweepMode.automatic);
      expect(again.cursor!.isAtSameMomentAs(DateTime.utc(2026, 10, 1)), isTrue,
          reason: '${again.cursor}');
      expect(again.backfillComplete, isTrue);
    });

    // Swift OneBadRowTests, on the same bytes.
    const swiftLedger = '{"good-a": {"ingested": {}},'
        ' "good-b": {"noText": {"prefilterVersion": 2}},'
        ' "future": {"needsReview": {"reason": "a case this build does not know"}}}';

    test('one unreadable verdict costs only itself', () {
      final v = SweepLedger.decodeVerdicts(swiftLedger);
      expect(v, {
        'good-a': LedgerVerdict.ingested,
        'good-b': const LedgerVerdict.noText(2),
      });
    });

    test('an empty or unreadable ledger is empty', () {
      expect(SweepLedger.decodeVerdicts(null), isEmpty);
      expect(SweepLedger.decodeVerdicts(''), isEmpty);
      expect(SweepLedger.decodeVerdicts('not json'), isEmpty);
      expect(SweepLedger.decodeVerdicts('[1,2]'), isEmpty);
    });

    test('a verdict is closed: a shape this build does not know is unreadable', () {
      for (final bad in [
        {'ingested': {'x': 1}},
        {'noText': {}},
        {'noText': {'prefilterVersion': '1'}},
        {'ingested': {}, 'dismissed': {}},
        {'ingested': true},
        'ingested',
      ]) {
        expect(() => LedgerVerdict.fromJson(bad), throwsFormatException,
            reason: '$bad');
      }
    });

    test('needs examination unless a verdict still stands', () async {
      final l = await SweepLedger.load(MemoryLedgerStore());
      await l.record(LedgerVerdict.ingested, 'i');
      await l.record(LedgerVerdict.dismissed, 'x');
      await l.record(const LedgerVerdict.noText(1), 'n');
      await l.record(LedgerVerdict.deferredNotLocal, 'd');
      bool needs(String id, int v) => l.needsExamination(id, prefilterVersion: v);
      expect(needs('i', 1), isFalse);
      expect(needs('x', 1), isFalse);
      expect(needs('n', 1), isFalse, reason: 'same pre-filter: it stands');
      expect(needs('n', 2), isTrue, reason: 'a better pre-filter revisits it');
      expect(needs('d', 1), isTrue, reason: 'deferred is always retried');
      expect(needs('new', 1), isTrue);
      expect(l.ingestedCount, 1);
      expect(l.deferredCount, 1);
    });

    test('writes before it moves: a failed write leaves the state as stored', () async {
      final store = FlakyStore();
      final l = await SweepLedger.load(store);
      store.failWrites = true;
      await expectLater(l.record(LedgerVerdict.ingested, 'a'), throwsStateError);
      await expectLater(l.setEnabled(true), throwsStateError);
      await expectLater(l.setCursor(DateTime.utc(2026)), throwsStateError);
      expect(l.verdict('a'), isNull);
      expect(l.enabled, isFalse);
      expect(l.cursor, isNull);
    });

    test('reset forgets verdicts and progress, keeps the setup', () async {
      final l = await SweepLedger.load(MemoryLedgerStore());
      await l.setEnabled(true);
      await l.setMode(SweepMode.automatic);
      await l.record(LedgerVerdict.ingested, 'a');
      await l.setCursor(DateTime.utc(2026));
      await l.setBackfillComplete(true);
      await l.reset();
      expect(l.verdicts, isEmpty);
      expect(l.cursor, isNull);
      expect(l.backfillComplete, isFalse);
      expect(l.enabled, isTrue);
      expect(l.mode, SweepMode.automatic);
    });
  });

  // ── The answer ─────────────────────────────────────────────────────────────

  group('capture session answer (fixtures api/uploads)', () {
    final cases = {
      for (final c in (loadSuite('api/uploads')!['cases'] as List))
        if ((c['request'] as Map)['endpoint'] == 'fn_create_capture_session' &&
            ((c['response'] as Map)['status'] as int) < 300)
          c['id'] as String:
              ((c['response'] as Map)['body'] as Map).cast<String, dynamic>()
    };

    test('every captured 2xx is read', () {
      expect(cases.keys, containsAll(<String>[
        'uploads:capture-session-create',
        'uploads:capture-session-duplicate-resumable',
        'uploads:capture-session-duplicate-settled',
      ]));
      for (final body in cases.values) {
        final s = CaptureSession.fromResponse(body);
        expect(s.docId, body['docId']);
        expect(s.duplicate, body['duplicate']);
        expect(s.uploadUrl, body['uploadUrl']);
      }
    });

    test('create, resumable replay and settled replay', () {
      final create = CaptureSession.fromResponse(cases['uploads:capture-session-create']!);
      expect(create.duplicate, isFalse);
      expect(create.uploadUrl, isNotNull);
      expect(create.existingStatus, isNull);
      final resumable =
          CaptureSession.fromResponse(cases['uploads:capture-session-duplicate-resumable']!);
      expect(resumable.duplicate, isTrue);
      expect(resumable.existingStatus, 'pending_upload');
      expect(resumable.uploadUrl, isNotNull, reason: 'the bytes never landed: re-PUT');
      final settled =
          CaptureSession.fromResponse(cases['uploads:capture-session-duplicate-settled']!);
      expect(settled.duplicate, isTrue);
      expect(settled.uploadUrl, isNull, reason: 'landed: upload nothing');
    });

    test('no `duplicate` is a backend that ignored assetKey: the sweep stops', () {
      final noDedupe = Map<String, dynamic>.of(cases['uploads:capture-session-create']!)
        ..remove('duplicate');
      expect(() => CaptureSession.fromResponse(noDedupe),
          throwsA(isA<DedupeUnsupported>()));
      final noDoc = Map<String, dynamic>.of(cases['uploads:capture-session-create']!)
        ..remove('docId');
      expect(() => CaptureSession.fromResponse(noDoc), throwsA(isA<DedupeUnsupported>()));
    });

    test('a FRESH session without a link is refused, never read as landed', () {
      final noUrl = Map<String, dynamic>.of(cases['uploads:capture-session-create']!)
        ..['uploadUrl'] = null;
      expect(() => CaptureSession.fromResponse(noUrl), throwsFormatException);
      final badUrl = Map<String, dynamic>.of(cases['uploads:capture-session-create']!)
        ..['uploadUrl'] = 42;
      expect(() => CaptureSession.fromResponse(badUrl), throwsFormatException);
    });
  });

  // ── The request's inputs ───────────────────────────────────────────────────

  group('request inputs', () {
    test('capturedAt is UTC whole seconds, floored, as ISO8601DateFormatter printed', () {
      // The Swift formatter's own output for these instants (swiftc, 2026-10-18).
      String at(double s) => Api.captureInstant(
          CameraSweepService.capturedAt(asset('x', seconds: s))!);
      expect(at(1759568400.0), '2025-10-04T09:00:00Z');
      expect(at(1759568400.999), '2025-10-04T09:00:00Z');
      expect(at(1759568400.5), '2025-10-04T09:00:00Z');
      expect(at(-1.5), '1969-12-31T23:59:58Z');
      // Microsecond rounding would cross into :01 here; flooring the Double
      // does not.
      expect(at(1759568400.9999997), '2025-10-04T09:00:00Z');
      expect(Api.captureInstant(DateTime.utc(2026, 7, 14, 9, 30, 15, 999)),
          '2026-07-14T09:30:15Z');
    });

    test('no date: no capturedAt', () {
      final a = SweepAsset(
          localIdentifier: 'x',
          assetKey: 'v1:x',
          creationSeconds: null,
          pixelWidth: 1,
          pixelHeight: 1,
          originalFilename: null,
          isScreenshot: false,
          isRepresentative: true);
      expect(CameraSweepService.capturedAt(a), isNull);
    });

    test('the filename is NSString.deletingPathExtension + ".jpg"', () {
      // Foundation's own answers for these names (swiftc, 2026-10-18).
      const foundation = {
        'IMG_0001.HEIC': 'IMG_0001.jpg',
        'v1:abc.jpg': 'v1:abc.jpg',
        'noext': 'noext.jpg',
        '.hidden': '.hidden.jpg',
        'a.b.c': 'a.b.jpg',
        'trail.': 'trail..jpg',
        'Café crème.jpeg': 'Café crème.jpg',
        'x.tar.gz': 'x.tar.jpg',
        'IMG 1.PNG': 'IMG 1.jpg',
        '..': '...jpg',
        'a/b.c': 'a/b.jpg',
        'a.b/c': 'a.b/c.jpg',
        '': '.jpg',
      };
      foundation.forEach((name, want) {
        expect('${CameraSweepService.deletingPathExtension(name)}.jpg', want,
            reason: name);
      });
      expect(CameraSweepService.uploadFilename(asset('a', name: 'IMG_4821.HEIC')),
          'IMG_4821.jpg');
      final noName = asset('a', name: null);
      expect(CameraSweepService.uploadFilename(noName), '${noName.assetKey}.jpg',
          reason: 'no resource: the key names the file, as in Swift');
    });
  });

  // ── The pass ───────────────────────────────────────────────────────────────

  group('pass', () {
    test('a fresh ledger: candidates wait in the tray and NOTHING is sent', () async {
      final (svc, ledger, bridge, ep, _) = await rig([
        asset('p1', seconds: 1759568400),
        asset('p2', seconds: 1759482000),
        asset('n1', seconds: 1759395600),
        asset('d1', seconds: 1759309200),
      ], verdicts: {
        'n1': SweepVerdict.noText,
        'd1': SweepVerdict.notLocallyAvailable,
      });
      final pass = await svc.sweep();
      expect(svc.candidates.map((a) => a.localIdentifier), ['p1', 'p2']);
      expect(ep.sessions, isEmpty, reason: 'the first backfill goes through review');
      expect(ep.puts, isEmpty);
      expect(ledger.verdict('n1'), const LedgerVerdict.noText(1));
      expect(ledger.verdict('d1'), LedgerVerdict.deferredNotLocal);
      expect(ledger.verdict('p1'), isNull, reason: 'a tray card has no verdict yet');
      expect(ledger.backfillComplete, isTrue, reason: 'ran out before the cap');
      expect(ledger.cursor,
          DateTime.fromMicrosecondsSinceEpoch(1759309200 * 1000000, isUtc: true));
      expect(pass.handled, 4);
      expect((pass.toTray, pass.noText, pass.deferred), (2, 1, 1));
    });

    test('a second pass skips what the ledger settled and sends nothing', () async {
      final (svc, _, bridge, ep, _) = await rig([asset('p1'), asset('n1')],
          verdicts: {'n1': SweepVerdict.noText});
      await svc.sweep();
      bridge.examinedIds.clear();
      final second = await svc.sweep();
      // S3 runs a pass on every library change, so a card already waiting is
      // not put through Vision again (Swift re-examined it every pass). It
      // still counts toward the cap.
      expect(bridge.examinedIds, isEmpty,
          reason: 'a tray card is not examined again');
      expect(second.held, 1);
      expect(second.handled, 1);
      expect(second.settled, 1);
      expect(ep.sessions, isEmpty);
      expect(svc.candidates.length, 1, reason: 'not duplicated in the tray');
    });

    test('approve: one session, then the bare PUT of the rendered bytes', () async {
      final (svc, ledger, bridge, ep, _) =
          await rig([asset('p1', seconds: 1759568400.75, name: 'Scan 7.HEIC')]);
      await svc.sweep();
      await svc.approveAll();
      expect(ep.sessions, hasLength(1));
      final s = ep.sessions.single;
      final a = bridge.assets.single;
      expect(s.assetKey, a.assetKey, reason: 'the bridge\'s key, never re-derived');
      expect(s.filename, 'Scan 7.jpg');
      expect(s.mimeType, 'image/jpeg');
      expect(Api.captureInstant(s.capturedAt!), '2025-10-04T09:00:00Z');
      final (url, bytes, mime) = ep.puts.single;
      expect(url, 'https://storage.example/put/${a.assetKey}');
      expect(mime, 'image/jpeg');
      expect(s.size, bytes.length, reason: 'size is the bytes that are PUT');
      expect(bytes.take(2), [0xFF, 0xD8]);
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
      expect(svc.candidates, isEmpty);
      expect(svc.ingestedThisSession, 1);
      expect(File(bridge.renderedPaths.single).existsSync(), isFalse,
          reason: 'the rendered copy is temporary');
    });

    test('a settled duplicate uploads nothing and is recorded', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      ep.answers[bridge.assets.single.assetKey] = {
        'docId': 'cam-1', 'duplicate': true, 'status': 'complete',
        'gcsPath': 'raw/x', 'uploadUrl': null,
      };
      await svc.sweep();
      await svc.approveAll();
      expect(ep.puts, isEmpty);
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
      expect(svc.ingestedThisSession, 1);
    });

    test('a duplicate whose bytes never landed is uploaded against the replay\'s link', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      ep.answers[bridge.assets.single.assetKey] = {
        'docId': 'cam-1', 'duplicate': true, 'status': 'pending_upload',
        'gcsPath': 'raw/x', 'uploadUrl': 'https://storage.example/again',
      };
      await svc.sweep();
      await svc.approveAll();
      expect(ep.puts.single.$1, 'https://storage.example/again');
      expect(ledger.verdict('p1'), LedgerVerdict.ingested);
    });

    test('no `duplicate`: the sweep STOPS, says so, and the cards stay', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1'), asset('p2')]);
      for (final a in bridge.assets) {
        ep.answers[a.assetKey] = {'docId': 'x', 'uploadUrl': 'https://u'};
      }
      await svc.sweep();
      await svc.approveAll();
      expect(svc.errorStoppedSweep, isTrue);
      expect(svc.failureTitle, 'Sweep stopped');
      expect(svc.errorMessage, DedupeUnsupported.message);
      expect(ep.sessions, hasLength(1), reason: 'approveAll stops with the sweep');
      expect(ep.puts, isEmpty);
      expect(svc.candidates.length, 2);
      expect(svc.candidateErrors['p1'], DedupeUnsupported.message);
      expect(ledger.verdict('p1'), isNull);
    });

    test('one refused photo keeps its card and the server\'s sentence', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1'), asset('p2')]);
      ep.answers[bridge.assets.first.assetKey] = ApiException(
          403, 'You have reached your plan\'s limit.',
          errorCode: 'PLAN_LIMIT', serverSentence: true);
      await svc.sweep();
      await svc.approveAll();
      expect(svc.candidateErrors['p1'], 'You have reached your plan\'s limit.');
      expect(svc.candidates.map((a) => a.localIdentifier), ['p1']);
      expect(ledger.verdict('p2'), LedgerVerdict.ingested, reason: 'one costs one');
      expect(svc.errorStoppedSweep, isFalse);
      // A later attempt that lands leaves nothing behind.
      ep.answers.clear();
      await svc.approve(svc.candidates.single);
      expect(svc.candidateErrors, isEmpty);
      expect(svc.candidates, isEmpty);
    });

    test('a PUT that did not land is not recorded, and says the retry', () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      ep.putFailsWith = 403;
      await svc.sweep();
      await svc.approveAll();
      expect(ledger.verdict('p1'), isNull, reason: 'the next pass re-requests a link');
      expect(svc.candidateErrors['p1'],
          'A photo’s upload link expired before the transfer finished. '
          'The next sweep starts it again.');
      expect(svc.ingestedThisSession, 0, reason: 'only an upload that landed counts');
    });

    test('a fresh session with no link is one refused photo, never "ingested"', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      ep.answers[bridge.assets.single.assetKey] = {
        'docId': 'cam-1', 'duplicate': false, 'uploadUrl': null, 'gcsPath': 'raw/x',
      };
      await svc.sweep();
      await svc.approveAll();
      expect(ledger.verdict('p1'), isNull);
      expect(svc.candidateErrors['p1'], isNotNull);
      expect(svc.errorStoppedSweep, isFalse);
    });

    test('not on the device: deferred, never no-text, and the card says why', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      bridge.notRenderable.add('p1');
      await svc.sweep();
      await svc.approveAll();
      expect(ledger.verdict('p1'), LedgerVerdict.deferredNotLocal);
      expect(svc.candidateErrors['p1'], CameraSweepService.iCloudSentence);
      expect(ep.sessions, isEmpty);
    });

    test('dismissed is permanent and sends nothing', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1')]);
      await svc.sweep();
      await svc.dismiss(svc.candidates.single);
      expect(ledger.verdict('p1'), LedgerVerdict.dismissed);
      bridge.examinedIds.clear();
      await svc.sweep();
      expect(bridge.examinedIds, isEmpty);
      expect(svc.candidates, isEmpty);
      expect(ep.sessions, isEmpty);
    });

    test('automatic, after the first backfill: candidates are filed as found', () async {
      final (svc, ledger, bridge, ep, _) = await rig([asset('p1'), asset('p2')]);
      await ledger.setMode(SweepMode.automatic);
      await ledger.setBackfillComplete(true);
      ep.putFailsWith = 500;
      final pass = await svc.sweep();
      expect(svc.candidates, isEmpty, reason: 'nobody is looking at a tray');
      expect(pass.failed.keys, ['p1', 'p2']);
      expect(svc.failureTitle, 'A photo couldn’t be added',
          reason: 'one photo\'s refusal is not the sweep ending');
      expect(svc.errorMessage,
          'A photo could not be uploaded (HTTP 500). The next sweep tries again.');
      ep.putFailsWith = null;
      final again = await svc.sweep();
      expect(again.ingested, 2);
      expect(ledger.ingestedCount, 2);
    });

    test('automatic still sends the FIRST backfill through review', () async {
      final (svc, ledger, _, ep, _) = await rig([asset('p1')]);
      await ledger.setMode(SweepMode.automatic);
      await svc.sweep();
      expect(svc.candidates.length, 1);
      expect(ep.sessions, isEmpty);
    });

    test('a pass is capped at 200 examined, and the next one continues', () async {
      final assets = [
        for (var i = 0; i < 250; i++) asset('a$i', seconds: 1759568400.0 - i * 60)
      ];
      final (svc, ledger, bridge, _, _) = await rig(assets,
          verdicts: {for (final a in assets) a.localIdentifier: SweepVerdict.noText});
      final first = await svc.sweep();
      expect(first.handled, CameraSweepService.backfillBatchLimit);
      expect(ledger.backfillComplete, isFalse, reason: 'something older is waiting');
      expect(ledger.cursor, assets[199].creationDate);
      final second = await svc.sweep();
      expect(second.handled, 50);
      expect(second.settled, 200);
      expect(ledger.backfillComplete, isTrue);
      expect(bridge.examinedIds.toSet().length, 250);
    });

    test('a burst contributes only its representative frame', () async {
      final (svc, _, bridge, _, _) =
          await rig([asset('b1', representative: false), asset('b2')]);
      final pass = await svc.sweep();
      expect(bridge.examinedIds, ['b2']);
      expect(pass.nonRepresentative, 1);
    });

    test('partial or no access: refused with the Swift sentence, nothing written', () async {
      for (final access in [SweepAccess.limited, SweepAccess.denied]) {
        final (svc, ledger, bridge, ep, store) = await rig([asset('p1')]);
        bridge.accessNow = access;
        final before = snapshot(store);
        final pass = await svc.sweep();
        expect(pass.refused?.access, access);
        expect(svc.accessRefused?.sentence,
            access == SweepAccess.limited
                ? SweepAccessRefused.limitedSentence
                : SweepAccessRefused.deniedSentence);
        expect(snapshot(store), before);
        expect(ep.sessions, isEmpty);
        expect(await svc.startIfEnabled(), isNull);
        expect(ledger.backfillComplete, isFalse);
      }
    });

    test('startIfEnabled does nothing until the user turned the sweep on', () async {
      final (svc, ledger, bridge, _, _) = await rig([asset('p1')]);
      expect(await svc.startIfEnabled(), isNull);
      expect(bridge.examinedIds, isEmpty);
      await ledger.setEnabled(true);
      expect(await svc.startIfEnabled(), isNotNull);
      expect(bridge.examinedIds, ['p1']);
    });

    test('a second call while a pass runs gets the running pass', () async {
      final (svc, _, bridge, _, _) = await rig([asset('p1')]);
      final a = svc.sweep();
      final b = svc.sweep();
      expect(identical(a, b), isTrue);
      await a;
      expect(bridge.examinedIds, ['p1']);
    });

    test('the alert clears, and a stale "stopped" cannot retitle the next one', () async {
      final (svc, _, _, _, _) = await rig([]);
      svc.presentFailure('x', stopsSweep: true);
      svc.clearError();
      expect(svc.errorMessage, isNull);
      expect(svc.errorStoppedSweep, isFalse);
      svc.presentFailure('y', stopsSweep: false);
      expect(svc.failureTitle, 'A photo couldn’t be added');
    });
  });

  // ── The dry run ────────────────────────────────────────────────────────────

  group('dry run', () {
    test('writes nothing, sends nothing, and says what a pass would do', () async {
      final (svc, ledger, bridge, ep, store) = await rig([
        asset('new'),
        asset('filed'),
        asset('stranded'),
        asset('n1'),
        asset('d1'),
        asset('settled'),
      ], verdicts: {
        'n1': SweepVerdict.noText,
        'd1': SweepVerdict.notLocallyAvailable,
      });
      await ledger.record(LedgerVerdict.ingested, 'settled');
      final key = {for (final a in bridge.assets) a.localIdentifier: a.assetKey};
      ep.filed[key['filed']!] = const CaptureMatch(docId: 'cam-f', status: 'complete');
      ep.filed[key['stranded']!] =
          const CaptureMatch(docId: 'cam-s', status: 'pending_upload');
      final before = snapshot(store);

      final run = await svc.dryRun();

      expect(snapshot(store), before, reason: 'no verdict, cursor or flag written');
      expect(ep.sessions, isEmpty, reason: 'no session: that call FILES the photo');
      expect(ep.puts, isEmpty);
      expect(svc.candidates, isEmpty, reason: 'the tray is untouched');
      expect(ledger.backfillComplete, isFalse);
      final outcome = {for (final e in run.entries) e.asset.localIdentifier: e.outcome};
      expect(outcome, {
        'new': DryRunOutcome.wouldHoldForReview,
        'filed': DryRunOutcome.duplicateSettled,
        'stranded': DryRunOutcome.duplicateWouldUpload,
        'n1': DryRunOutcome.wouldRecordNoText,
        'd1': DryRunOutcome.wouldDefer,
      });
      expect(run.settled, 1, reason: 'the ledger is read, never written');
      expect(ep.finds, [key['new'], key['filed'], key['stranded']],
          reason: 'only candidates are looked up, by their asset key');
      final filed = run.entries.firstWhere((e) => e.asset.localIdentifier == 'filed');
      expect(filed.match?.docId, 'cam-f');
      expect(filed.renderedBytes, greaterThan(2));
      for (final p in bridge.renderedPaths) {
        expect(File(p).existsSync(), isFalse, reason: 'rendered, then deleted');
      }
    });

    test('automatic after the backfill: a new candidate would be filed', () async {
      final (svc, ledger, _, _, _) = await rig([asset('new')]);
      await ledger.setMode(SweepMode.automatic);
      await ledger.setBackfillComplete(true);
      final run = await svc.dryRun();
      expect(run.entries.single.outcome, DryRunOutcome.wouldCreate);
    });

    test('a read that fails is UNKNOWN, never "would create"', () async {
      final (svc, _, _, ep, _) = await rig([asset('p1')]);
      ep.findThrows = StateError('permission-denied');
      final run = await svc.dryRun();
      expect(run.entries.single.outcome, DryRunOutcome.unknown);
      expect(run.entries.single.error, contains('permission-denied'));
    });

    test('refused access is reported, not walked', () async {
      final (svc, _, bridge, _, _) = await rig([asset('p1')]);
      bridge.accessNow = SweepAccess.limited;
      final run = await svc.dryRun();
      expect(run.refused, same(SweepAccessRefused.limited));
      expect(run.entries, isEmpty);
    });
  });

  // ── Sentences ──────────────────────────────────────────────────────────────

  group('sentences (the Swift app\'s, verbatim)', () {
    test('upload failures each name the retry', () {
      expect(
          CameraSweepService.uploadFailureSentence(
              transportError: 'The network connection was lost.', statusCode: 0),
          'A photo could not be uploaded — The network connection was lost. '
          'The next sweep tries again.');
      final expired = CameraSweepService.uploadFailureSentence(statusCode: 403);
      expect(expired, contains('expired'));
      expect(expired, isNot(contains('403')),
          reason: 'a status code is not a sentence for the reader (ADR-112)');
      expect(CameraSweepService.uploadFailureSentence(statusCode: 500), contains('500'));
    });

    test('the iCloud and dedupe sentences', () {
      expect(CameraSweepService.iCloudSentence,
          'This photo hasn’t finished downloading from iCloud. '
          'It stays here and the next sweep will try again.');
      expect(DedupeUnsupported.message,
          "This version of NoteLetter's server doesn't recognize camera-roll "
          'photos yet, so sweeping would add the same photos again. Try again '
          'after the next update.');
    });
  });
}
