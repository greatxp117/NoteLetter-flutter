/// Direction D parts for F-144's support screens (component-kit §26–§42):
/// Letter settings (`screens/letters.md` §Composition, *Letter settings*;
/// web `.dp-lset`, app-letters.css) and Support (`screens/support.md`
/// §Composition; web `.dp-sup`, app-support.css, and `.dp-dock`).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/cooldown.dart' show waitSuffix;
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_d_parts.dart';
import 'kit_failure.dart' show KitFailureInline;
import 'kit_text.dart';
import 'kit_wait.dart' show KitWaitNote;

// ── §31 numbered sections (Letter settings) ─────────────────────────────────

/// One of Letter settings' numbered sections: 72 above it (56 on a phone,
/// none for the first), then its §31 head and its body. [sectionKey] is the
/// section's [KitSections.keyOf] key and sits on the head's own box, so
/// Contents measures and jumps to the hairline as a browser measures web's
/// `SecHead` — its margin outside the box.
class KitDNumbered extends StatelessWidget {
  final GlobalKey sectionKey;
  final int n;
  final String title;
  final List<Widget> children;

  const KitDNumbered({
    super.key,
    required this.sectionKey,
    required this.n,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: n == 0 ? 0 : KitSecHead.gap(context)),
    child: Semantics(
      container: true,
      explicitChildNodes: true,
      label: title,
      child: Column(
        key: sectionKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitSecHead(n: n, title: title, margin: false),
          ...children,
        ],
      ),
    ),
  );
}

/// A sentence under a control (web `.dp-lset .cfg-group .sub`): what the
/// activation send did, what the rest's number means — sans 13/19 in
/// `--fg-muted`, at most 64ch, [top] under the control.
class KitDConfigSub extends StatelessWidget {
  final String text;
  final double top;

  const KitDConfigSub(this.text, {super.key, this.top = 8});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 13,
      height: 19 / 13,
      color: Tokens.of(context).fgMuted,
    );
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 64 * KitText.ch(context, style),
          ),
          child: Text(text, style: style),
        ),
      ),
    );
  }
}

/// A slot under a control for the sentence it answered with — a §14.2
/// refusal, a calm caption — [top] under it. Nothing when [child] is null.
class KitDSlot extends StatelessWidget {
  final Widget? child;
  final double top;

  const KitDSlot(this.child, {super.key, this.top = 8});

  @override
  Widget build(BuildContext context) => child == null
      ? const SizedBox.shrink()
      : Padding(
          padding: EdgeInsets.only(top: top),
          child: child,
        );
}

/// `.dp-save` — the daily letter's one write: its button, then the §14.2
/// refusal beside it (wrapping under on a narrow column); 24 above.
class KitDSaveRow extends StatelessWidget {
  final Widget button;
  final String? error;

  const KitDSaveRow({super.key, required this.button, this.error});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [button, if (error != null) KitFailureInline(error!)],
    ),
  );
}

// ── The latest letter (Letter settings' preview) ────────────────────────────

/// `.dp-lset .letter-none` — the sentence that stands where no letter is:
/// serif italic 16/24 in `--fg-lede`, never a letter-shaped placeholder.
class KitDLetterNone extends StatelessWidget {
  final String text;
  const KitDLetterNone(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.serif(
      fontSize: 16,
      height: 24 / 16,
      fontStyle: FontStyle.italic,
      color: Tokens.of(context).fgLede,
    ),
  );
}

/// `.dp-lset .letter-actions` — under the letter, 18 below it over a
/// `--rule` with 16 under that: the stored letter's figures (mono 11 caps,
/// `--fg-subtle`, `0.06em`) at the leading edge and the actions at the
/// trailing one, wrapping under on a narrow column; then [notes] — what an
/// action answered — 8 apart.
class KitDLetterActions extends StatelessWidget {
  final String? figures;
  final Widget actions;
  final List<Widget> notes;

  const KitDLetterActions({
    super.key,
    required this.figures,
    required this.actions,
    this.notes = const [],
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              if (figures != null)
                Text(
                  figures!.toUpperCase(),
                  style: KitText.capsLabel(
                    context,
                    color: t.fgSubtle,
                    letterSpacing: 0.06,
                  ),
                ),
              actions,
            ],
          ),
          for (final n in notes)
            Padding(padding: const EdgeInsets.only(top: 8), child: n),
        ],
      ),
    );
  }
}

// ── Support: the correspondence ─────────────────────────────────────────────

/// The correspondence as a ruled register (web `.dp-thread .sup-thread`):
/// a 1px `--fg` rule on top, the messages ([KitMessageCard]) each over a
/// `--rule`, then the awaiting line ([KitThreadNote]).
class KitDThread extends StatelessWidget {
  final List<Widget> children;
  const KitDThread({super.key, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: Tokens.of(context).fg)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// The running head's line on a phone for a page whose sheet is not
/// Contents (web `.d-peek` with a glyph): the glyph (16, `--fg-muted`), the
/// line in serif 600 16.5/22, and a count at the trailing edge (mono 11.5) —
/// Support's status with its message count. Ask's own is the same anatomy
/// with its history glyph (`KitAskPeek`).
class KitDIconPeek extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? count;

  const KitDIconPeek({
    super.key,
    required this.icon,
    required this.title,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: t.fgMuted),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.serif(
              fontSize: 16.5,
              height: 22 / 16.5,
              fontWeight: FontWeight.w600,
              color: t.fg,
              opsz: 18,
            ),
          ),
        ),
        if (count != null)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              count!,
              style: KitText.monoFigure(context, fontSize: 11.5, color: t.fg),
            ),
          ),
      ],
    );
  }
}

// ── §38 Composer, as Support docks it ───────────────────────────────────────

/// Support's composer (`.dp-dock .sup-composer`), docked at the column's
/// foot through [KitDPage.dock]: a raised card — `--surface`, 1px `--border`,
/// `--r-xl`, `--shadow-3`, `12px 14px 12px 20px` — holding the §38 field
/// ([KitGrowField]: one line tall at rest, growing with the text to 172px,
/// then scrolling) and the send: a 38px `--accent` circle with the arrow,
/// aligned to the field's last line.
///
/// **Write before you move** is the host's: [busy] holds the send while the
/// endpoint has not answered and the text STAYS; the host clears the field
/// only once the message was accepted. The send is held while the field is
/// empty ([onSend] null), while [busy], and for a cooldown's [waitLeft] — its
/// accessible name ([label]) then carries ` · m:ss` (web `title`). Above the
/// card, the one sentence slot: the cooldown's calm caption ([waitNote]),
/// else a refusal ([error], §14.2) — beside the text it refers to, which is
/// still in the box. ⌘/Ctrl+Enter sends; Enter is a newline. [maxLength]
/// caps what the field takes (web's `maxLength`).
class KitDComposer extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;
  final String label;
  final VoidCallback? onSend;
  final bool busy;
  final int waitLeft;
  final String? waitNote;
  final String? error;
  final int? maxLength;
  final FocusNode? focusNode;
  final Key? fieldKey;
  final Key? sendKey;

  const KitDComposer({
    super.key,
    required this.controller,
    required this.placeholder,
    required this.label,
    required this.onSend,
    this.busy = false,
    this.waitLeft = 0,
    this.waitNote,
    this.error,
    this.maxLength,
    this.focusNode,
    this.fieldKey,
    this.sendKey,
  });

  @override
  State<KitDComposer> createState() => _KitDComposerState();
}

class _KitDComposerState extends State<KitDComposer> {
  FocusNode? _own;
  FocusNode get _focus => widget.focusNode ?? (_own ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_cap);
  }

  @override
  void didUpdateWidget(KitDComposer old) {
    super.didUpdateWidget(old);
    if (!identical(old.controller, widget.controller)) {
      old.controller.removeListener(_cap);
      widget.controller.addListener(_cap);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_cap);
    _own?.dispose();
    super.dispose();
  }

  /// The field's cap (web `maxLength`): text past it is not taken. Never
  /// while an IME composition is open — that text is not the reader's yet.
  void _cap() {
    final max = widget.maxLength;
    final v = widget.controller.value;
    if (max == null || v.text.length <= max) return;
    if (v.composing.isValid && !v.composing.isCollapsed) return;
    widget.controller.value = TextEditingValue(
      text: v.text.substring(0, max),
      selection: TextSelection.collapsed(offset: max),
    );
  }

  bool get _waiting => widget.waitLeft > 0 && !widget.busy;
  bool get _canSend => widget.onSend != null && !widget.busy && !_waiting;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter &&
        e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final k = HardwareKeyboard.instance;
    if (!k.isMetaPressed && !k.isControlPressed) return KeyEventResult.ignored;
    if (_canSend) widget.onSend!();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final title =
        '${widget.label}${_waiting ? waitSuffix(widget.waitLeft) : ''}';
    final slot = widget.waitNote != null
        ? KitWaitNote(widget.waitNote!)
        : (widget.error == null ? null : KitFailureInline(widget.error!));
    final send = Opacity(
      opacity: _canSend ? 1 : AppSpacing.heldOpacity,
      child: KitDTap(
        key: widget.sendKey,
        onTap: _canSend ? widget.onSend : null,
        label: title,
        builder: (context, hover, focus) => Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hover ? t.accentHover : t.accent,
            shape: BoxShape.circle,
            border: focus ? Border.all(color: t.fg, width: 2) : null,
          ),
          // `IcoSend` is a right arrow (`M5 12h14M13 5l7 7-7 7`).
          child: Icon(Icons.arrow_forward, size: 17, color: t.accentFg),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (slot != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: slot),
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
                Expanded(
                  child: Focus(
                    canRequestFocus: false,
                    skipTraversal: true,
                    onKeyEvent: _onKey,
                    child: KitGrowField(
                      key: widget.fieldKey,
                      controller: widget.controller,
                      focusNode: _focus,
                      placeholder: widget.placeholder,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _waiting ? Tooltip(message: title, child: send) : send,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
