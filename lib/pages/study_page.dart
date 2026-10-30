/// Study programs in direction D (`spec/screens/study.md` §Composition —
/// Study programs; web `pages/StudyView.jsx`).
///
/// The D frame (kit §26–§29): the masthead with the `Deep study · N programs ·
/// N on` folio and the page's one action, **New program**; the sheet *Deep
/// study* with the page's Contents and *Today* — Home's desk figure, the
/// newest session's ungraded questions — beside the column of Programs and
/// Sessions as ruled registers. On a phone the sheet runs as the running head
/// and New program is the tab bar's centre.
///
/// **Every figure here is a stored field.** Progress is `introduced_count` of
/// `unit_count` from the program document, the schedule sentence is rendered
/// from what was read, the runway is the runway the build measured — and there
/// is no forecast, retention percentage or streak, because no field carries
/// one. A figure whose read is out draws the ellipsis; one that was refused
/// draws the dash (ADR-109) — never a zero for a read that has not said so.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../models/study.dart';
import '../services/api.dart';
import '../services/api_service.dart';
import '../services/error_text.dart';
import '../services/firestore_service.dart';
import '../shared/cooldown.dart';
import '../state/study_schedule.dart';
import '../widgets/kit/kit.dart';

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

  /// Null until the first snapshot (INV-24: `[]` is "you have no programs
  /// yet", an OFFER; a refused read is no evidence for it).
  List<StudyProgram>? _programs;
  Object? _progErr;

  /// The sessions read is its own region: a history that could not be read
  /// says nothing about the programs above it (§14.1 takes exactly the region
  /// that failed), and it feeds Today.
  List<StudySession> _sessions = const [];
  bool _sessLoaded = false;
  Object? _sessErr;

  StreamSubscription<List<StudyProgram>>? _progSub;
  StreamSubscription<List<StudySession>>? _sessSub;
  final KitSections _sec = KitSections(['programs', 'sessions']);

  @override
  void initState() {
    super.initState();
    _progSub = FirestoreService.instance.subscribeStudyPrograms().listen(
      (rows) => setState(() {
        _progErr = null;
        _programs = rows;
      }),
      onError: (Object e) => setState(() => _progErr = e),
    );
    _sessSub = FirestoreService.instance
        .subscribeStudySessions(limit: 40)
        .listen(
          (rows) => setState(() {
            _sessLoaded = true;
            _sessErr = null;
            _sessions = rows;
          }),
          onError: (Object e) => setState(() {
            _sessLoaded = true;
            _sessErr = e;
          }),
        );
  }

  @override
  void dispose() {
    _progSub?.cancel();
    _sessSub?.cancel();
    _sec.dispose();
    super.dispose();
  }

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
      final res = await Api.instance.updateStudyProgram(p.id, {
        'enabled': !p.enabled,
      });
      if (!mounted) return;
      final n = p.introducedCount;
      setState(
        () => _notes[p.id] = p.enabled
            // Off is a PAUSE — the copy may not imply progress is lost.
            ? 'Off. Nothing further will arrive. The '
                  '${kitCounted(n, 'passage')} it has introduced '
                  '${n == 1 ? 'is' : 'are'} kept.'
            // 2.30.0 — the backend decides whether a session goes now; this
            // only reports what it decided.
            : (studyActivationMessage(res) ?? 'On.'),
      );
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
      // ADR-011: a session record ALWAYS appears — the Sessions register is
      // the subscription that reconciles this promise, so nothing is claimed
      // about a session that has not been written yet.
      setState(
        () => _notes[p.id] =
            'Session requested — it appears under Sessions in a moment, and by '
            'email if this program sends one.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      // A 429 is a COOLDOWN, not a failure: it reads as the system working.
      // The wait is the SERVER's to state — the endpoint names the exact
      // remaining seconds, and the constant below is a 60s guess that goes
      // stale invisibly the day the window moves. It survives only for a 429
      // that carried no sentence at all (C11).
      setState(() {
        if (e.statusCode == 429) {
          // With a number (4.107.0, ADR-140) the card's wait carries the
          // sentence and clears it at zero, so the note is emptied rather than
          // left to outlive it.
          if (e.retryAfterS != null) {
            _notes.remove(p.id);
          } else {
            _notes[p.id] = cooldownSentence(
              e,
              'Just a moment — a session for this program was '
              'requested less than a minute ago.',
            );
          }
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

  void _newProgram() => context.go('/study/new');

  @override
  Widget build(BuildContext context) {
    final programs = _programs;
    final loaded = programs != null;
    final list = programs ?? const <StudyProgram>[];
    final on = list.where((p) => p.enabled).length;

    // What waits today is Home's desk figure (kit `kitStudyDue`): the NEWEST
    // session's ungraded questions, so the two surfaces never disagree. Unread
    // until the sessions read answers; a refused read says nothing here (its
    // §14.1 block is in the column).
    final newest = _sessions.isEmpty ? null : _sessions.first;
    final due = _sessLoaded && _sessErr == null ? kitStudyDue(newest) : null;

    final secs = [
      KitContentsItem(
        'programs',
        'Programs',
        count: loaded && _progErr == null ? '${list.length}' : null,
      ),
      if (_sessErr != null || _sessions.isNotEmpty)
        KitContentsItem(
          'sessions',
          'Sessions',
          count: _sessErr != null ? null : '${_sessions.length}',
        ),
    ];
    final ids = [for (final s in secs) s.id];
    if (!listEquals(_sec.ids, ids)) _sec.ids = ids;

    final folioN = _progErr != null
        ? '— programs'
        : loaded
        ? kitCounted(list.length, 'program')
        : '…';
    final folio =
        'Deep study\u00a0· $folioN'
        '${loaded && _progErr == null && list.isNotEmpty ? '\u00a0· $on on' : ''}';

    final empty = _progErr == null && loaded && list.isEmpty;

    return KitDPage(
      folio: folio,
      title: 'Study Programs',
      stand:
          'A program turns your own documents into questions that come back '
          'on their own schedule. How you grade an answer decides when you '
          'see it next.',
      action: KitPageAction(
        label: 'New program',
        short: 'New program',
        icon: Icons.add,
        onPressed: _newProgram,
      ),
      sections: _sec,
      sheet: KitDSheet(
        label: 'Deep study',
        foldOnPick: true,
        peek: KitSecPeek(items: secs, sections: _sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(items: secs, sections: _sec),
            // Absent when the read was refused: never a sentence about what
            // a refused read did not say (INV-24).
            if (_sessErr == null)
              KitDeskLedger(
                label: 'Today',
                loading: !_sessLoaded,
                quiet: due == null,
                quietText: 'Nothing is waiting today.',
                rows: [
                  if (due != null && newest != null)
                    KitLedgerRow(
                      id: 'session',
                      n: '${due.left}',
                      line: due.left == 1
                          ? 'question waiting'
                          : 'questions waiting',
                      sub: newest.programTitle.isEmpty
                          ? 'Study session'
                          : newest.programTitle,
                      onTap: () => context.go('/study/session/${newest.id}'),
                    ),
                ],
              ),
          ],
        ),
      ),
      child: empty
          // INV-24: `[]` is "you have no programs yet", an OFFER. It stands
          // where the programs would, so the sheet's Programs row finds it.
          ? KeyedSubtree(key: _sec.keyOf('programs'), child: _empty())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KeyedSubtree(
                  key: _sec.keyOf('programs'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      KitSectionHead(
                        'Programs',
                        flushTop: true,
                        meta: loaded && _progErr == null
                            ? '${kitCounted(list.length, 'program')} · $on on'
                            : null,
                      ),
                      if (_progErr != null)
                        // §14.1 takes the region the list would have filled —
                        // never beside it, and never over an offer to create
                        // the first program.
                        KitFailureBlock(
                          sentence: 'Your study programs could not be read.',
                          detail: describeSdkError(_progErr!),
                        )
                      else if (!loaded)
                        const KitSkeletonLines(
                          lines: [
                            KitSkelLine(0.6, true),
                            KitSkelLine(),
                            KitSkelLine(0.7),
                            KitSkelLine(0.5, true),
                            KitSkelLine(),
                            KitSkelLine(0.6),
                          ],
                        )
                      else
                        KitRuledRegister(
                          children: [
                            for (final p in list)
                              _ProgramCard(
                                key: ValueKey('program-${p.id}'),
                                program: p,
                                note: _notes[p.id],
                                error: _errors[p.id],
                                busy: _busy[p.id],
                                onToggle: () => _toggle(p),
                                onStudy: () => _studyNow(p),
                                onEdit: () => context.go('/study/${p.id}'),
                                onNew: _newProgram,
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (_sessErr != null || _sessions.isNotEmpty)
                  KeyedSubtree(
                    key: _sec.keyOf('sessions'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // `.dp-hist .hx-sh { margin-top: 72px }`.
                        const SizedBox(height: 72),
                        KitSectionHead(
                          'Sessions',
                          flushTop: true,
                          meta: _sessErr != null
                              ? null
                              : kitCounted(_sessions.length, 'session'),
                        ),
                        if (_sessErr != null)
                          KitFailureBlock(
                            sentence: 'Your recent sessions could not be read.',
                            detail: describeSdkError(_sessErr!),
                          )
                        else
                          KitRuledRegister(
                            children: [
                              for (final s in _sessions) _sessionRow(s),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  /// §37 in D — **an offer, not an apology.** The three moves say what a
  /// program is for, as a ruled list; the action row is what makes one. The
  /// masthead and the sheet stay.
  Widget _empty() => KitEmptyState(
    // `IcoCards`, the reference's study glyph (F-90 (2)).
    icon: KitCardsGlyph.icon,
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
      KitButton('New program', icon: Icons.add, onPressed: _newProgram),
    ],
  );

  /// One past session. Rendered from `program_title`, because a deleted
  /// program's sessions still list and that is normal, not an error.
  Widget _sessionRow(StudySession s) {
    final questions = s.items.fold<int>(0, (n, it) => n + it.questions.length);
    final answered = s.responses.length;
    final at = s.generatedAt;
    return KitStudyHistoryRow(
      key: ValueKey('session-${s.id}'),
      date: at == null ? '' : kitShortDay(at),
      time: at == null ? '' : kitClockTime(at),
      title: s.programTitle.isEmpty ? 'Study session' : s.programTitle,
      parts: questions > 0
          ? [
              '${s.newCount} new · ${s.reviewCount} '
                  '${s.reviewCount == 1 ? 'review' : 'reviews'}',
              '$answered of $questions answered',
            ]
          : const ['No questions'],
      chip: _sessionChip(s),
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

/// One program in the register: [KitProgramCard], whose D form is the ruled
/// entry (`.dp-study .st-prog`).
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
    super.key,
    required this.program,
    required this.note,
    required this.error,
    required this.busy,
    required this.onToggle,
    required this.onStudy,
    required this.onEdit,
    required this.onNew,
  });

  /// The program's own cooldown (4.107.0, ADR-140): Study now is held for the
  /// wait a refusal carried and counts it down, and the server's sentence is
  /// the note while it runs. Other programs' controls are untouched — the
  /// cooldown is per program.
  @override
  Widget build(BuildContext context) =>
      KitWait(waitKey: WaitKey.studySession(program.id), builder: _card);

  Widget _card(BuildContext context, CooldownWait wait) {
    final p = program;
    final on = p.enabled;
    final low = runwayNotice(p);
    return KitProgramCard(
      title: p.title,
      status: p.status,
      statusLabel: studyStatusLabel(p.status),
      introduced: p.introducedCount,
      units: p.unitCount,
      schedule: '${on ? '' : 'Was: '}${programScheduleSentence(p)}',
      on: on,
      offNote:
          'Off is a pause — the schedule and everything it has '
          'introduced are kept, and “Study now” still works.',
      switchLabel: busy == 'toggle' ? '…' : (on ? 'ON' : 'OFF'),
      switchControl: KitSwitch(
        value: on,
        tooltip: on ? 'Pause this program' : studyActivationHint,
        onChanged: busy != null ? null : (_) => onToggle(),
      ),
      actions: [
        KitButton(
          busy == 'study' ? 'Requesting…' : 'Study now',
          wait: busy == 'study' ? 0 : wait.left,
          onPressed: busy != null ? null : onStudy,
        ),
        KitButton(
          'Settings',
          icon: Icons.tune,
          variant: KitButtonVariant.ghost,
          onPressed: onEdit,
        ),
      ],
      // §12 — measured, not dismissible, the action the one
      // `low_material_reason` names; the glyph is the pattern's own.
      notice: low == null
          ? null
          : KitNotice(
              text: low.text,
              actionLabel: low.cta,
              onAction: low.action == 'new' ? onNew : onEdit,
            ),
      // Web's `shown`: the failure (§14.2), else the cooldown's sentence as
      // the kit's calm caption (§6.1, 4.108.0), else the program's own note,
      // else — off — what turning it on does, said BEFORE the switch is
      // touched (ADR-031).
      hint: error != null
          ? KitFailureInline(error!)
          : wait.sentence != null
          ? KitWaitNote(wait.sentence!)
          : null,
      hintText: note ?? (on ? null : studyActivationHint),
    );
  }
}
