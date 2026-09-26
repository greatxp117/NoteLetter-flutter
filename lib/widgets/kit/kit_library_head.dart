part of 'kit_headers.dart';

// ── What sits under the Library's chapter opening (web `LibraryHome.jsx`,
// `shared/OnboardingChecklist.jsx`, `app-onboarding.css`, `app-responsive.css`
// `.lib-actions`) ─────────────────────────────────────────────────────────────
//
// A part of kit_headers.dart: both belong to the header's region — the
// reference draws them between the chapter opening and the first section.

/// One step of the setup checklist. [onTap] is where the step is done; a done
/// step has none.
class KitSetupStep {
  final String label;
  final bool done;
  final VoidCallback? onTap;

  const KitSetupStep(this.label, {required this.done, this.onTap});
}

/// The first-run setup checklist (goal gradient: the account is step one,
/// already done). Two forms, as the reference's:
///
/// * [compact] — the strip under the populated Library's chapter opening: a
///   caret, a 90px progress bar and `N of M set up` on a disclosure, the
///   remaining steps as pills while it is closed, and **Hide**. Below the
///   compact width the pills take their own full line (`.onboard-chips {
///   order: 3; flex: 1 0 100% }` at 680).
/// * the card — the empty Library's: `N of M` in serif beside a note, Hide,
///   the bar full width.
///
/// Opening either shows every step, the crossed-off ones included — the only
/// place completed setup is visible. What is expanded, hidden and done is the
/// HOST's (client-local flags, never Firestore): this widget only draws it.
class KitSetupChecklist extends StatelessWidget {
  final List<KitSetupStep> steps;
  final bool compact;
  final bool expanded;
  final ValueChanged<bool> onExpanded;
  final VoidCallback onHide;

  const KitSetupChecklist({
    super.key,
    required this.steps,
    required this.expanded,
    required this.onExpanded,
    required this.onHide,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final done = steps.where((s) => s.done).length;
    final frac = steps.isEmpty ? 0.0 : done / steps.length;
    final phone = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;

    Widget bar({double? width}) => Container(
          width: width,
          height: 4,
          decoration: BoxDecoration(
            color: t.surfaceSunken,
            borderRadius: BorderRadius.circular(999),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: frac,
            child: Container(
              decoration: BoxDecoration(
                color: t.accent,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        );

    Widget caret() => AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 200),
          child: Icon(Icons.chevron_right, size: 14, color: t.fgSubtle),
        );

    Widget hide() => Semantics(
          button: true,
          label: 'Hide setup checklist',
          excludeSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onHide,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.s1),
              child: Text('Hide',
                  style: KitText.ui(context, color: t.fgSubtle)
                      .copyWith(fontSize: 12)),
            ),
          ),
        );

    Widget disclose(List<Widget> children) => Semantics(
          button: true,
          expanded: expanded,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onExpanded(!expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
              child: Row(mainAxisSize: MainAxisSize.min, children: children),
            ),
          ),
        );

    final list = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _SetupStepRow(step: steps[i], last: i == steps.length - 1),
      ],
    );

    if (compact) {
      final remaining = steps.where((s) => !s.done).toList();
      final pills = Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          for (final s in remaining)
            _SetupPill(label: s.label, onTap: s.onTap, large: phone),
        ],
      );
      final summary = disclose([
        caret(),
        const SizedBox(width: AppSpacing.s2),
        bar(width: 90),
        const SizedBox(width: AppSpacing.s2),
        // Flexible: at 320 the label wraps rather than pushing Hide off the
        // row (`.onboard-disclose { flex: 1 1 auto; min-width: 0 }`).
        Flexible(
          child: Text('$done of ${steps.length} set up',
              style: KitText.ui(context, color: t.fgMuted)
                  .copyWith(fontSize: 14)),
        ),
      ]);
      // No bottom margin: the search row's 22 above it is the gap. CSS
      // collapses `.onboard-compact`'s 20 into `.lib-actions`' 22; stacked
      // widgets would ADD them.
      return Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4, vertical: AppSpacing.s2),
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: AppRadius.lgR,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (phone) ...[
              Row(children: [
                Expanded(
                    child: Align(
                        alignment: Alignment.centerLeft, child: summary)),
                const SizedBox(width: AppSpacing.s3),
                hide(),
              ]),
              if (!expanded && remaining.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s3),
                pills,
                const SizedBox(height: AppSpacing.s2),
              ],
            ] else
              Row(children: [
                summary,
                const SizedBox(width: AppSpacing.s3),
                Expanded(child: expanded ? const SizedBox() : pills),
                const SizedBox(width: AppSpacing.s3),
                hide(),
              ]),
            if (expanded)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.s2),
                padding: const EdgeInsets.only(top: AppSpacing.s1),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: t.border)),
                ),
                child: list,
              ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.s6),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s6, vertical: AppSpacing.s5),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.lgR,
        boxShadow: AppShadows.s1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              disclose([
                caret(),
                const SizedBox(width: AppSpacing.s2),
                Text('$done of ${steps.length}',
                    style: AppTheme.serif(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: t.fg)),
              ]),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  done <= 1
                      ? 'Your library is already underway — the account was '
                          'the first step.'
                      : 'Your library is taking shape.',
                  style: KitText.ui(context, color: t.fgMuted)
                      .copyWith(fontSize: 14),
                ),
              ),
              hide(),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          bar(),
          if (expanded) ...[
            const SizedBox(height: AppSpacing.s4),
            list,
          ],
        ],
      ),
    );
  }
}

class _SetupStepRow extends StatelessWidget {
  final KitSetupStep step;
  final bool last;

  const _SetupStepRow({required this.step, required this.last});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: !step.done,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: step.done ? null : step.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s1, vertical: AppSpacing.s2),
          decoration: BoxDecoration(
            border: last ? null : Border(bottom: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: step.done ? t.positiveChipBg : null,
                  border: Border.all(
                      color: step.done ? t.positive : t.borderStrong),
                ),
                child: step.done
                    ? Icon(Icons.check, size: 13, color: t.positiveChipFg)
                    : null,
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Text(
                  step.label,
                  style: AppTheme.serif(
                    fontSize: 16,
                    height: 24 / 16,
                    color: step.done ? t.fgSubtle : t.fg,
                  ).copyWith(
                    decoration: step.done ? TextDecoration.lineThrough : null,
                    decorationColor: t.fgSubtle,
                  ),
                ),
              ),
              if (!step.done)
                Icon(Icons.chevron_right, size: 14, color: t.fgSubtle),
            ],
          ),
        ),
      ),
    );
  }
}

/// `.onboard-chip` — a remaining step as a pill; a real tap target on a phone.
class _SetupPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool large;

  const _SetupPill({required this.label, this.onTap, this.large = false});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: large
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: KitText.ui(context, color: t.fgMuted)
                  .copyWith(fontSize: large ? 14 : 12)),
        ),
      ),
    );
  }
}

/// `.lib-actions` — the Library's search field and its Add a source button.
/// The field is a button that opens search (`Search your library by
/// meaning…`, italic serif, the `Vector` mode pill and the ⌘K hint on a wide
/// screen); Add a source is the accent primary. Below the compact width they
/// stack — the field, then Add a source full width and centred.
class KitLibraryActions extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onAdd;

  const KitLibraryActions(
      {super.key, required this.onSearch, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;

    final field = Semantics(
      button: true,
      label: 'Search your library by meaning',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSearch,
        child: Container(
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 13)
              : const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            color: t.surface,
            border: Border.all(color: t.borderStrong),
            borderRadius: AppRadius.lgR,
            boxShadow: AppShadows.s1,
          ),
          child: Row(
            children: [
              Icon(Icons.search, size: 18, color: t.fgMuted),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  'Search your library by meaning…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: phone ? 16 : 18,
                    fontStyle: FontStyle.italic,
                    color: t.fgSubtle,
                  ),
                ),
              ),
              if (!phone) ...[
                const SizedBox(width: 13),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('VECTOR',
                      style: AppTheme.mono(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: t.accentText)),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final add = Semantics(
      button: true,
      label: 'Add a source',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onAdd,
        child: Container(
          padding: phone
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 13)
              : const EdgeInsets.fromLTRB(16, 0, 18, 0),
          decoration: BoxDecoration(
            color: t.accent,
            borderRadius: AppRadius.lgR,
            boxShadow: AppShadows.s1,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 16, color: t.accentFg),
              const SizedBox(width: 9),
              Text('Add a source',
                  style: KitText.ui(context, color: t.accentFg).copyWith(
                      fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );

    // `margin: 22px 0 6px` — the 6 collapses into the next section header's
    // 32, so none is drawn here.
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, const SizedBox(height: 12), add],
            )
          : IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 12),
                  add,
                ],
              ),
            ),
    );
  }
}
