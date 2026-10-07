import 'package:flutter/material.dart';

import '../../shared/cooldown.dart';
import '../../theme/app_radius.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_text.dart';
import 'kit_wait.dart';

/// §18 — the **Confirmation**: a panel that stops a destructive action and asks
/// for it again (4.56.0, ADR-092).
///
/// Not §15's overlay sheet, which holds something the reader came *for*. This
/// holds something they are about to lose, and it is the one overlay that
/// **cannot be dismissed by looking away while it is working**.
///
/// **Required parts** — a scrim that cancels on press · a centred panel
/// announcing itself as an alert dialog · a title naming the OBJECT, not the
/// verb · a body naming **what is lost and what is not** · a **§14.2 failure
/// slot inside the panel** · an action pair, the safe choice first and labelled
/// with the alternative it takes.
///
/// This file exists because the same helper was copied **verbatim into three
/// pages** (`shelf_page`, `chat_page`, `sources/browse_section`) while a fourth
/// dialog in `study/program_editor` drew plain Material chrome. That is ADR-041
/// in one widget, and the reason a kit exists at all.
///
/// The failure slot is **required, not optional**. On the reference, four of six
/// confirmed destructive actions could not report a refusal — one had no catch,
/// two logged to the console, one answered after the panel had closed. An
/// optional part is one a call site decides it does not need, and that decision
/// is invisible: a delete that never fails in testing looks exactly like a
/// delete whose failure is discarded.
class KitConfirm extends StatefulWidget {
  final String title;

  /// Names what is lost AND what is not. A `String` is the common case; a
  /// widget where the consequences are conditional.
  final String? body;
  final Widget? bodyWidget;

  /// Labelled with its consequence ("Delete conversation"), never "OK".
  final String confirmLabel;

  /// Labelled with the ALTERNATIVE it takes ("Keep it"), never a bare "Cancel"
  /// beside a destructive verb — that makes the reader work out which way is
  /// safe at the one moment it is expensive to get wrong.
  final String cancelLabel;

  /// Draws the confirming control in §6.1's danger variant. True whenever the
  /// action destroys something, whatever the verb on the button says.
  final bool danger;

  /// Runs the action. Return `null` on success, or the sentence to render in
  /// the panel — the panel stays open and shows it. The **caller** never pops:
  /// this widget closes only when the call has actually succeeded (§18 rule 1).
  final Future<String?> Function() onConfirm;

  /// The [WaitKey] of the cooldown [onConfirm]'s request is scoped to, when it
  /// has one (§6.1 Waiting, 4.107.0, ADR-140). A refusal that armed it holds
  /// the confirming control for the wait with ` · m:ss` on its label, and the
  /// server's sentence is the panel's failure slot until the wait ends — the
  /// panel stays open, as it does on any refusal. Null for an action no
  /// cooldown governs.
  final String? waitKey;

  const KitConfirm({
    super.key,
    required this.title,
    this.body,
    this.bodyWidget,
    required this.confirmLabel,
    required this.cancelLabel,
    this.danger = true,
    required this.onConfirm,
    this.waitKey,
  });

  /// Show it. Resolves **true** only when the action succeeded — a dismissal
  /// and a refusal both resolve false/null, and a refusal never gets that far
  /// because the panel does not close on one.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    String? body,
    Widget? bodyWidget,
    required String confirmLabel,
    required String cancelLabel,
    bool danger = true,
    required Future<String?> Function() onConfirm,
    String? waitKey,
  }) {
    return showDialog<bool>(
      context: context,
      // §18 rule 4: the scrim cancels — at every moment but one. The barrier
      // and Esc both arrive as `Navigator.maybePop`, which the panel's
      // [PopScope] refuses while the call is in flight (rule 3), so a reader
      // cannot tap away from a delete mid-flight and be left unable to tell
      // whether it happened. Until 2026-10-05 this was `false` outright, and
      // the scrim — a REQUIRED part — cancelled nothing at all.
      barrierDismissible: true,
      builder: (_) => KitConfirm(
        title: title,
        body: body,
        bodyWidget: bodyWidget,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        danger: danger,
        onConfirm: onConfirm,
        waitKey: waitKey,
      ),
    );
  }

  @override
  State<KitConfirm> createState() => _KitConfirmState();
}

class _KitConfirmState extends State<KitConfirm> {
  bool _busy = false;
  String? _error;

  Future<void> _run() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final message = await widget.onConfirm();
    if (!mounted) return;
    if (message == null) {
      Navigator.of(context).pop(true);
      return;
    }
    // §18 rules 1–2: the refusal keeps the panel open and answers inside it.
    // Closing here would tell the reader it worked. A cooldown that carried
    // its number is the confirm's WAIT, and the wait says its own sentence for
    // exactly as long as it runs — a copy held here would outlive it.
    setState(() {
      _busy = false;
      _error = Cooldowns.instance.waiting(widget.waitKey) ? null : message;
    });
  }

  @override
  Widget build(BuildContext context) => KitWait(
        waitKey: widget.waitKey,
        builder: (context, wait) => _panel(context, wait),
      );

  Widget _panel(BuildContext context, CooldownWait wait) {
    final t = Tokens.of(context);
    // A cooldown refused inside the panel is the calm caption; any other
    // refusal is §18's failure slot, red (§6.1, 4.108.0, ADR-145).
    final slot = kitRefusalSlot(wait, _error);
    final held = _busy ? 0 : wait.left;
    return PopScope(
      // Nothing dismisses it while the call is in flight — not the system back
      // gesture either.
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.xlR,
          side: BorderSide(color: t.border),
        ),
        title: Text(widget.title, style: KitText.h4(context)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.bodyWidget != null)
                widget.bodyWidget!
              else if (widget.body != null)
                Text(widget.body!, style: KitText.meta(context)),
              if (slot != null) ...[
                const SizedBox(height: 12),
                slot,
              ],
            ],
          ),
        ),
        actions: [
          // The safe choice first AND focused (§18 required parts, rule 4):
          // a reader who answers from the keyboard keeps what they have.
          KitButton.ghost(
            widget.cancelLabel,
            autofocus: true,
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          ),
          if (widget.danger)
            KitButton.danger(_busy ? 'Working…' : widget.confirmLabel,
                wait: held, onPressed: _busy ? null : _run)
          else
            KitButton.primary(_busy ? 'Working…' : widget.confirmLabel,
                wait: held, onPressed: _busy ? null : _run),
        ],
      ),
    );
  }
}
