import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'api.dart';
import 'api_service.dart';
import 'camera_sweep_bridge.dart';
import 'firestore_service.dart';
import 'sweep_ledger.dart';
import 'sweep_uploader.dart';
import 'sweep_words.dart';

/// The camera-roll sweep (F-125 S2; INV-14, `spec/features/camera-roll-sweep.md`),
/// ported from the retired Swift app's `CameraSweepService.swift` and
/// `CameraSweepAPI.swift` (NoteLetter 910864a) over S1's native bridge.
///
/// One pass: enumerate newest first from the backfill start, skip what the
/// ledger has settled, run the on-device text check, and for a candidate
/// read its key, then either hold it in the review tray or — automatic mode,
/// once the first backfill is done — render the JPEG, open a capture session
/// and PUT it.
///
/// **Two kinds of pass (5.40.0, ADR-195; spec §7).** Until a walk has
/// reached the start date with nothing left over, a pass walks the whole
/// library. After one has, a pass reads only what changed since the change
/// token that walk left ([ChangeMark]), plus what the ledger owes another
/// look ([SweepLedger.owedAnotherLook]). A token is kept only from a pass
/// that finished.
///
/// What it never does: upload an asset the pre-filter rejected, upload
/// anything in review mode before the user approves it, or request sessions
/// ahead in bulk (a signed URL lasts 15 minutes; spec §5).
///
/// [dryRun] is the same walk with every write taken out: no ledger write, no
/// session, no PUT. It says what a pass WOULD do, asking Firestore (a read)
/// whether each candidate is already filed.
///
/// The screens are S3's (`lib/pages/settings/camera_sweep_page.dart`,
/// `lib/pages/sources/sweep_tray.dart`), and so is what starts a pass in the
/// foreground (`lib/state/camera_sweep_host.dart`), which also answers S4's
/// background task.
///
/// **Uploads are background uploads (S4, [SweepUploader]).** A photo is
/// recorded `ingested` only when its bytes LANDED — the uploader's result,
/// in this launch or a later one — or when the server already had them.
/// Between a capture session and its upload's hand-off nothing can stop a
/// photo: [expire] waits for that step, the native side holds the app awake
/// through it, and a session is never opened once a pass has been told to
/// stop. So background time running out never marks a photo done and never
/// leaves a document that no upload is coming for.
class CameraSweepService extends ChangeNotifier {
  CameraSweepService({
    required this.bridge,
    required this.ledger,
    required this.endpoints,
    required this.uploader,
    this.words = SweepWords.ios,
  });

  /// The platform's sentences (5.26.1).
  final SweepWords words;

  final CameraSweepBridge bridge;
  final SweepLedger ledger;
  final SweepEndpoints endpoints;
  final SweepUploader uploader;

  /// The first backfill is bounded, and so is every pass: a roll full of
  /// screenshots is the EXPENSIVE case for this pipeline (each
  /// `article_title` costs a reverse image search, a multimodal pass and a
  /// proxied web search), and the first pass is the one that finds thousands
  /// at once (Swift `backfillBatchLimit`).
  static const backfillBatchLimit = 200;

  /// The bytes a sweep uploads are always a rendered JPEG (spec §5).
  static const uploadMimeType = 'image/jpeg';

  // ── State a screen draws (S3) ──────────────────────────────────────────────

  final List<SweepAsset> _candidates = [];

  /// Waiting on the user in the review tray. Client-local and in memory, as
  /// in Swift: these are not documents yet and nothing has been sent. A
  /// relaunch forgets the tray; the next pass finds them again, because a
  /// candidate stays `waiting` until it is in or dismissed — which is what a
  /// pass from a change token reads (5.40.0).
  List<SweepAsset> get candidates => List.unmodifiable(_candidates);

  bool _isSweeping = false;
  bool get isSweeping => _isSweeping;

  int _examined = 0;
  int get examined => _examined;

  /// The walk's position (5.43.0, ADR-198): photos the current or last
  /// whole-library walk has gone through, newest first — the ones settled on
  /// an earlier pass included, as each is passed on the way. null until a
  /// walk has begun in this launch. A pass from a change token reads only
  /// what changed and moves it not at all. *Looking back · {n} of {N}*.
  int? _walkPosition;
  int? get walkPosition => _walkPosition;

  /// The photos in range as that walk's listing counted them: its *N*.
  int? _walkTotal;
  int? get walkTotal => _walkTotal;

  /// The last pass stopped at its per-pass bound with photos left
  /// (feature §3): *Looking back* says when the rest is read.
  bool _capped = false;
  bool get capped => _capped;

  /// Counted when the bytes LANDED (or the server already had them), never
  /// when a request was merely sent (Swift D5).
  int _ingestedThisSession = 0;
  int get ingestedThisSession => _ingestedThisSession;

  /// Uploads this launch handed off whose result has not come back, by
  /// `localIdentifier`.
  final Map<String, _Upload> _uploads = {};
  int get uploadsInFlight => _uploads.length;

  /// Uploads an EARLIER launch handed off that the system still holds: a
  /// pass does not start a second upload of their photos.
  Set<String> _inFlightElsewhere = {};

  /// Results already counted, so a result read twice (its acknowledgement
  /// did not land) is counted once.
  final Set<String> _counted = {};

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Whether [errorMessage] actually ENDED the sweep. Only [DedupeUnsupported]
  /// does; one photo's refusal is one photo (Swift D5).
  bool _errorStoppedSweep = false;
  bool get errorStoppedSweep => _errorStoppedSweep;

  /// Partial or no library access, when the last pass was refused; its
  /// sentence is the Swift app's (spec §1).
  SweepAccessRefused? _accessRefused;
  SweepAccessRefused? get accessRefused => _accessRefused;

  final Map<String, String> _candidateErrors = {};

  final Map<String, CaptureMatch> _filed = {};

  /// Tray cards a look back found — the walk had not reached its start date
  /// — as against Ask me first's. The review says which (5.43.0, ADR-198).
  final Set<String> _byLookBack = {};

  /// Whether this waiting photo was found by a look back, which keeps
  /// everything for review whatever the mode; false: Ask me first held it.
  bool foundByLookBack(String localIdentifier) => _byLookBack.contains(localIdentifier);

  /// A tray card whose photo is ALREADY IN NoteLetter (screens/sources.md
  /// §Camera-roll sweep, 5.23.0): a document carries its asset key and its
  /// bytes landed — any status but `pending_upload` and `error`. Asked once,
  /// when the candidate enters the tray ([SweepEndpoints.findCapture]). It is
  /// what a phone moved from the Swift app shows for a photo that app already
  /// swept, before anything is approved. Add still works: the session answers
  /// `duplicate: true` with no upload link, and nothing uploads (spec §6).
  bool alreadyIn(String localIdentifier) {
    final m = _filed[localIdentifier];
    return m != null && !const {'pending_upload', 'error'}.contains(m.status);
  }

  /// Why a candidate could not be added, by `localIdentifier`. The card stays
  /// in the tray, carrying the sentence, until a later attempt settles it.
  Map<String, String> get candidateErrors => Map.unmodifiable(_candidateErrors);

  /// The alert's title is a CLAIM (Swift D5); D's words since 5.43.0.
  String get failureTitle =>
      _errorStoppedSweep ? stoppedTitle : oneFailedTitle;

  static const stoppedTitle = 'The camera roll stopped';
  static const oneFailedTitle = 'A photo couldn’t be added';

  /// The one place that sets the pair, so they cannot disagree.
  void presentFailure(String sentence, {required bool stopsSweep}) {
    _errorMessage = sentence;
    _errorStoppedSweep = stopsSweep;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    _errorStoppedSweep = false;
    notifyListeners();
  }

  /// What happens to a card once the call has come back: a sentence keeps it
  /// in the tray with its reason; null settles it. It cannot run before the
  /// answer exists — the umbrella's "write before you move".
  void record(String? sentence, String localIdentifier) {
    if (sentence != null) {
      _candidateErrors[localIdentifier] = sentence;
    } else {
      _candidates.removeWhere((c) => c.localIdentifier == localIdentifier);
      _candidateErrors.remove(localIdentifier);
      _filed.remove(localIdentifier);
      _byLookBack.remove(localIdentifier);
    }
    notifyListeners();
  }

  /// Forgets the tray and every sentence on it — the account it was found
  /// for signed out. Nothing was sent for a card, so nothing is lost: the
  /// next pass finds the same photos again.
  void clearTray() {
    _candidates.clear();
    _candidateErrors.clear();
    _filed.clear();
    _byLookBack.clear();
    _errorMessage = null;
    _errorStoppedSweep = false;
    _accessRefused = null;
    notifyListeners();
  }

  // ── The pass ───────────────────────────────────────────────────────────────

  Future<SweepPass>? _running;
  bool _cancelled = false;
  Completer<void>? _stopped;

  /// No pass starts while this is set: background time ran out, or the app
  /// left the foreground with no background task to finish in. [resume]
  /// lifts it (the app is back, or iOS granted a background task).
  bool _halted = false;
  bool get halted => _halted;

  /// The steps between a capture session and its upload's hand-off now in
  /// progress — what [expire] waits for.
  final Set<Future<void>> _handOffs = {};

  /// How long [expire] waits for a hand-off in progress. The native task
  /// completes 3 s after expiry whatever happens here.
  static const expiryGrace = Duration(seconds: 2);

  /// Runs the sweep only if the user turned it on and the library is fully
  /// readable; otherwise does nothing. Safe on every launch and sign-in.
  Future<SweepPass?> startIfEnabled() async {
    if (!ledger.enabled) return null;
    if (await bridge.access() != SweepAccess.granted) return null;
    return sweep();
  }

  /// One pass. A second call while one runs gets the running one; while
  /// [halted], none runs.
  Future<SweepPass> sweep() {
    final running = _running;
    if (running != null) return running;
    if (_halted) return Future.value(SweepPass()..halted = true);
    _cancelled = false;
    _stopped = Completer<void>();
    _isSweeping = true;
    _errorMessage = null;
    _errorStoppedSweep = false;
    _accessRefused = null;
    notifyListeners();
    final pass = _runSweep().whenComplete(() {
      _isSweeping = false;
      _running = null;
      notifyListeners();
    });
    return _running = pass;
  }

  /// Stops the pass at the next asset. Uploads already handed off carry on.
  void stop() {
    _cancelled = true;
    final stopped = _stopped;
    if (stopped != null && !stopped.isCompleted) stopped.complete();
  }

  /// Background time ran out (S4), or the app left the foreground with no
  /// background task: stop at the next safe point and start nothing until
  /// [resume]. Returns once any capture session in flight has handed its
  /// upload off — the one step that must not be cut in two, or a document
  /// would wait for bytes no upload is bringing — or after [grace].
  ///
  /// It records nothing: a photo whose upload is on its way is recorded when
  /// the bytes land, whenever that is.
  Future<void> expire({Duration grace = expiryGrace}) async {
    _halted = true;
    stop();
    if (_handOffs.isEmpty) return;
    await Future.wait(List.of(_handOffs)).timeout(grace, onTimeout: () => const []);
  }

  /// Passes may run again.
  void resume() {
    _halted = false;
  }

  Future<SweepPass> _runSweep() async {
    final pass = SweepPass();
    try {
      // Which photos already have an upload on its way — first, so that one
      // finishing between the two reads is caught by the drain below.
      await _refreshInFlight();
      // A result that came back while the app was away is recorded before
      // the walk, so its photo is skipped, not examined again.
      await drainUploads();
      await _recordInFlightAsWaiting();
      final version = (await bridge.constants()).prefilterVersion;
      final since = ledger.backfillStart;
      final changes = await _changesSinceMark(version, since);
      if (changes != null) {
        // Only what changed since the last pass that finished, and what the
        // ledger owes another look; a deletion needs nothing.
        pass.fromChangeToken = true;
        final ids = {...changes.localIdentifiers, ...ledger.owedAnotherLook};
        if (ids.isNotEmpty) {
          await _walk(version, (listing) => _examine(listing, pass), pass,
              only: ids.toList());
        }
        if (_finished(pass)) await ledger.setChangeMark(_mark(changes.token, version, since));
      } else {
        // The whole library. Its token is read FIRST, so a photo that lands
        // during the walk is read by the next pass, never skipped. Everything
        // the ledger has a standing verdict for is skipped without touching a
        // pixel, which is also what makes an interrupted walk resume (§7).
        final token = await _changeTokenNow();
        await _walk(version, (listing) => _examine(listing, pass), pass);
        if (_finished(pass)) {
          // Ran out of work before the cap: nothing older is waiting.
          await ledger.setBackfillComplete(true);
          if (token != null) await ledger.setChangeMark(_mark(token, version, since));
        }
      }
      // An automatic pass ends when what it sent has landed or failed, so
      // its counts are outcomes — unless it was stopped: an upload outlives
      // the pass that started it, and is recorded whenever it lands.
      if (pass._landings.isNotEmpty) {
        await Future.any([Future.wait(pass._landings), _stopped!.future]);
      }
    } on SweepAccessRefused catch (e) {
      _accessRefused = e;
      pass.refused = e;
    }
    _capped = pass.handled >= backfillBatchLimit && !_cancelled;
    if (pass.refused == null && _errorMessage == null) await _looked();
    return pass;
  }

  /// The end of a pass that finished without an error: the panel's "looked
  /// {ago}" (5.43.0, ADR-198 decision 7). Stopped or capped still counts —
  /// neither is an error. A write that fails keeps the last time the store
  /// holds, and is said in the log: it is a status line, never a photo.
  Future<void> _looked() async {
    try {
      await ledger.setLastLookedAt(DateTime.now());
    } catch (e) {
      debugPrint('camera sweep: when this pass ended could not be saved ($e)');
    }
  }

  /// Got through everything it was given: not capped, not stopped, not
  /// ended by the sweep stopping. Only such a pass may move the change mark,
  /// so nothing a pass did not reach is ever skipped (spec §7 rule 2).
  bool _finished(SweepPass pass) =>
      pass.handled < backfillBatchLimit && !_cancelled && !_errorStoppedSweep;

  static ChangeMark _mark(String token, int version, DateTime since) => ChangeMark(
        token: token,
        prefilterVersion: version,
        backfillStartMs: since.millisecondsSinceEpoch,
      );

  /// What changed since the mark, or null when this pass walks the whole
  /// library: no mark, one taken under another pre-filter or start date, or
  /// one the platform can no longer answer from (spec §7 rule 4).
  Future<SweepChanges?> _changesSinceMark(int version, DateTime since) async {
    final mark = ledger.changeMark;
    if (mark == null || !ledger.backfillComplete) return null;
    if (!mark.standsFor(prefilterVersion: version, backfillStart: since)) return null;
    final SweepChanges? changes;
    try {
      changes = await bridge.changesSince(mark.token);
    } on SweepAccessRefused {
      rethrow;
    } catch (e) {
      // A walk is always right; it is only slower.
      debugPrint('camera sweep: what changed could not be read ($e); '
          'walking the whole library');
      return null;
    }
    if (changes == null) await ledger.setChangeMark(null);
    return changes;
  }

  Future<String?> _changeTokenNow() async {
    try {
      return await bridge.changeToken();
    } on SweepAccessRefused {
      rethrow;
    } catch (e) {
      // No mark from this walk, so the next one walks too.
      debugPrint('camera sweep: the change token could not be read ($e)');
      return null;
    }
  }

  /// An upload in flight is a candidate's. One handed off before 5.40.0 has
  /// no verdict, and if it failed no pass from a change token would offer
  /// it again, so it is recorded `waiting` first (spec §7 rule 5).
  Future<void> _recordInFlightAsWaiting() async {
    for (final id in {..._inFlightElsewhere, ..._uploads.keys}) {
      await ledger.record(LedgerVerdict.waiting, id, ifNone: true);
    }
  }

  Future<void> _refreshInFlight() async {
    try {
      _inFlightElsewhere = {
        for (final u in await uploader.inFlight())
          if (!_uploads.containsKey(u.localIdentifier)) u.localIdentifier,
      };
    } catch (e) {
      // Said, not swallowed. Without it a pass may upload a photo whose
      // earlier upload is still on its way: the same bytes to the same
      // object, under the one document the asset key allows (INV-14).
      debugPrint('camera sweep: the uploads in flight could not be read ($e)');
    }
  }

  /// The walk both the pass and the dry run take: the whole library, or
  /// [only] those photos. [onAsset] runs for each photo that needs
  /// examining, at most [backfillBatchLimit] times. A listing carries no key;
  /// [onAsset] reads one only for a candidate.
  Future<void> _walk(
    int prefilterVersion,
    Future<void> Function(SweepListing listing) onAsset,
    SweepTally tally, {
    List<String>? only,
  }) async {
    var offset = 0;
    // A pass's whole-library walk is the look back a screen counts; a dry
    // run's rehearsal and a pass from a change token are not.
    final counts = only == null && tally is SweepPass;
    if (counts) _walkPosition = 0;
    while (true) {
      final page = await bridge.fetchImages(
        since: ledger.backfillStart,
        offset: offset,
        limit: CameraSweepBridge.defaultPageSize,
        localIdentifiers: only,
      );
      if (counts) _walkTotal = page.total;
      for (final asset in page.assets) {
        if (_cancelled || _errorStoppedSweep) return;
        if (tally.handled >= backfillBatchLimit) return;
        if (counts) _walkPosition = _walkPosition! + 1;
        // A burst contributes only its representative frame (spec §8).
        if (!asset.isRepresentative) {
          tally.nonRepresentative++;
          continue;
        }
        // Its upload is on its way (S4): recorded when it lands, never sent
        // twice.
        if (_uploads.containsKey(asset.localIdentifier) ||
            _inFlightElsewhere.contains(asset.localIdentifier)) {
          tally.inFlight++;
          continue;
        }
        if (!ledger.needsExamination(asset.localIdentifier,
            prefilterVersion: prefilterVersion)) {
          tally.settled++;
          continue;
        }
        await onAsset(asset);
        tally.handled++;
      }
      offset += page.assets.length;
      if (page.assets.isEmpty || offset >= page.total) return;
    }
  }

  Future<void> _examine(SweepListing listing, SweepPass pass) async {
    // Already waiting on the user: its verdict cannot have changed, so the
    // text check is not run again. It still counts toward the cap, as in
    // Swift — a tray of 200 is the first backfill's bound. (Swift re-ran
    // Vision on every card each pass; S3 runs a pass on every library change,
    // and a phone syncing iCloud changes its library constantly.)
    final id = listing.localIdentifier;
    if (_candidates.any((c) => c.localIdentifier == id)) {
      pass.held++;
      return;
    }
    final exam = await bridge.examine(id);
    _examined++;
    switch (exam.verdict) {
      case SweepVerdict.notLocallyAvailable:
        // Never "no text": that verdict would be permanent and wrong.
        await ledger.record(LedgerVerdict.deferredNotLocal, id);
        pass.deferred++;
      case SweepVerdict.noText:
        await ledger.record(LedgerVerdict.noText(exam.prefilterVersion), id);
        pass.noText++;
      case SweepVerdict.candidate:
        // Only now is the key read (spec §4): a candidate is the one photo
        // that is looked up or sent.
        final asset = await bridge.identify(id);
        // Waiting until it is in or dismissed, so a pass from a change token
        // finds it again however this ends: a tray a relaunch forgets, or an
        // upload that fails (spec §2).
        if (ledger.verdict(id) != LedgerVerdict.waiting) {
          await ledger.record(LedgerVerdict.waiting, id);
        }
        if (_toTray) {
          // The first backfill always goes through review, whatever mode the
          // user picked, because it is the pass that surfaces everything at
          // once (spec §3). Whether its photo is already in NoteLetter is
          // asked first, so the card arrives saying so.
          await _lookUp(asset);
          _candidates.add(asset);
          if (!ledger.backfillComplete) _byLookBack.add(id);
          pass.toTray++;
        } else {
          // Nobody is looking at a tray, so a refusal goes to the screen's
          // own alert — and it did not stop the sweep, unless the dedupe
          // branch said so.
          void failed(String sentence) {
            pass.failed[id] = sentence;
            if (!_errorStoppedSweep) presentFailure(sentence, stopsSweep: false);
          }

          switch (await _ingest(asset, fromPass: true)) {
            case _Landed():
              pass.ingested++;
            case _Refused(:final sentence):
              failed(sentence);
            case _NotStarted():
              break;
            case _Uploading(:final landed):
              pass.uploading++;
              pass._landings.add(landed.then((sentence) {
                if (sentence == null) {
                  pass.ingested++;
                } else {
                  failed(sentence);
                }
              }));
          }
        }
    }
    notifyListeners();
  }

  bool get _toTray => ledger.mode == SweepMode.review || !ledger.backfillComplete;

  /// One read per candidate entering the tray: `user_id` + the asset key.
  /// A read that fails says nothing about the card — never "new".
  Future<void> _lookUp(SweepAsset asset) async {
    try {
      final match = await endpoints.findCapture(asset.assetKey);
      if (match != null) _filed[asset.localIdentifier] = match;
    } catch (e) {
      debugPrint('camera sweep: could not ask whether ${asset.assetKey} is '
          'already filed — $e');
    }
  }

  // ── Review actions ─────────────────────────────────────────────────────────

  /// The card leaves the tray only once the photo is in — its upload LANDED,
  /// or the server already had it (Swift D5; S4 keeps it there through a
  /// background upload, where Swift let it go at the hand-off). On a refusal
  /// it stays, carrying the reason.
  Future<void> approve(SweepAsset asset) async => (await _handOffCard(asset)).settled;

  /// A snapshot, because settling mutates the tray. One refusal costs one
  /// photo; a refusal that ends the sweep ends this too. Each session is
  /// still opened immediately before its own upload starts (spec §5); the
  /// uploads then land side by side, rather than one after another.
  Future<void> approveAll() async {
    final settling = <Future<void>>[];
    for (final asset in List.of(_candidates)) {
      if (_errorStoppedSweep) break;
      settling.add((await _handOffCard(asset)).settled);
    }
    await Future.wait(settling);
  }

  /// Opens the card's session and hands its upload off; what it returns
  /// says when the card is settled.
  Future<_Card> _handOffCard(SweepAsset asset) async {
    final id = asset.localIdentifier;
    _candidateErrors.remove(id);
    notifyListeners();
    switch (await _ingest(asset, fromPass: false)) {
      case _Landed():
        record(null, id);
      case _Refused(:final sentence):
        record(sentence, id);
      case _NotStarted():
        break;
      case _Uploading(:final landed):
        return _Card(landed.then((sentence) => record(sentence, id)));
    }
    return _Card(Future<void>.value());
  }

  /// Client-local and permanent for that asset. Nothing is sent, which is why
  /// review mode costs no requests at all.
  Future<void> dismiss(SweepAsset asset) async {
    await ledger.record(LedgerVerdict.dismissed, asset.localIdentifier);
    _candidates.removeWhere((c) => c.localIdentifier == asset.localIdentifier);
    _candidateErrors.remove(asset.localIdentifier);
    _filed.remove(asset.localIdentifier);
    _byLookBack.remove(asset.localIdentifier);
    notifyListeners();
  }

  // ── Ingest ─────────────────────────────────────────────────────────────────

  /// What became of one photo: in already, on its way, refused (with the
  /// sentence), or — a pass told to stop — not started. It sets
  /// [errorMessage] only where the failure ends the whole sweep: who renders
  /// a refusal depends on who asked for it, a card or the automatic pass's
  /// alert.
  ///
  /// The order is the server's consistency (S4): render and STAGE the bytes,
  /// then — the last point at which stopping costs nothing — check the pass
  /// may go on, then open the session and hand its upload off, as one step
  /// [expire] waits for. A session is never opened for bytes that are not
  /// already staged, and never left without its upload.
  Future<_Ingest> _ingest(SweepAsset asset, {required bool fromPass}) async {
    final id = asset.localIdentifier;
    final already = _uploads[id];
    if (already != null) return _Uploading(already.landed.future);
    String? staged;
    try {
      final rendered = await bridge.renderedJpeg(id);
      if (rendered == null) {
        await ledger.record(LedgerVerdict.deferredNotLocal, id);
        return _Refused(words.deferredSentence);
      }
      final stage = await uploader.stage(rendered.path);
      staged = stage.uploadId;
      if (fromPass && _cancelled) return const _NotStarted();
      final handOff = Completer<void>();
      _handOffs.add(handOff.future);
      try {
        // Requested immediately before the upload: the signed URL lasts 15
        // minutes, so sessions are never taken out ahead of time.
        final session = CaptureSession.fromResponse(await endpoints.openSession(
          assetKey: asset.assetKey,
          filename: uploadFilename(asset),
          mimeType: uploadMimeType,
          size: stage.bytes,
          capturedAt: capturedAt(asset),
        ));
        final url = session.uploadUrl;
        if (url == null) {
          // `uploadUrl: null` is the bytes having already landed: record and
          // move on — the whole point of the server-side key.
          await ledger.record(LedgerVerdict.ingested, id);
          _ingestedThisSession++;
          notifyListeners();
          return const _Landed();
        }
        // A fresh session, or a replay whose document never received bytes
        // (`pending_upload`/`error`): upload against it (spec §6). Skipping
        // the replay's URL would strand the document at pending_upload.
        final upload = _Upload(stage.uploadId);
        _uploads[id] = upload;
        try {
          await uploader.start(
            uploadId: stage.uploadId,
            url: url,
            mimeType: uploadMimeType,
            localIdentifier: id,
            assetKey: asset.assetKey,
          );
        } catch (_) {
          _uploads.remove(id);
          rethrow;
        }
        staged = null; // the uploader's now; its completion deletes it
        notifyListeners();
        return _Uploading(upload.landed.future);
      } finally {
        handOff.complete();
        _handOffs.remove(handOff.future);
      }
    } on DedupeUnsupported catch (e) {
      // The one failure that ends the sweep: continuing would re-ingest the
      // library, one duplicate at a time, with no request failing.
      presentFailure(e.sentence, stopsSweep: true);
      stop();
      return _Refused(e.sentence);
    } on SweepAccessRefused catch (e) {
      _accessRefused = e;
      stop();
      return _Refused(e.sentence);
    } on ApiException catch (e) {
      return _Refused(e.message);
    } on FormatException catch (e) {
      return _Refused(e.message);
    } on PlatformException catch (e) {
      // The bridge could not render the photo (deleted since the pass found
      // it, or a write failed), or the uploader could not take it: its own
      // words, as an envelope's are. It stays `waiting`, so the next pass
      // offers it again — and a session already opened hands back its link.
      return _Refused(e.message ?? e.code);
    } finally {
      if (staged != null) await _discard(staged);
    }
  }

  Future<void> _discard(String uploadId) async {
    try {
      await uploader.discard(uploadId);
    } catch (e) {
      // A temporary file left behind costs disk, never a photo.
      debugPrint('camera sweep: a staged upload could not be deleted ($e)');
    }
  }

  // ── Upload results (S4) ────────────────────────────────────────────────────

  StreamSubscription<void>? _resultsWaiting;

  /// Listens for upload results, and records any that came back while
  /// nobody listened — the app was suspended, or not running at all.
  Future<void> attachUploads() {
    _resultsWaiting ??= uploader.resultsWaiting.listen(
      (_) => unawaited(drainUploads()),
      onError: (Object e) => debugPrint('camera sweep: upload results stopped ($e)'),
    );
    return drainUploads();
  }

  Future<void> close() async {
    await _resultsWaiting?.cancel();
    _resultsWaiting = null;
  }

  Future<void>? _draining;
  bool _drainAgain = false;

  /// Records every upload result waiting, then acknowledges it. A result
  /// whose ledger write fails is NOT acknowledged, so the next drain records
  /// it.
  Future<void> drainUploads() {
    final running = _draining;
    if (running != null) {
      _drainAgain = true;
      return running;
    }
    return _draining = _drain().whenComplete(() => _draining = null);
  }

  Future<void> _drain() async {
    do {
      _drainAgain = false;
      final List<SweepUploadResult> results;
      try {
        results = await uploader.finished();
      } catch (e) {
        debugPrint('camera sweep: upload results could not be read ($e)');
        return;
      }
      final recorded = <String>[];
      for (final r in results) {
        if (await _settleUpload(r)) recorded.add(r.uploadId);
      }
      if (recorded.isEmpty) continue;
      try {
        await uploader.acknowledge(recorded);
      } catch (e) {
        // Read again next time, and counted once (_counted).
        debugPrint('camera sweep: upload results could not be acknowledged ($e)');
      }
    } while (_drainAgain);
  }

  /// One result: landed is `ingested` in the ledger; anything else is the
  /// Swift uploader's sentence, on the card that asked or — automatic, or a
  /// result from an earlier launch — the screen's alert. true once recorded.
  Future<bool> _settleUpload(SweepUploadResult r) async {
    final id = r.localIdentifier;
    final mine = _uploads[id]?.uploadId == r.uploadId ? _uploads.remove(id) : null;
    if (mine == null) _inFlightElsewhere.remove(id);
    if (r.ok) {
      var recorded = true;
      try {
        await ledger.record(LedgerVerdict.ingested, id);
        if (_counted.add(r.uploadId)) _ingestedThisSession++;
      } catch (e) {
        // The photo IS in; only this phone's note of it is missing. Left
        // unacknowledged, so the next drain writes it — and if it never
        // does, the next pass asks the server, which answers "already here".
        debugPrint('camera sweep: ${r.uploadId} landed, but the ledger could not record it ($e)');
        recorded = false;
      }
      mine?.landed.complete(null);
      notifyListeners();
      return recorded;
    }
    final sentence = uploadFailureSentence(statusCode: r.statusCode, transportError: r.error);
    if (mine != null) {
      mine.landed.complete(sentence);
    } else {
      presentFailure(sentence, stopsSweep: false);
    }
    notifyListeners();
    return true;
  }

  /// A rendered copy the dry run measured, deleted: it is temporary.
  static Future<void> _drop(SweepRendered rendered) async {
    try {
      await File(rendered.path).delete();
    } on FileSystemException {
      // Already gone; the system clears tmp/ anyway.
    }
  }

  /// The capture instant the session carries, floored to the whole second
  /// from the exact Double the key read — what Swift's
  /// `ISO8601DateFormatter` printed. Not [SweepAsset.creationDate], which
  /// rounds to the microsecond and can cross into the next second.
  static DateTime? capturedAt(SweepAsset asset) {
    final s = asset.creationSeconds;
    return s == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(s.floor() * 1000, isUtc: true);
  }

  /// The name the session carries: the original's, with its extension made
  /// `.jpg` because the bytes are a rendered JPEG — or the key when the asset
  /// has no resource (Swift `ingest`).
  static String uploadFilename(SweepAsset asset) =>
      '${deletingPathExtension(asset.originalFilename ?? '${asset.assetKey}.jpg')}.jpg';

  /// `NSString.deletingPathExtension`, for a file name: the last component's
  /// extension goes when it has one — a dot that is neither the name's first
  /// character nor its last.
  @visibleForTesting
  static String deletingPathExtension(String name) {
    final slash = name.lastIndexOf('/');
    final dot = name.lastIndexOf('.');
    if (dot <= slash + 1 || dot == name.length - 1) return name;
    return name.substring(0, dot);
  }

  // ── The dry run ────────────────────────────────────────────────────────────

  /// What a pass would do, with nothing written: no ledger write (no
  /// verdict, no backfill flag, no change mark), no capture session, no PUT,
  /// no tray change. It always walks the whole library, and reads the key of
  /// every photo it examines, not only a candidate's: it is a rehearsal, and
  /// its entries are compared key by key. The text check runs and the JPEG is rendered (then
  /// deleted), so everything up to the upload is exercised. Whether a
  /// candidate is already filed is asked of Firestore by its asset key
  /// ([SweepEndpoints.findCapture]) — a photo the Swift app already swept
  /// must come back [DryRunOutcome.duplicateSettled].
  Future<SweepDryRun> dryRun() async {
    final run = SweepDryRun();
    try {
      final version = (await bridge.constants()).prefilterVersion;
      run.prefilterVersion = version;
      await _walk(version, (listing) async {
        run.entries.add(await _rehearse(listing));
      }, run);
    } on SweepAccessRefused catch (e) {
      run.refused = e;
    }
    return run;
  }

  Future<DryRunEntry> _rehearse(SweepListing listing) async {
    final asset = await bridge.identify(listing.localIdentifier);
    final exam = await bridge.examine(asset.localIdentifier);
    DryRunOutcome outcome;
    int? bytes;
    CaptureMatch? match;
    String? error;
    switch (exam.verdict) {
      case SweepVerdict.notLocallyAvailable:
        outcome = DryRunOutcome.wouldDefer;
      case SweepVerdict.noText:
        outcome = DryRunOutcome.wouldRecordNoText;
      case SweepVerdict.candidate:
        try {
          final rendered = await bridge.renderedJpeg(asset.localIdentifier);
          if (rendered == null) {
            outcome = DryRunOutcome.wouldDefer;
            break;
          }
          bytes = rendered.bytes;
          await _drop(rendered);
          match = await endpoints.findCapture(asset.assetKey);
          outcome = match == null
              ? (_toTray ? DryRunOutcome.wouldHoldForReview : DryRunOutcome.wouldCreate)
              : (const {'pending_upload', 'error'}.contains(match.status)
                  ? DryRunOutcome.duplicateWouldUpload
                  : DryRunOutcome.duplicateSettled);
        } catch (e) {
          outcome = DryRunOutcome.unknown;
          error = '$e';
        }
    }
    return DryRunEntry(
      asset: asset,
      examination: exam,
      outcome: outcome,
      renderedBytes: bytes,
      match: match,
      error: error,
    );
  }

  // ── Sentences (the Swift app's, verbatim) ──────────────────────────────────

  static final iCloudSentence = SweepWords.ios.deferredSentence;

  /// What to say about a PUT that did not land (Swift
  /// `CameraSweepUploader.failureSentence`, "sweep" made "look" in D). A 403 is overwhelmingly a signed
  /// URL that expired, which is a wait, not a loss. Every branch names the
  /// retry, because there is one: a failure leaves the photo `waiting`.
  static String uploadFailureSentence({String? transportError, required int statusCode}) {
    if (transportError != null) {
      return 'A photo could not be uploaded — $transportError '
          'The next look tries again.';
    }
    if (statusCode == 403) {
      return 'A photo’s upload link expired before the transfer finished. '
          'The next look starts it again.';
    }
    return 'A photo could not be uploaded (HTTP $statusCode). '
        'The next look tries again.';
  }
}

/// What the sweep needs from the network, as one seam: the session
/// (`Api.createCaptureSession`) and the "already in NoteLetter" read. The
/// bare signed PUT is the background uploader's (S4, [SweepUploader]).
abstract class SweepEndpoints {
  Future<Map<String, dynamic>> openSession({
    required String assetKey,
    required String filename,
    required String mimeType,
    required int size,
    DateTime? capturedAt,
  });

  Future<CaptureMatch?> findCapture(String assetKey);
}

/// The real ones: the session through `Api` (every request is built in
/// `api.dart`), and the read through [FirestoreService.findCapture].
class LiveSweepEndpoints implements SweepEndpoints {
  const LiveSweepEndpoints();

  @override
  Future<Map<String, dynamic>> openSession({
    required String assetKey,
    required String filename,
    required String mimeType,
    required int size,
    DateTime? capturedAt,
  }) =>
      Api.instance.createCaptureSession(
        assetKey: assetKey,
        filename: filename,
        mimeType: mimeType,
        size: size,
        capturedAt: capturedAt,
      );

  @override
  Future<CaptureMatch?> findCapture(String assetKey) =>
      FirestoreService.instance.findCapture(assetKey);
}

/// `fn_create_capture_session`'s answer, read (Swift `CameraSweepAPI.session`).
class CaptureSession {
  const CaptureSession({
    required this.docId,
    required this.duplicate,
    required this.uploadUrl,
    required this.existingStatus,
  });

  final String docId;
  final bool duplicate;

  /// Present on a fresh create, and on a replay whose document never received
  /// bytes (`pending_upload`/`error`). Null: nothing to upload.
  final String? uploadUrl;

  /// The existing document's status; null on a fresh create.
  final String? existingStatus;

  /// No `duplicate` (or no `docId`) is a backend that ignored `assetKey`:
  /// [DedupeUnsupported], and the sweep stops rather than re-ingest the
  /// library.
  ///
  /// Stricter than Swift in one place, on purpose: a FRESH session
  /// (`duplicate: false`) without an upload URL is refused for that photo.
  /// Swift read it as "already landed" and recorded the photo ingested, so
  /// its document would have sat at `pending_upload` with no pass ever
  /// coming back for it.
  factory CaptureSession.fromResponse(Map<String, dynamic> r) {
    final docId = r['docId'];
    final duplicate = r['duplicate'];
    if (docId is! String || duplicate is! bool) throw const DedupeUnsupported();
    final url = r['uploadUrl'];
    if (url != null && url is! String) {
      throw const FormatException('The capture session’s upload link could not be read.');
    }
    if (!duplicate && url == null) {
      throw const FormatException('The capture session came back without an upload link.');
    }
    final status = r['status'];
    return CaptureSession(
      docId: docId,
      duplicate: duplicate,
      uploadUrl: url as String?,
      existingStatus: status is String ? status : null,
    );
  }
}

/// The backend answered without `duplicate`: a deployment older than 2.18.0
/// that ignored `assetKey` and minted a fresh document per call (spec §6).
class DedupeUnsupported implements Exception {
  const DedupeUnsupported();

  /// The Swift app's sentence, "sweeping" made "looking through them" in D
  /// (5.43.0, ADR-198 decision 8).
  static const message =
      "This version of NoteLetter's server doesn't recognize camera-roll photos yet, "
      'so looking through them would add the same photos again. Try again after '
      'the next update.';

  String get sentence => message;

  @override
  String toString() => message;
}

/// Counts both walks share.
abstract class SweepTally {
  /// Assets examined (the cap counts these).
  int handled = 0;

  /// Skipped: a verdict that still stands.
  int settled = 0;

  /// Skipped: a burst frame the system did not pick.
  int nonRepresentative = 0;

  /// Skipped: its upload is on its way (S4).
  int inFlight = 0;

  /// Set when the library was not fully readable; nothing was enumerated.
  SweepAccessRefused? refused;
}

/// What one pass did.
class SweepPass extends SweepTally {
  int noText = 0;
  int deferred = 0;
  int toTray = 0;

  /// Already in the tray from an earlier pass: counted, not examined again.
  int held = 0;

  /// In: landed, or already on the server. Automatic mode.
  int ingested = 0;

  /// Handed to the background uploader (automatic mode). Each then lands
  /// ([ingested]) or fails ([failed]) — before the pass ends, unless it was
  /// stopped.
  int uploading = 0;

  /// Nothing ran: the sweep was halted (background time ran out, or the app
  /// is away with no background task).
  bool halted = false;

  /// Read only what changed since the change mark, not the whole library
  /// (spec §7).
  bool fromChangeToken = false;

  /// Automatic mode's refusals, by `localIdentifier`.
  final Map<String, String> failed = {};

  final List<Future<void>> _landings = [];

  @override
  String toString() => 'SweepPass(handled $handled, settled $settled, '
      'nonRepresentative $nonRepresentative, inFlight $inFlight, noText $noText, '
      'deferred $deferred, toTray $toTray, held $held, uploading $uploading, '
      'ingested $ingested, failed ${failed.length}'
      '${fromChangeToken ? ', from the change token' : ''}'
      '${halted ? ', halted' : ''}'
      '${refused == null ? '' : ', refused ${refused!.access.name}'})';
}

/// A card handed off; [settled] completes once it left the tray or kept its
/// sentence.
class _Card {
  const _Card(this.settled);
  final Future<void> settled;
}

/// An upload this launch handed off.
class _Upload {
  _Upload(this.uploadId);
  final String uploadId;

  /// null when it landed; the sentence when it did not.
  final Completer<String?> landed = Completer<String?>();
}

/// What became of one photo's ingest.
sealed class _Ingest {
  const _Ingest();
}

/// In: the server already had its bytes, and the ledger says so.
class _Landed extends _Ingest {
  const _Landed();
}

/// On its way; [landed] says how it ended.
class _Uploading extends _Ingest {
  const _Uploading(this.landed);
  final Future<String?> landed;
}

class _Refused extends _Ingest {
  const _Refused(this.sentence);
  final String sentence;
}

/// A pass told to stop, before anything was sent.
class _NotStarted extends _Ingest {
  const _NotStarted();
}

enum DryRunOutcome {
  /// Would be recorded no-text at this pre-filter version.
  wouldRecordNoText,

  /// Not on the device; would be deferred, never called no-text.
  wouldDefer,

  /// A candidate with no document under its key, which this pass would put
  /// in the review tray (review mode, or the first backfill).
  wouldHoldForReview,

  /// A candidate with no document under its key, which this pass would file.
  wouldCreate,

  /// Already filed and its bytes landed: a pass would record it and upload
  /// nothing.
  duplicateSettled,

  /// Already has a document that never received bytes: a pass would upload
  /// against the replay's link.
  duplicateWouldUpload,

  /// The render or the read failed; see [DryRunEntry.error].
  unknown,
}

class DryRunEntry {
  const DryRunEntry({
    required this.asset,
    required this.examination,
    required this.outcome,
    this.renderedBytes,
    this.match,
    this.error,
  });

  final SweepAsset asset;
  final SweepExamination examination;
  final DryRunOutcome outcome;
  final int? renderedBytes;
  final CaptureMatch? match;
  final String? error;

  @override
  String toString() => '${asset.localIdentifier} ${asset.assetKey} '
      '"${asset.originalFilename}" ${examination.verdict.name}'
      '${examination.characters == null ? '' : ' ${examination.characters} chars'}'
      ' -> ${outcome.name}'
      '${renderedBytes == null ? '' : ' (${renderedBytes}B jpeg)'}'
      '${match == null ? '' : ' ${match!.docId} ${match!.status}'}'
      '${error == null ? '' : ' error: $error'}';
}

/// What a pass would do.
class SweepDryRun extends SweepTally {
  int? prefilterVersion;
  final List<DryRunEntry> entries = [];

  int count(DryRunOutcome o) => entries.where((e) => e.outcome == o).length;

  @override
  String toString() {
    final by = {
      for (final o in DryRunOutcome.values)
        if (count(o) > 0) o.name: count(o)
    };
    return 'SweepDryRun(handled $handled, settled $settled, '
        'nonRepresentative $nonRepresentative, $by'
        '${refused == null ? '' : ', refused ${refused!.access.name}'})';
  }
}
