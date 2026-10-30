// Deep study's own D parts (`screens/study.md` §Composition, §Session player;
// web `pages/StudyView.jsx` and `pages/study/SessionPlayer.jsx` over
// `styles/app-study.css` and `app-d-pages.css` `.dp-study`, `.dp-sess`,
// `.dp-qs`). A page file never styles its own type or spacing (ADR-041), so a
// part only Study draws still lives in the kit. Metrics are web's numbers and
// this client's starting values; the one breakpoint web draws at 900 for
// these parts is kept at 900, because it is the player's own (a question's
// excerpt beside it, the grades in four).

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart'
    show Style, Margins, HtmlPaddings, FontSize, LineHeight;

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_frame.dart' show KitSheetScope;
import 'kit_d_parts.dart';
import 'kit_program_card.dart' show KitStudyChip, KitStudyMeter;
import 'kit_shell.dart' show KitGlyph;
import 'kit_text.dart';

/// Web's own breakpoint for the player and the history rows (`max-width:
/// 900px` in `app-study.css`).
const double _narrow = 900;

bool _isNarrow(BuildContext context) =>
    MediaQuery.sizeOf(context).width <= _narrow;

// ── Study programs ─────────────────────────────────────────────────────────

/// One past session in the Sessions register (web `HistoryRow`, `.dp-study
/// .st-hrow`): the date over its time in mono 11, the program's title in
/// serif 500 17, the session's figures in sans 12 parted by dots, and its
/// chip — or, when nothing happened to it, a chevron. A rule under it, 14
/// above and below; §36's hover reaching 12 past its text. At 900 and under
/// the date drops under the title.
class KitStudyHistoryRow extends StatelessWidget {
  final String date;
  final String time;
  final String title;
  final List<String> parts;
  final String? chip;
  final VoidCallback onTap;

  const KitStudyHistoryRow({
    super.key,
    required this.date,
    required this.time,
    required this.title,
    required this.parts,
    required this.onTap,
    this.chip,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final narrow = _isNarrow(context);
    final sub = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 12,
      height: 16 / 12,
      color: t.fgMuted,
    );
    final when = Text(
      '$date\n$time',
      style: AppTheme.mono(fontSize: 11, height: 16 / 11, color: t.fgSubtle),
    );
    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.serif(
            fontSize: 17,
            height: 22 / 17,
            fontWeight: FontWeight.w500,
            color: t.fg,
            opsz: 18,
          ),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < parts.length; i++) ...[
              if (i > 0)
                Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    color: t.fgSubtle,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(parts[i], style: sub),
            ],
          ],
        ),
      ],
    );
    final trailing = chip != null
        ? KitStudyChip(status: 'session', label: chip!)
        : Icon(Icons.chevron_right, size: 16, color: t.fgSubtle);
    return KitRowHover(
      onTap: onTap,
      label: '$title, $date',
      child: Container(
        padding: const EdgeInsets.fromLTRB(0, 14, 8, 14),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.rule)),
        ),
        child: narrow
            ? Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [main, const SizedBox(height: 8), when],
                    ),
                  ),
                  const SizedBox(width: 18),
                  trailing,
                ],
              )
            : Row(
                children: [
                  SizedBox(width: 92, child: when),
                  const SizedBox(width: 18),
                  Expanded(child: main),
                  const SizedBox(width: 18),
                  trailing,
                ],
              ),
      ),
    );
  }
}

// ── A session: the sheet ───────────────────────────────────────────────────

/// One question on the session's sheet.
class KitStudyQuestionItem {
  final String title;

  /// The grade given (*Good*…), once answered.
  final String? grade;
  const KitStudyQuestionItem(this.title, {this.grade});
}

/// The session sheet's **Questions** (web `.dp-qs` on `.rx-nav-toc` rows):
/// one row per question, numbered `1…n` in mono in the accent, its source
/// title in serif, and the grade given on an answered one, which reads in
/// `--fg-subtle`. The [marked] row is the question to answer NEXT — `--fg`
/// 600 with the accent dot — not the one in view. A row calls [onJump] and
/// folds the running head.
class KitStudyQuestions extends StatelessWidget {
  final List<KitStudyQuestionItem> items;
  final int? marked;
  final ValueChanged<int> onJump;

  const KitStudyQuestions({
    super.key,
    required this.items,
    required this.marked,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final dock = KitSheetScope.maybeOf(context)?.dock ?? false;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Questions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++)
            Builder(
              builder: (context) {
                final it = items[i];
                final on = marked == i;
                final done = it.grade != null;
                return KitDTap(
                  key: ValueKey('d-q-$i'),
                  label: '${i + 1} ${it.title}${done ? ', ${it.grade}' : ''}',
                  selected: on,
                  onTap: () {
                    onJump(i);
                    KitSheetScope.pick(context);
                  },
                  builder: (context, hover, focus) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(vertical: dock ? 11 : 9),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: t.rule)),
                          borderRadius: focus ? BorderRadius.circular(3) : null,
                        ),
                        foregroundDecoration: focus
                            ? BoxDecoration(
                                border: Border.all(color: t.accent, width: 2),
                                borderRadius: BorderRadius.circular(3),
                              )
                            : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 24,
                              child: Text(
                                '${i + 1}',
                                style: AppTheme.mono(
                                  fontSize: 11,
                                  fontWeight: on
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: t.accentText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                it.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.serif(
                                  fontSize: 16,
                                  fontWeight: on
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: on || (hover && !done)
                                      ? t.fg
                                      : done
                                      ? t.fgSubtle
                                      : t.fgMuted,
                                ),
                              ),
                            ),
                            if (done) ...[
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: t.hoverStrong,
                                  borderRadius: AppRadius.controlR(20),
                                ),
                                child: Text(
                                  it.grade!,
                                  style: AppTheme.mono(
                                    fontSize: 9.5,
                                    letterSpacing: 0.08 * 9.5,
                                    color: t.fgMuted,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (on)
                        Positioned(
                          left: -14,
                          top: 0,
                          bottom: 0,
                          child: Center(
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: t.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ── A session: the column ──────────────────────────────────────────────────

/// `.st-quiet` — a quiet note at the head of a session (the email that did
/// not send; Exam prep): sans 12.5/18 `--fg-muted` on the sunken ground,
/// `12px 14px`, `--r-sm`, an optional 15px glyph. [lead] is set in 600 `--fg`
/// before the sentence (*Exam prep* — …).
class KitStudyQuiet extends StatelessWidget {
  final IconData? icon;
  final String? lead;
  final String text;
  final double top;

  const KitStudyQuiet(
    this.text, {
    super.key,
    this.icon,
    this.lead,
    this.top = 20,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final note = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 12.5,
      height: 18 / 12.5,
      color: t.fgMuted,
    );
    return Container(
      margin: EdgeInsets.only(top: top),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.smR,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: KitGlyph(icon!, size: 15, color: t.fgMuted),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  if (lead != null)
                    TextSpan(
                      text: lead,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                      ),
                    ),
                  TextSpan(text: text),
                ],
              ),
              style: note,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.st-prog-line` — *1 of 3 answered* in mono caps beside the session's
/// measured meter (one count over its own total, the program card's meter).
class KitStudyAnswered extends StatelessWidget {
  final int answered;
  final int total;
  final double top;

  const KitStudyAnswered({
    super.key,
    required this.answered,
    required this.total,
    this.top = 18,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Row(
        children: [
          Text(
            '$answered of $total answered'.toUpperCase(),
            style: AppTheme.mono(
              fontSize: 11,
              letterSpacing: 0.1 * 11,
              color: t.fgMuted,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: KitStudyMeter(n: answered, of: total)),
        ],
      ),
    );
  }
}

/// `.st-panel` — a session's state said as information, never as an error:
/// still being made, not made, caught up, and *That’s the session*. A
/// surface card (`--border`, `--r-lg`, `24px 26px`, 28 above): an optional
/// mono caps [eyebrow] ([eyebrowCritical] in `--critical-text`: *Not made*),
/// the serif 600 20/27 [title], its serif 16/26 `--fg-lede` [paragraphs]
/// (≤56ch, 10 apart), skeleton lines while the questions are drawn
/// ([building]), and [actions] 18 under it.
class KitStudyPanel extends StatelessWidget {
  final String? eyebrow;
  final bool eyebrowCritical;
  final String title;
  final List<String> paragraphs;
  final bool building;
  final List<Widget> actions;
  final double top;

  const KitStudyPanel({
    super.key,
    required this.title,
    this.eyebrow,
    this.eyebrowCritical = false,
    this.paragraphs = const [],
    this.building = false,
    this.actions = const [],
    this.top = 28,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final p = AppTheme.serif(
      fontSize: 16,
      height: 26 / 16,
      color: t.fgLede,
      opsz: 18,
    );
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: top),
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 24),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.lgR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!.toUpperCase(),
              style: KitText.capsLabel(
                context,
                color: eyebrowCritical ? t.criticalText : null,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTheme.serif(
                fontSize: 20,
                height: 27 / 20,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.01 * 20,
                color: t.fg,
              ),
            ),
          ),
          for (var i = 0; i < paragraphs.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 8 : 10),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 56 * KitText.ch(context, p)),
                child: Text(paragraphs[i], style: p),
              ),
            ),
          if (building)
            const KitSkeletonLines(
              lines: [KitSkelLine(0.62), KitSkelLine(0.84), KitSkelLine(0.46)],
              top: 20,
            ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(spacing: 12, runSpacing: 12, children: actions),
          ],
        ],
      ),
    );
  }
}

/// One of a question's four grades.
class KitStudyGrade {
  final String label;

  /// The key that grades it (`1`–`4`), drawn beside the label.
  final String key;
  final VoidCallback? onTap;

  /// This grade's write is in flight: its button shows the dots.
  final bool busy;

  const KitStudyGrade(this.label, this.key, {this.onTap, this.busy = false});
}

/// `.st-excerpt` — the passage a question came from: *From {title}* in caps,
/// then its [body] (the chunk's sanitized html, in the page's renderer).
/// On the sunken ground under a question; flat beside a new one ([aside]).
class KitStudyExcerpt extends StatelessWidget {
  final String title;
  final Widget body;
  final bool aside;

  const KitStudyExcerpt({
    super.key,
    required this.title,
    required this.body,
    this.aside = false,
  });

  /// The excerpt body's type (`.st-excerpt-body`): serif 15/24 `--fg-lede`.
  static TextStyle bodyStyle(BuildContext context) => AppTheme.serif(
    fontSize: 15,
    height: 24 / 15,
    color: Tokens.of(context).fgLede,
    opsz: 16,
  );

  /// The same, as the html renderer's `body` — for `AppTheme.htmlStyles(…,
  /// body:)`, which every `Html` passes — flush under its label.
  static Style htmlBody(BuildContext context) => Style(
    margin: Margins.zero,
    padding: HtmlPaddings.zero,
    fontFamily: AppTheme.fontSerif,
    fontSize: FontSize(15),
    lineHeight: LineHeight(24 / 15),
    color: Tokens.of(context).fgLede,
  );

  /// Each paragraph `0 0 8px` (`.st-excerpt-body p`), spread after the
  /// shared map.
  static final Map<String, Style> htmlParagraphs = {
    'p': Style(margin: Margins.only(top: 0, bottom: 8)),
  };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('From $title'.toUpperCase(), style: KitText.capsLabel(context)),
        const SizedBox(height: 6),
        DefaultTextStyle.merge(style: bodyStyle(context), child: body),
      ],
    );
    if (aside) return inner;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.smR,
      ),
      child: inner,
    );
  }
}

/// `.st-q` — one question of a session (web `QuestionCard`): its kind's mark
/// (*New*, *Review*, *Exam prep*), the source, `n / N`; the question in serif
/// 22/32; *Show answer* until it is revealed; the answer under a rule; the
/// four grades — never optimistic, every one held while a grade is being
/// written; once graded, the grade's chip and the schedule's own answer
/// ([notes]: *back in 6 days*). A new question offers its [aside] excerpt
/// beside it (under it at 900 and under); a review keeps its excerpt behind
/// [onDisclose] until asked. [current] is the question to answer next.
class KitStudyQuestionCard extends StatelessWidget {
  /// `new`, `review` or `ramp`.
  final String kind;
  final String source;
  final String index;
  final String question;
  final String answer;
  final bool revealed;
  final bool done;
  final bool current;
  final String? grade;
  final List<String> notes;
  final VoidCallback onReveal;
  final List<KitStudyGrade> grades;

  /// A grade is being written: the note under the grades says so.
  final bool saving;

  /// The endpoint's refusal of this question's grade (§14.2), under the
  /// grades it answered — a 404 (no longer in the session), a 409 (already
  /// recorded) and a 401 each want a different next move (C6).
  final Widget? failure;
  final Widget? aside;
  final Widget? excerpt;
  final VoidCallback? onDisclose;

  const KitStudyQuestionCard({
    super.key,
    required this.kind,
    required this.source,
    required this.index,
    required this.question,
    required this.answer,
    required this.revealed,
    required this.done,
    required this.current,
    required this.onReveal,
    required this.grades,
    this.grade,
    this.notes = const [],
    this.saving = false,
    this.failure,
    this.aside,
    this.excerpt,
    this.onDisclose,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final narrow = _isNarrow(context);
    final sans = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      color: t.fg,
    );
    final kbd = AppTheme.mono(fontSize: 10, color: t.fgSubtle);

    final (markBg, markFg, markBorder) = switch (kind) {
      'new' => (t.accentChipBg, t.accentChipFg, t.accentChipBorder),
      'ramp' => (t.accentSoft, t.accentText, t.accentChipBorder),
      _ => (t.surfaceSunken, t.fgMuted, null),
    };
    final markLabel = switch (kind) {
      'new' => 'New',
      'ramp' => 'Exam prep',
      _ => 'Review',
    };

    final head = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            height: 22,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: markBg,
              borderRadius: AppRadius.controlR(20),
              border: markBorder == null ? null : Border.all(color: markBorder),
            ),
            child: Text(
              markLabel.toUpperCase(),
              style: AppTheme.mono(
                fontSize: 10,
                letterSpacing: 0.12 * 10,
                color: markFg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              source,
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
            index,
            style: AppTheme.mono(
              fontSize: 10.5,
              letterSpacing: 0.08 * 10.5,
              color: t.fgSubtle,
            ),
          ),
        ],
      ),
    );

    Widget pill({
      required Widget child,
      required double height,
      VoidCallback? onTap,
      Color? fill,
      Color? edge,
      String? label,
      bool held = false,
      bool expand = false,
    }) => Opacity(
      opacity: held ? AppSpacing.heldOpacity : 1,
      child: KitDTap(
        onTap: held ? null : onTap,
        label: label,
        builder: (context, hover, focus) => AnimatedContainer(
          duration: KitD.dur(context, AppMotion.durFast),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // A grade fills its column (`grid`); Show answer is inline.
          alignment: expand ? Alignment.center : null,
          decoration: BoxDecoration(
            color: hover && !held ? t.hover : fill,
            borderRadius: AppRadius.controlR(height),
            border: Border.all(
              color: focus ? t.accent : (edge ?? t.borderStrong),
              width: focus ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: done
              ? AppTheme.serif(
                  fontSize: 18,
                  height: 27 / 18,
                  color: t.fgMuted,
                  opsz: 24,
                )
              : AppTheme.serif(
                  fontSize: 22,
                  height: 32 / 22,
                  fontWeight: FontWeight.w500,
                  color: t.fg,
                  opsz: 24,
                ),
        ),
        if (revealed || done)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.only(top: 16),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.rule)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ANSWER', style: KitText.capsLabel(context)),
                const SizedBox(height: 7),
                Text(
                  answer,
                  style: done
                      ? AppTheme.serif(
                          fontSize: 16,
                          height: 26 / 16,
                          color: t.fgMuted,
                          opsz: 18,
                        )
                      : AppTheme.serif(
                          fontSize: 18,
                          height: 29 / 18,
                          color: t.fg,
                          opsz: 18,
                        ),
                ),
              ],
            ),
          ),
        if (!revealed && !done)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: pill(
              height: 40,
              onTap: onReveal,
              label: 'Show answer',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Show answer', style: sans),
                  const SizedBox(width: 10),
                  Text('space', style: kbd.copyWith(letterSpacing: 0.4)),
                ],
              ),
            ),
          ),
        if (revealed && !done) ...[
          Padding(
            padding: const EdgeInsets.only(top: 22),
            child: LayoutBuilder(
              builder: (context, c) {
                final cols = narrow ? 2 : 4;
                final w = (c.maxWidth - 8 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in grades)
                      SizedBox(
                        width: w,
                        child: pill(
                          height: 46,
                          expand: true,
                          onTap: g.onTap,
                          label: g.label,
                          held: g.onTap == null,
                          fill: g.busy ? t.accentSoft : t.surface,
                          edge: g.busy ? t.accentChipBorder : null,
                          child: g.busy
                              ? _Dots(color: t.seal)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(g.label, style: sans),
                                    const SizedBox(width: 8),
                                    Text(g.key, style: kbd),
                                  ],
                                ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (current)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                saving ? 'Saving your grade…' : 'Keys 1–4 grade, space reveals.',
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 12,
                  color: t.fgSubtle,
                ),
              ),
            ),
        ],
        if (failure != null)
          Padding(padding: const EdgeInsets.only(top: 10), child: failure),
        if (done)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.only(top: 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.rule)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: t.surfaceSunken,
                    borderRadius: AppRadius.controlR(24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check, size: 13, color: t.fgMuted),
                      const SizedBox(width: 7),
                      Text(
                        grade ?? '',
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: t.fg,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final n in notes)
                  Text(
                    n,
                    style: AppTheme.mono(
                      fontSize: 11,
                      letterSpacing: 0.06 * 11,
                      color: t.accentText,
                    ),
                  ),
              ],
            ),
          ),
        if (excerpt != null)
          excerpt!
        else if (onDisclose != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: KitDTap(
              onTap: onDisclose,
              label: 'Show the excerpt',
              builder: (context, hover, focus) => Container(
                height: 30,
                padding: const EdgeInsets.fromLTRB(9, 0, 11, 0),
                decoration: BoxDecoration(
                  color: hover ? t.hover : null,
                  borderRadius: AppRadius.controlR(28),
                  border: Border.all(
                    color: focus ? t.accent : t.border,
                    width: focus ? 2 : 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_outlined,
                      size: 14,
                      color: hover ? t.fg : t.fgMuted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Show the excerpt',
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12.5,
                        color: hover ? t.fg : t.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    final side = aside;
    final body = side == null
        ? main
        : narrow
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              main,
              Container(
                margin: const EdgeInsets.only(top: 24),
                padding: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.rule)),
                ),
                child: side,
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: main),
              const SizedBox(width: 24),
              Container(
                width: 264,
                padding: const EdgeInsets.only(left: 24),
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: t.rule)),
                ),
                child: side,
              ),
            ],
          );

    return AnimatedContainer(
      duration: KitD.dur(context, AppMotion.durBase),
      curve: AppMotion.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      decoration: BoxDecoration(
        color: done ? t.bg : t.surface,
        borderRadius: AppRadius.lgR,
        border: Border.all(
          color: done
              ? t.rule
              : current
              ? t.borderStrong
              : t.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [head, body],
      ),
    );
  }
}

/// `.st-dots` — three 4px dots in the seal, pulsing while a grade is written
/// (still under reduced motion).
class _Dots extends StatefulWidget {
  final Color color;
  const _Dots({required this.color});

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KitD.still(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Opacity(
            opacity: () {
              if (!_c.isAnimating) return 0.35;
              final p = ((_c.value - i * 0.16) % 1.0);
              return 0.35 + 0.65 * (p < 0.5 ? p * 2 : (1 - p) * 2);
            }(),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// `h:mm AM` — a session's time under its date (web `toLocaleTimeString`
/// with `hour: 'numeric', minute: '2-digit'`, en-US).
String kitClockTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}
