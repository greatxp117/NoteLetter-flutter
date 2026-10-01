import 'package:flutter/material.dart';
import '../../theme/app_shadows.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// Shared reader-panel chrome.
///
/// Two jobs, and they are different: the getters are a **token facade** for the
/// brightness (the `Html` style map needs a `Tokens` object, and six panels
/// need the same handful of colours); the builders below are the reader's own
/// **component layer** — the panel intro, the panel note, the empty state and
/// the panel strip.
///
/// Every one of those builders now composes its type from `KitText`. They used
/// to spell their own `TextStyle`s, which is inline composition one indirection
/// away: `note()` set the summary in the UI sans at `--fg-muted` where the
/// reference sets it as an italic serif lede, and `eyebrow()` was an 11px sans
/// at a different tracking from `.eyebrow`. A screen that reaches for a local
/// helper instead of the kit drifts exactly as far as one that writes the style
/// inline (ADR-041).
///
/// The panel strip lives here rather than in `lib/widgets/kit/` on purpose:
/// §6.8 says the segmented control is **not tabs** and no kit pattern draws
/// one, so this is the reader's own device and naming it a kit pattern would
/// be a `/contract-change`, not a refactor.
class ReaderUi {
  final bool dark;
  ReaderUi(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark;

  /// The token object for this brightness, so a caller that needs a token this
  /// facade does not name (the Html style map) does not add a third copy.
  Tokens get tokens => dark ? Tokens.dark : Tokens.light;

  // Every getter is a semantic token, never a palette step. They were raw
  // `AppColors` pairs until F-43 — the same values for eleven of them, and the
  // twelfth is why that mattered: [surface] was `--surface-raised` in light
  // and `--secondary`'s white wash in dark, two different roles under one
  // name, so nothing could say which one a box was meant to be. It is
  // `--surface-raised` in both now. A raw pair is also how `criticalText` sat
  // pinned to its light step after 4.21.0 (ADR-057) made the severities flip,
  // drawing the reader's error text in the accent in dark.
  Color get muted => tokens.fgMuted;
  Color get border => tokens.border;
  Color get card => tokens.surface;
  Color get surface => tokens.surfaceRaised;
  Color get fg => tokens.fg;
  Color get primary => tokens.accent;
  Color get accentFg => tokens.accentFg;
  Color get criticalText => tokens.criticalText;
  Color get rule => tokens.rule;
  Color get subtle => tokens.fgSubtle;
  Color get sunken => tokens.surfaceSunken;
  Color get positive => tokens.positive;

  /// The section label opening a panel (web `.eyebrow`) — the kit's type role,
  /// not a local approximation of it.
  Widget eyebrow(String text) => Eyebrow(text);

  /// The explanatory paragraph under a panel's eyebrow (web `.panel-note`):
  /// **italic serif at `--fg-lede`**, 15/23, capped at the reference's 64ch.
  ///
  /// This is a lede, and it was the UI sans at `--fg-muted` here until 4.54.1 —
  /// a standfirst in the body face is the second-most common way a screen stops
  /// looking like this app while every colour in it stays correct (§2.1).
  Widget note(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Lede(text, fontSize: 15, height: 23, maxWidth: 480),
      );

  Widget intro(String eyebrowText, [String? noteText]) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow(eyebrowText),
            if (noteText != null) note(noteText),
          ],
        ),
      );

  /// `.rsvp-track` — the 4px progress rail Listen and Speed read share: a
  /// `--surface-sunken` pill with an `--accent` fill. Where [onSeek] is given
  /// a tap or a drag seeks to that fraction, as the reference's `onTrack`
  /// does. It is drawn, not a Material [Slider]: the slider's thumb and
  /// overlay are no part of the reference, and its inactive track is
  /// `--border`, a line rather than a well.
  Widget track(double fraction, {void Function(double)? onSeek}) =>
      LayoutBuilder(builder: (context, box) {
        void at(double dx) =>
            onSeek?.call((dx / box.maxWidth).clamp(0.0, 1.0));
        final rail = SizedBox(
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: ColoredBox(
              color: sunken,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: ColoredBox(color: primary),
                ),
              ),
            ),
          ),
        );
        if (onSeek == null) return rail;
        // A 4px rail is not a target a finger can find; the hit area is 24.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => at(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => at(d.localPosition.dx),
          child: SizedBox(height: 24, child: Center(child: rail)),
        );
      });

  /// `.player-play` / `.rsvp-play` — the 60px `--accent` disc with
  /// `--shadow-1` that both transports centre on. A play triangle's mass sits
  /// left of its box, so [nudge] moves it right while the Play glyph shows
  /// (`.is-play`, 3px on Listen; `:not(.is-pause)`, 2px on Speed read).
  Widget playButton(
          {required IconData icon,
          required VoidCallback onTap,
          double iconSize = 26,
          double nudge = 0,
          String? tooltip}) =>
      Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: primary,
          shape: const CircleBorder(),
          elevation: 0,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                  shape: BoxShape.circle, boxShadow: AppShadows.s1),
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.only(left: nudge),
                child: Icon(icon, size: iconSize, color: accentFg),
              ),
            ),
          ),
        ),
      );

  /// A 1px dashed rule in `--border` (`border-top: 1px dashed`), for the
  /// manuscript's split control.
  Widget dashedRule() => SizedBox(
        height: 1,
        child: CustomPaint(painter: _DashPainter(border)),
      );

  /// §7 — the empty state, from the kit. The [action] is the panel's offer and
  /// becomes the pattern's action row: an empty state is an offer, not an
  /// apology, and a centred sentence saying "nothing here yet" is not this
  /// pattern.
  Widget empty(IconData icon, String title, String sub, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: KitEmptyState(
          icon: icon,
          title: title,
          standfirst: sub,
          actions: action == null ? const [] : [action],
        ),
      );
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    // A browser draws a 1px dashed border as 3px dashes with 3px gaps.
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, 0.5), Offset((x + 3).clamp(0, size.width), 0.5),
          paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}
