// The signed-out pages' own sheet — site furniture, not app furniture.
//
// Xavier's decision of 2026-09-26 on QUEUE F-44: the web reference BINDS for
// the signed-out landing and sign-in. Both web sheets (`signin.css`,
// `landing-actual.css`) say so in their headers — the signed-out surfaces share
// the marketing lockup and nothing else with the app, so they carry their own
// sheet rather than composing from the app kit (component-kit records the
// exception). **Tokens still bind**: every colour below is a `Tokens` role,
// every radius an `AppRadius` step, and the colour-literal gate reads this
// directory like any other.
//
// This is why these files live under `lib/site/` and not `lib/pages/`: the
// no-inline-composition lint (test/kit/no_inline_composition_test.dart) is the
// app kit's rule, and a page here that composed from the kit would be the
// defect, not one that spells its own type. Class names follow the web's
// (`si-*`) so a design diff reads against the same nouns.
import 'package:flutter/material.dart';

import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit_ground.dart';
import '../widgets/kit/kit_shell.dart';

/// The type roles of `signin.css`, resolved for the current theme.
class SiteType {
  final Tokens t;
  const SiteType(this.t);

  static SiteType of(BuildContext context) => SiteType(Tokens.of(context));

  TextStyle _mono(double size, double tracking, Color color) => TextStyle(
    fontFamily: AppTheme.fontMono,
    fontSize: size,
    letterSpacing: tracking * size,
    color: color,
    height: 1.3,
  );

  TextStyle _sans(
    double size,
    Color color, {
    double? height,
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: AppTheme.fontSans,
    fontSize: size,
    height: height,
    fontWeight: weight,
    color: color,
  );

  TextStyle _serif(
    double size, {
    double? height,
    double weight = 400,
    double tracking = 0,
    double? opsz,
    FontStyle? style,
    required Color color,
  }) {
    return TextStyle(
      fontFamily: AppTheme.fontSerif,
      fontSize: size,
      height: height,
      fontWeight: FontWeight.values[(weight ~/ 100) - 1],
      fontVariations: [
        FontVariation('wght', weight),
        if (opsz != null) FontVariation('opsz', opsz),
      ],
      fontStyle: style,
      letterSpacing: tracking * size,
      color: color,
    );
  }

  /// `.si-back` — also the landing's quiet top-bar link.
  TextStyle get back => _sans(13.5, t.fgMuted);

  /// `.si-folio` — `§ SIGN IN`.
  TextStyle get folio => _mono(11, 0.16, t.fgSubtle);

  /// `.si-h` — `clamp(38px, 5.2vw, 54px)`, letterpressed, opsz 60.
  TextStyle heading(double width) => _serif(
    (width * 0.052).clamp(38.0, 54.0),
    height: 1.04,
    tracking: -0.02,
    opsz: 60,
    color: t.fg,
  ).copyWith(shadows: AppShadows.letterpress);

  /// The `<em>` inside a heading: italic, in the accent.
  TextStyle em(TextStyle base) =>
      base.copyWith(fontStyle: FontStyle.italic, color: t.accent);

  /// `.si-lede` — italic serif 17/26 at `--fg-lede`.
  TextStyle get lede =>
      _serif(17, height: 26 / 17, style: FontStyle.italic, color: t.fgLede);

  /// `.si-field label`.
  TextStyle get label => _mono(10.5, 0.14, t.fgSubtle);

  /// `.si-field input`.
  TextStyle get input => _sans(15, t.fg);
  TextStyle get placeholder => _sans(15, t.fgSubtle);

  /// `.si-forgot`.
  TextStyle get forgot => _sans(12.5, t.fgMuted);

  /// `.si-submit`.
  TextStyle get submit => _sans(15, t.accentFg, weight: FontWeight.w500);

  /// `.si-or`.
  TextStyle get or => _mono(10, 0.16, t.fgSubtle);

  /// `.si-ghost`.
  TextStyle get ghost => _sans(14.5, t.fg);

  /// `.si-note` and its link button.
  TextStyle get note => _sans(13.5, t.fgMuted, height: 1.6);
  TextStyle get noteLink => note.copyWith(
    color: t.link,
    decoration: TextDecoration.underline,
    decorationColor: t.linkDecor,
  );

  /// `.si-said` — the reset confirmation.
  TextStyle get said => _sans(13, t.fgMuted, height: 19 / 13);

  /// `.si-aside .eb`.
  TextStyle get asideEyebrow => _mono(10.5, 0.16, t.accentChipFg);

  /// `.si-aside h2`.
  TextStyle get asideHeading =>
      _serif(26, height: 1.18, weight: 500, tracking: -0.015, color: t.fg);

  /// `.si-aside .pts li b` — text, so `--accent-text`, not `--seal`.
  TextStyle get pointNumber => _mono(10.5, 0.12, t.accentText);

  /// `.si-aside .pts li span` and its `<i>` lead.
  TextStyle get pointBody => _sans(14, t.fgMuted, height: 21 / 14);
  TextStyle get pointLead => pointBody.copyWith(color: t.fg);
}

/// `.nsi` — the page ground: `--bg` under the grain, no halftone lattice.
class SitePage extends StatelessWidget {
  final Widget child;
  const SitePage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Tokens.of(context).bg,
      child: KitGround(lattice: false, child: child),
    );
  }
}

/// `.si-top .brand` — the harmonised signed-out lockup: the quill at 26 and
/// the wordmark at 17 / 0.11em / opsz 24, in `--fg` (the app's rail draws it
/// in the chrome foreground instead).
class SiteBrand extends StatelessWidget {
  final VoidCallback onTap;
  const SiteBrand({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      label: 'NoteLetter',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            KitQuill(size: 26, color: t.fg),
            const SizedBox(width: 9),
            KitWordmark(fontSize: 17, color: t.fg, tracking: 0.11, opsz: 24),
          ],
        ),
      ),
    );
  }
}

/// A bare text control — `.si-back`, `.si-forgot`, the note's link.
class SiteTextButton extends StatelessWidget {
  final String label;
  final TextStyle style;
  final VoidCallback? onTap;
  const SiteTextButton(
    this.label, {
    super.key,
    required this.style,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: onTap == null ? 0.6 : 1,
          child: Text(label, style: style),
        ),
      ),
    );
  }
}

/// `.si-dash` — a 44px rule, then the 9px seal tick.
class SiteDash extends StatelessWidget {
  const SiteDash({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 30),
      child: Row(
        children: [
          Container(width: 44, height: 1, color: t.borderStrong),
          const SizedBox(width: 6),
          Container(width: 1, height: 9, color: t.seal),
        ],
      ),
    );
  }
}

/// `.si-field` — a mono caps label over a sunken input. [trailing] sits on
/// the label's row (`.si-pw-row`'s "Forgot it?").
class SiteField extends StatefulWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  const SiteField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.action,
    this.onSubmitted,
    this.trailing,
  });

  @override
  State<SiteField> createState() => _SiteFieldState();
}

class _SiteFieldState extends State<SiteField> {
  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final type = SiteType(t);
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: AppRadius.smR,
      borderSide: BorderSide(color: c, width: w),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(widget.label.toUpperCase(), style: type.label),
            ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
        const SizedBox(height: 7),
        TextField(
          controller: widget.controller,
          obscureText: widget.obscure,
          keyboardType: widget.keyboardType,
          autofillHints: widget.autofillHints,
          autocorrect: false,
          enableSuggestions: !widget.obscure,
          textInputAction: widget.action,
          onSubmitted: widget.onSubmitted,
          style: type.input,
          cursorColor: t.accent,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surfaceSunken,
            hintText: widget.hint,
            hintStyle: type.placeholder,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 13,
              vertical: 13,
            ),
            enabledBorder: border(t.border),
            border: border(t.border),
            // `:focus` — the outline in the accent. CSS draws it OUTSIDE a
            // strong border; Flutter has one stroke, so it is the accent.
            focusedBorder: border(t.accent, 2),
          ),
        ),
      ],
    );
  }
}

/// `.si-submit` — the accent fill, full width of the form column.
class SiteSubmit extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const SiteSubmit(this.label, {super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Material(
        color: t.accent,
        borderRadius: AppRadius.smR,
        shadowColor: t.fg,
        elevation: 0,
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.smR,
          hoverColor: t.accentHover,
          child: Container(
            decoration: const BoxDecoration(
              borderRadius: AppRadius.smR,
              boxShadow: AppShadows.s1,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            alignment: Alignment.center,
            child: Text(label, style: SiteType(t).submit),
          ),
        ),
      ),
    );
  }
}

/// `.si-ghost` — the raised outline button that carries the Google mark.
class SiteGhost extends StatelessWidget {
  final String label;
  final Widget? leading;
  final VoidCallback? onPressed;
  const SiteGhost(
    this.label, {
    super.key,
    this.leading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1,
      child: Material(
        color: t.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.smR,
          side: BorderSide(color: t.border),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: AppRadius.smR,
          hoverColor: t.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 9)],
                Flexible(
                  child: Text(label,
                      style: SiteType(t).ghost,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.si-or` — a caps word between two hairlines.
class SiteOr extends StatelessWidget {
  final String word;
  const SiteOr({super.key, this.word = 'or'});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: t.rule)),
          const SizedBox(width: 14),
          Text(word.toUpperCase(), style: SiteType(t).or),
          const SizedBox(width: 14),
          Expanded(child: Container(height: 1, color: t.rule)),
        ],
      ),
    );
  }
}

/// Google's "G", drawn — the reference's `GoogleIcon`, one provider with one
/// face on every signed-out surface. Four arcs and the bar; the colours are
/// Google's, fixed by brand in both themes.
class GoogleMark extends StatelessWidget {
  final double size;
  const GoogleMark({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: const CustomPaint(painter: _GooglePainter()),
  );
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  // literal-ok: Google's brand blue — the G is Google's mark, fixed in both themes
  static const _blue = Color(0xFF4285F4);
  // literal-ok: Google's brand green — the G is Google's mark, fixed in both themes
  static const _green = Color(0xFF34A853);
  // literal-ok: Google's brand yellow — the G is Google's mark, fixed in both themes
  static const _yellow = Color(0xFFFBBC05);
  // literal-ok: Google's brand red — the G is Google's mark, fixed in both themes
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final r = (s - stroke) / 2;
    final c = Offset(s / 2, s / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint p(Color color) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    // Clockwise from 3 o'clock, as Canvas angles run; the G's mouth is the
    // open quarter-eighth between the red arc's end and the bar.
    canvas.drawArc(rect, 0, 45 * deg, false, p(_blue));
    canvas.drawArc(rect, 45 * deg, 90 * deg, false, p(_green));
    canvas.drawArc(rect, 135 * deg, 90 * deg, false, p(_yellow));
    canvas.drawArc(rect, 225 * deg, 95 * deg, false, p(_red));
    // The bar, from the centre to the right edge of the ring.
    canvas.drawRect(
      Rect.fromLTWH(s / 2, s / 2 - stroke / 2, s / 2, stroke),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
