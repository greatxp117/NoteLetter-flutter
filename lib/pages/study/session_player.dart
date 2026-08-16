/// The study session player (contract 2.34.0 ADR-033; 2.37.2; 3.1.0 ADR-039).
///
/// This is where the session email's CTA lands. It subscribes to the ONE
/// session document while `fn_submit_study_answer` writes into it, which is
/// what makes a session resumable: close the app mid-session, come back, and
/// the grades already given are there.
library;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../models/study.dart';
import '../../services/api.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';

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

  Future<void> _grade(StudySession session, StudySessionItem item, String qid,
      String grade) async {
    setState(() => _busy.add(qid));
    try {
      final res =
          await Api.instance.submitStudyAnswer(session.id, qid, grade);
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
          final due = (res['item'] as Map?)?['due_at'];
          _outcome[qid] = due is int
              ? 'Back on ${_fmtDate(due)}.'
              : 'Recorded.';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _outcome[qid] = 'Could not record that — try again.');
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

  static String _fmtDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    return StreamBuilder<StudySession?>(
      stream: FirestoreService.instance.subscribeStudySession(widget.sessionId),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          // A dropped subscription is a connection problem, not a wrong
          // account — saying the latter sends the reader looking for a
          // problem they do not have.
          return _message(theme, muted, 'The connection dropped.',
              'Check your connection and try again.');
        }
        final session = snap.data;
        if (session == null) {
          return _message(theme, muted, 'Session not found',
              'This session may belong to another account.');
        }

        if (!session.gradable) {
          return _statusPanel(theme, muted, session);
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 64),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.programTitle,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(_sessionLine(session),
                      style:
                          theme.textTheme.bodySmall?.copyWith(color: muted)),
                  const SizedBox(height: 20),
                  for (final item in session.items)
                    _itemCard(theme, muted, session, item),
                ],
              ),
            ),
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

  Widget _statusPanel(ThemeData theme, Color muted, StudySession s) {
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
      // Open vocabulary: an unknown status is informational, never an error.
      _ => ('This session is not ready', 'Check back shortly.'),
    };
    return _message(theme, muted, title, body);
  }

  Widget _message(ThemeData theme, Color muted, String title, String body) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            ],
          ),
        ),
      );

  Widget _itemCard(ThemeData theme, Color muted, StudySession session,
      StudySessionItem item) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(color: muted)),
              ),
              if (item.kind == 'new')
                _chip(theme, 'New', AppColors.positive),
              // Present only when true — absence means an ordinary due review.
              if (item.ramp) _chip(theme, 'Exam prep', AppColors.primary),
            ],
          ),
          const SizedBox(height: 10),
          for (final q in item.questions)
            _question(theme, muted, session, item, q),
        ],
      ),
    );
  }

  Widget _chip(ThemeData theme, String label, Color color) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: theme.textTheme.labelSmall?.copyWith(color: color)),
      );

  Widget _question(ThemeData theme, Color muted, StudySession session,
      StudySessionItem item, Map<String, dynamic> q) {
    final qid = q['qid'] as String? ?? '';
    final revealed = _revealed.contains(qid);
    // A grade already in `responses` came from the live subscription — this is
    // what makes the session resumable across a restart.
    final already = session.responses[qid] != null;
    final outcome = _outcome[qid];

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q['question'] as String? ?? '',
              style: theme.textTheme.bodyLarge),
          const SizedBox(height: 8),
          if (!revealed && !already)
            OutlinedButton(
              onPressed: () {
                setState(() => _revealed.add(qid));
                // The excerpt mounts on reveal, so the read is logged here.
                _logExcerptRead(session, item);
              },
              child: const Text('Show answer'),
            )
          else ...[
            Text(q['answer'] as String? ?? '',
                style: theme.textTheme.bodyMedium),
            if (item.excerptHtml.isNotEmpty) ...[
              const SizedBox(height: 8),
              // The chunk's own sanitized html (INV-10 vocabulary).
              Html(data: item.excerptHtml),
            ],
            const SizedBox(height: 10),
            if (already && outcome == null)
              Text('Answered.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted))
            else if (outcome != null)
              Text(outcome,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted))
            else
              Wrap(
                spacing: 8,
                children: [
                  for (final g in studyGrades)
                    OutlinedButton(
                      onPressed: _busy.contains(qid)
                          ? null
                          : () => _grade(session, item, qid, g),
                      child: Text(_gradeLabels[g]!),
                    ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
