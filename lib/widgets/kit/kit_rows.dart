import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §4.1 — the list primitive: a bordered surface holding hairline-divided rows.
///
/// The container clips, so the rows' dividers stop at the corners; the last row
/// has no divider.
class KitRowList extends StatelessWidget {
  final List<Widget> rows;

  const KitRowList({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ClipRRect(
      borderRadius: AppRadius.mdR,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadius.mdR,
          border: Border.all(color: t.border),
        ),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: t.rule),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// §4.1 — one row: **[file badge · title + subtitle · count · date]**.
class KitSourceRow extends StatefulWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final String? count;
  final String? date;
  final VoidCallback? onTap;

  const KitSourceRow({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.count,
    this.date,
    this.onTap,
  });

  @override
  State<KitSourceRow> createState() => _KitSourceRowState();
}

class _KitSourceRowState extends State<KitSourceRow> {
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
        child: Container(
          color: _hover && widget.onTap != null
              ? t.hover
              : const Color(0x00000000),
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(
                        fontSize: 17,
                        height: 22 / 17,
                        fontWeight: FontWeight.w500,
                        color: t.fg,
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 12,
                          color: t.fgMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.count != null) ...[
                const SizedBox(width: 14),
                Text(widget.count!,
                    style:
                        AppTheme.mono(fontSize: 12, color: t.fgMuted)),
              ],
              if (widget.date != null) ...[
                const SizedBox(width: 14),
                SizedBox(
                  width: 64,
                  child: Text(
                    widget.date!,
                    textAlign: TextAlign.right,
                    style:
                        AppTheme.mono(fontSize: 11, color: t.fgSubtle),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The event families a timeline node can carry. The colour names the family;
/// it is not decoration.
enum KitNodeTone { accent, sage, plum, ink }

/// §4.2 — the activity timeline.
///
/// A continuous 1px **spine** runs behind the whole list, with a 32px surface
/// **node** per row sitting on it. The `-12px` inset is carried by **every
/// row**, linked or not, so the dividers stay one width and only the hover fill
/// distinguishes a row that leads somewhere.
class KitTimeline extends StatelessWidget {
  final List<Widget> rows;

  const KitTimeline({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Stack(
      children: [
        Positioned(
          left: 15,
          top: 6,
          bottom: 6,
          child: Container(width: 1, color: t.rule),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Container(height: 1, color: t.rule),
              rows[i],
            ],
          ],
        ),
      ],
    );
  }
}

/// §4.2 — one timeline row: node · `[chip · subject]` over a detail line ·
/// trailing timestamp.
///
/// A row that leads somewhere is a link whose affordance is **deliberately
/// quiet** — the feed is a record first, so it reads as a row until hovered.
class KitTimelineRow extends StatefulWidget {
  final IconData icon;
  final KitNodeTone tone;

  /// Mono caps, e.g. `INDEXED`.
  final String chip;
  final String subject;
  final String? detail;
  final String time;
  final VoidCallback? onTap;

  /// Adds the pulsing ring. Suppressed under `prefers-reduced-motion`.
  final bool live;

  const KitTimelineRow({
    super.key,
    required this.icon,
    this.tone = KitNodeTone.ink,
    required this.chip,
    required this.subject,
    this.detail,
    required this.time,
    this.onTap,
    this.live = false,
  });

  @override
  State<KitTimelineRow> createState() => _KitTimelineRowState();
}

class _KitTimelineRowState extends State<KitTimelineRow>
    with SingleTickerProviderStateMixin {
  bool _hover = false;
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _pulse = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1800))
        ..repeat();
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  Color _toneColor(Tokens t) => switch (widget.tone) {
        KitNodeTone.accent => t.accent,
        KitNodeTone.sage => t.positive,
        KitNodeTone.plum => t.isDark ? const Color(0xFFB99BB6) : t.chrome,
        KitNodeTone.ink => t.fgMuted,
      };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    Widget node = Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: t.surface,
        shape: BoxShape.circle,
        border: Border.all(color: t.border),
        boxShadow: AppShadows.s1,
      ),
      child: Icon(widget.icon, size: 15, color: _toneColor(t)),
    );

    if (widget.live && !reduceMotion && _pulse != null) {
      node = Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _pulse!,
            builder: (context, _) {
              final v = _pulse!.value;
              return Opacity(
                opacity: v < 0.7 ? (0.55 * (1 - v / 0.7)) : 0,
                child: Transform.scale(
                  scale: 0.85 + v * 0.4,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: _toneColor(t), width: 1.5),
                    ),
                  ),
                ),
              );
            },
          ),
          node,
        ],
      );
    }

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: _hover && widget.onTap != null
                ? t.hover
                : const Color(0x00000000),
            borderRadius: AppRadius.smR,
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 32, child: Center(child: node)),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 9,
                        runSpacing: 4,
                        children: [
                          Text(widget.chip.toUpperCase(),
                              style: KitText.capsLabel(context,
                                  fontSize: 10,
                                  letterSpacing: 0.1,
                                  color: t.fgSubtle)),
                          Text(
                            widget.subject,
                            style: TextStyle(
                              fontFamily: AppTheme.fontSans,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: t.fg,
                              decoration: _hover && widget.onTap != null
                                  ? TextDecoration.underline
                                  : null,
                              decorationColor: t.linkDecor,
                            ),
                          ),
                        ],
                      ),
                      if (widget.detail != null) ...[
                        const SizedBox(height: 3),
                        Text(widget.detail!,
                            style: TextStyle(
                              fontFamily: AppTheme.fontSans,
                              fontSize: 13,
                              color: t.fgMuted,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s4),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(widget.time,
                    style:
                        AppTheme.mono(fontSize: 12, color: t.fgSubtle)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
