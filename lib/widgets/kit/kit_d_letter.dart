// Component kit §28 — LetterQuick, the letter's own settings in the settings
// panel of Home and Letters (web `src/kit/d/LetterQuick.jsx`), and the stored
// letter read for the D surfaces that quote it (web `src/kit/d/letter.js`).
// F-141 builds both here, as their first consumer (Home).

import 'dart:math' as math;

import 'package:flutter/material.dart'
    show InputBorder, InputDecoration, TextField, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/newsletter.dart';
import '../../models/newsletter_settings.dart';
import '../../models/study.dart';
import '../../state/activation_message.dart';
import '../../state/schedule.dart' show deviceTimezone;
import '../../theme/app_radius.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart' show KitSwitch;
import 'kit_d_format.dart';
import 'kit_d_parts.dart';
import 'kit_failure.dart' show KitFailureInline;
import 'kit_d_home.dart' show KitDNone, KitHxLink;

// ── The stored letter, read without opening it ──────────────────────────────

/// A stored letter's volume, number and title (web `letterHead`).
class KitLetterHead {
  final String? vol;
  final String? no;
  final String title;
  const KitLetterHead({this.vol, this.no, required this.title});
}

/// The folio is one line: `Vol. I · No. 253 · …`. `No.` is read only where it
/// follows the volume, so a passage that happens to say "No. 5" is never taken
/// for the letter's number.
final RegExp _folio = RegExp(r'Vol\. ([IVXLC]+)(?:\s*·\s*No\. (\d+))?');

/// `{vol, no, title}` (web `letterHead`). Vol and No come from the folio in
/// `text_body`, each dropped when absent — the backend drops `No.` rather than
/// guess it. The title is the subject after *Your NoteLetter — *, else *Your
/// letter*.
KitLetterHead kitLetterHead(Newsletter? letter) {
  final f = _folio.firstMatch(letter?.textBody ?? '');
  final parts = (letter?.subject ?? '').split(' — ');
  final rest = parts.length > 1 ? parts.sublist(1).join(' — ') : '';
  return KitLetterHead(
    vol: f?.group(1),
    no: f?.group(2),
    title: rest.isEmpty ? 'Your letter' : rest,
  );
}

/// One passage of a letterheaded letter, as Home's card quotes it.
class KitLetterSection {
  /// 1-based, the passage's place in the letter.
  final int n;
  final String title;

  /// An excerpt of at most about 280 characters, cut at a word.
  final String text;

  /// The source's title, from the card's *Read “…” in context →* link.
  final String? source;
  final String? docId;

  const KitLetterSection({
    required this.n,
    required this.title,
    required this.text,
    this.source,
    this.docId,
  });
}

const int _excerpt = 280;

/// At most about 280 characters, cut at a word, trailing punctuation dropped,
/// an ellipsis after (web `excerpt`).
String kitLetterExcerpt(String? s) {
  final t = (s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= _excerpt) return t;
  final cut = t.substring(0, _excerpt);
  final end = math.max(cut.lastIndexOf(' '), _excerpt - 40);
  return '${cut.substring(0, end).replaceAll(RegExp(r'[,;:.\s]+$'), '')}…';
}

final RegExp _readerHref = RegExp(r'/reader/([^/?#]+)');
final RegExp _inContext = RegExp(r'Read “(.+)” in context');

/// The passages of a letterheaded letter (web `letterSections`). Each passage
/// card in `html_body` is an `<h2>` (its title), the passage block after it,
/// and the *Read “…” in context →* link back to the reader (INV-21) — the only
/// places a passage's source and document id are written. Our own server
/// render, parsed INERT: `package:html` builds a tree and runs nothing, loads
/// nothing, and only TEXT leaves this function. A letter written before the
/// letterhead has no such cards and yields no passages.
List<KitLetterSection> kitLetterSections(Newsletter? letter) {
  final html = letter?.htmlBody ?? '';
  if (!html.contains('data-nl-letterhead')) return const [];
  final doc = html_parser.parse(html);
  final out = <KitLetterSection>[];
  final heads = doc.querySelectorAll('h2');
  for (var i = 0; i < heads.length; i++) {
    final h = heads[i];
    final title = h.text.trim();
    // Web maps first and filters after, so `n` keeps the passage's place.
    if (title.isEmpty) continue;
    final card = h.parent;
    final body = h.nextElementSibling;
    dom.Element? link;
    if (card != null) {
      for (final a in card.querySelectorAll('a[href]')) {
        if ((a.attributes['href'] ?? '').contains('/reader/')) {
          link = a;
          break;
        }
      }
    }
    final m = link == null
        ? null
        : _readerHref.firstMatch(link.attributes['href'] ?? '');
    final src = link == null ? null : _inContext.firstMatch(link.text);
    String? docId;
    if (m != null) {
      try {
        docId = Uri.decodeComponent(m.group(1)!);
      } catch (_) {
        docId = null;
      }
    }
    out.add(
      KitLetterSection(
        n: i + 1,
        title: title,
        text: kitLetterExcerpt(body?.text),
        source: src?.group(1),
        docId: docId,
      ),
    );
  }
  return out;
}

/// Everything Home's letter card draws (web `letterParts`).
class KitLetterParts {
  final String? vol;
  final String? no;
  final String title;
  final List<KitLetterSection> sections;
  final String lede;

  /// `chunk_ids.length`, or null when the record carries none — unmeasured,
  /// never 0 (ADR-109).
  final int? count;

  /// `generated_at`.
  final int? at;

  const KitLetterParts({
    this.vol,
    this.no,
    required this.title,
    required this.sections,
    required this.lede,
    this.count,
    this.at,
  });
}

/// Web `letterParts`; null for no letter.
KitLetterParts? kitLetterParts(Newsletter? letter) {
  if (letter == null) return null;
  final h = kitLetterHead(letter);
  return KitLetterParts(
    vol: h.vol,
    no: h.no,
    title: h.title,
    sections: kitLetterSections(letter),
    lede: letter.ledeOf(240),
    count: letter.chunkIdsKnown ? letter.chunkIds.length : null,
    at: letter.generatedAt,
  );
}

/// The letter read, as Home holds it (web `{letter: undefined | null | record,
/// error}`): [answered] false is in flight; answered with no [letter] is an
/// ANSWER (none built yet); [error] is the only failure.
class KitLetterRead {
  final bool answered;
  final Newsletter? letter;
  final String? error;
  const KitLetterRead({this.answered = false, this.letter, this.error});
}

/// The letter's schedule as Home reads it (web `useLetterSchedule`). A failed
/// read is [KitLetterSchedule.failed]: every claim about the schedule is null,
/// so the next-letter line and the letter chips withdraw while the panel shows
/// the failure. Null (no instance) is a read still out.
class KitLetterSchedule {
  /// Delivery is ON (`enabled: true`); null when the read failed.
  final bool? on;

  /// *8:00 AM*, or null.
  final String? time;

  /// *Today, 8:00 AM* / *Tomorrow, 8:00 AM* / *Monday, 8:00 AM* while on.
  final String? next;

  const KitLetterSchedule({this.on, this.time, this.next});

  static const KitLetterSchedule failed = KitLetterSchedule();

  factory KitLetterSchedule.of(NewsletterSettings s, {DateTime? now}) {
    final on = s.enabled;
    return KitLetterSchedule(
      on: on,
      time: kitClock(s.deliveryTime),
      next: on
          ? kitNextAt(
              s.deliveryTime,
              frequency: s.frequency.isEmpty ? 'daily' : s.frequency,
              now: now,
            )
          : null,
    );
  }
}

/// The library's state, read once from the documents read (screens/library.md
/// §Composition): [loading] and [failed] are not states of the library at all
/// — they claim nothing (INV-24).
enum KitLibState { loading, failed, empty, reading, ready }

/// The standfirst's first sentence: what the letter is (web `letterSentence`).
/// With no letter yet it says only what the other reads support.
String? kitLetterSentence(
  KitLetterRead st,
  KitLetterParts? parts, {
  KitLibState libState = KitLibState.reading,
  KitLetterSchedule? sched,
  DateTime? now,
}) {
  if (st.error != null) return 'Your latest letter could not be read.';
  if (!st.answered) return null;
  if (parts == null) {
    if (libState == KitLibState.ready) return 'No letter has been built yet.';
    if (libState != KitLibState.reading) return null;
    if (sched != null && sched.on == false) {
      return 'Your library is being read.';
    }
    final next = sched?.next;
    if (next != null && !next.startsWith('Tomorrow')) {
      return 'Your library is being read. The next letter will draw from '
          'what’s indexed so far.';
    }
    return 'Your library is being read. Tomorrow’s letter will draw from '
        'what’s indexed so far.';
  }
  final n = parts.count;
  final what = n == null
      ? ''
      : ' — ${kitSay(n)} ${n == 1 ? 'passage' : 'passages'} from your library';
  return kitIsToday(parts.at, now)
      ? 'Today’s letter, “${parts.title},” is ready$what.'
      : 'Your latest letter, “${parts.title},” is from '
            '${kitLongDay(parts.at ?? 0)}$what.';
}

/// Questions waiting in Deep study (web `studyDue`).
class KitStudyDue {
  final int left;
  final String programTitle;
  const KitStudyDue(this.left, this.programTitle);
}

/// The newest session that was DELIVERED (`sent`, or `email_failed` — in-app
/// delivery is real delivery, INV-17) and its questions not yet graded. Null
/// when nothing waits.
KitStudyDue? kitStudyDue(StudySession? session) {
  if (session == null ||
      (session.status != 'sent' && session.status != 'email_failed')) {
    return null;
  }
  final total = session.items.fold<int>(0, (n, it) => n + it.questions.length);
  final left = math.max(0, total - session.responses.length);
  if (left <= 0) return null;
  return KitStudyDue(
    left,
    session.programTitle.isEmpty ? 'Deep study' : session.programTitle,
  );
}

/// The standfirst's second sentence: what is waiting (web `deskSentence`).
/// [review] is a MEASURED count or null — an unmeasured count says nothing
/// here; [atLimit]: the review read hit its limit, so the count is a floor.
String? kitDeskSentence({KitStudyDue? due, int? review, bool atLimit = false}) {
  final bits = <String>[];
  if (due != null) {
    bits.add(
      '${kitSay(due.left)} '
      '${due.left == 1 ? 'question waits' : 'questions wait'} in Deep study',
    );
  }
  if (review != null && review != 0) {
    bits.add(
      '${atLimit ? '${kitThousands(review)}+' : kitSay(review)} '
      '${review == 1 && !atLimit ? 'thing is' : 'things are'} set aside for '
      'your review',
    );
  }
  return bits.isEmpty ? null : '${kitCap(bits.join(', and '))}.';
}

// ── §28 LetterQuick ─────────────────────────────────────────────────────────

/// One LetterQuick write's outcome: the server's sentence on a refusal, or the
/// response body (whose `activationSend` says what turning delivery on did).
class KitLetterWrite {
  final String? error;
  final Map<String, dynamic>? response;
  const KitLetterWrite({this.error, this.response});
}

const List<(String, String)> _freq = [
  ('daily', 'Every day'),
  ('weekdays', 'Weekdays'),
  ('weekly', 'Weekly'),
];

/// What the BUILD uses for a schedule never stored (area_letter.py: frequency
/// `daily`, `itemsPerNewsletter` 5) — the panel says what will happen, not a
/// guess. The hour is Letter settings' own default.
const String _defTime = '07:00';
const String _defFreq = 'daily';
const int _defItems = 5;

/// §28 — the letter's own settings: Scheduled delivery, Arrives at, How often,
/// Passages in each letter, and the way to every letter setting.
///
/// **Write before you move** (umbrella trap): every control awaits [write] and
/// moves only on success; a refusal is drawn under it (§14.2) and the control
/// stays where it was. Turning delivery on stores the zone with the hour
/// (`deliveryTime` alone is read as UTC) and says what the activation send
/// did, from the response (ADR-031) — and, before it is touched, what it will
/// do. The time field edits a DRAFT and commits on blur or Enter; a refused
/// write puts it back to what the last READ stored.
///
/// [settings] is the stored document (null while the read is out),
/// [readError] its refusal. The host owns the request ([write] — built in
/// `services/api.dart`) and the re-read that follows it.
class KitLetterQuick extends StatefulWidget {
  final NewsletterSettings? settings;
  final String? readError;
  final Future<KitLetterWrite> Function(Map<String, dynamic> patch) write;
  final VoidCallback onEverySetting;

  const KitLetterQuick({
    super.key,
    required this.settings,
    required this.write,
    required this.onEverySetting,
    this.readError,
  });

  @override
  State<KitLetterQuick> createState() => _KitLetterQuickState();
}

class _KitLetterQuickState extends State<KitLetterQuick> {
  bool _busy = false;
  String? _err;
  String? _said;

  /// What this panel wrote and the server accepted, over the last read —
  /// web's `setS({...cur, ...patch})`. A new read replaces it.
  Map<String, dynamic> _over = const {};
  final TextEditingController _time = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _time.text = _timeValue;
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(KitLetterQuick old) {
    super.didUpdateWidget(old);
    if (!identical(old.settings, widget.settings)) {
      _over = const {};
      if (!_editing) _time.text = _timeValue;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _time.dispose();
    super.dispose();
  }

  NewsletterSettings get _s => widget.settings ?? const NewsletterSettings();

  bool get _enabled => (_over['enabled'] as bool?) ?? _s.enabled;

  String get _timeValue {
    final v = (_over['deliveryTime'] as String?) ?? _s.deliveryTime;
    return v.isEmpty ? _defTime : v;
  }

  String get _frequency {
    final v = (_over['frequency'] as String?) ?? _s.frequency;
    return v.isEmpty ? _defFreq : v;
  }

  int get _items {
    final v = (_over['itemsPerNewsletter'] as int?) ?? _s.itemsPerNewsletter;
    return v == 0 ? _defItems : v;
  }

  String get _tz {
    final v = (_over['timezone'] as String?) ?? _s.timezone;
    return v.isEmpty ? deviceTimezone() : v;
  }

  void _onFocus() {
    if (_focus.hasFocus) {
      _editing = true;
      return;
    }
    if (_editing) _commit();
  }

  /// `7:5`-shaped input is padded to the stored `HH:MM`; anything else is
  /// sent as typed, and the endpoint's refusal is what the reader sees.
  static String _normalise(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (m == null) return raw.trim();
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
  }

  void _commit() {
    _editing = false;
    final draft = _normalise(_time.text);
    if (draft.isNotEmpty && draft != _timeValue) {
      _put({'deliveryTime': draft, 'timezone': _tz});
    } else {
      setState(() => _time.text = _timeValue);
    }
  }

  Future<void> _put(Map<String, dynamic> patch) async {
    setState(() {
      _busy = true;
      _err = null;
      _said = null;
    });
    final r = await widget.write(patch);
    if (!mounted) return;
    setState(() {
      if (r.error != null) {
        _err = r.error;
      } else {
        _over = {..._over, ...patch};
        if (patch['enabled'] == true) _said = activationMessage(r.response);
      }
      _busy = false;
      // The field shows what is stored now: the write, or — refused — the
      // last read (memory: text-field revert).
      if (!_focus.hasFocus) _time.text = _timeValue;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    if (widget.settings == null) {
      return widget.readError != null
          ? Padding(
              padding: const EdgeInsets.only(top: 12),
              child: KitFailureInline(widget.readError!),
            )
          : Padding(
              padding: const EdgeInsets.only(top: 16),
              child: KitDNone('Reading your letter settings…'),
            );
    }
    final enabled = _enabled;
    final time = _timeValue;
    final freq = _freq
        .firstWhere((f) => f.$1 == _frequency, orElse: () => _freq[0])
        .$2;
    final note = AppTheme.serif(
      fontSize: 14,
      height: 21 / 14,
      fontStyle: FontStyle.italic,
      color: t.fgLede,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 2),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Scheduled delivery',
                      style: AppTheme.serif(
                        fontSize: 16,
                        height: 21 / 16,
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      enabled ? '$freq at ${kitClock(time) ?? time}' : 'Paused',
                      style: TextStyle(
                        fontFamily: AppTheme.fontSans,
                        fontSize: 13,
                        height: 18 / 13,
                        color: t.fgMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              KitSwitch(
                value: enabled,
                tooltip: 'Scheduled delivery',
                onChanged: _busy
                    ? null
                    : (_) => _put(
                        enabled
                            ? {'enabled': false}
                            : {
                                'enabled': true,
                                'deliveryTime': time,
                                'timezone': _tz,
                              },
                      ),
              ),
            ],
          ),
        ),
        if (!enabled && _said == null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(activationHint, style: note),
          ),
        if (_said != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_said!, style: note),
          ),
        const KitDLabel('Arrives at'),
        Row(
          children: [
            Container(
              width: 120,
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: t.surface,
                border: Border.all(color: t.borderStrong),
                borderRadius: AppRadius.controlR(40),
              ),
              child: Semantics(
                label: 'Delivery time',
                textField: true,
                child: TextField(
                  key: const ValueKey('d-lq-time'),
                  controller: _time,
                  focusNode: _focus,
                  readOnly: _busy,
                  keyboardType: TextInputType.datetime,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _focus.unfocus(),
                  cursorColor: t.accent,
                  style: AppTheme.mono(fontSize: 14, color: t.fg),
                  // The box is the field (`.d-lq-time input`): the theme's
                  // own input decoration draws nothing inside it.
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                _tz.replaceAll('_', ' '),
                style: AppTheme.mono(
                  fontSize: 11,
                  letterSpacing: 0.08 * 11,
                  color: t.fgSubtle,
                ),
              ),
            ),
          ],
        ),
        const KitDLabel('How often'),
        KitSlideSwitch<String>(
          label: 'How often',
          expand: true,
          held: _busy,
          value: _frequency,
          onChanged: (v) => _put({'frequency': v}),
          options: [for (final f in _freq) KitSlideOption(f.$1, f.$2)],
        ),
        const KitDLabel('Passages in each letter'),
        KitSlideSwitch<int>(
          label: 'Passages in each letter',
          expand: true,
          held: _busy,
          value: _items,
          onChanged: (v) => _put({'itemsPerNewsletter': v}),
          options: [
            for (final n in const [3, 5, 7]) KitSlideOption(n, '$n'),
          ],
        ),
        if (_err != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: KitFailureInline(_err!),
          ),
        Container(
          margin: const EdgeInsets.only(top: 22),
          padding: const EdgeInsets.only(top: 14),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.rule)),
          ),
          alignment: Alignment.centerLeft,
          child: KitHxLink(
            'Every letter setting →',
            onTap: widget.onEverySetting,
          ),
        ),
      ],
    );
  }
}
