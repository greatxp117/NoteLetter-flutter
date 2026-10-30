import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitButton, KitSwitch;
import 'kit_d_frame.dart';
import 'kit_d_parts.dart';
import 'kit_failure.dart' show KitFailureInline;
import 'kit_shell.dart';

/// A shelf's stored colour for this theme — its name or legacy hex — and an
/// unrecognised one the muted text colour (web `shelfColorVar`).
Color kitShelfColorOf(BuildContext context, String? token) {
  final t = Tokens.of(context);
  return AppColors.shelfColor(token, dark: t.isDark) ?? t.fgSubtle;
}

// Direction D's shelf parts (`screens/library.md` §Composition — Shelves and a
// shelf, the shelf map's Composition): the sheet's shelf row (web `.lx-shelf`)
// that the Library's Shelf facet, the Shelves index, a shelf's Sub-shelves and
// the map's *Go to a shelf* all draw; the shelf's mark (four spines); the
// running head's swatch; the sheet's quiet note (`.dp-note`).

/// The 8×11 swatch a shelf row and a running head lead with (`.lx-shelf i`,
/// `.dp-peek-sw`): the shelf's colour, `--border-strong` without one
/// (*Unshelved*), radius `1px 2px 2px 1px`. A search result's shelf draws it
/// 10 tall ([height], `.dp-res-s i`).
class KitShelfSwatch extends StatelessWidget {
  final Color? color;
  final double height;
  const KitShelfSwatch(this.color, {super.key, this.height = 11});

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: height,
    decoration: BoxDecoration(
      color: color ?? Tokens.of(context).borderStrong,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(1),
        bottomLeft: Radius.circular(1),
        topRight: Radius.circular(2),
        bottomRight: Radius.circular(2),
      ),
    ),
  );
}

/// One shelf in a sheet (web `.lx-shelf`): an 8×11 swatch of its colour, its
/// title in serif 16 `--fg-muted`, its count in mono 11 `--fg-subtle` at the
/// trailing edge, `8px 0` over a 1px `--rule`. [sub] (a sub-shelf in tree
/// order) is set 18 in and italic. [on] is the current one: `--fg` 600 with
/// the 6px accent dot 16 to its left. [create] is *New sub-shelf*'s form
/// (`.dp-new`): the `+` instead of a swatch, italic `--fg-muted`, gap 8, no
/// count. Stacked or in the running head the rows run as lines ([KitShelfRows]
/// draws them): no rule, `6px 0` (`10px 0` docked), a sub-shelf not indented
/// in the running head.
///
/// Choosing a row folds the running head where the page asked (web `FOLD`);
/// [chosenInert]: pressing the chosen row does nothing (a facet's rule).
class KitShelfRow extends StatelessWidget {
  final String title;
  final Color? color;
  final String? count;
  final bool sub;
  final bool on;
  final bool create;
  final bool chosenInert;
  final VoidCallback onTap;

  const KitShelfRow({
    super.key,
    required this.title,
    this.color,
    this.count,
    this.sub = false,
    this.on = false,
    this.chosenInert = false,
    required this.onTap,
  }) : create = false;

  /// *New sub-shelf* (`.lx-shelf.dp-new`).
  const KitShelfRow.create({
    super.key,
    required this.title,
    required this.onTap,
  }) : color = null,
       count = null,
       sub = false,
       on = false,
       chosenInert = false,
       create = true;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final scope = KitSheetScope.maybeOf(context);
    final lines = scope?.lines ?? false;
    final dock = scope?.dock ?? false;
    return KitDTap(
      label: title,
      selected: create ? null : on,
      onTap: () {
        if (on && chosenInert) return;
        onTap();
        KitSheetScope.pick(context);
      },
      builder: (context, hover, focus) {
        final style = AppTheme.serif(
          fontSize: 16,
          fontWeight: on ? FontWeight.w600 : FontWeight.w400,
          fontStyle: sub || create ? FontStyle.italic : FontStyle.normal,
          color: on || (hover && !create) ? t.fg : t.fgMuted,
        );
        final lead = create
            ? KitGlyph(Icons.add, size: 13, color: t.fgMuted)
            : KitShelfSwatch(color);
        final body = Row(
          mainAxisSize: lines ? MainAxisSize.min : MainAxisSize.max,
          children: [
            lead,
            SizedBox(width: create ? 8 : 10),
            if (lines)
              Text(title, style: style)
            else
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            if (count != null) ...[
              const SizedBox(width: 10),
              Text(
                count!,
                style: AppTheme.mono(fontSize: 11, color: t.fgSubtle),
              ),
            ],
          ],
        );
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: EdgeInsets.only(
                left: sub && !dock ? 18 : 0,
                top: lines ? (dock ? 10 : 6) : 8,
                bottom: lines ? (dock ? 10 : 6) : 8,
              ),
              decoration: lines
                  ? null
                  : BoxDecoration(
                      border: Border(bottom: BorderSide(color: t.rule)),
                    ),
              child: body,
            ),
            if (on)
              Positioned(
                left: -16,
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
            if (focus)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: t.accent, width: 2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A sheet's list of [KitShelfRow]s (web `.lx-shelves`): a column of ruled
/// rows beside the column, wrapping lines (gap `0 22px`) when the sheet is
/// stacked or is the running head — set 16 in, so the current row's dot has
/// room.
class KitShelfRows extends StatelessWidget {
  final List<Widget> children;
  const KitShelfRows({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final lines = KitSheetScope.maybeOf(context)?.lines ?? false;
    return Padding(
      padding: EdgeInsets.only(left: lines ? 16 : 0),
      child: lines
          ? Wrap(spacing: 22, children: children)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
    );
  }
}

/// The shelf's mark (web `ShelfSpines`, `.shelf-spines-mini`): four spines in
/// its colour, 5 wide and 2 apart in a 22px band, each at its own height and
/// opacity (.32–.88), rounded `1px 1px 0 0` at the top.
class KitShelfSpines extends StatelessWidget {
  final Color color;
  const KitShelfSpines(this.color, {super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Container(
              width: 5,
              height: 22 * (62 + ((i * 23) % 38)) / 100,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.32 + ((i * 7) % 5) * 0.14),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(1),
                ),
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// A shelf's sheet opens on its **mark** (`screens/library.md` §A shelf; the
/// identity block's form, kit §29, `.rx-d-id.dp-shelf-id`): the four spines
/// beside a mono caps [kicker] (*Shelf*, *Shelf · auto-created*,
/// `--accent-text` 10.5/`0.14em`) over the shelf's [name] in serif 600 17/22
/// (two lines at most), a `--rule` 18 under it. The running head does not draw
/// it — the masthead above says it.
class KitShelfIdentity extends StatelessWidget {
  final Color color;
  final String kicker;
  final String name;

  const KitShelfIdentity({
    super.key,
    required this.color,
    required this.kicker,
    required this.name,
  });

  @override
  Widget build(BuildContext context) {
    if (KitSheetScope.maybeOf(context)?.dock ?? false) {
      return const SizedBox.shrink();
    }
    final t = Tokens.of(context);
    return Container(
      key: const ValueKey('shelf-identity'),
      padding: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          KitShelfSpines(color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kicker.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    fontSize: 10.5,
                    letterSpacing: 0.14 * 10.5,
                    color: t.accentText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 17,
                    height: 22 / 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.01 * 17,
                    color: t.fg,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A sheet's quiet sentence (web `.dp-note`): serif italic 14/21 `--fg-lede`,
/// 10 above — *None yet.* where a list has nothing to say; also LetterQuick's
/// activation hint and what the send did, a letter's delivery note (F-144).
/// [top] is the space above (10; 0 where the host already spaces it).
class KitDNote extends StatelessWidget {
  final String text;
  final double top;
  const KitDNote(this.text, {super.key, this.top = 10});

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Text(
      text,
      style: AppTheme.serif(
        fontSize: 14,
        height: 21 / 14,
        fontStyle: FontStyle.italic,
        color: Tokens.of(context).fgLede,
      ),
    ),
  );
}

// ── Shelf settings, in the panel (`screens/library.md` §A shelf) ────────────

/// A stacked panel row's label (web `.d-pnl .ss-label`): mono caps 10.5,
/// `0.12em`, `--fg-subtle` — *Name*, *Color*, *Inside*, *Split*, and the
/// letter's *How prominently*.
class KitDFieldLabel extends StatelessWidget {
  final String text;
  const KitDFieldLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(
      text.toUpperCase(),
      style: AppTheme.mono(
        fontSize: 10.5,
        letterSpacing: 0.12 * 10.5,
        color: Tokens.of(context).fgSubtle,
      ),
    ),
  );
}

/// A panel row stacked (web `.d-pnl .shelf-settings .ss-row`): its
/// [KitDFieldLabel] over the control, 8 apart, the control full width; a
/// refusal under it; [top] 16 between rows.
class KitDFieldRow extends StatelessWidget {
  final String label;
  final Widget child;
  final String? error;
  final double top;

  const KitDFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.error,
    this.top = 16,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitDFieldLabel(label),
        const SizedBox(height: 8),
        child,
        if (error != null) ...[
          const SizedBox(height: 8),
          KitFailureInline(error!),
        ],
      ],
    ),
  );
}

/// *In your letter* in Shelf settings (`screens/library.md` §A shelf's place
/// in the letter, ADR-122/185; web `.d-pnl .shelf-letter`), unboxed: *Feed
/// today's letter* (serif 600 16/22) over its sentence (sans 13/19
/// `--fg-muted`; *{Mode} by {shelf}.* after it while the shelf inherits), the
/// switch at the trailing edge; while on, *How prominently* — a §34 Switch,
/// *Lead* · *Mixed* — over its italic hint; *Use the parent's setting* while
/// the shelf has a mode of its own and a parent; a refusal (§14.2, dense).
/// Write before you move: [held] while a write is out, and [mode] is what the
/// tags read says, so the controls move only when the write comes back.
class KitShelfLetter extends StatelessWidget {
  /// The mode in force: `lead`, `mixed` or `muted`.
  final String mode;

  /// The shelf whose mode this one inherits, when it has none of its own.
  final String? inheritedFrom;
  final bool canInherit;
  final bool held;
  final String? error;

  /// `muted`, `mixed`, `lead`, or null (inherit: `letter_mode: null`).
  final ValueChanged<String?> onMode;

  const KitShelfLetter({
    super.key,
    required this.mode,
    required this.onMode,
    this.inheritedFrom,
    this.canInherit = false,
    this.held = false,
    this.error,
  });

  static String labelOf(String mode) => switch (mode) {
    'lead' => 'Lead',
    'muted' => 'Muted',
    _ => 'Mixed',
  };

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final on = mode != 'muted';
    final sentence =
        (on
            ? 'Passages from this shelf are eligible for your daily letter.'
            : 'This shelf is muted — its passages stay out of your letter.') +
        (inheritedFrom != null ? ' ${labelOf(mode)} by $inheritedFrom.' : '');
    final weight = mode == 'lead' ? 'lead' : 'mixed';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Feed today’s letter',
                    style: AppTheme.serif(
                      fontSize: 16,
                      height: 22 / 16,
                      fontWeight: FontWeight.w600,
                      color: t.fg,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sentence,
                    style: TextStyle(
                      fontFamily: AppTheme.fontSans,
                      fontSize: 13,
                      height: 19 / 13,
                      color: t.fgMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            KitSwitch(
              value: on,
              tooltip: 'Feed today’s letter',
              onChanged: held ? null : (v) => onMode(v ? 'mixed' : 'muted'),
            ),
          ],
        ),
        if (on) ...[
          const SizedBox(height: 14),
          const KitDFieldLabel('How prominently'),
          const SizedBox(height: 8),
          KitSlideSwitch<String>(
            key: const ValueKey('shelf-letter-weight'),
            label: 'How prominently',
            value: weight,
            held: held,
            onChanged: (v) => onMode(v),
            options: const [
              KitSlideOption('lead', 'Lead'),
              KitSlideOption('mixed', 'Mixed'),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            weight == 'lead'
                ? 'often opens your letter'
                : 'blended in with the rest',
            style: AppTheme.serif(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: t.fgSubtle,
            ),
          ),
        ],
        if (canInherit) ...[
          const SizedBox(height: 10),
          KitButton.ghost(
            'Use the parent’s setting',
            onPressed: held ? null : () => onMode(null),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          KitFailureInline(error!, dense: true),
        ],
      ],
    );
  }
}
