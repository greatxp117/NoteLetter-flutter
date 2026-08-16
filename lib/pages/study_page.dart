/// Study programs (contract 2.34.0, ADR-033; reshaped 3.0.0, ADR-038).
///
/// A study program is a scheduled recall loop over chosen sources. This screen
/// lists them and starts a session; the editor and the player are separate
/// routes.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/study.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/firestore_service.dart';
import '../state/activation_message.dart';
import '../theme/app_colors.dart';
import '../widgets/app_toast.dart';
import '../theme/app_radius.dart';

/// Status copy for the OPEN vocabulary. An unrecognised value renders
/// neutrally — never as an error, and never as the raw token.
String studyStatusLabel(String status) {
  switch (status) {
    case 'active':
      return 'Introducing new material';
    case 'maintenance':
      return 'Reviews only';
    case 'complete':
      // A statement about TODAY, not a terminal state — more may fall due
      // tomorrow, so it must not read like an ending.
      return 'Nothing due today';
    default:
      return 'In progress';
  }
}

class StudyPage extends StatelessWidget {
  const StudyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    return StreamBuilder<List<StudyProgram>>(
      stream: FirestoreService.instance.subscribeStudyPrograms(),
      builder: (context, snap) {
        final programs = snap.data;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Study',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(
                          'A scheduled recall loop over sources you choose. '
                          'Questions come back on a spacing that follows how '
                          'well you remembered them.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  FilledButton.icon(
                    onPressed: () => context.go('/study/new'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New program'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (programs == null)
                const Center(child: CircularProgressIndicator())
              else if (programs.isEmpty)
                Text(
                  'No programs yet. Pick up to ten finished sources and they '
                  'become the curriculum, in the order you choose.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                )
              else
                for (final p in programs) _ProgramCard(program: p, muted: muted),
            ],
          ),
        );
      },
    );
  }
}

class _ProgramCard extends StatefulWidget {
  const _ProgramCard({required this.program, required this.muted});
  final StudyProgram program;
  final Color muted;

  @override
  State<_ProgramCard> createState() => _ProgramCardState();
}

class _ProgramCardState extends State<_ProgramCard> {
  bool _busy = false;

  /// The switch **writes before it moves** (the ADR-022 rule): an optimistic
  /// toggle that later fails leaves the reader believing a thing that is not
  /// true, and delivery is exactly where that matters.
  Future<void> _setEnabled(bool value) async {
    setState(() => _busy = true);
    try {
      final res = await Api.instance
          .updateStudyProgram(widget.program.id, {'enabled': value});
      if (!mounted) return;
      // 2.30.0 — the backend decides whether a session goes out now; this
      // only reports what it decided. Open reason vocabulary.
      final msg = value ? activationMessage(res) : null;
      AppToast.show(context, msg ?? (value ? 'Scheduled study is on.' : 'Paused. Your progress is kept.'),
          type: ToastType.success);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not change that.', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _studyNow() async {
    setState(() => _busy = true);
    try {
      final res = await Api.instance.requestStudySession(widget.program.id);
      final sessionId = res['sessionId'] as String?;
      if (!mounted) return;
      if (sessionId != null) {
        context.go('/study/session/$sessionId');
      } else {
        AppToast.show(context, 'Session requested.', type: ToastType.success);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 429 is a COOLDOWN, not a failure — render it as copy so it reads
      // like the system working rather than breaking.
      final cooling = e.statusCode == 429;
      AppToast.show(
          context,
          cooling
              ? 'A session was just requested — give it a moment.'
              : e.message,
          type: cooling ? ToastType.info : ToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = widget.program;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(
            color: isDark ? AppColors.borderDark : AppColors.borderLight),
        borderRadius: AppRadius.mdR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(p.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Switch(
                value: p.enabled,
                onChanged: _busy ? null : _setEnabled,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            // introduced_count is a display stat, never a cursor.
            '${studyStatusLabel(p.status)} · ${p.introducedCount} of ${p.unitCount} passages introduced'
            '${p.unitNumber > 1 ? ' · unit ${p.unitNumber}' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(color: widget.muted),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.tonal(
                onPressed: _busy ? null : _studyNow,
                child: Text(_busy ? 'Working…' : 'Study now'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => context.go('/study/${p.id}'),
                child: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
