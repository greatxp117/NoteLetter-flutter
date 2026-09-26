import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/newsletter.dart';
import '../models/tag.dart';
import '../shared/local_flags.dart';
import '../shared/upload_types.dart';
import '../state/documents_notifier.dart';
import '../state/newsletter_notifier.dart';
import '../state/settings_notifier.dart';
import '../state/tags_notifier.dart';
import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/kit/kit.dart';
import 'sources/shelf_books.dart';

/// **Library — the home screen** (`spec/screens/library.md`).
///
/// The route the web reference calls `library` is its default view and the
/// rail's *Home*; the rail's *Library* is Sources. This client had that
/// inverted — a bespoke "digest" dashboard on `/` and a volume table here — so
/// the screen the contract specifies existed nowhere and the screen it does not
/// specify existed twice. The table moved to Sources (`sources/volumes_section
/// .dart`), which is where `screens/sources.md` puts it.
///
/// Composition (library.md §Composition, ADR-041), every part from the kit:
///
/// * **Frame** Index (980) inside a scroll container — §1.4/§1.5.
/// * **Header** chapter opening: folio `{date} · {n} sources`, the greeting
///   title with its **italic accent clause**, and a standfirst that says
///   whether today's letter is ready.
/// * **Body** three sections, each opened by a section header carrying its own
///   count: today's letter (hero card), recently read (source rows), shelves
///   (a grid of shelf cards).
/// * **Empty** the drop zone leads — an offer, not an apology.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<DocumentsNotifier>().start();
      context.read<TagsNotifier>().start();
      context.read<NewsletterNotifier>().load();
      // The checklist's "Set up your daily letter" step reads the settings
      // doc, once per visit, as the reference's does.
      context.read<SettingsNotifier>().loadAll();
    });
    LocalFlags.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    // The client-local flags the checklist and the two view toggles read.
    return ListenableBuilder(
      listenable: Listenable.merge([
        LocalFlags.recentView,
        LocalFlags.shelvesView,
        LocalFlags.onboardDismissed,
        LocalFlags.onboardExpanded,
        LocalFlags.onboardAsked,
      ]),
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Consumer3<DocumentsNotifier, TagsNotifier, NewsletterNotifier>(
      builder: (context, docs, tags, letters, _) {
        if (docs.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final complete = docs.complete;
        final home = _LibraryHome(
          complete: complete,
          shelves: tags.tags,
          // The newest DAILY record, of any status (web ef14f8a) — see
          // NewsletterNotifier.todaysLetter.
          letter: letters.todaysLetter,
          // §14.2: a read that failed is not "no letter yet" (INV-24).
          letterError: letters.error,
          documents: docs.documents,
        );

        // §14 before §7, and above whatever did load (C2). `complete.isEmpty`
        // is true of a library that FAILED to load exactly as it is of one
        // with nothing in it, and §7 is an offer: drawn here it tells a reader
        // who has added things that they have added nothing. INV-24 has been
        // in `DocumentsNotifier` since F-08 and this screen never read it.
        if (docs.error != null) {
          return KitPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KitFailureBlock(
                  sentence: 'Your library could not be loaded.',
                  detail: docs.error!,
                  onRetry: () => context.read<DocumentsNotifier>().refresh(),
                ),
                // What did arrive is still true, and is kept — but it is no
                // longer the whole library, which is what the block says.
                if (complete.isNotEmpty) home,
              ],
            ),
          );
        }

        if (complete.isEmpty) {
          return _LibraryEmpty(documents: docs.documents);
        }

        return KitPage(child: home);
      },
    );
  }
}

class _LibraryHome extends StatefulWidget {
  final List<Document> complete;
  final List<Tag> shelves;
  final Newsletter? letter;
  final String? letterError;

  /// Every document, in flight or not — the checklist's "Add your first
  /// source" is done by the first one that exists, as the reference's is.
  final List<Document> documents;

  const _LibraryHome({
    required this.complete,
    required this.shelves,
    required this.letter,
    required this.documents,
    this.letterError,
  });

  @override
  State<_LibraryHome> createState() => _LibraryHomeState();
}

/// The Library's view toggles (web `LibraryHome.jsx`): Recently read is list
/// or shelf, Shelves is shelf or card — kept per viewer (`nl-recent-view`,
/// `nl-shelves-view`), the shelf the default for both.
const _recentViews = <({String id, String label, IconData icon})>[
  (id: 'list', label: 'List view', icon: Icons.view_agenda_outlined),
  (id: 'shelf', label: 'Shelf view', icon: Icons.shelves),
];
const _shelvesViews = <({String id, String label, IconData icon})>[
  (id: 'shelf', label: 'Shelf view', icon: Icons.shelves),
  (id: 'card', label: 'Card view', icon: Icons.grid_view),
];

class _LibraryHomeState extends State<_LibraryHome> {
  /// One book pulled across every named shelf (the reference's shelfOpenId).
  String? _shelfOpenId;

  Widget _toggle(List<({String id, String label, IconData icon})> views,
          ValueNotifier<String> which) =>
      KitSegmented(
        segments: [for (final v in views) KitSegment.icon(v.icon, v.label)],
        selected: math.max(0, views.indexWhere((v) => v.id == which.value)),
        onChanged: (i) => LocalFlags.setView(which, views[i].id),
      );

  @override
  Widget build(BuildContext context) {
    final complete = widget.complete;
    final shelves = widget.shelves;
    final letter = widget.letter;
    final letterError = widget.letterError;
    final total = complete.length;
    final recent = complete.take(12).toList();
    final recentView = LocalFlags.recentView.value;
    final shelvesView = LocalFlags.shelvesView.value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChapterOpening(
          folio: '${_today()} · ${_plural(total, 'source')}',
          title: '${_greeting()}, *reader*',
          standfirst: letter != null
              ? "Today's letter is ready — "
                  '${_passages(letter)} from your library.'
              : letterError != null
                  // Not "tomorrow's letter will draw…": that sentence is a
                  // claim about a letter we could not read.
                  ? "Today's letter could not be read."
                  : "Your library is being read. Tomorrow's letter will draw "
                      "from what's indexed so far.",
        ),

        if (letter == null && letterError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: KitFailureInline(letterError),
          ),

        // The setup checklist, as a strip (web OnboardingChecklist compact).
        _SetupChecklist(documents: widget.documents, compact: true),

        // `.lib-actions` — the search field and Add a source. They were a
        // ghost `Search` and an `Add a source` in the header's actions slot.
        KitLibraryActions(
          onSearch: () => context.go('/search'),
          onAdd: () => context.go('/sources'),
        ),

        // ── Today's letter ───────────────────────────────────────────────
        if (letter != null) ...[
          SectionHeader(
            "Today's letter",
            actionLabel: 'Preview the letter →',
            onAction: () => context.go('/letters'),
          ),
          KitHeroCard(
            title: 'A *Letter*',
            // The reference's masthead number is the letter's subject; the
            // date is the Sent cell's.
            marker: (letter.subject?.isNotEmpty ?? false)
                ? letter.subject
                : _letterDate(letter.generatedAt),
            // The librarian's note by its `data-nl-lede` marker, never a slice
            // of the body — the head of a letterheaded body is the masthead
            // (web 5d6fe8d). A letter with neither says what a letter is.
            standfirst: letter.ledeOf(140).isNotEmpty
                ? letter.ledeOf(140)
                : 'Your daily reading, drawn from what you’ve added to your '
                    'library.',
            // Counted off the record this hero is drawn from, so there is no
            // unread state. The web's "~n+1 min read" is arithmetic on a
            // passage count, not a measurement, and has no cell here; Sent
            // is drawn only for a letter that was.
            stats: [
              KitStat('${letter.chunkIds.length}', 'Passages'),
              if (letter.status == 'sent' &&
                  _letterDate(letter.generatedAt) != null)
                KitStat(_letterDate(letter.generatedAt)!, 'Sent'),
            ],
            actions: [
              KitButton.primary('Preview & send',
                  icon: Icons.mail_outlined,
                  onPressed: () => context.go('/letters')),
              KitButton.ghost('Schedule',
                  icon: Icons.schedule,
                  onPressed: () => context.go('/letters/settings')),
            ],
          ),
        ],

        // ── Recently read ────────────────────────────────────────────────
        SectionHeader(
          'Recently read · ${_plural(total, 'source')}',
          tools: _toggle(_recentViews, LocalFlags.recentView),
          actionLabel: 'View all →',
          onAction: () => context.go('/sources'),
        ),
        if (recentView == 'shelf')
          // The shelf F-65 built, bare: this section's header is its head.
          KitShelfView(
            items: [for (final d in recent) bookOf(d, shelves)],
            sort: 'recent',
            grouped: false,
            bare: true,
            label: 'Recently read',
          )
        else
          KitRowList(
            rows: [
              for (final d in recent.take(5))
                KitSourceLink(
                  docId: d.id,
                  builder: (context, open) => KitSourceRow(
                    leading: KitFileBadge(kitDocKind(d.type)),
                    title: d.title.isEmpty ? 'Untitled' : d.title,
                    subtitle: '${_shelfLabel(d, shelves)} · '
                        '${_plural(d.chunkCount ?? 0, 'passage')}',
                    count: '${d.chunkCount ?? 0}',
                    date: _rowDate(d.createdAt),
                    onTap: open,
                  ),
                ),
            ],
          ),

        // ── Shelves ──────────────────────────────────────────────────────
        SectionHeader(
          'Shelves · ${shelves.length}',
          tools: _toggle(_shelvesViews, LocalFlags.shelvesView),
          actionLabel: 'New shelf +',
          onAction: () => context.go('/shelves'),
        ),
        if (shelves.isEmpty)
          KitCard(
            child: Text(
              'No shelves yet — create one from the Shelves page.',
              style: KitText.meta(context),
            ),
          )
        else if (shelvesView == 'shelf')
          // `.lib-shelves` — a titled ledge per shelf, wrapping 320–440 wide;
          // one to a line on a phone.
          LayoutBuilder(builder: (context, c) {
            const gap = 18.0;
            final per = math.max(1, ((c.maxWidth + gap) / (320 + gap)).floor());
            final w = math.min(440.0, (c.maxWidth - gap * (per - 1)) / per);
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final s in shelves)
                    SizedBox(
                      width: w,
                      child: KitShelfUnit(
                        label: s.title,
                        books: [
                          for (final d in complete)
                            if (d.tagIds.contains(s.id)) bookOf(d, shelves),
                        ],
                        openId: _shelfOpenId,
                        onOpen: (id) => setState(() => _shelfOpenId = id),
                        dot: AppColors.shelfColor(s.color) ?? // pair-ok: a shelf's stored colour is a fixed data token
                            Tokens.of(context).fgSubtle,
                      ),
                    ),
                ],
              ),
            );
          })
        else
          KitCardGrid(
            children: [
              for (final s in shelves)
                Builder(builder: (context) {
                  final vols = complete
                      .where((d) => d.tagIds.contains(s.id))
                      .toList();
                  final passages = vols.fold<int>(
                      0, (n, d) => n + (d.chunkCount ?? 0));
                  return KitShelfCard(
                    title: s.title,
                    colorToken: s.color,
                    volumes: vols.length,
                    meta: '${_plural(vols.length, 'volume')}'
                        '${passages > 0 ? ' · ${_plural(passages, 'passage')}' : ''}',
                    // The shelf's OWN page, now that it has one: the card
                    // named a shelf and opened the index until F-08.
                    onTap: () => context.go('/shelves/${s.id}'),
                  );
                }),
            ],
          ),
      ],
    );
  }
}

/// The setup checklist's data (web `shared/OnboardingChecklist.jsx`): five
/// steps from live data — the account (done), a first source, a volume on a
/// shelf, the letter set up, a first question asked (the one client-local
/// flag) — plus whether it is hidden or open. Nothing here reaches Firestore.
class _SetupChecklist extends StatefulWidget {
  final List<Document> documents;
  final bool compact;

  const _SetupChecklist({required this.documents, required this.compact});

  @override
  State<_SetupChecklist> createState() => _SetupChecklistState();
}

class _SetupChecklistState extends State<_SetupChecklist> {
  /// Decided once, on the first render: a reader who had the middle steps
  /// done before this ever showed gets only the strip, never the card.
  bool? _preDone;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsNotifier>().newsletter;
    final docs = widget.documents;
    final steps = [
      const KitSetupStep('Create your account', done: true),
      KitSetupStep('Add your first source',
          done: docs.isNotEmpty, onTap: () => context.go('/sources')),
      KitSetupStep('File a volume onto a shelf',
          done: docs.any((d) => d.tagIds.isNotEmpty),
          onTap: () => context.go('/shelves')),
      // `enabled === true || !!deliveryTime` on a settings doc that exists.
      KitSetupStep('Set up your daily letter',
          done: settings != null &&
              (settings.enabled || settings.deliveryTime.isNotEmpty),
          onTap: () => context.go('/letters/settings')),
      KitSetupStep('Ask your library a question',
          done: LocalFlags.onboardAsked.value,
          onTap: () => context.go('/ask')),
    ];
    _preDone ??= steps[1].done && steps[2].done && steps[3].done;

    if (LocalFlags.onboardDismissed.value || steps.every((s) => s.done)) {
      return const SizedBox.shrink();
    }
    final compact = widget.compact || _preDone!;
    return KitSetupChecklist(
      steps: steps,
      compact: compact,
      // The full card starts open (it IS the first-run hero); the strip
      // starts closed; once toggled, the choice is remembered.
      expanded: LocalFlags.onboardExpanded.value ?? !compact,
      onExpanded: LocalFlags.setOnboardExpanded,
      onHide: LocalFlags.setOnboardDismissed,
    );
  }
}

/// The empty library. The **drop zone is the offer** — a reader with nothing
/// indexed is shown where the first thing goes, not told that there is nothing
/// here (`component-kit.md` §7).
class _LibraryEmpty extends StatelessWidget {
  final List<Document> documents;

  const _LibraryEmpty({required this.documents});

  @override
  Widget build(BuildContext context) {
    return KitPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ChapterOpening(
            title: 'Your library is *empty — for now.*',
            standfirst: "Bring in everything you've read. NoteLetter parses "
                'the text, makes it searchable, and starts writing you a '
                'daily letter from your own notes.',
          ),
          // The first-run checklist, as the full card (web LibraryEmpty).
          _SetupChecklist(documents: documents, compact: false),
          // This said "PDF, EPUB, Markdown, plain text, or images" and tagged
          // EPUB (C2b). No extractor has ever supported EPUB and
          // `application/epub+zip` is a hard 400 since 4.10.0, so the FIRST
          // screen a new reader sees promised a format the front door refuses
          // — while omitting Word, PowerPoint, audio and video, which are
          // real. component-kit §3 rule 3: a `pending` kind may be RENDERED
          // and must not be ADVERTISED.
          //
          // The reference fixed this exact string and made it read from the
          // constant beside the accepted list so the two cannot drift again.
          // This client already HAD that constant — `uploadAcceptHelp`, used
          // by `file_uploader` — and this screen was the second place the copy
          // was written by hand, which is how it stayed a release behind.
          KitDropZone(
            icon: Icons.upload_outlined,
            title: 'Drop files to begin',
            help: '$uploadAcceptHelp — or open Sources to browse',
            formats: const [
              KitTag('PDF'),
              KitTag('Word'),
              KitTag('Markdown'),
              KitTag('TXT'),
              KitTag('PNG / JPG'),
              KitTag('Audio'),
            ],
            onTap: () => context.go('/sources'),
          ),
          const SizedBox(height: 32),
          Center(
            child: KitButton.ghost(
              'Go to Sources to add or connect →',
              onPressed: () => context.go('/sources'),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Formatting ───────────────────────────────────────────────────────────────

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _today() {
  final now = DateTime.now();
  return '${_weekdays[now.weekday - 1]}, '
      '${_months[now.month - 1]} ${now.day}';
}

/// Matches the web reference's boundaries (12 / 18). This client's old
/// dashboard turned to evening at 17 and greeted a reader differently from
/// every other client for an hour a day.
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

/// The standfirst's count: `chunk_ids`, which names exactly the passages the
/// body holds (4.39.0) — the reference's `letter.chunk_ids.length`, and what
/// the Letters card counts. It read `passages_sent` and fell back to a bare
/// `passages` when that was absent, so the standfirst said "Today's letter is
/// ready — passages from your library." (2026-09-25 frame).
String _passages(Newsletter letter) =>
    _plural(letter.chunkIds.length, 'passage');

/// English plurals, in one place. Written out because "1 passages" shipped to a
/// real screen the first time each of these was inlined.
String _plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// The row date: minutes-ago, then a clock time within the day, then a calendar
/// date — the web's `formatDate`.
String _rowDate(int? ms) {
  if (ms == null) return '';
  final then = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(then);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 24) {
    final h = then.hour % 12 == 0 ? 12 : then.hour % 12;
    final m = then.minute.toString().padLeft(2, '0');
    return '$h:$m ${then.hour < 12 ? 'AM' : 'PM'}';
  }
  return '${_months[then.month - 1].substring(0, 3)} ${then.day}';
}

String? _letterDate(int? ms) {
  if (ms == null) return null;
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_months[d.month - 1].substring(0, 3)} ${d.day}';
}

String _shelfLabel(Document doc, List<Tag> shelves) {
  for (final s in shelves) {
    if (doc.tagIds.contains(s.id)) return s.title;
  }
  return 'Unshelved';
}
