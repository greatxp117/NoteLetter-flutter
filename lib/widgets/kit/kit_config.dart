import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_failure.dart' show KitFailureInline;

/// The **letter configuration form** — the reference's `.cfg-*` groups
/// (`LetterSettings.jsx`, `app-responsive.css` `.cfg-*`, `app-scripture.css`
/// `.cfg-rl` / `.rl-*`). Letter settings is the one screen that draws it, and
/// it draws every part twice (the daily letter, then the readings letter),
/// which is why the parts live here rather than on the page. The groups
/// themselves are [KitFieldGroup] (`kit_controls.dart`), which notification
/// settings and onboarding already compose from. In direction D the form sits
/// in Letter settings' numbered sections (`kit_d_support.dart`); its heading
/// is the D masthead's, so this file no longer draws one.
///
/// It is NOT the settings screen's setting row (icon plate + title +
/// description). This client drew Letter settings as a stack of those, and the
/// frame next to the reference was a different form: the reference labels
/// each group with a **mono caps label** over its control, separates groups
/// with a hairline `--rule`, and opens with a tinted **toggle card** for the
/// schedule. No `component-kit.md` section names this form yet; the metrics
/// below are the reference stylesheet's.

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
/// (`.rl-toggle-row` — the "Email it to me" switch). [error] is a refusal of
/// THIS field's write (`.rl-ferr`, §14.2), drawn under it — beside the
/// control that refused, never at the foot of the form.
class KitConfigField extends StatelessWidget {
  final String label;
  final Widget? child;
  final Widget? trailing;
  final String? note;
  final String? error;

  /// Space above the field: 15 in the readings letter's stack; 0 where a
  /// grid places it (`.st-fields`, the program editor).
  final double top;

  const KitConfigField({
    super.key,
    required this.label,
    this.child,
    this.trailing,
    this.note,
    this.error,
    this.top = 15,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
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
          if (error != null) ...[
            const SizedBox(height: 7),
            KitFailureInline(error!),
          ],
        ],
      ),
    );
  }
}

/// A field and the button that saves it, on one line (`.rl-field` with its
/// own Save): the field takes the line, the button 8 after it.
class KitConfigInline extends StatelessWidget {
  final Widget field;
  final Widget action;

  const KitConfigInline({super.key, required this.field, required this.action});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: field),
      const SizedBox(width: 8),
      action,
    ],
  );
}

/// `.rl-settings-f` — the readings letter's foot: 14 under a `--rule`, its
/// sentence in `.rl-fnote` (sans 11.5/17, `--fg-subtle`) — what a save is
/// doing, else that the daily letter is untouched.
class KitConfigFoot extends StatelessWidget {
  final String text;

  const KitConfigFoot(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.rule)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.fontSans,
          fontSize: 11.5,
          height: 17 / 11.5,
          color: t.fgSubtle,
        ),
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

/// `.src-toggle` — one row of a choose-from list inside a config group
/// (letter settings' **Draw from**): an 8px dot in the shelf's stored colour
/// (with the hairline every dot carries), the name in sans 14, a [KitSwitch]
/// at the end; 9px of vertical padding and a `--rule` between rows, none
/// above the first.
class KitSourceToggle extends StatelessWidget {
  /// A `/tags.color` token name; an unknown value resolves muted.
  final String? colorToken;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool first;

  const KitSourceToggle({
    super.key,
    required this.label,
    required this.value,
    this.colorToken,
    this.onChanged,
    this.first = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: t.rule)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color:
                  AppColors.shelfColor(colorToken, dark: t.isDark) ??
                  t.fgSubtle,
              shape: BoxShape.circle,
              border: Border.all(color: t.border, width: 0.5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 14,
                color: t.fg,
              ),
            ),
          ),
          const SizedBox(width: 10),
          KitSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
