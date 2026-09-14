import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

import '../../models/scripture_lookup.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/kit/kit.dart';
import 'result_card.dart' show SearchPassageAction;

/// **Verse search** (`spec/screens/search.md`, `spec/api/scripture.md`;
/// 2.28.0 / 4.9.0, ADR-027 §2 + ADR-045) — a citation read verse by verse,
/// with the passages from the reader's own library that answer it.
///
/// The shape of the answer is the **server's** to decide, not this widget's.
/// [ScriptureLookup.granularity] says whether each verse was its own query or
/// the whole citation was one; rendering per-verse passages for a
/// passage-granularity answer would pin a match to a verse it was never
/// measured against — a fabricated attribution, and one nothing about the
/// screen would look wrong for. So this reads the field; it never infers it.
///
/// The library matches are **one merged list** (4.9.0): the primary citation's
/// and the parallels', in the order the server returned them. Deliberately not
/// re-sorted — the two groups' distances come from different queries and do not
/// share a scale, so a client-side re-rank would present two rankings as one.
/// Every row names what it answered, which is what makes the merge safe rather
/// than a lie.
class ScriptureResults extends StatelessWidget {
  final ScriptureLookup data;
  final void Function(String documentId) onOpenSource;

  const ScriptureResults({
    super.key,
    required this.data,
    required this.onOpenSource,
  });

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final withText = data.verses.where((v) => v.text != null).length;
    final edition = data.edition ?? 'Public domain';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Head(data: data, edition: edition),

        // Said once, plainly: these words are not the reader's own edition.
        if (withText > 0) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.menu_book_outlined,
                  size: 13,
                  color: t.accentText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Verse text is $edition — your own notes and books are '
                  'what’s matched against it.',
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 12,
                    height: 18 / 12,
                    color: t.fgSubtle,
                  ),
                ),
              ),
            ],
          ),
        ],

        // Where else scripture tells this (4.9.0, ADR-045). The relation and
        // the label are the BACKEND's — the reason two passages are related is
        // committed data, and a client inventing one would assert something
        // nothing measured.
        if (data.parallels.isNotEmpty) ...[
          const SizedBox(height: 14),
          _Parallels(parallels: data.parallels),
        ],

        // The passage itself, verse by verse. Matches are the merged list
        // below, so nothing hangs under a verse.
        const SizedBox(height: 6),
        for (final v in data.verses) _Verse(verse: v),

        if (data.results.isNotEmpty) ...[
          SectionHeader(
            'From your library · ${data.found + data.parallelFound} matched'
            '${data.parallels.isNotEmpty ? ' · including the parallel passages' : ''}',
          ),
          for (final p in data.results)
            _PassageCard(passage: p, onOpenSource: onOpenSource),
        ],

        if (data.results.isEmpty) ...[
          const SizedBox(height: 20),
          Text(
            data.parallels.isNotEmpty
                ? 'Nothing on your shelves answers this passage yet, or the '
                      'places it’s told again.'
                : 'Nothing on your shelves answers this passage yet.',
            style: TextStyle(
              fontFamily: AppTheme.fontSans,
              fontSize: 13,
              height: 20 / 13,
              color: t.fgSubtle,
            ),
          ),
        ],
      ],
    );
  }
}

/// The reference, its measured counts, and the edition the verse text came
/// from — closed by a `--border-strong` rule.
class _Head extends StatelessWidget {
  final ScriptureLookup data;
  final String edition;

  const _Head({required this.data, required this.edition});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final n = data.verses.length;
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.borderStrong)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.reference,
                  style:
                      AppTheme.serif(
                        fontSize: 30,
                        height: 1.05,
                        fontWeight: FontWeight.w600,
                        color: t.fg,
                      ).copyWith(
                        letterSpacing: -0.02 * 30,
                        shadows: AppShadows.letterpress,
                      ),
                ),
                const SizedBox(height: 7),
                Text(
                  '$n ${n == 1 ? 'verse' : 'verses'} · ${data.found} '
                  '${data.found == 1 ? 'passage' : 'passages'} in your library'
                  '${data.perVerse ? '' : ' · matched across the whole passage'}',
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    color: t.fgMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // The edition NoteLetter searches with — named, so a reader can see
          // whose words these are (ADR-030).
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: t.accentChipBg,
              borderRadius: AppRadius.xsR,
              border: Border.all(color: t.accentChipBorder),
            ),
            child: Text(
              edition.toUpperCase(),
              style: AppTheme.mono(
                fontSize: 10,
                letterSpacing: 0.12 * 10,
                color: t.accentChipFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Parallels extends StatelessWidget {
  final List<ScriptureParallel> parallels;

  const _Parallels({required this.parallels});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          (parallels.first.relation ?? 'Also told in').toUpperCase(),
          style: AppTheme.mono(
            fontSize: 10,
            letterSpacing: 0.1 * 10,
            color: t.fgSubtle,
          ),
        ),
        for (final p in parallels)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: t.accentChipBg,
              borderRadius: AppRadius.xsR,
              border: Border.all(color: t.accentChipBorder),
            ),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: p.reference),
                  if (p.label != null)
                    TextSpan(
                      text: ' · ${p.label}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                ],
              ),
              style: TextStyle(
                fontFamily: AppTheme.fontSans,
                fontSize: 12.5,
                color: t.accentChipFg,
              ),
            ),
          ),
      ],
    );
  }
}

/// One verse: its number in the mono face, then its text — or, where the
/// shipped edition does not carry it, a line saying so. **An absence is
/// stated, never omitted.**
class _Verse extends StatelessWidget {
  final ScriptureVerse verse;

  const _Verse({required this.verse});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final has = verse.text != null;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.rule)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              '${verse.verse}',
              textAlign: TextAlign.right,
              style: AppTheme.mono(
                fontSize: 11,
                letterSpacing: 0.06 * 11,
                color: t.accentText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              verse.text ??
                  'This verse isn’t in the edition NoteLetter '
                      'carries.',
              style: has
                  ? AppTheme.serif(
                      fontSize: 15,
                      height: 24 / 15,
                      color: t.fgMuted,
                    )
                  : AppTheme.serif(
                      fontSize: 14,
                      height: 22 / 14,
                      color: t.fgSubtle,
                    ).copyWith(fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the merged list.
///
/// [ScripturePassage.matchedReference] is **mandatory on every row and drawn
/// on every row**: the list holds the primary citation's matches and the
/// parallels' together, so without it a Luke passage reads as though it
/// answered a Matthew query — the fabricated attribution ADR-045 made data
/// precisely so that a rendering convention could not lose it.
class _PassageCard extends StatelessWidget {
  final ScripturePassage passage;
  final void Function(String documentId) onOpenSource;

  const _PassageCard({required this.passage, required this.onOpenSource});

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final p = passage;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadius.mdR,
        boxShadow: AppShadows.s1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p.title ?? 'Untitled',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: AppTheme.fontSans,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.fg,
                  ),
                ),
              ),
              if (p.documentId.isNotEmpty)
                SearchPassageAction(
                  icon: Icons.visibility_outlined,
                  label: 'Open source',
                  onTap: () => onOpenSource(p.documentId),
                ),
            ],
          ),
          if (p.matchedReference != null) ...[
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'matched '),
                  TextSpan(
                    text: p.matchedReference!,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: t.fgMuted,
                    ),
                  ),
                  if (p.isParallel && p.parallelLabel != null)
                    TextSpan(text: ' · ${p.parallelLabel}'),
                ],
              ),
              style: AppTheme.mono(
                fontSize: 10.5,
                letterSpacing: 0.03 * 10.5,
                color: t.fgSubtle,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s2),
          // `text` is the representation `[Image: …]` lives in, so a marker
          // here draws as §17.2 rather than as one of the reader's sentences.
          KitMarkedText(
            p.text,
            style: AppTheme.serif(
              fontSize: 15,
              height: 25 / 15,
              color: t.fgLede,
            ),
          ),
        ],
      ),
    );
  }
}
