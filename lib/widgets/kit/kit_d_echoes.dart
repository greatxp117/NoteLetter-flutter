import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_covers.dart';
import 'kit_d_parts.dart';
import 'kit_markers.dart';
import 'kit_source_link.dart';
import 'kit_text.dart';

// ── §43 · Echo pair (5.83.0, ADR-255; screens/reader.md §Echoes) ────────────
//
// The source page's *Echoes*: a standfirst, then a ruled list of pairs — this
// source's passage (a button: it takes the column to the passage in the
// Manuscript), then the passages elsewhere that echo it (links: each opens the
// reader at that passage). Two voices, kept apart: this source's line is quiet
// and leads back into the Manuscript, the echo is the reading serif and leads
// away. Web `pages/reader/EchoesPanel.jsx` and the `.ec-*` block in
// `styles/app-source.css`; the metrics below are that block's.
//
// No figure: the pair's cosine is not drawn. It is a measurement of the
// embedder, not of anything a reader decides by.

/// `.ec-stand` — the standfirst above the list: serif italic 17/26
/// `--fg-lede` (16/24 on a phone), at most 60ch, 22 above the list.
class KitEchoStandfirst extends StatelessWidget {
  final String text;
  const KitEchoStandfirst(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final phone = KitD.phone(context);
    final style = KitText.lede(
      context,
      fontSize: phone ? 16 : 17,
      height: phone ? 24 : 26,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 60 * KitText.ch(context, style)),
        child: Text(text, style: style),
      ),
    );
  }
}

/// `.ec-note` — the panel note's voice (serif italic 15/23 `--fg-lede`, at
/// most 64ch), 18 above it; flush under the standfirst, which already
/// leaves its 22 (`.ec-stand + .ec-note`).
class KitEchoNote extends StatelessWidget {
  final String text;
  final bool afterStandfirst;
  const KitEchoNote(this.text, {super.key, this.afterStandfirst = false});

  @override
  Widget build(BuildContext context) {
    final style = KitText.lede(context, fontSize: 15, height: 23, opsz: 18);
    return Padding(
      padding: EdgeInsets.fromLTRB(2, afterStandfirst ? 0 : 18, 2, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 64 * KitText.ch(context, style)),
        child: Text(text, style: style),
      ),
    );
  }
}

/// `.ec-list` — a `--rule` above the first pair and between pairs, none
/// under the last, as History's list.
class KitEchoList extends StatelessWidget {
  final List<Widget> pairs;
  const KitEchoList({super.key, required this.pairs});

  @override
  Widget build(BuildContext context) {
    final rule = Tokens.of(context).rule;
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: rule))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < pairs.length; i++)
            i == pairs.length - 1
                ? pairs[i]
                : DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: rule)),
                    ),
                    child: pairs[i],
                  ),
        ],
      ),
    );
  }
}

/// One echo under a passage head: where it opens (the reader at [docId],
/// with [query] — `p={chunkId}&from=…`), what it says, and its source.
class KitEcho {
  final String docId;
  final String chunkId;
  final String? query;
  final String excerpt;

  /// The source's stored `type`, drawn as §6.4.1's word (the cover's).
  final String type;

  /// The source's title; null or empty is *Untitled*.
  final String? title;

  /// The in-app open. Null pushes the reader route, as [KitSourceLink] does.
  final VoidCallback? onOpen;

  const KitEcho({
    required this.docId,
    required this.chunkId,
    required this.excerpt,
    required this.type,
    this.query,
    this.title,
    this.onOpen,
  });
}

/// §43 — **Echo pair**: this source's passage, then the passage or passages
/// in other sources that echo it.
///
/// `.ec-pair` is a column, gap 10, padding `22px 2px` (the rules are the
/// list's). The **head** is a button — `¶ {chunkIndex + 1}` in mono 11
/// `--fg-subtle`, then the excerpt in serif italic 15/23 `--fg-muted`, two
/// lines at most, `--fg` on hover — that brings the passage into view in the
/// Manuscript and flashes it ([onShowPassage]). It never navigates. Its
/// **echoes** sit under the head's text (38 in on a desk, flush on a phone),
/// each a link in the §36 hover block.
class KitEchoPair extends StatelessWidget {
  final int chunkIndex;
  final String excerpt;
  final VoidCallback onShowPassage;
  final List<KitEcho> echoes;

  const KitEchoPair({
    super.key,
    required this.chunkIndex,
    required this.excerpt,
    required this.onShowPassage,
    required this.echoes,
  });

  @override
  Widget build(BuildContext context) {
    final phone = KitD.phone(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EchoHead(
            n: chunkIndex + 1,
            excerpt: excerpt,
            onTap: onShowPassage,
          ),
          const SizedBox(height: 10),
          // `.ec-echoes` — gap 4, indented under the head's text: the
          // numeral's 26 and the head's 12.
          Padding(
            padding: EdgeInsets.only(left: phone ? 0 : 38),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < echoes.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  _EchoLink(echoes[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `.ec-here` — this source's passage, a reset button with baseline gap 12;
/// keyboard focus draws a 2px `--accent` outline 4 out.
class _EchoHead extends StatelessWidget {
  final int n;
  final String excerpt;
  final VoidCallback onTap;
  const _EchoHead({required this.n, required this.excerpt, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      onTap: onTap,
      label: 'Show passage $n in the manuscript',
      builder: (context, hover, focus) {
        final text = AppTheme.serif(
          fontSize: 15,
          height: 23 / 15,
          fontStyle: FontStyle.italic,
          color: hover ? t.fg : t.fgMuted,
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (focus)
              Positioned(
                left: -4,
                right: -4,
                top: -4,
                bottom: -4,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.xsR,
                      border: Border.all(color: t.accent, width: 2),
                    ),
                  ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 26),
                  child: Text(
                    '¶ $n',
                    style: AppTheme.mono(
                      fontSize: 11,
                      letterSpacing: 0.08 * 11,
                      color: t.fgSubtle,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 60 * KitText.ch(context, text),
                    ),
                    child: KitMarkedText(
                      excerpt,
                      style: text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// `.ec-echo` — a link, a column with gap 8 and padding `10px 0`: the quote
/// in the reading serif 18/28 `--fg` (17/26 on a phone), at most 60ch, then
/// the source line — the kind in mono 10.5/`0.14em` caps `--accent-text`,
/// the title in sans 14 `--fg` on one line, and the 13px arrow in
/// `--fg-subtle` that steps 2 right to `--fg` on hover.
class _EchoLink extends StatelessWidget {
  final KitEcho echo;
  const _EchoLink(this.echo);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    final quote = AppTheme.serif(
      fontSize: phone ? 17 : 18,
      height: (phone ? 26 : 28) / (phone ? 17 : 18),
      color: t.fg,
      opsz: 18,
    );
    final title = (echo.title ?? '').isEmpty ? 'Untitled' : echo.title!;
    return KitSourceLink(
      docId: echo.docId,
      query: echo.query,
      onOpen: echo.onOpen,
      builder: (context, open) => KitRowHover(
        onTap: open,
        builder: (context, hover) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 60 * KitText.ch(context, quote),
                ),
                child: KitMarkedText(echo.excerpt, style: quote),
              ),
              const SizedBox(height: 8),
              // `.ec-src` aligns on the baseline; the arrow has none and
              // is centred on the line (`.ec-go { align-self: center }`).
              Row(
                children: [
                  Flexible(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          kitTypeLabel(echo.type).toUpperCase(),
                          style: AppTheme.mono(
                            fontSize: 10.5,
                            letterSpacing: 0.14 * 10.5,
                            color: t.accentText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontSans,
                              fontSize: 14,
                              color: t.fg,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedSlide(
                    offset: Offset(hover ? 2 / 13 : 0, 0),
                    duration: KitD.dur(context, AppMotion.durFast),
                    curve: AppMotion.easeOut,
                    child: Icon(
                      Icons.arrow_forward,
                      size: 13,
                      color: hover ? t.fg : t.fgSubtle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
