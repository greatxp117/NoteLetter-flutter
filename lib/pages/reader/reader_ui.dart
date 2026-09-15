import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
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
