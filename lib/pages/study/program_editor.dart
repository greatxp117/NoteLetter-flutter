/// Study program editor (`spec/screens/study.md` §Create / edit; contract
/// 2.34.0 ADR-033, reshaped 3.0.0 ADR-038), composed as web's
/// `pages/study/ProgramEditor.jsx`.
///
/// Chapter opening · Name · Sources for this subject · (an existing program:
/// What each source is · Where you are · Syllabus) · Delivery · Session length
/// · the form's foot. Each section is a [KitFormSection]; its lists are §4.1
/// [KitRowList]s of [KitFormRow]s; its fields are the readings letter's
/// sunken field ([KitConfigField] over [KitTextField]/[KitSelect]). Until
/// 2026-10-14 this screen was plain Material — a headline, `TextField`s and a
/// `CheckboxListTile` per source — with no email settings, no way to order or
/// remove a source, no way to say what a source IS, and no Delete.
///
/// Creation picks 1–10 finished sources whose ORDER is the curriculum order.
/// After creation the panels that matter are the ones 3.0.0 added: what kind
/// each source is, and where the reader has got to — because **the reader
/// holds the pointer**. A syllabus proposes; it never paces.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../models/document.dart';
import '../../models/study.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../state/schedule.dart';
import '../../state/study_schedule.dart';
import '../../widgets/kit/kit.dart';
import '../../shared/passage_figure.dart';

const _maxDocs = 10;

String _counted(int n, String noun, [String? many]) =>
    '$n ${n == 1 ? noun : (many ?? '${noun}s')}';

class ProgramEditorPage extends StatefulWidget {
  const ProgramEditorPage({super.key, this.programId});

  /// Null = create.
  final String? programId;

  @override
  State<ProgramEditorPage> createState() => _ProgramEditorPageState();
}

class _ProgramEditorPageState extends State<ProgramEditorPage> {
  final _title = TextEditingController();
  final _time = TextEditingController(text: '07:00');
  final _email = TextEditingController();
  final _ids = <String>[]; // order IS the curriculum order
  String _timezone = deviceTimezone();
  String _frequency = 'daily';
  bool _emailOn = true;
  int _newPer = 5;
  int _maxReviews = 10;
  bool _busy = false;

  /// The server's own sentence about the last save (C6). It was a constant in
  /// a toast; a 400 naming the field, a 409 naming the conflict and a 429
  /// naming the wait all rendered as the same four words, then disappeared.
  String? _error;

  /// What turning the new program on did (`activationSend`), said after the
  /// create — web's `.st-note` with its "Back to programs".
  String? _note;

  StudyProgram? _program;
  List<Document> _docs = const [];
  StreamSubscription<List<StudyProgram>>? _programs;
  bool _seeded = false;

  bool get _isNew => widget.programId == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _programs?.cancel();
    _title.dispose();
    _time.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final docs = await FirestoreService.instance.subscribeDocuments().first;
    if (!mounted) return;
    // Only finished sources can be a curriculum — an unindexed one has no
    // passages to introduce.
    setState(() => _docs =
        docs.where((d) => d.status == DocumentStatus.complete).toList());
    if (_isNew) return;
    // Live, as web's editor is handed its program from the list's
    // subscription: a kind, a position or a started unit shows as soon as it
    // is stored. The form's own fields are seeded once and then are the
    // reader's.
    _programs = FirestoreService.instance.subscribeStudyPrograms().listen((ps) {
      final p = ps.where((x) => x.id == widget.programId).firstOrNull;
      if (p == null || !mounted) return;
      setState(() {
        _program = p;
        if (!_seeded) {
          _seeded = true;
          _title.text = p.title;
          _ids
            ..clear()
            ..addAll(p.documentIds);
          _timezone = p.timezone;
          _time.text = p.deliveryTime;
          _frequency = p.frequency;
          _emailOn = p.emailEnabled;
          _email.text = p.emailAddress;
          _newPer = p.newPerSession;
          _maxReviews = p.maxReviewsPerSession;
        }
      });
    }, onError: (Object e) {
      if (mounted) setState(() => _error = 'This program could not be read.');
    });
  }

  void _close() => context.go('/study');

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
      _note = null;
    });
    // deliveryTime and timezone travel in the same call — the 2.29.0 rule:
    // a time with no zone is read as UTC.
    final body = <String, dynamic>{
      'title': _title.text.trim(),
      'deliveryTime': _time.text.trim(),
      'timezone': _timezone,
      'frequency': _frequency,
      'emailEnabled': _emailOn,
      'emailAddress': _email.text.trim(),
      'newPerSession': _newPer,
      'maxReviewsPerSession': _maxReviews,
    };
    try {
      if (_isNew) {
        final res = await Api.instance
            .createStudyProgram({...body, 'documentIds': List.of(_ids)});
        if (!mounted) return;
        final msg = studyActivationMessage(res);
        if (msg != null) {
          setState(() => _note = msg);
        } else {
          _close();
        }
      } else {
        // documentIds are immutable after creation (ADR-033 v1): never sent.
        await Api.instance.updateStudyProgram(widget.programId!, body);
        if (mounted) _close();
      }
    } on ApiException catch (e) {
      // Beside the form, not in a toast: this is something the reader has to
      // act on, and §14.2's whole job is to still be there when they look.
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'The program could not be saved. Please check your connection '
            'and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// §18 (ADR-092): the panel closes only on success and a refusal answers
  /// INSIDE it — the reader is never moved away from the thing that failed.
  Future<void> _delete() async {
    final p = _program;
    if (p == null) return;
    final n = p.introducedCount;
    final done = await KitConfirm.show(
      context,
      title: 'Delete “${p.title}”?',
      body: 'Its sessions stay in your history, with the grades you gave them. '
          'The schedule does not: every interval and due date goes, and the '
          '${_counted(n, 'passage')} it has introduced '
          '${n == 1 ? 'stops' : 'stop'} being tracked. A new program over the '
          'same documents starts from the beginning.',
      confirmLabel: 'Delete program',
      cancelLabel: 'Keep it',
      onConfirm: () async {
        try {
          await Api.instance.deleteStudyProgram(p.id);
          return null;
        } on ApiException catch (e) {
          return e.message;
        } catch (_) {
          return 'The program could not be deleted. Nothing has changed.';
        }
      },
    );
    if (done == true && mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final existing = !_isNew;
    final p = _program;
    final canSave =
        !_busy && _title.text.trim().isNotEmpty && (existing || _ids.isNotEmpty);
    return KitPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ChapterOpening(
            folio: existing
                ? 'Deep study · Program settings'
                : 'Deep study · New program',
            title: existing ? 'Program Settings' : 'A New Program',
            standfirst: existing
                ? 'What arrives, and when. The documents underneath it are '
                    'settled.'
                : 'Choose what you want to keep, and when you want to be '
                    'asked about it.',
          ),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              // `.st-form`
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: KitFailureInline(_error!),
                    ),
                  if (_note != null)
                    KitFormNote(_note!,
                        link: 'Back to programs', onLink: _close),
                  KitFormSection(
                    eyebrow: 'Name',
                    lede: 'Yours to recognise in a list of programs and at the '
                        'top of an email.',
                    children: [
                      KitTextField(
                        controller: _title,
                        placeholder: 'Untitled program',
                        face: KitFieldFace.ui,
                        sunken: true,
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                  KitFormSection(
                    eyebrow: 'Sources for this subject',
                    count: existing && p != null
                        ? _counted(p.documentIds.length, 'document')
                        : null,
                    children: [
                      if (existing) ..._fixedSources(p) else _picker(),
                    ],
                  ),
                  if (existing && p != null) ...[
                    SourceKindPanel(program: p, docs: _docs),
                    UnitPanel(program: p, docs: _docs),
                    _SyllabusPanel(program: p, docs: _docs),
                  ],
                  _delivery(),
                  _sessionLength(),
                  KitFormFoot(
                    leading: [
                      KitButton.primary(
                        _busy
                            ? 'Saving…'
                            : (existing ? 'Save changes' : 'Create program'),
                        onPressed: canSave ? _save : null,
                      ),
                      KitButton.ghost('Cancel', onPressed: _close),
                    ],
                    trailing: [
                      if (existing && p != null)
                        KitFormDangerButton('Delete program',
                            icon: Icons.delete_outline, onPressed: _delete),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// An existing program's sources: numbered, fixed, and said to be fixed.
  List<Widget> _fixedSources(StudyProgram? p) {
    if (p == null) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: KitRowList(rows: [
          for (var i = 0; i < p.documentIds.length; i++)
            () {
              final d = _docs
                  .where((x) => x.id == p.documentIds[i])
                  .firstOrNull;
              return KitFormRow(
                number: '${i + 1}',
                title: d?.title ?? p.documentIds[i],
                count: d == null
                    ? null
                    : passagesLabel(d.chunkCount),
              );
            }(),
        ]),
      ),
      const KitFixedNote(
          'Sources are fixed once a program starts, because every interval it '
          'holds is counted against them. Create a new program for a '
          'different set.'),
    ];
  }

  /// The source picker (web `SourcePicker`): the chosen, in curriculum order,
  /// each movable and removable; then what is left to add.
  Widget _picker() {
    final byId = {for (final d in _docs) d.id: d};
    final chosen = [
      for (final id in _ids)
        if (byId[id] != null) byId[id]!,
    ];
    final rest = _docs.where((d) => !_ids.contains(d.id)).toList();
    final full = _ids.length >= _maxDocs;

    void move(int i, int by) {
      final j = i + by;
      if (j < 0 || j >= _ids.length) return;
      setState(() {
        final x = _ids[i];
        _ids[i] = _ids[j];
        _ids[j] = x;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitFormLede(
            'A program teaches *one subject.* Choose the documents that '
            'belong to it — up to ten — in the order you want them taught; '
            'sessions introduce passages from the first before moving on. For '
            'a second subject, create a second program.'),
        if (chosen.isNotEmpty)
          KitRowList(rows: [
            for (var i = 0; i < chosen.length; i++)
              KitFormRow(
                number: '${i + 1}',
                kind: kitDocKind(chosen[i].type),
                title: chosen[i].title.isEmpty ? 'Untitled' : chosen[i].title,
                subtitle: (chosen[i].author ?? '').trim().isEmpty
                    ? null
                    : chosen[i].author!.trim(),
                count: passagesLabel(chosen[i].chunkCount),
                trailing: [
                  KitRowIconButton(Icons.arrow_upward,
                      label: 'Move earlier',
                      onPressed: i == 0 ? null : () => move(i, -1)),
                  KitRowIconButton(Icons.arrow_downward,
                      label: 'Move later',
                      onPressed:
                          i == chosen.length - 1 ? null : () => move(i, 1)),
                  KitRowIconButton(Icons.close,
                      label: 'Remove',
                      onPressed: () =>
                          setState(() => _ids.remove(chosen[i].id))),
                ],
              ),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: KitFormSubhead('Add documents',
              count: '${_ids.length} of $_maxDocs chosen'),
        ),
        KitRowList(rows: [
          for (final d in rest)
            KitFormRow(
              kind: kitDocKind(d.type),
              title: d.title.isEmpty ? 'Untitled' : d.title,
              subtitle: passagesLabel(d.chunkCount),
              trailing: [
                KitRowTextButton('Add',
                    onPressed: full
                        ? null
                        : () => setState(() {
                              if (!_ids.contains(d.id)) _ids.add(d.id);
                            })),
              ],
            ),
          if (rest.isEmpty)
            const KitFormRow(
                subtitle: 'Every finished document is already in this '
                    'program.'),
        ]),
        KitFixedNote(
            '${full ? 'Ten is the limit for one subject. Remove one to add '
                'another. ' : ''}Only documents that have finished processing '
            'can be studied.'),
      ],
    );
  }

  Widget _delivery() => KitFormSection(
        eyebrow: 'Delivery',
        lede: 'A session is made and sent at this hour, in this zone.',
        children: [
          KitFormGrid(
            wide: const {3},
            children: [
              KitConfigField(
                top: 0,
                label: 'Arrives at',
                child: KitTextField(
                  controller: _time,
                  icon: Icons.schedule_outlined,
                  placeholder: '07:00',
                  face: KitFieldFace.ui,
                  sunken: true,
                ),
              ),
              KitConfigField(
                top: 0,
                label: 'Time zone',
                child: KitSelect<String>(
                  value: _timezone,
                  options: timezoneOptions(_timezone),
                  label: (z) => z,
                  face: KitFieldFace.ui,
                  sunken: true,
                  onChanged: (z) => setState(() => _timezone = z),
                ),
              ),
              KitConfigField(
                top: 0,
                label: 'Cadence',
                child: KitSelect<String>(
                  value: _frequency,
                  options: const ['daily', 'weekdays', 'weekly'],
                  label: (f) => switch (f) {
                    'weekdays' => 'Weekdays',
                    'weekly' => 'Weekly',
                    _ => 'Daily',
                  },
                  face: KitFieldFace.ui,
                  sunken: true,
                  onChanged: (f) => setState(() => _frequency = f),
                ),
              ),
              KitConfigField(
                top: 0,
                label: 'Email',
                child: KitRowList(rows: [
                  KitFormRow(
                    title: 'Send each session by email',
                    plain: true,
                    subtitle: 'The email carries the questions only. '
                        'Answering happens here.',
                    trailing: [
                      KitSwitch(
                        value: _emailOn,
                        tooltip: 'Send each session by email',
                        onChanged: (v) => setState(() => _emailOn = v),
                      ),
                    ],
                  ),
                  if (_emailOn)
                    KitFormRow(
                      body: KitTextField(
                        controller: _email,
                        icon: Icons.mail_outline,
                        placeholder: 'Your account email, unless set',
                        keyboardType: TextInputType.emailAddress,
                        face: KitFieldFace.ui,
                        sunken: true,
                      ),
                    ),
                ]),
              ),
            ],
          ),
        ],
      );

  Widget _sessionLength() => KitFormSection(
        eyebrow: 'Session length',
        lede: 'How much a single session may carry. Anything due beyond that '
            'waits its turn and comes first next time.',
        children: [
          KitFormGrid(
            rowGap: 20,
            children: [
              KitCapCard(
                title: 'New passages',
                description:
                    'Introduced for the first time, in curriculum order.',
                child: KitStepper(
                  value: _newPer,
                  min: 1,
                  max: 20,
                  unit: _newPer == 1 ? 'passage' : 'passages',
                  onChanged: (v) => setState(() => _newPer = v),
                ),
              ),
              KitCapCard(
                title: 'Reviews',
                description: 'Passages you have seen and are due again.',
                child: KitStepper(
                  value: _maxReviews,
                  min: 1,
                  max: 50,
                  unit: _maxReviews == 1 ? 'question' : 'questions',
                  onChanged: (v) => setState(() => _maxReviews = v),
                ),
              ),
            ],
          ),
        ],
      );
}

/// What each source IS (3.0.0, ADR-038 §Source kind; web `SourceKindPanel`).
///
/// **Per document, and asked rather than guessed.** `notes` are never withheld;
/// a `reading` is served only as far as the reader says they have read,
/// because a textbook out of order is worse than useless. The guess is
/// deliberately narrow — handwriting and camera captures only — and
/// `author`/`publish_date` were **rejected on measurement** (null on both PDFs
/// of the first live program). It was read-only here until 2026-10-14: a
/// reader on this client could never say a source was a reading.
///
/// Each answer sends only that source's entry; the merge is per source, so a
/// correction never disturbs the reader's stored progress. Write before move:
/// the chip lights from the STORED kind, through the program's subscription.
class SourceKindPanel extends StatefulWidget {
  const SourceKindPanel(
      {super.key, required this.program, required this.docs});
  final StudyProgram program;
  final List<Document> docs;

  @override
  State<SourceKindPanel> createState() => _SourceKindPanelState();
}

class _SourceKindPanelState extends State<SourceKindPanel> {
  String? _busy;
  String? _error;
  final Map<String, TextEditingController> _positions = {};

  @override
  void dispose() {
    for (final c in _positions.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _write(String docId, Map<String, dynamic> entry) async {
    setState(() {
      _busy = docId;
      _error = null;
    });
    try {
      await Api.instance.updateStudyProgram(widget.program.id, {
        'sources': {docId: entry},
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'That could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  TextEditingController _positionCtrl(String id) =>
      _positions.putIfAbsent(id, () {
        final pos = widget.program.positionFor(id);
        return TextEditingController(text: pos == null ? '' : '${pos + 1}');
      });

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final ids = p.documentIds;
    final unset = ids.where((id) => p.storedKindFor(id) == null).length;
    return KitFormSection(
      eyebrow: 'What each source is',
      lede: 'Your own notes are always available — sessions can draw on any '
          'of them from day one. A reading you’re working through is '
          'different: it’s served only as far as you’ve actually read, '
          'because a book taken out of order teaches nothing.',
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(_error!),
          ),
        if (unset > 0)
          KitFineNote(
            '${unset == 1 ? 'One source still needs' : '$unset sources still need'}'
            ' an answer. Until then ${unset == 1 ? 'it is treated' : 'they are treated'}'
            ' as notes — nothing is held back.',
            top: 0,
            bottom: 8,
          ),
        KitRowList(rows: [
          for (final id in ids)
            () {
              final d = widget.docs.where((x) => x.id == id).firstOrNull;
              final kind = p.storedKindFor(id);
              final pos = p.positionFor(id);
              final held = _busy == id;
              return KitFormRow(
                kind: d == null ? null : kitDocKind(d.type),
                title: d?.title ?? 'Untitled',
                plain: true,
                wrap: true,
                subtitle: kind == 'reading'
                    ? (pos == null
                        ? 'A reading — no position set yet, so none of it is '
                            'served'
                        : 'A reading — served through passage ${pos + 1}')
                    : kind == 'notes'
                        ? 'Your notes — always available'
                        : 'Not answered yet',
                trailing: [
                  KitChoiceChip('My notes',
                      on: kind == 'notes',
                      onPressed:
                          held ? null : () => _write(id, {'kind': 'notes'})),
                  KitChoiceChip('A reading',
                      on: kind == 'reading',
                      onPressed:
                          held ? null : () => _write(id, {'kind': 'reading'})),
                  if (kind == 'reading')
                    SizedBox(
                      width: 130,
                      child: KitTextField(
                        controller: _positionCtrl(id),
                        placeholder: 'Read through…',
                        keyboardType: TextInputType.number,
                        face: KitFieldFace.ui,
                        sunken: true,
                        enabled: !held,
                        onChanged: (v) {
                          final n = int.tryParse(v.trim());
                          _write(id, {
                            'position': v.trim().isEmpty
                                ? null
                                : (n == null ? null : (n - 1).clamp(0, 1 << 30)),
                          });
                        },
                      ),
                    ),
                ],
              );
            }(),
        ]),
      ],
    );
  }
}

/// Where the reader is (3.0.0, ADR-038 §6/§7; web `UnitPanel`).
///
/// **A unit is the content between examinations, and the reader moves the
/// pointer.** "Start a new unit" works with or without a syllabus. A passed
/// exam date may RAISE a suggestion here and may never act on its own — dates
/// drift, and the reader is the only one who knows where the class actually
/// is. The confirm step is the unit form below, which states what will happen
/// (`confirm_required.json`: not a §18 panel) — it was a §18 dialog here.
class UnitPanel extends StatefulWidget {
  const UnitPanel(
      {super.key, required this.program, required this.docs});
  final StudyProgram program;
  final List<Document> docs;

  @override
  State<UnitPanel> createState() => _UnitPanelState();
}

class _UnitPanelState extends State<UnitPanel> {
  bool _busy = false;
  bool _asking = false;
  String? _error;
  final Map<String, TextEditingController> _positions = {};

  @override
  void dispose() {
    for (final c in _positions.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// A suggestion, never a state change. Only an `exam` qualifies: the reader
  /// does not move past material by submitting an essay on it.
  Map<String, dynamic>? _suggestion() {
    final p = widget.program;
    final syl = p.syllabus;
    if (syl == null) return null;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final dismissed = p.dismissedPrompts.toSet();
    final started = p.unitStartedAt;
    final passed = syl.assessments.where((a) {
      final on = a['on'] as String?;
      if (((a['assessment_kind'] as String?) ?? 'exam') != 'exam') return false;
      if (on == null || on.isEmpty || on.compareTo(today) >= 0) return false;
      if (dismissed.contains('$on|${a['title']}')) return false;
      if (started == null) return true;
      final at = DateTime.tryParse(on);
      return at != null && at.millisecondsSinceEpoch > started;
    }).toList()
      ..sort((a, b) => (b['on'] as String).compareTo(a['on'] as String));
    return passed.isEmpty ? null : passed.first;
  }

  Future<void> _advance() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final clean = <String, dynamic>{};
      _positions.forEach((id, c) {
        final n = int.tryParse(c.text.trim());
        if (n != null) clean[id] = (n - 1).clamp(0, 1 << 30);
      });
      await Api.instance.advanceStudyUnit(widget.program.id, positions: clean);
      if (!mounted) return;
      setState(() {
        _asking = false;
        for (final c in _positions.values) {
          c.clear();
        }
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      // Not idempotent: a reader who cannot tell a refusal from a timeout must
      // not be left to guess and press it again.
      if (mounted) {
        setState(() =>
            _error = 'The unit could not be started. Nothing has changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _dismiss(Map<String, dynamic> s) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Api.instance.updateStudyProgram(widget.program.id, {
        'dismissedPrompts': [
          ...widget.program.dismissedPrompts,
          '${s['on']}|${s['title']}',
        ],
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'That could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final readings =
        p.documentIds.where((id) => p.storedKindFor(id) == 'reading').toList();
    final unitNo = p.unitNumber;
    final suggestion = _suggestion();
    return KitFormSection(
      eyebrow: 'Where you are',
      count: 'Unit $unitNo',
      lede: 'A unit is the stretch of material between one test and the next. '
          'When you’ve had a test, start a new unit — sessions then treat '
          'what came before as covered and bring in what’s next. Nothing here '
          'happens on its own.',
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(_error!),
          ),
        if (suggestion != null && !_asking)
          KitRowList(rows: [
            KitFormRow(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KitFormLede(
                    '${suggestion['title']} was on ${suggestion['on']}. If '
                    'you’ve sat it, starting a new unit moves the program '
                    'past that material.',
                    tight: true,
                  ),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    KitButton.primary('Start a new unit',
                        onPressed:
                            _busy ? null : () => setState(() => _asking = true)),
                    KitButton.ghost('Not yet',
                        onPressed: _busy ? null : () => _dismiss(suggestion)),
                  ]),
                ],
              ),
            ),
          ]),
        if (!_asking)
          KitFormFoot(
            bare: true,
            top: suggestion != null ? 12 : 0,
            leading: [
              KitButton.ghost('Start a new unit',
                  onPressed:
                      _busy ? null : () => setState(() => _asking = true)),
            ],
          ),
        if (_asking)
          KitRowList(rows: [
            KitFormRow(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KitFormLede(
                    'Everything available now becomes covered material, and '
                    'unit ${unitNo + 1} starts from here. Nothing is deleted '
                    'and nothing you’ve already learned is rescheduled — '
                    'passages you’ve graded keep coming back exactly as they '
                    'would have.',
                    tight: true,
                  ),
                  if (readings.isNotEmpty) ...[
                    const KitFineNote(
                      'How far have you got in each reading? This is the one '
                      'thing the program can’t work out for itself.',
                      top: 0,
                      bottom: 6,
                    ),
                    for (final id in readings)
                      KitFormRow(
                        title: widget.docs
                                .where((d) => d.id == id)
                                .firstOrNull
                                ?.title ??
                            'Untitled',
                        plain: true,
                        subtitle: p.positionFor(id) == null
                            ? 'No position set'
                            : 'Currently through passage '
                                '${p.positionFor(id)! + 1}',
                        trailing: [
                          SizedBox(
                            width: 150,
                            child: KitTextField(
                              controller: _positions.putIfAbsent(
                                  id, () => TextEditingController()),
                              placeholder: 'Read through…',
                              keyboardType: TextInputType.number,
                              face: KitFieldFace.ui,
                              sunken: true,
                            ),
                          ),
                        ],
                      ),
                  ],
                  KitFormFoot(
                    bare: true,
                    top: 8,
                    leading: [
                      KitButton.primary(
                          _busy ? 'Starting…' : 'Start unit ${unitNo + 1}',
                          onPressed: _busy ? null : _advance),
                      KitButton.ghost('Cancel',
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _asking = false;
                                    for (final c in _positions.values) {
                                      c.clear();
                                    }
                                  })),
                    ],
                  ),
                ],
              ),
            ),
          ]),
      ],
    );
  }
}

/// The syllabus (2.36.0 ADR-035; reshaped 3.0.0 ADR-038; web `SyllabusPanel`).
///
/// Parsed once from an ordinary ingested document, **reviewed**, then applied.
/// It supplies display topics and assessment prompts only — **it paces
/// nothing** (INV-19). The read runs in the background (4.103.0, ADR-136) and
/// its plan waits in For your review.
class _SyllabusPanel extends StatefulWidget {
  const _SyllabusPanel({required this.program, required this.docs});
  final StudyProgram program;
  final List<Document> docs;

  @override
  State<_SyllabusPanel> createState() => _SyllabusPanelState();
}

class _SyllabusPanelState extends State<_SyllabusPanel> {
  /// 'suggest' | 'detach'
  String? _busy;
  String? _error;
  String? _docId;
  bool _attaching = false;
  bool _requested = false;

  Future<void> _suggest() async {
    final docId = _docId;
    if (docId == null) return;
    setState(() {
      _busy = 'suggest';
      _error = null;
    });
    try {
      await Api.instance.requestTask('syllabus_plan',
          {'programId': widget.program.id, 'documentId': docId});
      if (!mounted) return;
      setState(() {
        _requested = true;
        _attaching = false;
        _docId = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'That syllabus could not be read. Nothing was changed.');
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _detach() async {
    setState(() {
      _busy = 'detach';
      _error = null;
    });
    try {
      await Api.instance.detachSyllabusPlan(widget.program.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not detach the syllabus.');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.program;
    final syl = p.syllabus;
    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    // Any COMPLETE document that is not itself part of the curriculum.
    final candidates =
        widget.docs.where((d) => !p.documentIds.contains(d.id)).toList();
    return KitFormSection(
      eyebrow: 'Syllabus',
      count: syl == null
          ? null
          : '${_counted(syl.units.length, 'topic')} · '
              '${_counted(syl.assessments.length, 'assessment')}',
      lede: 'A syllabus is optional, and it never paces anything: dates on a '
          'syllabus drift, and only you know where the class actually is. '
          'What it gives this program is the course’s own list of topics, '
          'and a reminder after a test has passed — which you accept or '
          'ignore.',
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KitFailureInline(_error!),
          ),
        if (_requested)
          const KitFineNote(
            'The syllabus is being read — its plan will wait for you in For '
            'your review. Nothing changes here until you apply it there.',
            top: 0,
            bottom: 14,
          ),
        if (syl != null) ...[
          KitRowList(rows: [
            for (var i = 0; i < syl.units.length; i++)
              KitFormRow(
                number: '${i + 1}',
                title: (syl.units[i]['topic'] as String?) ?? '',
                plain: true,
                subtitle: (syl.units[i]['starts_on'] as String?)?.isNotEmpty ==
                        true
                    ? 'From ${syl.units[i]['starts_on']}'
                    : 'No date',
              ),
            for (final e in syl.assessments)
              () {
                final kind = (e['assessment_kind'] as String?) ?? 'exam';
                final on = (e['on'] as String?) ?? '';
                return KitFormRow(
                  number: '✳',
                  title: (e['title'] as String?) ?? '',
                  plain: true,
                  subtitle: '$on · '
                      '${kind == 'paper' ? 'a paper — no effect on units' : e['cumulative'] == true ? 'an exam, covering everything so far' : 'an exam'}'
                      '${on.isNotEmpty && on.compareTo(today) < 0 && kind == 'exam' ? ' · already passed' : ''}',
                );
              }(),
          ]),
          KitFormFoot(
            bare: true,
            top: 14,
            leading: [
              KitButton.ghost('Replace',
                  onPressed: () => setState(() => _attaching = true)),
              KitButton.ghost(_busy == 'detach' ? 'Detaching…' : 'Detach',
                  onPressed: _busy != null ? null : _detach),
            ],
          ),
          const KitFineNote(
              'Detaching removes the topic list and the after-a-test '
              'reminders. It changes nothing about what sessions serve you — '
              'that follows the unit you’re in, not the syllabus.'),
        ],
        if (syl == null || _attaching)
          Padding(
            padding: EdgeInsets.only(top: syl == null ? 0 : 14),
            child: KitRowList(rows: [
              KitFormRow(
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const KitFormLede(
                      'Pick the syllabus itself — upload it like any document '
                      'first if it isn’t in your library yet. A program '
                      'source can’t be its own syllabus.',
                      tight: true,
                    ),
                    KitSelect<String?>(
                      value: _docId,
                      options: [null, ...candidates.map((d) => d.id)],
                      label: (id) => id == null
                          ? 'Choose a document…'
                          : (candidates
                                  .where((d) => d.id == id)
                                  .firstOrNull
                                  ?.title ??
                              'Untitled'),
                      face: KitFieldFace.ui,
                      sunken: true,
                      onChanged: (id) => setState(() => _docId = id),
                    ),
                    KitFormFoot(
                      bare: true,
                      top: 10,
                      leading: [
                        KitButton.primary(
                          _busy == 'suggest' ? 'Reading it…' : 'Read the syllabus',
                          onPressed: (_docId == null || _busy != null)
                              ? null
                              : _suggest,
                        ),
                        if (_attaching)
                          KitButton.ghost('Cancel',
                              onPressed: () =>
                                  setState(() => _attaching = false)),
                      ],
                    ),
                  ],
                ),
              ),
            ]),
          ),
      ],
    );
  }
}
