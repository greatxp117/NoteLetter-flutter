// Home's own D parts (screens/library.md §Composition; web
// `pages/LibraryHome.jsx` + `styles/app-home.css`): the letter as it is sent,
// the desk ledger, Earlier letters, Recently added, and Your first sources. A
// page file never styles its own type or spacing (ADR-041), so a part only
// Home draws still lives in the kit. Metrics are the spec's Reference metrics
// (web's numbers) and this client's starting values.

import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitButton;
import 'kit_d_covers.dart' show KitCoverStrip;
import 'kit_d_format.dart';
import 'kit_d_letter.dart';
import 'kit_d_library.dart' show KitDropCard;
import 'kit_d_parts.dart';
import 'kit_d_shelves.dart';
import 'kit_failure.dart' show KitFailureInline;
import 'kit_shell.dart' show KitGlyph, KitQuill, KitUploadGlyph;
import 'kit_source_link.dart';

// ── Small D type every listing uses ─────────────────────────────────────────

/// `.hx-link` — D's quiet text action: sans 13/1.3 in `--fg-muted`, underlined
/// in `--link-decor`; hover `--fg` and a 2px underline; a 2px accent focus
/// ring. An optional leading glyph, 6 before the label.
class KitHxLink extends StatelessWidget {
  final String label;
  final IconData? icon;
  final double iconSize;

  /// Null holds the link (`--held-opacity`, no press): a write it starts is
  /// in flight.
  final VoidCallback? onTap;

  const KitHxLink(
    this.label, {
    super.key,
    this.icon,
    this.iconSize = 13,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: onTap == null ? AppSpacing.heldOpacity : 1,
      child: KitDTap(
        label: label,
        enabled: onTap != null,
        onTap: onTap,
        builder: (context, hover, focus) {
          final fg = hover ? t.fg : t.fgMuted;
          final text = Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 13,
              height: 1.3,
              color: fg,
              decoration: TextDecoration.underline,
              decorationColor: t.linkDecor,
              decorationThickness: hover ? 2 : 1,
            ),
          );
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              border: focus ? Border.all(color: t.accent, width: 2) : null,
            ),
            // `white-space: nowrap`, ellipsis only where the row is bounded:
            // a Flexible in an unbounded row (a section head's actions)
            // throws.
            child: LayoutBuilder(
              builder: (context, c) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    KitGlyph(icon!, size: iconSize, color: fg),
                    const SizedBox(width: 6),
                  ],
                  if (c.maxWidth.isFinite) Flexible(child: text) else text,
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.hx-none` — a listing's own quiet sentence: serif italic 16 `--fg-lede`,
/// [top] and [bottom] around it (the Library's `.lx-none`: 24 each), and an
/// optional [link] after it (*No volumes match.* · *Show every volume*).
class KitDNone extends StatelessWidget {
  final String text;
  final Widget? link;
  final double top;
  final double bottom;

  const KitDNone(
    this.text, {
    super.key,
    this.link,
    this.top = 0,
    this.bottom = 0,
  });

  static TextStyle style(BuildContext context) => AppTheme.serif(
    fontSize: 16,
    height: 1.4,
    fontStyle: FontStyle.italic,
    color: Tokens.of(context).fgLede,
  );

  @override
  Widget build(BuildContext context) {
    final line = link == null
        ? Text(text, style: style(context))
        : Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [Text(text, style: style(context)), link!],
          );
    if (top == 0 && bottom == 0) return line;
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: line,
    );
  }
}

/// `.hx-check` — the setup checklist's slot at the head of Home's column: 36
/// under it. The host draws this only while the strip is drawn, so a hidden,
/// dismissed or complete checklist takes no room.
class KitHomeCheckSlot extends StatelessWidget {
  final Widget child;
  const KitHomeCheckSlot({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(bottom: 36), child: child);
}

/// `ed-lower` — Recently added beside Earlier letters, 72 below the letter:
/// `minmax(0,1fr) minmax(320px,400px)` with a 44 gap, one column (48 apart)
/// in a column 1180 or narrower.
class KitHomeLower extends StatelessWidget {
  final Widget recent;
  final Widget? earlier;

  const KitHomeLower({super.key, required this.recent, this.earlier});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 72),
    child: LayoutBuilder(
      builder: (context, c) {
        if (earlier == null) return recent;
        if (c.maxWidth <= 1180) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [recent, const SizedBox(height: 48), earlier!],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: recent),
            const SizedBox(width: 44),
            SizedBox(width: 400, child: earlier),
          ],
        );
      },
    ),
  );
}

// ── The letter, as it is sent ───────────────────────────────────────────────

/// The next letter's phrase (`Today, 8:00 AM`, `Monday, 8:00 AM`) inside a
/// sentence: only a leading *Today* / *Tomorrow* is lower-cased there; a
/// weekday's name and the clock's AM/PM keep their case (web `lower`,
/// f1e6ed3). D's first port lower-cased the WHOLE phrase in two decks, so
/// they read "…arrives monday, 8:00 am".
@visibleForTesting
String kitNextInSentence(String s) => s.replaceFirstMapped(
  RegExp(r'^(Today|Tomorrow)\b'),
  (m) => m[1]!.toLowerCase(),
);

/// Home's letter as it is sent (web `EditionLetter`): a paper card under its
/// **letterhead** — the seal disc and feather, the wordmark *NoteLetter* with
/// its initials raised, a mono caps meta line (`Vol. I · No. 253 · This
/// morning · Three passages · 4 min read`, each part only when the record
/// says it) over a 2px `--fg` rule — then, by state: refused (§14.2 and *Go
/// to Letters*), in flight (a skeleton headline, busy), none built (what
/// starts the first letter, and *Letter settings*), or built (the headline,
/// the lede, the first three passages read from the letterheaded body as
/// TEXT, *Read the letter* and the ghost *Next letter …* / *Letter settings*).
class KitEditionLetter extends StatelessWidget {
  final KitLetterRead read;
  final KitLetterParts? parts;
  final KitLetterSchedule? sched;
  final KitLibState libState;

  /// *Read the letter* / *Go to Letters* — opens Letters.
  final VoidCallback onLetters;

  /// The ghost *Letter settings* / *Next letter …* — the §28 panel, or Letter
  /// settings where the page has none.
  final VoidCallback onSettings;
  final DateTime? now;

  const KitEditionLetter({
    super.key,
    required this.read,
    required this.parts,
    required this.sched,
    required this.libState,
    required this.onLetters,
    required this.onSettings,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
        // `@container hx (max-width:600px)`: the phone's card.
        final narrow = w <= 600;
        final padH = narrow ? 18.0 : (0.04 * w).clamp(22.0, 52.0);
        // The card's 1px edge on each side is inside its width.
        final inner = math.max(0.0, w - 2 * padH - 2);
        return Semantics(
          container: true,
          child: Container(
            key: const ValueKey('ed-letter'),
            padding: narrow
                ? const EdgeInsets.fromLTRB(18, 24, 18, 22)
                : EdgeInsets.symmetric(horizontal: padH, vertical: 30),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.border),
              borderRadius: narrow ? AppRadius.lgR : AppRadius.xlR,
              boxShadow: AppShadows.s2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _body(context, inner),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _body(BuildContext context, double inner) {
    final p = parts;
    final when = p == null
        ? null
        : (kitIsToday(p.at, now) ? 'This morning' : kitLongDay(p.at ?? 0));
    List<Widget> head([String? right]) => [
      _Letterhead(
        meta: [
          if (p?.vol != null) 'Vol. ${p!.vol}',
          if (p?.no != null) 'No. ${p!.no}',
          ?when,
          ?right,
        ].join(' · '),
      ),
    ];
    final ghost = sched?.next;

    if (read.error != null) {
      return [
        ...head(),
        _Headline('The letter could not be read', inner: inner),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Center(child: KitFailureInline(read.error!)),
        ),
        _Actions([KitButton.ghost('Go to Letters', onPressed: onLetters)]),
      ];
    }
    if (!read.answered) {
      return [
        ...head(),
        const KitSkeletonLines(
          center: true,
          lines: [KitSkelLine(0.5, true), KitSkelLine(0.7)],
        ),
      ];
    }
    if (p == null) {
      // An empty library has nothing to write from yet: the letter says what
      // starts it. With delivery OFF it promises no letter; with the library
      // unread or refused it says only that no letter has been built.
      final first = libState == KitLibState.empty;
      final off = sched != null && sched!.on == false;
      final known =
          libState == KitLibState.empty ||
          libState == KitLibState.reading ||
          libState == KitLibState.ready;
      final next = sched?.next;
      String? deck;
      if (off) {
        deck =
            'Scheduled delivery is off. Turn it on in Letter settings and '
            'the first letter follows its schedule.';
      } else if (first) {
        deck =
            'Add a source, and the first letter arrives '
            '${next != null ? kitNextInSentence(next) : 'the next morning'}, drawn '
            'from whatever is indexed by then.';
      } else if (libState == KitLibState.reading) {
        deck =
            'Your library is being read. ${next != null ? 'The first '
                      'letter arrives ${kitNextInSentence(next)}, drawn from what’s '
                      'indexed by then.' : 'Tomorrow’s letter will draw from '
                      'what’s indexed so far.'}';
      } else if (libState == KitLibState.ready && next != null) {
        deck =
            'The first letter arrives ${kitNextInSentence(next)}, drawn from '
            'what’s indexed by then.';
      }
      return [
        ...head(),
        _Headline(
          !known
              ? 'No letter has been built yet'
              : first
              ? 'Your first letter is waiting on your library'
              : 'Your first letter is being written',
          inner: inner,
        ),
        if (deck != null) _Deck(deck),
        _Actions([
          KitButton.ghost(
            'Letter settings',
            icon: Icons.schedule,
            onPressed: onSettings,
          ),
        ]),
      ];
    }
    // From `chunk_ids`: unmeasured, and so NO figure — never 0 — when the
    // record carries none (ADR-109; the Letters card's own arithmetic).
    final n = p.count;
    return [
      ...head(
        n == null
            ? null
            : '${kitCap(kitSay(n))} ${n == 1 ? 'passage' : 'passages'} · '
                  '${kitMinutes(n)} min read',
      ),
      _Headline(p.title, inner: inner),
      if (p.lede.isNotEmpty) _Deck(p.lede),
      if (p.sections.isNotEmpty)
        _Passages(sections: p.sections.take(3).toList()),
      _Actions([
        KitButton.secondary(
          'Read the letter',
          icon: Icons.mail_outline,
          onPressed: onLetters,
        ),
        KitButton.ghost(
          ghost != null
              ? 'Next letter ${kitNextInSentence(ghost)}'
              : 'Letter settings',
          icon: Icons.schedule,
          onPressed: onSettings,
        ),
      ]),
    ];
  }
}

/// `.ed-lh` — centred, 9 apart, 26 under, 22 above a 2px `--fg` rule.
class _Letterhead extends StatelessWidget {
  final String meta;
  const _Letterhead({required this.meta});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final wm = AppTheme.serif(
      fontSize: 15,
      height: 1,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.12 * 15,
      color: t.fg,
      opsz: 24,
    );
    final big = wm.copyWith(fontSize: 15 * 1.24, letterSpacing: 0.12 * 15);
    return Container(
      margin: const EdgeInsets.only(bottom: 26),
      padding: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.fg, width: 2)),
      ),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 42,
              height: 42,
              margin: const EdgeInsets.only(bottom: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.accentSoft,
                shape: BoxShape.circle,
              ),
              child: KitQuill(size: 19, color: t.seal),
            ),
          ),
          const SizedBox(height: 9),
          Semantics(
            label: 'NoteLetter',
            excludeSemantics: true,
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'N', style: big),
                  TextSpan(text: 'OTE', style: wm),
                  TextSpan(text: 'L', style: big),
                  TextSpan(text: 'ETTER', style: wm),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              meta.toUpperCase(),
              textAlign: TextAlign.center,
              style: AppTheme.mono(
                fontSize: 10.5,
                height: 16 / 10.5,
                letterSpacing: 0.18 * 10.5,
                color: t.fgMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.ed-head` in the paper — serif 600 `clamp(36px, 5cqi, 62px)`/1.02,
/// `-0.026em`, letterpressed, centred, at most about 22 characters wide.
class _Headline extends StatelessWidget {
  final String text;
  final double inner;
  const _Headline(this.text, {required this.inner});

  @override
  Widget build(BuildContext context) {
    final size = (0.05 * inner).clamp(36.0, 62.0);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 22 * size * 0.5),
        child: Semantics(
          header: true,
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: AppTheme.serif(
              fontSize: size,
              height: 1.02,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.026 * size,
              color: Tokens.of(context).fg,
              opsz: 60,
            ).copyWith(shadows: AppShadows.letterpress),
          ),
        ),
      ),
    );
  }
}

/// `.ed-deck` in the paper — serif italic 20/31 `--fg-lede`, centred, at most
/// about 62 characters wide, 12 below the headline.
class _Deck extends StatelessWidget {
  final String text;
  const _Deck(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 62 * 20 * 0.48),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppTheme.serif(
            fontSize: 20,
            height: 31 / 20,
            fontStyle: FontStyle.italic,
            color: Tokens.of(context).fgLede,
            opsz: 22,
          ),
        ),
      ),
    ),
  );
}

/// `.ed-letter-acts` in the paper — centred, wrapping 10 apart, 26 below over
/// 20 under a 1px `--rule`.
class _Actions extends StatelessWidget {
  final List<Widget> children;
  const _Actions(this.children);

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 26),
    padding: const EdgeInsets.only(top: 20),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Tokens.of(context).rule)),
    ),
    child: Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: children,
    ),
  );
}

/// `.ed-cols` — the first three passages, 32 below under a 1px `--fg` rule: a
/// three-column grid (cells `22 28 4`, a 1px `--border` between) over 900 of
/// letter; one column with the meta beside the text over 560; stacked under.
class _Passages extends StatelessWidget {
  final List<KitLetterSection> sections;
  const _Passages({required this.sections});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget stacked(int i) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PassageMeta(sections[i]),
        ),
        _PassageBody(section: sections[i], first: i == 0),
      ],
    );
    final body = LayoutBuilder(
      builder: (context, c) {
        final inner = c.maxWidth;
        if (inner > 900) {
          // Three columns, a 1px `--border` between them running the row's
          // full height (drawn over the row: no cell needs an intrinsic).
          final cw = inner / 3;
          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++)
                    SizedBox(
                      width: cw,
                      child: i >= sections.length
                          ? const SizedBox.shrink()
                          : Padding(
                              padding: EdgeInsets.fromLTRB(
                                i == 0 ? 0 : 29,
                                22,
                                i == 2 ? 0 : 28,
                                4,
                              ),
                              child: stacked(i),
                            ),
                    ),
                ],
              ),
              for (var i = 1; i < math.min(3, sections.length); i++)
                Positioned(
                  left: cw * i,
                  top: 0,
                  bottom: 0,
                  child: SizedBox(width: 1, child: ColoredBox(color: t.border)),
                ),
            ],
          );
        }
        final beside = inner > 560;
        // `minmax(120px, .3fr) minmax(0, 1fr)`, 28 apart.
        final metaW = math.max(120.0, 0.3 / 1.3 * (inner - 28));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < sections.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22),
                decoration: i == 0
                    ? null
                    : BoxDecoration(
                        border: Border(top: BorderSide(color: t.rule)),
                      ),
                child: beside
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: metaW,
                            child: _PassageMeta(sections[i]),
                          ),
                          const SizedBox(width: 28),
                          Expanded(
                            child: _PassageBody(
                              section: sections[i],
                              first: i == 0,
                            ),
                          ),
                        ],
                      )
                    : stacked(i),
              ),
          ],
        );
      },
    );
    return Container(
      key: const ValueKey('ed-cols'),
      margin: const EdgeInsets.only(top: 32),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.fg)),
      ),
      child: body,
    );
  }
}

/// `.ed-p-meta` — a mono `§ 01` in `--accent-text` over the passage's title.
class _PassageMeta extends StatelessWidget {
  final KitLetterSection section;
  const _PassageMeta(this.section);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '§ ${section.n.toString().padLeft(2, '0')}',
          style: AppTheme.mono(
            fontSize: 11,
            letterSpacing: 0.14 * 11,
            color: t.accentText,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          header: true,
          child: Text(
            section.title,
            style: AppTheme.serif(
              fontSize: 21,
              height: 1.2,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.01 * 21,
              color: t.fg,
              opsz: 24,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.ed-p-body` — the excerpt (serif 17/28; the first passage opens on a drop
/// cap, 63/51 600 `--accent`) and its source, a link to the reader when the
/// card names a document.
class _PassageBody extends StatelessWidget {
  final KitLetterSection section;
  final bool first;
  const _PassageBody({required this.section, required this.first});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = AppTheme.serif(
      fontSize: 17,
      height: 28 / 17,
      color: t.fg,
      opsz: 18,
    );
    final src = section.source;
    Widget source(bool hover) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              src!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.serif(
                fontSize: 14,
                height: 18 / 14,
                fontStyle: FontStyle.italic,
                color: t.fgMuted,
              ),
            ),
          ),
          if (section.docId != null) ...[
            const SizedBox(width: 6),
            AnimatedSlide(
              offset: Offset(hover ? 2 / 12 : 0, 0),
              duration: KitD.dur(context, AppMotion.durFast),
              curve: AppMotion.easeOut,
              child: Icon(Icons.arrow_forward, size: 12, color: t.fgMuted),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        first
            ? _DropCapText(section.text, style: style)
            : Text(section.text, style: style),
        if (src != null)
          section.docId != null
              ? KitSourceLink(
                  docId: section.docId!,
                  builder: (context, open) => KitDTap(
                    label: src,
                    onTap: open,
                    builder: (context, hover, focus) => source(hover),
                  ),
                )
              : source(false),
      ],
    );
  }
}

/// A paragraph whose first letter is a drop cap two lines deep (CSS
/// `::first-letter{float:left; margin:5px 9px 0 0; font-size:63px;
/// line-height:51px}`): the text beside the cap is the first two lines laid
/// out at the narrower width, the rest runs under at full [width]. Leading
/// punctuation goes with the letter, as `::first-letter` takes it.
class _DropCapText extends StatelessWidget {
  final String text;
  final TextStyle style;
  const _DropCapText(this.text, {required this.style});

  static final RegExp _punct = RegExp('[“”‘’"\'(\\[«]');

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    var i = 0;
    while (i < text.length - 1 && _punct.hasMatch(text[i])) {
      i++;
    }
    final first = text.substring(0, i + 1);
    final rest = text.substring(i + 1);
    // Measured as the Text widgets draw: over the ambient default style.
    final base = DefaultTextStyle.of(context).style;
    final body = base.merge(style);
    final cap = base.merge(
      AppTheme.serif(
        fontSize: 63,
        height: 51 / 63,
        fontWeight: FontWeight.w600,
        color: t.accent,
        opsz: 60,
      ).copyWith(leadingDistribution: TextLeadingDistribution.even),
    );
    return LayoutBuilder(
      builder: (context, c) {
        final capTp = TextPainter(
          text: TextSpan(text: first, style: cap),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final capW = capTp.width.ceilToDouble();
        capTp.dispose();
        final avail = c.maxWidth - capW - 9;
        if (!c.maxWidth.isFinite || avail < 48) {
          return Text(text, style: style);
        }
        // The text beside the cap is measured and drawn at the SAME width,
        // so the split falls exactly at the end of its second line.
        final tp = TextPainter(
          text: TextSpan(text: rest, style: body),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout(maxWidth: avail);
        final lines = tp.computeLineMetrics();
        var beside = rest;
        var below = '';
        if (lines.length > 2) {
          final y = lines[0].height + lines[1].height / 2;
          final pos = tp.getPositionForOffset(Offset(avail - 1, y));
          final end = tp.getLineBoundary(pos).end;
          beside = rest.substring(0, end).trimRight();
          below = rest.substring(end).trimLeft();
        }
        tp.dispose();
        return Semantics(
          label: text,
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: capW + 9,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(first, style: cap, softWrap: false),
                    ),
                  ),
                  SizedBox(
                    width: avail,
                    child: Text(beside, style: style),
                  ),
                ],
              ),
              if (below.isNotEmpty) Text(below, style: style),
            ],
          ),
        );
      },
    );
  }
}

// ── The desk ledger (the sheet's figures) ───────────────────────────────────

/// The review inbox's parts in words (web `reviewParts`): *{n} source
/// couldn’t be read*, *{n} import held*, *{n} filing suggestion*, *{n} change
/// to approve* — each only when it has any.
List<String> kitReviewParts({
  required int sources,
  required int holds,
  required int suggestions,
  required int proposals,
}) {
  final out = <String>[];
  void add(int n, String one, String many) {
    if (n != 0) out.add('$n ${n == 1 ? one : many}');
  }

  add(sources, 'source couldn’t be read', 'sources couldn’t be read');
  add(holds, 'import held', 'imports held');
  add(suggestions, 'filing suggestion', 'filing suggestions');
  add(proposals, 'change to approve', 'changes to approve');
  return out;
}

/// One thing waiting on the reader: a numeral ([n] null is unmeasured — the
/// dash), a serif line, an optional sans sub-line, the volumes being read
/// ([reading]), and where it opens.
class KitLedgerRow {
  final String id;
  final String? n;
  final String line;
  final String? sub;
  final List<Document> reading;
  final VoidCallback onTap;

  const KitLedgerRow({
    required this.id,
    required this.n,
    required this.line,
    required this.onTap,
    this.sub,
    this.reading = const [],
  });
}

/// The desk ledger under *On your desk* (web `Ledger`): one row per thing
/// waiting — each a button (a large italic numeral in `--accent-text`, a serif
/// line, an optional sans sub-line, a chevron nudging 2px on hover) — or, when
/// [quiet], *Nothing is waiting on you. The library is quiet.* The host says
/// quiet only when every read behind the ledger ANSWERED with nothing.
class KitDeskLedger extends StatelessWidget {
  final List<KitLedgerRow> rows;
  final bool quiet;

  const KitDeskLedger({super.key, required this.rows, this.quiet = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.fg)),
            ),
            child: Semantics(
              header: true,
              child: Text(
                'ON YOUR DESK',
                style: AppTheme.mono(
                  fontSize: 11,
                  height: 14 / 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.16 * 11,
                  color: t.fg,
                ),
              ),
            ),
          ),
          if (quiet)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                'Nothing is waiting on you. The library is quiet.',
                style: AppTheme.serif(
                  fontSize: 15,
                  fontStyle: FontStyle.italic,
                  color: t.fgLede,
                ),
              ),
            ),
          for (final r in rows) _LedgerRowView(r),
        ],
      ),
    );
  }
}

class _LedgerRowView extends StatelessWidget {
  final KitLedgerRow row;
  const _LedgerRowView(this.row);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final r = row;
    return KitRowHover(
      key: ValueKey('ledger-${r.id}'),
      onTap: r.onTap,
      reach: 12,
      label: [r.n ?? '—', r.line, ?r.sub].join(' '),
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 16, 6, 16),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 58,
              child: Text(
                r.n ?? '—',
                textAlign: TextAlign.right,
                maxLines: 1,
                style: AppTheme.serif(
                  fontSize: 46,
                  height: 0.9,
                  fontWeight: FontWeight.w500,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -0.02 * 46,
                  color: t.accentText,
                  opsz: 60,
                ).copyWith(fontFeatures: const [FontFeature.liningFigures()]),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    r.line,
                    style: AppTheme.serif(
                      fontSize: 18,
                      height: 24 / 18,
                      fontWeight: FontWeight.w500,
                      color: t.fg,
                    ),
                  ),
                  if (r.sub != null && r.sub!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        r.sub!,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 12.5,
                          height: 18 / 12.5,
                          color: t.fgMuted,
                        ),
                      ),
                    ),
                  if (r.reading.isNotEmpty) _IncomingBars(r.reading),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Icon(Icons.chevron_right, size: 15, color: t.fgSubtle),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.hx-bars` — up to three volumes being read: the title, its stage (kit
/// §32's vocabulary), a bar that runs only while processing, then *and {n in
/// words} more in the queue*.
class _IncomingBars extends StatelessWidget {
  final List<Document> docs;
  const _IncomingBars(this.docs);

  static const int _max = 3;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < math.min(_max, docs.length); i++) ...[
            if (i > 0) const SizedBox(height: 9),
            Builder(
              builder: (context) {
                final d = docs[i];
                final st = kitStageOf(d) ?? (label: 'Being read', live: false);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            d.title.isEmpty ? 'Untitled' : d.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontSans,
                              fontSize: 12.5,
                              color: t.fgMuted,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          st.label,
                          style: AppTheme.mono(
                            fontSize: 10.5,
                            letterSpacing: 0.02 * 10.5,
                            color: t.fgSubtle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    _LedgerBar(live: st.live),
                  ],
                );
              },
            ),
          ],
          if (docs.length > _max)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text(
                'and ${kitSay(docs.length - _max)} more in the queue',
                style: AppTheme.serif(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: t.fgSubtle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// `.hx-bar` across the row: 3 tall on `--surface-sunken`; [live] slides a
/// 28% `--fg-muted` fill on a 1.8s `--ease-in-out` loop, still under reduced
/// motion. Not live, it is the empty track (`width: 0`).
class _LedgerBar extends StatefulWidget {
  final bool live;
  const _LedgerBar({required this.live});

  @override
  State<_LedgerBar> createState() => _LedgerBarState();
}

class _LedgerBarState extends State<_LedgerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_LedgerBar old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.live && !KitD.still(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 3,
        color: t.surfaceSunken,
        child: widget.live
            ? LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  return AnimatedBuilder(
                    animation: _c,
                    builder: (context, _) {
                      final p = AppMotion.easeInOut.transform(_c.value);
                      final x = (-1 + 4.6 * p) * w * 0.28;
                      return Transform.translate(
                        offset: Offset(x, 0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(width: w * 0.28, color: t.fgMuted),
                        ),
                      );
                    },
                  );
                },
              )
            : null,
      ),
    );
  }
}

// ── Earlier letters ─────────────────────────────────────────────────────────

/// One earlier letter: its No. (null draws the dash), its title, its date.
class KitEarlierLetter {
  final String id;
  final String? no;
  final String title;
  final String date;
  const KitEarlierLetter({
    required this.id,
    required this.no,
    required this.title,
    required this.date,
  });
}

/// *Earlier letters* (web `EarlierLetters`): a small SectionHead with *All
/// letters →*, then one row per letter — its No. in italic serif
/// `--accent-text`, its title, its date in mono — each opening Letters.
/// Nothing at all with no rows: the section claims nothing.
class KitEarlierLetters extends StatelessWidget {
  final List<KitEarlierLetter> rows;
  final VoidCallback onOpen;
  final VoidCallback onAll;

  const KitEarlierLetters({
    super.key,
    required this.rows,
    required this.onOpen,
    required this.onAll,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'Earlier letters',
          small: true,
          actions: [KitHxLink('All letters →', onTap: onAll)],
        ),
        for (final l in rows)
          KitRowHover(
            key: ValueKey('ed-past-${l.id}'),
            onTap: onOpen,
            label: '${l.no == null ? '' : 'No. ${l.no} '}${l.title} ${l.date}',
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: t.rule)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 46,
                    child: Text(
                      l.no ?? '—',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: AppTheme.serif(
                        fontSize: 24,
                        height: 1,
                        fontStyle: FontStyle.italic,
                        color: t.accentText,
                        opsz: 36,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l.title,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(fontSize: 17, color: t.fg),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    l.date,
                    style: AppTheme.mono(
                      fontSize: 11,
                      letterSpacing: 0.03 * 11,
                      color: t.fgSubtle,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Recently added ──────────────────────────────────────────────────────────

/// *Recently added* (web `Register`): a small SectionHead — meta `{N} volumes`,
/// or `{N in words} being read` while nothing has finished, none while the
/// read is out or refused — with *The whole library →* and the List / Grid
/// toggle; then the six newest complete volumes as register rows, or in
/// [grid] §33's cover strip of the twelve newest. Before anything finished,
/// the newest six arrivals as reading rows, or *Nothing has finished reading
/// yet.* Loading: skeleton lines. Refused: §14.2.
class KitRecentlyAdded extends StatelessWidget {
  final KitShelfModel model;

  /// Documents `queued` or `processing`, newest first.
  final List<Document> incoming;
  final bool loaded;
  final String? libError;
  final bool grid;
  final Widget? toggle;
  final VoidCallback onWholeLibrary;

  const KitRecentlyAdded({
    super.key,
    required this.model,
    required this.incoming,
    required this.loaded,
    required this.libError,
    required this.grid,
    required this.onWholeLibrary,
    this.toggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final items = model.complete.take(6).toList();
    final reading = items.isNotEmpty
        ? const <Document>[]
        : incoming.take(6).toList();
    final String? meta = !loaded || libError != null
        ? null
        : (items.isNotEmpty || reading.isEmpty)
        ? kitCounted(model.total, 'volume')
        : '${kitCap(kitSay(reading.length))} being read';
    ({String title, Color? color})? homeOf(Document d) {
      final n = model.homeOf[d.id];
      if (n == null) return null;
      return (
        title: n.title,
        color: AppColors.shelfColor(n.color, dark: t.isDark) ?? t.fgSubtle,
      );
    }

    Widget body;
    if (libError != null) {
      body = KitFailureInline('Your library could not be read — $libError');
    } else if (!loaded) {
      body = const KitSkeletonLines(
        lines: [KitSkelLine(0.7), KitSkelLine(0.6), KitSkelLine(0.7)],
      );
    } else if (items.isEmpty) {
      body = reading.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final v in reading) KitRegisterRow(doc: v)],
            )
          : const KitDNone('Nothing has finished reading yet.');
    } else if (grid) {
      body = KitCoverStrip(
        items: model.complete.take(12).toList(),
        homeOf: homeOf,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final v in items)
            Builder(
              builder: (context) {
                final h = homeOf(v);
                return KitRegisterRow(
                  doc: v,
                  shelfTitle: h?.title,
                  shelfColor: h?.color,
                );
              },
            ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitSectionHead(
          'Recently added',
          small: true,
          meta: meta,
          actions: [
            KitHxLink('The whole library →', onTap: onWholeLibrary),
            ?toggle,
          ],
        ),
        body,
      ],
    );
  }
}

// ── An empty library: the first sources ────────────────────────────────────

/// *Your first sources* (web `FirstSources`), an empty library only, 64 above
/// the letter: a small SectionHead (*Files, links, services*), the drop zone
/// card — a control named *Add files*, *Drop files to begin* / *or tap to
/// browse — …* (this client's touch copy, CLAUDE.md) — and under it *Paste a
/// link* and *Connect Google Drive, Dropbox or Notion*. The drop zone opens
/// Add a source already picking: one upload path, not a second.
class KitFirstSources extends StatelessWidget {
  final VoidCallback onAddFiles;
  final VoidCallback onPasteLink;
  final VoidCallback onConnect;

  const KitFirstSources({
    super.key,
    required this.onAddFiles,
    required this.onPasteLink,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const KitSectionHead(
            'Your first sources',
            small: true,
            meta: 'Files, links, services',
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            // The Library's own drop zone card (`.lx-dz.lx-dz-card`): one
            // part, two hosts.
            child: KitDropCard(
              key: const ValueKey('d-first-dz'),
              icon: KitUploadGlyph.icon,
              title: 'Drop files to begin',
              sub: 'or tap to browse — PDF, EPUB, Word, slides, Markdown, '
                  'images, audio, video',
              onTap: onAddFiles,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Wrap(
              spacing: 26,
              runSpacing: 10,
              children: [
                KitHxLink(
                  'Paste a link',
                  icon: Icons.link,
                  iconSize: 14,
                  onTap: onPasteLink,
                ),
                KitHxLink(
                  'Connect Google Drive, Dropbox or Notion',
                  icon: Icons.menu_book_outlined,
                  iconSize: 14,
                  onTap: onConnect,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

