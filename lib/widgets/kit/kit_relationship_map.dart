import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart'
    show
        Icons,
        Material,
        MaterialType,
        TextField,
        InputDecoration,
        UnderlineInputBorder,
        InputBorder,
        Tooltip;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../shared/relmap_layout.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_frame.dart' show KitScrollView;

/// §24 — the Relationship map (5.25.0, ADR-177): shelves and the volumes on
/// them as one layered graph that reads child → parent, left to right.
///
/// Composed from the WEB reference, `pages/map/RelMap.jsx` and
/// `styles/app-map.css`, over the pure `shared/relmap_layout.dart`. 10MB's
/// `map_screen.dart` gave this file its skeleton — `InteractiveViewer` over a
/// sized canvas, `CustomPaint` for the wires — and none of its four defects
/// (ADR-177 §Rationale):
///   · full screen opens FITTED, through a [TransformationController], as the
///     inline canvas does; 10MB opened it at 1:1;
///   · a search match draws the marker pair (`--highlight` fill,
///     `--border-strong` ring);
///   · a wire takes its PARENT shelf's colour token, never the border's;
///   · a wire runs centre to centre beneath the chips, so no chip width — 10MB
///     assumed 172 — enters its geometry, and a chip sizes to its content.
///
/// Required parts, top to bottom: the toolbar (legend, search), the inspector
/// strip, the canvas (column headers, wires, chips) with the view controls
/// pinned over its top-left corner. Full screen covers the app with all of it
/// on `--bg`.
///
/// Departures, each because Flutter has no counterpart: no inner shadow on the
/// canvas (`--shadow-inset`; a hairline would be a different mark, so none);
/// hover (`--shadow-2`) reaches a mouse only; a drag past 4px never selects
/// (web's rule) and the viewer's pan takes over at 8, twice the slop.
class KitRelationshipMap extends StatefulWidget {
  final MapGraph graph;

  /// A node to select and centre on arrival — a shelf's *See on map*.
  final String? focusKey;

  /// The documents subscription's limit, for the window label.
  final int windowSize;

  /// Leave the map for a node: the reader for a volume, the shelf's page for a
  /// shelf.
  final ValueChanged<MapNode> onOpen;

  const KitRelationshipMap({
    super.key,
    required this.graph,
    this.focusKey,
    this.windowSize = documentWindow,
    required this.onOpen,
  });

  @override
  State<KitRelationshipMap> createState() => _KitRelationshipMapState();
}

// Zoom clamps to 0.2–4×; the buttons step ×1.2 about the centre.
const double _zMin = 0.2;
const double _zMax = 4;
double _clampZ(double z) => z.clamp(_zMin, _zMax).toDouble();

// A gesture that moved this far is a pan, never a tap on what it started on.
const double _dragSlop = 4;

// A focused node is shown at no smaller than this, so arriving from a shelf on
// a fitted 200-volume map does not centre a chip too small to read.
const double _focusZoom = 0.75;

// The view controls sit over the canvas's top-left corner, so a fitted graph
// is fitted into the band BELOW them (web `CTRL_CLEAR`).
const double _ctrlClear = 64;

/// What the inline map and its full-screen page share: one selection, one
/// search, one hover — so leaving full screen keeps what was lit.
class _MapSession extends ChangeNotifier {
  MapGraph graph;
  String? selected;
  String? hover;

  /// Focus on arrival, consumed by the first canvas that lays the graph out.
  String? pendingFocus;
  final TextEditingController query = TextEditingController();
  final List<_CanvasState> _canvases = [];

  _MapSession(this.graph, String? focus) {
    if (focus != null && graph.nodes.containsKey(focus)) {
      selected = focus;
      pendingFocus = focus;
    }
    query.addListener(notifyListeners);
  }

  bool get anyQuery => query.text.trim().isNotEmpty;

  void setGraph(MapGraph g) {
    graph = g;
    // A selection that no longer exists (its shelf deleted under us) is
    // dropped.
    if (selected != null && !g.nodes.containsKey(selected)) selected = null;
    notifyListeners();
  }

  void toggle(String key) {
    selected = selected == key ? null : key;
    notifyListeners();
  }

  void clearSelection() {
    if (selected == null) return;
    selected = null;
    notifyListeners();
  }

  void setHover(String? key) {
    if (hover == key) return;
    hover = key;
    notifyListeners();
  }

  /// The inspector's relation chips and Enter: select, and centre it.
  void selectAndCentre(String key) {
    selected = key;
    notifyListeners();
    if (_canvases.isNotEmpty) _canvases.last.centreOnKeepingZoom(key);
  }

  void enter() {
    final c = _canvases.isEmpty ? null : _canvases.last;
    final pos = c?._layout?.pos;
    if (pos == null) return;
    final first = firstInLayout(searchMatches(graph, query.text), pos);
    if (first != null) selectAndCentre(first);
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }
}

class _KitRelationshipMapState extends State<KitRelationshipMap> {
  late final _MapSession _s = _MapSession(widget.graph, widget.focusKey);

  @override
  void didUpdateWidget(KitRelationshipMap old) {
    super.didUpdateWidget(old);
    if (!identical(old.graph, widget.graph)) _s.setGraph(widget.graph);
  }

  @override
  void dispose() {
    _s.dispose();
    super.dispose();
  }

  void _enterFullScreen() {
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (ctx, _, _) => _FullScreenMap(
          session: _s,
          windowSize: widget.windowSize,
          onOpen: (n) {
            Navigator.of(ctx).pop();
            widget.onOpen(n);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _MapBody(
    session: _s,
    fullscreen: false,
    windowSize: widget.windowSize,
    onOpen: widget.onOpen,
    onToggleFullScreen: _enterFullScreen,
  );
}

/// Full screen covers the app — the canvas, its controls, the toolbar and the
/// inspector — on `--bg` (`.rm.rm-fs`, padding 12/14). Back, the toggle and
/// Esc leave it.
class _FullScreenMap extends StatelessWidget {
  final _MapSession session;
  final int windowSize;
  final ValueChanged<MapNode> onOpen;

  const _FullScreenMap({
    required this.session,
    required this.windowSize,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ColoredBox(
      color: t.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          // A route of its own has no Material above it; the search field
          // needs one.
          child: Material(
            type: MaterialType.transparency,
            child: _MapBody(
              session: session,
              fullscreen: true,
              windowSize: windowSize,
              onOpen: onOpen,
              onToggleFullScreen: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}

bool _compact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;

Duration _motion(BuildContext context, Duration d) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

class _MapBody extends StatefulWidget {
  final _MapSession session;
  final bool fullscreen;
  final int windowSize;
  final ValueChanged<MapNode> onOpen;
  final VoidCallback onToggleFullScreen;

  const _MapBody({
    required this.session,
    required this.fullscreen,
    required this.windowSize,
    required this.onOpen,
    required this.onToggleFullScreen,
  });

  @override
  State<_MapBody> createState() => _MapBodyState();
}

class _MapBodyState extends State<_MapBody> {
  // Esc is the WINDOW's on web (a keydown listener), so it works whatever has
  // focus — after Enter the search field has let go of it. The same here: a
  // keyboard handler, answering only on the route that is on top.
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    return _escape();
  }

  // Esc: full screen first, then the search, then the selection.
  bool _escape() {
    final s = widget.session;
    if (widget.fullscreen) {
      widget.onToggleFullScreen();
    } else if (s.query.text.isNotEmpty) {
      s.query.clear();
    } else if (s.selected != null) {
      s.clearSelection();
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Toolbar(session: session, windowSize: widget.windowSize),
          _Inspector(session: session, onOpen: widget.onOpen),
          Expanded(
            child: _Canvas(
              session: session,
              fullscreen: widget.fullscreen,
              onToggleFullScreen: widget.onToggleFullScreen,
            ),
          ),
        ],
      ),
    );
  }
}

// ----- Marks ---------------------------------------------------------------

Color _nodeColor(Tokens t, MapNode n) => n.isShelf
    ? (AppColors.shelfColor(n.color, dark: t.isDark) ??
          t.fgSubtle) // pair-ok: a shelf's stored colour is a fixed data token
    : t.fgMuted;

/// A shelf's §6.2 dot (with its hairline), or a volume's §6.4 plate.
class _NodeMark extends StatelessWidget {
  final MapNode node;
  final KitBadgeSize badge;
  final double dot;

  const _NodeMark(this.node, {this.badge = KitBadgeSize.mapChip, this.dot = 9});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (node.isShelf) {
      return Container(
        width: dot,
        height: dot,
        decoration: BoxDecoration(
          color: _nodeColor(t, node),
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: t.border, spreadRadius: 1)],
        ),
      );
    }
    return KitFileBadge(kitDocKind(node.type ?? ''), size: badge);
  }
}

TextStyle _caps(Tokens t, {double spacing = 0.08}) => TextStyle(
  fontFamily: AppTheme.fontSans,
  fontSize: 10,
  fontWeight: FontWeight.w700,
  letterSpacing: 10 * spacing,
  color: t.fgSubtle,
);

// ----- Toolbar -------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  final _MapSession session;
  final int windowSize;

  const _Toolbar({required this.session, required this.windowSize});

  @override
  Widget build(BuildContext context) {
    final legend = _Legend(
      counts: session.graph.counts,
      windowFull: session.graph.windowFull,
      windowSize: windowSize,
    );
    final search = _SearchField(session: session);
    // Phone: the search first at full width, the legend under it, wrapping.
    if (_compact(context)) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [search, const SizedBox(height: 10), legend],
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Row(
        children: [
          Expanded(child: legend),
          const SizedBox(width: 16),
          SizedBox(width: 240, child: search),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final MapCounts counts;
  final bool windowFull;
  final int windowSize;

  const _Legend({
    required this.counts,
    required this.windowFull,
    required this.windowSize,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final label = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 12.5,
      fontWeight: FontWeight.w700,
      color: t.fgMuted,
    );
    final count = AppTheme.mono(
      fontSize: 12.5,
      fontWeight: FontWeight.w600,
      color: t.fg,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    Widget entry(int n, String one, String many, {Widget? lead}) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (lead != null) ...[lead, const SizedBox(width: 6)],
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: '$n', style: count),
              TextSpan(text: ' ${n == 1 ? one : many}', style: label),
            ],
          ),
        ),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        entry(counts.shelves, 'shelf', 'shelves'),
        entry(counts.volumes, 'volume', 'volumes'),
        Tooltip(
          message: 'Each link points from a volume to its shelf',
          child: entry(
            counts.links,
            'link',
            'links',
            lead: CustomPaint(
              size: const Size(15, 9),
              painter: _LegendArrow(t.fgSubtle),
            ),
          ),
        ),
        if (counts.unshelved > 0)
          entry(counts.unshelved, 'unshelved', 'unshelved'),
        if (windowFull)
          Text(
            'of your most recent $windowSize',
            style: AppTheme.serif(
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: t.fgMuted,
            ),
          ),
      ],
    );
  }
}

/// The links entry's arrow, pointing the way the wires read (`.rm-leg-arrow`).
class _LegendArrow extends CustomPainter {
  final Color color;

  const _LegendArrow(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      const Offset(1, 4.5),
      const Offset(11, 4.5),
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(15, 4.5)
        ..lineTo(8, 1)
        ..lineTo(8, 8)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_LegendArrow old) => old.color != color;
}

/// An underline field: a leading search glyph at `--fg-subtle`, the
/// placeholder in italic serif, a clear control while it holds text.
class _SearchField extends StatelessWidget {
  final _MapSession session;

  const _SearchField({required this.session});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final text = AppTheme.serif(fontSize: 14, color: t.fg);
    return SizedBox(
      height: 34,
      child: Stack(
        children: [
          TextField(
            controller: session.query,
            style: text,
            cursorColor: t.accent,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => session.enter(),
            decoration: InputDecoration(
              isDense: true,
              // An underline field: the app theme's filled input is not this.
              filled: false,
              hintText: 'Find a shelf or volume…',
              hintStyle: text.copyWith(
                fontStyle: FontStyle.italic,
                color: t.fgSubtle,
              ),
              contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 8),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.border, width: 1.5),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: t.accent, width: 1.5),
              ),
              border: InputBorder.none,
            ),
          ),
          Positioned(
            left: 0,
            top: 10,
            child: IgnorePointer(
              child: Icon(Icons.search, size: 14, color: t.fgSubtle),
            ),
          ),
          if (session.query.text.isNotEmpty)
            Positioned(
              right: 0,
              top: 6,
              child: Semantics(
                button: true,
                label: 'Clear the search',
                child: GestureDetector(
                  onTap: session.query.clear,
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.close, size: 14, color: t.fgSubtle),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ----- Inspector -----------------------------------------------------------

class _Inspector extends StatelessWidget {
  final _MapSession session;
  final ValueChanged<MapNode> onOpen;

  const _Inspector({required this.session, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = _compact(context);
    final rel = relationsOf(session.graph, session.selected);
    final box = BoxDecoration(
      color: t.surface,
      border: Border.all(color: t.border),
      borderRadius: AppRadius.mdR,
    );
    if (rel == null) {
      return Container(
        margin: const EdgeInsets.only(top: 2, bottom: 12),
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 16),
        constraints: BoxConstraints(minHeight: compact ? 54 : 72),
        decoration: box,
        child: Row(
          children: [
            Text('INSPECTOR', style: _caps(t)),
            // Phone: the nothing-selected sentence is dropped.
            if (!compact) ...[
              const SizedBox(width: 13),
              Flexible(
                child: Text(
                  'Select a shelf or a volume to trace what it holds.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: t.fgMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    final node = rel.node;
    final ident = Row(
      mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
      children: [
        _NodeMark(node, badge: KitBadgeSize.mapIdentity, dot: 14),
        const SizedBox(width: 11),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(node.isShelf ? 'SHELF' : 'VOLUME', style: _caps(t)),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: compact ? double.infinity : 320,
                ),
                child: Text(
                  node.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                    opsz: 18,
                    color: t.fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final sections = KitScrollView.secondary(
      reason:
          'the relation chips: a shelf can hold two hundred volumes '
          '(kit §1.4) — they scroll sideways rather than wrap',
      axis: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: IntrinsicHeight(
          child: Row(
            children: [
              for (var i = 0; i < rel.sections.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(width: 13),
                  Container(width: 1, color: t.rule),
                  const SizedBox(width: 13),
                ],
                _section(t, rel.sections[i]),
              ],
            ],
          ),
        ),
      ),
    );
    final acts = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KitButton.secondary(
          node.isShelf ? 'Open shelf' : 'Open in reader',
          onPressed: () => onOpen(node),
        ),
        const SizedBox(width: 8),
        _SmallIconButton(
          Icons.close,
          tooltip: 'Clear selection',
          onTap: session.clearSelection,
        ),
      ],
    );

    if (compact) {
      // Identity and action on the first line, the relations on a second
      // line of their own that scrolls sideways.
      return Container(
        margin: const EdgeInsets.only(top: 2, bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
        decoration: box,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: ident),
                const SizedBox(width: 10),
                acts,
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: t.rule),
            sections,
          ],
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      constraints: const BoxConstraints(minHeight: 72),
      decoration: box,
      child: IntrinsicHeight(
        child: Row(
          children: [
            ident,
            const SizedBox(width: 13),
            Container(width: 1, color: t.rule),
            const SizedBox(width: 13),
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: sections),
            ),
            const SizedBox(width: 13),
            acts,
          ],
        ),
      ),
    );
  }

  Widget _section(Tokens t, MapSection s) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('${s.label.toUpperCase()} · ${s.nodes.length}', style: _caps(t)),
      const SizedBox(width: 8),
      if (s.nodes.isEmpty)
        Text(
          'none',
          style: AppTheme.serif(
            fontSize: 13,
            fontStyle: FontStyle.italic,
            color: t.fgMuted,
          ),
        )
      else
        for (var i = 0; i < s.nodes.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          _RelationChip(
            s.nodes[i],
            onTap: () => session.selectAndCentre(s.nodes[i].key),
          ),
        ],
    ],
  );
}

class _RelationChip extends StatefulWidget {
  final MapNode node;
  final VoidCallback onTap;

  const _RelationChip(this.node, {required this.onTap});

  @override
  State<_RelationChip> createState() => _RelationChipState();
}

class _RelationChipState extends State<_RelationChip> {
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
        child: Container(
          padding: const EdgeInsets.fromLTRB(7, 5, 11, 5),
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            border: Border.all(color: _hover ? t.borderStrong : t.border),
            borderRadius: AppRadius.pillR(64),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _NodeMark(widget.node, badge: KitBadgeSize.mapRelation),
              const SizedBox(width: 7),
              Text(
                widget.node.label,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: t.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.rm-iconbtn` — 32×32, `--r-sm`, `--hover` behind it on hover.
class _SmallIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;

  const _SmallIconButton(
    this.icon, {
    required this.tooltip,
    required this.onTap,
  }) : size = 15;

  const _SmallIconButton.zoom(
    this.icon, {
    required this.tooltip,
    required this.onTap,
  }) : size = 16;

  @override
  State<_SmallIconButton> createState() => _SmallIconButtonState();
}

class _SmallIconButtonState extends State<_SmallIconButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover ? t.hover : const Color(0x00000000),
                borderRadius: AppRadius.smR,
              ),
              child: Icon(
                widget.icon,
                size: widget.size,
                color: _hover ? t.fg : t.fgMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ----- Canvas --------------------------------------------------------------

class _Canvas extends StatefulWidget {
  final _MapSession session;
  final bool fullscreen;
  final VoidCallback onToggleFullScreen;

  const _Canvas({
    required this.session,
    required this.fullscreen,
    required this.onToggleFullScreen,
  });

  @override
  State<_Canvas> createState() => _CanvasState();
}

class _CanvasState extends State<_Canvas> {
  final TransformationController _tc = TransformationController();
  MapLayout? _layout;
  MapGraph? _layoutGraph;
  Size _layoutBox = Size.zero;
  Size _box = Size.zero;
  String _fitKey = '';

  // The gesture under way moved past the slop: its tap is a pan, never a
  // selection (web `moved`).
  Offset? _down;
  bool _moved = false;
  final Set<int> _pointers = {};

  _MapSession get _s => widget.session;

  @override
  void initState() {
    super.initState();
    _s._canvases.add(this);
  }

  @override
  void dispose() {
    _s._canvases.remove(this);
    _tc.dispose();
    super.dispose();
  }

  double get _z => _tc.value.getMaxScaleOnAxis();

  void _setView(double z, double x, double y) {
    // All three axes, as InteractiveViewer's own matrices are: its scale (and
    // the zoom label) is `getMaxScaleOnAxis`, which an unscaled z reads as 1
    // whenever the view is below 100%.
    _tc.value = Matrix4.diagonal3Values(z, z, z)..setTranslationRaw(x, y, 0);
  }

  double _fitZoom() {
    final l = _layout!;
    // The layout pads its own edges, so a graph no bigger than the box opens
    // at 100% rather than a margin's worth under it.
    return _clampZ(
      math.min(
        1,
        math.min(_box.width / l.width, (_box.height - _ctrlClear) / l.height),
      ),
    );
  }

  void fit() {
    final l = _layout;
    if (l == null) return;
    final z = _fitZoom();
    final band = _box.height - _ctrlClear;
    _setView(
      z,
      (_box.width - l.width * z) / 2,
      _ctrlClear + (band - l.height * z) / 2,
    );
  }

  void _centreOn(String key, double z) {
    final p = _layout?.pos[key];
    if (p == null) return;
    _setView(z, _box.width / 2 - p.dx * z, _box.height / 2 - p.dy * z);
  }

  void centreOnKeepingZoom(String key) =>
      _centreOn(key, math.max(_z, math.min(1, _focusZoom)));

  void _zoomAt(double nz, Offset at) {
    final z0 = _z;
    final z = _clampZ(nz);
    final t = _tc.value.getTranslation();
    _setView(
      z,
      at.dx - ((at.dx - t.x) / z0) * z,
      at.dy - ((at.dy - t.y) / z0) * z,
    );
  }

  void _zoomBy(double factor) =>
      _zoomAt(_z * factor, Offset(_box.width / 2, _box.height / 2));

  // Opens fitted, and re-fits when the graph's natural size (or the box)
  // changes — never when only the zoom did, so it never fights the reader.
  void _applyFit() {
    if (!mounted || _layout == null) return;
    final f = _s.pendingFocus;
    if (f != null && _layout!.pos.containsKey(f)) {
      _s.pendingFocus = null;
      _centreOn(f, math.max(_fitZoom(), math.min(1, _focusZoom)));
    } else {
      fit();
    }
  }

  // A plain wheel or two-finger trackpad scroll PANS; ⌘/Ctrl + wheel zooms
  // toward the pointer. InteractiveViewer zooms on a plain wheel, so the
  // signal is claimed here first.
  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (ev) {
      final s = ev as PointerScrollEvent;
      final kb = HardwareKeyboard.instance;
      if (kb.isControlPressed || kb.isMetaPressed) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final factor = math.max(
          1 / 1.2,
          math.min(1.2, math.exp(-s.scrollDelta.dy * 0.01)),
        );
        _zoomAt(_z * factor, box.globalToLocal(s.position));
      } else {
        final t = _tc.value.getTranslation();
        _setView(_z, t.x - s.scrollDelta.dx, t.y - s.scrollDelta.dy);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = _compact(context);
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              color: t.surfaceSunken,
              border: Border.all(color: t.border),
              borderRadius: AppRadius.lgR,
            ),
            child: ClipRRect(
              borderRadius: AppRadius.lgR,
              child: LayoutBuilder(
                builder: (context, c) {
                  _box = Size(c.maxWidth, c.maxHeight);
                  final w = math.max(280.0, c.maxWidth);
                  final h = math.max(220.0, c.maxHeight);
                  if (_layout == null ||
                      !identical(_layoutGraph, _s.graph) ||
                      _layoutBox != Size(w, h)) {
                    _layout = layoutGraph(_s.graph, w, h);
                    _layoutGraph = _s.graph;
                    _layoutBox = Size(w, h);
                  }
                  final l = _layout!;
                  final key =
                      '${l.width}x${l.height}@${c.maxWidth}x${c.maxHeight}';
                  if (key != _fitKey) {
                    _fitKey = key;
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) => _applyFit(),
                    );
                  }
                  // Inside the page's scroll view a vertical drag would go to
                  // the page, whose drag wins at the touch slop before the
                  // viewer's pan does at twice it (web: `touch-action: none`).
                  // Here the slop is web's 4px drag rule: the viewer pans past
                  // 8 and wins, and a tap that moved past 4 is no tap.
                  return MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      gestureSettings: const DeviceGestureSettings(
                        touchSlop: _dragSlop,
                      ),
                    ),
                    child: Listener(
                      onPointerDown: (e) {
                        _pointers.add(e.pointer);
                        if (_pointers.length == 1) {
                          _down = e.position;
                          _moved = false;
                        } else {
                          _moved = true; // a pinch is never a tap
                        }
                      },
                      onPointerMove: (e) {
                        final d = _down;
                        if (d != null &&
                            (e.position - d).distance > _dragSlop) {
                          _moved = true;
                        }
                      },
                      onPointerUp: (e) => _pointers.remove(e.pointer),
                      onPointerCancel: (e) => _pointers.remove(e.pointer),
                      onPointerSignal: _onSignal,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        // Activating the empty canvas clears the selection.
                        onTap: () {
                          if (!_moved) _s.clearSelection();
                        },
                        child: InteractiveViewer(
                          key: const Key('relmap-viewer'),
                          transformationController: _tc,
                          // The canvas is bigger than the box by design — the
                          // layout grows it rather than packing — so the child is
                          // not clamped to the viewport, and nothing bounds a pan.
                          constrained: false,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          minScale: _zMin,
                          maxScale: _zMax,
                          child: _Graph(
                            session: _s,
                            layout: l,
                            moved: () => _moved,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // The view controls: pinned to the canvas frame, never panned with it.
        Positioned(
          top: 14,
          left: 14,
          child: Row(
            children: [
              _FullScreenToggle(
                on: widget.fullscreen,
                size: compact ? 44 : 40,
                onTap: widget.onToggleFullScreen,
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: t.surface,
                  border: Border.all(color: t.border),
                  borderRadius: AppRadius.mdR,
                  boxShadow: AppShadows.s1,
                ),
                child: Row(
                  children: [
                    _SmallIconButton.zoom(
                      Icons.remove,
                      tooltip: 'Zoom out',
                      onTap: () => _zoomBy(1 / 1.2),
                    ),
                    const SizedBox(width: 2),
                    _ZoomPercent(controller: _tc, onTap: fit),
                    const SizedBox(width: 2),
                    _SmallIconButton.zoom(
                      Icons.add,
                      tooltip: 'Zoom in',
                      onTap: () => _zoomBy(1.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FullScreenToggle extends StatelessWidget {
  final bool on;
  final double size;
  final VoidCallback onTap;

  const _FullScreenToggle({
    required this.on,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final label = on ? 'Leave full screen' : 'Full screen';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          key: const Key('relmap-fullscreen'),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.border),
              borderRadius: AppRadius.mdR,
              boxShadow: AppShadows.s1,
            ),
            child: Icon(
              on ? Icons.close_fullscreen : Icons.open_in_full,
              size: 17,
              color: t.fgMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// The zoom as `{n}%`; activating it re-fits.
class _ZoomPercent extends StatelessWidget {
  final TransformationController controller;
  final VoidCallback onTap;

  const _ZoomPercent({required this.controller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tooltip(
      message: 'Fit the map',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 50),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Text(
              '${(controller.value.getMaxScaleOnAxis() * 100).round()}%',
              style: AppTheme.mono(
                fontSize: 11.5,
                color: t.fgMuted,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sized canvas the viewer pans: column headers, the wire layer beneath,
/// the chips above it.
class _Graph extends StatelessWidget {
  final _MapSession session;
  final MapLayout layout;
  final bool Function() moved;

  const _Graph({
    required this.session,
    required this.layout,
    required this.moved,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final g = session.graph;
    final selected = session.selected;
    final matches = searchMatches(g, session.query.text);
    final path = connectedPath(g, selected);
    final anyFocus = selected != null || session.anyQuery;
    final lit = selected != null ? path.nodes : matches;
    // Hovered and selected chips draw last, over their neighbours (z-index 5
    // and 6); the rest keep the graph's order.
    final drawn = g.nodes.values.where((n) => layout.pos.containsKey(n.key));
    final order = [
      for (final n in drawn)
        if (n.key != selected && n.key != session.hover) n,
      for (final n in drawn)
        if (n.key == session.hover && n.key != selected) n,
      for (final n in drawn)
        if (n.key == selected) n,
    ];
    return SizedBox(
      width: layout.width,
      height: layout.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: _Wires(
              graph: g,
              layout: layout,
              pathEdges: selected != null ? path.edges : const <int>{},
              anyFocus: anyFocus,
            ),
          ),
          for (final h in layout.headers)
            Positioned(
              left: h.x,
              top: 6,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: Text(
                  h.label.toUpperCase(),
                  style: _caps(t, spacing: 0.18),
                ),
              ),
            ),
          for (final n in order)
            Positioned(
              left: layout.pos[n.key]!.dx,
              top: layout.pos[n.key]!.dy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -0.5),
                child: _Chip(
                  node: n,
                  selected: selected == n.key,
                  off: selected != n.key && anyFocus && !lit.contains(n.key),
                  match: selected == null && matches.contains(n.key),
                  hovered: session.hover == n.key && selected != n.key,
                  onTap: () {
                    if (!moved()) session.toggle(n.key);
                  },
                  onHover: session.setHover,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// `saturate(0.5)`, CSS's own matrix (Filter Effects §feColorMatrix).
List<double> _saturate(double s) => [
  0.213 + 0.787 * s,
  0.715 - 0.715 * s,
  0.072 - 0.072 * s,
  0,
  0,
  0.213 - 0.213 * s,
  0.715 + 0.285 * s,
  0.072 - 0.072 * s,
  0,
  0,
  0.213 - 0.213 * s,
  0.715 - 0.715 * s,
  0.072 + 0.928 * s,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

class _Chip extends StatelessWidget {
  final MapNode node;
  final bool selected;
  final bool off;
  final bool match;
  final bool hovered;
  final VoidCallback onTap;
  final ValueChanged<String?> onHover;

  const _Chip({
    required this.node,
    required this.selected,
    required this.off,
    required this.match,
    required this.hovered,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final colour = _nodeColor(t, node);
    final volume = !node.isShelf;
    // Every rule with no line-height takes the page's 24px (`--lh-base`).
    final label = volume
        ? TextStyle(
            fontFamily: AppTheme.fontSans,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            height: 24 / 12.5,
            color: t.fg,
          )
        : AppTheme.serif(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 24 / 14,
            opsz: 14,
            color: t.fg,
          );
    final Color fill;
    final Color edge;
    if (selected) {
      fill = Color.alphaBlend(colour.withValues(alpha: 0.14), t.surface);
      edge = colour;
    } else if (match) {
      fill = t.highlight;
      edge = t.borderStrong;
    } else {
      fill = t.surface;
      edge = t.border;
    }
    final slow = _motion(context, const Duration(milliseconds: 350));
    final base = _motion(context, AppMotion.durBase);
    final pill = AnimatedContainer(
      duration: base,
      curve: AppMotion.easeOut,
      padding: volume
          ? const EdgeInsets.fromLTRB(5, 4, 12, 4)
          : const EdgeInsets.fromLTRB(9, 5, 12, 5),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: edge, width: 1.5),
        borderRadius: AppRadius.pillR(64),
        boxShadow: selected
            ? [
                ...AppShadows.s2,
                BoxShadow(
                  color: colour.withValues(alpha: 0.12),
                  spreadRadius: 4,
                ),
              ]
            : hovered
            ? AppShadows.s2
            : AppShadows.s1,
      ),
      child: ConstrainedBox(
        // A volume's title is one line, truncated at a fixed maximum so a
        // column keeps its rhythm; a shelf's is never truncated — few shelves,
        // and their names are the map's landmarks.
        constraints: BoxConstraints(
          maxWidth: volume ? 240 - 17 - 3 : double.infinity,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NodeMark(node),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                node.label,
                maxLines: 1,
                softWrap: false,
                overflow: volume ? TextOverflow.ellipsis : TextOverflow.visible,
                style: label,
              ),
            ),
            if (!volume) ...[
              const SizedBox(width: 8),
              Text(
                '${node.count}',
                style: AppTheme.mono(
                  fontSize: 11,
                  color: t.fgSubtle,
                ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: node.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => onHover(node.key),
        onExit: (_) => onHover(null),
        child: GestureDetector(
          key: Key('relmap-node-${node.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedScale(
            scale: selected ? 1.06 : 1,
            duration: base,
            curve: AppMotion.easeOut,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: off ? 1 : 0),
              duration: slow,
              curve: AppMotion.easeOut,
              builder: (context, v, child) => Opacity(
                opacity: 1 - 0.74 * v,
                child: ColorFiltered(
                  colorFilter: ColorFilter.matrix(_saturate(1 - 0.5 * v)),
                  child: child,
                ),
              ),
              child: pill,
            ),
          ),
        ),
      ),
    );
  }
}

// ----- Wires ---------------------------------------------------------------

class _WireStyle {
  final Color color;
  final double line;
  final double head;
  final double width;
  final double len;
  final double wide;

  const _WireStyle(
    this.color,
    this.line,
    this.head,
    this.width,
    this.len,
    this.wide,
  );

  static _WireStyle lerp(_WireStyle a, _WireStyle b, double t) => _WireStyle(
    Color.lerp(a.color, b.color, t)!,
    a.line + (b.line - a.line) * t,
    a.head + (b.head - a.head) * t,
    a.width + (b.width - a.width) * t,
    a.len + (b.len - a.len) * t,
    a.wide + (b.wide - a.wide) * t,
  );

  @override
  bool operator ==(Object o) =>
      o is _WireStyle &&
      o.color == color &&
      o.line == line &&
      o.head == head &&
      o.width == width &&
      o.len == len &&
      o.wide == wide;

  @override
  int get hashCode => Object.hash(color, line, head, width, len, wide);
}

/// The wire layer. A wire is its PARENT shelf's (ADR-177 §4): idle at 22%
/// (head 50%), 1.5px; on the selected path at full strength, 2.5px, a larger
/// head; off the path while anything is selected or searched, `--fg-subtle`
/// at 10% (head 14%). Changes ease over 350ms, as web's transitions do.
class _Wires extends StatefulWidget {
  final MapGraph graph;
  final MapLayout layout;
  final Set<int> pathEdges;
  final bool anyFocus;

  const _Wires({
    required this.graph,
    required this.layout,
    required this.pathEdges,
    required this.anyFocus,
  });

  @override
  State<_Wires> createState() => _WiresState();
}

class _WiresState extends State<_Wires> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  )..value = 1;
  List<_WireStyle> _from = const [];
  List<_WireStyle> _to = const [];

  List<_WireStyle> _styles(Tokens t) => [
    for (var i = 0; i < widget.graph.edges.length; i++) _style(t, i),
  ];

  _WireStyle _style(Tokens t, int i) {
    final e = widget.graph.edges[i];
    final on = widget.pathEdges.contains(i);
    final parent = widget.graph.nodes[e.parent];
    final colour = (on || !widget.anyFocus) && parent != null
        ? _nodeColor(t, parent)
        : t.fgSubtle;
    if (on) return _WireStyle(colour, 0.95, 0.95, 2.5, 11.5, 8.5);
    if (widget.anyFocus) return _WireStyle(colour, 0.10, 0.14, 1.5, 10, 7);
    return _WireStyle(colour, 0.22, 0.5, 1.5, 10, 7);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _retarget();
  }

  @override
  void didUpdateWidget(_Wires old) {
    super.didUpdateWidget(old);
    _retarget();
  }

  void _retarget() {
    final next = _styles(Tokens.of(context));
    if (_listEq(next, _to)) return;
    final now = _current();
    final animate =
        !MediaQuery.disableAnimationsOf(context) && now.length == next.length;
    _from = animate ? now : next;
    _to = next;
    if (animate) {
      _c.forward(from: 0);
    } else {
      _c.value = 1;
    }
  }

  List<_WireStyle> _current() {
    if (_from.length != _to.length) return _to;
    final v = AppMotion.easeOut.transform(_c.value);
    return [
      for (var i = 0; i < _to.length; i++) _WireStyle.lerp(_from[i], _to[i], v),
    ];
  }

  static bool _listEq(List<_WireStyle> a, List<_WireStyle> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(
        painter: _WirePainter(
          graph: widget.graph,
          layout: widget.layout,
          styles: _current(),
          tick: _c.value,
        ),
      ),
    ),
  );
}

class _WirePainter extends CustomPainter {
  final MapGraph graph;
  final MapLayout layout;
  final List<_WireStyle> styles;
  final double tick;

  const _WirePainter({
    required this.graph,
    required this.layout,
    required this.styles,
    required this.tick,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < graph.edges.length && i < styles.length; i++) {
      final e = graph.edges[i];
      final a = layout.pos[e.child];
      final b = layout.pos[e.parent];
      if (a == null || b == null) continue;
      final s = styles[i];
      final w = wireGeometry(a, b);
      canvas.drawPath(
        Path()
          ..moveTo(w.a.dx, w.a.dy)
          ..cubicTo(w.c1.dx, w.c1.dy, w.c2.dx, w.c2.dy, w.b.dx, w.b.dy),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width
          ..strokeCap = StrokeCap.round
          ..color = s.color.withValues(alpha: s.line),
      );
      final h = arrowHead(w.mid, w.tan, s.len, s.wide);
      canvas.drawPath(
        Path()
          ..moveTo(h[0].dx, h[0].dy)
          ..lineTo(h[1].dx, h[1].dy)
          ..lineTo(h[2].dx, h[2].dy)
          ..close(),
        Paint()..color = s.color.withValues(alpha: s.head),
      );
    }
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.tick != tick ||
      !identical(old.graph, graph) ||
      old.layout != layout ||
      !identical(old.styles, styles);
}
