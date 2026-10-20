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
/// either hold it in the review tray or — automatic mode, once the first
/// backfill is done — render the JPEG, open a capture session and PUT it.
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
  /// candidate gets no verdict until it is approved or dismissed.
  List<SweepAsset> get candidates => List.unmodifiable(_candidates);

  bool _isSweeping = false;
  bool get isSweeping => _isSweeping;

  int _examined = 0;
  int get examined => _examined;

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

  /// The alert's title is a CLAIM (Swift D5).
  String get failureTitle =>
      _errorStoppedSweep ? 'Sweep stopped' : 'A photo couldn’t be added';

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
      final version = (await bridge.constants()).prefilterVersion;
      // One newest-first walk covers both passes: photos taken since the
      // last run sort to the front, and everything the ledger has a standing
      // verdict for is skipped without touching a pixel, which is what makes
      // re-walking from the top cheap enough to do every time.
      await _walk(version, (asset) async {
        await _examine(asset, pass);
      }, pass);
      if (pass.handled < backfillBatchLimit && !_cancelled && !_errorStoppedSweep) {
        // Ran out of work before the cap: nothing older is waiting.
        await ledger.setBackfillComplete(true);
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
    return pass;
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

  /// The walk both the pass and the dry run take. [onAsset] runs for each
  /// asset that needs examining, at most [backfillBatchLimit] times.
  Future<void> _walk(
    int prefilterVersion,
    Future<void> Function(SweepAsset asset) onAsset,
    SweepTally tally, {
    bool moveCursor = true,
  }) async {
    var offset = 0;
    while (true) {
      final page = await bridge.fetchImages(
        since: ledger.backfillStart,
        offset: offset,
        limit: CameraSweepBridge.defaultPageSize,
      );
      for (final asset in page.assets) {
        if (_cancelled || _errorStoppedSweep) return;
        if (tally.handled >= backfillBatchLimit) return;
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
        final at = asset.creationDate;
        // Per asset, so a kill mid-batch resumes rather than restarts.
        if (moveCursor && at != null) await ledger.setCursor(at);
      }
      offset += page.assets.length;
      if (page.assets.isEmpty || offset >= page.total) return;
    }
  }

  Future<void> _examine(SweepAsset asset, SweepPass pass) async {
    // Already waiting on the user: its verdict cannot have changed, so the
    // text check is not run again. It still counts toward the cap, as in
    // Swift — a tray of 200 is the first backfill's bound. (Swift re-ran
    // Vision on every card each pass; S3 runs a pass on every library change,
    // and a phone syncing iCloud changes its library constantly.)
    if (_candidates.any((c) => c.localIdentifier == asset.localIdentifier)) {
      pass.held++;
      return;
    }
    final exam = await bridge.examine(asset.localIdentifier);
    _examined++;
    switch (exam.verdict) {
      case SweepVerdict.notLocallyAvailable:
        // Never "no text": that verdict would be permanent and wrong.
        await ledger.record(LedgerVerdict.deferredNotLocal, asset.localIdentifier);
        pass.deferred++;
      case SweepVerdict.noText:
        await ledger.record(
            LedgerVerdict.noText(exam.prefilterVersion), asset.localIdentifier);
        pass.noText++;
      case SweepVerdict.candidate:
        if (_toTray) {
          // The first backfill always goes through review, whatever mode the
          // user picked, because it is the pass that surfaces everything at
          // once (spec §3). Whether its photo is already in NoteLetter is
          // asked first, so the card arrives saying so.
          await _lookUp(asset);
          _candidates.add(asset);
          pass.toTray++;
        } else {
          final id = asset.localIdentifier;
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
      // words, as an envelope's are. Nothing is recorded, so the next pass
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
  /// verdict, no cursor, no backfill flag), no capture session, no PUT, no
  /// tray change. The text check runs and the JPEG is rendered (then
  /// deleted), so everything up to the upload is exercised. Whether a
  /// candidate is already filed is asked of Firestore by its asset key
  /// ([SweepEndpoints.findCapture]) — a photo the Swift app already swept
  /// must come back [DryRunOutcome.duplicateSettled].
  Future<SweepDryRun> dryRun() async {
    final run = SweepDryRun();
    try {
      final version = (await bridge.constants()).prefilterVersion;
      run.prefilterVersion = version;
      await _walk(version, (asset) async {
        run.entries.add(await _rehearse(asset));
      }, run, moveCursor: false);
    } on SweepAccessRefused catch (e) {
      run.refused = e;
    }
    return run;
  }

  Future<DryRunEntry> _rehearse(SweepAsset asset) async {
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
  /// `CameraSweepUploader.failureSentence`). A 403 is overwhelmingly a signed
  /// URL that expired, which is a wait, not a loss. Every branch names the
  /// retry, because there is one: nothing is recorded on failure.
  static String uploadFailureSentence({String? transportError, required int statusCode}) {
    if (transportError != null) {
      return 'A photo could not be uploaded — $transportError '
          'The next sweep tries again.';
    }
    if (statusCode == 403) {
      return 'A photo’s upload link expired before the transfer finished. '
          'The next sweep starts it again.';
    }
    return 'A photo could not be uploaded (HTTP $statusCode). '
        'The next sweep tries again.';
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

  /// The Swift app's sentence, verbatim.
  static const message =
      "This version of NoteLetter's server doesn't recognize camera-roll photos yet, "
      'so sweeping would add the same photos again. Try again after the next update.';

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

  /// Automatic mode's refusals, by `localIdentifier`.
  final Map<String, String> failed = {};

  final List<Future<void>> _landings = [];

  @override
  String toString() => 'SweepPass(handled $handled, settled $settled, '
      'nonRepresentative $nonRepresentative, inFlight $inFlight, noText $noText, '
      'deferred $deferred, toTray $toTray, held $held, uploading $uploading, '
      'ingested $ingested, failed ${failed.length}'
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
