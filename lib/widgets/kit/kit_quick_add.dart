import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitFileBadge, KitBadgeSize;
import 'kit_d_parts.dart' show KitD, KitDTap;
import 'kit_provider_logo.dart';
import 'kit_shell.dart' show KitGlyph;

// ── Quick add's own parts (F-152) ───────────────────────────────────────────
//
// Web `overlays/QuickAdd.jsx` and its `.qa-*` rules (`app-responsive.css`):
// the parts only quick add draws, spelled once here so the overlay
// (`lib/widgets/quick_add.dart`) composes and styles nothing itself. Its frame
// is component-kit §15's add sheet ([KitOverlaySheet], 540 / 82%), its zone
// [KitDropZone] `compact`, its one-source question [KitImageSetChoice].

/// `.qa-body` — the sheet's body: padded 16 20, its parts 14 apart.
class KitQaBody extends StatelessWidget {
  final List<Widget> children;

  const KitQaBody({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          children[i],
        ],
      ],
    ),
  );
}

/// Under a part of [KitQaBody] — the connect refusal under the chips
/// (`.qa-connect-fail`, 8 above), the device's image-set row under the link
/// row: [below] hangs off [child] rather than taking the body's 14.
class KitQaHang extends StatelessWidget {
  final Widget child;
  final Widget? below;
  final double gap;

  const KitQaHang({super.key, required this.child, this.below, this.gap = 8});

  @override
  Widget build(BuildContext context) {
    final b = below;
    if (b == null) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        child,
        SizedBox(height: gap),
        b,
      ],
    );
  }
}

/// `.qa-linkrow` — the link glyph (16, `--fg-subtle`), a sans 14 field padded
/// 11 above and below, and **Add** (30 tall, `--secondary`, held on an empty
/// field), in one row: 1px `--border` (`--accent` in focus), `--r-sm`,
/// `--surface`, padded 0 12, gap 9.
class KitQaLinkRow extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final bool autofocus;

  const KitQaLinkRow({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.autofocus = false,
  });

  static const placeholder = 'Paste a link — article, video, or podcast…';

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 14,
      height: 20 / 14,
      color: t.fg,
    );
    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      builder: (context, _) {
        final held = controller.text.trim().isEmpty;
        return AnimatedContainer(
          duration: KitD.dur(context, AppMotion.durFast),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.smR,
            border: Border.all(color: focusNode.hasFocus ? t.accent : t.border),
          ),
          child: Row(
            children: [
              KitGlyph(Icons.link, size: 16, color: t.fgSubtle),
              const SizedBox(width: 9),
              Expanded(
                // 42 tall, as web's `11px 0` around a 20px line: the theme's
                // field grew the row to 67 on a device (as KitLibLinkField's).
                child: SizedBox(
                  height: 42,
                  child: Center(
                    child: Semantics(
                      label: 'Paste a link',
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: autofocus,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        autocorrect: false,
                        style: style,
                        cursorColor: t.accent,
                        onSubmitted: (_) => onSubmit(),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          // The row above IS the field; the theme's outline
                          // would draw a second one inside it.
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          hintText: placeholder,
                          hintMaxLines: 1,
                          hintStyle: style.copyWith(color: t.fgSubtle),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              // `.qa-link-btn` is a `.btn-secondary`, held at the token.
              Opacity(
                opacity: held ? AppSpacing.heldOpacity : 1,
                child: KitDTap(
                  label: 'Add',
                  enabled: !held,
                  onTap: held ? null : onSubmit,
                  builder: (context, hover, focus) => AnimatedContainer(
                    duration: KitD.dur(context, AppMotion.durFast),
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hover ? t.secondaryHover : t.secondary,
                      borderRadius: AppRadius.controlR(30),
                      border: focus
                          ? Border.all(color: t.accent, width: 2)
                          : null,
                    ),
                    child: Text(
                      'Add',
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: t.secondaryFg,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// `.qa-added` — *Going to your library* (mono 10, 0.13em caps,
/// `--fg-subtle`) over the rows this opening made, `{ready} of {n} filed`
/// (mono 10.5 `--fg-muted`) at its trailing edge; rows 7 apart.
class KitQaAdded extends StatelessWidget {
  final int ready;
  final List<Widget> rows;

  const KitQaAdded({super.key, required this.ready, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'GOING TO YOUR LIBRARY',
                style: AppTheme.mono(
                  fontSize: 10,
                  letterSpacing: 1.3,
                  color: t.fgSubtle,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$ready of ${rows.length} filed',
              style: AppTheme.mono(fontSize: 10.5, color: t.fgMuted),
            ),
          ],
        ),
        for (final r in rows) ...[const SizedBox(height: 7), r],
      ],
    );
  }
}

/// Where a quick-add row stands (`.ustate`).
enum KitQaState { uploading, filed, error }

/// `.qa-urow` — one source going to the library: its plate (28 wide, the
/// form size), its name (serif 14/500, one line), the line under it (mono
/// 10.5 `--fg-subtle`: *uploading… n%*, the refusal's own words, or *added —
/// indexing will begin shortly*), a 3px bar while it uploads — determinate
/// only on committed bytes ([pct]), otherwise indeterminate — and the state
/// chip. On `--surface-raised`, 1px `--border`, `--r-sm`, padded 10 12.
///
/// The chip (`.ustate`, mono 10 0.08em caps): *Uploading* on `--accent-soft`,
/// *Filed* on the positive chip with its dot. *Error* is drawn on the
/// critical text, where web's falls through to the positive chip (F-152's
/// report, FOUND).
class KitQaRow extends StatelessWidget {
  final String kind;
  final String name;
  final String line;
  final KitQaState state;

  /// Whole percent of committed bytes; null while nothing measurable has
  /// moved (the session being made, a link being read).
  final int? pct;

  const KitQaRow({
    super.key,
    required this.kind,
    required this.name,
    required this.line,
    required this.state,
    this.pct,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final uploading = state == KitQaState.uploading;
    final (label, bg, fg) = switch (state) {
      KitQaState.uploading => ('UPLOADING', t.accentSoft, t.accentChipFg),
      KitQaState.filed => ('FILED', t.positiveChipBg, t.positiveChipFg),
      KitQaState.error => ('ERROR', t.surfaceSunken, t.criticalText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: t.surfaceRaised,
        borderRadius: AppRadius.smR,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: KitFileBadge(kind, size: KitBadgeSize.form),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  style: AppTheme.mono(fontSize: 10.5, color: t.fgSubtle),
                ),
                if (uploading) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: AppRadius.pillR(3),
                    child: LinearProgressIndicator(
                      value: pct == null ? null : pct! / 100,
                      minHeight: 3,
                      backgroundColor: t.surfaceSunken,
                      color: t.accent,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 9, 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (state == KitQaState.filed) ...[
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.positive,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: AppTheme.mono(
                    fontSize: 10,
                    height: 1,
                    letterSpacing: 0.8,
                    color: fg,
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

/// `.qa-or` — a hairline, the label (mono 10, 0.13em caps, `--fg-subtle`),
/// a hairline; 12 apart. The CALLER's words, uppercased here.
class KitQaOr extends StatelessWidget {
  final String label;

  const KitQaOr(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget hr() => Expanded(child: Container(height: 1, color: t.rule));
    return Row(
      children: [
        hr(),
        const SizedBox(width: 12),
        Text(
          label.toUpperCase(),
          style: AppTheme.mono(
            fontSize: 10,
            letterSpacing: 1.3,
            color: t.fgSubtle,
          ),
        ),
        const SizedBox(width: 12),
        hr(),
      ],
    );
  }
}

/// `.qa-chip` — one service to connect: its mark on a fixed white plate (24,
/// `--r-xs`, 1px `--border`), then its name (sans 13/500), in a pill (1px
/// `--border`, `--surface`, padded 7 13 7 8, gap 9). While its connect is in
/// flight it says *Connecting {name}…* and is held (`--held-opacity`).
class KitQaChip extends StatelessWidget {
  final String provider;
  final String name;
  final bool busy;
  final VoidCallback? onTap;

  const KitQaChip({
    super.key,
    required this.provider,
    required this.name,
    this.busy = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Opacity(
      opacity: busy ? AppSpacing.heldOpacity : 1,
      child: KitDTap(
        label: busy ? 'Connecting $name…' : name,
        enabled: !busy,
        onTap: busy ? null : onTap,
        builder: (context, hover, focus) => AnimatedContainer(
          duration: KitD.dur(context, AppMotion.durFast),
          padding: const EdgeInsets.fromLTRB(8, 7, 13, 7),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focus
                  ? t.accent
                  : hover
                  ? t.accentChipBorder
                  : t.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // literal-ok: a vendor brand-mark plate — fixed white in
                  // both themes (Notion's mark is black; web `.qa-chip .iconbox`).
                  color: const Color(0xFFFFFFFF),
                  borderRadius: AppRadius.xsR,
                  border: Border.all(color: t.border),
                ),
                child: KitProviderLogo(provider: provider, size: 15),
              ),
              const SizedBox(width: 9),
              Text(
                busy ? 'Connecting $name…' : name,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: t.fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.qa-foot` — *What can I add?* (the help glyph, sans 13/500 `--fg-muted`)
/// at the leading edge and *More options →* (sans 13/500 `--link`) at the
/// trailing one, padded 12 18. The surface and the rule above it are the
/// sheet's (§15's foot).
class KitQaFoot extends StatelessWidget {
  final VoidCallback onHelp;
  final VoidCallback onMore;

  const KitQaFoot({super.key, required this.onHelp, required this.onMore});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget link(
      String label,
      Color color,
      VoidCallback onTap, {
      IconData? icon,
    }) => KitDTap(
      label: label,
      onTap: onTap,
      builder: (context, hover, focus) => Container(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        decoration: BoxDecoration(
          color: hover ? t.hover : null,
          borderRadius: AppRadius.xsR,
          border: focus ? Border.all(color: t.accent, width: 2) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              KitGlyph(icon, size: 14, color: hover ? t.fg : color),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: hover && icon != null ? t.fg : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: link(
              'What can I add?',
              t.fgMuted,
              onHelp,
              icon: Icons.help_outline,
            ),
          ),
          const SizedBox(width: 18),
          Flexible(child: link('More options →', t.link, onMore)),
        ],
      ),
    );
  }
}
