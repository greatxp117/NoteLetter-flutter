import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../shared/local_flags.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/file_uploader.dart';
import '../../widgets/kit/kit.dart';
import '../letters/readings_letter.dart' show calendarLabel, calendarNote;
import '../tags/suggest_shelves.dart';

/// First-run onboarding — the step bodies (`spec/screens/onboarding.md`).
///
/// Presentation only: every piece of state lives in `wizard.dart` and is passed
/// down, matching the reference's own split.
///
/// Three places this deliberately differs from the design prototype, each
/// because the prototype is backed by mock data and this is backed by the
/// contract — the same three the web reference records:
///
///  · **Delivery is a frequency**, not the design's seven day-pills.
///    `fn_newsletter_settings` stores `frequency` from a closed set and has no
///    per-day field, so pills would either invent a mapping or silently drop
///    the choice — the ADR-009 defect.
///  · **"I read scripture" is ONE entry point for both scripture features**
///    (2.28.0): it turns on verse search (client-local, per device, ADR-027 §7)
///    and unlocks the readings letter on the next step. Unticked, that step is
///    **absent** rather than disabled — it is not a thing the reader is failing
///    to do.
///  · **Sources upload for real**, through the same ingest path the Sources
///    screen uses, rather than the prototype's simulated parse pipeline.

// ── 1 · Welcome ──────────────────────────────────────────────────────────────

class _Move {
  final String number;
  final IconData icon;
  final String title;
  final String description;

  const _Move(this.number, this.icon, this.title, this.description);
}

const List<_Move> _moves = [
  _Move(
    'I',
    Icons.layers_outlined,
    'Gather what you’ve read',
    'Upload files or paste a link. NoteLetter reads the text and makes every '
        'passage searchable.',
  ),
  _Move(
    'II',
    Icons.mail_outline,
    'Receive a daily letter',
    'Each morning, a few passages from your own library arrive — chosen '
        'quietly, set like a page.',
  ),
  _Move(
    'III',
    Icons.chat_bubble_outline,
    'Ask your library anything',
    'Put a question to everything you’ve kept. Answers come with the passages '
        'they’re drawn from.',
  ),
];

class WelcomeStep extends StatelessWidget {
  const WelcomeStep({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const KitMark(KitQuill.icon, size: 72),
      const SizedBox(height: AppSpacing.s6),
      const ChapterOpening(
        // Onboarding's own head, not §2.1's (F-80 (4)).
        onboarding: true,
        folio: 'Setting up',
        folioAside: 'a few minutes',
        title: 'Welcome to *your library.*',
        standfirst:
            'You’ve read more than you remember. NoteLetter keeps '
            'it close — searchable, and quietly distilled into a letter '
            'you’ll actually read. Four steps and it’s yours.',
      ),
      for (var i = 0; i < _moves.length; i++) ...[
        // `.ob-moves { gap: 2px }`: the rows are 2 apart, each closed by
        // its own rule. (Its 6 top margin collapses into the head's 30.)
        if (i > 0) const SizedBox(height: 2),
        KitNumberedMove(
          number: _moves[i].number,
          icon: _moves[i].icon,
          title: _moves[i].title,
          description: _moves[i].description,
          ruled: true,
          last: i == _moves.length - 1,
        ),
      ],
    ],
  );
}

// ── 2 · Sources ──────────────────────────────────────────────────────────────

/// Real uploads, through [FileUploader] — the same drop zone, the same link
/// row and the same in-flight rows the Sources screen composes, so a source
/// added here is in the library whether or not the wizard is finished.
///
/// **Indexing is never waited on** (`onboarding.md` §Rules): the counts below
/// are what the documents subscription says (INV-02), and the note says plainly
/// that indexing continues in the background. A wizard that blocked on
/// embedding would hold a first-run reader for minutes.
class SourcesStep extends StatelessWidget {
  final List<Document> documents;

  const SourcesStep({super.key, required this.documents});

  @override
  Widget build(BuildContext context) {
    final indexed = documents
        .where((d) => d.status == DocumentStatus.complete)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ChapterOpening(
          // Onboarding's own head, not §2.1's (F-80 (4)).
          onboarding: true,
          folio: '№ 01 · of 04',
          title: 'Bring in your reading.',
          standfirst:
              'Drop a file or paste a link. The more you bring, the '
              'more your letter has to draw from — you can always add more '
              'later.',
        ),
        const FileUploader(),
        if (documents.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s6),
          SectionHeader(
            'In your library',
            note: '$indexed indexed · ${documents.length} total',
          ),
        ],
        const KitProcNote(
          'Indexing runs in the background — you don’t have to wait here for '
          'it to finish.',
          padding: EdgeInsets.only(top: AppSpacing.s5),
        ),
      ],
    );
  }
}

// ── 3 · Librarian ────────────────────────────────────────────────────────────

class OnboardingPreset {
  final String id;
  final String label;
  final String prompt;

  const OnboardingPreset(this.id, this.label, this.prompt);
}

/// The four missions, verbatim from the reference: they are saved as the
/// letter's `purposeText` and read by the backend, so they are copy, not
/// placeholder.
const List<OnboardingPreset> presets = [
  OnboardingPreset(
    'attention',
    'Focus & attention',
    'I’m trying to reclaim my attention and do deeper, slower work. Favour '
        'what I’ve read about focus, distraction, and the economics of '
        'attention — and choose passages that challenge how I spend my time.',
  ),
  OnboardingPreset(
    'writing',
    'Become a better writer',
    'Help me grow as a writer. Prioritise notes and books on style, structure, '
        'and the writing process, and surface passages I can take a concrete '
        'craft lesson from.',
  ),
  OnboardingPreset(
    'systems',
    'Think in systems',
    'I want to understand how complex systems behave and make better '
        'decisions. Favour systems thinking, feedback, incentives, and models '
        'for judgement under uncertainty.',
  ),
  OnboardingPreset(
    'meaning',
    'Read more philosophy',
    'Bring me back to the larger questions. Prioritise philosophy, ethics, and '
        'reflective essays on how to live, and choose passages that sit with a '
        'question rather than rushing to answer it.',
  ),
];

class LibrarianStep extends StatelessWidget {
  final String preset;
  final TextEditingController prompt;
  final ValueChanged<OnboardingPreset> onPreset;

  /// *Use generative AI* (5.29.0, ADR-186; `onboarding.md` §Rules): ticked by
  /// default, a replay starts from the stored value — the wizard decides
  /// which — and it is account state, so it is written on Finish like
  /// everything else, never as it is answered.
  final bool useAI;
  final ValueChanged<bool> onUseAI;

  const LibrarianStep({
    super.key,
    required this.preset,
    required this.prompt,
    required this.onPreset,
    this.useAI = true,
    required this.onUseAI,
  });

  /// The check row's key, for the device run and the holds.
  static const useAIKey = ValueKey('ob-use-ai');

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ChapterOpening(
        // Onboarding's own head, not §2.1's (F-80 (4)).
        onboarding: true,
        folio: '№ 02 · of 04',
        title: 'Teach your *librarian.*',
        standfirst:
            'Write a short mission — what you’re reading toward, '
            'and what you want kept close. Your librarian uses it to '
            'weight which passages reach your letter.',
      ),
      const Eyebrow('Start from a mission'),
      const SizedBox(height: AppSpacing.s3),
      Wrap(
        spacing: AppSpacing.s2,
        runSpacing: AppSpacing.s2,
        children: [
          for (final p in presets)
            KitFilterChip(
              p.label,
              selected: preset == p.id,
              onPressed: () => onPreset(p),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.s4),
      KitTextField(
        controller: prompt,
        minLines: 5,
        maxLines: 10,
        placeholder: 'Describe what you’re reading toward…',
      ),
      const KitProcNote(
        'This is saved as your letter’s purpose and can be rewritten any '
        'time in Letter settings.',
      ),
      const SizedBox(height: AppSpacing.s6),
      const Eyebrow('What you read'),
      const SizedBox(height: AppSpacing.s3),
      // ONE question, two features (2.28.0). Verse search is client-local
      // (ADR-027 §7) and is written the moment it is answered, because it
      // changes nothing on the account; the readings LETTER is contract
      // state and waits for the finish.
      ValueListenableBuilder<bool>(
        valueListenable: LocalFlags.scripture,
        builder: (context, on, _) => KitRowList(
          raised: true,
          rows: [
            KitSettingRow(
              icon: Icons.menu_book_outlined,
              title: 'I read scripture',
              description:
                  'Turns on verse search — a citation like Mt 16:24-28 is '
                  'read verse by verse, with the passages on your shelves '
                  'that answer each one.',
              below: on
                  ? const KitRowNote(
                      'You can add a second letter from the day’s readings '
                      'in the next step.',
                    )
                  : null,
              trailing: [
                KitSwitch(
                  value: on,
                  tooltip: 'I read scripture',
                  // Write before move: the stored flag lands first
                  // ([LocalFlags.setScripture]), then the notifier this
                  // builder is listening to.
                  onChanged: (next) => LocalFlags.setScripture(next),
                ),
              ],
            ),
          ],
        ),
      ),
      // The generative-AI switch (5.29.0, ADR-186), under its own
      // eyebrow, as a check row. Unlike scripture it is ACCOUNT state:
      // the answer is held and written on Finish (`fn_ai_settings`, the
      // fourth separate call). The Shelves step is unaffected by it.
      const SizedBox(height: AppSpacing.s6),
      const Eyebrow('What NoteLetter writes'),
      const SizedBox(height: AppSpacing.s3),
      KitObCheck(
        key: useAIKey,
        value: useAI,
        title: 'Use generative AI',
        description:
            'Summaries of each source, Ask, cohesive reading, and the '
            'librarian’s notes in your letter. Untick it to see only what '
            'you added — you can change this in Settings.',
        onChanged: onUseAI,
      ),
    ],
  );
}

// ── 4 · Letter ───────────────────────────────────────────────────────────────

/// The closed set `fn_newsletter_settings` stores. Not days.
const List<(String, String)> frequencies = [
  ('daily', 'Daily'),
  ('weekdays', 'Weekdays'),
  ('weekly', 'Weekly'),
];

/// Suggest shelves as a step (ruled 2026-10-08; `onboarding.md`,
/// `library.md` §Suggesting shelves) — the Library sheet's own parts, over the
/// wizard's state. The field starts as the mission from the step before;
/// asking writes nothing, and the shelves left ticked are created on Finish.
class ShelvesStep extends StatelessWidget {
  final ShelfSuggestions s;
  const ShelvesStep({super.key, required this.s});

  @override
  Widget build(BuildContext context) {
    final n = s.chosen.length;
    final review = s.phase == SuggestPhase.review;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ChapterOpening(
          // Onboarding's own head, not §2.1's (F-80 (4)).
          onboarding: true,
          folio: '№ 03 · of 04',
          title: 'Choose your *shelves.*',
          standfirst:
              'Every source is filed on a shelf. Say what you read '
              'about and NoteLetter will suggest some — keep the ones you want.',
        ),
        if (review) ...[
          SuggestReview(s: s),
          const SizedBox(height: 14),
          Wrap(
            children: [
              s.tags.isNotEmpty
                  ? KitButton.ghost('Change what I wrote', onPressed: s.back)
                  : KitButton.primary('Change what I wrote', onPressed: s.back),
            ],
          ),
        ] else ...[
          SuggestAsk(s: s, autofocus: false),
          SuggestFailure(s: s),
        ],
        KitProcNote(
          review && n > 0
              ? '$n ${n == 1 ? 'shelf' : 'shelves'} will be created when you '
                    'finish.'
              : 'You can skip this — NoteLetter also makes shelves as your '
                    'sources are indexed.',
        ),
      ],
    );
  }
}

class LetterStep extends StatelessWidget {
  final String frequency;
  final ValueChanged<String> onFrequency;
  final TextEditingController time;
  final int count;
  final ValueChanged<int> onCount;
  final bool readings;
  final ValueChanged<bool> onReadings;

  const LetterStep({
    super.key,
    required this.frequency,
    required this.onFrequency,
    required this.time,
    required this.count,
    required this.onCount,
    required this.readings,
    required this.onReadings,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const ChapterOpening(
        // Onboarding's own head, not §2.1's (F-80 (4)).
        onboarding: true,
        folio: '№ 04 · of 04',
        title: 'Tune your *letter.*',
        standfirst:
            'A letter is from someone, to someone. Set when yours '
            'arrives and how much it carries.',
      ),
      KitFieldGroup(
        label: 'How often',
        first: true,
        child: KitSegmented(
          groupLabel: 'How often',
          segments: [for (final f in frequencies) KitSegment(f.$2)],
          selected: frequencies.indexWhere((f) => f.$1 == frequency),
          onChanged: (i) => onFrequency(frequencies[i].$1),
        ),
      ),
      KitFieldGroup(
        label: 'Arrives at',
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: KitTextField(controller: time, icon: Icons.schedule),
        ),
      ),
      KitFieldGroup(
        label: 'Passages per letter',
        child: KitStepper(
          value: count,
          min: 1,
          max: 5,
          onChanged: onCount,
          unit: count == 1 ? 'passage each time' : 'passages each time',
        ),
      ),
      // A second letter, not a mode of the one above (ADR-029) — and
      // offered only to someone who said they read scripture on the
      // previous step. Unticked there, this is ABSENT, not disabled.
      ValueListenableBuilder<bool>(
        valueListenable: LocalFlags.scripture,
        builder: (context, scripture, _) {
          if (!scripture) return const SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpacing.s6),
              const Eyebrow('A second letter'),
              const SizedBox(height: AppSpacing.s3),
              KitRowList(
                raised: true,
                rows: [
                  KitSettingRow(
                    icon: Icons.auto_stories_outlined,
                    title: 'The readings letter',
                    description:
                        'The day’s Mass readings, with the passages from '
                        'your shelves that answer them. It arrives beside '
                        'the letter you’ve just tuned, at its own hour — '
                        'that one is unchanged.',
                    below: readings
                        ? KitRowNote('$calendarLabel calendar. $calendarNote')
                        : null,
                    trailing: [
                      KitSwitch(
                        value: readings,
                        tooltip: 'The readings letter',
                        onChanged: onReadings,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}

// ── 5 · Done ─────────────────────────────────────────────────────────────────

class DoneStep extends StatelessWidget {
  final List<Document> documents;
  final String preset;
  final String frequency;
  final String time;
  final int count;
  final bool readings;

  /// The kept proposals' titles, and whether they were made (`fn_approve_tags`
  /// ran on this finish).
  final List<String> shelves;
  final bool shelvesMade;
  final bool saving;
  final String? error;

  /// The error is the shelves' (the third write), not the letter's.
  final bool shelvesFailed;

  /// The error is the AI choice's (the fourth write, 5.29.0), and the
  /// letter and the shelves are set.
  final bool aiFailed;

  /// The Librarian step's *Use generative AI* — the summary's *Generative
  /// AI* row says *On* or *Off* and returns there.
  final bool useAI;
  final ValueChanged<int> goTo;

  const DoneStep({
    super.key,
    required this.documents,
    required this.preset,
    required this.frequency,
    required this.time,
    required this.count,
    required this.readings,
    this.shelves = const [],
    this.shelvesMade = false,
    required this.saving,
    required this.error,
    this.shelvesFailed = false,
    this.aiFailed = false,
    this.useAI = true,
    required this.goTo,
  });

  @override
  Widget build(BuildContext context) {
    final mission = presets.firstWhere(
      (p) => p.id == preset,
      orElse: () => presets.first,
    );
    final freq = frequencies
        .firstWhere((f) => f.$1 == frequency, orElse: () => frequencies.first)
        .$2;
    final indexed = documents
        .where((d) => d.status == DocumentStatus.complete)
        .length;
    final showReadings = LocalFlags.scripture.value && readings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KitMark.seal(KitQuill.icon),
        const SizedBox(height: AppSpacing.s6),
        ChapterOpening(
          // Onboarding's own head, not §2.1's (F-80 (4)).
          onboarding: true,
          folio: saving
              ? 'Saving…'
              : error != null
              ? 'Not saved'
              : 'Ready',
          title: 'Your library is *open.*',
          standfirst: error != null
              ? (shelvesFailed
                    ? 'Your sources and your letter are set, but your shelves '
                          'could not be created. Try again, or suggest them later '
                          'from your Library.'
                    : aiFailed
                    ? 'Your sources and your letter are set, but your AI choice '
                          'could not be saved. Try again, or change it later in '
                          'Settings.'
                    : 'Your sources are safe, but these settings could not be '
                          'saved. You can set them in Letter settings.')
              : 'Everything’s in place. Here’s what to expect.',
        ),
        // §14.2 — the rejection, in the place the reader is looking, with every
        // choice above it kept.
        if (error != null) ...[
          KitFailureInline(error!),
          const SizedBox(height: AppSpacing.s4),
        ],
        KitRowList(
          raised: true,
          rows: [
            // The sources row is **Your sources** (onboarding.md, F-89): it
            // said *Your shelves* over a count of sources.
            KitSettingRow(
              icon: KitStackGlyph.icon,
              title: 'Your sources',
              description:
                  '${documents.length} '
                  '${documents.length == 1 ? 'source' : 'sources'} · '
                  '$indexed indexed so far',
              trailing: [
                KitSettingLink('Add more', icon: null, onTap: () => goTo(1)),
              ],
            ),
            KitSettingRow(
              icon: Icons.chat_bubble_outline,
              title: 'Your librarian',
              description: 'Curating for ${mission.label.toLowerCase()}',
              trailing: [
                KitSettingLink('Rewrite', icon: null, onTap: () => goTo(2)),
              ],
            ),
            // 5.29.0 (ADR-186): the Librarian step's choice, and the way back
            // to it.
            KitSettingRow(
              icon: KitSparkle.icon,
              title: 'Generative AI',
              description: useAI ? 'On' : 'Off',
              trailing: [
                KitSettingLink('Change', icon: null, onTap: () => goTo(2)),
              ],
            ),
            KitSettingRow(
              icon: Icons.shelves,
              title: 'Your shelves',
              description: shelves.isEmpty
                  ? 'Made as your sources are indexed'
                  : '${shelves.length} ${shelvesMade ? 'created' : 'to create'}'
                        ' · ${shelves.join(' · ')}',
              trailing: [
                if (!shelvesMade)
                  KitSettingLink(
                    shelves.isEmpty ? 'Choose' : 'Change',
                    icon: null,
                    onTap: () => goTo(3),
                  ),
              ],
            ),
            KitSettingRow(
              icon: Icons.mail_outline,
              title: 'Your letter',
              description:
                  '$freq, $time · $count '
                  '${count == 1 ? 'passage' : 'passages'}',
              trailing: [
                KitSettingLink('Adjust', icon: null, onTap: () => goTo(4)),
              ],
            ),
            if (showReadings)
              KitSettingRow(
                icon: Icons.auto_stories_outlined,
                title: 'The readings letter',
                description: 'On · $calendarLabel calendar, at its own hour',
                trailing: [
                  KitSettingLink('Adjust', icon: null, onTap: () => goTo(4)),
                ],
              ),
          ],
        ),
        const KitProcNote(
          'Indexing continues in the background. Your first letter goes out on '
          'the next scheduled send.',
          padding: EdgeInsets.only(top: AppSpacing.s5),
        ),
      ],
    );
  }
}
