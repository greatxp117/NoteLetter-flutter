import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/camera_sweep_bridge.dart';
import '../../services/camera_sweep_service.dart';
import '../../services/sweep_ledger.dart';
import '../../state/camera_sweep_host.dart';
import '../../widgets/kit/kit.dart';

// ── The camera roll in direction D (5.43.0, ADR-198; F-146) ─────────────────
//
// `screens/sources.md` §Camera roll: one row at the head of the Library's
// Correspondence ([CameraRollRow]); a flow over the app for the four-step
// setup, Looking back, the one-at-a-time review and the end page
// ([CameraRollFlow]); and the settings panel the row's *Settings* opens
// ([CameraRollSettings]). Built on today's signals and no others
// (`features/camera-roll-sweep.md` §9): the pre-filter's verdict and a
// candidate's screenshot flag, the mode, the start date and the library's
// count for it, the ledger and the tray, the walk, access, each filing's
// outcome, and when the last pass ended. The pre-filter, the ledger, the
// uploader and the background work are the sweep's, unchanged.
//
// Until 5.43.0 this was Settings → Camera roll (`/settings/camera-roll`) and
// Sources' tray section "From your camera roll" (F-125 S3).

/// The camera roll's copy, verbatim from `screens/sources.md` §Camera roll
/// (ADR-198's adapted sentences; the prototype's where ADR-198 kept them).
class CameraRollCopy {
  CameraRollCopy._();

  static const name = 'Camera roll';
  static const folio = 'Correspondence · Camera roll';

  // The row.
  static const rowOff = 'Pages, screenshots and notes from your photos';
  static const rowNoAccess = 'NoteLetter can’t see your photos';
  static const rowUnreadable =
      'This phone’s camera roll settings could not be read.';
  static String rowLooking(int n, int total) =>
      'Looking back · ${kitThousands(n)} of ${kitThousands(total)}';
  static String rowWaiting(int n) => '${kitThousands(n)} waiting for your review';
  static String rowOn(int n) => 'On · ${kitThousands(n)} taken in';

  // Setup.
  static String step(int n) => 'Camera roll · $n of 4';
  static const introTitle = 'The Pages in Your Camera Roll';
  static const introStand =
      'Most of us photograph what we mean to read later. NoteLetter can look '
      'through your photos, keep the ones worth reading, and file them with the '
      'rest of your library.';
  static const introLabel = 'How it reads your photos';
  static const introRows = [
    (
      'On your phone first',
      'Each photo is read here, on this phone. Nothing is uploaded to decide '
          'whether to keep it.',
    ),
    (
      'Only what it keeps leaves',
      'Screenshots, and photos with enough text in them to read, are uploaded '
          'and indexed. Photos without readable text stay where they are.',
    ),
    (
      'Nothing filed behind your back',
      'What the look back finds waits for you to file or pass over. After '
          'that, new photos are filed on their own or wait for you, as you '
          'choose.',
    ),
  ];
  static const accessTitle = 'Let NoteLetter See Your Photos';
  static const accessStand =
      'NoteLetter needs your whole photo library to look through it. With only '
      'the photos you pick, it would quietly find almost nothing.';
  static const allowAccess = 'Allow access';
  static const openSettings = 'Open Settings';
  static const whatTitle = 'What to Take In';
  static const whatStand =
      'Screenshots, and photos with enough text in them to read. Only a '
      'fraction of your photos have any; the rest are never uploaded.';
  static const keptLabel = 'Kept if it has text';
  static const keptCards =
      'A card, an ID or a receipt has text too, so it is kept like a page. To '
      'see each photo before it is sent, choose Ask me first in the next step.';
  static const reachLabel = 'Start by looking back';
  static const reaches = {
    SweepReach.fromNow: 'From now on',
    SweepReach.month: 'The last month',
    SweepReach.year: 'The last year',
    SweepReach.everything: 'Everything',
  };
  static String photos(int n) => '${kitThousands(n)} ${n == 1 ? 'photo' : 'photos'}';
  static const whereTitle = 'Where It Goes';
  static const whereStand =
      'Each photo NoteLetter keeps is read and shelved like anything you add. '
      'It can file them on its own, or ask you first.';
  static const modeLabel = 'When it keeps a photo';
  static const automatically = 'Automatically';
  static const askFirst = 'Ask me first';
  static const automaticNote =
      'It files each one the next time NoteLetter opens, or when your phone '
      'gives it a moment in the background.';
  static const askNote =
      'Each one waits for you, and nothing is sent until you file it.';
  static const lookBackNote =
      'The look back waits for you either way: it finds everything at once, so '
      'it’s worth a look before anything is sent.';
  static const startLooking = 'Start looking back';
  static const turnItOn = 'Turn it on';
  static const continueLabel = 'Continue';
  static const notNow = 'Not now';
  static const back = 'Back';

  // Looking back.
  static const lookingHead = 'Camera roll · Looking back';
  static String lookingTitle(SweepReach? reach, DateTime start) => switch (reach) {
    SweepReach.month => 'Looking Through the Last Month',
    SweepReach.year => 'Looking Through the Last Year',
    SweepReach.everything => 'Looking Through Everything',
    SweepReach.fromNow || null => 'Looking Back to ${kitDayMonth(start, year: true)}',
  };
  static const lookingStand =
      'Read on this phone, a few hundred at a time. Keep using NoteLetter; if '
      'it closes, the look back picks up where it left off.';
  static const cappedStand =
      'Read on this phone, a few hundred at a time. The next few hundred are '
      'read the next time NoteLetter opens.';
  static const trayFullStand =
      'Read on this phone, a few hundred at a time. The next few hundred are '
      'read once you have reviewed these.';
  static String ofPhotos(int total) => 'of ${kitThousands(total)} photos';
  static const forReview = 'for your review';
  static const passedOver = 'passed over';
  static const justFound = 'Just found';
  static const screenshot = 'Screenshot';
  static const photoWithText = 'Photo with text';
  static String taken(DateTime d) => 'Taken ${kitDayMonth(d)}';
  static const forYourReview = 'For your review';
  static const goToLibrary = 'Go to the library';
  static String reviewNow(int n) => n == 1 ? 'Review it now' : 'Review them now';
  static const done = 'Done';

  // Review.
  static String reviewHead(int k, int n) => 'Camera roll · Review · $k of $n';
  static const reviewHeadEnd = 'Camera roll · Review';
  static String summary(int filed, int waiting, int passed) =>
      'Filed ${kitThousands(filed)} · Waiting ${kitThousands(waiting)} · '
      'Passed over ${kitThousands(passed)}';
  static String takenOn(DateTime d) => 'Taken on ${kitDayMonth(d)}';
  static const alreadyIn = 'Already in NoteLetter';
  static const lookBackKeeps =
      'The look back keeps everything it finds for you to see first.';
  static const youAsked = 'You asked to see each photo before it is sent.';
  static const filingLine =
      'Once it is filed, NoteLetter reads it and shelves it as it does anything '
      'you add.';
  static const fileIt = 'File it';
  static String fileAll(int n) => 'File all ${kitThousands(n)}';
  static const passOver = 'Pass over';

  // The end.
  static const endFolio = 'Correspondence · Camera roll · On';
  static const endTitle = 'Everything Is Filed';
  static String endCounts(int filed, int passed) =>
      '${kitThousands(filed)} ${filed == 1 ? 'photo is' : 'photos are'} in your '
      'library and ${kitThousands(passed)} ${passed == 1 ? 'was' : 'were'} passed '
      'over.';
  static const endWalkLeft =
      'The look back goes on from here, a few hundred photos at a time.';
  static const endAutomatic =
      'New photos are looked at the next time NoteLetter opens, or when your '
      'phone gives it a moment, and the ones it keeps are filed.';
  static const endAsk =
      'New photos are looked at the next time NoteLetter opens, or when your '
      'phone gives it a moment, and the ones it keeps wait for you in the '
      'library.';

  // The panel.
  static const panelTitle = 'Camera roll settings';
  static String lookedAgo(String ago) => 'On · looked $ago';
  static const on = 'On';
  static String lookingThrough(int n) =>
      'Looking through your photos… ${kitThousands(n)} so far';
  static const takesInLabel = 'Takes in';
  static const takesIn =
      'Screenshots, and photos with enough text in them to read. Everything '
      'else stays on this phone.';
  static const takesInCards =
      'A card, an ID or a receipt has text too, so it is kept like a page. Ask '
      'me first shows you each one before it is sent.';
  static const lookingBackLabel = 'Looking back';
  static String since(DateTime d) => 'Since ${kitDayMonth(d, year: true)}';
  static const reachDone = ' · done';
  static const lookFurther = 'Look further back';
  static const startOver = 'Start over';
  static const startOverTitle = 'Start the camera roll over?';
  static const startOverBody =
      'This phone forgets which photos it has already looked at, so the next '
      'look back reads every photo from your start date again, and any you '
      'passed over will be offered again.';
  static const startOverBody2 =
      'Nothing already in your library is removed or added twice: NoteLetter '
      'recognises a photo it already has.';
  static const keepProgress = 'Keep my progress';
  static const lookNow = 'Look now';
  static const turnOff = 'Turn off the camera roll';
  static const turnOffTitle = 'Turn off the camera roll?';
  static const turnOffBody =
      'NoteLetter stops looking at your photos. What it has already filed '
      'stays in your library.';
  static const turnOffConfirm = 'Turn off';
  static const keepItOn = 'Keep it on';
  static const checkAgain = 'Check again';
  static String deferred(String title, int n) => '$title · ${kitThousands(n)}';
}

/// What a waiting photo is, as the pre-filter measured it — nothing more.
String cameraKind(SweepAsset a) =>
    a.isScreenshot ? CameraRollCopy.screenshot : CameraRollCopy.photoWithText;

/// The reach as set, for the panel and the Looking back folio: a D reach, or
/// "Since {date}" for a start date set before D.
String cameraReach(SweepLedger ledger) {
  final r = ledger.reach;
  return r == null ? CameraRollCopy.since(ledger.backfillStart) : CameraRollCopy.reaches[r]!;
}

// ── The row ─────────────────────────────────────────────────────────────────

/// The camera roll's row, first in Correspondence (sources.md §Camera roll,
/// *The row*): the camera glyph, *Camera roll*, a line and one action — the
/// first state that holds deciding it. Drawn only where there is a photo
/// library this client can look through. [onSettings] opens the panel.
class CameraRollRow extends StatelessWidget {
  final VoidCallback onSettings;

  const CameraRollRow({super.key, required this.onSettings});

  @override
  Widget build(BuildContext context) {
    final host = context.watch<CameraSweepHost?>();
    if (!CameraSweepBridge.isAvailable || host == null || !host.available) {
      return const SizedBox.shrink();
    }
    if (host.loadError != null) {
      return const KitServiceRow(
        glyph: Icons.photo_camera_outlined,
        name: CameraRollCopy.name,
        failure: KitFailureInline(CameraRollCopy.rowUnreadable, dense: true),
      );
    }
    final ledger = host.ledger, service = host.service;
    if (ledger == null || service == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, service]),
      builder: (context, _) {
        final waiting = service.candidates.length;
        final total = service.walkTotal ?? host.inRange;
        final position = service.walkPosition;
        KitLibAct settings() => KitLibAct('Settings', onTap: onSettings);
        final (String line, bool critical, Widget action) = !ledger.enabled
            ? (
                CameraRollCopy.rowOff,
                false,
                KitLibAct(
                  'Connect',
                  strong: true,
                  onTap: () => CameraRollFlow.open(context, CameraRollStep.intro),
                ),
              )
            : service.errorMessage != null
            ? (service.failureTitle, true, settings())
            : host.access != null && host.access != SweepAccess.granted
            ? (CameraRollCopy.rowNoAccess, false, settings())
            : service.isSweeping && !ledger.backfillComplete
            ? (
                position != null && total != null
                    ? CameraRollCopy.rowLooking(position, total)
                    : CameraRollCopy.lookingBackLabel,
                false,
                KitLibAct(
                  'Open',
                  onTap: () =>
                      CameraRollFlow.open(context, CameraRollStep.lookingBack),
                ),
              )
            : waiting > 0
            ? (
                CameraRollCopy.rowWaiting(waiting),
                false,
                KitLibAct(
                  'Review',
                  strong: true,
                  onTap: () => CameraRollFlow.open(context, CameraRollStep.review),
                ),
              )
            : (CameraRollCopy.rowOn(ledger.ingestedCount), false, settings());
        // `.lx-svc.on`: the positive dot while it looks, waits or is on —
        // never on a failure or lost access, which are not "on".
        final on = ledger.enabled &&
            service.errorMessage == null &&
            (host.access == null || host.access == SweepAccess.granted);
        return KitServiceRow(
          key: const ValueKey('camera-roll-row'),
          glyph: Icons.photo_camera_outlined,
          name: CameraRollCopy.name,
          line: line,
          on: on,
          critical: critical,
          action: action,
        );
      },
    );
  }
}

// ── The flow ────────────────────────────────────────────────────────────────

enum CameraRollStep { intro, access, what, where, lookingBack, review }

/// The flow over the app (sources.md §Camera roll): the setup's four steps,
/// Looking back, the review one photo at a time, and the end page. Opened
/// by the row (*Connect*, *Open*, *Review*), and by the panel's *Look
/// further back*. Closing it never stops a pass.
class CameraRollFlow extends StatefulWidget {
  final CameraRollStep start;

  const CameraRollFlow({super.key, this.start = CameraRollStep.intro});

  static Future<void> open(BuildContext context, CameraRollStep start) =>
      KitFlowFrame.show<void>(
        context,
        builder: (_) => CameraRollFlow(start: start),
      );

  @override
  State<CameraRollFlow> createState() => _CameraRollFlowState();
}

class _CameraRollFlowState extends State<CameraRollFlow> {
  late CameraRollStep _step = widget.start;
  final ScrollController _scroll = ScrollController();

  // Setup.
  SweepReach _reach = SweepReach.year;
  SweepMode? _mode;
  final Map<SweepReach, int?> _counts = {};
  bool _counted = false;
  String? _refusal;
  bool _asking = false;
  bool _turning = false;
  String? _writeFailure;

  // Review: every photo this review has shown, so "k of N" counts the ones
  // that left as well as those still waiting.
  final Set<String> _seen = {};
  String? _filing;
  bool _filingAll = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _to(CameraRollStep s) {
    setState(() {
      _step = s;
      _writeFailure = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (s == CameraRollStep.what && !_counted) unawaited(_count());
  }

  void _close() => Navigator.of(context).pop();

  CameraSweepHost get _host => context.read<CameraSweepHost>();

  /// Step 3's counts: the library's own, for each reach's start date — never
  /// estimated, and not drawn until counted.
  Future<void> _count() async {
    _counted = true;
    final host = _host;
    for (final r in [SweepReach.month, SweepReach.year, SweepReach.everything]) {
      final start = await host.startFor(r);
      final n = start == null ? null : await host.countSince(start);
      if (!mounted) return;
      setState(() => _counts[r] = n);
    }
  }

  /// *Allow access*: the photo prompt fires here and nowhere else (feature
  /// §1). Full access goes on; partial or no access stays, saying why.
  Future<void> _allow() async {
    setState(() {
      _asking = true;
      _refusal = null;
    });
    SweepAccess? got;
    try {
      got = await _host.requestAccess();
    } catch (e) {
      debugPrint('camera roll: photo access could not be asked ($e)');
    }
    if (!mounted) return;
    setState(() {
      _asking = false;
      _refusal = switch (got) {
        SweepAccess.granted => null,
        SweepAccess.limited => SweepAccessRefused.limitedSentence,
        _ => SweepAccessRefused.deniedAtSetupSentence,
      };
    });
    if (got == SweepAccess.granted) _to(CameraRollStep.what);
  }

  /// The setup's last button: on, the mode and the start date, written
  /// before anything moves. Then a pass, and Looking back (*From now on*
  /// closes the flow).
  Future<void> _turnOn(SweepMode mode) async {
    setState(() {
      _turning = true;
      _writeFailure = null;
    });
    final host = _host;
    try {
      final start = await host.startFor(_reach);
      if (start == null) throw StateError('no start date for $_reach');
      await host.turnOn(mode: mode, start: start, reach: _reach);
    } catch (e) {
      debugPrint('camera roll: not turned on ($e)');
      if (mounted) {
        setState(() {
          _turning = false;
          _writeFailure = CameraSweepHost.notSaved;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _turning = false);
    if (_reach == SweepReach.fromNow) {
      _close();
    } else {
      _to(CameraRollStep.lookingBack);
    }
  }

  Future<void> _file(CameraSweepService svc, SweepAsset a) async {
    setState(() => _filing = a.localIdentifier);
    try {
      await svc.approve(a);
    } finally {
      if (mounted) setState(() => _filing = null);
    }
  }

  Future<void> _fileAll(CameraSweepService svc) async {
    setState(() => _filingAll = true);
    try {
      await svc.approveAll();
    } finally {
      if (mounted) setState(() => _filingAll = false);
    }
  }

  Future<void> _passOver(CameraSweepService svc, SweepAsset a) async {
    try {
      await svc.dismiss(a);
    } catch (e) {
      // The ledger write failed, so the photo was NOT passed over: it stays,
      // saying so, at the control that refused.
      debugPrint('camera roll: a pass-over was not saved ($e)');
      svc.record(CameraSweepHost.notSaved, a.localIdentifier);
    }
  }

  @override
  Widget build(BuildContext context) {
    final host = context.watch<CameraSweepHost>();
    final ledger = host.ledger, service = host.service;
    if (ledger == null || service == null) {
      return KitFlowFrame(
        onEscape: _close,
        top: KitFlowTop(label: CameraRollCopy.name, onClose: _close),
        body: KitFlowBody(children: [
          if (host.loadError != null)
            const KitFailureInline(CameraRollCopy.rowUnreadable, dense: true),
        ]),
        foot: const [],
      );
    }
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, service]),
      builder: (context, _) => switch (_step) {
        CameraRollStep.intro => _intro(),
        CameraRollStep.access => _access(host),
        CameraRollStep.what => _what(),
        CameraRollStep.where => _where(ledger),
        CameraRollStep.lookingBack => _lookingBack(host, ledger, service),
        CameraRollStep.review => _review(host, ledger, service),
      },
    );
  }

  Widget _frame({
    required String label,
    double? progress,
    bool hides = false,
    required List<Widget> body,
    required List<Widget> foot,
  }) => KitFlowFrame(
    onEscape: _close,
    top: KitFlowTop(
      label: label,
      progress: progress,
      hides: hides,
      onClose: _close,
    ),
    body: KitFlowBody(controller: _scroll, children: body),
    foot: foot,
  );

  Widget _setup(int n, {required List<Widget> body, required List<Widget> foot}) =>
      _frame(label: CameraRollCopy.step(n), progress: n / 4, body: body, foot: foot);

  // ── 1 · What it does ──────────────────────────────────────────────────────

  Widget _intro() => _setup(
    1,
    body: [
      const KitFlowMast(
        folio: CameraRollCopy.folio,
        title: CameraRollCopy.introTitle,
        stand: CameraRollCopy.introStand,
      ),
      const KitFlowLabel(CameraRollCopy.introLabel),
      KitFlowRows(
        rows: [
          for (var i = 0; i < CameraRollCopy.introRows.length; i++)
            KitFlowRow(
              number: i + 1,
              title: CameraRollCopy.introRows[i].$1,
              sub: CameraRollCopy.introRows[i].$2,
              strong: true,
              top: true,
            ),
        ],
      ),
    ],
    foot: [
      KitFlowButton.primary(
        CameraRollCopy.continueLabel,
        onTap: () => _to(CameraRollStep.access),
      ),
      KitFlowButton.link(CameraRollCopy.notNow, onTap: _close),
    ],
  );

  // ── 2 · Access ────────────────────────────────────────────────────────────

  Widget _access(CameraSweepHost host) => _setup(
    2,
    body: [
      const KitFlowMast(
        folio: CameraRollCopy.folio,
        title: CameraRollCopy.accessTitle,
        stand: CameraRollCopy.accessStand,
      ),
      if (_refusal != null) ...[
        const SizedBox(height: 20),
        KitNotice(
          text: _refusal!,
          actionLabel: CameraRollCopy.openSettings,
          onAction: host.openSettings,
        ),
      ],
    ],
    foot: [
      KitFlowButton.primary(
        CameraRollCopy.allowAccess,
        icon: Icons.photo_camera_outlined,
        onTap: _asking ? null : _allow,
      ),
      KitFlowButton.link(
        CameraRollCopy.back,
        onTap: () => _to(CameraRollStep.intro),
      ),
    ],
  );

  // ── 3 · What to take in, and how far back ─────────────────────────────────

  Widget _what() => _setup(
    3,
    body: [
      const KitFlowMast(
        folio: CameraRollCopy.folio,
        title: CameraRollCopy.whatTitle,
        stand: CameraRollCopy.whatStand,
      ),
      const KitFlowLabel(CameraRollCopy.keptLabel),
      const KitFlowText.p(CameraRollCopy.keptCards),
      const KitFlowLabel(CameraRollCopy.reachLabel),
      Semantics(
        label: CameraRollCopy.reachLabel,
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final r in SweepReach.values)
              KitFlowRadio(
                label: CameraRollCopy.reaches[r]!,
                count: r == SweepReach.fromNow || _counts[r] == null
                    ? null
                    : CameraRollCopy.photos(_counts[r]!),
                selected: _reach == r,
                onTap: () => setState(() => _reach = r),
              ),
          ],
        ),
      ),
    ],
    foot: [
      KitFlowButton.primary(
        CameraRollCopy.continueLabel,
        onTap: () => _to(CameraRollStep.where),
      ),
      KitFlowButton.link(
        CameraRollCopy.back,
        onTap: () => _to(CameraRollStep.access),
      ),
    ],
  );

  // ── 4 · Where it goes ─────────────────────────────────────────────────────

  Widget _where(SweepLedger ledger) {
    final mode = _mode ?? ledger.mode;
    return _setup(
      4,
      body: [
        const KitFlowMast(
          folio: CameraRollCopy.folio,
          title: CameraRollCopy.whereTitle,
          stand: CameraRollCopy.whereStand,
        ),
        const KitFlowLabel(CameraRollCopy.modeLabel),
        CameraRollMode(
          mode: mode,
          lookBack: _reach != SweepReach.fromNow,
          onChanged: (m) => setState(() => _mode = m),
        ),
        if (_writeFailure != null) ...[
          const SizedBox(height: 20),
          KitFailureInline(_writeFailure!),
        ],
      ],
      foot: [
        KitFlowButton.primary(
          _reach == SweepReach.fromNow
              ? CameraRollCopy.turnItOn
              : CameraRollCopy.startLooking,
          icon: _reach == SweepReach.fromNow ? null : Icons.play_arrow,
          onTap: _turning ? null : () => _turnOn(mode),
        ),
        KitFlowButton.link(
          CameraRollCopy.back,
          onTap: () => _to(CameraRollStep.what),
        ),
      ],
    );
  }

  // ── Looking back ──────────────────────────────────────────────────────────

  Widget _lookingBack(
    CameraSweepHost host,
    SweepLedger ledger,
    CameraSweepService service,
  ) {
    final total = service.walkTotal ?? host.inRange;
    final position = service.walkPosition;
    final running = service.isSweeping;
    final waiting = service.candidates;
    final left = !ledger.backfillComplete;
    final stand = !running && left && service.capped
        ? (waiting.length >= CameraSweepService.backfillBatchLimit
              ? CameraRollCopy.trayFullStand
              : CameraRollCopy.cappedStand)
        : CameraRollCopy.lookingStand;
    final measured = position != null && total != null && total > 0;
    final reach = cameraReach(ledger);
    return _frame(
      label: CameraRollCopy.lookingHead,
      progress: measured ? position / total : null,
      hides: true,
      body: [
        KitFlowMast(
          folio: total == null ? reach : '$reach · ${CameraRollCopy.photos(total)}',
          title: CameraRollCopy.lookingTitle(ledger.reach, ledger.backfillStart),
          stand: stand,
        ),
        if (measured) ...[
          KitFlowBig(
            figure: kitThousands(position),
            label: CameraRollCopy.ofPhotos(total),
          ),
          const SizedBox(height: 14),
          KitFlowBar(value: position / total),
        ],
        KitFlowFigures(
          figures: [
            (kitThousands(waiting.length), CameraRollCopy.forReview),
            (kitThousands(ledger.passedOverCount), CameraRollCopy.passedOver),
            (kitThousands(ledger.deferredCount), host.words.deferredFigure),
          ],
        ),
        if (service.errorMessage != null) ...[
          const SizedBox(height: 20),
          KitFailureBlock(
            sentence: service.failureTitle,
            detail: service.errorMessage!,
            onRetry: service.errorStoppedSweep ? null : host.kick,
            retryLabel: CameraRollCopy.checkAgain,
          ),
        ],
        if (waiting.isNotEmpty) ...[
          const KitFlowLabel(CameraRollCopy.justFound),
          KitFlowRows(
            rows: [
              for (final a in waiting.reversed)
                KitFlowRow(
                  key: ValueKey('found-${a.localIdentifier}'),
                  lead: KitPhotoTile(
                    photoId: a.localIdentifier,
                    load: () => host.bridge!.thumbnail(a.localIdentifier),
                  ),
                  title: cameraKind(a),
                  sub: a.creationDate == null ? null : CameraRollCopy.taken(a.creationDate!),
                  trail: CameraRollCopy.forYourReview,
                  accent: true,
                ),
            ],
          ),
        ],
      ],
      foot: [
        if (running)
          KitFlowButton.primary(
            CameraRollCopy.goToLibrary,
            onTap: () {
              // The flow sits over the Library already; closing it shows the
              // Library, wherever the flow was opened.
              final router = GoRouter.maybeOf(context);
              _close();
              router?.go('/sources');
            },
          )
        else if (waiting.isNotEmpty)
          KitFlowButton.primary(
            CameraRollCopy.reviewNow(waiting.length),
            onTap: () => _to(CameraRollStep.review),
          )
        else
          KitFlowButton.primary(CameraRollCopy.done, onTap: _close),
      ],
    );
  }

  // ── Review, one photo at a time, and the end ──────────────────────────────

  Widget _review(
    CameraSweepHost host,
    SweepLedger ledger,
    CameraSweepService service,
  ) {
    final waiting = service.candidates;
    final ids = {for (final a in waiting) a.localIdentifier};
    _seen.addAll(ids);
    if (waiting.isEmpty) return _end(host, ledger);
    final a = waiting.first;
    final n = _seen.length;
    final k = _seen.difference(ids).length + 1;
    final busy = _filing != null || _filingAll;
    final refusal = service.candidateErrors[a.localIdentifier];
    final date = a.creationDate;
    final String note = refusal ??
        (service.alreadyIn(a.localIdentifier)
            ? CameraRollCopy.alreadyIn
            : service.foundByLookBack(a.localIdentifier)
            ? CameraRollCopy.lookBackKeeps
            : CameraRollCopy.youAsked);
    return _frame(
      label: CameraRollCopy.reviewHead(k, n),
      body: [
        KitFlowSummary(
          CameraRollCopy.summary(
            ledger.ingestedCount,
            waiting.length,
            ledger.passedOverCount,
          ),
        ),
        KitPhotoTile(
          key: ValueKey('review-${a.localIdentifier}'),
          photoId: a.localIdentifier,
          load: () => host.bridge!.thumbnail(
            a.localIdentifier,
            width: 720,
            height: 600,
          ),
          large: true,
          label: date == null ? null : CameraRollCopy.takenOn(date),
        ),
        KitFlowKicker(
          kicker: cameraKind(a),
          heading: date == null ? null : CameraRollCopy.takenOn(date),
        ),
        if (refusal != null) ...[
          const SizedBox(height: 10),
          KitFailureInline(refusal, dense: true),
        ] else
          KitFlowText.note(note),
        const KitFlowSlot(CameraRollCopy.filingLine),
        if (n <= 20) KitFlowDots(count: n, current: k - 1),
      ],
      foot: [
        KitFlowButton.primary(
          CameraRollCopy.fileIt,
          icon: Icons.check,
          onTap: busy ? null : () => _file(service, a),
        ),
        KitFlowGhosts(
          children: [
            if (waiting.length > 1)
              KitFlowButton.ghost(
                CameraRollCopy.fileAll(waiting.length),
                onTap: busy ? null : () => _fileAll(service),
              ),
            KitFlowButton.ghost(
              CameraRollCopy.passOver,
              onTap: busy ? null : () => _passOver(service, a),
            ),
          ],
        ),
      ],
    );
  }

  Widget _end(CameraSweepHost host, SweepLedger ledger) {
    final left = ledger.enabled && !ledger.backfillComplete;
    final next = left
        ? CameraRollCopy.endWalkLeft
        : ledger.mode == SweepMode.automatic
        ? CameraRollCopy.endAutomatic
        : CameraRollCopy.endAsk;
    return _frame(
      label: CameraRollCopy.reviewHeadEnd,
      body: [
        KitFlowMast(
          folio: CameraRollCopy.endFolio,
          title: CameraRollCopy.endTitle,
          stand:
              '${CameraRollCopy.endCounts(ledger.ingestedCount, ledger.passedOverCount)} '
              '$next',
        ),
      ],
      foot: [
        KitFlowButton.primary(
          CameraRollCopy.done,
          onTap: () {
            // The walk has photos left: Done runs the next pass (ADR-198
            // decision 5), as the panel's Look now does.
            if (left) host.kick();
            _close();
          },
        ),
      ],
    );
  }
}

/// "When it keeps a photo": the §6.8 segmented control (*Automatically* ·
/// *Ask me first*) and its note — setup step 4's and the panel's, the same
/// part. [lookBack] adds the sentence that every look back waits either way.
class CameraRollMode extends StatelessWidget {
  final SweepMode mode;
  final bool lookBack;
  final ValueChanged<SweepMode>? onChanged;

  const CameraRollMode({
    super.key,
    required this.mode,
    required this.lookBack,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      KitSegmented(
        groupLabel: CameraRollCopy.modeLabel,
        expand: true,
        segments: const [
          KitSegment(CameraRollCopy.automatically),
          KitSegment(CameraRollCopy.askFirst),
        ],
        selected: mode == SweepMode.automatic ? 0 : 1,
        onChanged: onChanged == null
            ? null
            : (i) => onChanged!(i == 0 ? SweepMode.automatic : SweepMode.review),
      ),
      KitFlowText.note(
        mode == SweepMode.automatic
            ? CameraRollCopy.automaticNote
            : CameraRollCopy.askNote,
      ),
      if (lookBack) const KitFlowText.note(CameraRollCopy.lookBackNote),
    ],
  );
}

// ── The settings panel ──────────────────────────────────────────────────────

/// *Camera roll settings* (sources.md §Camera roll, *The settings panel*):
/// the status line, access, a failure, what it takes in, the mode, the
/// reach with *Look further back* and *Start over*, the deferred line, then
/// *Look now* and *Turn off the camera roll*. Every control writes before it
/// moves. [close] closes the panel; [onLookFurther] opens Looking back once
/// the start date has moved.
class CameraRollSettings extends StatefulWidget {
  final VoidCallback close;
  final VoidCallback onLookFurther;

  const CameraRollSettings({
    super.key,
    required this.close,
    required this.onLookFurther,
  });

  @override
  State<CameraRollSettings> createState() => _CameraRollSettingsState();
}

class _CameraRollSettingsState extends State<CameraRollSettings> {
  String? _modeFailure;
  String? _reachFailure;
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    final host = context.read<CameraSweepHost>();
    // Access is read (never asked) and the photos in range counted as the
    // panel opens.
    unawaited(host.ready.then((_) async {
      await host.refreshAccess();
      if (host.access == SweepAccess.granted) await host.refreshInRange();
    }));
  }

  Future<void> _setMode(CameraSweepHost host, SweepMode m) async {
    setState(() {
      _writing = true;
      _modeFailure = null;
    });
    try {
      await host.setMode(m);
    } catch (e) {
      debugPrint('camera roll: the mode was not saved ($e)');
      if (mounted) setState(() => _modeFailure = CameraSweepHost.notSaved);
    }
    if (mounted) setState(() => _writing = false);
  }

  Future<void> _lookFurther(CameraSweepHost host) async {
    setState(() {
      _writing = true;
      _reachFailure = null;
    });
    try {
      await host.lookFurtherBack();
    } catch (e) {
      debugPrint('camera roll: the start date was not saved ($e)');
      if (mounted) {
        setState(() {
          _writing = false;
          _reachFailure = CameraSweepHost.notSaved;
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => _writing = false);
    widget.close();
    widget.onLookFurther();
  }

  void _startOver(CameraSweepHost host) => KitConfirm.show(
    context,
    title: CameraRollCopy.startOverTitle,
    body: '${CameraRollCopy.startOverBody}\n\n${CameraRollCopy.startOverBody2}',
    confirmLabel: CameraRollCopy.startOver,
    cancelLabel: CameraRollCopy.keepProgress,
    onConfirm: host.startOver,
  );

  void _turnOff(CameraSweepHost host) => KitConfirm.show(
    context,
    title: CameraRollCopy.turnOffTitle,
    body: CameraRollCopy.turnOffBody,
    confirmLabel: CameraRollCopy.turnOffConfirm,
    cancelLabel: CameraRollCopy.keepItOn,
    onConfirm: () async {
      try {
        await host.disable();
      } catch (e) {
        debugPrint('camera roll: not turned off ($e)');
        return CameraSweepHost.notSaved;
      }
      widget.close();
      return null;
    },
  );

  @override
  Widget build(BuildContext context) {
    final host = context.watch<CameraSweepHost>();
    final ledger = host.ledger, service = host.service;
    if (ledger == null || service == null) {
      return host.loadError == null
          ? const SizedBox.shrink()
          : const KitFailureInline(CameraRollCopy.rowUnreadable, dense: true);
    }
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, service]),
      builder: (context, _) {
        final looked = ledger.lastLookedAt;
        final status = service.isSweeping
            ? CameraRollCopy.lookingThrough(service.examined)
            : looked == null
            ? CameraRollCopy.on
            : CameraRollCopy.lookedAgo(kitAgo(looked));
        final access = host.access;
        final further = host.furtherReach;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitFlowStatus(status),
            if (access == SweepAccess.limited || access == SweepAccess.denied) ...[
              const SizedBox(height: 14),
              KitNotice(
                text: access == SweepAccess.limited
                    ? SweepAccessRefused.limitedSentence
                    : SweepAccessRefused.deniedSentence,
                actionLabel: CameraRollCopy.openSettings,
                onAction: host.openSettings,
              ),
            ],
            if (service.errorMessage != null) ...[
              const SizedBox(height: 14),
              KitFailureBlock(
                sentence: service.failureTitle,
                detail: service.errorMessage!,
                onRetry: service.errorStoppedSweep ? null : host.kick,
                retryLabel: CameraRollCopy.checkAgain,
              ),
            ],
            const KitDLabel(CameraRollCopy.takesInLabel),
            const KitFlowText.p(CameraRollCopy.takesIn),
            const KitFlowText.panelNote(CameraRollCopy.takesInCards),
            const KitDLabel(CameraRollCopy.modeLabel),
            CameraRollMode(
              mode: ledger.mode,
              lookBack: ledger.reach != SweepReach.fromNow,
              onChanged: _writing ? null : (m) => _setMode(host, m),
            ),
            if (_modeFailure != null) KitFailureInline(_modeFailure!),
            const KitDLabel(CameraRollCopy.lookingBackLabel),
            KitFlowReach(
              text:
                  '${cameraReach(ledger)}'
                  '${ledger.backfillComplete ? CameraRollCopy.reachDone : ''}',
              links: [
                if (further != null)
                  KitHxLink(
                    CameraRollCopy.lookFurther,
                    onTap: _writing ? null : () => _lookFurther(host),
                  ),
                KitHxLink(
                  CameraRollCopy.startOver,
                  onTap: _writing ? null : () => _startOver(host),
                ),
              ],
            ),
            if (_reachFailure != null) KitFailureInline(_reachFailure!),
            if (ledger.deferredCount > 0) ...[
              const SizedBox(height: 12),
              Text(
                CameraRollCopy.deferred(host.words.deferredTitle, ledger.deferredCount),
                style: KitText.meta(context),
              ),
            ],
            KitFlowPanelFoot(
              children: [
                KitFlowPanelButton(
                  CameraRollCopy.lookNow,
                  icon: Icons.refresh,
                  onTap: service.isSweeping ? null : host.kick,
                ),
                KitFlowPanelButton(
                  CameraRollCopy.turnOff,
                  danger: true,
                  onTap: () => _turnOff(host),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
