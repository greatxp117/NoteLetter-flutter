/// The study session player (contract 2.34.0 ADR-033; 2.37.2; 3.1.0 ADR-039),
/// in direction D (`spec/screens/study.md` §Composition — A session; web
/// `pages/study/SessionPlayer.jsx`).
///
/// This is where the session email's CTA lands. It subscribes to the ONE
/// session document while `fn_submit_study_answer` writes into it, which is
/// what makes a session resumable: close the app mid-session, come back, and
/// the grades already given are there.
///
/// Every state opens on the masthead with its way back in the crumb. The
/// session itself: its questions in the column; on the sheet *This session*
/// its figures (*Answered* with its meter), its questions numbered `1…n` —
/// the marked one is the question to answer NEXT — and the keys. On a phone
/// the running head reads `№ n · source · a of N` over a 2px rule measured by
/// the answered fraction, never by the scroll.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:go_router/go_router.dart';

import '../../models/study.dart';
import '../../services/analytics.dart';
import '../../services/api.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../../shared/extraction_markers.dart';
import '../../state/study_schedule.dart';
import '../../theme/app_theme.dart';
import '../../widgets/kit/kit.dart';

/// The four grades in SM-2 order, with the key that gives each (web `GRADES`).
const _grades = [
  ('again', 'Again', '1'),
  ('hard', 'Hard', '2'),
  ('good', 'Good', '3'),
  ('easy', 'Easy', '4'),
];

String _gradeLabel(String? id) {
  for (final g in _grades) {
    if (g.$1 == id) return g.$2;
  }
  // Open vocabulary: a grade this build does not know is still the grade.
  return id ?? '';
}

/// What the SERVER said about one graded question — the return date comes
/// from `item.due_at` in the response and is never computed here.
typedef _Extra = ({String? back, bool alreadyGraded, bool itemRetired});

/// One question in the order the reader answers them.
typedef _Entry = ({StudySessionItem item, Map<String, dynamic> q, String qid});

class SessionPlayerPage extends StatefulWidget {
  const SessionPlayerPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  State<SessionPlayerPage> createState() => _SessionPlayerPageState();
}

class _SessionPlayerPageState extends State<SessionPlayerPage> {
  StreamSubscription<StudySession?>? _sub;
  StudySession? _session;
  bool _answered = false;
  Object? _subErr;

  final Set<String> _revealed = {};
  final Set<String> _disclosed = {};
  final Map<String, _Extra> _extras = {};
  final Map<String, String> _gradeErr = {};

  /// The grade being written: every grade is held until it confirms
  /// (non-optimistic — this screen's whole value is that the schedule is
  /// real).
  ({String qid, String grade})? _busy;

  /// Excerpts shown this session, flushed in ONE batch per document (INV-03b:
  /// never a write per excerpt) every 15 s and on leaving. `_seen` makes it
  /// once per passage per session.
  final Set<String> _seen = {};
  final List<(String, String)> _pending = [];
  Timer? _flushTimer;

  /// `study_session_started` is emitted once, when the session document first
  /// arrives — not on every snapshot (the subscription re-delivers on every
  /// grade), and not on mount, because until the document is there the
  /// session may not exist at all.
  bool _announced = false;

  /// The questions as sections of the page's scroller: a sheet row jumps the
  /// column to its question, 24 under the top (kit §29's Contents jump).
  final KitSections _qs = KitSections(const []);
  final FocusNode _keys = FocusNode(debugLabel: 'session-keys');

  @override
  void initState() {
    super.initState();
    _subscribe();
    _flushTimer = Timer.periodic(const Duration(seconds: 15), (_) => _flush());
  }

  void _subscribe() {
    _sub?.cancel();
    _sub = FirestoreService.instance
        .subscribeStudySession(widget.sessionId)
        .listen(
          (s) {
            if (s != null && !_announced) {
              _announced = true;
              Analytics.track('study_session_started');
            }
            setState(() {
              _answered = true;
              _subErr = null;
              _session = s;
            });
          },
          // A dropped subscription is a CONNECTION problem, not a wrong
          // account (2.37.2).
          onError: (Object e) => setState(() {
            _answered = true;
            _subErr = e;
            _session = null;
          }),
        );
  }

  /// Reload: the subscription again, from the top.
  void _reload() {
    setState(() {
      _answered = false;
      _subErr = null;
    });
    _subscribe();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _flushTimer?.cancel();
    _flush();
    _qs.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _flush() {
    if (_pending.isEmpty) return;
    final byDoc = <String, List<String>>{};
    for (final (doc, chunk) in _pending) {
      (byDoc[doc] ??= []).add(chunk);
    }
    _pending.clear();
    byDoc.forEach((doc, ids) {
      // A study excerpt IS a read (ADR-039 §6): it reached the reader. It
      // moves no SM-2 state (INV-17) and never touches
      // last_included_in_newsletter.
      FirestoreService.instance.logChunksRead(doc, ids);
    });
  }

  /// An excerpt shown is a read — noted where it MOUNTS, which is what makes a
  /// review's excerpt count only once its disclosure is opened.
  void _noteShown(StudySessionItem item) {
    if (item.documentId.isEmpty || item.chunkId.isEmpty) return;
    if (!_seen.add(item.chunkId)) return;
    _pending.add((item.documentId, item.chunkId));
  }

  Future<void> _grade(String qid, String grade) async {
    final session = _session;
    if (session == null || _busy != null) return;
    setState(() {
      _busy = (qid: qid, grade: grade);
      _gradeErr.remove(qid);
    });
    try {
      final res = await Api.instance.submitStudyAnswer(session.id, qid, grade);
      // The grade, which is a closed set of four; never the question, the
      // answer or which document it came from (INV-25b).
      Analytics.track('study_answer_submitted', {'grade': grade});
      if (!mounted) return;
      final retired = res['itemRetired'] == true;
      final due = (res['item'] as Map?)?['due_at'];
      // Non-optimistic: the subscription delivers the recorded response; this
      // is only what the server SAID about it. `alreadyGraded` is recorded,
      // never an error (INV-17); `itemRetired` is information (INV-18).
      setState(
        () => _extras[qid] = (
          back: retired ? null : returnLabel(due is int ? due : null),
          alreadyGraded: res['alreadyGraded'] == true,
          itemRetired: retired,
        ),
      );
    } on ApiException catch (e) {
      // C6: a 404 (no longer in the session), a 409 (already recorded) and a
      // 401 (signed out) each want a different next move. The endpoint says
      // which; a constant said none of them.
      if (mounted) setState(() => _gradeErr[qid] = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _gradeErr[qid] =
              'The grade could not be saved — nothing was recorded.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _back() => context.go('/study');

  KitDBackControl get _crumb =>
      KitDBackControl('Study programs', onTap: _back);

  /// Every state but the session opens on the masthead too: one column, no
  /// sheet.
  Widget _frame(String title, String? stand, Widget child) => KitDPage(
    back: _crumb,
    // On a phone the crumb takes its own line and the folio wraps under it
    // (web `.dp-study .ed-rail { display: contents }`).
    crumbStacks: true,
    folio: 'Deep study\u00a0· Session',
    title: title,
    stand: stand,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    if (!_answered) {
      return _frame(
        'A Study Session',
        null,
        const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitDNone('Reading the session…'),
            KitSkeletonLines(
              lines: [KitSkelLine(0.7, true), KitSkelLine(), KitSkelLine(0.6)],
            ),
          ],
        ),
      );
    }
    // A subscription that failed is not a session that does not exist.
    // Telling a reader whose connection dropped that their session "may
    // belong to another account" is both wrong and unrecoverable-sounding.
    if (_subErr != null) {
      return _frame(
        'This Session Couldn’t Be Loaded',
        'The connection to your session dropped, so nothing here is up to '
            'date. Reload to try again — nothing you graded has been lost.',
        Align(
          alignment: Alignment.centerLeft,
          child: KitButton.primary('Reload', onPressed: _reload),
        ),
      );
    }
    final session = _session;
    if (session == null) {
      return _frame(
        'This Session Isn’t Here',
        'The link may be old, or the session may belong to another account. '
            'Your programs and history are on the study page.',
        Align(
          alignment: Alignment.centerLeft,
          child: KitButton.ghost(
            'Back to study programs',
            icon: Icons.chevron_left,
            onPressed: _back,
          ),
        ),
      );
    }
    return _player(context, session);
  }

  Widget _player(BuildContext context, StudySession s) {
    final flat = <_Entry>[
      for (final item in s.items)
        for (final q in item.questions)
          (item: item, q: q, qid: q['qid'] as String? ?? ''),
    ];
    final ids = [for (final e in flat) e.qid];
    if (!listEquals(_qs.ids, ids)) _qs.ids = ids;
    final responses = s.responses;
    bool graded(_Entry e) => responses[e.qid] != null;
    final answered = flat.where(graded).length;
    final ci = flat.indexWhere((e) => !graded(e));
    final current = ci >= 0 ? flat[ci] : null;
    // Gated on STATUS, never on item count: the build writes the full `items`
    // array under `generating` BEFORE the questions are drawn, so a reader
    // arriving from the email CTA inside that window would otherwise see a
    // gradable list whose every grade came back rejected (2.37.2).
    final gradable = s.gradable && flat.isNotEmpty;
    final fraction = flat.isEmpty ? 0.0 : answered / flat.length;
    final at = s.generatedAt;
    final ramp = s.rampCount;

    final sheet = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KitDLabel('This session', first: true),
        // Answered is one count over its own total — the only figure here
        // with a meter.
        KitFigures.ledger(
          top: 0,
          ledger: [
            KitFigureRow(
              'Answered',
              '$answered of ${flat.length}',
              meter: flat.isEmpty ? null : fraction,
            ),
            KitFigureRow('New', '${s.newCount}'),
            KitFigureRow('Reviews', '${s.reviewCount}'),
            if (ramp > 0) KitFigureRow('Exam prep', '$ramp'),
          ],
        ),
        if (gradable) ...[
          const KitDLabel('Questions'),
          KitStudyQuestions(
            items: [
              for (final e in flat)
                KitStudyQuestionItem(
                  e.item.title.isEmpty ? 'Untitled' : e.item.title,
                  grade: graded(e)
                      ? _gradeLabel(
                          (responses[e.qid] as Map?)?['grade'] as String?,
                        )
                      : null,
                ),
            ],
            marked: ci >= 0 ? ci : null,
            onJump: (i) => _qs.jump(flat[i].qid),
          ),
          const KitDLabel('Keys'),
          KitFigures(
            top: 0,
            rows: [
              ('Show the answer', 'Space'),
              for (final g in _grades) (g.$2, g.$3),
            ],
          ),
        ],
      ],
    );

    // `.dp-sess .d-main > :first-child { margin-top: 0 }`.
    var first = true;
    double top(double d) {
      if (!first) return d;
      first = false;
      return 0;
    }

    final column = <Widget>[
      if (s.status == 'email_failed')
        KitStudyQuiet(
          'The email didn’t send. The session itself is here, unchanged.',
          icon: Icons.mail_outline,
          top: top(20),
        ),
      if (ramp > 0)
        KitStudyQuiet(
          ' — $ramp extra ${ramp == 1 ? 'review' : 'reviews'} pulled forward '
          'ahead of a test. Grading them works exactly like any review.',
          lead: 'Exam prep',
          top: top(20),
        ),
      if (s.status == 'generating')
        KitStudyPanel(
          top: top(28),
          title: 'This session is still being made',
          paragraphs: const [
            'The questions are being drawn from your sources. It usually '
                'takes under a minute; this page updates on its own.',
          ],
          building: true,
          actions: [
            KitButton.ghost('Back to study programs', onPressed: _back),
          ],
        )
      else if (s.status == 'error')
        KitStudyPanel(
          top: top(28),
          eyebrow: 'Not made',
          eyebrowCritical: true,
          title: 'This session couldn’t be made',
          paragraphs: const [
            'Nothing was sent, and nothing was marked as reviewed.',
          ],
          actions: [
            KitButton.ghost('Back to study programs', onPressed: _back),
          ],
        )
      else if (s.status == 'empty')
        // ADR-011: not a failure.
        KitStudyPanel(
          top: top(28),
          title: 'You’re caught up',
          paragraphs: [
            s.errorMessage ??
                'Nothing new to introduce, and nothing due today.',
          ],
          actions: [
            KitButton.ghost('Back to study programs', onPressed: _back),
          ],
        )
      else if (!s.gradable)
        // An open vocabulary: a status this build does not know is
        // information, never a failure.
        KitStudyPanel(
          top: top(28),
          title: 'This session is not ready',
          paragraphs: const ['Check back shortly.'],
          actions: [
            KitButton.ghost('Back to study programs', onPressed: _back),
          ],
        ),
      if (gradable) ...[
        KitStudyAnswered(answered: answered, total: flat.length, top: top(18)),
        const SizedBox(height: 28),
        for (var i = 0; i < flat.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          KeyedSubtree(
            key: _qs.keyOf(flat[i].qid),
            child: _card(
              context,
              flat[i],
              i,
              flat.length,
              responses,
              current: identical(current, flat[i]),
            ),
          ),
        ],
        if (current == null)
          KitStudyPanel(
            title: 'That’s the session',
            paragraphs: [
              '$answered of ${kitCounted(flat.length, 'question')} answered '
                  '— ${s.newCount} new '
                  '${s.newCount == 1 ? 'passage' : 'passages'}, '
                  '${s.reviewCount} '
                  '${s.reviewCount == 1 ? 'review' : 'reviews'}.',
              if (s.dueRemaining > 0)
                '${s.dueRemaining} more '
                    '${s.dueRemaining == 1 ? 'was' : 'were'} due than the cap '
                    'allows. ${s.dueRemaining == 1 ? 'It comes' : 'They come'} '
                    'first in the next session.',
            ],
            actions: [
              KitButton.primary('Back to study programs', onPressed: _back),
            ],
          ),
      ],
    ];

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: (node, e) => _onKey(e, current),
      child: KitDPage(
        back: _crumb,
        crumbStacks: true,
        folio: at == null ? 'Session' : 'Session\u00a0· ${kitLongDay(at)}',
        title: s.programTitle.isEmpty ? 'Study session' : s.programTitle,
        stand: _stand(s),
        sections: _qs,
        sheet: KitDSheet(
          label: 'This session',
          foldOnPick: true,
          peek: KitLibPeek(
            mark: KitPeekMark(current != null ? '№ ${ci + 1}' : '§'),
            title: current != null
                ? (current.item.title.isEmpty
                      ? 'Question'
                      : current.item.title)
                : gradable
                ? 'That’s the session'
                : 'This session',
            count: '$answered',
            tail: ' of ${flat.length}',
          ),
          foot: KitPeekBar(fraction),
          body: sheet,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: column,
        ),
      ),
    );
  }

  /// The keys the sheet names: Space (or Enter) reveals the question to
  /// answer next; 1–4 grade it once revealed.
  KeyEventResult _onKey(KeyEvent e, _Entry? current) {
    if (e is! KeyDownEvent || current == null || _busy != null) {
      return KeyEventResult.ignored;
    }
    final qid = current.qid;
    final k = e.logicalKey;
    if ((k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.enter) &&
        !_revealed.contains(qid)) {
      setState(() => _revealed.add(qid));
      return KeyEventResult.handled;
    }
    if (_revealed.contains(qid)) {
      const digits = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ];
      final i = digits.indexOf(k);
      if (i >= 0) {
        _grade(qid, _grades[i].$1);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  /// The standfirst per status (open vocabulary — unknown says nothing
  /// alarming, and nothing at all).
  static String? _stand(StudySession s) => switch (s.status) {
    'empty' => 'Nothing was due — you’re caught up.',
    'error' =>
      'This session couldn’t be made, and nothing was marked as reviewed.',
    'generating' => 'Its questions are still being assembled.',
    'sent' || 'email_failed' =>
      '${s.newCount} new, ${s.reviewCount} for review.',
    _ => null,
  };

  Widget _excerptBody(BuildContext context, StudySessionItem item) => Html(
    // The chunk's own sanitized html (INV-10), annotated for §17: a marker
    // inside an excerpt is the extractor talking about the document, and
    // drawn in the body role it reads as the prompt's own copy (4.52.0,
    // ADR-089).
    data: markSanitizedHtml(item.excerptHtml),
    extensions: AppTheme.htmlExtensions,
    style: KitStudyExcerpt.htmlStyles(context),
  );

  Widget _card(
    BuildContext context,
    _Entry e,
    int i,
    int total,
    Map<String, dynamic> responses, {
    required bool current,
  }) {
    final item = e.item;
    final qid = e.qid;
    final response = responses[qid] as Map?;
    final done = response != null;
    final revealed = _revealed.contains(qid);
    final isNew = item.kind == 'new';
    final hasExcerpt = item.excerptHtml.isNotEmpty;
    final extra = _extras[qid];
    final busy = _busy;
    final err = _gradeErr[qid];

    // A new unit offers its excerpt beside the question before it is
    // answered; a review keeps it behind a disclosure — recall first is the
    // point. Either way, an excerpt drawn is a read.
    Widget? aside;
    if (isNew && !done && hasExcerpt) {
      _noteShown(item);
      aside = KitStudyExcerpt(
        aside: true,
        title: item.title.isEmpty ? 'your notes' : item.title,
        body: _excerptBody(context, item),
      );
    }
    Widget? excerpt;
    VoidCallback? onDisclose;
    if (!isNew && (revealed || done) && hasExcerpt) {
      if (_disclosed.contains(qid)) {
        _noteShown(item);
        excerpt = KitStudyExcerpt(
          title: item.title.isEmpty ? 'your notes' : item.title,
          body: _excerptBody(context, item),
        );
      } else {
        onDisclose = () => setState(() => _disclosed.add(qid));
      }
    }

    return KitStudyQuestionCard(
      // 2.36.0: a ramp item is an ordinary review the near exam pulled
      // forward.
      kind: item.ramp
          ? 'ramp'
          : isNew
          ? 'new'
          : 'review',
      source: item.title.isEmpty ? 'Untitled' : item.title,
      index: '${i + 1} / $total',
      question: e.q['question'] as String? ?? '',
      answer: e.q['answer'] as String? ?? '',
      revealed: revealed,
      done: done,
      current: current,
      grade: done ? _gradeLabel(response['grade'] as String?) : null,
      notes: [
        if (extra?.back != null) extra!.back!,
        if (extra?.alreadyGraded == true)
          'recorded — this passage was already graded this session',
        if (extra?.itemRetired == true)
          'recorded — this passage has since been edited away, so nothing '
              'was rescheduled',
      ],
      onReveal: () => setState(() => _revealed.add(qid)),
      saving: busy != null,
      grades: [
        for (final g in _grades)
          KitStudyGrade(
            g.$2,
            g.$3,
            busy: busy?.qid == qid && busy?.grade == g.$1,
            onTap: busy != null ? null : () => _grade(qid, g.$1),
          ),
      ],
      failure: err == null ? null : KitFailureInline(err),
      aside: aside,
      excerpt: excerpt,
      onDisclose: onDisclose,
    );
  }
}
