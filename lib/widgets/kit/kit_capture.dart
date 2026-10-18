import 'dart:typed_data';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_failure.dart';
import 'kit_text.dart';

/// §23 — the **Capture card** (5.23.0, F-125 S3): one photo the camera-roll
/// sweep found, waiting on the reader in the review tray
/// (`screens/sources.md` §Camera-roll sweep).
///
/// Web has no camera roll, so the reference is the retired iOS app's
/// `SweepReviewSection.CandidateCard` (frames `sweep-tray*.ios.*.png`).
///
/// **Required parts**, in order: the photo · the action pair, dismiss then
/// add · one caption slot, holding at most one thing — the §14.2 rejection of
/// its add (dense), or else the photo's standing, *Already in NoteLetter*.
///
/// **Reference metrics** — the photo 108×140, cover-fitted, on
/// `--surface-sunken` with a 1px `--border` at `--r-md`; the pair centred 8
/// under it, two §6.5 icon buttons, dismiss at `--fg-muted` and add at
/// `--accent` (a glyph, so 3:1 is its floor); the caption 8 under the pair,
/// sans 11, the card's width.
///
/// **Held while its add is in flight** (§6.1): both buttons at the token, so
/// a second tap cannot send a second session. The card leaves the tray only
/// when the call came back (the umbrella's "write before you move").
class KitCaptureCard extends StatefulWidget {
  /// Reads the photo's pixels; null when the photo is not on the device, and
  /// the card draws its ground.
  final Future<Uint8List?> Function() loadImage;

  /// A stable identity for the photo: the card reloads only when it changes.
  final String photoId;
  final VoidCallback? onDismiss;
  final VoidCallback? onAdd;

  /// The photo is already in NoteLetter — its standing, said under the pair.
  final bool alreadyIn;

  /// Why the last add was refused (§14.2, verbatim). Wins the slot over
  /// [alreadyIn]: a refusal is the newer fact.
  final String? failure;

  /// The add is in flight.
  final bool busy;

  const KitCaptureCard({
    super.key,
    required this.photoId,
    required this.loadImage,
    this.onDismiss,
    this.onAdd,
    this.alreadyIn = false,
    this.failure,
    this.busy = false,
  });

  static const double width = 108;
  static const double height = 140;

  /// The caption under a photo NoteLetter already holds.
  static const alreadyInLabel = 'Already in NoteLetter';

  @override
  State<KitCaptureCard> createState() => _KitCaptureCardState();
}

class _KitCaptureCardState extends State<KitCaptureCard> {
  late Future<Uint8List?> _image;

  @override
  void initState() {
    super.initState();
    _image = _load();
  }

  @override
  void didUpdateWidget(KitCaptureCard old) {
    super.didUpdateWidget(old);
    if (old.photoId != widget.photoId) _image = _load();
  }

  Future<Uint8List?> _load() async {
    try {
      return await widget.loadImage();
    } catch (e) {
      // The card still stands without its picture — the photo was deleted, or
      // access changed under it — and its actions say what happens next.
      debugPrint('capture card: no picture for ${widget.photoId} — $e');
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final held = widget.busy;
    final failure = widget.failure;
    return SizedBox(
      width: KitCaptureCard.width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: KitCaptureCard.width,
            height: KitCaptureCard.height,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              borderRadius: AppRadius.mdR,
              border: Border.all(color: t.border),
            ),
            child: FutureBuilder<Uint8List?>(
              future: _image,
              builder: (context, snap) {
                final bytes = snap.data;
                return bytes == null
                    ? const SizedBox.expand()
                    : Image.memory(bytes,
                        fit: BoxFit.cover,
                        width: KitCaptureCard.width,
                        height: KitCaptureCard.height,
                        gaplessPlayback: true);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Opacity(
            opacity: held ? AppSpacing.heldOpacity : 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KitIconButton(Icons.close,
                    tooltip: 'Skip this photo',
                    onPressed: held ? null : widget.onDismiss),
                const SizedBox(width: AppSpacing.s1),
                KitIconButton(Icons.add,
                    tooltip: 'Add this photo',
                    color: t.accent,
                    onPressed: held ? null : widget.onAdd),
              ],
            ),
          ),
          if (failure != null) ...[
            const SizedBox(height: AppSpacing.s2),
            SizedBox(
              width: KitCaptureCard.width,
              child: KitFailureInline(failure, dense: true),
            ),
          ] else if (widget.alreadyIn) ...[
            const SizedBox(height: AppSpacing.s2),
            SizedBox(
              width: KitCaptureCard.width,
              child: Text(KitCaptureCard.alreadyInLabel,
                  textAlign: TextAlign.center,
                  style: KitText.fine(context, color: t.fgMuted)),
            ),
          ],
        ],
      ),
    );
  }
}

/// The tray's rail: capture cards side by side, scrolling sideways, 12 apart,
/// top-aligned so a card whose caption wraps does not push its neighbours'
/// photos down.
class KitCaptureRail extends StatelessWidget {
  final List<Widget> cards;

  const KitCaptureRail({super.key, required this.cards});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s3),
              cards[i],
            ],
          ],
        ),
      );
}
