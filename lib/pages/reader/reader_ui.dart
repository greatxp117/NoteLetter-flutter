import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Shared reader-panel chrome — the Flutter mirror of the web reader's
/// `.panel-intro` / `.eyebrow` / `.panel-note` / `.browse-empty` primitives,
/// resolved against the design tokens (`AppColors`) for the active brightness.
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
  Color get critical => dark ? AppColors.criticalDark : AppColors.critical;
  Color get rule => dark ? AppColors.ruleDark : AppColors.ruleLight;
  Color get subtle =>
      dark ? AppColors.subtleForegroundDark : AppColors.subtleForegroundLight;
  Color get sunken =>
      dark ? AppColors.surfaceSunkenDark : AppColors.surfaceSunkenLight;
  Color get positive => dark ? AppColors.positiveDark : AppColors.positive;

  /// Small uppercase section label (web `.eyebrow`).
  Widget eyebrow(String text) => Text(
        text.toUpperCase(),
        style: TextStyle(fontFamily: 'Geist', 
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: muted,
        ),
      );

  /// Muted explanatory paragraph (web `.panel-note`).
  Widget note(String text) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          text,
          style: TextStyle(fontFamily: 'Geist', 
              fontSize: 14, height: 1.55, color: muted),
        ),
      );

  Widget intro(String eyebrowText, [String? noteText]) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            eyebrow(eyebrowText),
            if (noteText != null) note(noteText),
          ],
        ),
      );

  /// Centered empty state (web `.browse-empty`).
  Widget empty(IconData icon, String title, String sub, {Widget? action}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: Column(
            children: [
              Icon(icon, size: 26, color: muted),
              const SizedBox(height: 12),
              Text(title,
                  style: AppTheme.serif(
                      fontSize: 18, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 6),
              Text(sub,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Geist', fontSize: 13, color: muted)),
              if (action != null) ...[const SizedBox(height: 16), action],
            ],
          ),
        ),
      );
}
