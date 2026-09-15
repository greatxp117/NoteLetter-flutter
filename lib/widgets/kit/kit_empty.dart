import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §7's **mark** — the rounded chrome-filled tile holding a glyph that opens an
/// empty state, and the seal that opens a first-run step.
///
/// It was drawn inline inside [KitEmptyState] until F-14, which is fine until a
/// second surface needs it: the onboarding welcome step opens with the same
/// tile at 72 and the finish step with the [KitMark.seal] variant, and a second
/// hand-built copy of a mark is how one of them ends up a different tile
/// (`spec/screens/onboarding.md` §Composition — "onboarding introduces no new
/// primitives; a step that needs one is a kit change").
///
/// Two tones, and the tone is the whole meaning: [KitMark] is the chrome tile
/// that says *this is the app talking*, and [KitMark.seal] is the accent-soft
/// disc inside a dashed ring that says *this is finished and sealed*.
class KitMark extends StatelessWidget {
  final IconData icon;

  /// 60 for §7, 72 for the onboarding welcome, 86 for the finish seal — the
  /// reference's own sizes. The glyph scales with it.
  final double size;

  /// The seal form: a circle on `--accent-soft` with the glyph at `--seal`,
  /// inside a dashed `--accent-chip-border` ring.
  final bool seal;

  const KitMark(this.icon, {super.key, this.size = 60}) : seal = false;

  const KitMark.seal(this.icon, {super.key, this.size = 86}) : seal = true;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final tile = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: seal ? t.accentSoft : t.chrome,
        borderRadius: seal ? null : AppRadius.lgR,
        shape: seal ? BoxShape.circle : BoxShape.rectangle,
        boxShadow: seal ? null : AppShadows.s2,
      ),
      child: Icon(icon, size: size * 0.43, color: seal ? t.seal : t.chromeFg),
    );
    if (!seal) return tile;
    // The ring sits OUTSIDE the disc (`inset: -7px` on the reference), so it is
    // padding around the tile rather than a border on it — a border would eat
    // into the 86 and shrink the seal.
    return CustomPaint(
      painter: _DashedRingPainter(t.accentChipBorder),
      child: Padding(padding: const EdgeInsets.all(7), child: tile),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  final Color color;

  const _DashedRingPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..addOval(Rect.fromLTWH(0.75, 0.75, size.width - 1.5, size.height - 1.5));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 5).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 4;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

/// §7 — the empty state.
///
/// Mark → letterpressed serif title → italic serif standfirst → a stack of
/// **suggestion rows the user can act on**.
///
/// **An empty state is an offer, not an apology.** The suggestion rows are a
/// required part: a centred sentence saying "nothing here yet" is not this
/// pattern, and it is the form every one of these screens degrades into when
/// nobody is looking.
class KitEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String standfirst;

  /// Suggestion rows — build with [KitSuggestion], or pass buttons for the
  /// action-row form.
  final List<Widget> suggestions;

  /// A row of buttons instead of suggestion rows (the study screen's form).
  final List<Widget> actions;

  const KitEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.standfirst,
    this.suggestions = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.s6, AppSpacing.s8, AppSpacing.s6, AppSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              KitMark(icon),
              const SizedBox(height: AppSpacing.s5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTheme.serif(
                  fontSize: 28,
                  height: 34 / 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.02 * 28,
                  color: t.fg,
                ).copyWith(shadows: AppShadows.letterpress),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  standfirst,
                  textAlign: TextAlign.center,
                  style: KitText.lede(context, fontSize: 16, height: 25),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 26),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < suggestions.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.s2),
                        suggestions[i],
                      ],
                    ],
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A suggestion row inside an empty state: a full-width surface card with a
/// `--seal` leading icon and an **italic serif** label.
class KitSuggestion extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const KitSuggestion(
      {super.key, required this.icon, required this.label, this.onTap});

  @override
  State<KitSuggestion> createState() => _KitSuggestionState();
}

class _KitSuggestionState extends State<KitSuggestion> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.mdR,
            border: Border.all(
                color: _hover ? t.accentChipBorder : t.border),
            boxShadow: _hover ? AppShadows.s2 : AppShadows.s1,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: t.seal),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  widget.label,
                  style: KitText.lede(context, fontSize: 16, height: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The **drop zone** — the library's empty state leads with this rather than
/// with suggestion rows (`screens/library.md` §Composition).
///
/// Dashed `--border-strong` on `--bg`, `--r-md`, a centred feather, and the
/// accepted formats as source pills. The offer is the zone itself: a reader
/// with an empty library is not told their library is empty, they are shown
/// where to put the first thing in it.
///
/// Flutter has no dashed border primitive, so the dashes are painted
/// ([_DashedBorderPainter]) — a solid border here would read as a card and stop
/// looking like a target.
class KitDropZone extends StatefulWidget {
  final IconData icon;
  final String title;
  final String help;

  /// Format pills, rendered as source tags.
  final List<Widget> formats;
  final VoidCallback? onTap;

  const KitDropZone({
    super.key,
    required this.icon,
    required this.title,
    required this.help,
    this.formats = const [],
    this.onTap,
  });

  @override
  State<KitDropZone> createState() => _KitDropZoneState();
}

class _KitDropZoneState extends State<KitDropZone> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: _hover ? t.accent : t.borderStrong,
            radius: AppRadius.md,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.s8),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: AppRadius.mdR,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 40, color: t.seal),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: AppTheme.serif(
                    fontSize: 20,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  widget.help,
                  textAlign: TextAlign.center,
                  style: KitText.lede(context, fontSize: 15, height: 22),
                ),
                if (widget.formats.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s4),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: AppSpacing.s2,
                    runSpacing: AppSpacing.s2,
                    children: widget.formats,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        Radius.circular(radius),
      ));
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// A **numbered move** — the explainer row form of §7's suggestion stack.
///
/// The reference's study empty state uses it (`.st-move`): a mono numeral, a
/// sans title and a line of copy, in a surface card. It is read, not tapped,
/// which is the one way it differs from [KitSuggestion] — an empty state whose
/// rows explain the feature is still "an offer, not an apology", and dropping
/// the copy to fit a one-line suggestion row would throw away the offer.
///
/// The reference spells it **twice**: the study card above, and onboarding's
/// welcome step (`.ob-move`), where the same three parts sit in a **ruled**
/// row with an accent-soft icon tile leading them. Both live here, chosen by
/// [ruled] and [icon], rather than the second one being retyped on the screen
/// that needs it — a kit widget that can only draw one of the reference's two
/// spellings is a kit rule that quietly outranks the screen's (4.46.0).
class KitNumberedMove extends StatelessWidget {
  /// The numeral as the reference sets it — `I`, `II`, `III`.
  final String number;
  final String title;
  final String description;

  /// The leading glyph, on an `--accent-soft` tile at `--accent`. Onboarding's
  /// spelling; the study card has none.
  final IconData? icon;

  /// The ruled form: no card and no shadow, a 1px `--rule` above each row and
  /// below the last, so a stack reads as one ruled list rather than a pile of
  /// sheets. [last] draws that closing rule.
  final bool ruled;
  final bool last;

  const KitNumberedMove({
    super.key,
    required this.number,
    required this.title,
    required this.description,
    this.icon,
    this.ruled = false,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(number, style: KitText.capsLabel(context, letterSpacing: 0.12)),
        const SizedBox(height: 4),
        Text(title,
            style: AppTheme.serif(
              fontSize: 17,
              height: 22 / 17,
              fontWeight: FontWeight.w600,
              color: t.fg,
            )),
        const SizedBox(height: 4),
        Text(description,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 13,
              height: 19 / 13,
              color: t.fgMuted,
            )),
      ],
    );

    final lead = icon == null
        ? null
        : Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accentSoft,
              borderRadius: AppRadius.smR,
            ),
            child: Icon(icon, size: 20, color: t.accent),
          );

    final content = lead == null
        ? body
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              lead,
              const SizedBox(width: AppSpacing.s4),
              Expanded(child: body),
            ],
          );

    return Container(
      width: double.infinity,
      padding: ruled
          ? const EdgeInsets.symmetric(vertical: AppSpacing.s4, horizontal: 2)
          : const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4, vertical: AppSpacing.s3 + 1),
      decoration: ruled
          ? BoxDecoration(
              border: Border(
                top: BorderSide(color: t.rule),
                bottom: last ? BorderSide(color: t.rule) : BorderSide.none,
              ),
            )
          : BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.mdR,
              border: Border.all(color: t.border),
              boxShadow: AppShadows.s1,
            ),
      child: content,
    );
  }
}
