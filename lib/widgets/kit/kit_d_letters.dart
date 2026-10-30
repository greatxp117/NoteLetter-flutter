/// Direction D parts for F-144's letters screens (component-kit §26–§42;
/// screens/letters.md §Composition *Letters*, *A letter*, *The readings day*).
/// Web `pages/LettersView.jsx`, `pages/letters/LetterRead.jsx`,
/// `PinnedSources.jsx`, `ScriptureDayView.jsx`; sheet `styles/app-letters.css`.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitButton;
import 'kit_d_format.dart';
import 'kit_d_frame.dart' show KitContentsItem, KitSections;
import 'kit_d_home.dart' show KitLetterPassages;
import 'kit_d_letter.dart';
import 'kit_d_parts.dart';
import 'kit_d_shelf.dart' show KitDNote;
import 'kit_failure.dart' show KitFailureInline;
import 'kit_letter.dart' show KitLetterBadge;

// ── Letters: the latest letter ──────────────────────────────────────────────

/// `.ed-kicker` — the latest letter's line on Letters (Home draws a letterhead
/// instead): mono 11/0.16em caps in `--fg-muted`, [lead] 500 in
/// `--accent-text` (`The letter · No. {n}`), the [day], and [right] at the
/// trailing edge in `--fg-subtle` (the figures). Wraps `6px 16px`.
class KitLetterKicker extends StatelessWidget {
  final String lead;
  final String? day;
  final String? right;

  const KitLetterKicker({super.key, required this.lead, this.day, this.right});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    TextStyle s(Color c, {FontWeight w = FontWeight.w400}) => AppTheme.mono(
      fontSize: 11,
      height: 16 / 11,
      fontWeight: w,
      letterSpacing: 0.16 * 11,
      color: c,
    );
    final lead = Text(
      this.lead.toUpperCase(),
      style: s(t.accentText, w: FontWeight.w500),
    );
    final day = this.day == null
        ? null
        : Text(this.day!.toUpperCase(), style: s(t.fgMuted));
    final right = this.right == null
        ? null
        : Text(this.right!.toUpperCase(), style: s(t.fgSubtle));
    final head = Wrap(
      spacing: 16,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [lead, ?day],
    );
    if (right == null) return head;
    // `margin-left: auto` on the figures: they keep the line's trailing edge
    // beside the lead when they fit, and drop to a line of their own — still
    // trailing — when they do not (the phone's kicker).
    final scaler = MediaQuery.textScalerOf(context);
    double width(Text x) {
      final tp = TextPainter(
        text: TextSpan(text: x.data, style: x.style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final w = tp.width;
      tp.dispose();
      return w;
    }

    final need =
        width(lead) + (day == null ? 0 : 16 + width(day)) + 16 + width(right);
    return LayoutBuilder(
      builder: (context, c) => need <= c.maxWidth
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: head),
                const SizedBox(width: 16),
                right,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                head,
                const SizedBox(height: 6),
                Align(alignment: Alignment.centerRight, child: right),
              ],
            ),
    );
  }
}

/// `.ed-head` on Letters (not in Home's paper): serif 600
/// `clamp(36px, 5cqi, 62px)`/1.02, `-0.026em`, letterpressed, left, 14 under
/// the kicker. [width] is the letter's own (`cqi`).
class _Head extends StatelessWidget {
  final String text;
  final double width;
  const _Head(this.text, {required this.width});

  @override
  Widget build(BuildContext context) {
    final size = (0.05 * width).clamp(36.0, 62.0);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Semantics(
        header: true,
        child: Text(
          text,
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
    );
  }
}

/// `.ed-deck` — serif italic 20/31 `--fg-lede`, at most about 62 characters,
/// 14 under the head.
class _Deck extends StatelessWidget {
  final String text;
  const _Deck(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 62 * 20 * 0.48),
      child: Text(
        text,
        style: AppTheme.serif(
          fontSize: 20,
          height: 31 / 20,
          fontStyle: FontStyle.italic,
          color: Tokens.of(context).fgLede,
          opsz: 22,
        ),
      ),
    ),
  );
}

/// What [KitLatestLetter] shows.
enum KitLatestState { loading, none, refused, built }

/// Letters' latest letter (web `LatestLetter`, the prototype's `LatestD`): the
/// letter card under its **kicker** — `The letter · No. {n}`, the day, and at
/// the right its figures — then the title, the lede, ALL its passages (kit
/// `LetterPassages`) and *Read the letter* (secondary) · *Letter settings*
/// (ghost). Loading is the kicker over skeleton lines; none yet and a refused
/// archive read are the kicker over their head (the failure itself is §14.1
/// under *Sent*, INV-24).
class KitLatestLetter extends StatelessWidget {
  final KitLatestState state;
  final KitLetterParts? parts;

  /// `{n} passages · ~{n+1} min read`, or null without `chunk_ids` (ADR-109).
  final String? figures;
  final VoidCallback? onRead;
  final VoidCallback onSettings;
  final DateTime? now;

  const KitLatestLetter({
    super.key,
    required this.state,
    required this.onSettings,
    this.parts,
    this.figures,
    this.onRead,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final p = parts;
    final built = state == KitLatestState.built && p != null;
    final kicker = KitLetterKicker(
      lead: 'The letter${built && p.no != null ? ' · No. ${p.no}' : ''}',
      day: built
          ? (kitIsToday(p.at, now) ? 'This morning' : kitLongDay(p.at ?? 0))
          : null,
      right: built ? figures : null,
    );
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : 800.0;
        final children = <Widget>[kicker];
        switch (state) {
          case KitLatestState.loading:
            children.add(
              const KitSkeletonLines(
                top: 22,
                lines: [KitSkelLine(0.5, true), KitSkelLine(0.7)],
              ),
            );
          case KitLatestState.none:
            children
              ..add(_Head('No letter yet', width: w))
              ..add(
                const _Deck('It draws from what’s in your library so far.'),
              );
          case KitLatestState.refused:
            children.add(_Head('Your letters could not be read', width: w));
          case KitLatestState.built:
            if (p == null) break;
            children.add(_Head(p.title, width: w));
            if (p.lede.isNotEmpty) children.add(_Deck(p.lede));
            children.add(KitLetterPassages(sections: p.sections));
            children.add(
              Container(
                margin: const EdgeInsets.only(top: 26),
                padding: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Tokens.of(context).rule),
                  ),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    KitButton.secondary(
                      'Read the letter',
                      key: const ValueKey('d-letters-read'),
                      icon: Icons.mail_outline,
                      onPressed: onRead,
                    ),
                    KitButton.ghost(
                      'Letter settings',
                      key: const ValueKey('d-letters-settings'),
                      icon: Icons.tune,
                      onPressed: onSettings,
                    ),
                  ],
                ),
              ),
            );
        }
        return Semantics(
          container: true,
          liveRegion: state == KitLatestState.loading,
          child: Column(
            key: const ValueKey('d-letters-latest'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }
}

// ── Letters: the send line ──────────────────────────────────────────────────

/// `.dp-send-line` — what Send now answered, under the masthead (beside where
/// the action is pressed: the rail, a phone's tab bar): [note] — queued, or
/// the cooldown's calm caption — in serif italic 15/23 `--fg-lede`, or
/// [failure] as §14.2. 18 under the rule, at most 72ch. **Brought into view
/// when it arrives** (web `scrollIntoView({block: 'nearest'})`): a refusal a
/// screen above the reader's place is one nobody sees (ADR-056).
class KitSendLine extends StatefulWidget {
  final String? note;
  final String? failure;

  const KitSendLine({super.key, this.note, this.failure})
    : assert(note != null || failure != null);

  @override
  State<KitSendLine> createState() => _KitSendLineState();
}

class _KitSendLineState extends State<KitSendLine> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  Future<void> _reveal() async {
    if (!mounted) return;
    final still = KitD.still(context);
    final d = still ? Duration.zero : const Duration(milliseconds: 240);
    // `nearest`: above the view → its top to the top; below → its foot to the
    // foot; already in view → nothing moves.
    await Scrollable.ensureVisible(
      context,
      duration: d,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
    );
    if (!mounted) return;
    await Scrollable.ensureVisible(
      context,
      duration: d,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final f = widget.failure;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 72 * 15 * 0.5),
            child: f != null
                ? KitFailureInline(f)
                : Text(
                    widget.note!,
                    style: AppTheme.serif(
                      fontSize: 15,
                      height: 23 / 15,
                      fontStyle: FontStyle.italic,
                      color: t.fgLede,
                      opsz: 16,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ── Letters: the archive by month ───────────────────────────────────────────

/// `.lx-reg-h` over a month of letters: `{Month YYYY}` serif 600 22/1.2 over a
/// 1px `--fg` rule, its [count] in mono 11 `--fg-subtle`. [first]: no space
/// above (straight under *Sent*'s head); otherwise 42 (`34 + 8`).
class KitLetterMonthHead extends StatelessWidget {
  final String label;
  final String count;
  final bool first;

  const KitLetterMonthHead(
    this.label, {
    super.key,
    required this.count,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: EdgeInsets.only(top: first ? 0 : 42),
      padding: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.fg)),
      ),
      child: Semantics(
        header: true,
        child: Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(
              label,
              style: AppTheme.serif(
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: t.fg,
                opsz: 24,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                count,
                style: AppTheme.mono(
                  fontSize: 11,
                  letterSpacing: 0.04 * 11,
                  color: t.fgSubtle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.dp-lrow` — one sent letter in the archive (§36's row hover): its [no]
/// (italic serif 24 `--accent-text`, right in a 52 cell; blank for a letter
/// without one), the [title] (serif 500 17.5/23, one line) over its [lede]
/// (italic serif 14.5/21 `--fg-lede`, one line), the [figures] and the [date]
/// (mono 11 `--fg-subtle`), and the pill badge — `gap: 4px 18px`, a `--rule`
/// under. In a column 700 or narrower: the number (20, a 40 cell), the text
/// with the badge under it, the date — no figures. [onTap] null: an
/// informational row (generating, empty, failed — ADR-011), no hover.
class KitLetterArchiveRow extends StatelessWidget {
  final String no;
  final String title;
  final String? lede;
  final String? figures;
  final String date;
  final String badge;
  final bool settled;
  final VoidCallback? onTap;

  const KitLetterArchiveRow({
    super.key,
    required this.no,
    required this.title,
    required this.date,
    required this.badge,
    required this.settled,
    this.lede,
    this.figures,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth <= 700;
        final mono = AppTheme.mono(
          fontSize: 11,
          height: 16 / 11,
          letterSpacing: 0.03 * 11,
          color: t.fgSubtle,
        );
        final number = SizedBox(
          width: narrow ? 40 : 52,
          child: Text(
            no,
            textAlign: TextAlign.right,
            maxLines: 1,
            softWrap: false,
            style: AppTheme.serif(
              fontSize: narrow ? 20 : 24,
              height: 1,
              fontStyle: FontStyle.italic,
              color: t.accentText,
              opsz: 36,
            ),
          ),
        );
        final badge = KitLetterBadge(this.badge, settled: settled, lineBox: 24);
        final body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.serif(
                fontSize: 17.5,
                height: 23 / 17.5,
                fontWeight: FontWeight.w500,
                color: t.fg,
                opsz: 18,
              ),
            ),
            if (lede != null && lede!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                lede!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.serif(
                  fontSize: 14.5,
                  height: 21 / 14.5,
                  fontStyle: FontStyle.italic,
                  color: t.fgLede,
                ),
              ),
            ],
            if (narrow) ...[const SizedBox(height: 4), badge],
          ],
        );
        final date = Text(
          this.date,
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.right,
          style: mono,
        );
        final row = Container(
          padding: const EdgeInsets.fromLTRB(0, 14, 8, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: narrow
                ? [
                    number,
                    const SizedBox(width: 18),
                    Expanded(child: body),
                    const SizedBox(width: 18),
                    date,
                  ]
                : [
                    number,
                    const SizedBox(width: 18),
                    Expanded(child: body),
                    if (figures != null) ...[
                      const SizedBox(width: 18),
                      Text(figures!, maxLines: 1, softWrap: false, style: mono),
                    ],
                    const SizedBox(width: 18),
                    SizedBox(width: 64, child: date),
                    const SizedBox(width: 18),
                    badge,
                  ],
          ),
        );
        return KitRowHover(onTap: onTap, label: title, child: row);
      },
    );
  }
}

// ── A letter ────────────────────────────────────────────────────────────────

/// The letter as it was sent, the column's width (screens/letters.md
/// §Composition *A letter*): a letterheaded body lifted as a sheet — a 1px
/// `--border`, `--r-xl` (`--r-lg` in a column 600 or narrower) and
/// `--shadow-2`; its own ground takes the radius. **On a phone** (a window
/// 680 or narrower) it takes the screen's full width, unframed — through the
/// page's 18px sides — as the pre-D reader gave it: its 640px table needs
/// every pixel at 320.
class KitLiftedLetter extends StatelessWidget {
  final Widget child;

  /// The page's side on a phone, given back to the letter.
  static const double phoneSide = 18;

  const KitLiftedLetter({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (KitD.phone(context)) {
      return LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth + 2 * phoneSide;
          return OverflowBox(
            key: const ValueKey('d-letter-sheet'),
            fit: OverflowBoxFit.deferToChild,
            minWidth: w,
            maxWidth: w,
            alignment: Alignment.topCenter,
            child: child,
          );
        },
      );
    }
    final t = Tokens.of(context);
    return LayoutBuilder(
      builder: (context, c) {
        final r = c.maxWidth <= 600 ? AppRadius.lg : AppRadius.xl;
        return Container(
          key: const ValueKey('d-letter-sheet'),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(r),
            boxShadow: AppShadows.s2,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(math.max(0, r - 1)),
            child: child,
          ),
        );
      },
    );
  }
}

/// A letter's running head on a phone (screens/letters.md §Composition *A
/// letter*): `№ {n} · {passage} · {i} of {n}` — the letter's number (just
/// `№` without one) in accent serif, the passage the reader is in, and where
/// it stands; before the letter's passages are read (or for a letter with
/// none) its [title] and `{count} passages`.
class KitLetterPeek extends StatelessWidget {
  final String? no;
  final String title;
  final int? count;
  final List<KitContentsItem> items;
  final KitSections sections;

  const KitLetterPeek({
    super.key,
    required this.no,
    required this.title,
    required this.items,
    required this.sections,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final serif = AppTheme.serif(
      fontSize: 16.5,
      height: 22 / 16.5,
      fontWeight: FontWeight.w600,
      color: t.fg,
      opsz: 18,
    );
    return ListenableBuilder(
      listenable: sections,
      builder: (context, _) {
        final i = math.max(
          0,
          items.indexWhere((s) => s.id == sections.current),
        );
        final has = items.isNotEmpty;
        final tail = has
            ? ('${i + 1}', ' of ${items.length}')
            : (count == null ? null : ('$count', ' passages'));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              no == null ? '№' : '№ $no',
              style: serif.copyWith(color: t.accentText),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                has ? items[i].label : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: serif,
              ),
            ),
            if (tail != null) ...[
              const SizedBox(width: 6),
              Text.rich(
                TextSpan(
                  text: tail.$1,
                  style: AppTheme.mono(fontSize: 11.5, color: t.fg),
                  children: [
                    TextSpan(
                      text: tail.$2,
                      style: AppTheme.mono(fontSize: 11.5, color: t.fgSubtle),
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

// ── Letters' sheet: pinned for the next letter ──────────────────────────────

/// `.pinned` on the Letters sheet (§Pinned sources): the mono caps label, what
/// the next letter carries ([sentence], serif italic 14/21 — absent while the
/// cap is unread), the [rows], and a refused unpin as §14.2 under them.
class KitPinnedBlock extends StatelessWidget {
  final String? sentence;
  final List<Widget> rows;
  final String? error;

  const KitPinnedBlock({
    super.key,
    required this.rows,
    this.sentence,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      key: const ValueKey('d-pinned'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitDLabel('Pinned for the next letter'),
        if (sentence != null) KitDNote(sentence!, top: 0),
        const SizedBox(height: 6),
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: i == 0
                ? null
                : BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
            child: rows[i],
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: KitFailureInline(error!),
          ),
      ],
    );
  }
}

/// `.pinned-row` — the source's title (serif 15.5/22, one line; `--fg-muted`
/// when it is carried to the letter after — dimmed, never struck through),
/// its [note] (mono 10.5 `--fg-subtle`), and the labelled *Unpin*.
class KitPinnedRow extends StatelessWidget {
  final String title;
  final String? note;
  final bool overflow;
  final VoidCallback? onOpen;
  final bool busy;
  final VoidCallback onUnpin;

  const KitPinnedRow({
    super.key,
    required this.title,
    required this.onUnpin,
    this.note,
    this.overflow = false,
    this.onOpen,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final text = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.serif(
        fontSize: 15.5,
        height: 22 / 15.5,
        color: overflow ? t.fgMuted : t.fg,
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              onOpen == null
                  ? text
                  : KitDTap(
                      onTap: onOpen,
                      label: title,
                      builder: (context, hover, focus) => text,
                    ),
              if (note != null)
                Text(
                  note!,
                  style: AppTheme.mono(
                    fontSize: 10.5,
                    height: 15 / 10.5,
                    letterSpacing: 0.04 * 10.5,
                    color: t.fgSubtle,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        KitUnpinButton(title: title, busy: busy, onTap: onUnpin),
      ],
    );
  }
}

/// `.pinned-unpin` — the only undo a pin has, so a labelled control at a real
/// hit target: 32 tall, `0 12 0 10`, a 1px `--border` on `--surface`, the
/// height's radius, a 13px × and mono 11/0.04em `--fg-muted`. **Held** while
/// its write is in flight (§6.1, ruled 2026-10-14): *Unpinning…*, steady at
/// `--held-opacity`, no pointer events — never Material's disabled grey.
class KitUnpinButton extends StatelessWidget {
  final String title;
  final bool busy;
  final VoidCallback onTap;

  const KitUnpinButton({
    super.key,
    required this.title,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      enabled: !busy,
      child: IgnorePointer(
        ignoring: busy,
        child: Opacity(
          opacity: busy ? AppSpacing.heldOpacity : 1,
          child: KitDTap(
            onTap: onTap,
            label: 'Unpin $title',
            builder: (context, hover, focus) {
              final fg = hover ? t.fg : t.fgMuted;
              return Container(
                height: 32,
                padding: const EdgeInsets.fromLTRB(10, 0, 12, 0),
                decoration: BoxDecoration(
                  color: hover ? t.hover : t.surface,
                  border: Border.all(
                    color: focus
                        ? t.accent
                        : (hover ? t.borderStrong : t.border),
                    width: focus ? 2 : 1,
                  ),
                  borderRadius: AppRadius.controlR(32),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 13, color: fg),
                    const SizedBox(width: 6),
                    Text(
                      busy ? 'Unpinning…' : 'Unpin',
                      style: AppTheme.mono(
                        fontSize: 11,
                        letterSpacing: 0.04 * 11,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── The readings day ────────────────────────────────────────────────────────

/// `.rl-fnote.dp-scday-cycle` — the day's cycle line under the readings day's
/// standfirst: sans 11.5/17 `--fg-subtle`, 10 under it.
class KitDayCycle extends StatelessWidget {
  final String text;
  const KitDayCycle(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 11.5,
        height: 17 / 11.5,
        color: Tokens.of(context).fgSubtle,
      ),
    ),
  );
}

/// §14.2 where a D note would stand — [top] under what it speaks of (10, as
/// `.dp-note`): Letters' delivery switch refused (`.d-lq-err`), the readings
/// letter's settings unread (`.letters-err`, 24).
class KitDFailureNote extends StatelessWidget {
  final String text;
  final double top;
  const KitDFailureNote(this.text, {super.key, this.top = 10});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: KitFailureInline(text),
  );
}
