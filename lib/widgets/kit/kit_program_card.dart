import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_cards.dart';
import 'kit_shell.dart' show KitGlyph;

/// A study program on /study — web's `.st-prog` (StudyView.jsx ProgramCard,
/// app-study.css). Found 2026-10-14 by the study-wait frame against web's
/// phone frame: this client drew the notice and the hint ABOVE the controls,
/// the hint with no glyph and no rule, the chip on the title's right and a
/// 4-high accent meter on the sunken ground.
///
/// The body — the title and its [KitStudyChip] (`.st-prog-h`, wrapping), the
/// measured figure in mono (`.st-prog-fig`), a [KitStudyMeter], the schedule
/// and, when off, what off keeps — beside a side column of the switch,
/// [actions] in order (`.st-prog-side`, end-aligned, 12 apart). Below the one
/// breakpoint the side folds under the body as a wrapping row: web's 900,
/// this client's 768 (CLAUDE.md, one breakpoint). Then [notice] (§12) and the
/// hint (`.st-hint`: under a rule, the alert glyph beside the line), each
/// across the whole card. An off program lies on the page ground
/// (`.st-prog.is-off`).
class KitProgramCard extends StatelessWidget {
  final String title;

  /// The stored `status`, for the chip's dot; [statusLabel] is its words.
  final String status;
  final String statusLabel;
  final int introduced;
  final int units;
  final String schedule;
  final bool on;

  /// Said under the schedule when [on] is false (`.st-prog-due`).
  final String? offNote;

  /// `.st-sw-lbl` — the stored state in mono caps (or `…` while it moves).
  final String switchLabel;
  final Widget switchControl;

  /// Study now, then Settings.
  final List<Widget> actions;
  final Widget? notice;

  /// The hint's line: a widget of its own (§14.2's failure, §6.1's calm
  /// caption) wins over [hintText], which draws in `.st-note`'s face.
  final Widget? hint;
  final String? hintText;

  const KitProgramCard({
    super.key,
    required this.title,
    required this.status,
    required this.statusLabel,
    required this.introduced,
    required this.units,
    required this.schedule,
    required this.on,
    this.offNote,
    required this.switchLabel,
    required this.switchControl,
    required this.actions,
    this.notice,
    this.hint,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final sans13 = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 13,
      height: 19 / 13,
      color: t.fgMuted,
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              title,
              style: AppTheme.serif(
                fontSize: 22,
                height: 28 / 22,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.012 * 22,
                opsz: 24,
                color: t.fg,
              ),
            ),
            KitStudyChip(status: status, label: statusLabel),
          ],
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$introduced of $units'),
            TextSpan(
                text: ' passages introduced',
                style: TextStyle(color: t.fgSubtle)),
          ]),
          style: TextStyle(
            fontFamily: AppTheme.fontMono,
            fontSize: 12.5,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 8),
        KitStudyMeter(n: introduced, of: units),
        const SizedBox(height: 12),
        Text(schedule, style: sans13),
        if (!on && offNote != null) ...[
          const SizedBox(height: 6),
          Text(offNote!, style: sans13.copyWith(color: t.fgLede)),
        ],
      ],
    );

    final side = <Widget>[
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            switchLabel,
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10,
              letterSpacing: 0.12 * 10,
              color: t.fgSubtle,
            ),
          ),
          const SizedBox(width: 10),
          switchControl,
        ],
      ),
      ...actions,
    ];

    final hasHint = hint != null || hintText != null;
    return KitCard(
      onSurface: !on,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: body),
                const SizedBox(width: 28),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < side.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      side[i],
                    ],
                  ],
                ),
              ],
            )
          else ...[
            body,
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: side,
            ),
          ],
          if (notice != null) ...[
            // `.st-notice` cancels the grid's row gap down to the kit's 12.
            SizedBox(height: wide ? 12 : 16),
            notice!,
          ],
          if (hasHint) ...[
            SizedBox(height: (wide ? 28 : 16) + 4),
            Container(
              padding: const EdgeInsets.only(top: 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: t.rule)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    // Web's IcoAlert — the app's alert glyph.
                    child: KitGlyph(Icons.warning_amber_rounded,
                        size: 14, color: t.fgSubtle),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: hint ??
                        Text(
                          hintText!,
                          style: TextStyle(
                            fontFamily: AppTheme.fontSans,
                            fontSize: 12.5,
                            height: 18 / 12.5,
                            color: t.fgMuted,
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.st-chip`: every status in one neutral shell — sunken, mono caps — and
/// only the dot carries meaning (active positive, maintenance the seal, any
/// other the subtle ink), so an unknown value is legible, not alarming.
class KitStudyChip extends StatelessWidget {
  final String status;
  final String label;

  const KitStudyChip({super.key, required this.status, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final dot = switch (status) {
      'active' => t.positive,
      'maintenance' => t.seal,
      _ => t.fgSubtle,
    };
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.surfaceSunken,
        borderRadius: AppRadius.controlR(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTheme.fontMono,
              fontSize: 10,
              letterSpacing: 0.12 * 10,
              color: t.fgMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// `.st-meter`: progress and nothing else — `introduced_count` of
/// `unit_count`, both stored. 2 high on the rule, the filled part the seal.
class KitStudyMeter extends StatelessWidget {
  final int n;
  final int of;

  const KitStudyMeter({super.key, required this.n, required this.of});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fraction = of > 0 ? (n / of).clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(1),
      child: Container(
        height: 2,
        color: t.rule,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          heightFactor: 1,
          child: Container(color: t.seal),
        ),
      ),
    );
  }
}
