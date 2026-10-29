// F-125 S3: the camera-roll sweep's SCREENS, driven by taps on the simulator's
// real photo library against the EMULATOR suite. Run through
// tool/sweep_tray_test.sh, which adds the photos (simctl addmedia), sets full
// photo access, passes the emulator defines (the app refuses prod) and adds
// one more photo WHILE the test runs, when it prints SWEEP:ADD-PHOTO.
//
// What this proves that Tier 1 cannot:
//   - the switch on Settings → Camera roll turns the sweep on through the real
//     bridge, and a pass fills the Sources tray from the real library;
//   - a photo another install already filed (its document complete — what a
//     photo the Swift app swept looks like) says "Already in NoteLetter" on
//     its card BEFORE anything is approved, and Add on it files nothing and
//     uploads nothing;
//   - Skip records it dismissed and sends nothing;
//   - Add on a fresh photo opens a real capture session, and the PUT's refusal
//     (the dev shim's URL takes no PUT: 501) stays on its card;
//   - a photo added while the app is open reaches the tray through the native
//     change observer, with nothing tapped;
//   - a fresh app tree with the sweep on fills the tray at LAUNCH, with
//     nothing tapped.

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
import 'package:flutter_app/pages/settings/camera_sweep_page.dart';
import 'package:flutter_app/router.dart';
import 'package:flutter_app/services/api.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/state/auth_notifier.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';

/// The test photos are dated 2026-10-01..05 (tool/sweep_test_photos.py), the
/// frames' pages 10-10..12, and the simulator's samples years older. So from
/// this start the window holds the device test's photos and, once a frame
/// batch has run, its pages.
final _since = DateTime.utc(2026, 9, 1);

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
    // Umbrella law 1. An Add here OPENS A SESSION, which writes a document.
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

  Finder onCard(String id, String tooltip) => find.descendant(
      of: find.byKey(ValueKey(id)), matching: find.byTooltip(tooltip));

  Future<void> tapOnCard(WidgetTester tester, String id, String tooltip) async {
    final f = onCard(id, tooltip);
    await tester.ensureVisible(f);
    await pumpFor(tester, 500);
    await tester.tap(f);
  }

  testWidgets(
      'the tray, driven: on, already in, skip, add, a refusal, a new photo, launch',
      (tester) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final bridge = CameraSweepBridge();
    expect(await bridge.access(), SweepAccess.granted,
        reason: 'tool/sweep_tray_test.sh sets full access first');
    final store = AppGroupLedgerStore();
    try {
      // ── 0. The device's ledger: empty, OFF, the window on the test photos ──
      for (final k in SweepLedger.keys) {
        await store.write(k, null);
      }
      await store.write(SweepLedger.kBackfillStart, _since.millisecondsSinceEpoch);

      // Which photos the text check keeps, by key. Every copy of a photo
      // (one per run of this test or the S1/S2 ones) is its own asset under
      // ONE key.
      // The window the host walks: from the stored start to NOW. (Until
      // 2026-10-18 this counted to 10-09 only, to leave out the frames'
      // pages — but the walk has no end date, so once a frame batch had added
      // its pages (10-10..12) the tray held 3 more cards than were counted.)
      final page = await bridge.fetchImages(since: _since);
      final byKey = <String, List<String>>{};
      final nameOf = <String, String?>{};
      for (final a in page.assets.where((a) => a.isRepresentative)) {
        final e = await bridge.examine(a.localIdentifier);
        if (e.verdict != SweepVerdict.candidate) continue;
        final id = await bridge.identify(a.localIdentifier);
        byKey.putIfAbsent(id.assetKey, () => []).add(a.localIdentifier);
        nameOf[id.assetKey] = id.originalFilename;
      }
      debugPrint('sweep tray: ${byKey.length} candidate keys, '
          '${byKey.values.fold<int>(0, (n, l) => n + l.length)} candidate photos: '
          '${byKey.entries.map((e) => '${nameOf[e.key]}×${e.value.length}').join(', ')}');
      final denseKey = byKey.keys.firstWhere((k) => nameOf[k] == 'sweep-dense.jpg');
      final cafeKey = byKey.keys.firstWhere((k) => nameOf[k]!.startsWith('Caf'));
      final candidates = byKey.values.fold<int>(0, (n, l) => n + l.length);

      // ── 1. One key already in NoteLetter, its bytes landed ─────────────────
      // What a photo the retired Swift app swept looks like on prod: a
      // document under the key, `complete`. The session files it; the
      // emulator's REST (owner bearer) completes it, as the pipeline would.
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
      debugPrint('sweep tray: ${filedBefore.length} capture document(s) before; '
          '$denseDoc complete');

      // ── 2. Settings → Camera roll: the switch ──────────────────────────────
      var router = await pumpApp(tester);
      var host = hostOf(tester);
      await host.ready;
      expect(host.ledger!.enabled, isFalse);
      expect(host.watching, isFalse, reason: 'off: nothing watches the library');
      router.go('/settings/camera-roll');
      await pumpFor(tester, 1500);
      expect(find.text(CameraSweepPage.switchTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.modeTitle), findsNothing);
      await tester.tap(find.byType(KitSwitch));
      await waitFor(tester, 'the switch', () => host.ledger!.enabled);
      await pumpFor(tester, 1000);
      expect(find.text(CameraSweepPage.modeTitle), findsOneWidget);
      expect(find.text(CameraSweepPage.goBackTitle), findsOneWidget);
      expect(host.watching, isTrue, reason: 'the change observer is listened to');

      // ── 3. Sources: the tray, and what is already in ───────────────────────
      router.go('/sources');
      final svc = host.service!;
      // Every run adds another copy of each test photo to the simulator's
      // library, so the first pass grows with it (about 47 photos through
      // Vision, and a read per candidate, by 2026-10-18).
      await waitFor(tester, 'the pass',
          () => !svc.isSweeping && svc.candidates.length == candidates,
          seconds: 300,
          state: () => 'sweeping ${svc.isSweeping}, examined ${svc.examined}, '
              'tray ${svc.candidates.length} of $candidates, halted ${svc.halted}, '
              'error ${svc.errorMessage}');
      await pumpFor(tester, 1500);
      expect(find.text('FROM YOUR CAMERA ROLL · $candidates'), findsOneWidget);
      expect(find.byType(KitCaptureCard), findsNWidgets(candidates));
      for (final id in byKey[denseKey]!) {
        expect(svc.alreadyIn(id), isTrue, reason: '$id carries the filed key');
      }
      for (final id in byKey[cafeKey]!) {
        expect(svc.alreadyIn(id), isFalse);
      }
      expect(find.text(KitCaptureCard.alreadyInLabel),
          findsNWidgets(byKey[denseKey]!.length));
      expect((await _captures(uid)).length, filedBefore.length,
          reason: 'nothing is sent before approval');

      // ── 4. Skip a fresh one ────────────────────────────────────────────────
      final skipped = byKey[cafeKey]!.first;
      await tapOnCard(tester, skipped, 'Skip this photo');
      await waitFor(tester, 'the skip', () => svc.candidates.length == candidates - 1);
      expect(host.ledger!.verdict(skipped), LedgerVerdict.dismissed);
      expect((await _captures(uid)).length, filedBefore.length);

      // ── 5. Add one that is already in: nothing filed, nothing uploaded ─────
      final already = byKey[denseKey]!.first;
      await tapOnCard(tester, already, 'Add this photo');
      await waitFor(tester, 'the add', () => svc.candidates.length == candidates - 2);
      expect(host.ledger!.verdict(already), LedgerVerdict.ingested);
      final afterAlready = await _captures(uid);
      expect(afterAlready.length, filedBefore.length, reason: 'no second document');
      expect(afterAlready.firstWhere((d) => d.id == denseDoc).data()['status'], 'complete',
          reason: 'untouched: the session answered duplicate with no upload link');

      // ── 6. Add a fresh one: a real session; the PUT's refusal stays ────────
      final refused = byKey[cafeKey]![1];
      await tapOnCard(tester, refused, 'Add this photo');
      await waitFor(tester, 'the refusal', () => svc.candidateErrors.containsKey(refused));
      await pumpFor(tester, 1000);
      debugPrint('sweep tray: refusal "${svc.candidateErrors[refused]}"');
      expect(svc.candidateErrors[refused], startsWith('A photo could not be uploaded'));
      expect(find.text(svc.candidateErrors[refused]!), findsOneWidget);
      expect(svc.candidates.any((a) => a.localIdentifier == refused), isTrue,
          reason: 'the card stays, with its reason');
      expect(host.ledger!.verdict(refused), isNull, reason: 'nothing recorded');
      expect((await _captures(uid)).length, filedBefore.length + 1,
          reason: 'one document for the Café key, its bytes never landed');

      // ── 7. A photo taken while the app is open ─────────────────────────────
      final before = svc.candidates.length;
      final seen = {for (final a in svc.candidates) a.localIdentifier};
      debugPrint('SWEEP:ADD-PHOTO');
      await waitFor(tester, 'the change observer', () => svc.candidates.length == before + 1,
          seconds: 120);
      final live = svc.candidates.firstWhere((a) => !seen.contains(a.localIdentifier));
      debugPrint('sweep tray: the change observer brought ${live.originalFilename}');
      expect(live.originalFilename, 'sweep-live.jpg');

      // ── 8. Launch: a fresh app with the sweep on fills the tray itself ─────
      final waiting = svc.candidates.length;
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, 500);
      router = await pumpApp(tester);
      host = hostOf(tester);
      await host.ready;
      expect(host.ledger!.enabled, isTrue);
      router.go('/sources');
      final svc2 = host.service!;
      await waitFor(tester, 'the launch pass',
          () => !svc2.isSweeping && svc2.candidates.length == waiting);
      await pumpFor(tester, 1000);
      expect(svc2.candidates.any((a) => a.localIdentifier == skipped), isFalse,
          reason: 'dismissed is permanent');
      expect(svc2.candidates.any((a) => a.localIdentifier == already), isFalse,
          reason: 'ingested is settled');
      expect(svc2.candidates.any((a) => a.localIdentifier == refused), isTrue,
          reason: 'a refused add is offered again');
      expect(host.watching, isTrue);
      expect(find.text('FROM YOUR CAMERA ROLL · $waiting'), findsOneWidget);
    } finally {
      // OFF and empty, so no later run (the device run, a hold) starts a pass.
      for (final k in SweepLedger.keys) {
        await store.write(k, null);
      }
      await tester.pumpWidget(const SizedBox());
      await pumpFor(tester, 500);
    }
  }, timeout: const Timeout(Duration(minutes: 12)));
}
