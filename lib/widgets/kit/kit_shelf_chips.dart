import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/tag.dart';
import '../../shared/shelf_pick.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_failure.dart';

/// One chip in a §20 row: the shelf, and whether the item has it only because
/// its document does (the muted weight).
class KitShelfChip {
  final Tag shelf;
  final bool inherited;
  const KitShelfChip(this.shelf, {this.inherited = false});
}

/// §20 · Shelf chip editor (4.83.0, ADR-117) with its §20.1 Shelf picker
/// (4.104.0, ADR-137). Mirrors the reference's `shared/ShelfChipEditor.jsx`.
///
/// **Presentational.** The host owns every write, and the chips it passes are
/// what the last READ said: write before you move, so nothing here changes
/// until the host's call resolves and it rebuilds with new chips. While a write
/// is in flight ([busy]) every control is disabled.
///
/// Required parts: an optional mono caps [label] (the reader's `Shelves`) ·
/// one chip per shelf — a 6px dot in its stored colour, hairline-bordered, the
/// title, a remove control whose accessible name says what comes off what · the
/// dashed `+ Shelf` add control, **always present** · the §14.2 inline
/// rejection in its dense form beside the row.
///
/// The add control opens §20.1 — a search field, the shelves not on the item
/// ranked by `shared/shelf_pick.dart`, and a create row that is always last.
/// Choosing a shelf calls [onAdd]; the create row calls [onCreate] with the
/// query, and the host opens the create form with it.
class KitShelfChipEditor extends StatefulWidget {
  final String? label;
  final List<KitShelfChip> chips;
  final List<Tag> addable;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;
  final ValueChanged<String> onCreate;
  final bool busy;
  final String? error;
  final String Function(Tag shelf) removeLabel;

  const KitShelfChipEditor({
    super.key,
    this.label,
    required this.chips,
    required this.addable,
    required this.onAdd,
    required this.onRemove,
    required this.onCreate,
    required this.removeLabel,
    this.busy = false,
    this.error,
  });

  /// `.shelf-pick` width. The panel never exceeds the viewport less 32.
  static const double panelWidth = 288;

  @override
  State<KitShelfChipEditor> createState() => _KitShelfChipEditorState();
}

class _KitShelfChipEditorState extends State<KitShelfChipEditor> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  final _plusKey = GlobalKey();
  final _plusFocus = FocusNode(debugLabel: 'KitShelfChipEditor.add');
  final _group = Object();

  /// The panel's slide from the add control's leading edge, or null while it
  /// is closed.
  double? _shift;
  double _width = KitShelfChipEditor.panelWidth;

  @override
  void dispose() {
    _plusFocus.dispose();
    super.dispose();
  }

  /// Flush to the add control's leading edge, slid back only as far as keeps
  /// it 16px inside the viewport — measured on the PRESS, before the panel
  /// exists, which is when the reference measures too (§20.1 Behaviour).
  void _open() {
    final box = _plusKey.currentContext?.findRenderObject() as RenderBox?;
    final vw = MediaQuery.sizeOf(context).width;
    final left = box?.localToGlobal(Offset.zero).dx ?? 0;
    final w = math.min(KitShelfChipEditor.panelWidth, vw - 32);
    var x = math.min(0.0, vw - 16 - w - left);
    if (left + x < 16) x = 16 - left;
    setState(() {
      _shift = x;
      _width = w;
    });
    _portal.show();
  }

  void _close({bool refocus = true}) {
    if (_shift == null) return;
    _portal.hide();
    setState(() => _shift = null);
    if (refocus) _plusFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final label = widget.label;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Text(label.toUpperCase(), style: _labelStyle(t)),
          ),
        for (final c in widget.chips) _chip(context, t, c),
        _addControl(t),
        if (widget.error != null) KitFailureInline(widget.error!, dense: true),
      ],
    );
  }

  Widget _chip(BuildContext context, Tokens t, KitShelfChip c) {
    final colour = AppColors.shelfColor(c.shelf.color); // pair-ok: a shelf's stored colour is a fixed data token
    final direct = !c.inherited;
    return Container(
      height: 20,
      padding: const EdgeInsets.only(left: 7, right: 4),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(AppRadius.control(20)),
        border: Border.all(
            color: direct ? (colour ?? t.borderStrong) : t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: direct ? 1 : 0.55,
            child: _Dot(size: 6, color: colour ?? t.fgSubtle, hairline: t.border),
          ),
          const SizedBox(width: 5),
          Text(c.shelf.title,
              style: _chipStyle(direct ? t.fg : t.fgMuted)),
          const SizedBox(width: 3),
          Semantics(
            button: true,
            label: widget.removeLabel(c.shelf),
            excludeSemantics: true,
            child: _RoundTap(
              size: 16,
              enabled: !widget.busy,
              onTap: () => widget.onRemove(c.shelf.id),
              child: Icon(Icons.close, size: 10, color: t.fgSubtle),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addControl(Tokens t) {
    final open = _shift != null;
    return TapRegion(
      groupId: _group,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            left: 0,
            top: 0,
            width: _width,
            child: CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomLeft,
              followerAnchor: Alignment.topLeft,
              offset: Offset(_shift ?? 0, 6),
              child: TapRegion(
                groupId: _group,
                onTapOutside: (_) => _close(refocus: false),
                child: _ShelfPickerPanel(
                  onItem: [for (final c in widget.chips) c.shelf],
                  addable: widget.addable,
                  onPick: (id) {
                    _close();
                    widget.onAdd(id);
                  },
                  onCreate: (name) {
                    _close(refocus: false);
                    widget.onCreate(name);
                  },
                  onEscape: _close,
                ),
              ),
            ),
          ),
          child: Semantics(
            button: true,
            expanded: open,
            label: 'Add a shelf',
            excludeSemantics: true,
            child: Focus(
              focusNode: _plusFocus,
              child: _DashedTap(
                key: _plusKey,
                enabled: !widget.busy,
                onTap: () => open ? _close(refocus: false) : _open(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 11, color: t.fgSubtle),
                    const SizedBox(width: 4),
                    Text('Shelf', style: _chipStyle(t.fgSubtle)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

TextStyle _labelStyle(Tokens t) => AppTheme.mono(
    fontSize: 10, letterSpacing: 1, color: t.fgSubtle);

TextStyle _chipStyle(Color c) =>
    TextStyle(fontFamily: AppTheme.fontSans, fontSize: 11, color: c);

/// §20.1's panel. A combobox: focus stays in the search field, one row is
/// active, ↑/↓ move it through the list and on to the create row (stopping at
/// the ends), Enter chooses it, Esc closes. Typing resets it to the first.
class _ShelfPickerPanel extends StatefulWidget {
  final List<Tag> onItem;
  final List<Tag> addable;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onCreate;
  final VoidCallback onEscape;

  const _ShelfPickerPanel({
    required this.onItem,
    required this.addable,
    required this.onPick,
    required this.onCreate,
    required this.onEscape,
  });

  @override
  State<_ShelfPickerPanel> createState() => _ShelfPickerPanelState();
}

class _ShelfPickerPanelState extends State<_ShelfPickerPanel> {
  final _q = TextEditingController();
  final _focus = FocusNode(debugLabel: 'ShelfPicker.search');
  final _scroll = ScrollController();
  int _active = 0;
  bool _in = false;

  /// 32px, 40 at ≤ 680 — a phone's touch target (§20.1 reference metrics).
  double get _rowH => MediaQuery.sizeOf(context).width <= 680 ? 40 : 32;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      setState(() => _in = true);
    });
  }

  @override
  void dispose() {
    _q.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _choose(List<PickRow> rows, PickState st, int i) {
    if (i < rows.length) {
      widget.onPick(rows[i].shelf.id);
    } else {
      widget.onCreate(st.createName);
    }
  }

  void _keepInView(int i, int rowCount) {
    if (!_scroll.hasClients || i >= rowCount) return;
    final top = i * (_rowH + 1);
    final pos = _scroll.position;
    if (top < pos.pixels) {
      _scroll.jumpTo(top);
    } else if (top + _rowH > pos.pixels + pos.viewportDimension) {
      _scroll.jumpTo(top + _rowH - pos.viewportDimension);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final rows = pickRows(widget.addable, _q.text);
    final st = pickState(
        onItem: widget.onItem, addable: widget.addable, q: _q.text, rows: rows);
    final count = rows.length + 1; // the create row is always last
    final at = math.min(_active, count - 1);

    KeyEventResult onKey(FocusNode _, KeyEvent e) {
      if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
        return KeyEventResult.ignored;
      }
      final k = e.logicalKey;
      if (k == LogicalKeyboardKey.arrowDown) {
        final n = math.min(at + 1, count - 1);
        setState(() => _active = n);
        _keepInView(n, rows.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.arrowUp) {
        final n = math.max(at - 1, 0);
        setState(() => _active = n);
        _keepInView(n, rows.length);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.enter ||
          k == LogicalKeyboardKey.numpadEnter) {
        _choose(rows, st, at);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.escape) {
        widget.onEscape();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    return AnimatedOpacity(
      opacity: _in ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _in ? Offset.zero : const Offset(0, -0.02),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Material(
          type: MaterialType.transparency,
          child: Container(
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              borderRadius: AppRadius.mdR,
              border: Border.all(color: t.border),
              boxShadow: AppShadows.s2,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(t, onKey),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: Container(
                    decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: t.rule))),
                    child: ListView(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(5),
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                                bottom: i == rows.length - 1 ? 0 : 1),
                            child: _row(t, i == at, i,
                                onTap: () => _choose(rows, st, i),
                                child: _shelfRow(t, rows[i])),
                          ),
                        if (st.empty != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
                            child: Text(st.empty!, style: _emptyStyle(t)),
                          ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(5),
                  child: _row(t, at == rows.length, rows.length,
                      onTap: () => _choose(rows, st, rows.length),
                      child: _createRow(t, st.createName)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(Tokens t, FocusOnKeyEventCallback onKey) => Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: t.rule))),
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: t.fgSubtle),
            const SizedBox(width: 9),
            Expanded(
              child: Focus(
                onKeyEvent: onKey,
                child: TextField(
                  key: const ValueKey('shelf-pick-search'),
                  controller: _q,
                  focusNode: _focus,
                  autocorrect: false,
                  enableSuggestions: false,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    // A soft keyboard's Done arrives here, not as a key event.
                    final rows = pickRows(widget.addable, _q.text);
                    final st = pickState(
                        onItem: widget.onItem,
                        addable: widget.addable,
                        q: _q.text,
                        rows: rows);
                    _choose(rows, st, math.min(_active, rows.length));
                  },
                  onChanged: (_) => setState(() => _active = 0),
                  style: AppTheme.serif(fontSize: 16, height: 22 / 16, color: t.fg),
                  cursorColor: t.fg,
                  // Every border named, not `InputDecoration.collapsed`:
                  // collapsed clears the RESTING border only, and the app
                  // theme's focusedBorder drew a rounded outline round a field
                  // that is always focused (the first device frame). §20.1's
                  // field is a bare input on the panel, closed by its rule.
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Find or create a shelf…',
                    hintStyle: AppTheme.serif(
                        fontSize: 16,
                        height: 22 / 16,
                        fontStyle: FontStyle.italic,
                        color: t.fgSubtle),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _row(Tokens t, bool on, int i,
          {required VoidCallback onTap, required Widget child}) =>
      Semantics(
        button: true,
        selected: on,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (_) {
            if (_active != i) setState(() => _active = i);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              key: ValueKey('shelf-pick-row-$i'),
              constraints: BoxConstraints(minHeight: _rowH),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: on ? t.hoverStrong : null,
                borderRadius: BorderRadius.circular(AppRadius.control(_rowH)),
              ),
              alignment: Alignment.centerLeft,
              child: child,
            ),
          ),
        ),
      );

  Widget _shelfRow(Tokens t, PickRow r) {
    final title = r.shelf.title;
    final m = r.match;
    final base = _rowStyle(t);
    return Row(
      children: [
        _Dot(
            size: 8,
            color: AppColors.shelfColor(r.shelf.color) ?? t.fgSubtle, // pair-ok: a shelf's stored colour is a fixed data token
            hairline: t.border),
        const SizedBox(width: 9),
        Expanded(
          child: Text.rich(
            TextSpan(style: base, children: [
              TextSpan(text: title.substring(0, m.start)),
              TextSpan(
                  text: title.substring(m.start, m.end),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              TextSpan(text: title.substring(m.end)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Only a stored count is a figure (ADR-109). `--fg-muted`, not
        // `--fg-subtle`: it sits on the active row's `--hover-strong`, where
        // the quieter tier measured under the 11px text floor on the web.
        if (r.shelf.documentCountStored) ...[
          const SizedBox(width: 9),
          Text('${r.shelf.documentCount}',
              style: AppTheme.mono(fontSize: 11, color: t.fgMuted)),
        ],
      ],
    );
  }

  Widget _createRow(Tokens t, String name) => Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration:
                BoxDecoration(color: t.accentSoft, shape: BoxShape.circle),
            child: Icon(Icons.add, size: 12, color: t.accentText),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text.rich(
              name.isEmpty
                  ? const TextSpan(text: 'New shelf…')
                  : TextSpan(children: [
                      const TextSpan(text: 'Create '),
                      TextSpan(
                          text: '“$name”',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
              style: _rowStyle(t),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
}

TextStyle _rowStyle(Tokens t) => TextStyle(
    fontFamily: AppTheme.fontSans, fontSize: 13, height: 1.3, color: t.fg);

TextStyle _emptyStyle(Tokens t) => AppTheme.serif(
    fontSize: 14, height: 20 / 14, fontStyle: FontStyle.italic, color: t.fgMuted);

/// A shelf's dot — its stored colour with the hairline every swatch carries
/// (§6.2), because two of the ten sit close to the dark page.
class _Dot extends StatelessWidget {
  final double size;
  final Color color;
  final Color hairline;
  const _Dot({required this.size, required this.color, required this.hairline});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: hairline, width: 1),
        ),
      );
}

/// The chip's remove control: 16px round, `--hover` under the pointer.
class _RoundTap extends StatefulWidget {
  final double size;
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  const _RoundTap(
      {required this.size,
      required this.enabled,
      required this.onTap,
      required this.child});

  @override
  State<_RoundTap> createState() => _RoundTapState();
}

class _RoundTapState extends State<_RoundTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _hover && widget.enabled ? t.hover : null,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The dashed `+ Shelf` control — 20px, `0 8px`, 1px dashed `--border-strong`.
class _DashedTap extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  final Widget child;
  const _DashedTap(
      {super.key,
      required this.enabled,
      required this.onTap,
      required this.child});

  @override
  State<_DashedTap> createState() => _DashedTapState();
}

class _DashedTapState extends State<_DashedTap> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final r = AppRadius.control(20);
    return MouseRegion(
      cursor: widget.enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: Container(
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: _hover && widget.enabled ? t.hover : null,
              borderRadius: BorderRadius.circular(r),
            ),
            foregroundDecoration:
                _Dashed(color: t.borderStrong, radius: r),
            // No `alignment`: a Container with one takes all the width it is
            // offered, and in the row's Wrap that is a whole line — the add
            // control dropped under the chips at full width (the first frame).
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _Dashed extends Decoration {
  final Color color;
  final double radius;
  const _Dashed({required this.color, required this.radius});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _DashedPainter(this);
}

class _DashedPainter extends BoxPainter {
  final _Dashed d;
  _DashedPainter(this.d);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size;
    if (size == null) return;
    final rect = (offset & size).deflate(0.5);
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(d.radius)));
    final paint = Paint()
      ..color = d.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += 5) {
        canvas.drawPath(metric.extractPath(at, at + 3), paint);
      }
    }
  }
}
