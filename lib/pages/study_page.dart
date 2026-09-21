/// Study programs (`spec/screens/study.md` §Composition, ADR-041).
///
/// Index frame · chapter opening (§2.1) with the `Deep study · N programs`
/// folio and a **New program** action · one §5.1 surface card per program,
/// carrying its status chip, its measured progress and its §12 Notice when the
/// build says it is running low · §7 empty state · the session history under a
/// §3 header.
///
/// **Every figure here is a stored field.** Progress is `introduced_count` of
/// `unit_count` from the program document, the schedule sentence is rendered
/// from what was read, the runway is the runway the build measured — and there
/// is no forecast, retention percentage or streak, because no field carries
/// one.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/study.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../shared/dates.dart';
import '../state/study_schedule.dart';
import '../theme/app_spacing.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import '../services/error_text.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  /// Per program: what the last write said, and what it refused.
  final Map<String, String> _notes = {};
  final Map<String, String> _errors = {};
  final Map<String, String> _busy = {};

  Future<void> _toggle(StudyProgram p) async {
    setState(() {
      _busy[p.id] = 'toggle';
      _errors.remove(p.id);
      _notes.remove(p.id);
    });
    try {
      // Write BEFORE it moves (ADR-022): the switch reflects the STORED value
      // and the subscription is what changes it, so a refused write leaves the
      // control where it was.
      final res =
          await Api.instance.updateStudyProgram(p.id, {'enabled': !p.enabled});
      if (!mounted) return;
      setState(() => _notes[p.id] = p.enabled
          // Off is a PAUSE — the copy may not imply progress is lost.
          ? 'Off. Nothing further will arrive. The ${p.introducedCount} '
              'passages it has introduced are kept.'
          // 2.30.0 — the backend decides whether a session goes now; this
          // only reports what it decided.
          : (studyActivationMessage(res) ?? 'On.'));
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors[p.id] = e.message);
    } catch (_) {
      if (mounted) setState(() => _errors[p.id] = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  Future<void> _studyNow(StudyProgram p) async {
    setState(() {
      _busy[p.id] = 'study';
      _errors.remove(p.id);
      _notes.remove(p.id);
    });
    try {
      await Api.instance.requestStudySession(p.id);
      if (!mounted) return;
      // ADR-011: a session record ALWAYS appears — the history below is the
      // subscription that reconciles this promise, so nothing is claimed about
      // a session that has not been written yet.
      setState(() => _notes[p.id] =
          'Session requested — it appears under Sessions in a moment, and by '
          'email if this program sends one.');
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 429 is a COOLDOWN, not a failure: it reads as the system working.
      // The wait is the SERVER's to state — the endpoint names the exact
      // remaining seconds, and the constant below is a 60s guess that goes
      // stale invisibly the day the window moves. It survives only for a 429
      // that carried no sentence at all (C11).
      setState(() {
        if (e.statusCode == 429) {
          _notes[p.id] = cooldownSentence(
              e,
              'Just a moment — a session for this program was '
              'requested less than a minute ago.');
        } else {
          _errors[p.id] = e.message;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _errors[p.id] = 'Something went wrong.');
    } finally {
      if (mounted) setState(() => _busy.remove(p.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StudyProgram>>(
      stream: FirestoreService.instance.subscribeStudyPrograms(),
      builder: (context, snap) {
        // INV-24 (ADR-071): a failed subscription is not an empty library of
        // programs, and the empty state is a claim about the reader.
        if (snap.hasError) {
          return KitPage(
            child: KitFailureBlock(
              sentence: 'Your programs could not be read.',
              detail: describeSdkError(snap.error!),
            ),
          );
        }
        final programs = snap.data;
        if (programs != null && programs.isEmpty) {
          return KitPage(child: _empty(context));
        }

        return KitPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChapterOpening(
                folio: 'Deep study · '
                    '${programs == null ? '…' : programs.length} '
                    '${programs?.length == 1 ? 'program' : 'programs'}',
                title: 'Study Programs',
                standfirst:
                    'A program turns your own documents into questions that '
                    'come back on their own schedule. How you grade an answer '
                    'decides when you see it next.',
                actions: [
                  KitButton('New program',
                      icon: Icons.add,
                      onPressed: () => context.go('/study/new')),
                ],
              ),
              if (programs == null)
                KitRowNote('Loading…')
              else
                for (final p in programs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _ProgramCard(
                      program: p,
                      note: _notes[p.id],
                      error: _errors[p.id],
                      busy: _busy[p.id],
                      onToggle: () => _toggle(p),
                      onStudy: () => _studyNow(p),
                      onEdit: () => context.go('/study/${p.id}'),
                      onNew: () => context.go('/study/new'),
                    ),
                  ),
              const _Sessions(),
              const SizedBox(height: AppSpacing.s8),
            ],
          ),
        );
      },
    );
  }

  /// §7 — **an offer, not an apology.** The three rows say what a program is
  /// for; the action row is what makes one.
  Widget _empty(BuildContext context) => KitEmptyState(
        icon: Icons.style_outlined,
        title: 'Go deeper on one subject',
        standfirst:
            'Your letter keeps the whole library in view. A study program is '
            'the other direction — one set of documents, learned properly, '
            'using spaced repetition and retrieval practice.',
        suggestions: const [
          KitNumberedMove(
            number: 'I',
            title: 'One subject at a time',
            description:
                'Up to ten finished documents, in the order you want them '
                'taught — sessions introduce passages from the first before '
                'moving on.',
          ),
          KitNumberedMove(
            number: 'II',
            title: 'It arrives as its own session',
            description:
                'Separate from your daily letter, at its own hour. The email '
                'carries the questions only — answering happens here.',
          ),
          KitNumberedMove(
            number: 'III',
            title: 'Recall first, then grade yourself',
            description:
                'You answer before the answer shows, then mark it Again, '
                'Hard, Good or Easy. What you miss comes back sooner; what '
                'you know comes back later, and the screen tells you when.',
          ),
        ],
        actions: [
          KitButton('New program',
              icon: Icons.add, onPressed: () => context.go('/study/new')),
        ],
      );
}

/// One program: a §5.1 surface card.
class _ProgramCard extends StatelessWidget {
  final StudyProgram program;
  final String? note;
  final String? error;
  final String? busy;
  final VoidCallback onToggle;
  final VoidCallback onStudy;
  final VoidCallback onEdit;
  final VoidCallback onNew;

  const _ProgramCard({
    required this.program,
    required this.note,
    required this.error,
    required this.busy,
    required this.onToggle,
    required this.onStudy,
    required this.onEdit,
    required this.onNew,
  });

  @override
  Widget build(BuildContext context) {
    final p = program;
    final on = p.enabled;
    final low = runwayNotice(p);

    return KitCard(
      padding: const EdgeInsets.all(AppSpacing.s4 + 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(p.title, style: KitText.h4(context)),
              ),
              const SizedBox(width: AppSpacing.s2),
              // Open vocabulary: an unknown status renders in the same neutral
              // shell, humanised, never as the raw token.
              KitStatusPill(studyStatusLabel(p.status),
                  positive: p.status == 'active'),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          // A measured figure and a meter backed by it — the design's
          // simulated progress bar is not a signal.
          Text(
            '${p.introducedCount} of ${p.unitCount} passages introduced',
            style: KitText.meta(context),
          ),
          const SizedBox(height: 6),
          _Meter(n: p.introducedCount, of: p.unitCount),
          const SizedBox(height: AppSpacing.s3),
          Text('${on ? '' : 'Was: '}${programScheduleSentence(p)}',
              style: KitText.meta(context)),
          if (!on) ...[
            const SizedBox(height: 4),
            KitRowNote(
                'Off is a pause — the schedule and everything it has '
                'introduced are kept, and “Study now” still works.'),
          ],
          if (low != null)
            // §12 — measured, not dismissible, and the action is the one
            // `low_material_reason` names.
            KitNotice(
              icon: Icons.error_outline,
              text: low.text,
              actionLabel: low.cta,
              onAction: low.action == 'new' ? onNew : onEdit,
            ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.s3),
            KitFailureInline(error!),
          ] else if (note != null) ...[
            const SizedBox(height: AppSpacing.s3),
            KitRowNote(note!),
          ] else if (!on) ...[
            const SizedBox(height: AppSpacing.s3),
            // Said BEFORE the switch is touched (ADR-031's obligation).
            KitRowNote(studyActivationHint),
          ],
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              KitButton(busy == 'study' ? 'Requesting…' : 'Study now',
                  onPressed: busy != null ? null : onStudy),
              KitButton('Settings',
                  icon: Icons.tune,
                  variant: KitButtonVariant.ghost,
                  onPressed: onEdit),
              KitSwitch(
                value: on,
                tooltip: on ? 'Pause this program' : studyActivationHint,
                onChanged: busy != null ? null : (_) => onToggle(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Progress, and nothing else: `introduced_count` of `unit_count`, both stored.
class _Meter extends StatelessWidget {
  final int n;
  final int of;

  const _Meter({required this.n, required this.of});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fraction = of > 0 ? (n / of).clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 4,
        color: t.surfaceSunken,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: Container(color: t.accent),
        ),
      ),
    );
  }
}

/// The session history — §3 header over §4.1 rows. Rendered from
/// `program_title`, because a deleted program's sessions still list and that
/// is normal, not an error.
class _Sessions extends StatelessWidget {
  const _Sessions();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StudySession>>(
      stream: FirestoreService.instance.subscribeStudySessions(limit: 40),
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(top: AppSpacing.s6),
            child: KitFailureBlock(
              sentence: 'Your sessions could not be read.',
              detail: describeSdkError(snap.error!),
            ),
          );
        }
        final rows = snap.data ?? const <StudySession>[];
        if (rows.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Sessions'),
            KitRowList(
              rows: [for (final r in rows) _sessionRow(context, r)],
            ),
          ],
        );
      },
    );
  }

  Widget _sessionRow(BuildContext context, StudySession s) {
    final questions =
        s.items.fold<int>(0, (n, it) => n + it.questions.length);
    final answered = s.responses.length;
    final chip = _sessionChip(s);
    return KitSourceRow(
      title: s.programTitle.isEmpty ? 'Study session' : s.programTitle,
      subtitle: questions > 0
          ? '${s.newCount} new · ${s.reviewCount} '
              '${s.reviewCount == 1 ? 'review' : 'reviews'} · '
              '$answered of $questions answered'
          : 'No questions',
      date: shortDate(s.generatedAt),
      trailing: chip == null ? null : KitStatusPill(chip),
      onTap: () => context.go('/study/session/${s.id}'),
    );
  }

  /// What happened to the session, and separately to its EMAIL (4.22.0,
  /// ADR-059, INV-23). A delivery problem never contradicts the session
  /// itself — the questions are here and answerable either way — so this only
  /// ever adds a chip, and an absent `delivery` map shows none at all.
  static String? _sessionChip(StudySession s) {
    const status = {
      'email_failed': 'Email didn’t send',
      'empty': 'Nothing was due',
      'generating': 'Still being made',
      'error': 'Not made',
    };
    const delivery = {
      'bounced': 'Email not delivered',
      'dropped': 'Email not delivered',
      'spam': 'Marked as spam',
      'deferred': 'Email still sending',
    };
    final byStatus = status[s.status];
    if (byStatus != null) return byStatus;
    final byDelivery = delivery[s.deliveryState];
    if (byDelivery != null) return byDelivery;
    // Never `default: return status` — that is how a reader is shown the
    // literal token. `sent` is the ordinary case and carries no chip.
    if (s.status.isNotEmpty && s.status != 'sent') {
      return s.status.replaceAll(RegExp(r'[_-]+'), ' ');
    }
    return null;
  }
}
