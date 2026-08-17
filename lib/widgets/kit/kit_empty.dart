import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

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
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.chrome,
                  borderRadius: AppRadius.lgR,
                  boxShadow: AppShadows.s2,
                ),
                child: Icon(icon, size: 26, color: t.chromeFg),
              ),
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
