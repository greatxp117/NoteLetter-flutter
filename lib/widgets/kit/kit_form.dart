import 'package:flutter/material.dart' show Icons;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_shell.dart' show KitGlyph;
import 'kit_text.dart';

/// The long form's pieces — the program editor's (web `ProgramEditor.jsx`,
/// `app-study.css` §editor), named here so the screen composes them rather than
/// spelling their metrics (ADR-041). Until 2026-10-14 the Flutter editor was
/// plain Material — a headline, `TextField`s, a `CheckboxListTile` per source —
/// against the reference's sections of card-and-row panels.
///
/// The rows sit in a [KitRowList] (§4.1's bordered list: `.st-card` is the same
/// container); the labelled fields are [KitConfigField] over a sunken
/// [KitTextField] / [KitSelect] (`.rl-field` / `.rl-input`, which the editor
/// shares with the readings letter); the session caps hold a [KitStepper].

/// The UI sans at [size] on a [line] px line — every sans role of the form.
TextStyle _sans(double size, Color color, {double? line, FontWeight? weight}) =>
    TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: size,
      height: line == null ? null : line / size,
      fontWeight: weight,
      color: color,
    );

/// `.st-sec` — one section of the form: an eyebrow (and, beside it, a mono
/// count), a sans 13/20 paragraph at `--fg-muted` capped at 62ch, then the
/// section's body. 32 above every section.
///
/// [lede] may carry one `*clause*`, set as web's `.st-sec-p em` — the serif
/// italic at 14.5 in `--fg` ("A program teaches *one subject.*").
class KitFormSection extends StatelessWidget {
  final String eyebrow;
  final String? count;
  final String? lede;
  final List<Widget> children;

  const KitFormSection({
    super.key,
    required this.eyebrow,
    this.count,
    this.lede,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Eyebrow(eyebrow, color: t.fgMuted)),
              if (count != null)
                Text(count!, style: KitText.monoMeta(context, letterSpacing: 0)),
            ],
          ),
          if (count != null) const SizedBox(height: 4),
          if (lede != null) KitFormLede(lede!),
          ...children,
        ],
      ),
    );
  }
}

/// `.st-sec-p` — the section's paragraph: sans 13/20 `--fg-muted`, 8 above and
/// 14 below, at most 62ch. [tight] drops the margins (`margin: 0 0 8px` inside
/// a card).
class KitFormLede extends StatelessWidget {
  final String text;
  final bool tight;

  const KitFormLede(this.text, {super.key, this.tight = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final base = _sans(13, t.fgMuted, line: 20);
    final em = KitText.lede(context, fontSize: 14.5, height: 20, color: t.fg);
    final parts = text.split('*');
    return Padding(
      padding: EdgeInsets.only(top: tight ? 0 : 8, bottom: tight ? 8 : 14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 62 * KitText.ch(context, base)),
        child: Text.rich(TextSpan(style: base, children: [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].isNotEmpty)
              TextSpan(text: parts[i], style: i.isOdd ? em : null),
        ])),
      ),
    );
  }
}

/// `.st-row` — one row of a form's list: a mono step number, a file plate, a
/// title over a sans 12 line, a mono count, then the row's own controls.
/// 12/14 padding, 14 between parts. [plain] sets the title in the UI sans
/// (`.st-row-t.plain`, 13.5/600) — a document named in a setting rather than
/// listed as a source.
class KitFormRow extends StatelessWidget {
  final String? number;
  final String? kind;
  final String? title;
  final bool plain;
  final String? subtitle;
  final String? count;
  final List<Widget> trailing;

  /// A row whose controls cannot share its width with the text drops them
  /// under it (`flex-wrap: wrap`, the source-kind rows).
  final bool wrap;

  /// A row that is only a sentence ("Every finished document is already in
  /// this program.").
  final Widget? body;

  const KitFormRow({
    super.key,
    this.number,
    this.kind,
    this.title,
    this.plain = false,
    this.subtitle,
    this.count,
    this.trailing = const [],
    this.wrap = false,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // Below the compact width a row that carries its own controls folds its
    // count into the line under the title — the recorded deviation that hides
    // §4.1's count at 768 — rather than squeezing the title to nothing beside
    // three 30px controls.
    final fold = count != null &&
        trailing.isNotEmpty &&
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final subtitle = fold
        ? [if (this.subtitle != null) this.subtitle!, count!].join(' · ')
        : this.subtitle;
    final count_ = fold ? null : count;
    final main = body ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null)
              Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: plain
                    ? _sans(13.5, t.fg, line: 21, weight: FontWeight.w600)
                    : AppTheme.serif(
                        fontSize: 16,
                        height: 21 / 16,
                        fontWeight: FontWeight.w500,
                        color: t.fg,
                        opsz: 18,
                      ),
              ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: _sans(12, t.fgMuted, line: 17)),
            ],
          ],
        );
    final lead = <Widget>[
      if (number != null)
        SizedBox(
          width: 22,
          child: Text(number!,
              textAlign: TextAlign.center,
              style: KitText.monoMeta(context,
                  fontSize: 12, letterSpacing: 0, color: t.accentText)),
        ),
      if (kind != null) KitFileBadge(kind!, size: KitBadgeSize.form),
    ];
    final tail = <Widget>[
      if (count_ != null)
        Text(count_, style: KitText.monoMeta(context, letterSpacing: 0)),
      ...trailing,
    ];
    final pad = const EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    if (wrap && tail.isNotEmpty) {
      // `flex-wrap: wrap`: the controls keep the text's line while they fit
      // beside it, and drop under it, whole, when they do not.
      return Padding(
        padding: pad,
        child: LayoutBuilder(builder: (context, c) {
          final head = Row(children: [
            for (final w in lead) ...[w, const SizedBox(width: 14)],
            Expanded(child: main),
          ]);
          final controls = Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: tail,
          );
          if (c.maxWidth >= 560) {
            return Row(children: [
              Expanded(child: head),
              const SizedBox(width: 14),
              controls,
            ]);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [head, const SizedBox(height: 10), controls],
          );
        }),
      );
    }
    return Padding(
      padding: pad,
      child: Row(
        children: [
          for (final w in lead) ...[w, const SizedBox(width: 14)],
          Expanded(child: main),
          for (final w in tail) ...[const SizedBox(width: 14), w],
        ],
      ),
    );
  }
}

/// `.st-iconbtn` — a row's 30×30 bordered square (move earlier, move later,
/// remove): `--surface`, the glyph 14 at `--fg-muted`, held at the token.
class KitRowIconButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  const KitRowIconButton(this.icon,
      {super.key, required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      child: Opacity(
        opacity: onPressed == null ? AppSpacing.heldOpacity : 1,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.controlR(30),
              border: Border.all(color: t.border),
            ),
            child: KitGlyph(icon, size: 14, color: t.fgMuted),
          ),
        ),
      ),
    );
  }
}

/// `.st-addbtn` — a row's quiet text action ("Add"): 30 high, a 1px
/// `--border-strong` outline on no fill, sans 12.5/500 at `--fg`.
class KitRowTextButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const KitRowTextButton(this.label, {super.key, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? AppSpacing.heldOpacity : 1,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: AppRadius.controlR(30),
              border: Border.all(color: t.borderStrong),
            ),
            child: Text(label,
                style: _sans(12.5, t.fg, weight: FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

/// `.st-unitchip` — a choice in a row (My notes · A reading): 24 high, a 1px
/// `--border-strong` outline, mono 11 at `--fg-muted`; chosen, the accent chip
/// with a check. Held at the token while its write is in flight.
class KitChoiceChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onPressed;

  const KitChoiceChip(this.label,
      {super.key, required this.on, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = on ? t.accentChipFg : t.fgMuted;
    return Semantics(
      button: true,
      selected: on,
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? AppSpacing.heldOpacity : 1,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            decoration: BoxDecoration(
              color: on ? t.accentChipBg : null,
              borderRadius: AppRadius.controlR(24),
              border: Border.all(
                  color: on ? t.accentChipBorder : t.borderStrong),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (on) ...[
                KitGlyph(Icons.check, size: 11, color: fg),
                const SizedBox(width: 4),
              ],
              Text(label,
                  style: KitText.monoMeta(context,
                      fontSize: 11, letterSpacing: 0, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.st-fixed` — a standing condition said beside its control (the sources are
/// fixed; only finished documents can be studied): the alert triangle 14 at
/// `--fg-subtle`, then the sentence in the note role. 12 above.
class KitFixedNote extends StatelessWidget {
  final String text;

  const KitFixedNote(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            // Web's IcoAlert, the triangle — the app's alert glyph everywhere.
            child: KitGlyph(Icons.warning_amber_rounded,
                size: 14, color: t.fgSubtle),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: KitText.note(context))),
        ],
      ),
    );
  }
}

/// `.st-fine` — the quietest sentence in the form (what Detach does, how many
/// sources still need an answer): sans 12/18 at `--fg-subtle`, at most 62ch.
class KitFineNote extends StatelessWidget {
  final String text;
  final double top;
  final double bottom;

  const KitFineNote(this.text, {super.key, this.top = 14, this.bottom = 0});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = _sans(12, t.fgSubtle, line: 18);
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 62 * KitText.ch(context, style)),
        child: Text(text, style: style),
      ),
    );
  }
}

/// `.st-picker-h` — a list's own small head inside a section: a mono caps
/// label, and a mono count at the trailing edge. 8 below.
class KitFormSubhead extends StatelessWidget {
  final String label;
  final String? count;

  const KitFormSubhead(this.label, {super.key, this.count});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
                child: Text(label.toUpperCase(),
                    style: KitText.capsLabel(context))),
            if (count != null)
              Text(count!, style: KitText.monoMeta(context, letterSpacing: 0)),
          ],
        ),
      );
}

/// `.st-cap` — a session cap: a `--surface` card at `--r-md`, 16/18 padding, a
/// sans 13/600 title over a 12/17 line, then its stepper 12 under.
class KitCapCard extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const KitCapCard(
      {super.key,
      required this.title,
      required this.description,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: _sans(13, t.fg, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(description,
              style: _sans(12, t.fgMuted, line: 17)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// `.st-form-foot` — the form's closing row: a 1px `--rule` above, 20 under it,
/// 32 above the rule; [leading] at the start, [trailing] pushed to the end
/// (`.sp`), wrapping on a phone.
class KitFormFoot extends StatelessWidget {
  final List<Widget> leading;
  final List<Widget> trailing;

  /// The unit and syllabus panels' button rows (`style={{ borderTop: 0,
  /// paddingTop: 0 }}`): the same row with no rule and no gap of its own.
  final bool bare;
  final double top;

  const KitFormFoot({
    super.key,
    this.leading = const [],
    this.trailing = const [],
    this.bare = false,
    this.top = 32,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: EdgeInsets.only(top: top),
      padding: EdgeInsets.only(top: bare ? 0 : 20),
      decoration: bare
          ? null
          : BoxDecoration(border: Border(top: BorderSide(color: t.rule))),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: leading,
          ),
          ...trailing,
        ],
      ),
    );
  }
}

/// `.st-danger` — the form's one destructive action (Delete program): an
/// outlined 34-high control, the label and its glyph in `--critical-text`, on
/// no fill. Quieter than §6.1's filled danger, because it sits at the end of a
/// settings form rather than in a confirmation.
class KitFormDangerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const KitFormDangerButton(this.label,
      {super.key, required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? AppSpacing.heldOpacity : 1,
        child: GestureDetector(
          onTap: onPressed,
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            decoration: BoxDecoration(
              borderRadius: AppRadius.controlR(34),
              border: Border.all(color: t.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              KitGlyph(icon, size: 14, color: t.criticalText),
              const SizedBox(width: 7),
              Text(label,
                  style: _sans(13, t.criticalText)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.st-fields` / `.st-caps` — a two-column grid of fields (18 between rows,
/// 20 between columns) that stacks to one column below the compact width
/// (web: 900; this client's one breakpoint: 768). [wide] children span both
/// columns (`.st-fields-wide`).
class KitFormGrid extends StatelessWidget {
  final List<Widget> children;
  final Set<int> wide;
  final double rowGap;

  const KitFormGrid(
      {super.key,
      required this.children,
      this.wide = const {},
      this.rowGap = 18});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final one = c.maxWidth < AppSpacing.compactWidth - 2 * 20;
        if (one) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) SizedBox(height: rowGap),
                children[i],
              ],
            ],
          );
        }
        // Grid placement: a wide child takes a row of its own; otherwise two
        // to a row, and one left alone keeps its column's width.
        final rows = <Widget>[];
        var i = 0;
        while (i < children.length) {
          if (wide.contains(i)) {
            rows.add(children[i]);
            i += 1;
            continue;
          }
          final pair = i + 1 < children.length && !wide.contains(i + 1);
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 20),
              Expanded(child: pair ? children[i + 1] : const SizedBox()),
            ],
          ));
          i += pair ? 2 : 1;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var r = 0; r < rows.length; r++) ...[
              if (r > 0) SizedBox(height: rowGap),
              rows[r],
            ],
          ],
        );
      });
}

/// `.st-note` with its `.st-inline-link` — a sentence about what just happened
/// and the one way on ("… Back to programs"): the note role, the link in
/// `--link` underlined in `--link-decor`.
class KitFormNote extends StatefulWidget {
  final String text;
  final String? link;
  final VoidCallback? onLink;

  const KitFormNote(this.text, {super.key, this.link, this.onLink});

  @override
  State<KitFormNote> createState() => _KitFormNoteState();
}

class _KitFormNoteState extends State<KitFormNote> {
  final _tap = TapGestureRecognizer();

  @override
  void dispose() {
    _tap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    _tap.onTap = widget.onLink;
    final base = KitText.note(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text.rich(TextSpan(style: base, children: [
        TextSpan(text: widget.text),
        if (widget.link != null) ...[
          const TextSpan(text: ' '),
          TextSpan(
            text: widget.link,
            recognizer: _tap,
            style: base.copyWith(
              color: t.link,
              decoration: TextDecoration.underline,
              decorationColor: t.linkDecor,
            ),
          ),
        ],
      ])),
    );
  }
}
