import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// §10 — the composer dock: a persistent input anchored to the bottom of a
/// scrolling pane.
///
/// **Required parts** — a **gradient scrim** rising from the page colour, so
/// content dissolves under the dock rather than colliding with it (the scrim
/// ignores pointer events; the composer does not) · the composer card ·
/// leading icon controls and a **filled circular send control**.
///
/// The input is **italic serif 17/24**, not the UI sans: a prompt is written,
/// not typed into a form field. Dropping that is one of the ways a screen stops
/// looking like this app while every colour in it stays correct.
///
/// It is a **dock, not a card** — it belongs to the frame, which is what makes
/// it right for a conversation (Ask, Support) and wrong for a form.
class KitComposerDock extends StatelessWidget {
  final TextEditingController controller;
  final String placeholder;

  /// Null disables the send control — the "nothing to send" and "in flight"
  /// states are both expressed this way.
  final VoidCallback? onSend;

  /// True while the endpoint has not answered. The control shows progress and
  /// **the text stays in the box** — the caller must not clear it until the
  /// send resolves (ADR-022).
  final bool busy;

  /// Leading icon controls, if the screen has any.
  final List<Widget> leading;

  /// Rendered above the composer, inside the dock: the endpoint's own
  /// rejection copy. It sits here rather than in the transcript because the
  /// text it refers to is still in the box.
  final String? error;

  final int? maxLength;
  final int minLines;
  final int maxLines;

  const KitComposerDock({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onSend,
    this.busy = false,
    this.leading = const [],
    this.error,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 5,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final gutter =
        compact ? AppSpacing.frameGutterCompact : AppSpacing.frameGutter;

    return Stack(
      children: [
        // The scrim: transparent → --bg, and pointer-transparent so the
        // content it dissolves stays reachable.
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [t.bg.withValues(alpha: 0), t.bg],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, AppSpacing.s4, gutter, 22),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSpacing.frameReading),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(
                          bottom: AppSpacing.s2, left: AppSpacing.s2),
                      child: Text(
                        error!,
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 13,
                          height: 1.45,
                          color: t.critical,
                        ),
                      ),
                    ),
                  ],
                  DecoratedBox(
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
                          for (final control in leading) ...[
                            control,
                            const SizedBox(width: AppSpacing.s2),
                          ],
                          Expanded(
                            child: TextField(
                              controller: controller,
                              minLines: minLines,
                              maxLines: maxLines,
                              maxLength: maxLength,
                              textInputAction: TextInputAction.newline,
                              style: AppTheme.serif(
                                fontSize: 17,
                                height: 24 / 17,
                                fontStyle: FontStyle.italic,
                                color: t.fg,
                              ),
                              decoration: InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                counterText: '',
                                contentPadding: EdgeInsets.zero,
                                hintText: placeholder,
                                hintStyle: AppTheme.serif(
                                  fontSize: 17,
                                  height: 24 / 17,
                                  fontStyle: FontStyle.italic,
                                  color: t.fgSubtle,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s2),
                          _SendControl(onSend: onSend, busy: busy),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The filled circular send control — 38×38, `--r-pill`, `--accent` on
/// `--accent-fg`.
class _SendControl extends StatelessWidget {
  final VoidCallback? onSend;
  final bool busy;

  const _SendControl({this.onSend, this.busy = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final enabled = onSend != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'Send',
      child: MouseRegion(
        cursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: enabled ? onSend : null,
          child: Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: enabled ? t.accent : t.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(t.fgSubtle),
                    ),
                  )
                : Icon(
                    Icons.north_east,
                    size: 17,
                    color: enabled ? t.accentFg : t.fgSubtle,
                  ),
          ),
        ),
      ),
    );
  }
}
