import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../services/camera_sweep_bridge.dart';
import '../../services/camera_sweep_service.dart';
import '../../state/camera_sweep_host.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/kit/kit.dart';

/// **From your camera roll** — the camera-roll sweep's review tray on Sources
/// (`screens/sources.md` §Camera-roll sweep; F-125 S3). The retired iOS app's
/// `SweepReviewSection`, composed from the kit: a §3 header carrying the
/// count, a rail of §23 capture cards, and *Add all* under it.
///
/// Rows here are **candidates, not documents**: they exist only on this
/// device and nothing has been sent for them. Approved, a photo becomes an
/// ordinary document and arrives through the documents subscription in the
/// sections that already draw it (INV-02).
///
/// Drawn only once the sweep is on, and only while there is something to
/// show: cards, a pass that has found none yet, or a failure that stopped one.
class SweepTraySection extends StatefulWidget {
  const SweepTraySection({super.key});

  /// A pass that has found nothing yet (Swift's sentence).
  static const looking = 'Looking through your photos…';

  @override
  State<SweepTraySection> createState() => _SweepTraySectionState();
}

class _SweepTraySectionState extends State<SweepTraySection> {
  /// Cards whose add is in flight — held, so a second tap sends nothing.
  final Set<String> _busy = {};
  bool _addingAll = false;

  Future<void> _add(CameraSweepService service, SweepAsset asset) async {
    setState(() => _busy.add(asset.localIdentifier));
    try {
      await service.approve(asset);
    } finally {
      if (mounted) setState(() => _busy.remove(asset.localIdentifier));
    }
  }

  Future<void> _skip(CameraSweepService service, SweepAsset asset) async {
    try {
      await service.dismiss(asset);
    } catch (e) {
      // The ledger write failed, so the photo was NOT skipped: the card stays
      // and says so, at the control that refused.
      debugPrint('camera sweep: a skip was not saved ($e)');
      service.record(CameraSweepHost.notSaved, asset.localIdentifier);
    }
  }

  Future<void> _addAll(CameraSweepService service) async {
    setState(() => _addingAll = true);
    try {
      await service.approveAll();
    } finally {
      if (mounted) setState(() => _addingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Nullable: a screen pumped without the app's providers (a widget test)
    // has no sweep, which is the same as a platform without one.
    final host = context.watch<CameraSweepHost?>();
    final ledger = host?.ledger, service = host?.service, bridge = host?.bridge;
    if (host == null ||
        !host.available ||
        ledger == null ||
        service == null ||
        bridge == null) {
      return const SizedBox.shrink();
    }
    return ListenableBuilder(
      listenable: Listenable.merge([ledger, service]),
      builder: (context, _) {
        final cards = service.candidates;
        final error = service.errorMessage;
        if (!ledger.enabled ||
            (cards.isEmpty && !service.isSweeping && error == null)) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(cards.isEmpty
                ? 'From your camera roll'
                : 'From your camera roll · ${cards.length}'),
            if (error != null)
              KitFailureBlock(
                sentence: service.failureTitle,
                detail: error,
                // A stopped sweep stays stopped until the server can dedupe;
                // one photo's refusal is retried by the next pass.
                onRetry: service.errorStoppedSweep ? null : host.kick,
                retryLabel: 'Check again',
              ),
            if (cards.isEmpty && service.isSweeping)
              const KitProcNote(SweepTraySection.looking)
            else if (cards.isNotEmpty) ...[
              KitCaptureRail(cards: [
                for (final a in cards)
                  KitCaptureCard(
                    key: ValueKey(a.localIdentifier),
                    photoId: a.localIdentifier,
                    loadImage: () => bridge.thumbnail(a.localIdentifier),
                    alreadyIn: service.alreadyIn(a.localIdentifier),
                    failure: service.candidateErrors[a.localIdentifier],
                    busy: _addingAll || _busy.contains(a.localIdentifier),
                    onDismiss: () => _skip(service, a),
                    onAdd: () => _add(service, a),
                  ),
              ]),
              if (cards.length > 1) ...[
                const SizedBox(height: AppSpacing.s3),
                KitActionFlow(children: [
                  KitButton.secondary('Add all ${cards.length}',
                      onPressed: _addingAll || _busy.isNotEmpty
                          ? null
                          : () => _addAll(service)),
                ]),
              ],
            ],
          ],
        );
      },
    );
  }
}
