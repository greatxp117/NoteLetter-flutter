import 'package:flutter/widgets.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §6.1 — the four button variants, and **the variant carries meaning**.
enum KitButtonVariant {
  /// `--accent`. The only primary CTA colour in the app.
  primary,

  /// `--secondary` — plum on paper, a white wash on ink.
  secondary,

  /// `--critical`. Destructive only.
  danger,

  /// Transparent, `--fg-muted`, fills `--hover`.
  ghost,
}

/// A kit button. Height 36, radius from its height (`0.25 × h`), sans 14/500.
///
/// Never build a button from a bare `TextButton`/`ElevatedButton`: Material's
/// defaults are a different design system, and a screen that reaches for one
/// gets Material's radius, ripple, elevation and padding — none of which appear
/// in any token file.
class KitButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final KitButtonVariant variant;

  const KitButton(
    this.label, {
    super.key,
    this.icon,
    this.onPressed,
    this.variant = KitButtonVariant.primary,
  });

  const KitButton.primary(this.label,
      {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.primary;
  const KitButton.secondary(this.label,
      {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.secondary;
  const KitButton.danger(this.label, {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.danger;
  const KitButton.ghost(this.label, {super.key, this.icon, this.onPressed})
      : variant = KitButtonVariant.ghost;

  @override
  State<KitButton> createState() => _KitButtonState();
}

class _KitButtonState extends State<KitButton> {
  bool _hover = false;

  static const double _height = 36;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final disabled = widget.onPressed == null;

    late final Color bg;
    late final Color fg;
    List<BoxShadow>? shadow;

    switch (widget.variant) {
      case KitButtonVariant.primary:
        bg = _hover ? t.accentHover : t.accent;
        fg = t.accentFg;
        shadow = AppShadows.s1;
      case KitButtonVariant.secondary:
        bg = _hover
            ? (t.isDark
                ? const Color(0x24FFFFFF)
                : AppColors.secondaryAccent)
            : t.secondary;
        fg = t.secondaryFg;
      case KitButtonVariant.danger:
        // `--critical` stays brick-500 in both themes, so the label is
        // paper-50 — NOT accentFg, which flips dark and would fail contrast.
        bg = _hover ? const Color(0xFF6E1F18) : t.critical;
        fg = t.criticalFg;
        shadow = AppShadows.s1;
      case KitButtonVariant.ghost:
        bg = _hover ? t.hover : const Color(0x00000000);
        fg = _hover ? t.fg : t.fgMuted;
    }

    return MouseRegion(
      cursor: disabled
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Container(
            height: _height,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: AppRadius.controlR(_height),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 14, color: fg),
                  const SizedBox(width: AppSpacing.s2),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 14,
                    height: 1,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// §6.2 — tag pill variants.
enum KitTagVariant { shelf, source, accent, ghost }

/// A pill. `3px 10px`, pill radius, sans 12/500, optional 6px leading dot.
///
/// A shelf pill takes its colour from the tag's **stored token name**. Swatches,
/// dots, plates and spines carry a hairline border in every theme — `plum-600`
/// and `ink-500` sit close to the dark-mode page and would otherwise vanish.
class KitTag extends StatelessWidget {
  final String label;
  final KitTagVariant variant;

  /// A `/tags.color` token name. Resolved via [AppColors.shelfColor]; an
  /// unrecognised value falls back to muted rather than failing.
  final String? colorToken;
  final VoidCallback? onTap;

  const KitTag(
    this.label, {
    super.key,
    this.variant = KitTagVariant.source,
    this.colorToken,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    late final Color bg;
    late final Color fg;
    Color? borderColor;

    switch (variant) {
      case KitTagVariant.shelf:
        bg = t.isDark ? const Color(0x1F6F8159) : const Color(0xFFE2E8DC);
        fg = t.isDark ? const Color(0xFFA8B894) : const Color(0xFF495936);
      case KitTagVariant.source:
        bg = t.surfaceSunken;
        fg = t.fgMuted;
      case KitTagVariant.accent:
        bg = t.accentChipBg;
        fg = t.accentChipFg;
        borderColor = t.accentChipBorder;
      case KitTagVariant.ghost:
        bg = const Color(0x00000000);
        fg = t.fgMuted;
        borderColor = t.borderStrong;
    }

    final dot = AppColors.shelfColor(colorToken);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: borderColor == null ? null : Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dot,
                shape: BoxShape.circle,
                // The hairline that keeps plum-600 and ink-500 visible on the
                // dark page.
                border: Border.all(color: t.border, width: 0.5),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: dot != null && variant == KitTagVariant.shelf ? fg : fg,
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? pill
        : GestureDetector(onTap: onTap, child: pill);
  }
}

/// §6.3 — a status pill. Mono 10 / 0.1em caps.
class KitStatusPill extends StatelessWidget {
  final String label;
  final bool positive;

  const KitStatusPill(this.label, {super.key, this.positive = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2, vertical: 2),
      decoration: BoxDecoration(
        color: positive
            ? (t.isDark ? const Color(0x1F6F8159) : const Color(0xFFE2E8DC))
            : t.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: KitText.capsLabel(
          context,
          fontSize: 10,
          letterSpacing: 0.1,
          color: positive
              ? (t.isDark ? const Color(0xFFA8B894) : const Color(0xFF495936))
              : t.fgMuted,
        ),
      ),
    );
  }
}

/// §6.4 — the document plate. Portrait, tinted per type, mono 9 caps.
enum KitBadgeSize {
  /// 26×32 — inline, in a timeline row.
  inline(26, 32, 8),

  /// 36×44 — in a source row.
  row(36, 44, 9),

  /// 40×48 — in a screen header.
  header(40, 48, 10);

  final double width;
  final double height;
  final double fontSize;
  const KitBadgeSize(this.width, this.height, this.fontSize);
}

class KitFileBadge extends StatelessWidget {
  /// `pdf` · `epub` · `web` · `podcast` · `note` — anything else renders
  /// neutral. Build it from a document's `type` with [kitDocKind].
  final String kind;
  final KitBadgeSize size;

  const KitFileBadge(this.kind, {super.key, this.size = KitBadgeSize.row});

  /// The plate's own word, which is **not** the kind: an audio source's plate
  /// reads AUDIO, and an unknown kind reads DOC rather than printing whatever
  /// token was passed in. Printing the raw value is the same class of defect as
  /// showing a user the literal status `pending_upload`.
  static const _labels = <String, String>{
    'pdf': 'PDF',
    'epub': 'EPUB',
    'web': 'WEB',
    'podcast': 'AUDIO',
    'note': 'NOTE',
  };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final k = kind.toLowerCase();

    late final Color bg;
    late final Color fg;
    late final Color border;

    switch (k) {
      case 'pdf':
        bg = const Color(0x1F9D352D);
        fg = t.isDark ? const Color(0xFFE97D39) : const Color(0xFF6E1F18);
        border = const Color(0x339D352D);
      case 'epub':
        bg = t.isDark ? const Color(0x1F6F8159) : const Color(0xFFE2E8DC);
        fg = t.isDark ? const Color(0xFFA8B894) : const Color(0xFF495936);
        border = const Color(0x336F8159);
      case 'web':
      case 'note':
      case 'podcast':
        bg = t.surfaceSunken;
        fg = t.fgMuted;
        border = t.border;
      default:
        bg = t.surfaceSunken;
        fg = t.fgMuted;
        border = t.border;
    }

    return Container(
      width: size.width,
      height: size.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.xsR,
        border: Border.all(color: border),
      ),
      child: Text(
        _labels[k] ?? 'DOC',
        style: AppTheme.mono(
          fontSize: size.fontSize,
          height: 1,
          letterSpacing: 0.06 * size.fontSize,
          color: fg,
        ),
      ),
    );
  }
}

/// §6.5 — a 34×34 icon button. Icon 17px.
///
/// Icon stroke weight is **1.75 everywhere**, round caps and joins. Flutter's
/// bundled Material icons have a fixed stroke, so the app uses the `_outlined`
/// set throughout — mixing filled and outlined is visible across a screen even
/// when nothing else is wrong.
class KitIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;

  const KitIconButton(this.icon,
      {super.key, this.onPressed, this.tooltip, this.color});

  @override
  State<KitIconButton> createState() => _KitIconButtonState();
}

class _KitIconButtonState extends State<KitIconButton> {
  bool _hover = false;
  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: _size,
          height: _size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hover ? t.hover : const Color(0x00000000),
            borderRadius: AppRadius.controlR(_size),
          ),
          child: Icon(
            widget.icon,
            size: 17,
            color: widget.color ?? (_hover ? t.fg : t.fgMuted),
          ),
        ),
      ),
    );
  }
}

/// A document `type` → the plate kind ([KitFileBadge]).
///
/// Mirrors the web reference's `docKind` exactly, including that every web-ish
/// source (article, YouTube, Instagram, TikTok) shares one plate: the plate says
/// where a source came from, not which service it came through.
String kitDocKind(String type) {
  switch (type) {
    case 'pdf':
      return 'pdf';
    case 'epub':
      return 'epub';
    case 'podcast':
      return 'podcast';
    case 'url':
    case 'article':
    case 'youtube':
    case 'instagram':
    case 'tiktok':
      return 'web';
    default:
      return 'note';
  }
}
