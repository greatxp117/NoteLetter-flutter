import 'package:flutter/material.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

/// Search's own field (`spec/screens/search.md` §Composition (direction D),
/// **Tools**; web `SearchView.jsx` `.hx-search.dp-field.dp-q`).
///
/// Search is the one page that passes kit §27's `field`: the query stands in
/// the rail's place of Search and **stays in the masthead at every width** —
/// beside the folio wider than 1024, under it to 680, and on a phone under the
/// standfirst, above the rule. The page decides the slot; this is the field.
///
/// Required parts, in order: the search glyph (17, `--fg-muted`), a serif 17
/// input with the italic `--fg-subtle` placeholder *Ask your library in plain
/// language…*, and — only while the field holds text — a round 30px clear
/// control *Clear the search* (15px cross, `--fg-subtle`; `--hover` and `--fg`
/// under a fine pointer). 44 tall, `0 9px 0 15px`, `--surface` inside a 1px
/// `--border` at the 44px control radius; a hover raises the border to
/// `--border-strong`; focus rings it in `--accent` over a 4px `--accent-soft`.
/// **Enter searches**; nothing searches on a keystroke (the screen is
/// submit-driven on this client).
///
/// Lives beside the page rather than in `widgets/kit/` because no other page
/// has one (kit §27: Search is the only page that passes `field`); its type is
/// the kit's ([KitText.bodyReading], [KitText.lede]).
class SearchQueryField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  /// Empties the field and returns the page to its no-query state (web
  /// `clear`: the query and the submission both go).
  final VoidCallback onClear;

  const SearchQueryField({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  State<SearchQueryField> createState() => _SearchQueryFieldState();
}

class _SearchQueryFieldState extends State<SearchQueryField> {
  final _focus = FocusNode(debugLabel: 'search-query');
  bool _hover = false;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SearchQueryField old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final focused = _focus.hasFocus;
    final holds = widget.controller.text.isNotEmpty;
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        // `.dp-q{cursor:text}`: the whole field focuses the input, not only
        // the run of characters in it.
        onTap: _focus.requestFocus,
        child: AnimatedContainer(
          key: const ValueKey('search-field'),
          duration: KitD.dur(context, AppMotion.durBase),
          curve: AppMotion.easeOut,
          height: 44,
          padding: const EdgeInsets.only(left: 15, right: 9),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.controlR(44),
            border: Border.all(
              color: focused
                  ? t.accent
                  : (_hover ? t.borderStrong : t.border),
            ),
            boxShadow: focused
                ? [BoxShadow(color: t.accentSoft, spreadRadius: 4)]
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 17, color: t.fgMuted),
              const SizedBox(width: 11),
              Expanded(
                child: Semantics(
                  label: 'Search your library',
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focus,
                    textInputAction: TextInputAction.search,
                    onSubmitted: widget.onSubmitted,
                    style: KitText.bodyReading(context,
                        fontSize: 17, height: 22),
                    cursorColor: t.accent,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'Ask your library in plain language…',
                      hintMaxLines: 1,
                      hintStyle: KitText.lede(context,
                          fontSize: 17,
                          height: 22,
                          color: t.fgSubtle,
                          opsz: 18),
                    ),
                  ),
                ),
              ),
              if (holds) ...[
                const SizedBox(width: 11),
                _Clear(onTap: widget.onClear),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// `.dp-q-x` — the round clear control: 30, `--fg-subtle`; under a fine
/// pointer `--hover` behind a `--fg` cross; a 2px accent focus ring.
class _Clear extends StatelessWidget {
  final VoidCallback onTap;
  const _Clear({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      key: const ValueKey('search-clear'),
      label: 'Clear the search',
      onTap: onTap,
      builder: (context, hover, focus) => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hover ? t.hover : null,
          border: focus ? Border.all(color: t.accent, width: 2) : null,
        ),
        child: Icon(Icons.close, size: 15, color: hover ? t.fg : t.fgSubtle),
      ),
    );
  }
}
