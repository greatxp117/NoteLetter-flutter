import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';

/// The section break, and the package default underneath it.
///
/// `<hr>` has been in the extraction vocabulary since contract 1.1.0 and no
/// stored chunk contained one until 4.26.0 (ADR-063) — five sources emitted it
/// and the chunker dropped every one. Now that it arrives, something has to
/// draw it, and flutter_html's default is `border: Border.all()`: a black box
/// on all four sides. Black does not flip, so on the dark `--surface` it is a
/// line nobody can see, and in light it is a hard rectangle where the web
/// reference draws a 6%-ink hairline.
///
/// Nothing would have failed. The rule renders, in a colour from a package.
void main() {
  test('the section rule is --rule, in both themes, and a hairline', () {
    for (final t in [Tokens.light, Tokens.dark]) {
      final hr = AppTheme.htmlStyles(t)['hr'];
      expect(hr, isNotNull, reason: 'no style for <hr> at all');
      final border = hr!.border!;
      expect(border.top.color, t.rule);
      // A rule, not a box: the other three sides must be none, or the black
      // default comes back on three of them.
      expect(border.bottom.style, BorderStyle.none);
      expect(border.left.style, BorderStyle.none);
      expect(border.right.style, BorderStyle.none);
    }
    expect(AppTheme.htmlStyles(Tokens.light)['hr']!.border!.top.color,
        isNot(AppTheme.htmlStyles(Tokens.dark)['hr']!.border!.top.color),
        reason: 'a rule that is the same colour in both themes is a raw step');
  });

  test('every Html() in the app passes the shared style map', () {
    // The colour is only half of it: a call site that passes no `style:` takes
    // the package default and is invisible to the test above. Read the source,
    // the way the token gates read the CSS.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      // Comments included the doc comment on the helper itself, which names
      // `Html()` in prose — a test that fails on its own documentation is a
      // test people delete.
      final src = f.readAsStringSync()
          .replaceAll(RegExp(r'^\s*///?.*$', multiLine: true), '');
      for (final m in RegExp(r'\bHtml\(').allMatches(src)) {
        final call = src.substring(m.start, (m.start + 400).clamp(0, src.length));
        if (!call.contains('AppTheme.htmlStyles')) {
          final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
          offenders.add('${f.path}:$line');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'these render chunk html with flutter_html\'s own <hr>: '
            '${offenders.join(', ')}');
  });
}
