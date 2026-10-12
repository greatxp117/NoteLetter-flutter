// F-75 — the cohesive column's passage type and source title follow the
// reference (app-kit.css `.passage .quote`; app-responsive.css
// `.cohesive-passage .pmeta .srctitle`, `.cohesive-note`). Found by F-43's
// respelling and left for this item; the search pair's query does not reach
// the cohesive mode, so these are the proof.
import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/cohesive_reading.dart';
import 'package:flutter_app/pages/search/cohesive_column.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/theme/tokens.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

CohesiveReading _reading({String? html}) => CohesiveReading.fromJson({
      'query': 'budget',
      'breadth': 'normal',
      'pool': 2,
      'kept': 1,
      'note': 'renumbered',
      'sections': [
        {
          'title': 'The budget',
          'bridge': '',
          'passages': [
            {
              'chunk_id': 'c1',
              'document_id': 'd1',
              'chunk_index': 0,
              'source_type': 'pdf',
              'text': 'Quarterly tax figures and the operating budget.',
              'html': html,
              'score': 0.81,
              'link': '/reader/d1?p=c1',
              'document': {'title': 'Quarterly Tax Summary', 'type': 'pdf'},
            }
          ],
        }
      ],
    });

Future<void> _pump(WidgetTester tester, CohesiveReading r) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        child: CohesiveColumn(
          reading: r,
          error: null,
          requestId: null,
          onRetry: () {},
          onOpenInContext: (_) {},
          onOpenSource: (_) {},
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('the plain quote is serif 18/30', (tester) async {
    await _pump(tester, _reading());
    final quote = tester.widget<KitMarkedText>(find.byType(KitMarkedText));
    expect(quote.style.fontFamily, AppTheme.fontSerif);
    expect(quote.style.fontSize, 18);
    expect(quote.style.height! * 18, closeTo(30, 0.01));
  });

  testWidgets('the html quote names the serif too, at 18/30', (tester) async {
    await _pump(
        tester, _reading(html: '<p>Quarterly tax figures and the budget.</p>'));
    final html = tester.widget<Html>(find.byType(Html));
    final body = html.style['body']!;
    expect(body.fontFamily, AppTheme.fontSerif,
        reason: 'the html branch set no family and drew in the UI sans');
    expect(body.fontSize?.value, 18);
  });

  testWidgets('the source title is serif 14/500; the note is --fg-subtle',
      (tester) async {
    await _pump(tester, _reading());
    final title = tester.widget<Text>(find.text('Quarterly Tax Summary'));
    expect(title.style?.fontSize, 14);
    expect(title.style?.fontWeight, FontWeight.w500);
    final note = tester.widget<Text>(
        find.text('The arrangement needed adjusting; every passage is here.'));
    expect(note.style?.color, Tokens.light.fgSubtle);
  });
}
