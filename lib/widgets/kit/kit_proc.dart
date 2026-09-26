part of 'kit_controls.dart';

// ── A document being processed (screens/sources.md §Composition, 4.98.0,
// ADR-131; web `SourcesBrowse.jsx` ProcRow + `app-sources-browse.css` .proc-*) ──
//
// One CARD per document, the stage in a STATUS PILL — never in the subtitle.
// The composition line said "keep the row anatomy and carry the stage in the
// subtitle" until 4.98.0, contradicting §Document processing's own table; web
// had always drawn this.

/// The pill's tone, from §Document processing's table (web `procPill`).
enum KitProcTone { work, wait, done, fail, hold }

/// `.proc-pill`: mono 10 caps at `--r-pill`, toned; `work` leads with a
/// spinner, `fail` with the alert glyph.
class KitProcPill extends StatelessWidget {
  final String label;
  final KitProcTone tone;

  const KitProcPill(this.label, {super.key, required this.tone});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final (bg, fg) = switch (tone) {
      KitProcTone.work => (t.accentSoft, t.accentChipFg),
      KitProcTone.wait => (t.surfaceSunken, t.fgMuted),
      KitProcTone.done => (t.positiveChipBg, t.positiveChipFg),
      KitProcTone.fail => (t.accentSoft, t.criticalText),
      KitProcTone.hold => (t.surfaceSunken, t.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tone == KitProcTone.work) ...[
            // `.proc-spinner`: 11px, a 1.5px ring in the chip border with its
            // head in accent text.
            SizedBox(
              width: 11,
              height: 11,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.accentText,
                backgroundColor: t.accentChipBorder,
              ),
            ),
            const SizedBox(width: 7),
          ],
          if (tone == KitProcTone.fail) ...[
            Icon(Icons.warning_amber_rounded, size: 12, color: fg),
            const SizedBox(width: 7),
          ],
          Text(
            label.toUpperCase(),
            style: KitText.capsLabel(context,
                fontSize: 10, letterSpacing: 0.06, color: fg),
          ),
        ],
      ),
    );
  }
}

/// `.proc-row`: a `--surface` card (1px `--border`, `--r-md`, `--shadow-1`)
/// whose top line is a 32×40 File badge, the title (serif 15/500, one line)
/// over a mono 11 `--fg-subtle` subtitle, and the trailing [pill]; beneath it
/// [foot] — the progress strip while working, the ruled attention strip when
/// the row needs a person. Below the compact width the pill drops under the
/// title, as web's does at 720.
class KitProcCard extends StatelessWidget {
  final String kind;
  final String title;
  final String subtitle;
  final Widget pill;
  final Widget foot;

  /// A failed row's edge takes the accent chip border (`.proc-row.failed`).
  final bool failed;

  const KitProcCard({
    super.key,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.pill,
    required this.foot,
    this.failed = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.serif(
                fontSize: 15, fontWeight: FontWeight.w500, color: t.fg)),
        const SizedBox(height: 2),
        Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.mono(fontSize: 11, color: t.fgSubtle)),
        if (compact) ...[
          const SizedBox(height: 8),
          pill,
        ],
      ],
    );
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: failed ? t.accentChipBorder : t.border),
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s1,
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Row(
              crossAxisAlignment: compact
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                KitFileBadge(kind, size: KitBadgeSize.proc),
                const SizedBox(width: 14),
                Expanded(child: info),
                if (!compact) ...[
                  const SizedBox(width: 14),
                  pill,
                ],
              ],
            ),
          ),
          foot,
        ],
      ),
    );
  }
}

/// `.proc-active`: the 3px bar (indeterminate — ADR-024 declines to
/// synthesise a server-side percentage; determinate only for an upload's own
/// fraction), then the trailing controls.
class KitProcActive extends StatelessWidget {
  final double? fraction;
  final bool queued;
  final List<Widget> actions;

  const KitProcActive(
      {super.key, this.fraction, this.queued = false, required this.actions});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: fraction,
                backgroundColor: t.surfaceSunken,
                color: queued || fraction == null ? t.borderStrong : t.accent,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ...actions,
        ],
      ),
    );
  }
}

/// `.proc-error`: a `--rule` above, the italic serif detail sentence, an
/// optional §14.2 [failure], then the actions — trailing beside the sentence
/// on a wide row, under it (right-aligned) below the compact width.
class KitProcAttention extends StatelessWidget {
  final String detail;
  final Widget? failure;
  final List<Widget> actions;

  const KitProcAttention(
      {super.key, required this.detail, this.failure, required this.actions});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(detail,
            style: AppTheme.serif(
                fontSize: 14,
                height: 20 / 14,
                fontStyle: FontStyle.italic,
                color: t.fgLede)),
        if (failure != null) ...[const SizedBox(height: 6), failure!],
      ],
    );
    final acts = Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: actions,
    );
    return Container(
      padding: const EdgeInsets.only(top: 12, bottom: 14),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: t.rule))),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerRight, child: acts),
              ],
            )
          : Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                acts,
              ],
            ),
    );
  }
}
