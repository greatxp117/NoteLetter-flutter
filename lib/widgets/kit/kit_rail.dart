import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_failure.dart';
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

/// §9.1 — one action in an entry's trailing cluster.
///
/// [danger] is carried but **not painted at rest**: the pattern says a
/// destructive action declares itself on hover only, because a cluster that is
/// red at rest reads as a row in trouble. This client has no hover — every
/// device it ships to is a coarse pointer — so the flag reaches the semantics
/// and the confirmation, never the glyph. The colour is not "missing" here; the
/// state it belongs to does not exist on this client.
class KitRailEntryAction {
  final IconData icon;

  /// Spoken by a screen reader and shown as a tooltip. Name the object, not the
  /// verb alone: "Delete" in a list of twelve names nothing.
  final String label;
  final bool danger;
  final VoidCallback onPressed;

  const KitRailEntryAction({
    required this.icon,
    required this.label,
    this.danger = false,
    required this.onPressed,
  });
}

/// One entry: a truncating serif title, a mono trailing time, and a 2-line
/// preview. Active adds the 2px `--accent` bar and a raised `--surface` fill.
///
/// The preview is a **required part of the entry as drawn**, and it has to be
/// backed by something real — the reference stores it on the thread for exactly
/// that reason (4.54.0). A rail entry that pads its second line with a derived
/// count or a re-stated title is the prototype defect.
///
/// **§9.1 entry actions** (4.55.0, ADR-091) are optional and, where present,
/// change two things about the entry. The actions are **siblings** of the thing
/// that opens it — never nested inside it — and the **trailing time yields** to
/// the cluster rather than sharing the row with it, because 320px holds a
/// truncating title and one of the two. The reference reveals the cluster on
/// hover and keeps it unconditionally under a coarse pointer; here there is
/// only the second case, so it is simply always there.
class KitRailEntry extends StatefulWidget {
  final String title;
  final String? time;
  final String? preview;
  final bool active;
  final VoidCallback onTap;

  /// §9.1. Empty is the plain §9 entry, which is the whole pattern on a rail
  /// whose entries are only ever opened.
  final List<KitRailEntryAction> actions;

  /// Draw the title as an in-place field instead — §9.1's rename, in the
  /// title's own type role and never in a dialog. Seeded from [title].
  final bool renaming;

  /// Commits (submit or focus loss) and abandons (Escape). The title must move
  /// only when the CALL resolves, so the host keeps [renaming] true until then
  /// — a field that closes on submit paints a rename that may not have landed.
  final ValueChanged<String>? onRenameCommit;
  final VoidCallback? onRenameCancel;

  /// While the rename or the delete is in flight: the field stops taking edits
  /// and the cluster stops taking taps.
  final bool busy;

  /// §14.2 inline, dense, in this entry's own flow. The request was about one
  /// conversation and so is the failure — never a rail-wide banner.
  final String? error;

  const KitRailEntry({
    super.key,
    required this.title,
    this.time,
    this.preview,
    this.active = false,
    required this.onTap,
    this.actions = const [],
    this.renaming = false,
    this.onRenameCommit,
    this.onRenameCancel,
    this.busy = false,
    this.error,
  });

  @override
  State<KitRailEntry> createState() => _KitRailEntryState();
}

class _KitRailEntryState extends State<KitRailEntry> {
  bool _hover = false;

  /// Owned here, not by the host: the field IS the title in its own type role,
  /// and a controller the host passes down is one more thing to seed, dispose
  /// and keep in step with a list that rebuilds from a subscription.
  TextEditingController? _rename;
  FocusNode? _renameFocus;

  @override
  void initState() {
    super.initState();
    if (widget.renaming) _openRename();
  }

  @override
  void didUpdateWidget(KitRailEntry old) {
    super.didUpdateWidget(old);
    if (widget.renaming && !old.renaming) {
      _openRename();
    } else if (!widget.renaming && old.renaming) {
      _closeRename();
    }
  }

  void _openRename() {
    _rename = TextEditingController(text: widget.title)
      ..selection = TextSelection(
          baseOffset: 0, extentOffset: widget.title.characters.length);
    _renameFocus = FocusNode();
    // Focus after the frame the field is built in — requesting it during a
    // build attaches to a node that is not in the tree yet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.renaming) _renameFocus?.requestFocus();
    });
  }

  void _closeRename() {
    _rename?.dispose();
    _renameFocus?.dispose();
    _rename = null;
    _renameFocus = null;
  }

  @override
  void dispose() {
    _closeRename();
    super.dispose();
  }

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
                          child: widget.renaming && _rename != null
                              ? _RenameField(
                                  controller: _rename!,
                                  focus: _renameFocus!,
                                  enabled: !widget.busy,
                                  onCommit: widget.onRenameCommit,
                                  onCancel: widget.onRenameCancel,
                                )
                              : Text(
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
                        // §9.1: the time YIELDS to the cluster. It is not
                        // squeezed beside it — 320px holds a truncating title
                        // and one of the two, and the one that can be acted on
                        // wins.
                        if (widget.actions.isEmpty &&
                            !widget.renaming &&
                            widget.time != null &&
                            widget.time!.isNotEmpty) ...[
                          const SizedBox(width: AppSpacing.s2),
                          Text(
                            widget.time!,
                            style: AppTheme.mono(
                              fontSize: 10,
                              color: widget.active ? t.accentText : t.fgSubtle,
                            ),
                          ),
                        ],
                        if (widget.actions.isNotEmpty && !widget.renaming) ...[
                          const SizedBox(width: AppSpacing.s2),
                          for (final a in widget.actions)
                            _RailEntryActionButton(
                                action: a, enabled: !widget.busy),
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
                    // §14.2, dense, in THIS entry's flow — a rail is a dense
                    // control group by that pattern's own metric.
                    if (widget.error != null) ...[
                      const SizedBox(height: 4),
                      KitFailureInline(widget.error!, dense: true),
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

/// §9.1 — one icon button in an entry's trailing cluster. §6.5's icon button at
/// the rail's scale: 24×24, `--r-sm`, icon 14 at the app's uniform stroke.
///
/// It is a real control with a real label, not a tappable glyph: a rail of
/// twelve conversations announcing "Delete" twelve times tells a screen reader
/// nothing about which one.
class _RailEntryActionButton extends StatelessWidget {
  final KitRailEntryAction action;
  final bool enabled;

  const _RailEntryActionButton({required this.action, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      label: action.label,
      child: Tooltip(
        message: action.label,
        child: InkWell(
          onTap: enabled ? action.onPressed : null,
          borderRadius: AppRadius.smR,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Icon(
              action.icon,
              size: 14,
              color: enabled ? t.fgSubtle : t.fgSubtle.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// §9.1's rename, in place, in the **title's own type role** — the same serif
/// 14/600 the title is drawn in, so the edit happens where the reader is
/// looking rather than in a dialog somewhere else.
///
/// Commits on submit and on focus loss; abandons on Escape. Escape must also
/// stop the focus loss it CAUSES from committing the draft it just abandoned,
/// which is what [_abandoned] is for.
class _RenameField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool enabled;
  final ValueChanged<String>? onCommit;
  final VoidCallback? onCancel;

  const _RenameField({
    required this.controller,
    required this.focus,
    required this.enabled,
    this.onCommit,
    this.onCancel,
  });

  @override
  State<_RenameField> createState() => _RenameFieldState();
}

class _RenameFieldState extends State<_RenameField> {
  bool _abandoned = false;

  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_onFocus);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    if (widget.focus.hasFocus || _abandoned || !mounted) return;
    widget.onCommit?.call(widget.controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _abandoned = true;
          widget.onCancel?.call();
        },
      },
      child: TextField(
        controller: widget.controller,
        focusNode: widget.focus,
        enabled: widget.enabled,
        maxLines: 1,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => widget.onCommit?.call(v),
        style: AppTheme.serif(
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: t.fg,
        ),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: t.surfaceRaised,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          border: OutlineInputBorder(
            borderRadius: AppRadius.smR,
            borderSide: BorderSide(color: t.accentChipBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.smR,
            borderSide: BorderSide(color: t.accentChipBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.smR,
            borderSide: BorderSide(color: t.accentChipBorder),
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
