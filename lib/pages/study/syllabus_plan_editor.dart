/// The syllabus plan editor (`screens/study.md` §Syllabus; web
/// `pages/study/SyllabusPlanEditor.jsx`). From 4.103.0 (ADR-136) the read runs
/// in the background and this editor opens over the stored proposal from For
/// your review: edits live here until **Apply this plan**, which hands the
/// edited `units` and `assessments` to [onApply] — the stored proposal is never
/// rewritten.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';

class SyllabusPlanEditor extends StatefulWidget {
  /// `fn_suggest_syllabus_plan`'s body: `{units, assessments, skipped, notes}`.
  final Map<String, dynamic> proposal;
  final bool busy;
  final void Function(List<Map<String, dynamic>> units,
      List<Map<String, dynamic>> assessments) onApply;
  final VoidCallback onDiscard;
  final String discardLabel;

  const SyllabusPlanEditor({
    super.key,
    required this.proposal,
    required this.onApply,
    required this.onDiscard,
    this.busy = false,
    this.discardLabel = 'Discard',
  });

  @override
  State<SyllabusPlanEditor> createState() => _SyllabusPlanEditorState();
}

class _Unit {
  final TextEditingController topic;
  String? startsOn;
  _Unit(String t, this.startsOn) : topic = TextEditingController(text: t);
}

class _Assessment {
  final TextEditingController title;
  String? on;
  String kind;
  bool cumulative;
  _Assessment(String t, this.on, this.kind, this.cumulative)
      : title = TextEditingController(text: t);
}

class _SyllabusPlanEditorState extends State<SyllabusPlanEditor> {
  late final List<_Unit> _units = [
    for (final u in (widget.proposal['units'] as List?) ?? const [])
      if (u is Map) _Unit('${u['topic'] ?? ''}', u['startsOn'] as String?),
  ];
  late final List<_Assessment> _tests = [
    for (final a in (widget.proposal['assessments'] as List?) ?? const [])
      if (a is Map)
        _Assessment('${a['title'] ?? ''}', a['on'] as String?,
            (a['assessmentKind'] as String?) ?? 'exam', a['cumulative'] == true),
  ];
  late final List<Map> _skipped = [
    for (final s in (widget.proposal['skipped'] as List?) ?? const [])
      if (s is Map) s,
  ];

  @override
  void dispose() {
    for (final u in _units) {
      u.topic.dispose();
    }
    for (final a in _tests) {
      a.title.dispose();
    }
    super.dispose();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<String?> _pick(String? current) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(current ?? '') ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    return d == null ? current : _iso(d);
  }

  /// What Apply would send, and what it would leave out — said before it is
  /// pressed (web `pending`).
  ({
    List<Map<String, dynamic>> units,
    List<Map<String, dynamic>> assessments,
    List<String> leftOut
  }) get _pending {
    final units = [
      for (final u in _units)
        if (u.topic.text.trim().isNotEmpty)
          {'topic': u.topic.text.trim(), 'startsOn': u.startsOn},
    ];
    final assessments = <Map<String, dynamic>>[];
    final leftOut = <String>[];
    for (final a in _tests) {
      final title = a.title.text.trim();
      if (title.isEmpty || a.on == null) {
        leftOut.add(title.isEmpty ? 'An assessment' : title);
      } else {
        assessments.add({
          'title': title,
          'on': a.on,
          'assessmentKind': a.kind,
          'cumulative': a.cumulative,
        });
      }
    }
    return (units: units, assessments: assessments, leftOut: leftOut);
  }


  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fine = KitText.meta(context).copyWith(color: t.fgMuted);
    final notes = (widget.proposal['notes'] as String?) ?? '';
    final pending = _pending;
    final busy = widget.busy;

    Widget dateControl(String? value, ValueChanged<String?> set) =>
        KitButton.ghost(value ?? 'Add a date',
            icon: Icons.event_outlined,
            onPressed: busy ? null : () async => set(await _pick(value)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Here’s what the syllabus says. Nothing takes effect until you apply '
          'it — edit anything that was read wrong.'
          '${notes.isEmpty ? '' : ' The reader’s note: “$notes”.'}',
          style: KitText.body(context),
        ),
        const SizedBox(height: 10),
        if (_units.isEmpty)
          Text(
              'Nothing usable could be read from this document — add topics by '
              'hand, or pick another document.',
              style: fine),
        for (var i = 0; i < _units.length; i++)
          Padding(
            key: ValueKey('syl-unit-$i'),
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 22, child: Text('${i + 1}', style: fine)),
                Expanded(
                  child: KitTextField(
                      controller: _units[i].topic,
                      placeholder: 'Topic',
                      enabled: !busy,
                      onChanged: (_) => setState(() {})),
                ),
                const SizedBox(width: 6),
                dateControl(_units[i].startsOn,
                    (v) => setState(() => _units[i].startsOn = v)),
                KitIconButton(Icons.close,
                    tooltip: 'Remove topic',
                    onPressed: busy
                        ? null
                        : () => setState(() => _units.removeAt(i).topic.dispose())),
              ],
            ),
          ),
        Wrap(spacing: 8, children: [
          KitButton.ghost('Topic',
              icon: Icons.add,
              onPressed: busy
                  ? null
                  : () => setState(() => _units.add(_Unit('', null)))),
          KitButton.ghost('Assessment',
              icon: Icons.add,
              onPressed: busy
                  ? null
                  : () => setState(() => _tests.add(_Assessment(
                      'Exam', _iso(DateTime.now()), 'exam', false)))),
        ]),
        if (_tests.isEmpty)
          Text(
              'No dated assessments were read from this syllabus. If it has '
              'any, add them — a test is what marks the end of a unit and '
              'pulls its material forward in the week before.',
              style: fine),
        for (var i = 0; i < _tests.length; i++)
          Padding(
            key: ValueKey('syl-test-$i'),
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: KitTextField(
                      controller: _tests[i].title,
                      placeholder: 'Assessment',
                      enabled: !busy,
                      onChanged: (_) => setState(() {})),
                ),
                dateControl(
                    _tests[i].on, (v) => setState(() => _tests[i].on = v)),
                SizedBox(
                  width: 190,
                  child: KitSelect<String>(
                    value: _tests[i].kind,
                    options: const ['exam', 'paper'],
                    label: (k) =>
                        k == 'paper' ? 'A paper I hand in' : 'A test I sit',
                    onChanged: busy
                        ? null
                        : (k) => setState(() => _tests[i].kind = k),
                  ),
                ),
                if (_tests[i].kind == 'exam')
                  SizedBox(
                    width: 230,
                    child: KitCheckRow(
                      value: _tests[i].cumulative,
                      title: 'covers everything so far',
                      onChanged: busy
                          ? null
                          : (v) => setState(() => _tests[i].cumulative = v),
                    ),
                  ),
                KitIconButton(Icons.close,
                    tooltip: 'Remove assessment',
                    onPressed: busy
                        ? null
                        : () => setState(() => _tests.removeAt(i).title.dispose())),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Text(
            'Only a test you sit ends a unit — handing in a paper doesn’t mean '
            'you’ve moved past the material, so papers are kept for reference '
            'and do nothing else.',
            style: fine),
        // skipped[] reports rows understood and deliberately NOT used — never
        // collapsed away, and worded as a decision the reader may reverse.
        if (_skipped.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Left out of the plan — add anything back that shouldn’t have '
              'been:', style: fine),
          for (final s in _skipped)
            Text(
                '${s['label'] ?? ''}${s['on'] != null ? ' · ${s['on']}' : ''} — '
                '${skipReasonCopy(s['reason'] as String?)}',
                style: fine),
        ],
        if (pending.leftOut.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Applying now would leave this out:', style: fine),
          for (final l in pending.leftOut)
            Text('$l — it needs both a name and a date.', style: fine),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          KitButton.primary(busy ? 'Applying…' : 'Apply this plan',
              onPressed: busy || pending.units.isEmpty
                  ? null
                  : () => widget.onApply(pending.units, pending.assessments)),
          KitButton.ghost(widget.discardLabel,
              onPressed: busy ? null : widget.onDiscard),
        ]),
      ],
    );
  }
}

/// What the syllabus parse understood and deliberately did NOT use, in words
/// (2.37.0, ADR-037) — web `skipReasonCopy` (`pages/study/schedule.js`), copy
/// for copy. The `reason` vocabulary is OPEN: an unknown value still renders
/// its label and date, with the generic "left out".
///
/// Until 4.112.0 every row here was this client's own paraphrase ("not a
/// teaching week" where `screens/study.md` quotes "a week that teaches
/// nothing"), and `assessment` (ADR-149) fell to the generic line.
String skipReasonCopy(String? reason) => switch (reason) {
      'non_teaching' => 'a week that teaches nothing',
      'exam_unit_unmatched' =>
        'this exam named a topic that isn’t in the plan',
      'exam_no_units' => 'none of the topics this exam covers matched the plan',
      'over_cap' => 'the plan was already full — add it by hand if you need it',
      // 4.112.0 (ADR-149): a unit whose topic names a sitting is dropped from
      // the units; the assessment itself is kept, which is where the reader
      // finds it.
      'assessment' => 'an exam or quiz, not a week of material — it is with '
          'the assessments when the syllabus dates it',
      _ => 'left out',
    };
