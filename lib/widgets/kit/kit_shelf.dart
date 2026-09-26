part of 'kit_rows.dart';

// ── The shelf: cloth-bound spines on a ledge (web `pages/sources/ShelfView.jsx`,
// `styles/app-sources-shelf.css`) ─────────────────────────────────────────────
//
// Built ONCE, here, and composed by both screens that draw it: Sources' shelf
// view (F-65, the reference's default) and the Library's "Recently read" and
// per-shelf ledges (F-54). A part of kit_rows.dart because a shelf is a way of
// laying out the same source links a §4.1 row list lays out.
//
// Not ported: the reference's hover popover (`.bpop`). It is a pointer-hover
// glimpse, and a touch screen has no hover; a tap opens the detail card, which
// carries everything the popover did and more.

/// One volume on a shelf. The kit holds no document model, so a screen maps
/// its documents onto this.
class KitBook {
  final String id;
  final String title;

  /// §6.4.1 kind ([kitDocKind]) — picks the cloth and the spine's mark.
  final String kind;
  final int passages;

  /// `word_count`, where the document carries one; the spine's width.
  final int? words;

  /// `created_at`, epoch ms.
  final int? createdAt;
  final int viewCount;

  /// The first shelf the document is on, in shelf order — its name and its
  /// colour (the spine's band). Null when it is on none.
  final String? shelf;
  final Color? shelfColor;
  final String? sourceUrl;

  const KitBook({
    required this.id,
    required this.title,
    required this.kind,
    this.passages = 0,
    this.words,
    this.createdAt,
    this.viewCount = 0,
    this.shelf,
    this.shelfColor,
    this.sourceUrl,
  });

  String get _title => title.isEmpty ? 'Untitled' : title;
}

// component-kit §6.4.1 — "every live kind has a spine cloth (4.84.1)". Deep
// brand darks that do NOT flip with the theme: the books read the same in any
// light, which is design-tokens.md's named exemption for a raw step.
// pair-ok: the book cloth does not flip (design-tokens.md, a raw step is right)
final Map<String, Color> _cloth = {
  'pdf':
      AppColors.shelfColors['brick-700']!, // pair-ok: cloth is a fixed raw step
  // literal-ok: epub's deep-sage cloth is the reference's own literal (app-sources-shelf.css), a pending kind
  'epub': const Color(0xFF3A4A2B),
  'web':
      AppColors.shelfColors['plum-600']!, // pair-ok: cloth is a fixed raw step
  'youtube':
      AppColors.shelfColors['plum-600']!, // pair-ok: cloth is a fixed raw step
  'instagram':
      AppColors.shelfColors['plum-600']!, // pair-ok: cloth is a fixed raw step
  'tiktok':
      AppColors.shelfColors['plum-600']!, // pair-ok: cloth is a fixed raw step
  'note':
      AppColors.shelfColors['ink-500']!, // pair-ok: cloth is a fixed raw step
  // literal-ok: ochre-600, the podcast cloth — a fixed raw step (the --warning pair would flip)
  'podcast': const Color(0xFF8A5A12),
  'video':
      AppColors.shelfColors['sage-700']!, // pair-ok: cloth is a fixed raw step
};

Color _clothFor(String kind) => _cloth[kind] ?? _cloth['note']!;

// The cloth's own ink: --paper-50 and the brick-400 band, both fixed.
const Color _clothInk = AppColors.chromeForeground; // pair-ok: on fixed cloth
const Color _clothBrick = AppColors.chromeAccentBar; // pair-ok: on fixed cloth

/// `SHELF_KIND_LONG` — a kind spelled for a cover or a detail eyebrow.
const _kindLong = <String, String>{
  'pdf': 'Document',
  'epub': 'Book',
  'web': 'Web clip',
  'youtube': 'YouTube',
  'instagram': 'Instagram',
  'tiktok': 'TikTok',
  'note': 'Note',
  'podcast': 'Recording',
  'video': 'Video',
};

/// `SPINE_KIND_ICON` — the reference's glyph per kind, as Material draws it.
const _kindIcon = <String, IconData>{
  'pdf': Icons.insert_drive_file_outlined,
  'epub': Icons.menu_book_outlined,
  'web': Icons.link,
  'youtube': Icons.play_arrow,
  'instagram': Icons.play_arrow,
  'tiktok': Icons.play_arrow,
  'note': Icons.edit_outlined,
  'podcast': Icons.play_arrow,
  'video': Icons.play_arrow,
};

/// `SHELF_GROUPS` — the shelf view's own group labels, over the whole kind
/// vocabulary (component-kit §6.4.1 rule 2), in the reference's order.
const kShelfGroups = <({String id, String label})>[
  (id: 'pdf', label: 'Documents'),
  (id: 'epub', label: 'Books'),
  (id: 'web', label: 'Web clips'),
  (id: 'youtube', label: 'YouTube'),
  (id: 'instagram', label: 'Instagram'),
  (id: 'tiktok', label: 'TikTok'),
  (id: 'note', label: 'Notes'),
  (id: 'podcast', label: 'Audio'),
  (id: 'video', label: 'Video'),
];

/// Deterministic from an id — a book keeps its height between renders.
/// The reference's `(h * 31 + c) >>> 0`, in unsigned 32-bit.
int _shelfHash(String s) {
  var h = 0;
  for (final c in s.codeUnits) {
    h = (h * 31 + c) & 0xFFFFFFFF;
  }
  return h;
}

/// `sourceWords`: the stored count, else 850 a passage, else 6000.
int _bookWords(KitBook b) {
  if ((b.words ?? 0) > 0) return b.words!;
  return b.passages > 0 ? (b.passages * 850) : 6000;
}

/// `spineWidth` — 16–64px on a log scale from 1,500 to 320,000 words.
double _spineWidth(int words) {
  final lo = math.log(1500), hi = math.log(320000);
  final t = ((math.log(math.max(words, 1)) - lo) / (hi - lo)).clamp(0.0, 1.0);
  return (16 + t * (64 - 16)).roundToDouble();
}

String _fmtWords(int words) =>
    words >= 1000 ? '${(words / 1000).round()}k words' : '$words words';

const _mon = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDay(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${_mon[d.month - 1]} ${d.day}';
}

/// `.bcover-author` — the source's host, else the kind spelled long.
String _author(KitBook b) {
  final url = b.sourceUrl;
  if (url != null && url.isNotEmpty) {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isNotEmpty) return host.replaceFirst(RegExp(r'^www\.'), '');
  }
  return _kindLong[b.kind] ?? b.kind;
}

/// The cloth: the kind's colour under the reference's spine shading. The
/// shading is BLENDED onto the cloth, stop by stop: a `BoxDecoration` with a
/// gradient ignores its `color`, so a translucent gradient over `color` drew
/// the scrims over nothing and the book had no cloth at all.
BoxDecoration _clothDecoration(
  String kind,
  BorderRadius radius, {
  required List<double> stops,
}) {
  final cloth = _clothFor(kind);
  return BoxDecoration(
    borderRadius: radius,
    gradient: LinearGradient(
      colors: [
        // literal-ok: spine shading — a black scrim blended onto fixed cloth
        Color.alphaBlend(const Color(0x57000000), cloth),
        cloth,
        cloth,
        // literal-ok: spine shading — a white scrim blended onto fixed cloth
        Color.alphaBlend(const Color(0x12FFFFFF), cloth),
      ],
      stops: stops,
    ),
  );
}

/// A spine (`.bspine`): cloth, a band in the shelf's colour, the title set
/// vertically, the kind's mark at the foot, the unread dot at the head.
/// A §6.4.3 link: a plain tap opens the detail card, and the link itself is
/// the reader route (rule 3).
class KitBookSpine extends StatelessWidget {
  final KitBook book;
  final bool open;
  final VoidCallback onTap;

  /// The band's colour — the named shelf's own on a shelf's ledge, else the
  /// book's first shelf, else brick-400.
  final Color? accent;

  const KitBookSpine({
    super.key,
    required this.book,
    required this.open,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final height = 168.0 + (_shelfHash(book.id) % 48);
    final width = _spineWidth(_bookWords(book));
    return KitSourceLink(
      docId: book.id,
      onOpen: onTap,
      builder: (context, activate) => Semantics(
        button: true,
        label: book._title,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: activate,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, open ? -20 : 0, 0),
            width: width,
            height: height,
            child: Container(
              padding: const EdgeInsets.only(top: 12, bottom: 10),
              decoration: _clothDecoration(
                book.kind,
                const BorderRadius.only(
                  topLeft: Radius.circular(1),
                  bottomLeft: Radius.circular(1),
                  topRight: Radius.circular(3),
                  bottomRight: Radius.circular(3),
                ),
                stops: const [0, 0.11, 0.84, 1],
              ).copyWith(boxShadow: open ? AppShadows.s3 : AppShadows.s1),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.56,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            color: accent ?? book.shelfColor ?? _clothBrick,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          child: RotatedBox(
                            quarterTurns: 1,
                            child: Text(
                              book._title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.serif(
                                fontSize: 13,
                                height: 1,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.13,
                                color: _clothInk,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Icon(
                        _kindIcon[book.kind] ??
                            Icons.insert_drive_file_outlined,
                        size: 13,
                        color: _clothBrick,
                      ),
                    ],
                  ),
                  if (book.viewCount == 0)
                    Positioned(
                      top: -5,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: t.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The cover title's size: 21, or less when the longest word would not fit
/// [width] at 21 (never under 14).
double _coverTitleSize(String title, double width) {
  var longest = 0.0;
  for (final w in title.split(RegExp(r'\s+'))) {
    if (w.isEmpty) continue;
    final tp = TextPainter(
      text: TextSpan(
        text: w,
        style: AppTheme.serif(fontSize: 21, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    longest = math.max(longest, tp.width);
  }
  if (longest <= width || longest == 0) return 21;
  return math.max(14, (21 * width / longest).floorToDouble());
}

/// `.bcover` — the pulled book's front: cloth, a ruled frame, the kind as a
/// mono eyebrow, the title, a brick rule, the source, the quill seal.
class KitBookCover extends StatelessWidget {
  final KitBook book;
  final double width;
  final double height;

  const KitBookCover({
    super.key,
    required this.book,
    this.width = 196,
    this.height = 280,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: _clothDecoration(
        book.kind,
        const BorderRadius.only(
          topLeft: Radius.circular(2),
          bottomLeft: Radius.circular(2),
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
        ),
        stops: const [0, 0.07, 0.12, 1],
      ).copyWith(boxShadow: AppShadows.s3),
      padding: const EdgeInsets.fromLTRB(18, 13, 13, 13),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _clothInk.withValues(alpha: 0.26)),
          borderRadius: BorderRadius.circular(2),
        ),
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
        child: Column(
          children: [
            Text(
              (_kindLong[book.kind] ?? book.kind).toUpperCase(),
              style: AppTheme.mono(
                fontSize: 9,
                letterSpacing: 1.8,
                color: _clothBrick,
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Flexible: a long title gives up lines before the frame
                  // does — the cover is a fixed size, the title is not. And
                  // the type steps down until its longest WORD fits the
                  // frame: a wrap never splits a word on the reference, and
                  // on a 170px phone cover "Cornbread," would not fit at 21.
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final size = _coverTitleSize(book._title, c.maxWidth);
                        return Text(
                          book._title,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.serif(
                            fontSize: size,
                            height: 1.18,
                            fontWeight: FontWeight.w600,
                            color: _clothInk,
                          ),
                        );
                      },
                    ),
                  ),
                  Container(
                    width: 26,
                    height: 2,
                    margin: const EdgeInsets.symmetric(vertical: 13),
                    color: _clothBrick,
                  ),
                  Text(
                    _author(book),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.serif(
                      fontSize: 13,
                      height: 1.3,
                      fontStyle: FontStyle.italic,
                      color: _clothInk.withValues(alpha: 0.82),
                    ),
                  ),
                ],
              ),
            ),
            KitGlyph(KitQuill.icon, size: 18, color: _clothBrick),
          ],
        ),
      ),
    );
  }
}

/// `.book-detail` — the card a pulled spine opens under its shelf: the cover,
/// the kind and date, the title and source, five stats, the note, and the two
/// ways in. Stacks (cover centred over the text) below the compact width.
class KitBookDetail extends StatelessWidget {
  final KitBook book;
  final VoidCallback onClose;

  const KitBookDetail({super.key, required this.book, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    final kind = _kindLong[book.kind] ?? book.kind;

    Widget stat(String num, String label, {bool last = false}) => Container(
      padding: EdgeInsets.only(right: last ? 0 : 16),
      decoration: BoxDecoration(
        border: last ? null : Border(right: BorderSide(color: t.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            num,
            style: AppTheme.serif(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: t.fg,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label.toUpperCase(),
            style: AppTheme.mono(
              fontSize: 10,
              letterSpacing: 1,
              color: t.fgSubtle,
            ),
          ),
        ],
      ),
    );

    final meta = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Eyebrow('$kind · added ${_fmtDay(book.createdAt)}'),
        const SizedBox(height: 9),
        Text(
          book._title,
          style: AppTheme.serif(
            fontSize: 26,
            height: 1.16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.26,
            color: t.fg,
          ),
        ),
        const SizedBox(height: 5),
        Text(_author(book), style: KitText.ui(context, color: t.fgMuted)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: [
            stat(_fmtWords(_bookWords(book)).replaceAll(' words', ''), 'Words'),
            stat('${book.passages}', 'Passages'),
            stat(book.shelf ?? 'Unshelved', 'Shelf'),
            stat(_fmtDay(book.createdAt), 'Added'),
            stat(
              book.viewCount > 0 ? '${book.viewCount}×' : 'Unread',
              book.viewCount > 0 ? 'Views' : 'Status',
              last: true,
            ),
          ],
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            '${book.passages} passage${book.passages == 1 ? '' : 's'} '
            'indexed and searchable. Open it to '
            'read, or pull a single passage into your letter.',
            style: KitText.lede(context, fontSize: 15, height: 23),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            KitSourceLink(
              docId: book.id,
              builder: (context, open) => KitButton.primary(
                'Open in reader',
                icon: Icons.menu_book_outlined,
                onPressed: open,
              ),
            ),
            KitSourceLink(
              docId: book.id,
              builder: (context, open) => KitButton.ghost(
                'Find a passage',
                icon: Icons.search,
                onPressed: open,
              ),
            ),
          ],
        ),
      ],
    );

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s2,
      ),
      child: Stack(
        // The close control sits in the card's padding (`.bd-close` at 14/14
        // of the card), outside the content box — clipped, it drew as a sliver.
        clipBehavior: Clip.none,
        children: [
          compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: KitBookCover(book: book, width: 170, height: 244),
                    ),
                    const SizedBox(height: 20),
                    meta,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    KitBookCover(book: book),
                    const SizedBox(width: 30),
                    Expanded(child: meta),
                  ],
                ),
          Positioned(
            top: -12,
            right: -14,
            child: Semantics(
              button: true,
              label: 'Close',
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onClose,
                child: SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.close, size: 16, color: t.fgSubtle),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.shelf-unit` — a head, the spines standing on a ledge, and the detail card
/// of whichever book is pulled. [openId]/[onOpen] belong to the host, so one
/// book is pulled across every shelf a screen draws (the Library's ledges
/// share one, as the reference's `shelfOpenId` does).
class KitShelfUnit extends StatelessWidget {
  final String label;
  final List<KitBook> books;
  final String? openId;
  final ValueChanged<String?> onOpen;

  /// No head at all (`bare`) — the Library's "Recently read" shelf, whose
  /// section header is its head.
  final bool bare;

  /// A NAMED shelf's colour: its head becomes the plate + serif name + mono
  /// count (`.shelf-head-named`) and every spine's band takes this colour.
  final Color? dot;

  const KitShelfUnit({
    super.key,
    required this.label,
    required this.books,
    required this.openId,
    required this.onOpen,
    this.bare = false,
    this.dot,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < AppSpacing.compactWidth;
    KitBook? open;
    for (final b in books) {
      if (b.id == openId) open = b;
    }
    final passages = books.fold<int>(0, (n, b) => n + b.passages);
    final dark = t.brightness == Brightness.dark;

    Widget? head;
    if (!bare && dot != null) {
      head = Row(
        children: [
          Container(
            width: 12,
            height: 16,
            decoration: BoxDecoration(
              color: dot,
              borderRadius: AppRadius.xsR,
              border: Border.all(color: t.border),
              boxShadow: AppShadows.s1,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: AppTheme.serif(
              fontSize: 20,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: t.fg,
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              '${books.length} ${books.length == 1 ? 'volume' : 'volumes'} · '
              '$passages passage${passages == 1 ? '' : 's'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(
                fontSize: 11,
                letterSpacing: 0.22,
                color: t.fgSubtle,
              ),
            ),
          ),
        ],
      );
    } else if (!bare) {
      head = Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Eyebrow('$label · ${books.length}'),
          // `.shelf-hint` hides at 720 on the reference; its hover clause is
          // not said here, where there is no hover.
          if (!compact) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                '$passages passage${passages == 1 ? '' : 's'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: KitText.lede(
                  context,
                  fontSize: 13,
                  height: 18,
                ).copyWith(color: t.fgSubtle),
              ),
            ),
          ],
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (head != null) head,
        SizedBox(
          height: 244,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(8, 26, 8, 0),
            children: [
              for (var i = 0; i < books.length; i++) ...[
                if (i > 0) const SizedBox(width: 3),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: KitBookSpine(
                    book: books[i],
                    open: books[i].id == openId,
                    onTap: () =>
                        onOpen(books[i].id == openId ? null : books[i].id),
                    accent: dot,
                  ),
                ),
              ],
              if (books.isEmpty)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 22, left: 4),
                    child: Text(
                      'This shelf is empty.',
                      style: KitText.lede(
                        context,
                        fontSize: 14,
                        height: 20,
                      ).copyWith(color: t.fgSubtle),
                    ),
                  ),
                ),
              const SizedBox(width: 14),
            ],
          ),
        ),
        // The ledge: a thin painted board seen edge-on.
        Container(
          height: 9,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(1),
              topRight: Radius.circular(1),
              bottomLeft: Radius.circular(3),
              bottomRight: Radius.circular(3),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [t.surfaceRaised, t.surfaceSunken, t.borderStrong],
              stops: const [0, 0.55, 1],
            ),
            border: Border(
              // literal-ok: the ledge's lit top edge — a white scrim
              top: BorderSide(color: Color(dark ? 0x14FFFFFF : 0x66FFFFFF)),
            ),
            boxShadow: const [
              BoxShadow(
                // literal-ok: the ledge's cast shadow — ink-700 under alpha
                color: Color(0x6614171F),
                offset: Offset(0, 12),
                blurRadius: 20,
                spreadRadius: -10,
              ),
            ],
          ),
        ),
        if (open != null)
          KitBookDetail(book: open, onClose: () => onOpen(null)),
      ],
    );
  }
}

/// `ShelfView` — a library's volumes as shelves: one ledge in the chosen
/// order, or one per kind under the `type` sort. Holds which book is pulled,
/// and drops it when that book leaves [items].
class KitShelfView extends StatefulWidget {
  final List<KitBook> items;

  /// `recent` (the order given) · `title` · `passages` · `type` (grouped).
  final String sort;

  /// Override the grouping [sort] implies.
  final bool? grouped;
  final bool bare;

  /// The single ledge's label; defaults to what the order is called.
  final String? label;

  const KitShelfView({
    super.key,
    required this.items,
    this.sort = 'recent',
    this.grouped,
    this.bare = false,
    this.label,
  });

  @override
  State<KitShelfView> createState() => _KitShelfViewState();
}

const _shelfOrderLabel = <String, String>{
  'recent': 'Recently added',
  'title': 'A to Z',
  'passages': 'Most passages',
};

class _KitShelfViewState extends State<KitShelfView> {
  String? _openId;

  @override
  void didUpdateWidget(covariant KitShelfView old) {
    super.didUpdateWidget(old);
    if (_openId != null && !widget.items.any((b) => b.id == _openId)) {
      _openId = null;
    }
  }

  List<KitBook> _ordered(List<KitBook> list) {
    final a = [...list];
    if (widget.sort == 'title') {
      a.sort(
        (x, y) => x._title.toLowerCase().compareTo(y._title.toLowerCase()),
      );
    } else if (widget.sort == 'passages') {
      a.sort((x, y) => y.passages.compareTo(x.passages));
    }
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final byKind = widget.grouped ?? widget.sort == 'type';
    final groups = byKind
        ? [
            for (final g in kShelfGroups)
              (
                label: g.label,
                books: _ordered(
                  widget.items.where((b) => b.kind == g.id).toList(),
                ),
              ),
          ].where((g) => g.books.isNotEmpty).toList()
        : [
            (
              label:
                  widget.label ??
                  _shelfOrderLabel[widget.sort] ??
                  'On the shelf',
              books: _ordered(widget.items),
            ),
          ];

    if (groups.isEmpty || groups.first.books.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
        child: Center(
          child: Text(
            'Nothing on this shelf yet.',
            style: KitText.lede(
              context,
              fontSize: 15,
              height: 22,
            ).copyWith(color: t.fgSubtle),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) const SizedBox(height: 30),
            KitShelfUnit(
              label: groups[i].label,
              books: groups[i].books,
              openId: _openId,
              onOpen: (id) => setState(() => _openId = id),
              bare: widget.bare,
            ),
          ],
        ],
      ),
    );
  }
}

/// `.src-card` — a volume as a card (the Sources card view): the plate, the
/// kind in mono caps, the unread dot and the date; the serif title (two
/// lines); the shelf; a ruled foot with the shelf and the passage count in
/// the accent. A §6.4.3 link.
class KitSourceCard extends StatefulWidget {
  final KitBook book;

  /// The kind as the reference's `KIND_NAME` spells it (`PDFs`, `Web clips`).
  final String kindLabel;

  /// The row's date string (the screen owns the date format).
  final String date;

  const KitSourceCard({
    super.key,
    required this.book,
    required this.kindLabel,
    required this.date,
  });

  @override
  State<KitSourceCard> createState() => _KitSourceCardState();
}

class _KitSourceCardState extends State<KitSourceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final b = widget.book;
    final shelf = b.shelf ?? 'Unshelved';
    return KitSourceLink(
      docId: b.id,
      builder: (context, open) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: open,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 15),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: AppRadius.mdR,
              boxShadow: _hover ? AppShadows.s2 : AppShadows.s1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    KitFileBadge(b.kind, size: KitBadgeSize.card),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.kindLabel.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.mono(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: t.fgSubtle,
                        ),
                      ),
                    ),
                    if (b.viewCount == 0) ...[
                      const SizedBox(width: 11),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: t.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      widget.date,
                      style: AppTheme.mono(fontSize: 10, color: t.fgSubtle),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  b._title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 17,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  shelf,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: KitText.ui(
                    context,
                    color: t.fgMuted,
                  ).copyWith(fontSize: 13),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.only(top: 11),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: t.rule)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          shelf,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.mono(
                            fontSize: 10,
                            letterSpacing: 0.4,
                            color: t.fgSubtle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${b.passages} passage${b.passages == 1 ? '' : 's'}',
                        style: AppTheme.mono(
                          fontSize: 10.5,
                          color: t.accentText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// `.src-cards` — `repeat(auto-fill, minmax(232px, 1fr))`, gap 16; two
/// columns (gap 12) at 720 and one at 460, as the reference's breakpoints.
class KitSourceCardGrid extends StatelessWidget {
  final List<Widget> cards;

  const KitSourceCardGrid({super.key, required this.cards});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = MediaQuery.sizeOf(context).width;
      final gap = w <= 720 ? 12.0 : 16.0;
      final cols = w <= 460
          ? 1
          : w <= 720
          ? 2
          : math.max(1, ((c.maxWidth + gap) / (232 + gap)).floor());
      final cell = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final card in cards) SizedBox(width: cell, child: card),
        ],
      );
    },
  );
}
