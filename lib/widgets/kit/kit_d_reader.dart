import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/document.dart';
import '../../models/tag.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'kit_controls.dart';
import 'kit_d_covers.dart';
import 'kit_d_frame.dart';
import 'kit_d_parts.dart';
import 'kit_failure.dart';
import 'kit_text.dart';

// ── Direction D: the source page's own parts (`screens/reader.md`
// §Composition; web `pages/ReaderView.jsx` and the D block at the head of
// `styles/app-source.css`) ─────────────────────────────────────────────────
//
// They are the reader's alone — no other page draws an identity block, a
// reading-progress rule or a wrapping section — but a page file never styles
// its own type (ADR-041), so they live here, beside Home's and the Library's
// (kit_d_home.dart, kit_d_library.dart).

/// The sheet's **identity block**: a 52px §33 cover in the shelf's cloth (the
/// unshelved cloth without one), the kind and shelf in mono caps
/// (`{kind} · {shelf}`, 10.5/`0.14em` `--accent-text`), the title in serif 600
/// 17/22 on two lines at most; a `--rule` 18 under it. It is where a cover
/// tapped in a listing lands. The running head does not draw it (the
/// masthead above says it), so inside the dropped sheet it is nothing.
class KitReaderIdentity extends StatelessWidget {
  final Document doc;

  /// The document's first shelf; null is *Unshelved* and the unshelved cloth
  /// the listings draw.
  final Tag? shelf;

  const KitReaderIdentity({super.key, required this.doc, this.shelf});

  @override
  Widget build(BuildContext context) {
    if (KitSheetScope.maybeOf(context)?.dock ?? false) {
      return const SizedBox.shrink();
    }
    final t = Tokens.of(context);
    final title = doc.title.isEmpty ? 'Untitled' : doc.title;
    final kind = kitTypeLabel(doc.type);
    final cloth = shelf == null
        ? null
        : AppColors.shelfColor(
            shelf!.color,
            dark: t.isDark,
          ); // pair-ok: a shelf's stored colour is a fixed data token
    return Container(
      key: const ValueKey('rx-identity'),
      padding: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: KitCover(doc: doc, shelf: cloth),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$kind · ${shelf?.title ?? 'Unshelved'}'.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(
                    fontSize: 10.5,
                    letterSpacing: 0.14 * 10.5,
                    color: t.accentText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.serif(
                    fontSize: 17,
                    height: 22 / 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.01 * 17,
                    color: t.fg,
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

/// The sheet's first label after the identity block (*In this volume*): 22
/// under the block on the page, flush at the top of the dropped running head,
/// where the block is not drawn.
class KitReaderSheetLabel extends StatelessWidget {
  final String text;
  const KitReaderSheetLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final dock = KitSheetScope.maybeOf(context)?.dock ?? false;
    return KitDLabel(text, first: dock, top: 22);
  }
}

/// The running head's line while the source is read: *In this volume* in
/// `--fg-muted` (web `.d-peek-t.d-peek-wait`).
class KitPeekWait extends StatelessWidget {
  final String text;
  const KitPeekWait(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppTheme.serif(
      fontSize: 16.5,
      height: 22 / 16.5,
      fontWeight: FontWeight.w600,
      color: Tokens.of(context).fgMuted,
      opsz: 18,
    ),
  );
}

/// The byline in the masthead's byline slot (`screens/reader.md` §Header):
/// author · publish date · source host · reading time, each optional, the
/// row absent when none apply. The standfirst's italic serif — 20/30
/// `--fg-lede` (17/26 on a phone), 14 under the title; the author in `--fg`
/// 500, the host in `--accent-text` with its external glyph, the only part
/// that links (to `source_url`).
class KitReaderByline extends StatelessWidget {
  final String? author;
  final String? published;
  final String? host;
  final VoidCallback? onSource;
  final String? readingTime;

  const KitReaderByline({
    super.key,
    this.author,
    this.published,
    this.host,
    this.onSource,
    this.readingTime,
  });

  bool get isEmpty =>
      author == null &&
      published == null &&
      host == null &&
      readingTime == null;

  @override
  Widget build(BuildContext context) {
    if (isEmpty) return const SizedBox.shrink();
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    final base = AppTheme.serif(
      fontSize: phone ? 17 : 20,
      height: (phone ? 26 : 30) / (phone ? 17 : 20),
      fontStyle: FontStyle.italic,
      color: t.fgLede,
    );
    final parts = <InlineSpan>[];
    void add(InlineSpan s) {
      if (parts.isNotEmpty) {
        parts.add(
          TextSpan(
            text: '  ·  ',
            style: base.copyWith(color: t.fgSubtle),
          ),
        );
      }
      parts.add(s);
    }

    if (author != null) {
      add(
        TextSpan(
          text: author,
          style: base.copyWith(color: t.fg, fontWeight: FontWeight.w500),
        ),
      );
    }
    if (published != null) add(TextSpan(text: published));
    if (host != null) {
      add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: KitDTap(
            onTap: onSource ?? () {},
            label: host,
            builder: (context, hover, focus) => Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: host),
                  const TextSpan(text: ' '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(
                      Icons.open_in_new,
                      size: 11,
                      color: t.accentText,
                    ),
                  ),
                ],
              ),
              style: base.copyWith(
                color: t.accentText,
                decoration: hover ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
      );
    }
    if (readingTime != null) add(TextSpan(text: readingTime));
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Text.rich(TextSpan(children: parts), style: base),
    );
  }
}

/// What stands under the byline: the §Source freshness banner or note, 16
/// under it (web `.rx-d .ed-mast > .import-reconnect { margin-top: 16px }`).
class KitReaderMastNote extends StatelessWidget {
  final Widget child;
  const KitReaderMastNote({super.key, required this.child});

  @override
  Widget build(BuildContext context) =>
      // The notice brings its own 12 (`source_freshness.dart`); 4 more is
      // the masthead's 16.
      Padding(padding: const EdgeInsets.only(top: 4), child: child);
}

/// Stats, then **Finish** (§Finishing a document): *Mark finished* / *Mark
/// unfinished* as a full-width SECONDARY button — the page's one brick button
/// is its action — with its note in italic serif 14/21 `--fg-lede` under it
/// and its §14.2 refusal beside it. 16 under what precedes it.
class KitReaderFinish extends StatelessWidget {
  final String label;
  final String note;
  final VoidCallback? onPressed;
  final String? error;

  const KitReaderFinish({
    super.key,
    required this.label,
    required this.note,
    this.onPressed,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KitButton(
            label,
            variant: KitButtonVariant.secondary,
            center: true,
            onPressed: onPressed,
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: AppTheme.serif(
              fontSize: 14,
              height: 21 / 14,
              fontStyle: FontStyle.italic,
              color: t.fgLede,
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            KitFailureInline(error!),
          ],
        ],
      ),
    );
  }
}

/// The opt-in detailed reading stats (`screens/reader.md` §Detailed reading
/// stats), in the sheet under the catalogue card: a rule, the eyebrow and its
/// note, then the four figures as independent facts — **never** a bar, a
/// percentage or parts summing to the total, because they overlap. *Not yet
/// reached you*, the one exclusive figure, is set apart in `--fg-subtle`.
class KitReadingBreakdown extends StatelessWidget {
  final int read;
  final int searched;
  final int lettered;
  final int untouched;

  const KitReadingBreakdown({
    super.key,
    required this.read,
    required this.searched,
    required this.lettered,
    required this.untouched,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    Widget fig(int n, String what, {bool none = false}) => Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$n ',
            style: AppTheme.serif(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: none ? t.fgSubtle : t.fg,
              opsz: 16,
            ),
          ),
          TextSpan(text: what),
        ],
      ),
      style: TextStyle(
        fontFamily: AppTheme.fontSans,
        fontSize: 13,
        color: none ? t.fgSubtle : t.fgMuted,
      ),
    );
    return Semantics(
      container: true,
      label: 'Detailed reading stats',
      child: Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 14),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: t.rule)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('How these passages reached you'),
            const SizedBox(height: 4),
            Text(
              'Ways overlap — a passage can arrive more than one way.',
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12,
                height: 1.5,
                color: t.fgSubtle,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 26,
              runSpacing: 6,
              children: [
                fig(read, 'read in the reader'),
                fig(searched, 'opened from a search'),
                fig(lettered, 'arrived in a letter'),
                fig(untouched, 'not yet reached you', none: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// The Summary's lede: serif 22/34 at most 60ch (19/30 on a phone), the
/// italic lede the panel's note is, at the size D gives the first section.
class KitSummaryLede extends StatelessWidget {
  final String text;
  const KitSummaryLede(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final phone = KitD.phone(context);
    final style = AppTheme.serif(
      fontSize: phone ? 19 : 22,
      height: (phone ? 30 : 34) / (phone ? 19 : 22),
      fontStyle: FontStyle.italic,
      color: t.fgLede,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 60 * KitText.ch(context, style)),
        child: Text(text, style: style),
      ),
    );
  }
}

/// The running head's **reading-progress rule** (`screens/reader.md`
/// §Composition, Phone): 2px of accent along the line's foot that fills as
/// the page scrolls — the scroll's own fraction, from the page's primary
/// scroller. Nothing under it: web draws no track (`.d-peek-prog`). Placed by
/// [KitDSheet.foot].
class KitReadProgress extends StatelessWidget {
  final ScrollController controller;
  const KitReadProgress({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            var f = 0.0;
            if (controller.hasClients) {
              final p = controller.position;
              if (p.hasContentDimensions && p.maxScrollExtent > 0) {
                f = (p.pixels / p.maxScrollExtent).clamp(0.0, 1.0);
              }
            }
            return Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                key: const ValueKey('rx-progress'),
                widthFactor: f,
                heightFactor: 1,
                child: ColoredBox(color: t.accent),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// One section of the source page's column (§31's SecHead that **wraps** its
/// body — web `SecD` over the kit's `SecHeadLine`): the head line, then the
/// body, at most 940 wide. A section not reached yet ([mounted] false)
/// reserves half the window and draws nothing in it — a RESERVE, not an
/// empty state — so the sections below are far enough apart to mount in turn.
/// [sectionKey] is the section's [KitSections.keyOf] key: the whole section
/// is what Contents measures and jumps to.
class KitReaderSection extends StatelessWidget {
  final GlobalKey sectionKey;
  final int n;
  final String title;
  final bool mounted;
  final Widget Function(BuildContext context) builder;

  const KitReaderSection({
    super.key,
    required this.sectionKey,
    required this.n,
    required this.title,
    required this.mounted,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final reserve = MediaQuery.sizeOf(context).height * 0.5;
    return Padding(
      padding: EdgeInsets.only(top: n == 0 ? 0 : KitSecHead.gap(context)),
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: title,
        child: Column(
          key: sectionKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KitSecHead(n: n, title: title, margin: false),
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 940,
                  minHeight: mounted ? 0 : reserve,
                ),
                child: mounted ? builder(context) : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
