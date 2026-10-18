import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

import 'api.dart';
import 'api_service.dart';
import 'camera_sweep_bridge.dart';
import 'firestore_service.dart';
import 'sweep_ledger.dart';

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
/// foreground (`lib/state/camera_sweep_host.dart`). Not here yet: the
/// background task and background uploads (S4). The PUT is foreground and
/// awaited until S4.
class CameraSweepService extends ChangeNotifier {
  CameraSweepService({
    required this.bridge,
    required this.ledger,
    required this.endpoints,
  });

  final CameraSweepBridge bridge;
  final SweepLedger ledger;
  final SweepEndpoints endpoints;

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

  /// Runs the sweep only if the user turned it on and the library is fully
  /// readable; otherwise does nothing. Safe on every launch and sign-in.
  Future<SweepPass?> startIfEnabled() async {
    if (!ledger.enabled) return null;
    if (await bridge.access() != SweepAccess.granted) return null;
    return sweep();
  }

  /// One pass. A second call while one runs gets the running one.
  Future<SweepPass> sweep() {
    final running = _running;
    if (running != null) return running;
    _cancelled = false;
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

  /// Stops the pass at the next asset.
  void stop() {
    _cancelled = true;
  }

  Future<SweepPass> _runSweep() async {
    final pass = SweepPass();
    try {
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
    } on SweepAccessRefused catch (e) {
      _accessRefused = e;
      pass.refused = e;
    }
    return pass;
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
          final sentence = await _ingest(asset);
          if (sentence == null) {
            pass.ingested++;
          } else {
            pass.failed[asset.localIdentifier] = sentence;
            // Nobody is looking at a tray, so the sentence goes to the
            // screen's own alert — and it did not stop the sweep, unless the
            // dedupe branch said so.
            if (!_errorStoppedSweep) presentFailure(sentence, stopsSweep: false);
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

  /// The card leaves the tray only once the photo is in (Swift D5). On a
  /// refusal it stays, carrying the reason.
  Future<void> approve(SweepAsset asset) async {
    _candidateErrors.remove(asset.localIdentifier);
    notifyListeners();
    record(await _ingest(asset), asset.localIdentifier);
  }

  /// A snapshot, because settling mutates the tray. One refusal costs one
  /// photo; a refusal that ends the sweep ends this too.
  Future<void> approveAll() async {
    for (final asset in List.of(_candidates)) {
      if (_errorStoppedSweep) return;
      await approve(asset);
    }
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

  /// Null when the photo is in (the bytes landed, or the server already had
  /// them); otherwise the sentence saying why not. It sets [errorMessage]
  /// only where the failure ends the whole sweep: who renders a refusal
  /// depends on who asked for it, a card or the automatic pass's alert.
  Future<String?> _ingest(SweepAsset asset) async {
    final id = asset.localIdentifier;
    try {
      final rendered = await bridge.renderedJpeg(id);
      if (rendered == null) {
        await ledger.record(LedgerVerdict.deferredNotLocal, id);
        return iCloudSentence;
      }
      final bytes = await _take(rendered);
      // Requested immediately before the PUT: the signed URL lasts 15
      // minutes, so sessions are never taken out ahead of time.
      final session = CaptureSession.fromResponse(await endpoints.openSession(
        assetKey: asset.assetKey,
        filename: uploadFilename(asset),
        mimeType: uploadMimeType,
        size: bytes.length,
        capturedAt: capturedAt(asset),
      ));
      final url = session.uploadUrl;
      if (url != null) {
        // A fresh session, or a replay whose document never received bytes
        // (`pending_upload`/`error`): upload against it (spec §6). Skipping
        // the replay's URL would strand the document at pending_upload.
        try {
          await endpoints.putSigned(url, bytes, uploadMimeType);
        } on ApiException catch (e) {
          // Nothing is recorded, so the next pass examines the photo again
          // and the replay hands back a fresh link.
          return uploadFailureSentence(
            statusCode: e.statusCode,
            transportError: e.statusCode == 0 ? e.message : null,
          );
        }
      }
      // `uploadUrl: null` is the bytes having already landed: record and move
      // on — the whole point of the server-side key.
      await ledger.record(LedgerVerdict.ingested, id);
      _ingestedThisSession++;
      notifyListeners();
      return null;
    } on DedupeUnsupported catch (e) {
      // The one failure that ends the sweep: continuing would re-ingest the
      // library, one duplicate at a time, with no request failing.
      presentFailure(e.sentence, stopsSweep: true);
      stop();
      return e.sentence;
    } on SweepAccessRefused catch (e) {
      _accessRefused = e;
      stop();
      return e.sentence;
    } on ApiException catch (e) {
      return e.message;
    } on FormatException catch (e) {
      return e.message;
    } on PlatformException catch (e) {
      // The bridge could not render the photo (deleted since the pass found
      // it, or a write failed): its own words, as an envelope's are.
      return e.message ?? e.code;
    }
  }

  /// The rendered file's bytes, and the file gone: it is a temporary copy.
  static Future<Uint8List> _take(SweepRendered rendered) async {
    final file = File(rendered.path);
    try {
      return await file.readAsBytes();
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Already gone; the system clears tmp/ anyway.
      }
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
          bytes = (await _take(rendered)).length;
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

  static const iCloudSentence =
      'This photo hasn’t finished downloading from iCloud. '
      'It stays here and the next sweep will try again.';

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
/// (`Api.createCaptureSession`), the bare signed PUT (INV-08: no
/// Authorization header), and the dry run's read.
abstract class SweepEndpoints {
  Future<Map<String, dynamic>> openSession({
    required String assetKey,
    required String filename,
    required String mimeType,
    required int size,
    DateTime? capturedAt,
  });

  Future<void> putSigned(String url, Uint8List bytes, String mimeType);

  Future<CaptureMatch?> findCapture(String assetKey);
}

/// The real ones: the session through `Api` (every request is built in
/// `api.dart`), the bare PUT through [ApiService.putBytes] (no Authorization
/// header, the declared Content-Type — INV-08, as the image-set upload does),
/// and the dry run's read through [FirestoreService.findCapture].
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
  Future<void> putSigned(String url, Uint8List bytes, String mimeType) =>
      ApiService.instance.putBytes(url, bytes, mimeType);

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
  int ingested = 0;

  /// Automatic mode's refusals, by `localIdentifier`.
  final Map<String, String> failed = {};

  @override
  String toString() => 'SweepPass(handled $handled, settled $settled, '
      'nonRepresentative $nonRepresentative, noText $noText, deferred $deferred, '
      'toTray $toTray, held $held, ingested $ingested, failed ${failed.length}'
      '${refused == null ? '' : ', refused ${refused!.access.name}'})';
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
