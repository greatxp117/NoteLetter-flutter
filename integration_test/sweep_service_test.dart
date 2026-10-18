// F-125 S2: the camera-roll sweep's ledger and service on a real photo
// library (the simulator's) against the EMULATOR suite. Run through
// tool/sweep_service_test.sh, which adds the photos, grants full access and
// passes the emulator defines; the app refuses to run without them.
//
// What this proves that Tier 1 cannot:
//   - the ledger persists in THIS app's App Group, on a device, across a
//     fresh SweepLedger read back from the store;
//   - a full sweep FILES captures through the real builder and the real
//     backend (the dev shim), one document per asset key (INV-14), and its
//     bytes land;
//   - a second sweep files NOTHING, because the ledger skips every settled
//     photo before it touches a pixel;
//   - the dry run writes NOTHING (ledger, tray, endpoint, Firestore) and finds
//     an already-filed photo as a duplicate by its asset key, which is the
//     real-phone check for photos the Swift app swept.
//
// NOT proven here: a PUT to a REAL signed URL. The shim's "signed" URL is the
// storage emulator's download URL, which takes no PUT, so the session's link
// is swapped for a resumable upload the emulator opens for the same object
// (sweep_emulator_upload.dart); since S4 the app's own background uploader
// sends the bytes there. The storage trigger does not run either (no
// functions emulator), so a filed document stays `pending_upload`.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/services/sweep_uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sweep_emulator_upload.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';

/// Every test photo (tool/sweep_test_photos.py) is dated 2026-10-01..04; the
/// simulator's own sample photos are years older. So the window holds only
/// ours, however many copies earlier runs added.
final _since = DateTime.utc(2026, 9, 1);

/// The backend's deterministic id (spec/api/uploads.md; INV-14).
String _camId(String uid, String key) =>
    'cam-${sha256.convert(utf8.encode('$uid|camera_roll|$key')).toString().substring(0, 32)}';

Future<Map<String, Object?>> _ledgerState(SweepLedgerStore store) =>
    store.read(SweepLedger.keys);

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
    // Umbrella law 1: never against prod. A capture session WRITES a
    // document, so this refuses before anything is sent.
    if (!ApiService.useEmulator) {
      fail('Refusing to run: pass --dart-define=USE_EMULATOR=true (umbrella law 1).');
    }
    FirebaseFirestore.instance
        .useFirestoreEmulator(ApiService.emulatorHost, ApiService.firestorePort);
    await FirebaseAuth.instance.useAuthEmulator(ApiService.emulatorHost, ApiService.authPort);
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
  });

  test('sweep, sweep again, dry run: the ledger works and the dry run writes nothing',
      () async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final bridge = CameraSweepBridge();
    expect(await bridge.access(), SweepAccess.granted,
        reason: 'tool/sweep_service_test.sh grants full access first');
    final version = (await bridge.constants()).prefilterVersion;

    // ── The ledger starts empty, in this app's App Group ─────────────────────
    final store = AppGroupLedgerStore();
    for (final k in SweepLedger.keys) {
      await store.write(k, null);
    }
    var ledger = await SweepLedger.load(store);
    expect(ledger.verdicts, isEmpty);
    await ledger.setBackfillStart(_since);

    final live = const LiveSweepEndpoints();
    final ep = EmulatorPutStandIn(live);
    final uploader = NativeSweepUploader();
    var svc = CameraSweepService(
        bridge: bridge, ledger: ledger, endpoints: ep, uploader: uploader);
    await svc.attachUploads();
    final before = await _captures(uid);
    debugPrint('sweep: ${before.length} capture document(s) before');

    // ── 1. Dry run on a fresh ledger ─────────────────────────────────────────
    var state = await _ledgerState(store);
    final dry1 = await svc.dryRun();
    debugPrint('sweep: dry run 1 $dry1');
    for (final e in dry1.entries) {
      debugPrint('sweep:   $e');
    }
    expect(dry1.refused, isNull);
    expect(await _ledgerState(store), state, reason: 'the dry run wrote the ledger');
    expect(ep.sessions, isEmpty, reason: 'the dry run opened a capture session');
    expect(ep.uploads, isEmpty);
    expect(svc.candidates, isEmpty, reason: 'the dry run touched the tray');
    expect((await _captures(uid)).length, before.length,
        reason: 'the dry run filed something');
    final candidates = dry1.entries
        .where((e) => e.examination.verdict == SweepVerdict.candidate)
        .toList();
    expect(candidates, isNotEmpty, reason: 'the test photos include text');
    expect(candidates.map((e) => e.outcome).toSet(), {DryRunOutcome.wouldHoldForReview},
        reason: 'a fresh ledger: the first backfill goes through the tray, '
            'and nothing is filed yet');
    expect(dry1.entries.where((e) => e.examination.verdict == SweepVerdict.noText),
        isNotEmpty);
    final keys = {for (final e in candidates) e.asset.assetKey};

    // ── 2. A full sweep: the tray, then approve all ──────────────────────────
    final pass1 = await svc.sweep();
    debugPrint('sweep: pass 1 $pass1');
    expect(pass1.refused, isNull);
    expect(pass1.toTray, candidates.length);
    expect(ep.sessions, isEmpty, reason: 'nothing is sent before approval');
    final tray = svc.candidates.map((a) => a.localIdentifier).toList();
    await svc.approveAll();
    debugPrint('sweep: approved ${tray.length}; sessions ${ep.sessions.length}, '
        'puts ${ep.uploads.length}, errors ${svc.candidateErrors}');
    expect(svc.candidateErrors, isEmpty);
    expect(svc.candidates, isEmpty);
    expect(ep.sessions.length, tray.length, reason: 'one session per approved photo');
    // Each copy's replay of a key finds the document still pending_upload
    // here (no storage trigger runs), so it is uploaded again — spec §6.
    expect(ep.uploads.length, tray.length);
    for (final id in tray) {
      expect(ledger.verdict(id), LedgerVerdict.ingested, reason: id);
    }
    for (final e in dry1.entries.where((e) => e.examination.verdict == SweepVerdict.noText)) {
      expect(ledger.verdict(e.asset.localIdentifier), LedgerVerdict.noText(version));
    }
    expect(ledger.backfillComplete, isTrue);

    // What was filed: exactly one document per asset key (INV-14), under the
    // backend's deterministic id, carrying the key, its bytes landed.
    final after = await _captures(uid);
    String keyOf(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
        (d.data()['source_capture'] as Map)['asset_key'] as String;
    final beforeKeys = before.map(keyOf).toSet();
    final filed = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final d in after) {
      filed.putIfAbsent(keyOf(d), () => []).add(d);
    }
    expect(after.length, before.length + keys.difference(beforeKeys).length,
        reason: 'one new document per new key, whatever the number of copies');
    for (final key in keys) {
      expect(filed[key], hasLength(1), reason: 'exactly one document for $key (INV-14)');
      final d = filed[key]!.single;
      expect(d.id, _camId(uid, key));
      final cap = d.data()['source_capture'] as Map;
      expect(cap['source'], 'camera_roll');
      expect(cap['captured_at'], isA<Timestamp>(), reason: 'INV-06');
      expect(d.data()['mime_type'], 'image/jpeg');
      debugPrint('sweep: filed ${d.id} ${d.data()['title']} '
          '${d.data()['status']} ${cap['captured_at']}');
    }
    for (final u in ep.uploads) {
      expect(await EmulatorPutStandIn.storedSize(u.downloadUrl), u.size,
          reason: 'bytes landed at ${u.downloadUrl}');
    }

    // ── 3. A second sweep, on a ledger read back from the App Group ──────────
    ledger = await SweepLedger.load(store);
    expect(ledger.ingestedCount, tray.length, reason: 'the verdicts persisted');
    await svc.close();
    svc = CameraSweepService(
        bridge: bridge, ledger: ledger, endpoints: ep, uploader: uploader);
    await svc.attachUploads();
    final sessionsBefore = ep.sessions.length, putsBefore = ep.uploads.length;
    final pass2 = await svc.sweep();
    debugPrint('sweep: pass 2 $pass2');
    expect(pass2.handled, 0, reason: 'every photo already has a standing verdict');
    expect(pass2.settled, greaterThanOrEqualTo(tray.length));
    expect(svc.candidates, isEmpty);
    expect(ep.sessions.length, sessionsBefore, reason: 'the second sweep sent a session');
    expect(ep.uploads.length, putsBefore);
    expect((await _captures(uid)).length, after.length,
        reason: 'the second sweep filed something');

    // ── 4. Dry run on a reset ledger: already filed, found by asset key ──────
    // A fresh install over a library another install already swept — the
    // real-phone check, where that install is the Swift app.
    await ledger.reset();
    state = await _ledgerState(store);
    final findsBefore = ep.finds.length;
    final dry2 = await svc.dryRun();
    debugPrint('sweep: dry run 2 $dry2');
    for (final e in dry2.entries) {
      debugPrint('sweep:   $e');
    }
    expect(await _ledgerState(store), state, reason: 'the dry run wrote the ledger');
    expect(ep.sessions.length, sessionsBefore, reason: 'the dry run opened a session');
    expect(ep.uploads.length, putsBefore);
    expect(svc.candidates, isEmpty);
    expect((await _captures(uid)).length, after.length);
    expect(ep.finds.length - findsBefore,
        dry2.entries.where((e) => e.examination.verdict == SweepVerdict.candidate).length);
    for (final e in dry2.entries.where((e) => e.examination.verdict == SweepVerdict.candidate)) {
      expect(e.match, isNotNull, reason: '${e.asset.assetKey} not found by its key');
      expect(e.match!.docId, _camId(uid, e.asset.assetKey));
      // Here the document is still pending_upload (no trigger in the
      // emulator); on prod a swept photo is complete: duplicateSettled.
      expect(e.outcome, DryRunOutcome.duplicateWouldUpload);
    }

    for (final k in SweepLedger.keys) {
      await store.write(k, null);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
