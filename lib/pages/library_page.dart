import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/document.dart';
import '../models/newsletter.dart';
import '../models/tag.dart';
import '../state/documents_notifier.dart';
import '../state/newsletter_notifier.dart';
import '../state/tags_notifier.dart';
import '../widgets/kit/kit.dart';

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
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<DocumentsNotifier, TagsNotifier, NewsletterNotifier>(
      builder: (context, docs, tags, letters, _) {
        if (docs.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        final complete = docs.complete;
        if (complete.isEmpty) return const _LibraryEmpty();

        return KitPage(
          child: _LibraryHome(
            complete: complete,
            shelves: tags.tags,
            // A `generating`/`error`/`empty` record is history, not a letter to
            // lead the screen with: the hero's figures and preview would all be
            // about something that was never sent.
            letter: letters.latest?.status == 'sent' ? letters.latest : null,
          ),
        );
      },
    );
  }
}

class _LibraryHome extends StatelessWidget {
  final List<Document> complete;
  final List<Tag> shelves;
  final Newsletter? letter;

  const _LibraryHome({
    required this.complete,
    required this.shelves,
    required this.letter,
  });

  @override
  Widget build(BuildContext context) {
    final total = complete.length;
    final recent = complete.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChapterOpening(
          folio: '${_today()} · $total ${total == 1 ? 'source' : 'sources'}',
          title: '${_greeting()}, *reader*',
          standfirst: letter != null
              ? "Today's letter is ready — "
                  '${_passages(letter!)} from your library.'
              : "Your library is being read. Tomorrow's letter will draw "
                  "from what's indexed so far.",
          actions: [
            KitButton.ghost('Search',
                icon: Icons.search, onPressed: () => context.go('/search')),
            KitButton.primary('Add a source',
                icon: Icons.add, onPressed: () => context.go('/sources')),
          ],
        ),

        // ── Today's letter ───────────────────────────────────────────────
        if (letter != null) ...[
          SectionHeader(
            "Today's letter",
            actionLabel: 'Preview the letter →',
            onAction: () => context.go('/letters'),
            first: true,
          ),
          KitHeroCard(
            title: 'A *Letter*',
            marker: _letterDate(letter!.generatedAt),
            standfirst: _letterLede(letter!.html),
            // Only figures with a backing signal get a cell: `passages_sent`
            // and `passages_found` are stored as sent, so they stay honest as
            // the library grows. The web's "~n+1 min read" is arithmetic on a
            // passage count, not a measurement, and has no cell here.
            stats: [
              if (letter!.passagesSent != null)
                KitStat('${letter!.passagesSent}', 'Passages'),
              if (letter!.passagesFound != null)
                KitStat('${letter!.passagesFound}', 'Found'),
            ],
            actions: [
              KitButton.primary('Preview & send',
                  icon: Icons.mail_outlined,
                  onPressed: () => context.go('/letters')),
              KitButton.ghost('Schedule',
                  icon: Icons.schedule,
                  onPressed: () => context.go('/settings')),
            ],
          ),
        ],

        // ── Recently read ────────────────────────────────────────────────
        SectionHeader(
          'Recently read · $total ${total == 1 ? 'source' : 'sources'}',
          actionLabel: 'View all →',
          onAction: () => context.go('/sources'),
          first: letter == null,
        ),
        KitRowList(
          rows: [
            for (final d in recent)
              KitSourceRow(
                leading: KitFileBadge(kitDocKind(d.type)),
                title: d.title.isEmpty ? 'Untitled' : d.title,
                subtitle: '${_shelfLabel(d, shelves)} · '
                    '${d.chunkCount ?? 0} passages',
                count: '${d.chunkCount ?? 0}',
                date: _rowDate(d.createdAt),
                onTap: () => context.push('/reader/${d.id}'),
              ),
          ],
        ),

        // ── Shelves ──────────────────────────────────────────────────────
        SectionHeader(
          'Shelves · ${shelves.length}',
          actionLabel: 'New shelf +',
          onAction: () => context.go('/tags'),
        ),
        if (shelves.isEmpty)
          KitCard(
            child: Text(
              'No shelves yet — create one from the Shelves page.',
              style: KitText.meta(context),
            ),
          )
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
                    meta: '${vols.length} '
                        '${vols.length == 1 ? 'volume' : 'volumes'}'
                        '${passages > 0 ? ' · $passages passages' : ''}',
                    onTap: () => context.go('/tags'),
                  );
                }),
            ],
          ),
      ],
    );
  }
}

/// The empty library. The **drop zone is the offer** — a reader with nothing
/// indexed is shown where the first thing goes, not told that there is nothing
/// here (`component-kit.md` §7).
class _LibraryEmpty extends StatelessWidget {
  const _LibraryEmpty();

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
          KitDropZone(
            icon: Icons.upload_outlined,
            title: 'Drop files to begin',
            help: 'PDF, EPUB, Markdown, plain text, or images — '
                'or open Sources to browse',
            formats: const [
              KitTag('PDF'),
              KitTag('EPUB'),
              KitTag('Markdown'),
              KitTag('TXT'),
              KitTag('PNG / JPG'),
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

String _passages(Newsletter letter) {
  final n = letter.passagesSent;
  if (n == null) return 'passages';
  return '$n passage${n == 1 ? '' : 's'}';
}

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

/// The letter's opening line, taken from the letter itself.
///
/// A newsletter record carries `html` and no plain-text body on this client, so
/// the lede is the rendered letter with its markup stripped — the real first
/// words of the real letter. Returns null rather than a placeholder when there
/// is nothing to show: the hero drops the standfirst instead of asserting
/// something about a letter nobody has read.
String? _letterLede(String html) {
  if (html.isEmpty) return null;
  final text = html
      .replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>',
          dotAll: true, caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&rsquo;', '’')
      .replaceAll('&mdash;', '—')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (text.isEmpty) return null;
  return text.length <= 140 ? text : '${text.substring(0, 140).trim()}…';
}

String _shelfLabel(Document doc, List<Tag> shelves) {
  for (final s in shelves) {
    if (doc.tagIds.contains(s.id)) return s.title;
  }
  return 'Unshelved';
}
