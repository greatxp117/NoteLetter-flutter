import 'package:flutter/widgets.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// The three page-header forms (`component-kit.md` §2).
///
/// All three share one anatomy — **eyebrow → serif display title → italic serif
/// standfirst → optional rule** — and differ in weight and in which optional
/// parts appear. **Every screen uses exactly one.** They are separate widgets
/// rather than one configurable header precisely so a screen has to choose,
/// instead of assembling a fourth form by accident.
///
/// Common to all three: the title is serif and **letterpressed**, with negative
/// tracking and an `opsz` matched to its size, and an emphasised clause inside
/// it is **italic `--accent`** (write it as `*clause*` — see [AccentTitle]).

/// §2.1 — the home screen. Greeting + standfirst. No eyebrow, no rule.
class GreetingHeader extends StatelessWidget {
  /// Wrap the accent clause in asterisks: `'Good evening, *Xavier*'`.
  final String title;
  final String standfirst;

  const GreetingHeader(
      {super.key, required this.title, required this.standfirst});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccentTitle(
          title,
          style: AppTheme.serif(
            fontSize: 36,
            height: 1.1,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.02 * 36,
            color: Tokens.of(context).fg,
          ).copyWith(shadows: AppShadows.letterpress),
        ),
        const SizedBox(height: 6),
        Lede(standfirst, fontSize: 17, height: 26),
      ],
    );
  }
}

/// §2.2 — index and settings screens. Title + standfirst.
class PageHeader extends StatelessWidget {
  final String title;
  final String? standfirst;
  final Widget? trailing;

  const PageHeader(
      {super.key, required this.title, this.standfirst, this.trailing});

  @override
  Widget build(BuildContext context) {
    final heading = AccentTitle(
      title,
      style: AppTheme.serif(
        fontSize: 32,
        height: 1.1,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.02 * 32,
        color: Tokens.of(context).fg,
      ).copyWith(shadows: AppShadows.letterpress),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (trailing == null)
          heading
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: heading),
              const SizedBox(width: AppSpacing.s4),
              trailing!,
            ],
          ),
        if (standfirst != null) ...[
          const SizedBox(height: 6),
          Lede(standfirst!, fontSize: 16, height: 24),
        ],
        const SizedBox(height: AppSpacing.s8 - 4),
      ],
    );
  }
}

/// §2.3 — the full editorial opener: a document or section presented as a
/// chapter. Folio row → title → standfirst → **chapter rule**.
class ChapterOpening extends StatelessWidget {
  /// The badge or seal that opens the folio row.
  final Widget? mark;

  /// Mono caps, at `--seal`.
  final String? folio;
  final String title;
  final String? standfirst;

  const ChapterOpening({
    super.key,
    this.mark,
    this.folio,
    required this.title,
    this.standfirst,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s2, bottom: 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mark != null || folio != null)
              Row(
                children: [
                  if (mark != null) ...[
                    mark!,
                    const SizedBox(width: AppSpacing.s3),
                  ],
                  if (folio != null)
                    Expanded(
                      child: Text(
                        folio!.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: KitText.capsLabel(context,
                            color: t.seal, letterSpacing: 0.18),
                      ),
                    ),
                ],
              ),
            const SizedBox(height: 14),
            AccentTitle(
              title,
              style: AppTheme.serif(
                fontSize: 44,
                height: 1.03,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.024 * 44,
                color: t.fg,
              ).copyWith(shadows: AppShadows.letterpress),
            ),
            if (standfirst != null) ...[
              const SizedBox(height: 14),
              Lede(standfirst!, fontSize: 18, height: 28),
            ],
            const SizedBox(height: 22),
            const ChapterRule(),
          ],
        ),
      ),
    );
  }
}

/// The chapter rule: **two bars, not one.** A 54×2 rule in `--fg` with a 26×1
/// `--accent` bar 5px beneath it. The short accent underbar is the part that
/// gets dropped, and without it the rule reads as a generic divider.
class ChapterRule extends StatelessWidget {
  const ChapterRule({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SizedBox(
      width: 54,
      height: 8,
      child: Stack(
        children: [
          Container(width: 54, height: 2, color: t.fg),
          Positioned(
            top: 5,
            child: Container(width: 26, height: 1, color: t.accent),
          ),
        ],
      ),
    );
  }
}

/// §3 — separates the stacked sections of an index screen.
///
/// An **eyebrow** (optionally carrying its own count as part of the text) and
/// an optional trailing link, **baseline-aligned** with it.
class SectionHeader extends StatelessWidget {
  final String eyebrow;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// The reference margin is `32px 0 14px`; the leading 32 is suppressed for
  /// the first section on a screen, which sits under a header that has already
  /// paid for the space.
  final bool first;

  const SectionHeader(
    this.eyebrow, {
    super.key,
    this.actionLabel,
    this.onAction,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : AppSpacing.s8, bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: Eyebrow(eyebrow)),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                actionLabel!,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 13,
                  color: t.fgMuted,
                  decoration: TextDecoration.underline,
                  decorationColor: t.linkDecor,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// §3 variant — the ruled section label used inside the letter sheet: a mono
/// caps label beside a hairline that fills the remaining width.
class RuledSectionLabel extends StatelessWidget {
  final String label;

  const RuledSectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s8 - 4, bottom: 14),
      child: Row(
        children: [
          Text(label.toUpperCase(),
              style: KitText.capsLabel(context,
                  fontSize: 10, letterSpacing: 0.16)),
          const SizedBox(width: AppSpacing.s3),
          Expanded(child: Container(height: 1, color: t.border)),
        ],
      ),
    );
  }
}
