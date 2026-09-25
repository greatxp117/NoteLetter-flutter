import 'package:flutter/material.dart';

import '../../widgets/kit/kit.dart';

/// **What can I add?** — the reference sheet the Sources add panel's section
/// header opens (`screens/sources.md` §Composition body 1: "The section header
/// carries a trailing 'What can I add?' link"; web `SourcesInfoSheet.jsx`).
///
/// Purely informational — no endpoint, no write. Its content mirrors the
/// extraction contract and URL detection, word for word with the reference, and
/// must stay truthful to them rather than aspirational: a sheet that promises a
/// kind the front door refuses is the EPUB defect again (C2b).
///
/// Composed from the kit: the §15 Overlay sheet, a Section header (§3) per
/// group with its note, and rows that are setting rows (icon plate, title,
/// description) because that is what each line is — never a new row shape.
class SourcesInfoSheet {
  SourcesInfoSheet._();

  static Future<void> show(BuildContext context) => KitOverlaySheet.show(
    context,
    icon: Icons.auto_awesome_outlined,
    title: 'What can I add?',
    subtitle: 'Every kind of source NoteLetter reads, and the clever bits.',
    width: 640,
    builder: (_) => const _Body(),
  );
}

typedef _Row = ({IconData icon, String name, String detail});

const List<_Row> _pasteLinks = [
  (
    icon: Icons.link,
    name: 'Web articles & blog posts',
    detail:
        'Full text with headings, lists, tables, quotes, and inline '
        'images preserved.',
  ),
  (
    icon: Icons.play_arrow_outlined,
    name: 'YouTube videos & playlists',
    detail:
        'The transcript, timestamped so you can jump to any moment. '
        'Playlists expand into one entry per video.',
  ),
  (
    icon: Icons.play_arrow_outlined,
    name: 'Instagram & TikTok',
    detail:
        'Captions when present; otherwise the spoken audio is transcribed '
        'automatically.',
  ),
  (
    icon: Icons.headphones_outlined,
    name: 'Podcasts — Apple Podcasts & Spotify',
    detail:
        'A timestamped transcript plus the real episode audio to play '
        'alongside it.',
  ),
];

const List<_Row> _uploadFiles = [
  (
    icon: Icons.insert_drive_file_outlined,
    name: 'PDF',
    detail:
        'Headings, tables, code, and figures — with OCR fallback for '
        'scanned pages.',
  ),
  (
    icon: Icons.insert_drive_file_outlined,
    name: 'Word documents (.docx)',
    detail: 'Headings, lists, tables, and embedded images.',
  ),
  (
    icon: Icons.insert_drive_file_outlined,
    name: 'Slide decks (.pptx)',
    detail: 'One section per slide, with the speaker notes kept and marked.',
  ),
  (
    icon: Icons.notes,
    name: 'Plain text & Markdown',
    detail: 'Decoded to clean paragraphs, with Markdown headings detected.',
  ),
  (
    icon: Icons.visibility_outlined,
    name: 'Images',
    detail:
        'Screenshots, photos of text, handwriting, and memes are read with '
        'OCR and kept as a captioned figure.',
  ),
  (
    icon: Icons.headphones_outlined,
    name: 'Audio recordings',
    detail:
        'Voice memos, lectures, and interviews are transcribed with '
        'timestamps you can play against.',
  ),
  (
    icon: Icons.play_arrow_outlined,
    name: 'Video (up to 2 GB)',
    detail:
        'Transcribed from the audio track, with timestamps. On-screen text '
        'and slides are not read.',
  ),
];

const List<_Row> _specialCases = [
  (
    icon: Icons.auto_awesome_outlined,
    name: 'A screenshot of an article becomes the article',
    detail:
        'Snap a news story and NoteLetter recognizes it, fetches the '
        'original web article for the full text, and keeps your screenshot as '
        'the lead figure.',
  ),
  (
    icon: Icons.auto_awesome_outlined,
    name: 'Publisher transcripts preferred for podcasts',
    detail:
        'When a show publishes its own transcript it is used as-is (often '
        'speaker-labeled); otherwise the episode audio is transcribed for you.',
  ),
  (
    icon: Icons.auto_awesome_outlined,
    name: 'Timestamps you can jump to',
    detail:
        'Video and podcast transcripts carry per-line timings, so the '
        'reader lets you jump straight to the moment a passage was said.',
  ),
  (
    icon: Icons.auto_awesome_outlined,
    name: 'What can’t be reached is told honestly',
    detail:
        'Spotify-exclusive podcasts and a few blocked pages can’t be '
        'fetched — those show a clear error instead of failing silently.',
  ),
];

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    Widget group(
      String title,
      String? note,
      List<_Row> rows, {
      bool first = false,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title, first: first),
        if (note != null) KitProcNote(note, padding: EdgeInsets.zero),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: 10),
          KitRowList(
            rows: [
              for (final r in rows)
                KitSettingRow(
                  icon: r.icon,
                  title: r.name,
                  description: r.detail,
                ),
            ],
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          group(
            'Paste a link',
            'Type is detected automatically — one field for all of these.',
            _pasteLinks,
            first: true,
          ),
          group(
            'Upload a file',
            'Drop it in, or pick from your device. Up to 100 MB — 2 GB for '
                'video.',
            _uploadFiles,
          ),
          group(
            'Connect a service',
            'Import and keep in sync from your cloud: Google Drive, '
                'OneDrive, Notion and Dropbox.',
            const [],
          ),
          group('Smart handling', null, _specialCases),
        ],
      ),
    );
  }
}
