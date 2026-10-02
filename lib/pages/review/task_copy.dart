/// For your review's words for a background task (`screens/review.md`
/// §Proposals §Running, 4.101.0–4.103.0) — mirrors `ReviewView.jsx`'s
/// TASK_PILL / PHASE_LABEL / PROPOSING_LABEL / KIND_NAME, `taskDetail` and
/// `proposalLine`, as pure functions a test can hold to the reference.
library;

import '../../models/background_task.dart';
import '../../widgets/kit/kit.dart' show KitProcTone;

String _counted(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

const _taskPill = <String, (KitProcTone, String)>{
  'queued': (KitProcTone.wait, 'Queued'),
  'running': (KitProcTone.work, 'Working'),
  'applying': (KitProcTone.work, 'Applying'),
  'awaiting_review': (KitProcTone.hold, 'Needs you'),
  'failed': (KitProcTone.fail, 'Failed'),
};
const _phaseLabel = <String, String>{
  'capturing': 'Reading',
  'stripping': 'Deleting',
  'proposing': 'Finding shelves',
};

/// A proposal kind's one phase, named for what it reads (4.102.0, 4.103.0).
const _proposingLabel = <String, String>{
  'shelf_backfill': 'Reading your library',
  'shelf_split': 'Reading the shelf',
  'syllabus_plan': 'Reading the syllabus',
  'reorg_plan': 'Reading the document',
};
const _kindName = <String, String>{
  'shelf_delete': 'Deleting a shelf',
  'shelf_backfill': 'Finding sources for a shelf',
  'shelf_split': 'Suggesting a split',
  'syllabus_plan': 'Reading a syllabus',
  'reorg_plan': 'Drafting a reorganization',
};

const taskStalledSentence =
    'This stopped before it finished. Try again to finish it.';

/// The §6.3 pill: stalled before anything, then a running task's phase, then
/// the status. An unknown status waits, labelled as a task — never its token.
(KitProcTone, String) taskPill(BackgroundTask t, DateTime now) {
  if (t.isStalled(now)) return (KitProcTone.fail, 'Stalled');
  final phase = t.progress?['phase'] as String?;
  if (t.status == 'running' && phase == 'proposing') {
    final l = _proposingLabel[t.kind];
    if (l != null) return (KitProcTone.work, l);
  }
  if (t.status == 'running') {
    final l = _phaseLabel[phase];
    if (l != null) return (KitProcTone.work, l);
  }
  return _taskPill[t.status] ?? (KitProcTone.wait, 'Waiting');
}

/// The detail line — measured values only (§22), never elapsed time.
String taskDetail(BackgroundTask t) {
  final bits = [_kindName[t.kind] ?? 'Background task'];
  final p = t.progress ?? const {};
  final done = p['done'], total = p['total'];
  final members = t.capture?['member_count'];
  if (done is num && total is num && total > 0) {
    bits.add('${done.toInt()} of ${_counted(total.toInt(), 'source')} taken off');
  } else if (members is num) {
    bits.add(_counted(members.toInt(), 'source'));
  }
  return bits.join(' · ');
}

/// The strip's sentence: stalled, failed, or the proposal in one line.
String? taskSentence(BackgroundTask t, DateTime now) {
  if (t.isStalled(now)) return taskStalledSentence;
  if (t.status == 'failed') {
    return t.errorMessage ?? 'This could not be finished. Try again.';
  }
  if (t.status == 'awaiting_review') return proposalLine(t);
  return null;
}

/// The proposal in one line (`screens/review.md` §Proposals). Null for a kind
/// no renderer lists: its row still stands, with its subject and Dismiss.
String? proposalLine(BackgroundTask t) {
  final r = t.result;
  if (r == null) return null;
  final shelf = t.subjectTitle ?? 'this shelf';
  List list(String k) => (r[k] as List?) ?? const [];
  int n(String k) => (r[k] as num?)?.toInt() ?? 0;
  switch (t.kind) {
    case 'shelf_backfill':
      return '${list('candidates').length} of your '
          '${_counted(n('scanned'), 'source')} look like they belong on $shelf.';
    case 'shelf_split':
      return '$shelf could become '
          '${_counted(list('parts').length, 'shelf', 'shelves')}.';
    case 'syllabus_plan':
      final doc = t.params['document_title'] as String? ?? 'the syllabus';
      final units = list('units').length, tests = list('assessments').length;
      return units > 0 || tests > 0
          ? '${_counted(units, 'topic')} and ${_counted(tests, 'assessment')} '
              'read from $doc.'
          : 'Nothing usable was read from $doc.';
    case 'reorg_plan':
      return '${t.subjectTitle ?? 'This document'} could be divided into '
          '${_counted(list('sections').length, 'section')}.';
    case 'shelf_delete':
      final m = {
        for (final p in list('proposals'))
          if (p is Map) p['documentId'],
      }.length;
      return m > 0
          ? '$m of ${_counted(n('scanned'), 'source')} from $shelf have a '
              'suggested shelf.'
          : 'None of your shelves looked like a clear fit for the sources '
              'from $shelf.';
  }
  return null;
}
