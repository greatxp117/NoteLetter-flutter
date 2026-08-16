/// Study program editor (contract 2.34.0 ADR-033; reshaped 3.0.0 ADR-038).
///
/// Creation picks 1–10 finished sources whose ORDER is the curriculum order.
/// After creation the two panels that matter are the ones 3.0.0 added: what
/// kind each source is, and where the reader has got to — because **the reader
/// holds the pointer**. A syllabus proposes; it never paces.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../models/document.dart';
import '../../models/study.dart';
import '../../services/api.dart';
import '../../services/firestore_service.dart';
import '../../state/schedule.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_toast.dart';

class ProgramEditorPage extends StatefulWidget {
  const ProgramEditorPage({super.key, this.programId});

  /// Null = create.
  final String? programId;

  @override
  State<ProgramEditorPage> createState() => _ProgramEditorPageState();
}

class _ProgramEditorPageState extends State<ProgramEditorPage> {
  final _title = TextEditingController();
  final _selected = <String>[]; // order IS the curriculum order
  String _timezone = deviceTimezone();
  String _deliveryTime = '07:00';
  String _frequency = 'daily';
  int _newPerSession = 5;
  int _maxReviews = 10;
  bool _saving = false;

  StudyProgram? _program;
  List<Document> _docs = const [];

  bool get _isNew => widget.programId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final docs = await FirestoreService.instance.subscribeDocuments().first;
    if (!mounted) return;
    setState(() {
      // Only finished sources can be a curriculum — an unindexed one has no
      // passages to introduce.
      _docs = docs
          .where((d) => d.status == DocumentStatus.complete)
          .toList();
    });
    if (!_isNew) {
      final programs =
          await FirestoreService.instance.subscribeStudyPrograms().first;
      if (!mounted) return;
      final p = programs.where((x) => x.id == widget.programId).firstOrNull;
      if (p != null) {
        setState(() {
          _program = p;
          _title.text = p.title;
          _selected
            ..clear()
            ..addAll(p.documentIds);
          _timezone = p.timezone;
          _deliveryTime = p.deliveryTime;
          _frequency = p.frequency;
          _newPerSession = p.newPerSession;
          _maxReviews = p.maxReviewsPerSession;
        });
      }
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _selected.isEmpty) return;
    setState(() => _saving = true);
    try {
      if (_isNew) {
        final res = await Api.instance.createStudyProgram({
          'title': _title.text.trim(),
          'documentIds': _selected,
          'deliveryTime': _deliveryTime,
          // A client sending deliveryTime sends timezone in the SAME call
          // (2.29.0), or the orchestrator reads the stored time as UTC.
          'timezone': _timezone,
          'frequency': _frequency,
          'newPerSession': _newPerSession,
          'maxReviewsPerSession': _maxReviews,
        });
        if (!mounted) return;
        final id = res['programId'] as String?;
        AppToast.show(context, 'Program created.', type: ToastType.success);
        if (id != null) context.go('/study/$id');
      } else {
        // documentIds are immutable after creation (ADR-033 v1), so they are
        // deliberately NOT sent on update.
        await Api.instance.updateStudyProgram(widget.programId!, {
          'title': _title.text.trim(),
          'deliveryTime': _deliveryTime,
          'timezone': _timezone,
          'frequency': _frequency,
          'newPerSession': _newPerSession,
          'maxReviewsPerSession': _maxReviews,
        });
        if (!mounted) return;
        AppToast.show(context, 'Saved.', type: ToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Could not save that.', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted =
        isDark ? AppColors.mutedForegroundDark : AppColors.mutedForeground;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 64),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isNew ? 'New study program' : 'Study program',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 18),

              if (_isNew) ...[
                Text('Sources — the order is the curriculum order',
                    style: theme.textTheme.labelLarge),
                Text(
                  'Up to ten finished sources. New passages are introduced in '
                  'this order.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
                const SizedBox(height: 8),
                for (final d in _docs)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(d.id),
                    title: Text(d.title, maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    subtitle: _selected.contains(d.id)
                        ? Text('${_selected.indexOf(d.id) + 1} of ${_selected.length}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: muted))
                        : null,
                    onChanged: (on) => setState(() {
                      if (on == true) {
                        if (_selected.length < 10) _selected.add(d.id);
                      } else {
                        _selected.remove(d.id);
                      }
                    }),
                  ),
                const SizedBox(height: 18),
              ],

              _schedule(theme, muted),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? 'Saving…'
                    : (_isNew ? 'Create program' : 'Save')),
              ),

              if (!_isNew && _program != null) ...[
                const SizedBox(height: 28),
                _SourceKindPanel(program: _program!, docs: _docs),
                const SizedBox(height: 24),
                _UnitPanel(program: _program!, docs: _docs, onDone: _load),
                const SizedBox(height: 24),
                _SyllabusPanel(program: _program!, docs: _docs, onDone: _load),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _schedule(ThemeData theme, Color muted) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: _deliveryTime,
                decoration: const InputDecoration(labelText: 'Time (HH:MM)'),
                onChanged: (v) => _deliveryTime = v.trim(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _timezone,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Timezone'),
                items: [
                  for (final tz in timezoneOptions(_timezone))
                    DropdownMenuItem(value: tz, child: Text(tz)),
                ],
                onChanged: (v) => setState(() => _timezone = v ?? _timezone),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('Daily')),
                  DropdownMenuItem(value: 'weekdays', child: Text('Weekdays')),
                  DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                ],
                onChanged: (v) => setState(() => _frequency = v ?? _frequency),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: '$_newPerSession',
                decoration: const InputDecoration(labelText: 'New per session'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _newPerSession = int.tryParse(v) ?? 5,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                initialValue: '$_maxReviews',
                decoration: const InputDecoration(labelText: 'Max reviews'),
                keyboardType: TextInputType.number,
                onChanged: (v) => _maxReviews = int.tryParse(v) ?? 10,
              ),
            ),
          ]),
        ],
      );
}

/// What each source IS (3.0.0, ADR-038 §Source kind).
///
/// **Per document, and asked rather than guessed.** `notes` are never withheld;
/// a `reading` is served only as far as the reader says they have read, because
/// a textbook out of order is worse than useless. The guess is deliberately
/// narrow — handwriting and camera captures only — and `author`/`publish_date`
/// were **rejected on measurement** (null on both PDFs of the first live
/// program), which makes the ambiguous middle the common case and the ask
/// first-class rather than a fallback.
class _SourceKindPanel extends StatelessWidget {
  const _SourceKindPanel({required this.program, required this.docs});
  final StudyProgram program;
  final List<Document> docs;

  String _titleFor(String id) =>
      docs.where((d) => d.id == id).firstOrNull?.title ?? id;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppColors.mutedForegroundDark
        : AppColors.mutedForeground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What each source is', style: theme.textTheme.labelLarge),
        Text(
          'Notes are always available. A reading is only served as far as you '
          'have got — a textbook out of order is worse than useless.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        for (final id in program.documentIds)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                    child: Text(_titleFor(id),
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(
                  program.kindFor(id) == 'reading'
                      ? 'A reading'
                      : 'My notes',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Starting a new unit (3.0.0, ADR-038).
///
/// **A unit is the content between examinations, and the reader moves the
/// pointer.** Always an explicit action, available with or without a syllabus,
/// and it asks each `reading` the one thing nothing can infer: how far you got.
class _UnitPanel extends StatefulWidget {
  const _UnitPanel(
      {required this.program, required this.docs, required this.onDone});
  final StudyProgram program;
  final List<Document> docs;
  final Future<void> Function() onDone;

  @override
  State<_UnitPanel> createState() => _UnitPanelState();
}

class _UnitPanelState extends State<_UnitPanel> {
  final Map<String, int?> _positions = {};
  bool _busy = false;

  Future<void> _advance() async {
    final readings = widget.program.documentIds
        .where((id) => widget.program.kindFor(id) == 'reading')
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new unit?'),
        content: Text(
          readings.isEmpty
              ? 'Everything available so far is treated as covered, and new '
                  'material is introduced from here.'
              : 'Everything available so far is treated as covered. Say how far '
                  'you have read in each reading, and new material is '
                  'introduced from there.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not yet')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Start the unit')),
        ],
      ),
    );
    // Deliberately not idempotent, so it is confirmed before it is called.
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await Api.instance.advanceStudyUnit(widget.program.id,
          positions: {
            for (final e in _positions.entries)
              if (e.value != null) e.key: e.value,
          });
      await widget.onDone();
      if (mounted) {
        AppToast.show(context, 'Unit ${widget.program.unitNumber + 1} started.',
            type: ToastType.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not start the unit.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppColors.mutedForegroundDark
        : AppColors.mutedForeground;
    final readings = widget.program.documentIds
        .where((id) => widget.program.kindFor(id) == 'reading')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Unit ${widget.program.unitNumber}',
            style: theme.textTheme.labelLarge),
        Text(
          'A unit is the stretch between one test and the next. Starting a new '
          'one is always your call — no date does it for you.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        for (final id in readings)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: TextFormField(
              decoration: InputDecoration(
                labelText:
                    'How far in "${widget.docs.where((d) => d.id == id).firstOrNull?.title ?? id}"? (passage number)',
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) => _positions[id] = int.tryParse(v),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : _advance,
          child: Text(_busy ? 'Starting…' : 'Start a new unit'),
        ),
      ],
    );
  }
}

/// The syllabus (2.36.0 ADR-035; reshaped 3.0.0 ADR-038).
///
/// Parsed once from an ordinary ingested document, **reviewed**, then applied.
/// It supplies display topics and assessment prompts only — **it paces
/// nothing** (INV-19). Attaching or detaching changes the topic list and the
/// reminders, and nothing else.
class _SyllabusPanel extends StatefulWidget {
  const _SyllabusPanel(
      {required this.program, required this.docs, required this.onDone});
  final StudyProgram program;
  final List<Document> docs;
  final Future<void> Function() onDone;

  @override
  State<_SyllabusPanel> createState() => _SyllabusPanelState();
}

class _SyllabusPanelState extends State<_SyllabusPanel> {
  bool _busy = false;
  String? _sourceId;
  List<Map<String, dynamic>> _units = [];
  List<Map<String, dynamic>> _assessments = [];
  List<Map<String, dynamic>> _skipped = [];
  bool _proposed = false;

  Future<void> _suggest() async {
    if (_sourceId == null) return;
    setState(() => _busy = true);
    try {
      final res =
          await Api.instance.suggestSyllabusPlan(widget.program.id, _sourceId!);
      if (!mounted) return;
      setState(() {
        _units = ((res['units'] as List?) ?? const [])
            .map((u) => (u as Map).cast<String, dynamic>())
            .toList();
        _assessments = ((res['assessments'] as List?) ?? const [])
            .map((a) => (a as Map).cast<String, dynamic>())
            .toList();
        _skipped = ((res['skipped'] as List?) ?? const [])
            .map((s) => (s as Map).cast<String, dynamic>())
            .toList();
        _proposed = true;
      });
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not read that syllabus.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      await Api.instance.applySyllabusPlan(
          widget.program.id, _sourceId!, _units, _assessments);
      await widget.onDone();
      if (mounted) {
        setState(() => _proposed = false);
        AppToast.show(context, 'Syllabus attached.', type: ToastType.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not apply that plan.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.brightness == Brightness.dark
        ? AppColors.mutedForegroundDark
        : AppColors.mutedForeground;
    final attached = widget.program.syllabus;
    // Any COMPLETE document that is not itself part of the curriculum.
    final candidates = widget.docs
        .where((d) => !widget.program.documentIds.contains(d.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Syllabus', style: theme.textTheme.labelLarge),
        Text(
          'A syllabus gives this program its topic names and reminds you when '
          'a test is coming. It does not decide what you study or when — that '
          'stays with you.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 8),
        if (attached != null && !_proposed) ...[
          Text('${attached.units.length} topics · '
              '${attached.assessments.length} assessments',
              style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    try {
                      await Api.instance.detachSyllabusPlan(widget.program.id);
                      await widget.onDone();
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
            child: const Text('Detach — keeps every passage and all progress'),
          ),
        ] else if (!_proposed) ...[
          DropdownButtonFormField<String>(
            initialValue: _sourceId,
            isExpanded: true,
            decoration:
                const InputDecoration(labelText: 'Attach a syllabus document'),
            items: [
              for (final d in candidates)
                DropdownMenuItem(
                    value: d.id,
                    child: Text(d.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _sourceId = v),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: (_busy || _sourceId == null) ? null : _suggest,
            child: Text(_busy ? 'Reading…' : 'Read this syllabus'),
          ),
        ] else ...[
          // The proposal is EDITABLE before it is applied — the suggest/apply
          // split is the whole safety mechanism, and a review you cannot
          // change is not a review.
          for (var i = 0; i < _units.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: TextFormField(
                initialValue: _units[i]['topic'] as String? ?? '',
                decoration: InputDecoration(
                    labelText: 'Topic ${i + 1}',
                    helperText: _units[i]['starts_on'] as String?),
                onChanged: (v) => _units[i] = {..._units[i], 'topic': v},
              ),
            ),
          const SizedBox(height: 8),
          if (_assessments.isEmpty)
            Text(
              'No dated assessments were read from this syllabus. An exam is '
              'what pulls its topics forward in the week before it — if there '
              'are some, they may be in a grading table rather than the '
              'calendar.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            )
          else
            for (final a in _assessments)
              Text(
                '${a['title']} · ${a['on']}'
                '${a['assessment_kind'] == 'paper' ? ' · a paper you hand in' : ' · a test you sit'}'
                '${a['cumulative'] == true ? ' · cumulative' : ''}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          // skipped[] reports rows understood and deliberately NOT used —
          // never collapsed away, and worded as a decision you may reverse.
          if (_skipped.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Left out — add anything back that should not have been:',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
            for (final s in _skipped)
              Text(
                '${s['label'] ?? ''}${s['on'] != null ? ' · ${s['on']}' : ''} — ${_skipReason(s['reason'] as String?)}',
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
              ),
          ],
          const SizedBox(height: 10),
          Row(children: [
            FilledButton(
              onPressed: _busy ? null : _apply,
              child: Text(_busy ? 'Applying…' : 'Apply'),
            ),
            const SizedBox(width: 8),
            TextButton(
                onPressed: () => setState(() => _proposed = false),
                child: const Text('Cancel')),
          ]),
        ],
      ],
    );
  }

  /// Open vocabulary — an unknown reason takes generic copy rather than
  /// rendering the raw token.
  static String _skipReason(String? reason) {
    switch (reason) {
      case 'non_teaching':
        return 'not a teaching week';
      case 'exam_unit_unmatched':
        return 'its topics could not be matched';
      case 'exam_no_units':
        return 'it named no topics';
      case 'over_cap':
        return 'beyond the limit for one syllabus';
      default:
        return 'left out of the plan';
    }
  }
}
