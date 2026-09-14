import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// Shared reader-panel chrome.
///
/// Two jobs, and they are different: the getters are a **token facade** for the
/// brightness (the `Html` style map needs a `Tokens` object, and six panels
/// need the same handful of colours); the builders below are the reader's own
/// **component layer** — the panel intro, the panel note, the empty state and
/// the panel strip.
///
/// Every one of those builders now composes its type from `KitText`. They used
/// to spell their own `TextStyle`s, which is inline composition one indirection
/// away: `note()` set the summary in the UI sans at `--fg-muted` where the
/// reference sets it as an italic serif lede, and `eyebrow()` was an 11px sans
/// at a different tracking from `.eyebrow`. A screen that reaches for a local
/// helper instead of the kit drifts exactly as far as one that writes the style
/// inline (ADR-041).
///
/// The panel strip lives here rather than in `lib/widgets/kit/` on purpose:
/// §6.8 says the segmented control is **not tabs** and no kit pattern draws
/// one, so this is the reader's own device and naming it a kit pattern would
/// be a `/contract-change`, not a refactor.
class ReaderUi {
  final bool dark;
  ReaderUi(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark;

  /// The token object for this brightness, so a caller that needs a token this
  /// facade does not name (the Html style map) does not add a third copy.
  Tokens get tokens => dark ? Tokens.dark : Tokens.light;

  Color get muted =>
      dark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;
  Color get border => dark ? AppColors.borderDark : AppColors.borderLight;
  Color get card => dark ? AppColors.cardDark : AppColors.cardLight;
  Color get surface => dark ? AppColors.secondaryDark : AppColors.secondaryLight;
  Color get fg => dark ? AppColors.foregroundDark : AppColors.foregroundLight;
  Color get primary => dark ? AppColors.primaryDark : AppColors.primary;
  Color get accentFg =>
      dark ? AppColors.primaryForegroundDark : AppColors.primaryForeground;
  // Both of these used to be pinned to their light steps — `critical` under a
  // comment claiming it is "token-identical to brick in both themes", true
  // until 4.21.0 (ADR-057) made all three severities flip. In dark it resolved
  // to the ACCENT, so the five rules that draw error text in the reader drew it
  // in the same vermilion as a primary button.
  Color get criticalText =>
      dark ? AppColors.criticalTextDark : AppColors.criticalTextLight;
  Color get rule => dark ? AppColors.ruleDark : AppColors.ruleLight;
  Color get subtle =>
      dark ? AppColors.subtleForegroundDark : AppColors.subtleForegroundLight;
  Color get sunken =>
      dark ? AppColors.surfaceSunkenDark : AppColors.surfaceSunkenLight;
  Color get positive => dark ? AppColors.positiveDark : AppColors.positive;

  /// The section label opening a panel (web `.eyebrow`) — the kit's type role,
  /// not a local approximation of it.
  Widget eyebrow(String text) => Eyebrow(text);

  /// The explanatory paragraph under a panel's eyebrow (web `.panel-note`):
  /// **italic serif at `--fg-lede`**, 15/23, capped at the reference's 64ch.
  ///
  /// This is a lede, and it was the UI sans at `--fg-muted` here until 4.54.1 —
  /// a standfirst in the body face is the second-most common way a screen stops
  /// looking like this app while every colour in it stays correct (§2.1).
  Widget note(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Lede(text, fontSize: 15, height: 23, maxWidth: 480),
      );

  Widget intro(String eyebrowText, [String? noteText]) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow(eyebrowText),
            if (noteText != null) note(noteText),
          ],
        ),
      );

  /// §7 — the empty state, from the kit. The [action] is the panel's offer and
  /// becomes the pattern's action row: an empty state is an offer, not an
  /// apology, and a centred sentence saying "nothing here yet" is not this
  /// pattern.
  Widget empty(IconData icon, String title, String sub, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: KitEmptyState(
          icon: icon,
          title: title,
          standfirst: sub,
          actions: action == null ? const [] : [action],
        ),
      );
}

/// One panel in the reader's strip.
class ReaderPanel {
  final String id;
  final String label;
  final IconData icon;

  /// The mono chip trailing the label — the Original panel carries the
  /// document's own `type`. Null on every other panel.
  final String? count;

  const ReaderPanel(this.id, this.label, this.icon, {this.count});
}

/// The reader's panel strip (web `.src-tabs`).
///
/// **The selection is an underline, not a fill.** The reference draws a quiet
/// row of sans labels over a 1px `--rule`, with a 2px `--accent` bar under the
/// selected one and the label moving `--fg-muted` → `--fg`; this client drew
/// six filled accent pills, which reads as a row of buttons rather than as the
/// chapter divisions of one document.
///
/// The row **scrolls rather than compressing its labels**: a tab label is a
/// name, and "Speed read" broken over two lines makes the strip two rows tall
/// and reads as two tabs.
class ReaderPanelTabs extends StatelessWidget {
  final List<ReaderPanel> panels;
  final String selected;
  final ValueChanged<String> onSelect;

  const ReaderPanelTabs({
    super.key,
    required this.panels,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final p in panels)
              _Tab(
                panel: p,
                on: p.id == selected,
                onTap: () => onSelect(p.id),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final ReaderPanel panel;
  final bool on;
  final VoidCallback onTap;

  const _Tab({required this.panel, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = on ? t.fg : t.fgMuted;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 12),
        // The selected bar is a BOTTOM BORDER, not a sized bar: the strip
        // scrolls horizontally, so its children are laid out with an unbounded
        // width and a `Container(height: 2)` with no child collapses to nothing
        // there — the underline was drawn and invisible in the first pair.
        // A border is sized by the box it is on, which is sized by the label.
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: on ? t.accent : const Color(0x00000000),
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(panel.icon, size: 16, color: fg),
            const SizedBox(width: 8),
            Text(
              panel.label,
              softWrap: false,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
            if (panel.count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                decoration: BoxDecoration(
                  color: on ? t.accentChipBg : t.surfaceSunken,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  panel.count!,
                  style: KitText.capsLabel(
                    context,
                    fontSize: 10,
                    letterSpacing: 0.04,
                    color: on ? t.accentChipFg : t.fgMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
