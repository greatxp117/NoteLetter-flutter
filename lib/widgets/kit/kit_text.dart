import 'package:flutter/widgets.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// The named type roles (`spec/design-tokens.md` §Type, `component-kit.md`).
///
/// These are the app's `.h1` / `.eyebrow` / `.lede` / `.meta` / `.caps-label`
/// — semantic roles, not sizes. A screen picks a **role**, never a font size:
/// `KitText.eyebrow` rather than "mono 11 caps at 0.16em", because the second
/// form is what drifts when it is retyped on the next screen.
///
/// Material's `TextTheme` (app_theme.dart) covers display/headline/title/body.
/// It has no name for the four devices that actually carry this brand — the
/// eyebrow, the italic serif lede, the mono caps label and the reading measure
/// — which is why they appeared on five Flutter screens and eleven web ones
/// (ADR-041). They live here so a screen cannot forget them by accident.
class KitText {
  KitText._();

  // ── Display / headings — serif, letterpressed, tight ─────────────────────

  /// `.h1` — 48/56, the largest heading a screen uses.
  static TextStyle h1(BuildContext context) => AppTheme.serif(
        fontSize: 48,
        height: 56 / 48,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.02 * 48,
        color: Tokens.of(context).fg,
      ).copyWith(shadows: AppShadows.letterpress);

  /// `.h2` — 36/44.
  static TextStyle h2(BuildContext context) => AppTheme.serif(
        fontSize: 36,
        height: 44 / 36,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.015 * 36,
        color: Tokens.of(context).fg,
      );

  /// `.h3` — 28/36.
  static TextStyle h3(BuildContext context) => AppTheme.serif(
        fontSize: 28,
        height: 36 / 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.01 * 28,
        color: Tokens.of(context).fg,
      );

  /// `.h4` — 18/28.
  static TextStyle h4(BuildContext context) => AppTheme.serif(
        fontSize: 18,
        height: 28 / 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.005 * 18,
        color: Tokens.of(context).fg,
      );

  // ── The four editorial devices ───────────────────────────────────────────

  /// `.eyebrow` — 11px / 600 / 0.16em caps in the UI sans.
  ///
  /// Opens a section. **The most commonly dropped required part in the whole
  /// kit**, and the one whose absence most changes how a screen reads: without
  /// it a stack of sections becomes an undifferentiated list.
  static TextStyle eyebrow(BuildContext context, {Color? color}) => TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 11,
        height: 16 / 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.16 * 11,
        color: color ?? Tokens.of(context).fgMuted,
      );

  /// `.lede` — italic serif 18/30 at `--fg-lede`. The standfirst under a page
  /// title. **Italic serif, never the UI sans**: rendering a standfirst in the
  /// body face is the second-most-common way a header stops looking like this
  /// app while every colour in it stays correct.
  static TextStyle lede(BuildContext context,
          {double fontSize = 18, double? height}) =>
      AppTheme.serif(
        fontSize: fontSize,
        height: (height ?? 30) / fontSize,
        fontWeight: FontWeight.w400,
        fontStyle: FontStyle.italic,
        color: Tokens.of(context).fgLede,
      );

  /// `.meta` — sans 14/20 at `--fg-subtle`.
  static TextStyle meta(BuildContext context) => TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 14,
        height: 20 / 14,
        color: Tokens.of(context).fgSubtle,
      );

  /// `.caps-label` — mono 11 / 500 / 0.08em caps. Stat labels, folio lines,
  /// group labels, timeline chips.
  static TextStyle capsLabel(BuildContext context,
          {Color? color, double fontSize = 11, double letterSpacing = 0.08}) =>
      AppTheme.mono(
        fontSize: fontSize,
        height: 14 / 11,
        fontWeight: FontWeight.w500,
        letterSpacing: letterSpacing * fontSize,
        color: color ?? Tokens.of(context).fgMuted,
      );

  // ── Body ─────────────────────────────────────────────────────────────────

  /// `.body` — sans 16/24, the UI default.
  static TextStyle body(BuildContext context) => TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 16,
        height: 24 / 16,
        color: Tokens.of(context).fg,
      );

  /// `.body-reading` — serif 18/30. Prose. Pair with [readingMeasure].
  static TextStyle bodyReading(BuildContext context) => AppTheme.serif(
        fontSize: 18,
        height: 30 / 18,
        fontWeight: FontWeight.w400,
        color: Tokens.of(context).fg,
      );

  /// `.pull-quote` — italic serif 22/32 at `--fg-muted`.
  static TextStyle pullQuote(BuildContext context) => AppTheme.serif(
        fontSize: 22,
        height: 32 / 22,
        fontStyle: FontStyle.italic,
        color: Tokens.of(context).fgMuted,
      );

  /// Constrains prose to `--measure`. The frame ceiling and the measure are
  /// **two different constraints** and a reading screen obeys both.
  static Widget readingMeasure({required Widget child}) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSpacing.measure),
        child: child,
      );
}

/// An eyebrow, as a widget. Sections take this rather than styling a [Text]
/// themselves.
class Eyebrow extends StatelessWidget {
  final String text;
  final Color? color;

  const Eyebrow(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), style: KitText.eyebrow(context, color: color));
}

/// The italic serif standfirst under a page title, capped at the 56ch the
/// reference uses for every header form.
class Lede extends StatelessWidget {
  final String text;
  final double fontSize;
  final double? height;
  final double maxWidth;

  const Lede(
    this.text, {
    super.key,
    this.fontSize = 18,
    this.height,
    this.maxWidth = 540,
  });

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Text(text,
            style: KitText.lede(context, fontSize: fontSize, height: height)),
      );
}

/// A display title with the signature **italic accent clause**.
///
/// Splits on a single pair of `*asterisks*`: `Good evening, *Xavier*` renders
/// the second half italic in `--accent`. That clause is the app's signature and
/// is a required part of the greeting and chapter-opening headers — not
/// decoration to drop.
class AccentTitle extends StatelessWidget {
  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  const AccentTitle(this.text, {super.key, required this.style, this.textAlign});

  @override
  Widget build(BuildContext context) {
    final accent = Tokens.of(context).accent;
    final parts = text.split('*');
    if (parts.length < 3) {
      return Text(text, style: style, textAlign: textAlign);
    }
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          for (var i = 0; i < parts.length; i++)
            TextSpan(
              text: parts[i],
              style: i.isOdd
                  ? style.copyWith(
                      fontStyle: FontStyle.italic, color: accent)
                  : null,
            ),
        ],
      ),
      textAlign: textAlign,
    );
  }
}
