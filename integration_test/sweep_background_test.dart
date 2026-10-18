// F-125 S4: the camera-roll sweep IN THE BACKGROUND, on the simulator's real
// photo library against the EMULATOR suite. Run through
// tool/sweep_background_test.sh, which adds the photos, sets full photo
// access, passes the emulator defines (the app refuses prod), runs the hold
// proxy (tool/sweep_hold_proxy.py), and — when this prints SWEEP:BACKGROUND —
// sends the app to the background and brings it back.
//
// What this proves that Tier 1 cannot:
//   1. the task's handler — registered under this app's own identifier —
//      runs a pass under the sweep's settings, its photos' uploads go through
//      the real background URLSession and land, and the task is completed
//      only when the pass ended. On a phone the launch is iOS's own
//      (`_simulateLaunchForTaskWithIdentifier:`, the call Apple's development
//      guide types into the debugger). The SIMULATOR accepts no request
//      (`submit` answers BGTaskSchedulerErrorDomain 1, unavailable), so its
//      `_simulateLaunch…` finds nothing to run; there the same handler is
//      driven with a stand-in task (SweepBackgroundTask.swift, debug only),
//      and the trail says which ran;
//   2. when the system takes the time back mid-pass
//      (`_simulateExpirationForTaskWithIdentifier:`) while a capture session
//      is in flight, that session's upload is still handed off, no other
//      session opens, nothing is recorded before its bytes land — and the
//      next task finishes the job, one document per photo with its bytes;
//   3. an upload handed off just before the app leaves the foreground
//      finishes while the app is in the background, and the photo reaches the
//      same terminal state as in the foreground: recorded `ingested`, its card
//      gone, its bytes stored.
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/camera_sweep_service.dart';
import 'package:flutter_app/services/sweep_background.dart';
import 'package:flutter_app/services/sweep_ledger.dart';
import 'package:flutter_app/services/sweep_uploader.dart';
import 'package:flutter_app/state/camera_sweep_host.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'sweep_emulator_upload.dart';

const seedEmail = 'seed@noteletter.test';
const seedPassword = 'seed-password-1';

/// The hold proxy the script runs (tool/sweep_hold_proxy.py), and how long
/// it holds the upload: longer than iOS's ~30 s of background running time,
/// so the bytes land after the app is SUSPENDED (the script prints
/// RunningBoard's own record of when it was).
const holdProxy = String.fromEnvironment('SWEEP_HOLD_PROXY');
const holdMs = int.fromEnvironment('SWEEP_HOLD_MS', defaultValue: 50000);

/// The test photos are dated 2026-10-01..05 (tool/sweep_test_photos.py); the
/// simulator's own samples are years older.
final _since = DateTime.utc(2026, 9, 1);

Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _captures(String uid) async =>
    (await FirebaseFirestore.instance
            .collection('documents')
            .where('user_id', isEqualTo: uid)
            .where('source_capture.source', isEqualTo: 'camera_roll')
            .get())
        .docs;

String _keyOf(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
    (d.data()['source_capture'] as Map)['asset_key'] as String;

/// The real uploader, with every result it hands the service kept — the
/// service acknowledges a result once recorded, and the native side then
/// forgets it.
class _Recording implements SweepUploader {
  _Recording(this.real);
  final SweepUploader real;
  final Map<String, SweepUploadResult> results = {};
  final List<String> started = [];
  final Map<String, int> startedAtMs = {};

  @override
  Future<SweepStaged> stage(String renderedPath) => real.stage(renderedPath);
  @override
  Future<void> start({
    required String uploadId,
    required String url,
    required String mimeType,
    required String localIdentifier,
    required String assetKey,
  }) {
    started.add(uploadId);
    startedAtMs[uploadId] = DateTime.now().millisecondsSinceEpoch;
    return real.start(
        uploadId: uploadId,
        url: url,
        mimeType: mimeType,
        localIdentifier: localIdentifier,
        assetKey: assetKey);
  }

  @override
  Future<void> discard(String uploadId) => real.discard(uploadId);
  @override
  Future<List<SweepUploadInFlight>> inFlight() => real.inFlight();
  @override
  Future<List<SweepUploadResult>> finished() async {
    final r = await real.finished();
    for (final x in r) {
      results[x.uploadId] = x;
    }
    return r;
  }

  @override
  Future<void> acknowledge(Iterable<String> uploadIds) => real.acknowledge(uploadIds);
  @override
  Stream<void> get resultsWaiting => real.resultsWaiting;
}

/// When the app left and re-entered the foreground, and a tick every 250 ms
/// while the Dart side ran — a long gap is the process SUSPENDED.
class _Lifecycle with WidgetsBindingObserver {
  final List<(AppLifecycleState, int)> states = [];
  final List<int> ticks = [];
  Timer? _timer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(milliseconds: 250),
        (_) => ticks.add(DateTime.now().millisecondsSinceEpoch));
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      states.add((state, DateTime.now().millisecondsSinceEpoch));

  int? at(AppLifecycleState s, {int after = 0}) {
    for (final (x, t) in states) {
      if (x == s && t >= after) return t;
    }
    return null;
  }

  /// The longest stretch between [from] and [to] with no tick.
  int longestGap(int from, int to) {
    var last = from, gap = 0;
    for (final t in ticks.where((t) => t > from && t <= to)) {
      if (t - last > gap) gap = t - last;
      last = t;
    }
    return to - last > gap ? to - last : gap;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    // Umbrella law 1. A pass here OPENS SESSIONS, which write documents.
    if (!ApiService.useEmulator) {
      fail('Refusing to run: pass --dart-define=USE_EMULATOR=true (umbrella law 1).');
    }
    FirebaseFirestore.instance
        .useFirestoreEmulator(ApiService.emulatorHost, ApiService.firestorePort);
    await FirebaseAuth.instance.useAuthEmulator(ApiService.emulatorHost, ApiService.authPort);
    await FirebaseAuth.instance
        .signInWithEmailAndPassword(email: seedEmail, password: seedPassword);
  });

  testWidgets('the background task, its expiry, and an upload that lands while the app is away',
      (tester) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final bridge = CameraSweepBridge();
    expect(await bridge.access(), SweepAccess.granted,
        reason: 'tool/sweep_background_test.sh grants full access first');
    final version = (await bridge.constants()).prefilterVersion;
    expect(holdProxy, isNotEmpty, reason: 'run through tool/sweep_background_test.sh');

    // ── The rig: the app's own pieces, the endpoints' PUT link swapped for one
    //    the storage emulator takes (sweep_emulator_upload.dart). ─────────────
    final store = AppGroupLedgerStore();
    for (final k in SweepLedger.keys) {
      await store.write(k, null);
    }
    final standIn = EmulatorPutStandIn(const LiveSweepEndpoints());
    final uploader = _Recording(NativeSweepUploader());
    final background = NativeSweepBackground();
    final session = ValueNotifier<int>(0);
    final host = CameraSweepHost(
      session: session,
      isSignedIn: () => FirebaseAuth.instance.currentUser != null,
      bridge: bridge,
      store: store,
      endpoints: standIn,
      uploader: uploader,
      background: background,
    );
    await host.ready;
    final ledger = host.ledger!;
    final svc = host.service!;
    // Set up directly (not through the switch, which would run a pass now):
    // on, automatic, the first catch-up done, the test photos' window.
    await ledger.setBackfillStart(_since);
    await ledger.setMode(SweepMode.automatic);
    await ledger.setBackfillComplete(true);
    await ledger.setEnabled(true);
    final schedule = await background.setScheduled(true);
    debugPrint('sweep bg: schedule $schedule; pending ${await background.debugPending()}');

    final page = await bridge.fetchImages(since: _since, limit: 200);
    final photos = page.assets.where((a) => a.isRepresentative).toList();
    debugPrint('sweep bg: ${photos.length} photos in the window');
    final before = await _captures(uid);

    Future<List<Map<String, Object?>>> trailSince(int n) async =>
        (await background.debugTrail()).skip(n).toList();

    Future<List<Map<String, Object?>>> waitTrail(int n, String event, {int seconds = 240}) async {
      for (var i = 0; i < seconds * 4; i++) {
        final t = await trailSince(n);
        if (t.any((e) => e['event'] == event)) return t;
        await tester.pump(const Duration(milliseconds: 250));
      }
      fail('timed out waiting for the native trail to say "$event": ${await trailSince(n)}');
    }

    Future<void> waitUploads({int seconds = 120}) async {
      for (var i = 0; i < seconds * 4; i++) {
        if (svc.uploadsInFlight == 0 &&
            (await uploader.real.inFlight()).isEmpty &&
            (await uploader.real.finished()).isEmpty) {
          return;
        }
        await tester.pump(const Duration(milliseconds: 250));
      }
      fail('uploads still in flight: ${svc.uploadsInFlight}, '
          '${(await uploader.real.inFlight()).length} native');
    }

    List<String> events(List<Map<String, Object?>> t) =>
        [for (final e in t) e['event'] as String];

    // ── 1. iOS launches the task: a pass runs, its uploads land ──────────────
    var mark = (await background.debugTrail()).length;
    await background.debugSimulateLaunch();
    var trail = await waitTrail(mark, 'completed');
    debugPrint('sweep bg: launch 1 trail ${jsonEncode(trail)}');
    final via = trail.firstWhere((e) => e['event'] == 'simulateLaunch')['via'];
    debugPrint('sweep bg: launched via $via');
    expect((await background.debugTrail()).firstWhere((e) => e['event'] == 'registered')['ok'], isTrue,
        reason: 'BGTaskScheduler took the registration: Info.plist permits the identifier');
    expect(events(trail), containsAllInOrder(['simulateLaunch', 'launched', 'run', 'ran', 'completed']));
    expect(trail.lastWhere((e) => e['event'] == 'completed')['success'], isTrue);
    final ranAt = trail.firstWhere((e) => e['event'] == 'ran')['atMs'] as num;
    expect(events(trail), anyOf(contains('scheduled'), contains('notScheduled')),
        reason: 'the next task is asked for first thing (Swift)');
    await waitUploads();

    final candidates = <SweepAsset>[], noText = <SweepAsset>[];
    for (final a in photos) {
      final v = ledger.verdict(a.localIdentifier);
      if (v == LedgerVerdict.ingested) {
        candidates.add(a);
      } else if (v == LedgerVerdict.noText(version)) {
        noText.add(a);
      } else {
        fail('${a.localIdentifier} "${a.originalFilename}" has no verdict after the task: $v');
      }
    }
    debugPrint('sweep bg: task 1 recorded ${candidates.length} ingested, ${noText.length} no-text; '
        '${standIn.sessions.length} sessions, ${uploader.started.length} uploads');
    expect(candidates, isNotEmpty);
    expect(noText, isNotEmpty);
    expect(standIn.sessions, hasLength(candidates.length), reason: 'one session per photo');
    expect(uploader.started, hasLength(standIn.uploads.length),
        reason: 'every session with a link got its upload');
    for (final r in uploader.results.values) {
      expect(r.ok, isTrue, reason: '$r');
      expect((r.finishedAtMs ?? 0) <= ranAt, isTrue,
          reason: 'the task answered only after its uploads landed');
    }
    for (final u in standIn.uploads) {
      expect(await EmulatorPutStandIn.storedSize(u.downloadUrl), u.size,
          reason: 'the bytes landed for ${u.assetKey}');
    }
    final keys = {for (final a in candidates) a.assetKey};
    var after = await _captures(uid);
    for (final key in keys) {
      expect(after.where((d) => _keyOf(d) == key), hasLength(1),
          reason: 'one document for $key (INV-14)');
    }
    expect(after.length - before.length, keys.difference(before.map(_keyOf).toSet()).length);

    // ── 2. The time runs out with a session in flight ────────────────────────
    await ledger.reset();
    await ledger.setBackfillComplete(true);
    final sessions0 = standIn.sessions.length, uploads0 = uploader.started.length;
    var expiryAsked = false;
    // Inside the Dart side's 2 s bound, so its wait — not the native
    // backstop — is what ends the task.
    standIn.sessionDelay = const Duration(milliseconds: 800);
    standIn.onSessionStart = (_) {
      if (expiryAsked) return;
      expiryAsked = true;
      unawaited(background.debugSimulateExpiration());
    };
    mark = (await background.debugTrail()).length;
    await background.debugSimulateLaunch();
    trail = await waitTrail(mark, 'completed');
    debugPrint('sweep bg: launch 2 trail ${jsonEncode(trail)}');
    expect(events(trail), containsAllInOrder(['launched', 'run', 'simulateExpiration', 'expired']));
    expect(trail.lastWhere((e) => e['event'] == 'completed')['success'], isFalse);
    final expiredAt = trail.firstWhere((e) => e['event'] == 'expired')['atMs'] as num;
    final completedAt = trail.lastWhere((e) => e['event'] == 'completed')['atMs'] as num;
    expect(completedAt - expiredAt, lessThan(3500), reason: 'completed promptly on expiry');
    standIn.sessionDelay = null;
    standIn.onSessionStart = null;
    await tester.pump(const Duration(seconds: 3));
    final phase2 = standIn.sessions.skip(sessions0).toList();
    debugPrint('sweep bg: expiry phase opened ${phase2.length} session(s), '
        '${uploader.started.length - uploads0} upload(s)');
    expect(phase2, hasLength(1), reason: 'the one in flight, and none after the expiry');
    expect(phase2.single.$2.millisecondsSinceEpoch, lessThan(expiredAt),
        reason: 'opened before the expiry');
    expect(uploader.started.length - uploads0, 1,
        reason: 'the session in flight still handed its upload off: no empty document');
    final ack = trail.where((e) => e['event'] == 'expireAcknowledged');
    expect(ack, isNotEmpty, reason: 'the Dart side answered the expiry');
    expect(uploader.startedAtMs[uploader.started.last]!, lessThan(ack.first['atMs'] as num),
        reason: 'the expiry was answered only after the hand-off: never between the two');
    expect(svc.halted, isTrue, reason: 'nothing starts until the app is back or a task');
    await waitUploads();
    final recorded = [
      for (final a in photos)
        if (ledger.verdict(a.localIdentifier) == LedgerVerdict.ingested) a
    ];
    expect(recorded, hasLength(1), reason: 'only the photo whose bytes landed');
    expect(recorded.single.assetKey, phase2.single.$1);

    // The next task finishes the job.
    mark = (await background.debugTrail()).length;
    await background.debugSimulateLaunch();
    trail = await waitTrail(mark, 'completed');
    expect(trail.lastWhere((e) => e['event'] == 'completed')['success'], isTrue);
    await waitUploads();
    for (final a in candidates) {
      expect(ledger.verdict(a.localIdentifier), LedgerVerdict.ingested, reason: a.localIdentifier);
    }
    for (final a in noText) {
      expect(ledger.verdict(a.localIdentifier), LedgerVerdict.noText(version));
    }
    for (final u in standIn.uploads) {
      expect(await EmulatorPutStandIn.storedSize(u.downloadUrl), u.size,
          reason: 'every session opened has its bytes: ${u.assetKey}');
    }
    after = await _captures(uid);
    for (final key in keys) {
      expect(after.where((d) => _keyOf(d) == key), hasLength(1), reason: 'still one: $key');
    }

    // ── 3. An upload that lands while the app is in the background ───────────
    await ledger.reset(); // the first catch-up again: candidates wait in the tray
    svc.resume();
    final pass = await svc.sweep();
    debugPrint('sweep bg: tray pass $pass');
    expect(svc.candidates, isNotEmpty);
    final card = svc.candidates.first;
    standIn
      ..via = holdProxy
      ..holdMs = holdMs;
    final life = _Lifecycle()..start();
    final uploadsBefore = uploader.started.length;
    var addDone = false;
    final add = svc.approve(card).whenComplete(() => addDone = true);
    for (var i = 0; i < 40 && uploader.started.length == uploadsBefore; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(uploader.started.length, uploadsBefore + 1, reason: 'handed off');
    final handedOffAt = DateTime.now().millisecondsSinceEpoch;
    debugPrint('SWEEP:BACKGROUND');
    // The script sends the app away now and brings it back later.
    int? pausedAt, resumedAt;
    for (var i = 0; i < 240 * 4; i++) {
      pausedAt = life.at(AppLifecycleState.paused, after: handedOffAt);
      if (pausedAt != null) {
        resumedAt = life.at(AppLifecycleState.resumed, after: pausedAt);
        if (resumedAt != null && addDone) break;
      }
      await tester.pump(const Duration(milliseconds: 250));
    }
    life.stop();
    standIn.via = null;
    expect(pausedAt, isNotNull, reason: 'the app never left the foreground');
    expect(resumedAt, isNotNull, reason: 'the app never came back');
    await add;
    final result = uploader.results.values.lastWhere((r) => r.localIdentifier == card.localIdentifier);
    final gap = life.longestGap(pausedAt!, resumedAt!);
    final wakes = await background.debugUploads();
    final proxyLog = (await Dio().get<String>('$holdProxy/log')).data!
        .trim().split('\n').map((l) => jsonDecode(l) as Map).toList();
    final held = proxyLog.last;
    debugPrint('sweep bg: away ${resumedAt - pausedAt} ms (paused $pausedAt, resumed $resumedAt); '
        'longest Dart silence $gap ms; result $result at ${result.finishedAtMs}; '
        'proxy $held; wakes $wakes');
    expect(result.ok, isTrue);
    expect(held['answeredMs'] as num, inExclusiveRange(pausedAt, resumedAt),
        reason: 'the bytes went while the app was away');
    expect(result.finishedAtMs!, inExclusiveRange(pausedAt, resumedAt),
        reason: 'and the app heard of it while it was away');
    expect(result.appState, 2, reason: 'UIApplicationState.background');
    expect(ledger.verdict(card.localIdentifier), LedgerVerdict.ingested,
        reason: 'the same terminal state as a foreground upload');
    expect(svc.candidates.any((c) => c.localIdentifier == card.localIdentifier), isFalse,
        reason: 'its card left the tray');
    expect(await EmulatorPutStandIn.storedSize(standIn.uploads.last.downloadUrl),
        standIn.uploads.last.size);
    // Whether the process was SUSPENDED when the bytes landed is
    // RunningBoard's to say (the script prints its timeline); a wake for the
    // session's events is iOS resuming it to deliver them.
    final woke = (wakes['wakes'] as List? ?? const []).cast<num>();
    debugPrint('SWEEP:RESULT answered=${held['answeredMs']} finished=${result.finishedAtMs} '
        'paused=$pausedAt resumed=$resumedAt wakes=${woke.join(',')}');

    for (final k in SweepLedger.keys) {
      await store.write(k, null);
    }
    await background.setScheduled(false);
    host.dispose();
  }, timeout: const Timeout(Duration(minutes: 15)));
}
