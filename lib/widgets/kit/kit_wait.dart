import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../shared/cooldown.dart';

/// §6.1 Button · **State — Waiting** (4.107.0, ADR-140): a control whose
/// request was refused by a cooldown that carried `retry_after_s`.
///
/// **Required parts** — the control is disabled for exactly that many
/// seconds, counted from when the refusal arrived; its idle label is followed
/// by the remaining time as ` · m:ss` (an icon control carries it in its
/// accessible title); the server's sentence renders verbatim in the slot that
/// site already uses for that refusal while the wait runs, and leaves with
/// it. At zero the control has its own label back.
///
/// This is the one way a screen learns that a control is waiting — web's
/// `useCooldown`. It reads the app-wide [Cooldowns] registry, so the wait
/// belongs to what the server scopes it to (a document, a job, a provider, a
/// program, the caller), never to this widget: two controls over one
/// document's retry, or two folders of one provider, wait on one clock, and a
/// screen that is rebuilt or left and re-entered keeps it.
///
/// It rebuilds [builder] when a wait is armed or ends, and once per
/// whole-second boundary while one runs — and does nothing at all while idle.
/// The control itself takes the figure through its own `wait:` (KitButton,
/// KitSettingLink) or `waitLeft:` (KitComposerDock), which disable it and
/// draw the suffix in tabular figures; [KitConfirm] takes a `waitKey`.
///
/// **Write before you move:** nothing here changes until a refusal has
/// arrived. While the request is in flight the control shows its busy label,
/// never a countdown — callers pass `wait: busy ? 0 : wait.left`.
class KitWait extends StatefulWidget {
  /// A [WaitKey]; null waits on nothing (the builder sees
  /// [CooldownWait.none]).
  final String? waitKey;
  final Widget Function(BuildContext context, CooldownWait wait) builder;

  const KitWait({super.key, required this.waitKey, required this.builder});

  @override
  State<KitWait> createState() => _KitWaitState();
}

class _KitWaitState extends State<KitWait> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    Cooldowns.instance.addListener(_changed);
    _schedule();
  }

  @override
  void didUpdateWidget(covariant KitWait old) {
    super.didUpdateWidget(old);
    if (old.waitKey != widget.waitKey) _schedule();
  }

  @override
  void dispose() {
    Cooldowns.instance.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    _schedule();
  }

  /// One timer, to the next boundary of the figure, and none while idle.
  void _schedule() {
    _tick?.cancel();
    _tick = null;
    final next = Cooldowns.instance.untilNextSecond(widget.waitKey);
    if (next == null) return;
    _tick = Timer(next, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, Cooldowns.instance.of(widget.waitKey));
}

/// A control's label with its wait: the idle [label], then ` · m:ss` in
/// tabular figures so the label does not shift as it counts (`.btn-wait`). The
/// suffix inherits the control's face and colour, and at zero it is not there
/// at all — a plain `Text(label)`, byte-identical to a control that has never
/// waited.
Widget kitWaitLabel(
  String label,
  int wait, {
  required TextStyle style,
  int? maxLines,
  TextOverflow? overflow,
}) {
  if (wait < 1) {
    return Text(label, maxLines: maxLines, overflow: overflow, style: style);
  }
  return Text.rich(
    TextSpan(
      text: label,
      children: [
        TextSpan(
          text: waitSuffix(wait),
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ],
    ),
    maxLines: maxLines,
    overflow: overflow,
    style: style,
  );
}
