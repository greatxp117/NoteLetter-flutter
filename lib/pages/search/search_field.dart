import 'package:flutter/material.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// The Search header (`spec/screens/search.md` §Composition).
///
/// Search is one of the three screens with a **bespoke header** — the kit's
/// chapter opening (§2.1) is not used here, and the reason is editorial: this
/// screen's first act is a question, so the field *is* the title. A chapter
/// opening above it would announce a screen the reader is already looking at.
///
/// It lives beside the page rather than in `widgets/kit/` because it is not a
/// kit pattern: `component-kit.md` §2 names it as specified in the screen file,
/// and putting a one-screen component in the shared kit is how a kit stops
/// being a vocabulary. The rule it still obeys is the one that matters — the
/// page file does not style its own type; this file does, once.
///
/// Required parts, in order: a mono `--accent-text` eyebrow · the field, a 16/20
/// padded `--surface` bar at `--r-lg` with a 1px `--border-strong`, a 22px
/// icon, a **serif 22/28 input with an italic placeholder**, and a mono caps
/// mode pill on `--accent-soft`. Focus raises the border to `--accent` and the
/// shadow to `--shadow-2`.
class SearchBigField extends StatefulWidget {
  final TextEditingController controller;

  /// `Vector` or `Scripture` — the palette's mode indicator. The Scripture
  /// value is not reachable yet on this client (the citation path is unwired);
  /// the parameter exists so wiring it later does not reshape the header.
  final String mode;

  final ValueChanged<String> onSubmitted;

  const SearchBigField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    this.mode = 'Vector',
  });

  @override
  State<SearchBigField> createState() => _SearchBigFieldState();
}

class _SearchBigFieldState extends State<SearchBigField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final focused = _focus.hasFocus;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Semantic search across your library',
          style: KitText.capsLabel(context,
              fontSize: 10, letterSpacing: 0.16, color: t.accentText),
        ),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.lgR,
            border: Border.all(color: focused ? t.accent : t.borderStrong),
            boxShadow: focused ? AppShadows.s2 : AppShadows.s1,
          ),
          child: Row(
            children: [
              Icon(Icons.search,
                  // 22 is the reference; a phone takes 18 with the field's
                  // type, so the icon stays proportionate to the line it opens.
                  size: compact ? 18 : 22,
                  color: t.fgMuted),
              const SizedBox(width: 14),
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: widget.onSubmitted,
                  style: AppTheme.serif(
                    fontSize: compact ? 18 : 22,
                    height: 28 / 22,
                    color: t.fg,
                  ),
                  cursorColor: t.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: 'Ask your library in plain language…',
                    // Italic, and in the serif: the placeholder is the one
                    // piece of copy on this screen written in the reader's
                    // voice rather than the app's.
                    hintStyle: AppTheme.serif(
                      fontSize: compact ? 18 : 22,
                      height: 28 / 22,
                      fontStyle: FontStyle.italic,
                      color: t.fgSubtle,
                    ),
                  ),
                ),
              ),
              // The mode pill is dropped on a phone, as in the reference: at
              // that width it costs a third of the field, and the mode is
              // already visible in what the results are.
              if (!compact) ...[
                const SizedBox(width: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.mode.toUpperCase(),
                    style: KitText.capsLabel(context,
                        fontSize: 10, letterSpacing: 0.08, color: t.accentText),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
