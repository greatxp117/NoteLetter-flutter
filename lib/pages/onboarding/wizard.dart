import 'package:flutter/material.dart' show Icons, Material;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../models/document.dart';
import '../../shared/local_flags.dart';
import '../../state/documents_notifier.dart';
import '../../state/schedule.dart';
import '../../state/scripture_letter_notifier.dart';
import '../../state/settings_notifier.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import '../../services/analytics.dart';
import 'steps.dart';

/// First-run onboarding (`spec/screens/onboarding.md`) — five steps, shown
/// once, escapable, and replayable from Settings.
///
/// **A gate, not a route.** First run has to be a place you arrive at, and a
/// route is one back gesture away from being skipped by accident; that is also
/// why it is composed around the shell in `router.dart` rather than inside
/// `AppLayout` — it has its own frame, and the app's rail is exactly what a
/// reader with nothing in their library has no use for yet.
///
/// **Nothing is written until the last step.** A reader who leaves half way
/// leaves no trace on their account. Sources are the one exception and
/// deliberately so: they went through the real ingest path the moment they were
/// dropped, and are theirs already whether or not the wizard is finished.
class OnboardingGate extends StatefulWidget {
  final Widget child;

  const OnboardingGate({super.key, required this.child});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
    // The gate's own subject. `start()` is idempotent, and without it the gate
    // would wait for whichever screen subscribes first — which on a first run
    // is a screen behind the gate.
    context.read<DocumentsNotifier>().start();
  }

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    return ValueListenableBuilder<bool>(
      valueListenable: LocalFlags.onboarded,
      builder: (context, onboarded, _) => ValueListenableBuilder<bool>(
        valueListenable: LocalFlags.onboardingReplay,
        builder: (context, replay, _) {
          // Both halves, and each is load-bearing:
          //
          //  · `!docs.loading` — shown on the first snapshot to ARRIVE empty,
          //    never before one has. Gating on the empty list alone flashes the
          //    wizard at every returning reader for a frame, because the list
          //    is empty until Firestore answers.
          //  · `docs.error == null` (INV-24, ADR-071) — a failed subscription
          //    yields the same empty list a new account does, and putting a
          //    reader with a library through first-run setup is the loudest
          //    possible version of that mistake.
          //
          // And a reader who already HAS documents has plainly onboarded
          // themselves whatever the flag says.
          final firstRun = !onboarded &&
              !docs.loading &&
              docs.error == null &&
              docs.documents.isEmpty;
          if (!replay && !firstRun) return widget.child;
          return OnboardingWizard(
            documents: docs.documents,
            onDone: _leave,
            onSkip: _leave,
          );
        },
      ),
    );
  }

  /// Finishing and skipping set the SAME flag: skipping is a decision, not a
  /// deferral (`onboarding.md` §States), and the flow stays reachable from
  /// Settings either way.
  Future<void> _leave() async {
    LocalFlags.onboardingReplay.value = false;
    await LocalFlags.setOnboarded(true);
  }
}

/// One step of the rail's list.
class _Step {
  /// The step's id in the `step` vocabulary — the reference's own `STEPS` keys,
  /// which is a closed set `analytics-events.md` names. Carried on the step
  /// rather than derived from an index so that reordering the wizard cannot
  /// quietly re-label what an operator is reading.
  final String key;
  final String label;
  final String sub;

  /// The mono numeral, where the step has one. Welcome and the finish are
  /// bookends, not numbered work.
  final String? number;

  const _Step(this.key, this.label, this.sub, {this.number});
}

const List<_Step> _steps = [
  _Step('welcome', 'Welcome', 'What this is'),
  _Step('sources', 'Bring in your reading', 'Upload & connect', number: '01'),
  _Step('librarian', 'Teach your librarian', 'Set its mission', number: '02'),
  _Step('letter', 'Tune your letter', 'When & how much', number: '03'),
  _Step('done', 'You’re set', 'Open your library'),
];

/// The rail's footer quote, one per step, cycled.
const List<(String, String)> _quotes = [
  (
    'Try to love the questions themselves, like locked rooms and like books '
        'written in a very foreign tongue.',
    'Rilke · Letters to a Young Poet',
  ),
  (
    'A library is a place where attention is preserved — the stacks remember '
        'what we ourselves do not.',
    'Reading notes',
  ),
  (
    'The universe (which others call the Library) is composed of an indefinite '
        'number of hexagonal galleries.',
    'Borges · The Library of Babel',
  ),
];

class OnboardingWizard extends StatefulWidget {
  final List<Document> documents;
  final Future<void> Function() onDone;
  final Future<void> Function() onSkip;

  const OnboardingWizard({
    super.key,
    required this.documents,
    required this.onDone,
    required this.onSkip,
  });

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int _step = 0;
  final ScrollController _scroll = ScrollController();

  String _preset = presets.first.id;
  late final TextEditingController _prompt =
      TextEditingController(text: presets.first.prompt);

  bool _readings = false;
  String _frequency = 'weekdays';
  late final TextEditingController _time = TextEditingController(text: '07:00');
  int _count = 3;

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    // The first step counts. The reference's effect runs on mount as well as on
    // every change, and without this the welcome screen — the one step every
    // reader who opens the wizard sees — would be the only one never counted.
    _reportStep(_step);
  }

  void _reportStep(int step) => Analytics.track('onboarding_step', {
        'step': step >= 0 && step < _steps.length ? _steps[step].key : 'unknown',
      });

  @override
  void dispose() {
    _scroll.dispose();
    _prompt.dispose();
    _time.dispose();
    super.dispose();
  }

  void _goTo(int step) {
    setState(() => _step = step);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _reportStep(step);
  }

  /// The only write, and it happens on the last step (`onboarding.md` §Rules).
  ///
  /// Canonical key names only — `fn_newsletter_settings` rejects the whole
  /// request on an unknown key (2.0.0, ADR-009). The readings letter is a
  /// separate document with its own closed key set (ADR-029), so it is a
  /// second call, and **its failure does not cost the first one**.
  Future<void> _finish() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });

    // Both notifiers are read BEFORE the first await: a `context.read` after
    // one is a use across an async gap, and on a widget the save itself can
    // unmount it is a read of a dead tree.
    final letters = context.read<SettingsNotifier>();
    final readingsLetter = context.read<ScriptureLetterNotifier>();

    String? failed = await letters.saveOnboardingLetter(
      frequency: _frequency,
      deliveryTime: _time.text.trim(),
      itemsPerNewsletter: _count,
      timezone: deviceTimezone(),
      purposeText: _prompt.text.trim(),
    );

    // A SECOND call, to a document with its own closed key set (ADR-029) —
    // and its failure does not cost the first call's write.
    if (LocalFlags.scripture.value && _readings) {
      await readingsLetter.turnOn();
      failed ??= readingsLetter.saveError;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      _saveError = failed;
    });
    // A save failure keeps the wizard open with every choice intact and says
    // so (§14.2, `onboarding.md` §States/Save failed). It must not claim
    // success, and it must not throw the run away.
    if (failed == null) await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final last = _steps.length - 1;

    final rail = _Rail(
      step: _step,
      compact: compact,
      onStep: _goTo,
    );

    final main = Expanded(
      child: Container(
        color: t.bg,
        child: KitGround(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(
                    compact ? AppSpacing.frameGutterCompact : 48,
                    compact ? 28 : 56,
                    compact ? AppSpacing.frameGutterCompact : 48,
                    AppSpacing.s10,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: _body(),
                    ),
                  ),
                ),
              ),
              _Footer(
                step: _step,
                last: last,
                saving: _saving,
                failed: _saveError != null,
                compact: compact,
                onBack: () => _goTo(_step - 1),
                onSkip: () => widget.onSkip(),
                onNext: () => _goTo(_step + 1),
                onFinish: _finish,
              ),
            ],
          ),
        ),
      ),
    );

    // **A `Material`, and it is not decoration.** The wizard replaces the
    // routed child, so unlike every screen it does NOT sit inside the shell's
    // Scaffold — and text with no Material ancestor falls back to Flutter's
    // debug style, which draws a double yellow underline under every line on
    // the screen. It is not an error and nothing fails; the first capture of
    // this pair simply had it under all of it.
    return Material(
      color: t.chrome,
      child: SafeArea(
        child: compact
            ? Column(children: [rail, main])
            : Row(children: [rail, main]),
      ),
    );
  }

  Widget _body() {
    switch (_step) {
      case 0:
        return const WelcomeStep();
      case 1:
        return SourcesStep(documents: widget.documents);
      case 2:
        return LibrarianStep(
          preset: _preset,
          prompt: _prompt,
          onPreset: (p) => setState(() {
            _preset = p.id;
            _prompt.text = p.prompt;
          }),
        );
      case 3:
        return LetterStep(
          frequency: _frequency,
          onFrequency: (f) => setState(() => _frequency = f),
          time: _time,
          count: _count,
          onCount: (c) => setState(() => _count = c),
          readings: _readings,
          onReadings: (on) => setState(() => _readings = on),
        );
      default:
        return DoneStep(
          documents: widget.documents,
          preset: _preset,
          frequency: _frequency,
          time: _time.text,
          count: _count,
          readings: _readings,
          saving: _saving,
          error: _saveError,
          goTo: _goTo,
        );
    }
  }
}

/// The rail (`onboarding.md` §Composition) — brand lockup · mono caps eyebrow ·
/// the promise line with its italic clause · the step list · the quote.
///
/// Below the compact width it is a **header**, as the reference's own rail is:
/// the promise, the step list and the quote go, and the brand sits beside a
/// progress line that says which step of how many. That is a measured figure —
/// the step index — not a simulated one.
class _Rail extends StatelessWidget {
  final int step;
  final bool compact;
  final ValueChanged<int> onStep;

  const _Rail({required this.step, required this.compact, required this.onStep});

  static const double _width = 320;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final quote = _quotes[step % _quotes.length];

    return Container(
      width: compact ? double.infinity : _width,
      color: t.chrome,
      // The grain alone: a lattice of dots belongs to the paper ground, and on
      // the plum field it would be a different surface rather than a softer one.
      child: KitGround(
        lattice: false,
        darkTint: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? AppSpacing.frameGutterCompact : 28,
            compact ? 14 : 30,
            compact ? AppSpacing.frameGutterCompact : 28,
            compact ? 14 : 26,
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KitBrand(
                      mark: Icon(Icons.edit_note,
                          size: 22, color: AppColors.chromeForeground),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    _Progress(step: step),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const KitBrand(
                      mark: Icon(Icons.edit_note,
                          size: 22, color: AppColors.chromeForeground),
                    ),
                    const SizedBox(height: 30),
                    Eyebrow('Setting up your library', color: t.chromeMuted),
                    const SizedBox(height: 9),
                    AccentTitle(
                      'Your library, *distilled* — a daily letter from what '
                      'you’ve read.',
                      style: AppTheme.serif(
                        fontSize: 25,
                        height: 1.18,
                        fontWeight: FontWeight.w500,
                        letterSpacing: -0.01 * 25,
                        color: t.chromeFg,
                      ),
                      // The accent ON CHROME is brick-400, never the page's
                      // brick-500: the page accent on the plum field is a
                      // muddy near-match rather than a clause
                      // (`onboarding.md` §Composition).
                      accent: t.chromeAccentBar,
                    ),
                    const SizedBox(height: 30),
                    for (var i = 0; i < _steps.length; i++)
                      _StepRow(
                        index: i,
                        current: step,
                        onTap: i <= step ? () => onStep(i) : null,
                      ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.only(top: 18),
                      decoration: BoxDecoration(
                        border: Border(
                            top: BorderSide(color: t.chromeBorder)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quote.$1,
                            style: KitText.lede(context,
                                    fontSize: 14.5, height: 22)
                                .copyWith(color: t.chromeMuted),
                          ),
                          const SizedBox(height: AppSpacing.s2),
                          Text(
                            '— ${quote.$2}',
                            style: AppTheme.mono(
                              fontSize: 10.5,
                              letterSpacing: 0.06 * 10.5,
                              color: t.chromeSubtle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// The compact rail's progress line: `Step n of 5` and a bar. Both read the
/// step index — the only thing here that is actually known.
class _Progress extends StatelessWidget {
  final int step;

  const _Progress({required this.step});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Row(
      children: [
        Text(
          'Step ${step + 1} of ${_steps.length}',
          style: AppTheme.mono(
            fontSize: 11,
            letterSpacing: 0.08 * 11,
            color: t.chromeMuted,
          ),
        ),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: ClipRRect(
            borderRadius: AppRadius.pillR(3),
            child: Container(
              height: 3,
              color: t.chromeActive,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: step / (_steps.length - 1),
                child: Container(color: t.chromeAccentBar),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One row of the rail's step list: a numbered disc on its own rail, the step's
/// label, and — on the active step only — its sub-line.
class _StepRow extends StatelessWidget {
  final int index;
  final int current;
  final VoidCallback? onTap;

  const _StepRow({required this.index, required this.current, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final s = _steps[index];
    final done = index < current;
    final active = index == current;
    final isLast = index == _steps.length - 1;

    final disc = Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active
            ? t.chromeFg
            : done
                ? t.accent
                : null,
        border: Border.all(
          color: active
              ? t.chromeFg
              : done
                  ? t.accent
                  : t.chromeBorder,
        ),
      ),
      child: done
          ? Icon(Icons.check, size: 14, color: t.chromeFg)
          : active && s.number == null
              ? Icon(Icons.edit_note, size: 13, color: t.chrome)
              : s.number == null
                  ? Icon(Icons.check, size: 14, color: t.chromeSubtle)
                  : Text(
                      s.number!,
                      style: AppTheme.mono(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: active ? t.chrome : t.chromeMuted,
                      ),
                    ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  disc,
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1.5,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        constraints: const BoxConstraints(minHeight: 14),
                        color: done ? t.accent : t.chromeBorder,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3, bottom: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.label,
                        // kit-ok: F-43 — web `.ob-step-label`; no kit role names it
                        style: TextStyle(
                          fontFamily: AppTheme.fontSans,
                          fontSize: 14,
                          height: 1.3,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w500,
                          color: active ? t.chromeFg : t.chromeMuted,
                        ),
                      ),
                      // The sub-line belongs to the ACTIVE step only, as the
                      // reference draws it: five of them at once is a second
                      // paragraph in the rail, not a stepper.
                      if (active) ...[
                        const SizedBox(height: 3),
                        Text(
                          s.sub,
                          style: AppTheme.mono(
                            fontSize: 10.5,
                            height: 1.3,
                            letterSpacing: 0.04 * 10.5,
                            color: t.chromeSubtle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pinned footer bar: back or the meta line · the skip control · the
/// advance button. The only control that writes anything is the last step's.
class _Footer extends StatelessWidget {
  final int step;
  final int last;
  final bool saving;
  final bool failed;
  final bool compact;
  final VoidCallback onBack;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final VoidCallback onFinish;

  const _Footer({
    required this.step,
    required this.last,
    required this.saving,
    required this.failed,
    required this.compact,
    required this.onBack,
    required this.onSkip,
    required this.onNext,
    required this.onFinish,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AppSpacing.frameGutterCompact : 48,
        vertical: AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: Row(
        children: [
          if (step > 0)
            KitButton.ghost('Back', icon: Icons.chevron_left, onPressed: onBack)
          else if (!compact)
            Text(
              'A letter from your own library',
              style: AppTheme.mono(
                fontSize: 11,
                letterSpacing: 0.06 * 11,
                color: t.fgSubtle,
              ),
            ),
          const Spacer(),
          if (step != last) ...[
            // No chevron: skipping is an escape, not a way onward.
            KitSettingLink('Skip setup', icon: null, onTap: onSkip),
            const SizedBox(width: AppSpacing.s3),
          ],
          if (step == last)
            KitButton.primary(
              saving
                  ? 'Saving…'
                  : failed
                      ? 'Try again'
                      : 'Open your library',
              icon: Icons.arrow_forward,
              onPressed: saving ? null : onFinish,
            )
          else
            KitButton.primary(
              step == 0 ? 'Begin' : 'Continue',
              icon: Icons.arrow_forward,
              onPressed: onNext,
            ),
        ],
      ),
    );
  }
}
