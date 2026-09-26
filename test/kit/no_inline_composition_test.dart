import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A page file never styles its own type or spacing (ADR-041, F-17).
///
/// The kit (`lib/widgets/kit/`) is where a type role or a gap is spelled; a
/// page composes from it. This reads every file under `lib/pages/` and fails
/// on a `TextStyle(` or `EdgeInsets(` literal there — the two spellings by
/// which eleven screens drifted eleven ways while every other gate was green.
///
/// An exemption is a `// kit-ok: <reason>` comment on the line above the site
/// (or trailing it). It must give a reason, and it must sit on a site: a mark
/// that exempts nothing is a claim nobody is checking.
///
/// `AppTheme.serif(` and `AppTheme.mono(` are the same composition in another
/// spelling, and there were 63 of them when this landed. They are RATCHETED,
/// not forbidden: each file's count is pinned below and may only fall, and a
/// fall must be written down here in the same commit — a baseline that is
/// allowed to sit above the truth lets the next site in for free. F-43 owes
/// the conversion.
const _ratchet = <String, int>{
  'lib/pages/branding_page.dart': 9,
  'lib/pages/chat_page.dart': 1,
  'lib/pages/library/document_detail_sheet.dart': 2,
  'lib/pages/not_found_page.dart': 2,
  'lib/pages/onboarding/wizard.dart': 6,
  'lib/pages/reader_page.dart': 1,
  'lib/pages/reader/listen_panel.dart': 2,
  'lib/pages/reader/manuscript_panel.dart': 3,
  'lib/pages/reader/speed_read_panel.dart': 1,
  'lib/pages/search_page.dart': 2,
  'lib/pages/search/cohesive_column.dart': 6,
  'lib/pages/search/reading_pane.dart': 5,
  'lib/pages/search/result_card.dart': 3,
  'lib/pages/search/scripture_results.dart': 8,
  'lib/pages/search/search_field.dart': 2,
  'lib/pages/sources/organization_settings_panel.dart': 2,
  'lib/pages/sources/sync_settings_panel.dart': 3,
};

final _literal = RegExp(r'(?<![A-Za-z0-9_])(TextStyle|EdgeInsets)\(');
final _fontHelper = RegExp(r'AppTheme\.(serif|mono)\(');
final _mark = RegExp(r'kit-ok:(.*)$');

/// A mark exempts only when it says why: a bare `kit-ok:` is not a reason.
bool _reasoned(String line) {
  final m = _mark.firstMatch(line);
  return m != null &&
      m.group(1)!.replaceAll(RegExp(r'[^A-Za-z]'), '').length >= 8;
}

/// The code on a line, without a trailing `//` comment. A `//` that follows a
/// colon is a URL inside a string, not a comment.
String _code(String line) {
  final m = RegExp(r'(^|[^:])//').firstMatch(line);
  return m == null ? line : line.substring(0, m.start + m.group(1)!.length);
}

class Finding {
  final String where;
  final String what;
  Finding(this.where, this.what);
  @override
  String toString() => '$where: $what';
}

class Scan {
  final List<Finding> literals = [];
  final List<Finding> badMarks = [];
  final Map<String, int> helpers = {};
  int files = 0;
  int exempted = 0;
}

/// Scans [source] as the file [path]. Exposed so the matcher itself is tested
/// on text it must catch — a lint that reads nothing is green forever.
void scanSource(String path, String source, Scan out) {
  final lines = source.split('\n');
  final usedMarks = <int>{};
  for (var i = 0; i < lines.length; i++) {
    final code = _code(lines[i]);
    final h = _fontHelper.allMatches(code).length;
    if (h > 0) out.helpers[path] = (out.helpers[path] ?? 0) + h;
    if (!_literal.hasMatch(code)) continue;
    // The mark is on this line, or on the comment line directly above.
    int? markAt;
    if (_reasoned(lines[i])) {
      markAt = i;
    } else if (i > 0 &&
        lines[i - 1].trimLeft().startsWith('//') &&
        _reasoned(lines[i - 1])) {
      markAt = i - 1;
    }
    if (markAt == null) {
      out.literals.add(Finding('$path:${i + 1}', lines[i].trim()));
    } else {
      usedMarks.add(markAt);
      out.exempted++;
    }
  }
  for (var i = 0; i < lines.length; i++) {
    if (!_mark.hasMatch(lines[i])) continue;
    if (!_reasoned(lines[i])) {
      out.badMarks.add(Finding('$path:${i + 1}', 'kit-ok with no reason'));
    } else if (!usedMarks.contains(i)) {
      out.badMarks.add(Finding('$path:${i + 1}',
          'kit-ok exempts nothing — no TextStyle(/EdgeInsets( on or below it'));
    }
  }
}

Scan scanPages() {
  final out = Scan();
  final files = Directory('lib/pages')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final f in files) {
    out.files++;
    scanSource(f.path, f.readAsStringSync(), out);
  }
  return out;
}

void main() {
  group('the matcher', () {
    test('catches both literals, const or not, and skips kit spellings', () {
      final s = Scan();
      scanSource(
          'x.dart',
          [
            "Text('a', style: TextStyle(fontSize: 12)),",
            "Text('b', style: const TextStyle(fontSize: 12)),",
            'Padding(padding: EdgeInsets(1, 2, 3, 4)),',
            'Padding(padding: EdgeInsets.all(8)),',
            'Text(x, style: KitText.small(context)),',
            '// a comment naming TextStyle( is not a site',
            "Link(uri: 'https://x.test/TextStyle(')",
          ].join('\n'),
          s);
      expect(s.literals.map((f) => f.where),
          ['x.dart:1', 'x.dart:2', 'x.dart:3', 'x.dart:7']);
    });

    test('a mark above or on the line exempts it; a bare or idle mark fails',
        () {
      final s = Scan();
      scanSource(
          'x.dart',
          [
            '// kit-ok: a type specimen draws the raw face',
            "Text('a', style: TextStyle(fontSize: 12)),",
            "Text('b', style: TextStyle()), // kit-ok: span emphasis only here",
            '// kit-ok:',
            "Text('c', style: TextStyle()),",
            '// kit-ok: this one sits above nothing at all',
            "Text('d'),",
          ].join('\n'),
          s);
      expect(s.exempted, 2);
      expect(s.literals.map((f) => f.where), ['x.dart:5']);
      expect(s.badMarks.map((f) => f.where), ['x.dart:4', 'x.dart:6']);
    });

    test('counts the font helpers', () {
      final s = Scan();
      scanSource('x.dart',
          'a(AppTheme.serif(fontSize: 1), AppTheme.mono(fontSize: 2));', s);
      expect(s.helpers['x.dart'], 2);
    });
  });

  group('lib/pages', () {
    final scan = scanPages();

    test('was actually read', () {
      // A moved directory or a wrong cwd reads zero files and passes.
      expect(scan.files, greaterThan(40));
      expect(scan.exempted, greaterThan(0));
    });

    test('no TextStyle( or EdgeInsets( literal outside the kit', () {
      expect(scan.literals, isEmpty,
          reason: 'Compose from lib/widgets/kit/ (KitText, AppSpacing) — or, '
              'where a site truly has no kit role, mark it '
              '`// kit-ok: <reason>`:\n${scan.literals.join('\n')}');
    });

    test('every kit-ok gives a reason and exempts a site', () {
      expect(scan.badMarks, isEmpty, reason: scan.badMarks.join('\n'));
    });

    test('AppTheme.serif(/mono( only fall, and the fall is written down', () {
      final drift = <String>[];
      for (final path in {..._ratchet.keys, ...scan.helpers.keys}) {
        final pinned = _ratchet[path] ?? 0;
        final now = scan.helpers[path] ?? 0;
        if (now > pinned) {
          drift.add('$path: $now, pinned $pinned — compose from KitText');
        } else if (now < pinned) {
          drift.add('$path: $now, pinned $pinned — lower the pin to $now');
        }
      }
      expect(drift, isEmpty, reason: drift.join('\n'));
    });
  });
}
