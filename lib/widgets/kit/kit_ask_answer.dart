import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/ask_thread.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_d_frame.dart';
import 'kit_d_parts.dart';
import 'kit_failure.dart';
import 'kit_markers.dart';
import 'kit_text.dart';

// ── §25 Written answer (5.30.0, ADR-187) ────────────────────────────────────

/// §25 — the prose a turn's library message carries above its citations (web
/// `shared/AskAnswer.jsx`, `.ask-answer`). The blocks are drawn as stored: a
/// quotation is the cited passage's own characters, proven by the backend
/// before it was stored (INV-35), so nothing here re-derives, trims or
/// re-quotes it — the rule and the italic ARE the quotation marks.
///
/// - **Paragraph** — serif 17/28 at `--fg`, ≤64ch; each `[n]` is a
///   [KitAskRef], never a superscript and never the bracketed text.
/// - **Quote** — serif italic 17/28, set in 16 from a 2px `--accent` rule, its
///   text through §17.2 (it is `chunk.text`), then a sans 12 `--fg-muted` meta
///   line 6 under it: the marker and the cited source's title.
/// - **Note** — with no answer, `answer_note` as ONE italic sans 13/20 line in
///   `--fg-muted`, verbatim. Never §14: nothing failed that the reader can
///   retry, and the passages below are whole.
///
/// An unknown kind never reaches here ([askAnswer] drops it). A marker or a
/// quote whose `n` names no citation is impossible by INV-35 and, if one
/// arrives anyway, renders as nothing — never a chip that goes nowhere.
class KitAskAnswer extends StatelessWidget {
  final List<AskAnswerBlock>? answer;
  final String? note;
  final List<AskCitation> citations;

  /// A marker was activated: scroll to citation `n` and mark it (the host's).
  final ValueChanged<int>? onCite;

  const KitAskAnswer({
    super.key,
    required this.answer,
    this.note,
    required this.citations,
    this.onCite,
  });

  static final RegExp _marker = RegExp(r'\[(\d+)\]');

  AskCitation? _cite(int n) =>
      n >= 1 && n <= citations.length ? citations[n - 1] : null;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final blocks = answer;
    if (blocks == null || blocks.isEmpty) {
      final n = note;
      if (n == null || n.isEmpty) return const SizedBox.shrink();
      final style = TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 13,
        height: 20 / 13,
        fontStyle: FontStyle.italic,
        color: t.fgMuted,
      );
      return ConstrainedBox(
        key: const ValueKey('ask-answer-note'),
        constraints: BoxConstraints(maxWidth: 64 * KitText.ch(context, style)),
        child: Text(n, style: style),
      );
    }
    final prose = AppTheme.serif(
      fontSize: 17,
      height: 28 / 17,
      color: t.fg,
      opsz: 18,
    );
    final measure = 64 * KitText.ch(context, prose);
    final out = <Widget>[];
    for (final b in blocks) {
      Widget? w;
      if (b.kind == AskBlockKind.paragraph) {
        w = _paragraph(context, b.text, prose, measure);
      } else {
        final c = _cite(b.n ?? 0);
        if (c != null) w = _quote(context, b, c, prose, measure);
      }
      if (w == null) continue;
      if (out.isNotEmpty) out.add(const SizedBox(height: 12));
      out.add(w);
    }
    return Column(
      key: const ValueKey('ask-answer'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: out,
    );
  }

  Widget _paragraph(
      BuildContext context, String text, TextStyle style, double measure) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _marker.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final n = int.parse(m.group(1)!);
      final c = _cite(n);
      if (c != null) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          // `margin-left: 1px; vertical-align: 0.15em` — raised off the line's
          // baseline by 0.15 of the paragraph's size.
          child: Padding(
            padding: const EdgeInsets.only(left: 1),
            child: Transform.translate(
              offset: Offset(0, -0.15 * (style.fontSize ?? 17)),
              child: KitAskRef(
                n: n,
                title: c.title,
                onTap: onCite == null ? null : () => onCite!(n),
              ),
            ),
          ),
        ));
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: measure),
      child: Text.rich(TextSpan(style: style, children: spans)),
    );
  }

  Widget _quote(BuildContext context, AskAnswerBlock b, AskCitation c,
      TextStyle prose, double measure) {
    final t = Tokens.of(context);
    return Container(
      key: ValueKey('ask-quote-${b.n}'),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.accent, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: measure),
            child: KitMarkedText(
              b.text,
              style: prose.copyWith(fontStyle: FontStyle.italic),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              KitAskRef(
                n: b.n!,
                title: c.title,
                onTap: onCite == null ? null : () => onCite!(b.n!),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  c.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KitText.small(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// §25's **reference marker**: the citation's own mono `--accent-text` index
/// in a small bordered chip — 18 high, `0 5px`, mono 10.5/600, 1px
/// `--border`, `--r-xs`, `--bg`. Hover: `--accent-soft` under an `--accent`
/// edge; focus: a 2px accent ring. Named for the passage it takes the reader
/// to (`Passage 1: Pasta Fundamentals`).
class KitAskRef extends StatelessWidget {
  final int n;
  final String title;
  final VoidCallback? onTap;

  const KitAskRef({super.key, required this.n, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      onTap: onTap,
      label: 'Passage $n: $title',
      // Sized to its figure: inside a line of text the chip is offered the
      // paragraph's whole width, and an aligned box takes all of it.
      builder: (context, hover, focus) => Container(
        height: 18,
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: hover ? t.accentSoft : t.bg,
          borderRadius: AppRadius.xsR,
          border: Border.all(
            color: focus || hover ? t.accent : t.border,
            width: focus ? 2 : 1,
          ),
        ),
        child: Center(
          widthFactor: 1,
          child: Text(
            '$n',
            style: KitText.monoFigure(
              context,
              fontSize: 10.5,
              weight: FontWeight.w600,
              color: t.accentText,
            ).copyWith(height: 1),
          ),
        ),
      ),
    );
  }
}

// ── Ask in direction D (screens/ask.md §Composition) ────────────────────────
//
// Ask's own parts: the conversation's title on the masthead, a turn's two
// heads, the citations' ruled register, the conversations sheet's rows and its
// running head's line, and the §38 composer Ask docks at its column's foot
// (web `.dp-ask`, `.dp-convos`, `.ask-composer` in `app-d-pages.css`). They
// live here, not in the page: a page under `lib/pages/` spells no type.

/// The masthead's title on Ask — the open conversation's title, *Ask Your
/// Library*, or *Ask {shelf}* — set smaller than §26's: `clamp(38px, 4cqi,
/// 64px)`, 32 on a phone (`.dp-ask .ed-title`), in the masthead's own face,
/// leading, tracking and letterpress. Drawn plain: a conversation's title is
/// the reader's question, and §26's `*clause*` parsing would eat an asterisk
/// they typed. Pass it as [KitDPage.titleWidget].
class KitAskTitle extends StatelessWidget {
  final String text;
  const KitAskTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    return LayoutBuilder(builder: (context, c) {
      final size = phone ? 32.0 : (0.04 * c.maxWidth).clamp(38.0, 64.0);
      return Semantics(
        header: true,
        child: Text(
          text,
          style: AppTheme.serif(
            fontSize: size,
            height: phone ? 1.02 : 0.98,
            fontWeight: FontWeight.w600,
            letterSpacing: (phone ? -0.028 : -0.03) * size,
            color: t.fg,
            opsz: 60,
          ).copyWith(shadows: AppShadows.letterpress),
        ),
      );
    });
  }
}

/// A turn's head: mono 10.5 / 0.14em caps — *You* in `--fg-subtle`, *Your
/// library* in `--accent-text`.
class KitAskWho extends StatelessWidget {
  final String text;
  final bool library;
  const KitAskWho(this.text, {super.key, this.library = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Text(
      text.toUpperCase(),
      style: KitText.monoMeta(
        context,
        fontSize: 10.5,
        letterSpacing: 0.14,
        height: 14 / 10.5,
        color: library ? t.accentText : t.fgSubtle,
      ),
    );
  }
}

/// **The reader's question** — under a 2px `--fg` rule, 16 below it the mono
/// caps *You*, 8 below that the question in serif 600 `clamp(24px, 2.6cqi,
/// 32px)`/1.18, −0.016em, `opsz 36`. 56 above every question after the first
/// ([first] has none).
class KitAskQuestion extends StatelessWidget {
  final String text;
  final bool first;
  const KitAskQuestion(this.text, {super.key, this.first = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: first ? 0 : 56),
      child: Container(
        padding: const EdgeInsets.only(top: 16),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.fg, width: 2)),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final size = (0.026 * c.maxWidth).clamp(24.0, 32.0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const KitAskWho('You'),
              const SizedBox(height: 8),
              Text(
                text,
                textWidthBasis: TextWidthBasis.longestLine,
                style: AppTheme.serif(
                  fontSize: size,
                  height: 1.18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.016 * size,
                  color: t.fg,
                  opsz: 36,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

/// **The library's turn**, 22 under the question: the mono caps *Your library*
/// in `--accent-text`, then ONE of —
///
/// - [line]: a sentence in place of passages — the thinking line (*Reading
///   your notes…*) or one of the three empty answers — serif italic 16/25 in
///   `--fg-lede`, 8 under the head;
/// - [failure] (§14.2, the server's sentence) 10 under the head, and [retry]
///   10 under that;
/// - the written answer (§25) 10 under the head, then the citations 14 under
///   it; or `answer_note` 4 under the head, the citations 12 under it; or,
///   with neither (an answer before 5.30.0, or generative AI off), the
///   citations alone 10 under the head ([citations], a [KitAskCitations]).
///
/// The gaps are web's margins collapsed (`.who` 4 under it, `.ask-answer`
/// 10 above and 14 below, `.ask-answer-note` 12 below, `.citations` 10 above).
class KitAskReply extends StatelessWidget {
  final String? line;
  final Widget? failure;
  final Widget? retry;
  final List<AskAnswerBlock>? answer;
  final String? note;
  final List<AskCitation> cited;
  final ValueChanged<int>? onCite;
  final Widget? citations;

  const KitAskReply({
    super.key,
    this.line,
    this.failure,
    this.retry,
    this.answer,
    this.note,
    this.cited = const [],
    this.onCite,
    this.citations,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final hasAnswer = answer != null && answer!.isNotEmpty;
    final hasNote = !hasAnswer && note != null && note!.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const KitAskWho('Your library', library: true),
          if (line != null) ...[
            const SizedBox(height: 8),
            Text(
              line!,
              style: AppTheme.serif(
                fontSize: 16,
                height: 25 / 16,
                fontStyle: FontStyle.italic,
                color: t.fgLede,
                opsz: 18,
              ),
            ),
          ],
          if (failure != null) ...[
            const SizedBox(height: 10),
            failure!,
            if (retry != null) ...[const SizedBox(height: 10), retry!],
          ],
          if (line == null && failure == null && citations != null) ...[
            if (hasAnswer) ...[
              const SizedBox(height: 10),
              KitAskAnswer(answer: answer, citations: cited, onCite: onCite),
              const SizedBox(height: 14),
            ] else if (hasNote) ...[
              const SizedBox(height: 4),
              KitAskAnswer(answer: null, note: note, citations: cited),
              const SizedBox(height: 12),
            ] else
              const SizedBox(height: 10),
            citations!,
          ],
        ],
      ),
    );
  }
}

/// The citations as a **ruled register**: a 1px `--rule` on top, then each
/// [KitAskCitation].
class KitAskCitations extends StatelessWidget {
  final List<Widget> children;
  const KitAskCitations({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Tokens.of(context).rule)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      );
}

/// One passage in the register: `28px 38px 1fr`, gaps `6px 14px`, `14px 0`, a
/// 1px `--rule` under — the index (serif italic 22, `--accent-text`,
/// right-aligned), the §6.4 File badge, the source's title (serif 600 16.5/22)
/// over the WHOLE excerpt (serif 15.5/24, §17.2 markers inline — nothing
/// truncates it), and under them its [actions] (*Open*, the host link), gaps
/// `6px 18px`. [marked]: a §25 marker just pointed here — `--accent-soft`.
class KitAskCitation extends StatelessWidget {
  final int index;
  final String title;
  final String excerpt;
  final String? sourceType;
  final bool marked;
  final List<Widget> actions;

  const KitAskCitation({
    super.key,
    required this.index,
    required this.title,
    required this.excerpt,
    this.sourceType,
    this.marked = false,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return AnimatedContainer(
      duration: KitD.dur(context, AppMotion.durFast),
      curve: AppMotion.easeOut,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: marked ? t.accentSoft : t.accentSoft.withValues(alpha: 0),
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$index',
              textAlign: TextAlign.right,
              style: AppTheme.serif(
                fontSize: 22,
                height: 1,
                fontStyle: FontStyle.italic,
                color: t.accentText,
                opsz: 36,
              ),
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 38,
            child: Align(
              alignment: Alignment.topLeft,
              child: KitFileBadge(kitDocKind(sourceType ?? ''),
                  size: KitBadgeSize.chip),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTheme.serif(
                    fontSize: 16.5,
                    height: 22 / 16.5,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                    opsz: 18,
                  ),
                ),
                const SizedBox(height: 4),
                KitMarkedText(
                  excerpt,
                  style: AppTheme.serif(
                    fontSize: 15.5,
                    height: 24 / 15.5,
                    color: t.fg,
                    opsz: 18,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── The conversations sheet (§29 · §9 · §9.1 · §9.2 · §36) ─────────────────

/// *New conversation* at the head of the list: the `+` (15) and serif 16 in
/// `--fg-muted`, `--fg` on hover and `--fg` 600 while it is current (no
/// conversation open); `10px 0`, a `--rule` under. Choosing it folds the
/// running head.
class KitAskNewConversation extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const KitAskNewConversation(
      {super.key, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      key: const ValueKey('ask-new'),
      selected: active,
      onTap: () {
        onTap();
        KitSheetScope.pick(context);
      },
      builder: (context, hover, focus) {
        final ink = active || hover ? t.fg : t.fgMuted;
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          foregroundDecoration: focus
              ? BoxDecoration(
                  border: Border.all(color: t.accent, width: 2),
                  borderRadius: AppRadius.smR,
                )
              : null,
          child: Row(
            children: [
              Icon(Icons.add, size: 15, color: ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'New conversation',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KitText.bodyReading(
                    context,
                    fontSize: 16,
                    height: 22,
                    weight: active ? FontWeight.w600 : FontWeight.w400,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A group's label in the list (*Today*, *Earlier*): mono 10.5 / 0.14em caps
/// in `--fg-subtle`, 18 above and 4 under.
class KitAskGroupLabel extends StatelessWidget {
  final String text;
  const KitAskGroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 4),
        child: KitAskWho(text),
      );
}

/// §9.1 — one action in an entry's cluster.
class KitAskConvoAction {
  final IconData icon;

  /// Names the object, not the verb alone: *Delete* in a list of twelve names
  /// nothing.
  final String label;
  final bool danger;
  final VoidCallback onPressed;

  const KitAskConvoAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });
}

/// One conversation in the sheet (§9 entry in D): its title (serif 15.5/500,
/// one line; 600 when open), its §9.2 scope (mono 9.5 / 0.1em caps
/// `--accent-text`, yielding to the title; nothing at all when unscoped), and
/// its italic preview (serif 13.5 `--fg-lede`, two lines) — `9px 12px`, a
/// `--rule` under. The open one is marked by the 6px accent dot to its left
/// and weight 600, no fill of its own. It **rounds in place** (§36: the entry
/// carries its own side padding, so the hover reaches nowhere).
///
/// §9.1's cluster (rename, delete) is a SIBLING of the open affordance, at the
/// trailing edge of the title line: 24×24 buttons, icons 14 in `--fg-subtle`,
/// a destructive one `--critical-text` on hover only. This client's form is
/// the coarse pointer's, so the cluster is always present, and the trailing
/// time yields to it — [time] is drawn only when [actions] is empty. The
/// rename is in place, in a field carrying the title's own role; it commits on
/// Enter or blur and abandons on Escape, and the title moves only when the
/// call resolves (the host keeps [renaming] until then). A rejection is §14.2,
/// dense, in the entry's own flow.
class KitAskConvo extends StatelessWidget {
  final String title;
  final String? scope;
  final String? time;
  final String preview;
  final bool active;
  final VoidCallback onOpen;
  final List<KitAskConvoAction> actions;
  final bool renaming;
  final bool busy;
  final String? error;
  final ValueChanged<String>? onRenameCommit;
  final VoidCallback? onRenameCancel;

  const KitAskConvo({
    super.key,
    required this.title,
    required this.onOpen,
    this.scope,
    this.time,
    this.preview = '',
    this.active = false,
    this.actions = const [],
    this.renaming = false,
    this.busy = false,
    this.error,
    this.onRenameCommit,
    this.onRenameCancel,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final cluster = actions.isNotEmpty && !renaming;
    final titleStyle = AppTheme.serif(
      fontSize: 15.5,
      height: 1.2,
      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
      color: t.fg,
      opsz: 16,
    );
    final open = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(right: cluster ? 52 : 0),
            // The title takes what the scope leaves (`flex: 1`); the scope
            // keeps its own width and gives way only past half the line
            // (`flex-shrink: 1` on its natural width).
            child: LayoutBuilder(builder: (context, c) => Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: titleStyle),
                ),
                if (scope != null && scope!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: c.maxWidth / 2),
                    child: Text(
                      scope!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KitText.monoMeta(
                        context,
                        fontSize: 9.5,
                        letterSpacing: 0.1,
                        height: 12 / 9.5,
                        color: t.accentText,
                      ),
                    ),
                  ),
                ],
                if (!cluster && time != null && time!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(time!,
                      style: KitText.monoMeta(context,
                          fontSize: 10, letterSpacing: 0)),
                ],
              ],
            )),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.serif(
                fontSize: 13.5,
                height: 16 / 13.5,
                fontStyle: FontStyle.italic,
                color: t.fgLede,
                opsz: 14,
              ),
            ),
          ],
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (renaming)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: _AskRenameField(
                    initial: title,
                    enabled: !busy,
                    onCommit: onRenameCommit,
                    onCancel: onRenameCancel,
                  ),
                )
              else
                // No label of its own: the entry reads as what it shows —
                // title, scope and preview — as web's open button does.
                KitRowHover(
                  reach: 0,
                  onTap: () {
                    onOpen();
                    KitSheetScope.pick(context);
                  },
                  child: open,
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
                  child: KitFailureInline(error!, dense: true),
                ),
            ],
          ),
          if (active)
            Positioned(
              left: -14,
              top: 20,
              child: ExcludeSemantics(
                child: Container(
                  key: const ValueKey('ask-convo-dot'),
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(color: t.accent, shape: BoxShape.circle),
                ),
              ),
            ),
          if (cluster)
            Positioned(
              top: 5,
              right: 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 2),
                    _AskConvoButton(action: actions[i], enabled: !busy),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AskConvoButton extends StatelessWidget {
  final KitAskConvoAction action;
  final bool enabled;
  const _AskConvoButton({required this.action, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Tooltip(
      message: action.label,
      child: Opacity(
        opacity: enabled ? 1 : AppSpacing.heldOpacity,
        child: KitDTap(
          onTap: action.onPressed,
          enabled: enabled,
          label: action.label,
          builder: (context, hover, focus) => Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: hover ? t.hover : null,
              borderRadius: AppRadius.smR,
              border: focus ? Border.all(color: t.accent, width: 2) : null,
            ),
            child: Icon(
              action.icon,
              size: 14,
              color: hover
                  ? (action.danger ? t.criticalText : t.fg)
                  : t.fgSubtle,
            ),
          ),
        ),
      ),
    );
  }
}

/// §9.1's rename field: the title's role (serif 14/600, `opsz 16`) on
/// `--surface-raised`, a 1px `--accent-chip-border`, `--r-sm`, `2px 6px`
/// (`.convo-rename`). Commits on Enter and on focus loss; Escape abandons —
/// and the focus loss it causes must not then commit the abandoned draft.
class _AskRenameField extends StatefulWidget {
  final String initial;
  final bool enabled;
  final ValueChanged<String>? onCommit;
  final VoidCallback? onCancel;

  const _AskRenameField({
    required this.initial,
    required this.enabled,
    this.onCommit,
    this.onCancel,
  });

  @override
  State<_AskRenameField> createState() => _AskRenameFieldState();
}

class _AskRenameFieldState extends State<_AskRenameField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.initial,
  )..selection =
      TextSelection(baseOffset: 0, extentOffset: widget.initial.length);
  final FocusNode _focus = FocusNode();
  bool _abandoned = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
    // After the frame the field is built in: a node not yet in the tree
    // cannot take focus.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _onFocus() {
    if (_focus.hasFocus || _abandoned || !mounted) return;
    widget.onCommit?.call(_c.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final edge = OutlineInputBorder(
      borderRadius: AppRadius.smR,
      borderSide: BorderSide(color: t.accentChipBorder),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _abandoned = true;
          widget.onCancel?.call();
        },
      },
      child: Semantics(
        label: 'Conversation title',
        textField: true,
        child: TextField(
          controller: _c,
          focusNode: _focus,
          enabled: widget.enabled,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => widget.onCommit?.call(v),
          style: AppTheme.serif(
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: t.fg,
            opsz: 16,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: t.surfaceRaised,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            border: edge,
            enabledBorder: edge,
            focusedBorder: edge,
            disabledBorder: edge,
          ),
        ),
      ),
    );
  }
}

/// The running head's line on Ask (§30, web `.d-peek-t` / `.d-peek-n`): the
/// history glyph (16, `--fg-muted`), the open conversation's title — else
/// *Conversations* — in serif 600 16.5/22, one line, and at the trailing edge
/// the count of conversations in mono 11.5. [count] null draws no count (the
/// read is out, or refused): a figure that is not measured is left out.
class KitAskPeek extends StatelessWidget {
  final String title;
  final String? count;
  const KitAskPeek({super.key, required this.title, this.count});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      children: [
        Icon(Icons.history, size: 16, color: t.fgMuted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.serif(
              fontSize: 16.5,
              height: 22 / 16.5,
              fontWeight: FontWeight.w600,
              color: t.fg,
              opsz: 18,
            ),
          ),
        ),
        if (count != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              count!,
              style: KitText.monoFigure(context, fontSize: 11.5, color: t.fg),
            ),
          ),
        ],
      ],
    );
  }
}

// ── §38 Composer, as Ask docks it ───────────────────────────────────────────

/// Ask's composer (`.ask-composer`): a raised card — `--surface`, 1px
/// `--border`, `--r-xl`, `--shadow-3`, `12px 14px 12px 20px` — holding the
/// §38 field ([KitGrowField]: one line tall, growing to 172 then scrolling)
/// and the send: a 38px `--accent` circle with the arrow (17, `--accent-fg`),
/// aligned to the field's last line, named *Ask*, held at `--held-opacity`
/// while the field is empty or a turn is in flight ([busy]).
///
/// **A hardware Enter asks; Shift+Enter is a newline; the Enter that ends an
/// IME composition is the composition's** — while the field's `composing`
/// range is open the key is not a send. The field carries [label] as its
/// accessible name and [placeholder] as its hint. Docked at the column's foot
/// through [KitDPage.dock].
class KitAskComposer extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String placeholder;
  final bool busy;
  final VoidCallback onSubmit;

  const KitAskComposer({
    super.key,
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.onSubmit,
    this.focusNode,
    this.busy = false,
  });

  @override
  State<KitAskComposer> createState() => _KitAskComposerState();
}

class _KitAskComposerState extends State<KitAskComposer> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  bool get _canSend => widget.controller.text.trim().isNotEmpty && !widget.busy;

  /// Enter's three readings (§38): a send, a newline (Shift), or the end of an
  /// IME composition — which is the composition's, never a send.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter &&
        e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
    final composing = widget.controller.value.composing;
    if (composing.isValid && !composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    // Held or not, the Enter is consumed: an empty field or a turn in flight
    // must not take a newline the reader meant as a send.
    if (_canSend) widget.onSubmit();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.xlR,
        border: Border.all(color: t.border),
        boxShadow: AppShadows.s3,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onKeyEvent: _onKey,
                child: Semantics(
                  label: widget.label,
                  textField: true,
                  // §38's field draws no border and no fill of its own
                  // (KitGrowField): the card is the field's frame.
                  child: KitGrowField(
                    key: const ValueKey('ask-field'),
                    controller: widget.controller,
                    focusNode: _focus,
                    placeholder: widget.placeholder,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final on = _canSend;
                return Opacity(
                  opacity: on ? 1 : AppSpacing.heldOpacity,
                  child: KitDTap(
                    key: const ValueKey('ask-send'),
                    onTap: on ? widget.onSubmit : null,
                    label: 'Ask',
                    builder: (context, hover, focus) => Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hover ? t.accentHover : t.accent,
                        shape: BoxShape.circle,
                        border: focus
                            ? Border.all(color: t.fg, width: 2)
                            : null,
                      ),
                      child: Icon(Icons.arrow_forward,
                          size: 17, color: t.accentFg),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
