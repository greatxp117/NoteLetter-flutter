import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_cards.dart' show kitFigure;
import 'kit_ground.dart';
import 'kit_text.dart';
import 'kit_provider_logo.dart';

/// §1.1 — the app shell: a **chrome rail** and an inset **main pane**.
///
/// The inset is the whole device: the pane reads as a sheet lying on the plum
/// desk. A main pane flush to the edges is a different app — which is what this
/// client shipped, because `AppLayout` was a bare `Row(Sidebar, Expanded)` with
/// no chrome behind it, no inset, no corner and no ground.
class KitShell extends StatelessWidget {
  final Widget rail;
  final Widget child;

  const KitShell({super.key, required this.rail, required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ColoredBox(
      color: t.chrome,
      child: Row(
        children: [
          SizedBox(width: AppSpacing.railWidth, child: rail),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, AppSpacing.shellInset,
                  AppSpacing.shellInset, AppSpacing.shellInset),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg)),
                  boxShadow: AppShadows.s1,
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg)),
                  child: KitGround(child: child),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The compact (phone) form of the shell: the rail becomes a drawer and the
/// pane goes full-bleed, but **the ground and the chrome surface stay**.
///
/// The pane paints `--surface` under the ground exactly as the wide one does.
/// [KitGround] draws only the texture — it is transparent by design, since it
/// also overlays surfaces that bring their own colour — so a compact pane that
/// omitted the fill let the Scaffold's chrome plum through the whole body:
/// every screen rendered its page text, at correct `--fg`, on the desk colour.
class KitShellCompact extends StatelessWidget {
  final Widget child;

  const KitShellCompact({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Tokens.of(context).surface,
        child: KitGround(child: child),
      );
}

/// §1.2 — the chrome rail's scaffolding: brand lockup, scrollable nav region,
/// pinned bottom.
///
/// **Foregrounds on chrome are white at token alphas, not `--fg`.** The chrome
/// surface is plum in both themes, so a foreground taken from the page tokens
/// flips to near-black in light mode and disappears.
class KitChromeRail extends StatelessWidget {
  final Widget brand;
  final List<Widget> items;
  final Widget? footer;

  const KitChromeRail(
      {super.key, required this.brand, required this.items, this.footer});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ColoredBox(
      color: t.chrome,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 14),
              child: brand,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: AppSpacing.s1),
                      items[i],
                    ],
                  ],
                ),
              ),
            ),
            if (footer != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border:
                      Border(top: BorderSide(color: t.chromeBorder)),
                ),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The brand lockup (§1.2): the **quill** mark + the small-caps serif
/// **wordmark**, in chrome foreground.
///
/// The pattern owns both parts. It used to take its mark from the caller, and
/// every caller passed Material's `edit_note` beside a plain serif
/// `NoteLetter` — a lockup the reference never draws (F-57). Web: `.sb-brand`
/// (mark 22, gap 10), `.mh-brand` (mark 20, gap 8), `.ob-brand` (mark 24,
/// gap 11, wordmark 19); `.wordmark` is 15px everywhere else.
class KitBrand extends StatelessWidget {
  final double markSize;
  final double gap;
  final double wordmarkSize;

  /// The rail's lockup (`.sb-brand`).
  const KitBrand({super.key})
      : markSize = 22,
        gap = 10,
        wordmarkSize = 15;

  /// The phone app bar's lockup (`.mh-brand`).
  const KitBrand.appBar({super.key})
      : markSize = 20,
        gap = 8,
        wordmarkSize = 15;

  /// The onboarding rail's lockup (`.ob-brand`).
  const KitBrand.onboarding({super.key})
      : markSize = 24,
        gap = 11,
        wordmarkSize = 19;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KitQuill(size: markSize, color: t.chromeFg),
        SizedBox(width: gap),
        KitWordmark(fontSize: wordmarkSize, color: t.chromeFg),
      ],
    );
  }
}

/// `.wordmark` — NOTELETTER in serif 600 caps, tracked 0.12em, its two
/// initials raised to 1.24em (`.wm-init`). The tracking is the base size's:
/// CSS computes `0.12em` on the wordmark and the initials inherit the pixels.
class KitWordmark extends StatelessWidget {
  final double fontSize;
  final Color color;

  /// The tracking, in ems of [fontSize], and the optical size. The app's
  /// `.wordmark` is 0.12em at opsz 28; the signed-out pages' harmonised lockup
  /// (`signin.css` / `landing-actual.css` `.brand .name`) is 0.11em at opsz 24.
  final double tracking;
  final double opsz;

  const KitWordmark({
    super.key,
    this.fontSize = 15,
    required this.color,
    this.tracking = 0.12,
    this.opsz = 28,
  });

  @override
  Widget build(BuildContext context) {
    TextStyle style(double size) => AppTheme.serif(
          fontSize: size,
          fontWeight: FontWeight.w600,
          letterSpacing: tracking * fontSize,
          height: 1,
          color: color,
        ).copyWith(fontVariations: [
          const FontVariation('wght', 600),
          FontVariation('opsz', opsz),
        ]);
    final base = style(fontSize);
    final init = style(fontSize * 1.24);
    return Text.rich(
      TextSpan(style: base, children: [
        TextSpan(text: 'N', style: init),
        const TextSpan(text: 'OTE'),
        TextSpan(text: 'L', style: init),
        const TextSpan(text: 'ETTER'),
      ]),
      semanticsLabel: 'NoteLetter',
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// The quill — the reference's `IcoFeather` (a 512-unit filled path), the
/// app's mark wherever web draws one. Material has no such glyph; the nearest
/// (`edit_note`) is a notepad, which is what this client drew for months.
class KitQuill extends StatelessWidget {
  final double size;
  final Color color;

  const KitQuill({super.key, required this.size, required this.color});

  /// A sentinel for kit widgets that take an [IconData] (§7's [KitMark], the
  /// settings feature card): pass this and [KitGlyph] draws the quill.
  static const IconData icon = IconData(0xF8FF, fontFamily: 'NoteLetterQuill');

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QuillPainter(color)),
    );
  }
}

class _QuillPainter extends CustomPainter {
  final Color color;

  const _QuillPainter(this.color);

  static final Path _path = Path()
    ..moveTo(483.4, 244.2)
    ..lineTo(351.9, 287.1)
    ..lineTo(449.64, 287.1)
    ..cubicTo(439.766, 297.72, 453.39, 283.975, 403.4, 333.97)
    ..lineTo(255.8, 383.09)
    ..lineTo(354.04, 383.09)
    ..cubicTo(279.05, 456.21, 159.44, 453.71, 107.24, 437.19)
    ..lineTo(41.1, 503.18)
    ..cubicTo(31.726, 512.554, 16.5, 512.554, 7.12, 503.18)
    ..cubicTo(-2.26, 493.806, -2.254, 478.58, 7.12, 469.2)
    ..lineTo(266.62, 210)
    ..cubicTo(272.869, 203.75, 272.869, 193.63, 266.62, 187.38)
    ..cubicTo(260.371, 181.131, 250.25, 181.131, 244, 187.38)
    ..lineTo(65.6, 365.58)
    ..cubicTo(58.78, 306.1, 68.61, 216.7, 129.1, 156.3)
    ..lineTo(214.84, 70.62)
    ..cubicTo(305.46, -20, 404.64, -17.65, 467.14, 44.84)
    ..cubicTo(517.8, 95.34, 528.9, 169.7, 483.4, 244.2)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 512, size.height / 512);
    canvas.drawPath(_path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_QuillPainter old) => old.color != color;
}

/// The reference's `IcoSparkle` — eight short strokes radiating from an
/// empty centre (icons.jsx), at its 1.75 stroke on a 24 grid. Material has no
/// such glyph: its `auto_awesome` is a FILLED twinkle, which is the prompt
/// glyph Ask drew in this client's frames and in no one else's (F-78 (2)).
class KitSparkle extends StatelessWidget {
  final double size;
  final Color color;

  const KitSparkle({super.key, required this.size, required this.color});

  /// A sentinel for kit widgets that take an [IconData], as [KitQuill.icon].
  static const IconData icon = IconData(0xF8FE, fontFamily: 'NoteLetterSparkle');

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _SparklePainter(color)),
      );
}

class _SparklePainter extends CustomPainter {
  final Color color;
  const _SparklePainter(this.color);

  /// `M12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1
  /// M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1`.
  static const _strokes = [
    (12.0, 3.0, 12.0, 6.0),
    (12.0, 18.0, 12.0, 21.0),
    (3.0, 12.0, 6.0, 12.0),
    (18.0, 12.0, 21.0, 12.0),
    (5.6, 5.6, 7.7, 7.7),
    (16.3, 16.3, 18.4, 18.4),
    (5.6, 18.4, 7.7, 16.3),
    (16.3, 7.7, 18.4, 5.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round;
    for (final (x1, y1, x2, y2) in _strokes) {
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

/// The reference's `IcoUpload` (Lucide `upload`): an open tray with an arrow
/// rising out of it, stroked at 1.75 on a 24 grid. Material's upload glyphs
/// are a filled arrow over a bar — the drop zone drew one, centred, where the
/// reference draws this (F-79 (1)).
class KitUploadGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const KitUploadGlyph({super.key, required this.size, required this.color});

  /// A sentinel for kit widgets that take an [IconData], as [KitQuill.icon].
  static const IconData icon = IconData(0xF8FD, fontFamily: 'NoteLetterUpload');

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _UploadPainter(color)),
      );
}

class _UploadPainter extends CustomPainter {
  final Color color;
  const _UploadPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4
    canvas.drawPath(
        Path()
          ..moveTo(21, 15)
          ..lineTo(21, 19)
          ..arcToPoint(const Offset(19, 21), radius: const Radius.circular(2))
          ..lineTo(5, 21)
          ..arcToPoint(const Offset(3, 19), radius: const Radius.circular(2))
          ..lineTo(3, 15),
        paint);
    // M17 8l-5-5-5 5M12 3v12
    canvas.drawPath(
        Path()
          ..moveTo(17, 8)
          ..lineTo(12, 3)
          ..lineTo(7, 8)
          ..moveTo(12, 3)
          ..lineTo(12, 15),
        paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_UploadPainter old) => old.color != color;
}

/// The reference's `IcoStack` — three stacked layers (a diamond and two
/// chevrons under it), stroked at 1.75 on a 24 grid: the shelf glyph. Material's
/// `layers` is two (F-81 (6)).
class KitStackGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const KitStackGlyph({super.key, required this.size, required this.color});

  /// A sentinel for kit widgets that take an [IconData], as [KitQuill.icon].
  static const IconData icon = IconData(0xF8FC, fontFamily: 'NoteLetterStack');

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _StackPainter(color)),
      );
}

class _StackPainter extends CustomPainter {
  final Color color;
  const _StackPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // M2 6l10-4 10 4-10 4z  M2 12l10 4 10-4  M2 18l10 4 10-4
    canvas.drawPath(
        Path()
          ..moveTo(2, 6)
          ..lineTo(12, 2)
          ..lineTo(22, 6)
          ..lineTo(12, 10)
          ..close()
          ..moveTo(2, 12)
          ..lineTo(12, 16)
          ..lineTo(22, 12)
          ..moveTo(2, 18)
          ..lineTo(12, 22)
          ..lineTo(22, 18),
        paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StackPainter old) => old.color != color;
}

/// The reference's `IcoCards` — a card with two lines on it and a second
/// card's edge tilted behind: Study's glyph. Material's `style` is three fanned
/// cards, which read as another app's (F-90 (2)).
class KitCardsGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const KitCardsGlyph({super.key, required this.size, required this.color});

  /// A sentinel for kit widgets that take an [IconData], as [KitQuill.icon].
  static const IconData icon = IconData(0xF8FB, fontFamily: 'NoteLetterCards');

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CardsPainter(color)),
      );
}

class _CardsPainter extends CustomPainter {
  final Color color;
  const _CardsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // M8.6 4.7l6.6-1.5a1.6 1.6 0 0 1 1.9 1.2l1 4.4
    canvas.drawPath(
        Path()
          ..moveTo(8.6, 4.7)
          ..lineTo(15.2, 3.2)
          ..arcToPoint(const Offset(17.1, 4.4),
              radius: const Radius.circular(1.6))
          ..lineTo(18.1, 8.8),
        paint);
    // rect x4 y7 w12.5 h14 rx1.8
    canvas.drawRRect(
        RRect.fromRectAndRadius(const Rect.fromLTWH(4, 7, 12.5, 14),
            const Radius.circular(1.8)),
        paint);
    // M7.6 12.5h5.3M7.6 16h3.2
    canvas.drawLine(const Offset(7.6, 12.5), const Offset(12.9, 12.5), paint);
    canvas.drawLine(const Offset(7.6, 16), const Offset(10.8, 16), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardsPainter old) => old.color != color;
}

/// The reference's `IcoMap` — a box over two, joined by a forked line: the
/// shelf map's glyph (*Shelf map*, *See on map*). Material's `map` is a
/// folded paper map, which says geography, not a graph (F-126).
class KitMapGlyph extends StatelessWidget {
  final double size;
  final Color color;

  const KitMapGlyph({super.key, required this.size, required this.color});

  /// A sentinel for kit widgets that take an [IconData], as [KitQuill.icon].
  static const IconData icon = IconData(0xF8F6, fontFamily: 'NoteLetterMap');

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MapPainter(color)),
      );
}

class _MapPainter extends CustomPainter {
  final Color color;
  const _MapPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.75
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // rect x16 y16 w6 h6 rx1 · rect x2 y16 w6 h6 rx1 · rect x9 y2 w6 h6 rx1
    for (final r in const [
      Rect.fromLTWH(16, 16, 6, 6),
      Rect.fromLTWH(2, 16, 6, 6),
      Rect.fromLTWH(9, 2, 6, 6),
    ]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r, const Radius.circular(1)), paint);
    }
    // M5 16v-3a1 1 0 0 1 1-1h12a1 1 0 0 1 1 1v3  M12 12V8
    canvas.drawPath(
        Path()
          ..moveTo(5, 16)
          ..lineTo(5, 13)
          ..arcToPoint(const Offset(6, 12), radius: const Radius.circular(1))
          ..lineTo(18, 12)
          ..arcToPoint(const Offset(19, 13), radius: const Radius.circular(1))
          ..lineTo(19, 16)
          ..moveTo(12, 12)
          ..lineTo(12, 8),
        paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MapPainter old) => old.color != color;
}

/// An [IconData] as a kit widget draws it: [KitQuill.icon] is the quill,
/// [KitSparkle.icon] the reference's sparkle, [KitUploadGlyph.icon] its
/// upload tray, [KitStackGlyph.icon] its shelf stack, [KitCardsGlyph.icon]
/// Study's cards, [KitMapGlyph.icon] the shelf map's, any other a Material
/// [Icon].
class KitGlyph extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;

  const KitGlyph(this.icon, {super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    final Widget? painted = icon == KitQuill.icon
        ? KitQuill(size: size, color: color)
        : icon == KitSparkle.icon
            ? KitSparkle(size: size, color: color)
            : icon == KitUploadGlyph.icon
                ? KitUploadGlyph(size: size, color: color)
                : icon == KitStackGlyph.icon
                    ? KitStackGlyph(size: size, color: color)
                    : icon == KitCardsGlyph.icon
                        ? KitCardsGlyph(size: size, color: color)
                        : icon == KitMapGlyph.icon
                        ? KitMapGlyph(size: size, color: color)
                        : KitProviderLogo.providerOf(icon) != null
                            // A vendor's mark carries its own colours.
                            ? KitProviderLogo(
                                provider: KitProviderLogo.providerOf(icon)!,
                                size: size)
                            : null;
    if (painted == null) return Icon(icon, size: size, color: color);
    // Laid out as [Icon] lays out: its own box at [size], the glyph centred
    // in whatever a parent forces it to fill. A bare painted box took a
    // tile's tight 36 and drew the sheet's 18 mark at 36, over its own tile
    // (the 2026-10-12 shelf-create-sheet frame).
    return SizedBox(
        width: size, height: size, child: Center(child: painted));
  }
}

/// The phone app bar's trailing control (`.mh-btn`): 36 square, `--r-sm`, the
/// glyph 20 at white .80, hover fill white .08 with the glyph at `--paper-50`.
/// The search control (F-57) is the first.
class KitAppBarButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const KitAppBarButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  State<KitAppBarButton> createState() => _KitAppBarButtonState();
}

class _KitAppBarButtonState extends State<KitAppBarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.chromeActive : const Color(0x00000000),
              borderRadius: AppRadius.smR,
            ),
            child: Icon(widget.icon,
                size: 20, color: _hover ? t.chromeFg : t.chromeControl),
          ),
        ),
      ),
    );
  }
}

/// A mono caps group label in the rail.
///
/// [onAdd] puts the reference's `.sb-group-add` beside it — a 22px `+` in the
/// chrome's subtle foreground, announced by [addLabel]. The Shelves group's
/// "New shelf" (4.83.0, ADR-117) is the first: it is how a first shelf gets
/// made, so it is drawn whatever the library holds.
class KitRailGroupLabel extends StatelessWidget {
  final String label;
  final VoidCallback? onAdd;
  final String? addLabel;

  const KitRailGroupLabel(this.label, {super.key, this.onAdd, this.addLabel});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final text = Padding(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, AppSpacing.s1),
      child: Text(
        label.toUpperCase(),
        style: AppTheme.mono(
          fontSize: 10,
          letterSpacing: 0.14 * 10,
          color: t.chromeSubtle,
        ),
      ),
    );
    final add = onAdd;
    if (add == null) return text;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: text),
        Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 2),
          child: _RailGroupAdd(onTap: add, label: addLabel ?? 'Add'),
        ),
      ],
    );
  }
}

class _RailGroupAdd extends StatefulWidget {
  final VoidCallback onTap;
  final String label;
  const _RailGroupAdd({required this.onTap, required this.label});

  @override
  State<_RailGroupAdd> createState() => _RailGroupAddState();
}

class _RailGroupAddState extends State<_RailGroupAdd> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            key: ValueKey('rail-add-${widget.label}'),
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _hover ? t.chromeHover : const Color(0x00000000),
              borderRadius: AppRadius.smR,
            ),
            child: Icon(
              Icons.add,
              size: 14,
              color: _hover ? t.chromeFg : t.chromeSubtle,
            ),
          ),
        ),
      ),
    );
  }
}

/// How many unread a badge says (`shell/notify.jsx`): the count, capped at
/// `9+`.
///
/// The cap is the whole reason this is a function. A badge is a glyph, not a
/// figure — it says *there is something here*, and the rail item is 10px of
/// mono wide at the trailing edge. `127` there is not a more precise badge,
/// it is a broken one; the feed is where the number lives.
String kitBadgeLabel(int count) => count > 9 ? '9+' : '$count';

/// §1.2 attention count (4.100.0, ADR-135): the pill's text for [count] —
/// null (no pill) at zero, `9+` past nine, and the em dash while the count is
/// unmeasured (null). Pair it with [KitNavItem.badgeUnmeasured].
String? kitAttentionLabel(int? count) => count == null
    ? '—'
    : count > 0
        ? kitBadgeLabel(count)
        : null;

/// A rail nav item.
///
/// The **active item is marked by a 2px accent bar in the leading margin** plus
/// a raised fill — never by colour alone.
class KitNavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  /// §1.2's optional trailing count, mono, in the chrome's own foregrounds.
  final String? count;

  /// The **unread badge** (`screens/activity.md` §Toasts and unread) — the
  /// same trailing slot as [count], drawn as a filled pill rather than a
  /// figure. Takes that slot when both are given: a count is how many things
  /// there are, a badge is that some of them are new, and the second is the
  /// one worth the space.
  final String? badge;

  /// §1.2's **attention count** whose read failed or has not answered
  /// (INV-30): [badge] (the em dash) is drawn in the same pill at the label's
  /// alpha, without the accent fill — a failed read is not work waiting.
  final bool badgeUnmeasured;

  const KitNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
    this.count,
    this.badge,
    this.badgeUnmeasured = false,
  });

  @override
  State<KitNavItem> createState() => _KitNavItemState();
}

class _KitNavItemState extends State<KitNavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = widget.active || _hover ? t.chromeFg : t.chromeMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: widget.active
                    ? t.chromeActive
                    : (_hover ? t.chromeHover : const Color(0x00000000)),
                borderRadius: AppRadius.smR,
              ),
              child: Row(
                children: [
                  Icon(widget.icon, size: 16, color: fg),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: fg,
                      ),
                    ),
                  ),
                  if (widget.badge != null)
                    _KitNavBadge(widget.badge!,
                        unmeasured: widget.badgeUnmeasured)
                  else if (widget.count != null)
                    Text(
                      widget.count!,
                      style: AppTheme.mono(
                        fontSize: 11,
                        color: widget.active ? t.chromeFg : t.chromeSubtle,
                      ),
                    ),
                ],
              ),
            ),
            if (widget.active)
              Positioned(
                left: -8,
                top: 8,
                bottom: 8,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: t.chromeAccentBar,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One shelf in the rail's tree (§1.2, 5.28.0, ADR-185): a [KitNavItem]'s row
/// with a 16px disclosure cell and the shelf's 8px dot in place of the icon,
/// indented 14px per level. [expanded] is null for a leaf, which keeps the
/// cell empty so every dot aligns. [count] is the subtree's volume count.
class KitRailShelfRow extends StatefulWidget {
  final String label;
  final Color dot;
  final int depth;
  final bool active;
  final bool? expanded;
  final String? count;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  const KitRailShelfRow({
    super.key,
    required this.label,
    required this.dot,
    required this.depth,
    required this.onTap,
    this.active = false,
    this.expanded,
    this.count,
    this.onToggle,
  });

  @override
  State<KitRailShelfRow> createState() => _KitRailShelfRowState();
}

class _KitRailShelfRowState extends State<KitRailShelfRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = widget.active || _hover ? t.chromeFg : t.chromeMuted;
    final open = widget.expanded;
    return Padding(
      padding: EdgeInsets.only(left: widget.depth * 14.0),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: open == null
                ? null
                : Semantics(
                    button: true,
                    expanded: open,
                    label: '${open ? 'Collapse' : 'Expand'} ${widget.label}',
                    excludeSemantics: true,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: widget.onToggle,
                        child: Icon(
                            open ? Icons.expand_more : Icons.chevron_right,
                            size: 12,
                            color: t.chromeSubtle),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTap: widget.onTap,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: widget.active
                            ? t.chromeActive
                            : (_hover ? t.chromeHover : const Color(0x00000000)),
                        borderRadius: AppRadius.smR,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 4),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: widget.dot, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              widget.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.fontSans,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: fg,
                              ),
                            ),
                          ),
                          if (widget.count != null)
                            Text(
                              widget.count!,
                              style: AppTheme.mono(
                                fontSize: 11,
                                color: widget.active
                                    ? t.chromeFg
                                    : t.chromeSubtle,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (widget.active)
                      Positioned(
                        left: -8,
                        top: 8,
                        bottom: 8,
                        child: Container(
                          width: 2,
                          decoration: BoxDecoration(
                            color: t.chromeAccentBar,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The filled pill a [KitNavItem] wears when something is unread.
///
/// **The fill is the chrome's accent, not `--accent`.** The rail is plum in
/// both themes, so a page token flips underneath a surface that does not:
/// `--accent`'s light half froze the drawer's avatar to a colour nobody chose,
/// and the same half would land here. `--brick-400` is the accent this surface
/// already draws — the active item's bar is it — and white is its foreground,
/// as everywhere else on the chrome.
class _KitNavBadge extends StatelessWidget {
  final String label;
  final bool unmeasured;

  const _KitNavBadge(this.label, {this.unmeasured = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      margin: const EdgeInsets.only(left: AppSpacing.s2),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Unmeasured: `rgba(255,255,255,.10)` under the label's `.40`.
        color: unmeasured ? t.chromeBorder : t.chromeAccentBar,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: AppTheme.mono(
            fontSize: 11,
            height: 1.2,
            color: unmeasured ? t.chromeSubtle : t.chromeFg),
      ),
    );
  }
}

/// The rail's **library card** (web `.sb-libcard`): the corpus at a glance, and
/// the place a newly added source visibly lands.
///
/// A card, not a row, because it carries figures. Same active treatment as
/// [KitNavItem] — 2px accent bar plus a raised fill.
///
/// NOTE: this pattern is in the web reference but was **missing from
/// `component-kit.md` §1.2** when the kit was transcribed. Recorded as owed
/// spec text (a `/contract-change` PATCH), not invented here — the figures,
/// alphas and metrics below are read off `app-kit.css`.
class KitRailCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final List<KitRailFigure> figures;
  final bool active;
  final VoidCallback? onTap;

  const KitRailCard({
    super.key,
    required this.icon,
    required this.label,
    required this.figures,
    this.active = false,
    this.onTap,
  });

  @override
  State<KitRailCard> createState() => _KitRailCardState();
}

class _KitRailCardState extends State<KitRailCard> {
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
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2, bottom: 6),
              padding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                color: widget.active
                    ? const Color(0x1AFFFFFF)
                    : (_hover
                        ? const Color(0x17FFFFFF)
                        : const Color(0x0DFFFFFF)),
                borderRadius: AppRadius.mdR,
                border: Border.all(
                    color: _hover
                        ? const Color(0x29FFFFFF)
                        : t.chromeBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(widget.icon, size: 15, color: t.chromeFg),
                      const SizedBox(width: 10),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          color: t.chromeFg,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (final f in widget.figures)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kitFigure(f.value).text,
                                style: AppTheme.mono(
                                  fontSize: 16,
                                  height: 1,
                                  // The highlight is a state the VALUE decides,
                                  // so it cannot fire on a dash (ADR-109).
                                  color: !kitFigure(f.value).measured
                                      ? t.chromeSubtle
                                      : f.highlight
                                          ? t.chromeAccentBar
                                          : t.chromeFg,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                f.label.toUpperCase(),
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.mono(
                                  fontSize: 9,
                                  letterSpacing: 0.1 * 9,
                                  color: const Color(0x61FFFFFF),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (widget.active)
              Positioned(
                left: -9,
                top: 12,
                bottom: 16,
                child: Container(
                  width: 2,
                  decoration: BoxDecoration(
                    color: t.chromeAccentBar,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One figure in a [KitRailCard]. [highlight] paints the numeral in
/// `--brick-400` — used for a non-zero unread count.
class KitRailFigure {
  /// Null means NOT MEASURED — drawn by [kitFigure], the one rule (ADR-109).
  final String? value;
  final String label;
  final bool highlight;

  const KitRailFigure(this.value, this.label, {this.highlight = false});
}

/// The rail's footer identity block: initials avatar, name, secondary line.
class KitRailFooter extends StatelessWidget {
  final String initials;
  final String name;
  final String? secondary;

  const KitRailFooter(
      {super.key,
      required this.initials,
      required this.name,
      this.secondary});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.accent,
              shape: BoxShape.circle,
            ),
            child: Text(
              initials,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.chromeFg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: t.chromeFg,
                  ),
                ),
                if (secondary != null && secondary!.isNotEmpty)
                  Text(
                    secondary!,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      fontSize: 10,
                      letterSpacing: 0.06 * 10,
                      color: t.chromeSubtle,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// §1.3 — the utility rail at the top of the main pane: a mono caps breadcrumb,
/// a flexible gap, then trailing controls. 48px, closed by a `--rule`.
/// The narrowest a crumb may be and still be one — about a dozen mono caps
/// at 10.5px. Under it the bar draws none.
const double _crumbFloor = 108;

class KitUtilityBar extends StatelessWidget {
  final String? crumb;
  final List<Widget> actions;
  final Widget? leading;

  const KitUtilityBar(
      {super.key, this.crumb, this.actions = const [], this.leading});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.s2),
          ],
          if (crumb != null)
            // Expanded, not Flexible + a Spacer: a loose Flexible that draws
            // nothing (the crumb dropped below its floor) still leaves its
            // share of the row EMPTY at the end, so the actions sat mid-bar
            // — the readings day view's Library control stood in the middle of
            // a phone's bar while the reference's sits at the edge (frames,
            // 2026-10-05). The crumb takes all the free room; the actions end
            // the row either way.
            Expanded(
              // A crumb squeezed to a stub is worse than no crumb: `§ LET…`
              // and `READI…` are what this bar drew on the readings day view
              // at phone width, where the back control and one action leave
              // about six characters. They read as a rendering fault and say
              // nothing, and the back control beside them has already named
              // the parent. Below the floor the crumb is dropped; above it
              // the ellipsis still earns its place, because a truncated
              // `READINGS · THURSDAY, SEPTEMB…` is a crumb.
              //
              // The LayoutBuilder sits INSIDE the Expanded deliberately: its
              // `maxWidth` is the room the crumb actually got, after the
              // leading control and the actions have taken theirs. Measured
              // at the outer bar it would be the whole width, and the rule
              // would fire on screens where the crumb fits perfectly well
              // — a detector red on correct code is worse than none.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < _crumbFloor) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    crumb!.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KitText.capsLabel(
                      context,
                      fontSize: 10.5,
                      letterSpacing: 0.13,
                      color: t.fgSubtle,
                    ),
                  );
                },
              ),
            )
          else
            const Spacer(),
          if (crumb != null && actions.isNotEmpty)
            const SizedBox(width: AppSpacing.s2),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s1),
            actions[i],
          ],
        ],
      ),
    );
  }
}
