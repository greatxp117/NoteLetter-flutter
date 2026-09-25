import 'package:flutter/widgets.dart';

import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_text.dart';

/// The **letter configuration form** — the reference's `.letter-config`
/// (`LetterSettings.jsx`, `app-responsive.css` `.cfg-*`, `app-scripture.css`
/// `.cfg-rl`). Letter settings is the one screen that draws it, and it draws
/// every part twice (the daily letter, then the readings letter), which is why
/// the parts live here rather than on the page. The groups themselves are
/// [KitFieldGroup] (`kit_controls.dart`), which notification settings and
/// onboarding already compose from.
///
/// It is NOT the settings screen's setting row (icon plate + title +
/// description). This client drew Letter settings as a stack of those, and the
/// frame next to the reference was a different form: the reference labels
/// each group with a **mono caps label** over its control, separates groups
/// with a hairline `--rule`, and opens with a tinted **toggle card** for the
/// schedule. No `component-kit.md` section names this form yet; the metrics
/// below are the reference stylesheet's.

/// `.letter-config-h h2` + `.letter-config .sub` — serif 24/600 at `-0.015em`
/// over the italic serif lede. The screen's title is a heading, not an eyebrow.
class KitConfigHeading extends StatelessWidget {
  final String title;
  final String? standfirst;

  const KitConfigHeading(this.title, {super.key, this.standfirst});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTheme.serif(
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.015 * 24,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 8),
        if (standfirst != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 22),
            child: Text(
              standfirst!,
              style: KitText.lede(context, fontSize: 14, height: 22),
            ),
          ),
      ],
    );
  }
}

/// `.cfg-rl` — the toggle card that opens a letter's group: a whole-card
/// switch. `--surface-sunken` with a `--border` edge when off; **tinted**
/// `--accent-chip-bg` with an `--accent-chip-border` edge when on. A 17px
/// glyph at `--accent-text`, a sans 13.5/600 title over a sans 12/18
/// description (`--fg-muted`, `--fg-lede` when on), and the switch trailing.
///
/// The card is the control, as the reference's `<button role="switch">` is —
/// but it still WRITES BEFORE IT MOVES (ADR-022): [value] is what was stored,
/// and [onChanged] is the write; the card changes colour when the caller's
/// state does, never on the tap.
class KitConfigToggle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const KitConfigToggle({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: value ? t.accentChipBg : t.surfaceSunken,
            borderRadius: AppRadius.mdR,
            border: Border.all(color: value ? t.accentChipBorder : t.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 17, color: t.accentText),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12,
                        height: 18 / 12,
                        color: value ? t.fgLede : t.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              KitSwitch(value: value, onChanged: onChanged),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.cfg-hint` / `.cfg-note` — the sentence under a field that explains what
/// an empty value means: sunken and muted when it is only information
/// ("Letters will go to … until you set a different address."), accent-chip
/// when it is a problem ("… can't be delivered until you add an address.").
class KitConfigHint extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool warn;

  const KitConfigHint(
    this.text, {
    super.key,
    required this.icon,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = warn ? t.accentChipFg : t.fgMuted;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: warn ? t.accentChipBg : t.surfaceSunken,
        borderRadius: AppRadius.smR,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: fg),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12.5,
                height: 1.45,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.rl-field` — the readings letter's labelled field: a sans 12.5/600 label,
/// the control 7px under it, and an optional `.rl-fnote` (sans 11.5/17 at
/// `--fg-subtle`). [trailing] puts a control on the label's row
/// (`.rl-toggle-row` — the "Email it to me" switch).
class KitConfigField extends StatelessWidget {
  final String label;
  final Widget? child;
  final Widget? trailing;
  final String? note;

  const KitConfigField({
    super.key,
    required this.label,
    this.child,
    this.trailing,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (child != null) ...[const SizedBox(height: 7), child!],
          if (note != null) ...[
            const SizedBox(height: 7),
            Text(
              note!,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 11.5,
                height: 17 / 11.5,
                color: t.fgSubtle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// `.rl-static` — a value SHOWN, not chosen (the readings calendar): serif 15.
class KitConfigStatic extends StatelessWidget {
  final String text;
  const KitConfigStatic(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.serif(fontSize: 15, color: Tokens.of(context).fg),
  );
}
