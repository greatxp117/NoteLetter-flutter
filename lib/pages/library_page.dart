import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/newsletter.dart';
import '../models/study.dart';
import '../services/api.dart';
import '../services/api_service.dart' show ApiException;
import '../services/error_text.dart';
import '../services/firestore_service.dart';
import '../shared/local_flags.dart';
import '../state/documents_notifier.dart';
import '../state/newsletter_notifier.dart';
import '../state/review_inbox.dart';
import '../state/settings_notifier.dart';
import '../state/tags_notifier.dart';
import '../widgets/kit/kit.dart';
import '../widgets/sidebar.dart' show shellAiOn;
import 'tags/shelf_sheet.dart' show showShelfSheet;
import 'tags/suggest_shelves.dart';

/// **Home** (route `/`, the rail's *Home*; `spec/screens/library.md`
/// §Composition, direction D). Web `pages/LibraryHome.jsx` — the prototype's
/// HomeHybrid.
///
/// The edition's masthead (§26) — folio `{date} · {N} sources · {N}
/// passages`, the greeting with its accent clause, a standfirst of the letter
/// sentence and the desk sentence — with *Add a source* as the page's one
/// action and *Letter settings* (§28 LetterQuick) as its settings. The sheet
/// (§29, *On this page*) is Contents over the desk ledger; on a phone it runs
/// as the running head (§30). The column: the setup checklist strip while
/// setup is unfinished, *Your first sources* in an empty library, the letter
/// as it is sent, Recently added beside Earlier letters, and the shelves
/// (§42). Ask your library is not on Home.
///
/// The library's state — empty / reading / ready — chooses the standfirst,
/// the letter's text, the Contents and the lower sections; `loading` and
/// `failed` are not states of the library and claim nothing: the folio's
/// figures draw the dash, the lists the skeleton or §14.2, and the page never
/// takes the empty state on a refused read (INV-24 — an empty list is not
/// evidence of an empty library).
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final KitSections _sec = KitSections(const ['letter', 'recent', 'shelves']);

  // Questions waiting in Deep study: the newest session (web `useStudyDue`).
  StreamSubscription<List<StudySession>>? _studySub;
  bool _studyLoaded = false;
  String? _studyError;
  StudySession? _studyNewest;

  // The letter's parts, parsed once per record (the body is read as text).
  Newsletter? _partsOf;
  KitLetterParts? _parts;

  @override
  void initState() {
    super.initState();
    LocalFlags.ensureLoaded();
    _openStudy();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DocumentsNotifier>().start();
      context.read<TagsNotifier>().start();
      context.read<NewsletterNotifier>().load();
      // The schedule (the next-letter line, the letter chips), the checklist's
      // letter step and LetterQuick all read the settings document.
      context.read<SettingsNotifier>().loadAll();
      // The shell's one inbox (INV-30); idempotent — the rail starts it too.
      context.read<ReviewInbox?>()?.start();
    });
  }

  void _openStudy() {
    try {
      _studySub = FirestoreService.instance
          .subscribeStudySessions(limit: 1)
          .listen(
            (rows) {
              if (!mounted) return;
              setState(() {
                _studyLoaded = true;
                _studyError = null;
                _studyNewest = rows.isEmpty ? null : rows.first;
              });
            },
            onError: (Object e) {
              if (!mounted) return;
              setState(() {
                _studyLoaded = true;
                _studyError = describeSdkError(e);
              });
            },
          );
    } catch (e) {
      // A read that could not even be opened is a refused read: no row, and
      // never the quiet sentence.
      _studyLoaded = true;
      _studyError = describeSdkError(e);
    }
  }

  @override
  void dispose() {
    _studySub?.cancel();
    _sec.dispose();
    super.dispose();
  }

  KitLetterParts? _partsFor(Newsletter? letter) {
    if (!identical(letter, _partsOf)) {
      _partsOf = letter;
      _parts = kitLetterParts(letter);
    }
    return _parts;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // The client-local flags the checklist and the List / Grid choice read.
    listenable: Listenable.merge([
      LocalFlags.onboardDismissed,
      LocalFlags.onboardExpanded,
      LocalFlags.onboardAsked,
      LocalFlags.sourceView,
    ]),
    builder: (context, _) => _home(context),
  );

  Widget _home(BuildContext context) {
    final docs = context.watch<DocumentsNotifier>();
    final tags = context.watch<TagsNotifier>();
    final letters = context.watch<NewsletterNotifier>();
    final settings = context.watch<SettingsNotifier>();
    final inbox = context.watch<ReviewInbox?>()?.view;
    final aiOn = shellAiOn(context);
    final router = GoRouter.maybeOf(context);
    void go(String to, {Object? extra}) => router?.go(to, extra: extra);
    final now = DateTime.now();

    // ── The library ─────────────────────────────────────────────────────────
    final documents = docs.documents;
    final loaded = !docs.loading && !tags.loading;
    final libError = docs.error ?? tags.error;
    final measured = loaded && libError == null;
    final model = kitShelfModel(tags.tags, documents);
    final incoming = documents
        .where(
          (d) =>
              d.status == DocumentStatus.processing ||
              d.status == DocumentStatus.queued,
        )
        .toList();
    final empty = measured && documents.isEmpty;
    final libState = libError != null
        ? KitLibState.failed
        : !loaded
        ? KitLibState.loading
        : empty
        ? KitLibState.empty
        : model.total > 0
        ? KitLibState.ready
        : KitLibState.reading;

    // ── The letter, its schedule, the desk ──────────────────────────────────
    // The newest BUILT daily letter (ADR-131/132). Not answered is in flight;
    // answered with none is an answer; only the error is a failure.
    final read = KitLetterRead(
      answered: letters.loaded,
      letter: letters.loaded ? letters.latest : null,
      error: letters.error,
    );
    final parts = _partsFor(read.letter);
    // Null until read; a refused read withdraws only the claims about the
    // schedule (the next-letter line, the letter chips) — the panel shows it.
    final stored = settings.newsletter;
    final sched = stored != null
        ? KitLetterSchedule.of(stored, now: now)
        : (settings.error != null ? KitLetterSchedule.failed : null);
    final letterOn = sched?.on == true;
    final due = _studyError != null ? null : kitStudyDue(_studyNewest);

    // Earlier letters: up to five SENT daily letters of the twelve newest,
    // excluding the one shown — `kind != 'scripture'`, never `== 'daily'`.
    // Absent on a failed read: the section claims nothing.
    final newest = [...letters.history, ...letters.readings]
      ..sort((a, b) => (b.generatedAt ?? 0).compareTo(a.generatedAt ?? 0));
    final past = letters.error != null
        ? const <Newsletter>[]
        : newest
              .take(12)
              .where(
                (l) =>
                    !l.isScripture &&
                    l.status == 'sent' &&
                    l.id != read.letter?.id,
              )
              .take(5)
              .toList();

    // The desk ledger: every row a measurement. The review count is the
    // shell's one inbox (INV-30); unmeasured, it draws the dash.
    final ledger = <KitLedgerRow>[
      if (due != null)
        KitLedgerRow(
          id: 'study',
          n: '${due.left}',
          line: due.left == 1 ? 'question waiting' : 'questions waiting',
          sub: 'Deep study · ${due.programTitle}',
          onTap: () => go('/study'),
        ),
      if (inbox != null && inbox.count != null && inbox.count != 0)
        KitLedgerRow(
          id: 'review',
          // `500+` at the read limit, never 500 (screens/review.md §Data).
          n: inbox.countText,
          line: 'set aside for your review',
          sub: kitReviewParts(
            sources: inbox.sources.length,
            holds: inbox.holds.length,
            suggestions: inbox.suggestions.length,
            proposals: inbox.proposals.length,
          ).join(' · '),
          onTap: () => go('/review'),
        )
      else if (inbox != null && inbox.loaded && inbox.count == null)
        KitLedgerRow(
          id: 'review',
          n: null,
          line: 'set aside for your review',
          sub: 'Could not be counted',
          onTap: () => go('/review'),
        ),
      if (incoming.isNotEmpty)
        KitLedgerRow(
          id: 'reading',
          n: '${incoming.length}',
          line: incoming.length == 1
              ? 'volume being read'
              : 'volumes being read',
          reading: incoming,
          onTap: () => go('/sources'),
        ),
    ];
    final quiet =
        ledger.isEmpty &&
        measured &&
        inbox?.count == 0 &&
        _studyLoaded &&
        _studyError == null;

    // ── The page's words ────────────────────────────────────────────────────
    final sources = measured ? kitThousands(model.total) : '—';
    final passages = measured ? kitThousands(model.passages) : '—';
    final folio =
        '${kitLongDay(now.millisecondsSinceEpoch)} · '
        '$sources ${measured && model.total == 1 ? 'source' : 'sources'} · '
        '$passages ${measured && model.passages == 1 ? 'passage' : 'passages'}';
    final standParts = [
      kitLetterSentence(
        read,
        parts,
        libState: libState,
        sched: sched,
        now: now,
      ),
      kitDeskSentence(
        due: due,
        review: inbox?.count,
        atLimit: inbox?.atLimit ?? false,
      ),
    ].whereType<String>().join(' ');
    final stand = empty
        ? 'Your library is empty for now. Bring in what you’ve read, and '
              'NoteLetter makes it searchable and starts writing you a daily '
              'letter from it.'
        : (standParts.isEmpty ? null : standParts);

    // The sheet leads with Home's contents — only the sections the page has.
    final secs = empty
        ? const [
            KitContentsItem('first', 'Your first sources'),
            KitContentsItem('letter', 'The letter'),
          ]
        : [
            const KitContentsItem('letter', 'The letter'),
            const KitContentsItem('recent', 'Recently added'),
            if (past.isNotEmpty)
              const KitContentsItem('earlier', 'Earlier letters'),
            const KitContentsItem('shelves', 'The shelves'),
          ];
    final ids = [for (final s in secs) s.id];
    if (!listEquals(_sec.ids, ids)) _sec.ids = ids;

    final view = LocalFlags.sourceView.value;
    final toggle = model.total > 0 ? const KitViewToggle() : null;
    final canBackfill = model.total > 0;

    void openLetterSettings() {
      if (!KitPageTools.instance.openSettings()) go('/letters/settings');
    }

    void newShelf() => showShelfSheet(
      context,
      canBackfill: canBackfill,
      land: (id) => go('/shelves/$id'),
      shelves: tags.tags,
    );

    return KitDPage(
      folio: folio,
      title: '${kitGreeting(now)}, *reader*',
      stand: stand,
      action: KitPageAction(
        label: 'Add a source',
        short: 'Add',
        icon: Icons.add,
        onPressed: () => go('/sources/add'),
      ),
      settings: KitPageSettings(
        label: 'Letter settings',
        has: const ['letter'],
        body: (context, close) => _LetterQuickHost(close: close),
      ),
      sections: _sec,
      sheet: KitDSheet(
        label: 'On this page',
        foldOnPick: true,
        peek: KitSecPeek(items: secs, sections: _sec),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const KitDLabel('Contents', first: true),
            KitContents(items: secs, sections: _sec),
            KitDeskLedger(rows: ledger, quiet: quiet),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SetupChecklist(documents: documents, aiOn: aiOn, go: go),
          if (empty)
            KeyedSubtree(
              key: _sec.keyOf('first'),
              child: KitFirstSources(
                // One upload path: Add a source, already picking.
                onAddFiles: () => go('/sources/add', extra: 'pick'),
                onPasteLink: () => go('/sources/add'),
                onConnect: () => go('/sources'),
              ),
            ),
          KeyedSubtree(
            key: _sec.keyOf('letter'),
            child: KitEditionLetter(
              read: read,
              parts: parts,
              sched: sched,
              libState: libState,
              now: now,
              onLetters: () => go('/letters'),
              onSettings: openLetterSettings,
            ),
          ),
          if (!empty)
            KitHomeLower(
              recent: KeyedSubtree(
                key: _sec.keyOf('recent'),
                child: KitRecentlyAdded(
                  model: model,
                  incoming: incoming,
                  loaded: loaded,
                  libError: libError,
                  grid: view == 'grid' && model.total > 0,
                  toggle: toggle,
                  onWholeLibrary: () => go('/sources'),
                ),
              ),
              earlier: past.isEmpty
                  ? null
                  : KeyedSubtree(
                      key: _sec.keyOf('earlier'),
                      child: KitEarlierLetters(
                        rows: [
                          for (final l in past)
                            KitEarlierLetter(
                              id: l.id,
                              no: kitLetterHead(l).no,
                              title: kitLetterHead(l).title,
                              date: l.generatedAt == null
                                  ? ''
                                  : kitShortDay(l.generatedAt!),
                            ),
                        ],
                        onOpen: () => go('/letters'),
                        onAll: () => go('/letters'),
                      ),
                    ),
            ),
          if (!empty)
            KeyedSubtree(
              key: _sec.keyOf('shelves'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  KitSectionHead(
                    'The shelves',
                    meta: measured
                        ? kitCounted(model.roots.length, 'shelf', 'shelves')
                        : null,
                    actions: [
                      KitHxLink(
                        'Suggest shelves',
                        icon: KitSparkle.icon,
                        onTap: () => showSuggestShelvesSheet(
                          context,
                          canBackfill: canBackfill,
                        ),
                      ),
                      KitHxLink('New shelf', icon: Icons.add, onTap: newShelf),
                      KitHxLink('All shelves →', onTap: () => go('/shelves')),
                      ?toggle,
                    ],
                  ),
                  KitShelfListing(
                    model: model,
                    view: view,
                    letterOn: letterOn,
                    loaded: loaded,
                    libError: libError,
                    onNewShelf: newShelf,
                    actions: KitShelfActions(
                      onOpenShelf: (n) =>
                          go(n.unshelved ? '/sources' : '/shelves/${n.id}'),
                      // Absent while generative AI is off (5.29.0, ADR-186).
                      onAsk: aiOn ? (n) => go('/ask/shelf/${n.id}') : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The setup checklist strip (web `shared/OnboardingChecklist.jsx`, compact):
/// the account (always done), a first source, a volume on a shelf, the letter
/// set up (`enabled` or a `deliveryTime` on the settings document), a first
/// question asked — the one client-local flag. While generative AI is off the
/// Ask step is ABSENT (5.29.0, ADR-186), so the strip can still complete;
/// steps are read by id, never by position. Hidden, dismissed or complete, it
/// is absent and its slot takes no room. Nothing here reaches Firestore.
class _SetupChecklist extends StatelessWidget {
  final List<Document> documents;
  final bool aiOn;
  final void Function(String to, {Object? extra}) go;

  const _SetupChecklist({
    required this.documents,
    required this.aiOn,
    required this.go,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>().newsletter;
    final steps = <String, KitSetupStep>{
      'account': const KitSetupStep('Create your account', done: true),
      'source': KitSetupStep(
        'Add your first source',
        done: documents.isNotEmpty,
        onTap: () => go('/sources/add'),
      ),
      'shelf': KitSetupStep(
        'File a volume onto a shelf',
        done: documents.any((d) => d.tagIds.isNotEmpty),
        onTap: () => go('/shelves'),
      ),
      'letter': KitSetupStep(
        'Set up your daily letter',
        done:
            settings != null &&
            (settings.enabled || settings.deliveryTime.isNotEmpty),
        onTap: () => go('/letters/settings'),
      ),
      if (aiOn)
        'ask': KitSetupStep(
          'Ask your library a question',
          done: LocalFlags.onboardAsked.value,
          onTap: () => go('/ask'),
        ),
    };
    if (LocalFlags.onboardDismissed.value ||
        steps.values.every((s) => s.done)) {
      return const SizedBox.shrink();
    }
    return KitHomeCheckSlot(
      child: KitSetupChecklist(
        steps: steps.values.toList(),
        compact: true,
        // Closed by default; once toggled, the choice is remembered.
        expanded: LocalFlags.onboardExpanded.value ?? false,
        onExpanded: LocalFlags.setOnboardExpanded,
        onHide: LocalFlags.setOnboardDismissed,
      ),
    );
  }
}

/// §28's body on Home: LetterQuick over the settings document the app already
/// reads ([SettingsNotifier]). Each write is one `fn_newsletter_settings` PUT
/// built in `services/api.dart`, then a re-read, so the schedule Home draws
/// (and the letter chips) follow it.
class _LetterQuickHost extends StatelessWidget {
  final VoidCallback close;
  const _LetterQuickHost({required this.close});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>();
    final router = GoRouter.maybeOf(context);
    return KitLetterQuick(
      settings: settings.newsletter,
      readError: settings.newsletter == null ? settings.error : null,
      write: (patch) => writeLetterSettings(settings, patch),
      onEverySetting: () {
        close();
        router?.go('/letters/settings');
      },
    );
  }
}

/// One LetterQuick write: the PUT, then the settings document re-read. The
/// server's sentence on a refusal.
@visibleForTesting
Future<KitLetterWrite> writeLetterSettings(
  SettingsNotifier settings,
  Map<String, dynamic> patch,
) async {
  try {
    final res = await Api.instance.updateNewsletterSettings(patch);
    unawaited(settings.loadAll());
    return KitLetterWrite(response: res);
  } on ApiException catch (e) {
    return KitLetterWrite(error: e.message);
  } catch (_) {
    return const KitLetterWrite(error: 'The change was not saved.');
  }
}
