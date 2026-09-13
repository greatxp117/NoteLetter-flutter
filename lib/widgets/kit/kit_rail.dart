import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §9 — the **Inspector rail**: a secondary column beside the main content.
///
/// **Required parts** — a header with a mono caps title and an optional close
/// control · a scroll region · grouped entries under mono caps group labels ·
/// an **active entry marked by a 2px `--accent` bar in the leading margin**
/// plus a raised surface fill. The bar is the part that gets dropped, and
/// without it the active entry is marked by fill alone — which is colour alone,
/// the one marking §1.2 already forbids for the chrome rail.
///
/// **On a phone the rail is an overlay** with a backdrop and a **visible close
/// control**; the grouping, the labels and the active marker do not change.
/// That is not this client adapting a desktop column — it is §9's own phone
/// form, and it is the form every Flutter surface takes, since this app is
/// below the compact breakpoint on every device it ships to.
///
/// This pattern had **no live consumer on any client** until 4.53.0 (ADR-090):
/// it was transcribed at 4.5.0 from `.ask-rail*`/`.convo*`, seventeen classes
/// in the web stylesheet that nothing mounted. Ask is its first, on web and
/// here. Do not confuse it with `KitRailGroupLabel`/`KitRailCard` in
/// `kit_shell.dart` — those are the **chrome rail** (§1.2), a different pattern
/// that happens to share a word.
class KitInspectorRail extends StatelessWidget {
  /// Mono caps, in the header.
  final String title;

  /// The overlay's close control. Required on the phone form — an overlay a
  /// reader cannot dismiss is a trap — and omitted only where the rail is a
  /// column that never covers anything.
  final VoidCallback? onClose;

  /// The dashed control above the entries. Goes solid + `--accent-soft` when
  /// [newActive] — which is what "no conversation is open" looks like, rather
  /// than the rail having no marked entry at all.
  final String newLabel;
  final VoidCallback? onNew;
  final bool newActive;

  /// Groups, in order. Each renders its mono caps label then its entries.
  final List<KitRailGroup> groups;

  /// Rendered in the scroll region instead of the groups — a §14.1 block when
  /// the list could not be read, or a quiet line while it loads. An empty rail
  /// and a rail that failed are different pictures (INV-24).
  final Widget? notice;

  final double width;

  const KitInspectorRail({
    super.key,
    required this.title,
    this.onClose,
    this.newLabel = 'New',
    this.onNew,
    this.newActive = false,
    this.groups = const [],
    this.notice,
    this.width = 320,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(right: BorderSide(color: t.rule)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s5, AppSpacing.s5, AppSpacing.s3, AppSpacing.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: KitText.capsLabel(context,
                          color: t.fgMuted, letterSpacing: 0.14),
                    ),
                  ),
                  if (onClose != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 17),
                      color: t.fgMuted,
                      onPressed: onClose,
                      tooltip: 'Close',
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s3, 0, AppSpacing.s3, AppSpacing.s5),
                children: [
                  if (onNew != null)
                    _RailNewControl(
                      label: newLabel,
                      active: newActive,
                      onTap: onNew!,
                    ),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s3),
                      child: notice!,
                    )
                  else
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.s3,
                            AppSpacing.s3, AppSpacing.s3, 5),
                        child: Text(
                          g.label.toUpperCase(),
                          style: KitText.capsLabel(context,
                              color: t.fgSubtle,
                              fontSize: 10,
                              letterSpacing: 0.12),
                        ),
                      ),
                      ...g.entries,
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled group of [KitRailEntry] rows.
class KitRailGroup {
  final String label;
  final List<Widget> entries;

  const KitRailGroup({required this.label, required this.entries});
}

/// One entry: a truncating serif title, a mono trailing time, and a 2-line
/// preview. Active adds the 2px `--accent` bar and a raised `--surface` fill.
///
/// The preview is a **required part of the entry as drawn**, and it has to be
/// backed by something real — the reference stores it on the thread for exactly
/// that reason (4.54.0). A rail entry that pads its second line with a derived
/// count or a re-stated title is the prototype defect.
class KitRailEntry extends StatefulWidget {
  final String title;
  final String? time;
  final String? preview;
  final bool active;
  final VoidCallback onTap;

  const KitRailEntry({
    super.key,
    required this.title,
    this.time,
    this.preview,
    this.active = false,
    required this.onTap,
  });

  @override
  State<KitRailEntry> createState() => _KitRailEntryState();
}

class _KitRailEntryState extends State<KitRailEntry> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: widget.active
                ? t.surface
                : (_hover ? t.hover : const Color(0x00000000)),
            borderRadius: AppRadius.smR,
            boxShadow: widget.active ? AppShadows.s1 : null,
          ),
          child: Stack(
            children: [
              // The 2px accent bar in the leading margin. Not colour alone:
              // the fill above and this bar are two markings, deliberately.
              if (widget.active)
                Positioned(
                  left: 0,
                  top: 9,
                  bottom: 9,
                  width: 2,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: t.accent,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s3, vertical: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.serif(
                              fontSize: 14,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                              color: t.fg,
                            ),
                          ),
                        ),
                        if (widget.time != null && widget.time!.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.s2),
                          Text(
                            widget.time!,
                            style: AppTheme.mono(
                              fontSize: 10,
                              color: widget.active ? t.accentText : t.fgSubtle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (widget.preview != null &&
                        widget.preview!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.preview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 12,
                          height: 16 / 12,
                          color: t.fgMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dashed new-conversation control. Solid + `--accent-soft` when active.
class _RailNewControl extends StatefulWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RailNewControl({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  State<_RailNewControl> createState() => _RailNewControlState();
}

class _RailNewControlState extends State<_RailNewControl> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final solid = widget.active;
    final fg = solid ? t.accentChipFg : t.fg;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.s2),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3, vertical: 10),
          decoration: solid
              ? BoxDecoration(
                  color: t.accentSoft,
                  borderRadius: AppRadius.smR,
                  border: Border.all(color: t.accentChipBorder),
                )
              : BoxDecoration(
                  color: _hover ? t.surface : const Color(0x00000000),
                  borderRadius: AppRadius.smR,
                ),
          // Flutter has no dashed border primitive, so the idle state's dashes
          // are painted. A solid border here would read as the ACTIVE state,
          // which is the one distinction this control carries.
          foregroundDecoration: solid
              ? null
              : _DashedRailBorder(
                  color: _hover ? t.accentChipBorder : t.borderStrong,
                  radius: AppRadius.sm,
                ),
          child: Row(
            children: [
              Icon(Icons.add, size: 15, color: fg),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRailBorder extends Decoration {
  final Color color;
  final double radius;

  const _DashedRailBorder({required this.color, required this.radius});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedRailPainter(color: color, radius: radius);
}

class _DashedRailPainter extends BoxPainter {
  final Color color;
  final double radius;

  _DashedRailPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(offset.dx + 0.5, offset.dy + 0.5, size.width - 1,
          size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    const dash = 4.0;
    const gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }
}
