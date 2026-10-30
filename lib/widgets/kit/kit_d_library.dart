// The Library's and Add a source's own D parts (screens/sources.md
// §Composition; web `pages/SourcesBrowse.jsx`, `pages/AddSource.jsx`,
// `pages/sources/intake.jsx`, `pages/sources/proc.jsx` + `styles/
// app-library.css`): the cloud notices, the service rows, the processing rows
// and arrivals, the Shelf facet, the jump letters. A page file never styles
// its own type or spacing (ADR-041), so a part only these pages draw still
// lives in the kit.

import 'dart:math' as math;

import 'package:flutter/material.dart'
    show
        Icons,
        InputBorder,
        InputDecoration,
        TextField,
        TextInputAction,
        TextInputType;
import 'package:flutter/widgets.dart';

import '../../theme/app_motion.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitProcTone;
import 'kit_d_frame.dart' show KitSheetScope;
import 'kit_d_home.dart' show KitHxLink;
import 'kit_d_parts.dart';
import 'kit_d_shelf.dart' show KitShelfRow, KitShelfRows;
import 'kit_provider_logo.dart';
import 'kit_shell.dart' show KitGlyph;
import 'kit_wait.dart' show kitWaitLabel;

// ── The cloud notices (`.lx-notices`, `.lx-notice`) ─────────────────────────

/// One cloud notice: a sentence on a 2px rule — `--positive`, or `--accent`
/// for a reason banner ([warn]) — set in the standfirst's italic serif
/// (17/26 `--fg-lede`), with a trailing *Dismiss* where it can be dismissed.
/// [status] announces it (the claim in flight).
class KitLibNotice extends StatelessWidget {
  final String text;
  final bool warn;
  final bool status;
  final VoidCallback? onDismiss;

  const KitLibNotice(
    this.text, {
    super.key,
    this.warn = false,
    this.status = false,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final sentence = Text(
      text,
      style: AppTheme.serif(
        fontSize: 17,
        height: 26 / 17,
        fontStyle: FontStyle.italic,
        color: t.fgLede,
        opsz: 18,
      ),
    );
    final dismiss = onDismiss == null
        ? null
        : KitHxLink('Dismiss', onTap: onDismiss);
    return Semantics(
      liveRegion: status,
      container: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 2, 0, 2),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: warn ? t.accent : t.positive, width: 2),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            // `flex: 1 1 320px` beside the link: the link takes the next line
            // once the sentence would fall under 320.
            if (dismiss == null) return sentence;
            if (c.maxWidth >= 320 + 18 + 72) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: sentence),
                  const SizedBox(width: 18),
                  dismiss,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [sentence, const SizedBox(height: 6), dismiss],
            );
          },
        ),
      ),
    );
  }
}

/// The notices strip between the masthead and the grid: 24 above the first,
/// 16 apart; with nothing to say it takes no room.
class KitLibNotices extends StatelessWidget {
  final List<Widget> children;
  const KitLibNotices({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 24 : 16),
            child: children[i],
          ),
      ],
    );
  }
}

/// `.lx-note` — a calm line under a part (a disconnect's outcome, a
/// playlist's measured count): sans 12.5/18 `--fg-muted`, 10 above.
class KitLibNote extends StatelessWidget {
  final String text;
  final bool status;
  const KitLibNote(this.text, {super.key, this.status = true});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: status,
    child: Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: AppTheme.fontSans,
          fontSize: 12.5,
          height: 18 / 12.5,
          color: Tokens.of(context).fgMuted,
        ),
      ),
    ),
  );
}

// ── The row's quiet actions (`.lx-act`) ─────────────────────────────────────

/// A processing row's or a service row's action as quiet underlined text:
/// sans 12.5/18 `--fg-muted`, underlined `--border-strong`; [strong] (Retry,
/// Index it anyway, Connect) in `--fg` 500 underlined `--link-decor`. Hover
/// `--fg`; held at `--held-opacity` while [onTap] is null or [wait] runs, the
/// wait's ` · m:ss` after the label (§6.1).
class KitLibAct extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool strong;
  final int wait;

  const KitLibAct(
    this.label, {
    super.key,
    this.onTap,
    this.icon,
    this.strong = false,
    this.wait = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final held = onTap == null || wait > 0;
    return Opacity(
      opacity: held ? AppSpacing.heldOpacity : 1,
      child: KitDTap(
        label: label,
        enabled: !held,
        onTap: held ? null : onTap,
        builder: (context, hover, focus) {
          final fg = strong || hover ? t.fg : t.fgMuted;
          final line = strong || hover ? t.linkDecor : t.borderStrong;
          return Container(
            constraints: const BoxConstraints(minHeight: 24),
            alignment: Alignment.centerLeft,
            decoration: focus
                ? BoxDecoration(
                    border: Border.all(color: t.accent, width: 2),
                    borderRadius: BorderRadius.circular(3),
                  )
                : null,
            // In a narrow arrival the label ellipsizes rather than
            // overflowing its column; beside a service row it takes its own
            // width.
            child: LayoutBuilder(
              builder: (context, c) {
                final text = kitWaitLabel(
                  label,
                  wait,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 12.5,
                    height: 18 / 12.5,
                    fontWeight: strong ? FontWeight.w500 : FontWeight.w400,
                    color: fg,
                    decoration: TextDecoration.underline,
                    decorationColor: line,
                  ),
                );
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      KitGlyph(icon!, size: 13, color: fg),
                      const SizedBox(width: 5),
                    ],
                    c.maxWidth.isFinite ? Flexible(child: text) : text,
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// `.lx-acts` — a row's actions, wrapping `4px 14px` (an arrival's `2px 12px`).
class KitLibActs extends StatelessWidget {
  final List<Widget> children;
  final bool tight;
  final WrapAlignment alignment;

  const KitLibActs({
    super.key,
    required this.children,
    this.tight = false,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: alignment,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: tight ? 12 : 14,
    runSpacing: tight ? 2 : 4,
    children: children,
  );
}

// ── Correspondence: the services (`.lx-svc`) ────────────────────────────────

/// One service that sends the library volumes: its mark on a white plate (32,
/// `--r-c-32`), its name (serif 16/21), *Connected* with a `--positive` dot in
/// `--positive-text` or its [line] (sans 12/17 `--fg-muted`), and one quiet
/// [action]. A refused connect ([failure], §14.2) runs under the name.
///
/// The camera roll's row (sources.md §Camera roll, the first in
/// Correspondence on a client with a photo library) is the same row with a
/// [glyph] in place of a vendor's [provider] mark — on the prototype's plate
/// (`.lx-svc-logo`: `--surface` inside a 1px `--border`, the glyph 17 in
/// `--fg`; F-146) — a [critical] line (`--critical-text`) where a failure
/// stands, no [line] where its store could not be read ([failure] says so),
/// and [on] (`.lx-svc.on`): its own line after the `--positive` dot, in
/// `--positive-text`, while it is looking, waiting or on.
class KitServiceRow extends StatelessWidget {
  final String? provider;
  final IconData? glyph;
  final String name;
  final String? line;
  final bool connected;
  final bool on;
  final bool critical;
  final Widget? action;
  final Widget? failure;

  const KitServiceRow({
    super.key,
    this.provider,
    this.glyph,
    required this.name,
    this.line,
    this.connected = false,
    this.on = false,
    this.critical = false,
    this.action,
    this.failure,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final lineStyle = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 12,
      height: 17 / 12,
      color: connected || on
          ? t.positiveText
          : critical
          ? t.criticalText
          : t.fgMuted,
    );
    final mark = provider != null
        ? Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              // literal-ok: a vendor brand-mark plate — fixed white in both
              // themes (Notion's mark is black; web `.lx-svc-logo`).
              color: const Color(0xFFFFFFFF),
              borderRadius: AppRadius.controlR(32),
              border: Border.all(color: t.border),
            ),
            child: KitProviderLogo(provider: provider!, size: 18),
          )
        : Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.controlR(32),
              border: Border.all(color: t.border),
            ),
            child: KitGlyph(
              glyph ?? Icons.photo_camera_outlined,
              size: 17,
              color: t.fg,
            ),
          );
    final shown = connected ? 'Connected' : line;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              mark,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.serif(
                        fontSize: 16,
                        height: 21 / 16,
                        color: t.fg,
                      ),
                    ),
                    if (shown != null)
                      Row(
                        children: [
                          if (connected || on) ...[
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: t.positive,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              shown,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: lineStyle,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (action != null) ...[const SizedBox(width: 12), action!],
            ],
          ),
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(left: 44, top: 4),
              child: failure!,
            ),
        ],
      ),
    );
  }
}

/// The services as a list (nothing connected: a column at most 680 wide) or,
/// with a service connected, a compact grid of `minmax(300px, 1fr)` columns
/// 36 apart, 36 above the cloud panels.
class KitServiceList extends StatelessWidget {
  final List<Widget> rows;
  final bool compact;

  const KitServiceList({super.key, required this.rows, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (!compact) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: KitLibGrid(min: 300, colGap: 36, rowGap: 0, children: rows),
    );
  }
}

/// `repeat(auto-fill, minmax({min}px, 1fr))` — as many equal columns of at
/// least [min] as fit, [colGap] and [rowGap] apart. The arrivals' grid and
/// the catalogue's wall (`136`, `30px 26px`), the services' (`300`, `36`).
class KitLibGrid extends StatelessWidget {
  final double min;
  final double colGap;
  final double rowGap;

  /// Room above the grid: the arrivals' 10, the wall's 14.
  final double top;
  final List<Widget> children;

  const KitLibGrid({
    super.key,
    required this.children,
    this.min = 136,
    this.colGap = 26,
    this.rowGap = 30,
    this.top = 0,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top),
    child: LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth.isFinite ? c.maxWidth : min;
        final n = math.max(1, ((w + colGap) / (min + colGap)).floor());
        final itemW = (w - (n - 1) * colGap) / n;
        return Wrap(
          spacing: colGap,
          runSpacing: rowGap,
          children: [
            for (final ch in children) SizedBox(width: itemW, child: ch),
          ],
        );
      },
    ),
  );
}

// ── Being catalogued: the stage and the bar (`.lx-stage`, `.lx-bar`) ────────

/// A document's stage in the pipeline: mono 10.5/`.12em` caps — `work` with
/// a pulsing dot in `--fg-muted`, `wait` in `--fg-subtle`, `fail` in
/// `--critical-text` with the alert glyph, `done` in `--positive-text`. The
/// dot holds still under reduced motion.
class KitLibStage extends StatefulWidget {
  final String label;
  final KitProcTone tone;

  const KitLibStage(this.label, {super.key, required this.tone});

  @override
  State<KitLibStage> createState() => _KitLibStageState();
}

class _KitLibStageState extends State<KitLibStage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(KitLibStage old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.tone == KitProcTone.work && !KitD.still(context);
    if (run && !_c.isAnimating) _c.repeat(reverse: true);
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fg = switch (widget.tone) {
      KitProcTone.fail => t.criticalText,
      KitProcTone.done => t.positiveText,
      KitProcTone.wait => t.fgSubtle,
      KitProcTone.work || KitProcTone.hold => t.fgMuted,
    };
    final dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.tone == KitProcTone.work) ...[
          KitD.still(context)
              ? dot
              : AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => Opacity(
                    opacity:
                        0.35 + 0.65 * AppMotion.easeInOut.transform(_c.value),
                    child: child,
                  ),
                  child: dot,
                ),
          const SizedBox(width: 6),
        ],
        if (widget.tone == KitProcTone.fail) ...[
          Icon(Icons.warning_amber_rounded, size: 11, color: fg),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            widget.label.toUpperCase(),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.mono(
              fontSize: 10.5,
              letterSpacing: 0.12 * 10.5,
              color: fg,
            ),
          ),
        ),
      ],
    );
  }
}

/// `.lx-bar` — a row's 32px bar: [live] while a document is actually being
/// read, [value] while its bytes leave this device (the measured fraction),
/// [done] in `--positive` as it joins the catalogue; the fill `--fg-muted`.
class KitLibBar extends StatelessWidget {
  final bool live;
  final double? value;
  final bool done;
  const KitLibBar({super.key, this.live = false, this.value, this.done = false});

  @override
  Widget build(BuildContext context) => KitStageBar(
    live: live,
    value: value,
    done: done,
    fill: Tokens.of(context).fgMuted,
  );
}

/// `.lx-proc-msg` — the detail sentence of a row that needs the reader: serif
/// italic 14/20 `--fg-lede` (an arrival's 13/18).
class KitLibProcMessage extends StatelessWidget {
  final String text;
  final bool small;
  const KitLibProcMessage(this.text, {super.key, this.small = false});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTheme.serif(
      fontSize: small ? 13 : 14,
      height: small ? 18 / 13 : 20 / 14,
      fontStyle: FontStyle.italic,
      color: Tokens.of(context).fgLede,
    ),
  );
}

// ── Being catalogued: the row (`.lx-proc`) ──────────────────────────────────

/// A source in the pipeline as a register row: the cover's [word] for its
/// type (mono caps `--fg-subtle`), the [title] (serif 500 16.5/22), its
/// [stage], a 32px [bar] — or, when it needs the reader ([attention]), the
/// detail [message] — then its [wait] sentence, its [refusal] and its
/// [actions]. A container 720 or wider runs it as
/// `104px minmax(0,1.5fr) minmax(150px,.9fr) auto`; narrower, word and stage
/// share the first line and the title takes the next.
class KitLibProcRow extends StatelessWidget {
  final String word;
  final String title;
  final Widget stage;
  final Widget? bar;
  final String? message;
  final Widget? wait;
  final Widget? refusal;
  final Widget? actions;
  final bool attention;

  const KitLibProcRow({
    super.key,
    required this.word,
    required this.title,
    required this.stage,
    this.bar,
    this.message,
    this.wait,
    this.refusal,
    this.actions,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final wordText = Text(
      word.toUpperCase(),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.mono(
        fontSize: 10.5,
        letterSpacing: 0.12 * 10.5,
        color: t.fgSubtle,
      ),
    );
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.serif(
        fontSize: 16.5,
        height: 22 / 16.5,
        fontWeight: FontWeight.w500,
        color: t.fg,
      ),
    );
    final msg = message == null ? null : KitLibProcMessage(message!);
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final List<Widget> lines;
        if (!wide) {
          lines = [
            Row(
              children: [
                Expanded(child: wordText),
                const SizedBox(width: 18),
                Flexible(child: stage),
              ],
            ),
            const SizedBox(height: 4),
            titleText,
            if (attention) ...[
              if (msg != null) ...[const SizedBox(height: 4), msg],
              if (wait != null) ...[const SizedBox(height: 4), wait!],
              if (refusal != null) ...[const SizedBox(height: 4), refusal!],
              if (actions != null) ...[const SizedBox(height: 8), actions!],
            ] else ...[
              if (bar != null || actions != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (bar != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: bar!,
                      ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: actions ?? const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ],
              if (wait != null) ...[const SizedBox(height: 4), wait!],
              if (refusal != null) ...[const SizedBox(height: 4), refusal!],
            ],
          ];
          return Container(
            padding: const EdgeInsets.fromLTRB(0, 11, 0, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.rule)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: lines,
            ),
          );
        }
        const indent = 104.0 + 22;
        Widget under(Widget w, [double top = 3]) => Padding(
          padding: EdgeInsets.only(left: indent, top: top),
          child: w,
        );
        final head = Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: 104, child: wordText),
            const SizedBox(width: 22),
            Expanded(flex: 15, child: titleText),
            const SizedBox(width: 22),
            if (attention)
              stage
            else ...[
              Expanded(
                flex: 9,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 150),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      stage,
                      if (bar != null) ...[const SizedBox(height: 5), bar!],
                    ],
                  ),
                ),
              ),
              if (actions != null) ...[const SizedBox(width: 22), actions!],
            ],
          ],
        );
        return Container(
          padding: const EdgeInsets.fromLTRB(0, 14, 8, 14),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.rule)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              head,
              if (attention && msg != null) under(msg),
              if (wait != null) under(wait!),
              if (refusal != null) under(refusal!),
              if (attention && actions != null) under(actions!, 7),
            ],
          ),
        );
      },
    );
  }
}

// ── Being catalogued in Grid: the arrival (`.lx-arr`) ───────────────────────

/// In Grid, a source in the pipeline arrives face-out: a ruled slip (7:10)
/// with its [word], [title] and [author] and its [bar] — or, when it needs the
/// reader ([attention]), a [stamp] (*Couldn’t be read*, *Stalled*) — then its
/// [stage], [message], wait, refusal and [actions] under the slip, 7 apart.
class KitArrivalSlip extends StatelessWidget {
  final String word;
  final String title;
  final String? author;
  final Widget stage;
  final Widget? bar;
  final String? stamp;
  final String? message;
  final Widget? wait;
  final Widget? refusal;
  final Widget? actions;
  final bool attention;

  const KitArrivalSlip({
    super.key,
    required this.word,
    required this.title,
    required this.stage,
    this.author,
    this.bar,
    this.stamp,
    this.message,
    this.wait,
    this.refusal,
    this.actions,
    this.attention = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    // color-mix(in oklab, --critical 45%, --border), mixed in sRGB.
    final edge = attention ? Color.lerp(t.border, t.critical, 0.45)! : t.border;
    final slip = AspectRatio(
      aspectRatio: 7 / 10,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          final em = w * 0.104;
          return CustomPaint(
            painter: _RuledSlip(
              ground: t.surface,
              rule: t.rule,
              edge: edge,
              step: 1.9 * em,
            ),
            child: Stack(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    0.13 * w,
                    0.13 * w,
                    0.11 * w,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        word.toUpperCase(),
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: AppTheme.mono(
                          fontSize: 0.58 * em,
                          letterSpacing: 0.18 * 0.58 * em,
                          color: t.fgSubtle,
                        ),
                      ),
                      SizedBox(height: 0.6 * em),
                      Text(
                        title,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                          fontSize: 1.08 * em,
                          height: 1.18,
                          fontWeight: FontWeight.w600,
                          color: t.fgMuted,
                        ),
                      ),
                      if (author != null && author!.isNotEmpty) ...[
                        SizedBox(height: 0.35 * em),
                        Text(
                          author!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.serif(
                            fontSize: 0.8 * em,
                            fontStyle: FontStyle.italic,
                            color: t.fgSubtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (stamp != null)
                  Positioned(
                    left: 0.1 * w,
                    right: 0.1 * w,
                    bottom: 0.12 * w * 10 / 7,
                    child: Transform.rotate(
                      angle: -5 * math.pi / 180,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          vertical: 0.35 * 0.58 * em * 1.6,
                          horizontal: 0.4 * 0.58 * em * 1.6,
                        ),
                        decoration: BoxDecoration(
                          color: t.surface.withValues(alpha: 0.88),
                          border: Border.all(color: t.criticalText, width: 1.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          stamp!.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: AppTheme.mono(
                            fontSize: 0.58 * em,
                            letterSpacing: 0.14 * 0.58 * em,
                            color: t.criticalText,
                          ),
                        ),
                      ),
                    ),
                  )
                else if (bar != null)
                  Positioned(
                    left: 0.13 * w,
                    bottom: 0.1 * w * 10 / 7,
                    child: bar!,
                  ),
              ],
            ),
          );
        },
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        slip,
        const SizedBox(height: 7),
        stage,
        if (attention && message != null) ...[
          const SizedBox(height: 7),
          KitLibProcMessage(message!, small: true),
        ],
        if (wait != null) ...[const SizedBox(height: 7), wait!],
        if (refusal != null) ...[const SizedBox(height: 7), refusal!],
        if (actions != null) ...[const SizedBox(height: 7), actions!],
      ],
    );
  }
}

class _RuledSlip extends CustomPainter {
  final Color ground, rule, edge;
  final double step;
  _RuledSlip({
    required this.ground,
    required this.rule,
    required this.edge,
    required this.step,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndCorners(
      Offset.zero & size,
      topLeft: const Radius.circular(2),
      bottomLeft: const Radius.circular(2),
      topRight: const Radius.circular(5),
      bottomRight: const Radius.circular(5),
    );
    canvas.save();
    canvas.clipRRect(r);
    canvas.drawRect(Offset.zero & size, Paint()..color = ground);
    final line = Paint()..color = rule;
    if (step > 1) {
      for (var y = step - 1; y < size.height; y += step) {
        canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), line);
      }
    }
    final e = Paint()..color = edge;
    // inset 0 0 0 1px, inset 3px 0 0 — the slip's hairline and its spine.
    canvas.drawRect(Rect.fromLTWH(0, 0, 3, size.height), e);
    canvas.restore();
    canvas.drawRRect(
      r.deflate(0.5),
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_RuledSlip old) =>
      old.ground != ground ||
      old.rule != rule ||
      old.edge != edge ||
      old.step != step;
}

// ── The sheet: the Shelf facet (`.lx-shelf`) ────────────────────────────────

/// One row of [KitShelfFacet]: a shelf in tree order ([depth] > 0 is nested),
/// its colour (resolved for the theme; null draws `--border-strong`) and its
/// subtree's complete volumes.
class KitShelfFacetItem {
  final String id;
  final String title;
  final Color? color;
  final int depth;
  final int count;

  const KitShelfFacetItem(
    this.id,
    this.title, {
    this.color,
    this.depth = 0,
    required this.count,
  });
}

/// The sheet's Shelf facet: *Every shelf*, then every shelf in tree order —
/// serif 16 `--fg-muted`, `8px 0`, a 1px `--rule`, an 8×11 swatch of its
/// colour, a nested one 18 in and italic, the count mono 11 `--fg-subtle`, the
/// chosen row `--fg` 600 with the 6px accent dot 16 to its left. Stacked or
/// docked the rows run as wrapping lines (a nested one not indented). Absent
/// with no shelves. Pressing the chosen row does nothing.
class KitShelfFacet extends StatelessWidget {
  final List<KitShelfFacetItem> items;

  /// The chosen shelf's id, or null for *Every shelf*.
  final String? value;
  final ValueChanged<String?> onChanged;
  final int total;

  const KitShelfFacet({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final dock = KitSheetScope.maybeOf(context)?.dock ?? false;

    // The row is the kit's `.lx-shelf` ([KitShelfRow]); a facet's chosen row
    // is inert, and a choice folds the running head.
    Widget row(String? id, String title, Color? color, int depth, int count) =>
        KitShelfRow(
          title: title,
          color: color,
          count: '$count',
          sub: depth > 0,
          on: id == value,
          chosenInert: true,
          onTap: () => onChanged(id),
        );

    final rows = <Widget>[
      row(null, 'Every shelf', null, 0, total),
      for (final it in items) row(it.id, it.title, it.color, it.depth, it.count),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Shelf',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitDLabel('Shelf', top: dock ? 16 : 22),
          KitShelfRows(children: rows),
        ],
      ),
    );
  }
}

// ── The sheet: Order (`.lx-order-f`) ─────────────────────────────────────────

/// The sheet's *Order* group: its mono label, then a §34 Switch named *Order
/// by* filling the sheet's width — 36 tall on a phone. It moves only when
/// [value] moves.
class KitLibOrder extends StatelessWidget {
  final List<(String, String)> options;
  final String value;
  final ValueChanged<String> onChanged;

  const KitLibOrder({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dock = KitSheetScope.maybeOf(context)?.dock ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KitDLabel('Order', top: dock ? 16 : 22),
        KitSlideSwitch<String>(
          label: 'Order by',
          fill: true,
          height: KitD.phone(context) ? 36 : null,
          value: value,
          onChanged: onChanged,
          options: [for (final o in options) KitSlideOption(o.$1, o.$2)],
        ),
      ],
    );
  }
}

// ── The catalogue: the jump letters (`.lx-jump`) ────────────────────────────

/// A–Z's row of letters that jumps to one: 30×30, serif 15 `--fg`; a letter
/// no volume files under is held (`--fg-subtle` at `--held-opacity`). 14 above.
class KitJumpLetters extends StatelessWidget {
  final Set<String> have;
  final ValueChanged<String> onJump;

  const KitJumpLetters({super.key, required this.have, required this.onJump});

  static const letters = [
    'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', //
    'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
  ];

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Jump to a letter',
      child: Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [
            for (final c in letters)
              Opacity(
                opacity: have.contains(c) ? 1 : AppSpacing.heldOpacity,
                child: KitDTap(
                  label: c,
                  enabled: have.contains(c),
                  onTap: have.contains(c) ? () => onJump(c) : null,
                  builder: (context, hover, focus) => Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hover && have.contains(c) ? t.hover : null,
                      borderRadius: AppRadius.controlR(28),
                      border: focus
                          ? Border.all(color: t.accent, width: 2)
                          : null,
                    ),
                    child: Text(
                      c,
                      style: AppTheme.serif(
                        fontSize: 15,
                        color: !have.contains(c)
                            ? t.fgSubtle
                            : hover
                            ? t.accentText
                            : t.fg,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── The running head's line (`LibPeek`, Add a source's peek) ─────────────────

/// The Library's and Add a source's phone peek: a glyph, the [title] (serif
/// 600 16.5/22), an optional mono caps [meta], and at the trailing edge a
/// [count] in mono with its [tail] subtler (` of 7`, ` of 3 ready`).
class KitLibPeek extends StatelessWidget {
  final IconData? icon;

  /// What leads the line in place of the glyph — a shelf's swatch
  /// ([KitShelfSwatch], web `.dp-peek-sw`).
  final Widget? mark;
  final String title;
  final String? meta;
  final String? count;
  final String? tail;

  /// The title while the page's read is out: `--fg-muted` (web
  /// `.d-peek-t.d-peek-wait`).
  final bool wait;

  const KitLibPeek({
    super.key,
    this.icon,
    this.mark,
    required this.title,
    this.meta,
    this.count,
    this.tail,
    this.wait = false,
  }) : assert(icon != null || mark != null);

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        mark ?? KitGlyph(icon!, size: 16, color: t.fgMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 16.5,
                    height: 22 / 16.5,
                    fontWeight: FontWeight.w600,
                    color: wait ? t.fgMuted : t.fg,
                    opsz: 18,
                  ),
                ),
              ),
              if (meta != null && meta!.isNotEmpty) ...[
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    meta!.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.mono(
                      fontSize: 10.5,
                      letterSpacing: 0.12 * 10.5,
                      color: t.fgMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text.rich(
            TextSpan(
              text: count,
              style: AppTheme.mono(fontSize: 11.5, color: t.fg),
              children: [
                if (tail != null)
                  TextSpan(
                    text: tail,
                    style: AppTheme.mono(fontSize: 11.5, color: t.fgSubtle),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ── The empty catalogue: the drop zone card and the link field ──────────────

/// `.lx-dz-card` — the empty catalogue's drop zone, a keyboard-operable
/// control named [label]: the upload glyph (22, `--accent`), [title] (serif
/// 600 20/1.2) and [sub] (sans 12.5/18 `--fg-muted`) on a 1.5px dashed
/// `--border-strong` card; hover `--accent` and `--hover`.
class KitDropCard extends StatelessWidget {
  final String title;
  final String sub;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  const KitDropCard({
    super.key,
    required this.title,
    required this.sub,
    required this.icon,
    this.label = 'Add files',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return KitDTap(
      label: label,
      onTap: onTap,
      builder: (context, hover, focus) => CustomPaint(
        painter: _DashedCard(
          color: hover || focus ? t.accent : t.borderStrong,
          fill: hover ? t.hover : null,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              KitGlyph(icon, size: 22, color: t.accent),
              const SizedBox(height: 12),
              Text(
                title,
                style: AppTheme.serif(
                  fontSize: 20,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: t.fg,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                sub,
                style: TextStyle(
                  fontFamily: AppTheme.fontSans,
                  fontSize: 12.5,
                  height: 18 / 12.5,
                  color: t.fgMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedCard extends CustomPainter {
  final Color color;
  final Color? fill;
  const _DashedCard({required this.color, this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(2),
    );
    if (fill != null) canvas.drawRRect(rr, Paint()..color = fill!);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(rr.deflate(0.75));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        final next = math.min(d + 4.5, m.length);
        canvas.drawPath(m.extractPath(d, next), paint);
        d = next + 4.5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCard old) =>
      old.color != color || old.fill != fill;
}

/// `.lx-link` — the empty catalogue's link field: the link glyph, a 42-tall
/// serif 16 field over a 1px `--border-strong` rule (`--accent` in focus), the
/// placeholder italic `--fg-subtle`, and *Add link* (30 tall, `--r-c-32`,
/// `--secondary`), held on an empty field.
class KitLibLinkField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final bool submitting;
  final String placeholder;

  const KitLibLinkField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    this.submitting = false,
    this.placeholder = 'Paste a link — article, video, or podcast…',
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final style = AppTheme.serif(fontSize: 16, color: t.fg);
    return ListenableBuilder(
      listenable: Listenable.merge([focusNode, controller]),
      builder: (context, _) {
        final empty = controller.text.trim().isEmpty;
        final held = submitting || empty;
        return Container(
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: focusNode.hasFocus ? t.accent : t.borderStrong,
              ),
            ),
          ),
          child: Row(
            children: [
              KitGlyph(Icons.link, size: 15, color: t.fgSubtle),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: Center(
                    child: Semantics(
                      label: 'Paste a link',
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        style: style,
                        cursorColor: t.accent,
                        onSubmitted: (_) => onSubmit(),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          hintText: placeholder,
                          hintMaxLines: 1,
                          hintStyle: style.copyWith(
                            fontStyle: FontStyle.italic,
                            color: t.fgSubtle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Opacity(
                opacity: held ? AppSpacing.heldOpacity : 1,
                child: KitDTap(
                  label: 'Add link',
                  enabled: !held,
                  onTap: held ? null : onSubmit,
                  builder: (context, hover, focus) => AnimatedContainer(
                    duration: KitD.dur(context, AppMotion.durFast),
                    height: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hover && !held ? t.secondaryHover : t.secondary,
                      borderRadius: AppRadius.controlR(32),
                      border: focus
                          ? Border.all(color: t.accent, width: 2)
                          : null,
                    ),
                    child: Text(
                      submitting ? 'Adding…' : 'Add link',
                      maxLines: 1,
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 12.5,
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

// ── What adding answered (`.dz-rejection`, §12) ─────────────────────────────

/// A file or link the library would not take, by NAME (§12 Notice,
/// `.dz-rejection`): the name in `--critical-text` 600, then ` — ` and the
/// sentence in sans 13 `--fg-muted`, on the accent chip ground. A batch that
/// silently drops what it would not take is the failure ADR-046 replaced.
class KitRefusedNotice extends StatelessWidget {
  final String name;
  final String reason;

  const KitRefusedNotice({super.key, required this.name, required this.reason});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final base = TextStyle(
      fontFamily: AppTheme.fontSans,
      fontSize: 13,
      height: 1.45,
      color: t.fgMuted,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.accentChipBg,
        border: Border.all(color: t.accentChipBorder),
        borderRadius: AppRadius.smR,
      ),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(
              text: name,
              style: base.copyWith(
                color: t.criticalText,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: ' — $reason'),
          ],
        ),
      ),
    );
  }
}

/// `.dz-rejections` — the refused files and links, 12 above, 8 apart; read
/// out as an alert.
class KitRefusedNotices extends StatelessWidget {
  final List<KitRefusedNotice> children;
  const KitRefusedNotices({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      container: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

