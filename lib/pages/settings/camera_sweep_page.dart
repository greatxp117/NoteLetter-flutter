import 'package:flutter/material.dart' show Icons, showDatePicker;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../services/camera_sweep_bridge.dart';
import '../../services/camera_sweep_service.dart';
import '../../services/error_text.dart';
import '../../services/sweep_ledger.dart';
import '../../shared/dates.dart';
import '../../state/camera_sweep_host.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/kit/kit.dart';

/// **Settings → Camera roll** (`/settings/camera-roll`; `screens/settings.md`
/// §Camera-roll sweep card, F-125 S3). The retired iOS app's
/// `CameraSweepSettingsView`, composed from the kit: a §2.2 sub-screen header,
/// then labelled groups of setting rows, as Notification settings is.
///
/// Everything here is client-local and per-device (ADR-023): no endpoint, no
/// Firestore document, nothing to save. Every control **writes before it
/// moves** — a switch, a mode or a date changes on screen only once the
/// device's store took it.
///
/// In the spec's order: enable → library permission (asked HERE, on the
/// switch, never at launch; partial or no access refused with its sentence and
/// *Open Settings*) → mode → the catch-up's start date with the photos in
/// range → status.
class CameraSweepPage extends StatefulWidget {
  const CameraSweepPage({super.key});

  // The copy — `screens/settings.md` §Camera-roll sweep card holds it
  // verbatim (5.23.0); the retired iOS app's words.
  static const standfirst =
      'Screenshots, photos of documents, whiteboards and handwritten notes are '
      'added to your library. Everything else stays on your phone — photos are '
      'checked for text on this device, and only the ones that have any are '
      'sent.';
  static const switchTitle = 'Sweep my camera roll';
  static const modeTitle = 'When a photo qualifies';
  /// Swift's picker said "Add it automatically"; a §6.8 segment on a phone
  /// cannot hold that, so the segment says the mode in one word.
  static const automaticLabel = 'Automatically';
  static const reviewLabel = 'Ask me first';
  static const firstCatchUpNote =
      'The first catch-up always goes through review, whichever you pick. '
      'It’s the pass that finds everything at once, so it’s worth a look '
      'before it runs.';
  static const automaticNote =
      'Automatic still means "next time the app runs, or when iOS gives us a '
      'moment in the background" — there’s no way to wake an app the instant '
      'a photo is taken.';
  static const goBackTitle = 'Go back to';
  static const catchUpNote =
      'Only a fraction of these will have readable text — the rest are never '
      'uploaded. NoteLetter works through them a few hundred at a time.';
  static const inRangeTitle = 'Photos in range';
  static const addedTitle = 'Added from photos';
  static const iCloudTitle = 'Waiting for iCloud';
  static const waitingTitle = 'Waiting for your review';
  static const checkTitle = 'Check for new photos';
  static String checking(int n) => 'Checking photos… $n so far';
  static const startOverTitle = 'Start over';
  static const confirmTitle = 'Start this phone’s photo sweep over?';
  static const confirmBody =
      'This phone forgets which photos it has already checked, so the next '
      'sweep looks at every photo from your start date again — and any you '
      'dismissed in review will be offered again.\n\n'
      'Nothing already in your library is removed or added twice: NoteLetter '
      'recognises a photo it already has.';
  static const keepLabel = 'Keep my progress';

  @override
  State<CameraSweepPage> createState() => _CameraSweepPageState();
}

class _CameraSweepPageState extends State<CameraSweepPage> {
  bool _switching = false;
  String? _writeFailure;

  @override
  void initState() {
    super.initState();
    final host = context.read<CameraSweepHost>();
    // What the page shows is read when it opens: access (without asking) and
    // the photos in range.
    host.ready.then((_) async {
      await host.refreshAccess();
      if (host.access == SweepAccess.granted) await host.refreshInRange();
    });
  }

  /// Every write goes through here: the control stays where the store is
  /// until the write came back, and a failed write says so beside it.
  Future<void> _write(Future<void> Function() write) async {
    setState(() => _writeFailure = null);
    try {
      await write();
    } catch (e) {
      debugPrint('camera sweep: a setting was not saved ($e)');
      if (mounted) setState(() => _writeFailure = CameraSweepHost.notSaved);
    }
  }

  Future<void> _toggle(CameraSweepHost host, bool on) async {
    setState(() => _switching = true);
    await _write(() => on ? host.enable() : host.disable());
    if (mounted) setState(() => _switching = false);
  }

  Future<void> _pickDate(CameraSweepHost host, SweepLedger ledger) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: ledger.backfillStart.isAfter(now) ? now : ledger.backfillStart,
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked == null) return;
    await _write(() => host.setBackfillStart(picked));
  }

  void _startOver(CameraSweepHost host) {
    KitConfirm.show(
      context,
      title: CameraSweepPage.confirmTitle,
      body: CameraSweepPage.confirmBody,
      confirmLabel: CameraSweepPage.startOverTitle,
      cancelLabel: CameraSweepPage.keepLabel,
      onConfirm: host.startOver,
    );
  }

  @override
  Widget build(BuildContext context) {
    final host = context.watch<CameraSweepHost>();
    final ledger = host.ledger, service = host.service;
    return KitPage(
      width: KitFrameWidth.reading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubScreenHeader(
            parentLabel: 'Settings',
            onBack: () => context.go('/settings'),
            eyebrow: 'Camera roll',
            standfirst: CameraSweepPage.standfirst,
          ),
          if (host.loadError != null)
            KitFailureBlock(
              sentence: 'This phone’s sweep settings could not be read.',
              detail: describeSdkError(host.loadError!),
            )
          else if (ledger == null || service == null)
            KitRowList(raised: true, rows: [
              KitRowSlot(child: Text('Loading…', style: KitText.meta(context))),
            ])
          else
            ListenableBuilder(
              listenable: Listenable.merge([ledger, service]),
              builder: (context, _) => _body(host, ledger, service),
            ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }

  Widget _body(CameraSweepHost host, SweepLedger ledger, CameraSweepService service) {
    final access = host.access;
    // Partial access is refused whether or not the sweep is on (Swift drew it
    // either way); no access is said once the sweep is on, or once the switch
    // was refused for it — a switch that springs back with no sentence is a
    // refusal nobody can see.
    final SweepAccessRefused? refusal = host.refused ??
        (access == SweepAccess.limited
            ? SweepAccessRefused.limited
            : access == SweepAccess.denied && ledger.enabled
                ? SweepAccessRefused.denied
                : null);
    final running = ledger.enabled && access == SweepAccess.granted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitFieldGroup(
          label: 'Sweep',
          first: true,
          child: KitRowList(raised: true, rows: [
            KitSettingRow(
              icon: Icons.photo_library_outlined,
              title: CameraSweepPage.switchTitle,
              trailing: [
                KitSwitch(
                  value: ledger.enabled,
                  tooltip: CameraSweepPage.switchTitle,
                  onChanged: _switching ? null : (on) => _toggle(host, on),
                ),
              ],
              below: refusal == null && _writeFailure == null
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_writeFailure != null) KitFailureInline(_writeFailure!),
                        if (refusal != null)
                          KitNotice(
                            text: refusal.sentence,
                            actionLabel: 'Open Settings',
                            onAction: host.openSettings,
                          ),
                      ],
                    ),
            ),
          ]),
        ),
        if (running) ...[
          KitFieldGroup(
            label: 'Mode',
            child: KitRowList(raised: true, rows: [
              KitSettingRow(
                icon: Icons.tune,
                title: CameraSweepPage.modeTitle,
                description: ledger.backfillComplete
                    ? CameraSweepPage.automaticNote
                    : CameraSweepPage.firstCatchUpNote,
                // The row's control strip, in the text column (as the level
                // picker on Notifications): two long choices fill it rather
                // than overflow a phone's trailing edge.
                below: KitSegmented(
                  groupLabel: CameraSweepPage.modeTitle,
                  expand: true,
                  segments: const [
                    KitSegment(CameraSweepPage.automaticLabel),
                    KitSegment(CameraSweepPage.reviewLabel),
                  ],
                  selected: ledger.mode == SweepMode.automatic ? 0 : 1,
                  onChanged: (i) => _write(() => host.setMode(
                      i == 0 ? SweepMode.automatic : SweepMode.review)),
                ),
              ),
            ]),
          ),
          KitFieldGroup(
            label: 'Catch up',
            child: KitRowList(raised: true, rows: [
              KitSettingRow(
                icon: Icons.history,
                title: CameraSweepPage.goBackTitle,
                description: CameraSweepPage.catchUpNote,
                // In the row's control strip, under the copy: beside it, the
                // date took a phone's text column down to three words a line.
                below: Align(
                  alignment: Alignment.centerLeft,
                  child: KitSettingLink(dayDate(ledger.backfillStart),
                      icon: Icons.calendar_today_outlined,
                      onTap: () => _pickDate(host, ledger)),
                ),
              ),
              // Measured by the library, never estimated; not drawn until it
              // has been counted (unread is not zero).
              if (host.inRange != null)
                KitSettingRow(
                  icon: Icons.photo_outlined,
                  title: CameraSweepPage.inRangeTitle,
                  trailing: [_Figure(host.inRange!)],
                ),
            ]),
          ),
          KitFieldGroup(
            label: 'Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (service.errorMessage != null) ...[
                  KitFailureBlock(
                    sentence: service.failureTitle,
                    detail: service.errorMessage!,
                    onRetry: service.errorStoppedSweep ? null : host.kick,
                    retryLabel: 'Check again',
                  ),
                  const SizedBox(height: AppSpacing.s3),
                ],
                KitRowList(raised: true, rows: [
                  KitSettingRow(
                    icon: Icons.check_circle_outline,
                    title: CameraSweepPage.addedTitle,
                    trailing: [_Figure(ledger.ingestedCount)],
                  ),
                  if (service.candidates.isNotEmpty)
                    KitSettingRow(
                      icon: Icons.inbox_outlined,
                      title: CameraSweepPage.waitingTitle,
                      trailing: [
                        _Figure(service.candidates.length),
                        KitSettingLink('Open Sources',
                            onTap: () => context.go('/sources')),
                      ],
                    ),
                  if (ledger.deferredCount > 0)
                    KitSettingRow(
                      icon: Icons.cloud_outlined,
                      title: CameraSweepPage.iCloudTitle,
                      trailing: [_Figure(ledger.deferredCount)],
                    ),
                  KitSettingRow(
                    icon: Icons.refresh,
                    title: CameraSweepPage.checkTitle,
                    description: service.isSweeping
                        ? CameraSweepPage.checking(service.examined)
                        : null,
                    trailing: [
                      KitSettingLink('Check now',
                          onTap: service.isSweeping ? null : host.kick),
                    ],
                  ),
                ]),
                // The form's one destructive action, at its end (§18 asks
                // first): the ledger holds the photos dismissed in review too,
                // so those come back — the part a reader would not guess.
                const SizedBox(height: AppSpacing.s4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: KitFormDangerButton(CameraSweepPage.startOverTitle,
                      icon: Icons.restart_alt,
                      onPressed: () => _startOver(host)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// A count in a setting row's control strip, in the figure role.
class _Figure extends StatelessWidget {
  final int n;
  const _Figure(this.n);

  @override
  Widget build(BuildContext context) =>
      Text('$n', style: KitText.monoFigure(context));
}
