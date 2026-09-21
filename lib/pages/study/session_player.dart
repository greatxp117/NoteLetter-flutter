/// The study session player (contract 2.34.0 ADR-033; 2.37.2; 3.1.0 ADR-039).
///
/// This is where the session email's CTA lands. It subscribes to the ONE
/// session document while `fn_submit_study_answer` writes into it, which is
/// what makes a session resumable: close the app mid-session, come back, and
/// the grades already given are there.
library;

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../models/study.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../shared/extraction_markers.dart';
import '../../state/study_schedule.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import '../../services/analytics.dart';

/// Grades in SM-2 order, with the promise each one makes.
const _gradeLabels = {
  'again': 'Again',
  'hard': 'Hard',
  'good': 'Good',
  'easy': 'Easy',
};

class SessionPlayerPage extends StatefulWidget {
  const SessionPlayerPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<SessionPlayerPage> createState() => _SessionPlayerPageState();
}

class _SessionPlayerPageState extends State<SessionPlayerPage> {
  final Set<String> _revealed = {};
  final Set<String> _busy = {};

  /// What the SERVER said about each graded question — the return date comes
  /// from `item.due_at` in the response and is never computed here.
  final Map<String, String> _outcome = {};

  /// Chunks whose excerpt has been shown. `chunk_read` is written where the
  /// excerpt MOUNTS (ADR-033 §9 as amended by ADR-039 §6), which is what makes
  /// a review's excerpt count only once its disclosure is opened.
  final Set<String> _readLogged = {};

  /// `study_session_started` is emitted once, when the session document first
  /// arrives — not on every rebuild of the stream, and not on mount, because
  /// until the document is there the session may not exist at all. That a
  /// session was started; never which programme or which passages.
  bool _sessionAnnounced = false;

  Future<void> _grade(StudySession session, StudySessionItem item, String qid,
      String grade) async {
    setState(() => _busy.add(qid));
    try {
      final res =
          await Api.instance.submitStudyAnswer(session.id, qid, grade);
      // The grade, which is a closed set of four; never the question, the
      // answer or which document it came from (INV-25b).
      Analytics.track('study_answer_submitted', {'grade': grade});
      if (!mounted) return;
      setState(() {
        // Non-optimistic: the outcome is whatever the server reports.
        if (res['alreadyGraded'] == true) {
          // Recorded, NOT an error — the first grade per item per session is
          // the one that moves SM-2 state (INV-17); later ones only record.
          _outcome[qid] = 'Already answered in this session.';
        } else if (res['itemRetired'] == true) {
          // INV-18: the passage this question came from no longer exists.
          // The reader answered what they were shown, so this is information,
          // never a failure.
          _outcome[qid] = 'Recorded. This passage has since been removed from '
              'the source, so it will not come back.';
        } else {
          // The schedule's OWN answer, from the response — never computed
          // here from the grade (INV-17).
          final due = (res['item'] as Map?)?['due_at'];
          final back = returnLabel(due is int ? due : null);
          _outcome[qid] = back == null
              ? 'Recorded.'
              : 'Recorded — $back.';
        }
      });
    } on ApiException catch (e) {
      // C6: this said "Could not record that — try again" for everything, and
      // the three answers it flattened want three different next moves. A 404
      // means this item is no longer in the session and trying again cannot
      // help; a 409 means it is already recorded, so trying again would be
      // asking twice; a 401 means the session expired and the answer is to
      // sign in. The endpoint says which; the constant said none of them.
      if (mounted) setState(() => _outcome[qid] = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _outcome[qid] =
            'That could not be recorded. Please check your connection and '
            'try again.');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(qid));
    }
  }

  void _logExcerptRead(StudySession session, StudySessionItem item) {
    if (item.chunkId.isEmpty || !_readLogged.add(item.chunkId)) return;
    // A study excerpt IS a read (ADR-039 §6): it reached the reader. It moves
    // no SM-2 state (INV-17) and never touches last_included_in_newsletter.
    FirestoreService.instance
        .logChunksRead(item.documentId, [item.chunkId]);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StudySession?>(
      stream: FirestoreService.instance.subscribeStudySession(widget.sessionId),
      builder: (context, snap) {
        if (snap.hasError) {
          // A dropped subscription is a CONNECTION problem, not a wrong
          // account (2.37.2). Saying the latter sends the reader looking for a
          // problem they do not have, on the one screen whose whole claim is
          // that what it shows is real.
          return KitPage(
            width: KitFrameWidth.reading,
            child: KitFailureBlock(
              sentence: 'The connection dropped.',
              detail: '${snap.error}',
              onRetry: () => setState(() {}),
              retryLabel: 'Try again',
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return KitPage(
            width: KitFrameWidth.reading,
            child: KitRowNote('Loading…'),
          );
        }
        final session = snap.data;
        if (session == null) {
          return KitPage(
            width: KitFrameWidth.reading,
            child: KitEmptyState(
              icon: Icons.help_outline,
              title: 'Session not found',
              standfirst: 'The link may be old, or this session may belong to '
                  'another account.',
            ),
          );
        }

        if (!_sessionAnnounced) {
          _sessionAnnounced = true;
          Analytics.track('study_session_started');
        }

        return KitPage(
          width: KitFrameWidth.reading,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ChapterOpening(
                folio: session.trigger == 'manual'
                    ? 'Study · requested'
                    : 'Study · scheduled',
                title: session.programTitle.isEmpty
                    ? 'Study session'
                    : session.programTitle,
                standfirst: _sessionLine(session),
              ),
              // Gated on STATUS, never on item count: the build writes the
              // full `items` array under `generating` BEFORE the questions are
              // drawn, so a reader arriving from the email CTA inside that
              // window would otherwise see a gradable list whose every grade
              // came back rejected (2.37.2).
              if (!session.gradable)
                _statusPanel(session)
              else
                for (final item in session.items) _itemCard(session, item),
              const SizedBox(height: AppSpacing.s8),
            ],
          ),
        );
      },
    );
  }

  String _sessionLine(StudySession s) {
    final parts = <String>[];
    if (s.newCount > 0) parts.add('${s.newCount} new');
    if (s.reviewCount > 0) parts.add('${s.reviewCount} to review');
    if (s.rampCount > 0) parts.add('${s.rampCount} pulled forward for an exam');
    // due_remaining is overdue material BEYOND this session's cap — still due,
    // and saying so stops the session reading as "you are finished".
    if (s.dueRemaining > 0) parts.add('${s.dueRemaining} still due after this');
    return parts.isEmpty ? 'Nothing due.' : parts.join(' · ');
  }

  /// A session that cannot be graded says why, and says it as information.
  /// `empty` is not a failure (ADR-011) and an unknown status is not either —
  /// the vocabulary is open.
  Widget _statusPanel(StudySession s) {
    final (title, body) = switch (s.status) {
      'generating' => (
          'Still being made',
          'The questions are being drawn. This page updates on its own.'
        ),
      'empty' => (
          'Nothing due',
          s.errorMessage ??
              'There was nothing new to introduce and nothing due to review.'
        ),
      'error' => (
          'This session could not be built',
          s.errorMessage ?? 'Nothing was consumed — try again.'
        ),
      _ => ('This session is not ready', 'Check back shortly.'),
    };
    return KitCard(
      padding: const EdgeInsets.all(AppSpacing.s5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: KitText.h4(context)),
          const SizedBox(height: 6),
          Lede(body, fontSize: 16, height: 24, maxWidth: double.infinity),
        ],
      ),
    );
  }

  /// One unit: its source, its kind, and its questions.
  Widget _itemCard(StudySession session, StudySessionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: KitCard(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: KitText.meta(context)),
                ),
                if (item.kind == 'new')
                  const KitStatusPill('New', positive: true),
                // Present only when true — its absence means an ordinary due
                // review, not "no exam".
                if (item.ramp) ...[
                  const SizedBox(width: 6),
                  const KitStatusPill('Exam prep'),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.s3),
            for (final q in item.questions) _question(session, item, q),
          ],
        ),
      ),
    );
  }

  Widget _question(
      StudySession session, StudySessionItem item, Map<String, dynamic> q) {
    final qid = q['qid'] as String? ?? '';
    final revealed = _revealed.contains(qid);
    // A grade already in `responses` came from the live subscription — this is
    // what makes a session resumable across a restart, or a device.
    final already = session.responses[qid] != null;
    final outcome = _outcome[qid];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The prompt in reading type — this is the thing being recalled.
          Text(q['question'] as String? ?? '',
              style: KitText.bodyReading(context)),
          const SizedBox(height: AppSpacing.s2),
          if (!revealed && !already)
            KitButton('Show answer',
                variant: KitButtonVariant.secondary,
                onPressed: () {
                  setState(() => _revealed.add(qid));
                  // The excerpt MOUNTS on reveal, so the read is logged here —
                  // which is what makes a review's excerpt count only once its
                  // disclosure is opened (ADR-039 §6).
                  _logExcerptRead(session, item);
                })
          else ...[
            Text(q['answer'] as String? ?? '',
                style: KitText.body(context)),
            if (item.excerptHtml.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s2),
              // The chunk's own sanitized html (INV-10), annotated for §17:
              // a marker inside an excerpt is the extractor talking about the
              // document, and drawn in the body role it reads as the prompt's
              // own copy (4.52.0, ADR-089).
              Html(
                data: markSanitizedHtml(item.excerptHtml),
                extensions: AppTheme.htmlExtensions,
                style: AppTheme.htmlStyles(Tokens.of(context)),
              ),
            ],
            const SizedBox(height: AppSpacing.s3),
            if (already && outcome == null)
              KitRowNote('Answered.')
            else if (outcome != null)
              KitRowNote(outcome)
            else
              // Grades are NOT optimistic: the row disables until the write
              // confirms (the 2.33.0 posture — this screen's whole value is
              // that the schedule is real).
              Wrap(
                spacing: AppSpacing.s2,
                runSpacing: AppSpacing.s2,
                children: [
                  for (final g in studyGrades)
                    KitButton(
                      _gradeLabels[g]!,
                      variant: KitButtonVariant.secondary,
                      onPressed: _busy.contains(qid)
                          ? null
                          : () => _grade(session, item, qid, g),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
