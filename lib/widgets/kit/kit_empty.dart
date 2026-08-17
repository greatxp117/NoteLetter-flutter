import 'package:flutter/widgets.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_text.dart';

/// §7 — the empty state.
///
/// Mark → letterpressed serif title → italic serif standfirst → a stack of
/// **suggestion rows the user can act on**.
///
/// **An empty state is an offer, not an apology.** The suggestion rows are a
/// required part: a centred sentence saying "nothing here yet" is not this
/// pattern, and it is the form every one of these screens degrades into when
/// nobody is looking.
class KitEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String standfirst;

  /// Suggestion rows — build with [KitSuggestion], or pass buttons for the
  /// action-row form.
  final List<Widget> suggestions;

  /// A row of buttons instead of suggestion rows (the study screen's form).
  final List<Widget> actions;

  const KitEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.standfirst,
    this.suggestions = const [],
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.s6, AppSpacing.s8, AppSpacing.s6, AppSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.chrome,
                  borderRadius: AppRadius.lgR,
                  boxShadow: AppShadows.s2,
                ),
                child: Icon(icon, size: 26, color: t.chromeFg),
              ),
              const SizedBox(height: AppSpacing.s5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: AppTheme.serif(
                  fontSize: 28,
                  height: 34 / 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.02 * 28,
                  color: t.fg,
                ).copyWith(shadows: AppShadows.letterpress),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  standfirst,
                  textAlign: TextAlign.center,
                  style: KitText.lede(context, fontSize: 16, height: 25),
                ),
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 26),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < suggestions.length; i++) ...[
                        if (i > 0) const SizedBox(height: AppSpacing.s2),
                        suggestions[i],
                      ],
                    ],
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      actions[i],
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A suggestion row inside an empty state: a full-width surface card with a
/// `--seal` leading icon and an **italic serif** label.
class KitSuggestion extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const KitSuggestion(
      {super.key, required this.icon, required this.label, this.onTap});

  @override
  State<KitSuggestion> createState() => _KitSuggestionState();
}

class _KitSuggestionState extends State<KitSuggestion> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: AppRadius.mdR,
            border: Border.all(
                color: _hover ? t.accentChipBorder : t.border),
            boxShadow: _hover ? AppShadows.s2 : AppShadows.s1,
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: t.seal),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  widget.label,
                  style: KitText.lede(context, fontSize: 16, height: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
