import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// The page header (`component-kit.md` §2.1) — **one pattern with optional
/// parts**, used by nine of the eleven screens.
///
/// Anatomy: `lead` (badge/seal) → `folio` (mono caps at `--seal`) → **title**
/// (the one required part; serif, letterpressed, with an italic `--accent`
/// clause written as `*clause*`) → `standfirst` (italic serif, never the UI
/// sans) → `actions` → the **chapter rule**.
///
/// 4.5.0 shipped three header widgets here — a greeting header and a page
/// header alongside this one — because the kit was transcribed from
/// `app-kit.css` without reading the call sites. `.lib-greeting`, `.lib-sub`,
/// `.sources-h1` and `.sources-sub` are dead CSS that no web component
/// renders. Corrected at contract 4.5.1; a stylesheet records what was once
/// true, only the components say what renders now.
class ChapterOpening extends StatelessWidget {
  /// Opens the folio row — a [KitFileBadge] or a seal.
  final Widget? mark;

  /// Mono caps at `--seal`. Carries the screen's count.
  final String? folio;

  /// Accent clause written as `*clause*`.
  final String title;
  final String? standfirst;

  /// Top-aligned with the title block.
  final List<Widget> actions;

  /// Suppressible where the header runs straight into a control bar.
  final bool rule;

  const ChapterOpening({
    super.key,
    this.mark,
    this.folio,
    required this.title,
    this.standfirst,
    this.actions = const [],
    this.rule = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (mark != null || folio != null) ...[
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
                    // Two lines on a phone rather than an ellipsis: the folio
                    // carries the screen's COUNT, and the count is at the end
                    // of the line — truncating drops the only figure in it.
                    maxLines: compact ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: KitText.capsLabel(context,
                        color: t.seal, letterSpacing: 0.18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        AccentTitle(
          title,
          style: AppTheme.serif(
            // The reference is 44px; a 44px display line does not fit a phone,
            // so narrow viewports take 32. Recorded in CLAUDE.md §Composition
            // deviations — the proportions and roles are unchanged.
            fontSize: compact ? 32 : 44,
            height: 1.03,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.024 * (compact ? 32 : 44),
            color: t.fg,
          ).copyWith(shadows: AppShadows.letterpress),
        ),
        if (standfirst != null) ...[
          const SizedBox(height: 14),
          Lede(standfirst!, fontSize: 18, height: 28),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s2, bottom: 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 768),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (actions.isEmpty)
              titleBlock
            // On a phone the actions go BELOW the title. Beside it they take
            // half the width, and a 32px display line in the other half wraps
            // mid-word — the greeting rendered as "Good mornin / g, / reader".
            else if (compact) ...[
              titleBlock,
              const SizedBox(height: AppSpacing.s4),
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: actions,
              ),
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: AppSpacing.s4),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < actions.length; i++) ...[
                          if (i > 0) const SizedBox(width: AppSpacing.s2),
                          actions[i],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            if (rule) ...[
              const SizedBox(height: 22),
              const ChapterRule(),
            ],
          ],
        ),
      ),
    );
  }
}

/// §2.2 — the header for a screen reached *from* another one. Back control →
/// eyebrow → **plain sans** standfirst.
///
/// Deliberately not the editorial voice: this is a utility screen, and the
/// italic serif lede belongs to chapter openings.
class SubScreenHeader extends StatelessWidget {
  final String parentLabel;
  final VoidCallback? onBack;
  final String eyebrow;
  final String? standfirst;

  const SubScreenHeader({
    super.key,
    required this.parentLabel,
    this.onBack,
    required this.eyebrow,
    this.standfirst,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onBack,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chevron_left, size: 15, color: t.fgMuted),
                const SizedBox(width: 2),
                Text(
                  parentLabel,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    color: t.fgMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Eyebrow(eyebrow),
        if (standfirst != null) ...[
          const SizedBox(height: AppSpacing.s1),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s5),
            child: Text(
              standfirst!,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 14,
                height: 1.45,
                color: t.fgMuted,
              ),
            ),
          ),
        ],
      ],
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
