// F-146 (5.43.0, ADR-198): the camera roll in direction D, driven by taps on
// the simulator's real photo library against the EMULATOR suite. Run through
// tool/sweep_tray_test.sh, which adds the photos (simctl addmedia), sets full
// photo access, passes the emulator defines (the app refuses prod) and adds
// one more photo WHILE the test runs, when it prints SWEEP:ADD-PHOTO.
// (Until 5.43.0 this drove F-125 S3's Settings → Camera roll and Sources'
// tray, both retired; the file keeps its name so F-125's record still points
// at it.)
//
// What this proves that Tier 1 cannot:
//   - the Library's camera roll row opens the four-step setup, and its
//     *Allow access* reaches the real bridge (full access, set by the script);
//   - step 3's counts are the real library's, per reach;
//   - *Start looking back* writes on, the mode and the reach, and the look
//     back walks the real library: Looking back counts the walk's position
//     over the photos in range, and Just found lists what it kept, while
//     NOTHING is sent;
//   - the one-at-a-time review: "k of N", the summary line, a photo another
//     install already filed says "Already in NoteLetter" and *File it* files
//     nothing new and uploads nothing; *Pass over* records it and sends
//     nothing; *File it* on a fresh photo opens a real capture session and
//     hands its upload to the background session — since 2026-10-20 the dev
//     shim's `/__storage/` route takes the PUT, so it LANDS and the photo
//     leaves the review (a refusal, should one come, stays with its sentence);
//   - "Everything Is Filed" once the tray is empty, with the ledger's counts;
//   - a photo added while the app is open reaches the row (Ask me first) through
//     the native change observer, with nothing tapped;
//   - *Camera roll settings* in the panel, and *Turn off the camera roll*
//     behind "Turn off the camera roll?".

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/app.dart';
import 'package:flutter_app/app_providers.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/pages/sources/camera_roll.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _captures(String uid) async =>
    (await FirebaseFirestore.instance
            .collection('documents')
            .where('user_id', isEqualTo: uid)
            .where('source_capture.source', isEqualTo: 'camera_roll')
            .get())
        .docs;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Umbrella law 1. A filing here OPENS A SESSION, which writes a document.
    if (!ApiService.useEmulator) {
      fail('Refusing to run: pass --dart-define=USE_EMULATOR=true (umbrella law 1).');
    }
    FirebaseFirestore.instance
        .useFirestoreEmulator(ApiService.emulatorHost, ApiService.firestorePort);
    await FirebaseAuth.instance.useAuthEmulator(ApiService.emulatorHost, ApiService.authPort);
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
  });

  Future<void> pumpFor(WidgetTester tester, [int ms = 1000]) async {
    for (var i = 0; i < ms ~/ 250; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> waitFor(WidgetTester tester, String what, bool Function() done,
      {int seconds = 90, String Function()? state}) async {
    for (var i = 0; i < seconds * 4; i++) {
      if (done()) return;
      if (state != null && i % 40 == 39) debugPrint('sweep tray: waiting for $what — ${state()}');
      await tester.pump(const Duration(milliseconds: 250));
    }
    fail('timed out waiting for $what${state == null ? '' : ' — ${state()}'}');
  }

  Future<GoRouter> pumpApp(WidgetTester tester) async {
    final auth = AuthNotifier();
    final router = createRouter(auth);
    await tester.pumpWidget(MultiProvider(
      providers: appProviders(auth),
      child: NoteLetterApp(router: router),
    ));
    await pumpFor(tester, 3000);
    return router;
  }

  CameraSweepHost hostOf(WidgetTester tester) =>
      Provider.of<CameraSweepHost>(tester.element(find.byType(NoteLetterApp)),
          listen: false);

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f.last);
    await pumpFor(tester, 500);
    await tester.tap(f.last);
    await pumpFor(tester, 750);
  }

  Finder onRow(String text) => find.descendant(
      of: find.byKey(const ValueKey('camera-roll-row')), matching: find.text(text));

  testWidgets(
      'the camera roll in D: the four-step setup, Looking back, the one-at-a-time '
      'review, Everything Is Filed, and the panel', (tester) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final bridge = CameraSweepBridge();
    expect(await bridge.access(), SweepAccess.granted,
        reason: 'tool/sweep_tray_test.sh sets full access first');
    final store = AppGroupLedgerStore();
    try {
      // ── 0. The device's ledger: empty and OFF ──────────────────────────────
      for (final k in SweepLedger.keys) {
        await store.write(k, null);
      }
      final router = await pumpApp(tester);
      final host = hostOf(tester);
      await host.ready;
      expect(host.ledger!.enabled, isFalse);

      // The look back the test will choose: The last year. The test photos
      // are dated 2026-10 (tool/sweep_test_photos.py); the simulator's own
      // samples are years older. Which photos the text check keeps, by key —
      // every copy (one per earlier run) is its own asset under ONE key.
      final since = (await host.startFor(SweepReach.year))!;
      final page = await bridge.fetchImages(since: since);
      final byKey = <String, List<String>>{};
      final nameOf = <String, String?>{};
      for (final a in page.assets.where((a) => a.isRepresentative)) {
        final e = await bridge.examine(a.localIdentifier);
        if (e.verdict != SweepVerdict.candidate) continue;
        final id = await bridge.identify(a.localIdentifier);
        byKey.putIfAbsent(id.assetKey, () => []).add(a.localIdentifier);
        nameOf[id.assetKey] = id.originalFilename;
      }
      final candidates = byKey.values.fold<int>(0, (n, l) => n + l.length);
      debugPrint('sweep tray: ${page.total} photos in the last year, $candidates '
          'candidates under ${byKey.length} keys: '
          '${byKey.entries.map((e) => '${nameOf[e.key]}×${e.value.length}').join(', ')}');
      final denseKey = byKey.keys.firstWhere((k) => nameOf[k] == 'sweep-dense.jpg');
      final cafeKey = byKey.keys.firstWhere((k) => nameOf[k]!.startsWith('Caf'));

      // ── 1. One key already in NoteLetter, its bytes landed ─────────────────
      final opened = await Api.instance.createCaptureSession(
        assetKey: denseKey,
        filename: 'sweep-dense.jpg',
        mimeType: 'image/jpeg',
        size: 1000,
        capturedAt: DateTime.utc(2026, 10, 3, 9),
      );
      final denseDoc = opened['docId'] as String;
      final rest = Dio(BaseOptions(
        baseUrl: 'http://${ApiService.emulatorHost}:${ApiService.firestorePort}'
            '/v1/projects/${DefaultFirebaseOptions.currentPlatform.projectId}'
            '/databases/(default)/documents',
        headers: {'Authorization': 'Bearer owner'},
      ));
      await rest.patch('/documents/$denseDoc',
          queryParameters: {'updateMask.fieldPaths': 'status'},
          data: {
            'fields': {'status': {'stringValue': 'complete'}},
          });
      final filedBefore = await _captures(uid);
      // An earlier device test in this emulator session (sweep_service_test)
      // may already have filed the Café key: then its filing is a replay.
      final cafeHadDoc = filedBefore.any((d) =>
          (d.data()['source_capture'] as Map?)?['asset_key'] == cafeKey);

      // ── 2. The row, then the four steps ────────────────────────────────────
      router.go('/sources');
      await pumpFor(tester, 2500);
      expect(onRow(CameraRollCopy.rowOff), findsOneWidget);
      await tap(tester, onRow('Connect'));
      expect(find.text('CAMERA ROLL · 1 OF 4'), findsOneWidget);
      expect(find.text(CameraRollCopy.introTitle), findsOneWidget);
      await tap(tester, find.text(CameraRollCopy.continueLabel));
      expect(find.text('CAMERA ROLL · 2 OF 4'), findsOneWidget);
      await tap(tester, find.text(CameraRollCopy.allowAccess));
      await waitFor(tester, 'step 3', () => find.text('CAMERA ROLL · 3 OF 4').evaluate().isNotEmpty);
      expect(host.ledger!.enabled, isFalse, reason: 'access is not on');
      await waitFor(tester, 'the counts',
          () => find.text(CameraRollCopy.photos(page.total)).evaluate().isNotEmpty,
          seconds: 30);
      debugPrint('DEVICE-RUN F-146 step 3: The last year · ${CameraRollCopy.photos(page.total)}');
      await tap(tester, find.text(CameraRollCopy.continueLabel));
      expect(find.text('CAMERA ROLL · 4 OF 4'), findsOneWidget);
      expect(find.text(CameraRollCopy.askNote), findsOneWidget);
      expect(find.text(CameraRollCopy.lookBackNote), findsOneWidget);
      await tap(tester, find.text(CameraRollCopy.startLooking));

      // ── 3. Looking back: the walk counted, nothing sent ────────────────────
      final svc = host.service!;
      await waitFor(tester, 'Looking back', () =>
          find.text('CAMERA ROLL · LOOKING BACK').evaluate().isNotEmpty);
      expect(host.ledger!.enabled, isTrue);
      expect(host.ledger!.reach, SweepReach.year);
      expect(host.ledger!.mode, SweepMode.review);
      expect(find.text('Looking Through the Last Year'), findsOneWidget);
      await waitFor(tester, 'the look back',
          () => !svc.isSweeping && svc.candidates.length == candidates,
          seconds: 300,
          state: () => 'sweeping ${svc.isSweeping}, at ${svc.walkPosition} of '
              '${svc.walkTotal}, tray ${svc.candidates.length} of $candidates, '
              'error ${svc.errorMessage}');
      await pumpFor(tester, 1500);
      debugPrint('DEVICE-RUN F-146 looked back: ${svc.walkPosition} of ${svc.walkTotal} '
          'photos, ${svc.candidates.length} for your review, '
          '${host.ledger!.passedOverCount} passed over');
      expect(svc.walkPosition, page.total);
      expect(find.text(CameraRollCopy.ofPhotos(page.total)), findsOneWidget);
      expect(find.text(CameraRollCopy.forReview), findsOneWidget);
      expect(find.text(CameraRollCopy.justFound.toUpperCase()), findsOneWidget);
      expect((await _captures(uid)).length, filedBefore.length,
          reason: 'a look back sends nothing before review');
      await tap(tester, find.text(CameraRollCopy.reviewNow(candidates)));

      // ── 4. The review, one photo at a time ─────────────────────────────────
      expect(find.text('CAMERA ROLL · REVIEW · 1 OF $candidates'), findsOneWidget);
      expect(
          find.text(CameraRollCopy.summary(0, candidates, host.ledger!.passedOverCount)),
          findsOneWidget);
      // Already in: the dense key's copies, and anything an earlier batch in
      // this emulator session filed.
      final alreadyIds = {
        for (final a in svc.candidates)
          if (svc.alreadyIn(a.localIdentifier)) a.localIdentifier
      };
      expect(alreadyIds, containsAll(byKey[denseKey]!));
      var filedFresh = false, filedIn = 0;
      for (var i = 0; svc.candidates.isNotEmpty; i++) {
        if (i > candidates + 5) fail('the review did not empty');
        final a = svc.candidates.first;
        final id = a.localIdentifier;
        final already = svc.alreadyIn(id);
        expect(find.text(CameraRollCopy.reviewHead(i + 1, candidates).toUpperCase()), findsOneWidget,
            reason: 'k of N');
        if (already) {
          expect(find.text(CameraRollCopy.alreadyIn), findsOneWidget);
          await tap(tester, find.text(CameraRollCopy.fileIt));
          await waitFor(tester, 'filing $id', () => !svc.candidates.contains(a));
          expect(host.ledger!.verdict(id), LedgerVerdict.ingested);
          filedIn++;
        } else if (!filedFresh && byKey[cafeKey]!.contains(id)) {
          await tap(tester, find.text(CameraRollCopy.fileIt));
          await waitFor(
              tester,
              'the filing to land or be refused',
              () => !svc.candidates.contains(a) || svc.candidateErrors.containsKey(id),
              seconds: 120);
          await pumpFor(tester, 1000);
          final sentence = svc.candidateErrors[id];
          if (sentence == null) {
            debugPrint('DEVICE-RUN F-146 a fresh photo filed: its upload LANDED '
                '(${nameOf[cafeKey]}), verdict ${host.ledger!.verdict(id)}');
            expect(host.ledger!.verdict(id), LedgerVerdict.ingested);
          } else {
            debugPrint('DEVICE-RUN F-146 refusal "$sentence"');
            expect(find.text(sentence), findsOneWidget);
            expect(svc.candidates.first, a, reason: 'a refused photo stays');
            expect(host.ledger!.verdict(id), LedgerVerdict.waiting);
            await tap(tester, find.text(CameraRollCopy.passOver));
            await waitFor(tester, 'passing over $id', () => !svc.candidates.contains(a));
            expect(host.ledger!.verdict(id), LedgerVerdict.dismissed);
          }
          filedFresh = true;
        } else {
          await tap(tester, find.text(CameraRollCopy.passOver));
          await waitFor(tester, 'passing over $id', () => !svc.candidates.contains(a));
          expect(host.ledger!.verdict(id), LedgerVerdict.dismissed);
        }
      }
      expect(filedFresh, isTrue);
      expect(filedIn, alreadyIds.length);
      final after = await _captures(uid);
      expect(after.length, filedBefore.length + (cafeHadDoc ? 0 : 1),
          reason: 'one document per key (INV-14): the Café key\'s, if it had '
              'none; the dense key files nothing new');
      expect(after.firstWhere((d) => d.id == denseDoc).data()['status'], 'complete',
          reason: 'untouched: the session answered duplicate with no upload link');

      // ── 5. Everything Is Filed ─────────────────────────────────────────────
      await pumpFor(tester, 1000);
      expect(find.text(CameraRollCopy.endTitle), findsOneWidget);
      final endLine =
          '${CameraRollCopy.endCounts(host.ledger!.ingestedCount, host.ledger!.passedOverCount)} '
          '${CameraRollCopy.endAsk}';
      expect(find.text(endLine), findsOneWidget);
      debugPrint('DEVICE-RUN F-146 end: "$endLine"');
      await tap(tester, find.text(CameraRollCopy.done));
      await pumpFor(tester, 1000);
      expect(find.byType(CameraRollFlow), findsNothing);
      expect(onRow(CameraRollCopy.rowOn(host.ledger!.ingestedCount)), findsOneWidget);

      // ── 6. A photo taken while the app is open: the row says it waits ──────
      debugPrint('SWEEP:ADD-PHOTO');
      await waitFor(tester, 'the change observer', () => svc.candidates.length == 1,
          seconds: 120);
      await pumpFor(tester, 1000);
      expect(svc.candidates.single.originalFilename, 'sweep-live.jpg');
      expect(onRow(CameraRollCopy.rowWaiting(1)), findsOneWidget);
      await tap(tester, onRow('Review'));
      expect(find.text(CameraRollCopy.youAsked), findsOneWidget,
          reason: 'Ask me first held it; the walk was done');
      await tap(tester, find.text(CameraRollCopy.passOver));
      await waitFor(tester, 'the end', () => svc.candidates.isEmpty);
      await pumpFor(tester, 750);
      await tap(tester, find.text(CameraRollCopy.done));

      // ── 7. The panel, and turning it off ───────────────────────────────────
      await tap(tester, onRow('Settings'));
      expect(find.text(CameraRollCopy.panelTitle), findsOneWidget);
      expect(find.textContaining('On · looked '), findsOneWidget);
      expect(find.text('The last year · done'), findsOneWidget);
      expect(find.text(CameraRollCopy.lookFurther), findsOneWidget);
      await tap(tester, find.text(CameraRollCopy.turnOff));
      expect(find.text(CameraRollCopy.turnOffTitle), findsOneWidget);
      await tap(tester, find.text(CameraRollCopy.turnOffConfirm));
      await waitFor(tester, 'off', () => !host.ledger!.enabled);
      await pumpFor(tester, 1000);
      expect(host.watching, isFalse);
      expect(onRow(CameraRollCopy.rowOff), findsOneWidget);
      expect(host.ledger!.reach, SweepReach.year, reason: 'kept');
      debugPrint('DEVICE-RUN F-146 turned off; the row reads "${CameraRollCopy.rowOff}"');
    } finally {
      // OFF and empty, so no later run (the device run, a hold) starts a pass.
      for (final k in SweepLedger.keys) {
        await store.write(k, null);
      }
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, 500);
    }
  }, timeout: const Timeout(Duration(minutes: 15)));
}
