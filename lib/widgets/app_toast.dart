import 'package:flutter/material.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

enum ToastType { success, error, info }

/// The transient on-screen answer to an action the reader just took — the
/// reference's `ToastHost` (`src/shell/notify.jsx`).
///
/// **Every colour is a token, and the level colours are the reference's
/// `LEVEL_COLOR`**: success `--positive`, error `--critical-text`, info
/// `--fg-muted`, on a `--surface` card with a `--border` hairline and a 3px
/// level rule down the leading edge. Until 2026-10-05 this drew
/// `Colors.green.shade400` / `Colors.red.shade400` — Material palette steps in
/// no token file, identical in both themes — and `--accent` for info, which is
/// the colour the reference spent 4.30.0 (ADR-067) taking OFF its own toast:
/// a completed action and a failed one must not arrive in two shades of the
/// same hue. No gate could see it: LITERAL reads hex constructors and a
/// `Colors.green` is a name.
class AppToast {
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
  }) {
    final t = Tokens.of(context);

    final (Color level, IconData iconData) = switch (type) {
      ToastType.success => (t.positive, Icons.check_circle_outline),
      ToastType.error => (t.criticalText, Icons.error_outline),
      ToastType.info => (t.fgMuted, Icons.notifications_none),
    };

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          elevation: 0,
          content: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.border),
              borderRadius: AppRadius.mdR,
              boxShadow: AppShadows.s3,
            ),
            // The level rule is a child, not a `Border(left:)`: Flutter draws
            // a rounded border only when every side has the same colour.
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(color: level, child: const SizedBox(width: 3)),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(iconData, color: level, size: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              message,
                              style: TextStyle(
                                fontFamily: AppTheme.fontSans,
                                color: t.fg,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
  }
}
