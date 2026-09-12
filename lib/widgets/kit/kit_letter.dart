/// §11 — the newsletter as a physical page.
///
/// Two forms, and the letter itself decides which (4.50.0, ADR-087):
///
///  * [KitLetterPaper] hosts a body that **brings its own letterhead** BARE.
///    It is the letter that was sent, so it is not framed, not tinted and not
///    re-themed — a reader opening it is looking at the object in their inbox.
///  * [KitLetterSheet] is the frame this client draws for a body that has
///    none, which is every `daily` letter written before 4.50.0 and every
///    readings letter. It is the §11 pattern in full.
///
/// Deciding by the ATTRIBUTE rather than by a version is what lets an archive
/// of both shapes render correctly, in either deploy order.
library;

import 'package:flutter/material.dart' show Icon, IconData, Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
// The sent letter is a TABLE layout and has to be: it is HTML mail, where
// tables are the only reliable box model. flutter_html drops <table> unless
// this extension is installed, so without it a complete letter renders as an
// empty strip — which it did, with nothing failing.
import 'package:flutter_html_table/flutter_html_table.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// The letter's own colours, frozen.
///
/// The sent letter's palette is **baked light hex** in the backend renderer,
/// because no email client resolves a custom property
/// (`harness/letter_palette_check.py` holds that table to `theme.css`). The
/// ground it sits on has to be frozen with it: a `--surface` page behind a
/// light letter puts a near-black gutter around white paper in dark mode, and
/// a theme-flipping body would be a different object from the one that was
/// sent.
class _Paper {
  // literal-ok: --paper-50, the letter's own page. It does not flip, for the
  // same reason the letter's inlined colours do not (ADR-087).
  static const ground = Color(0xFFFAFAF7);
  // literal-ok: --ink-700, the letter's own ink, frozen with its ground.
  static const ink = Color(0xFF14171F);
}

/// A complete letter, hosted bare on its own paper.
class KitLetterPaper extends StatelessWidget {
  final String html;

  const KitLetterPaper(this.html, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _Paper.ground,
      width: double.infinity,
      child: Html(
        data: html,
        extensions: const [TableHtmlExtension()],
        style: {
          // The shared map, resolved against the LIGHT tokens and only the
          // light ones. Every other Html() in the app passes
          // `AppTheme.htmlStyles(Tokens.of(context))`; this one may not,
          // because the letter does not flip — so it is frozen at the theme
          // the letter was rendered in rather than skipping the map, which
          // would take flutter_html's own black four-sided <hr>.
          ...AppTheme.htmlStyles(Tokens.light),
          // The body style carries only the face and the ink — every colour
          // that matters is inline in the letter and must win.
          'body': Style(
            margin: Margins.zero,
            padding: HtmlPaddings.zero,
            color: _Paper.ink,
            fontFamily: AppTheme.fontSerif,
          ),
          'img': Style(width: Width(100, Unit.percent)),
        },
      ),
    );
  }
}

/// The §11 letter sheet: the frame this client draws around a **frame-less**
/// body.
///
/// Required parts, in order — checkered page ground · centred paper · masthead
/// (title + issue marker) closed by a `--border-strong` rule · standfirst ·
/// body · seal footer above a `--border` top rule. The **actions bar sits
/// outside the sheet** and is therefore not part of this widget.
class KitLetterSheet extends StatelessWidget {
  /// The masthead's title. Set in the versal lockup the letter uses: uppercase
  /// serif with the opening capitals raised.
  final String title;

  /// The trailing issue marker — a subject, a date, a number.
  final String? marker;

  /// The italic serif standfirst under the masthead rule.
  final String? standfirst;

  /// The body, already composed: [RuledSectionLabel]s, [KitLetterProse] and
  /// [KitLetterAttribution] rows.
  final List<Widget> children;

  /// The seal footer's line. Italic serif, beside the mark.
  final String sealText;

  const KitLetterSheet({
    super.key,
    required this.title,
    this.marker,
    this.standfirst,
    this.children = const [],
    required this.sealText,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: AppSpacing.frameSheet),
        child: Container(
          margin: EdgeInsets.symmetric(
              horizontal: compact
                  ? AppSpacing.frameGutterCompact
                  : AppSpacing.frameGutter),
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.s5 : AppSpacing.s16,
            compact ? AppSpacing.s8 : AppSpacing.s12 + AppSpacing.s2,
            compact ? AppSpacing.s5 : AppSpacing.s16,
            compact ? AppSpacing.s8 : AppSpacing.s16,
          ),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.mdR,
            boxShadow: AppShadows.s2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── masthead, closed by the strong rule ──────────────────
              Container(
                padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                decoration: BoxDecoration(
                  border: Border(
                      bottom: BorderSide(color: t.borderStrong)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: KitVersal(title)),
                    if (marker != null && marker!.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.s3),
                      Flexible(
                        child: Text(
                          marker!.toUpperCase(),
                          textAlign: TextAlign.end,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: KitText.capsLabel(context,
                              fontSize: 11, letterSpacing: 0.1),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              if (standfirst != null && standfirst!.isNotEmpty) ...[
                Lede(standfirst!, maxWidth: double.infinity),
                const SizedBox(height: AppSpacing.s8 - 4),
              ],
              ...children,
              // ── seal footer ─────────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.s8),
                padding: const EdgeInsets.only(top: AppSpacing.s6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_sealMark, size: 22, color: t.seal),
                    const SizedBox(width: AppSpacing.s2 + 2),
                    Expanded(
                      child: Text(sealText,
                          style: KitText.lede(context,
                              fontSize: 13, height: 19)),
                    ),
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

/// The masthead lockup: uppercase serif with the opening capital of each word
/// raised. `A Letter.` sets as `A LETTER.` with the A and the L a fifth larger
/// — the versal the app and the sent letter share.
///
/// **Which letters rise is not a detail.** The sent letter raised the O and the
/// L for a whole release, so every letter read `NOteLETTER` (4.50.1).
class KitVersal extends StatelessWidget {
  final String text;
  final double fontSize;

  const KitVersal(this.text, {super.key, this.fontSize = 36});

  @override
  Widget build(BuildContext context) {
    final base = AppTheme.serif(
      fontSize: fontSize,
      height: 1,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.08 * fontSize,
      color: Tokens.of(context).fg,
    );
    final spans = <TextSpan>[];
    var atWordStart = true;
    for (final ch in text.toUpperCase().split('')) {
      final isLetter = RegExp(r'[A-Z]').hasMatch(ch);
      spans.add(TextSpan(
        text: ch,
        style: (atWordStart && isLetter)
            ? base.copyWith(fontSize: fontSize * 1.2, fontWeight: FontWeight.w600)
            : null,
      ));
      if (isLetter) atWordStart = false;
      if (ch == ' ') atWordStart = true;
    }
    return Text.rich(TextSpan(style: base, children: spans),
        maxLines: 2, overflow: TextOverflow.ellipsis);
  }
}

/// A frame-less letter body, rendered inside [KitLetterSheet].
///
/// Themed, unlike [KitLetterPaper]: this body carries no colours of its own —
/// it is the card list a pre-4.50.0 build wrote — so it takes the app's, and
/// flips with the theme like the sheet around it.
class KitLetterBody extends StatelessWidget {
  final String html;

  const KitLetterBody(this.html, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Html(
      data: html,
      style: {
        ...AppTheme.htmlStyles(t),
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontFamily: AppTheme.fontSerif,
          fontSize: FontSize(17),
          lineHeight: LineHeight(28 / 17),
          color: t.fg,
        ),
        // §11 — marked text in a letter is a SOLID fill, stronger than the
        // reader's `--highlight` wash, deliberately. Both halves are frozen
        // steps because the pair has to hold in both themes, and the letter's
        // own mark is this exact pair.
        'mark': Style(
          // literal-ok: --brick-500, §11's letter mark fill
          backgroundColor: const Color(0xFF9D352D),
          // literal-ok: --paper-50, the label on that fill
          color: const Color(0xFFFAFAF7),
        ),
        'blockquote': Style(
          margin: Margins.only(left: 0, bottom: 12),
          padding: HtmlPaddings.only(left: 14),
          border: Border(left: BorderSide(color: t.accent, width: 2)),
        ),
        'a': Style(color: t.link),
        'img': Style(width: Width(100, Unit.percent)),
      },
    );
  }
}

/// A paragraph of the letter's body — serif 17/28, the reading size the sheet
/// sets. `child` rather than a string so a passage can carry marked text and
/// §17 markers.
class KitLetterProse extends StatelessWidget {
  final Widget child;

  const KitLetterProse({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s3),
        child: DefaultTextStyle(
          style: AppTheme.serif(
            fontSize: 17,
            height: 28 / 17,
            color: Tokens.of(context).fg,
          ),
          child: child,
        ),
      );
}

/// The line under a passage — its source, or the count it is part of.
class KitLetterAttribution extends StatelessWidget {
  final String text;

  const KitLetterAttribution(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s8 - 4),
        child: Text(text,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 12,
              color: Tokens.of(context).fgMuted,
            )),
      );
}

/// The mark in the seal. The same glyph the chrome rail sets as the brand
/// (`sidebar.dart`), so the seal on the letter and the mark on the app are one
/// thing rather than two that drift.
const IconData _sealMark = Icons.edit_note;
