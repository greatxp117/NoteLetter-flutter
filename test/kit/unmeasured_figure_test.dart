import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/tags/shelf_page.dart';
import 'package:flutter_app/state/documents_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// The call-site half of component-kit §8's unmeasured figure (4.75.0,
/// ADR-109; QUEUE F-31). The kit's half — null draws the dash, `0` draws `0` —
/// is in `kit_smoke_test.dart`; this asserts that a screen counting out of a
/// refused or unarrived documents read actually PASSES null. The web
/// reference's frame of the defect is `reader-error.web.light.png`: a §14
/// block and three confident zeros in one picture.
class _Tags extends TagsNotifier {
  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  List<Tag> get tags =>
      [Tag.fromJson('s1', {'user_id': 'u1', 'title': 'Psalms'})];
}

class _Docs extends DocumentsNotifier {
  _Docs({this.fail, this.arrived = true});
  final String? fail;
  final bool arrived;

  @override
  void start() {}
  @override
  bool get loading => !arrived;
  @override
  String? get error => fail;
  @override
  List<Document> get complete => const [];
}

Future<void> _pump(WidgetTester tester, _Docs docs) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<TagsNotifier>(create: (_) => _Tags()),
      ChangeNotifierProvider<DocumentsNotifier>.value(value: docs),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ShelfPage(shelfId: 's1')),
    ),
  ));
  await tester.pump();
}

/// The sheet's Figures, *The shelf* (kit §29): Volumes, Passages, Span, In
/// your letter — a value the read did not measure is the dash (ADR-109).
List<String> _figures(WidgetTester tester) => [
      for (final r in tester
          .widget<KitFigures>(find.byWidgetPredicate(
              (w) => w is KitFigures && w.label == 'The shelf'))
          .rows)
        r.$2
    ];

void main() {
  testWidgets('a refused documents read draws the shelf figures unmeasured',
      (tester) async {
    await _pump(tester, _Docs(fail: 'Missing or insufficient permissions.'));
    final f = _figures(tester);
    expect(f.take(3), ['—', '—', '—'],
        reason: 'Volumes, Passages and Span are counted out of the read '
            'that failed');
    expect(f[3], 'Mixed',
        reason: '"In your letter" is the shelf\'s own stored mode');
    // The folio's counts are the same measurements.
    expect(find.text('SHELF\u00a0· — VOLUMES\u00a0· — PASSAGES'), findsOneWidget);
  });

  testWidgets('a read that has not arrived is not zero either',
      (tester) async {
    await _pump(tester, _Docs(arrived: false));
    // Direction D: until both reads answer the shelf page is its skeleton —
    // the frame with no figure in it at all, never a zero.
    expect(find.byType(KitFigures), findsNothing);
    expect(find.byType(KitSkeletonLines), findsWidgets);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('an empty shelf that WAS read keeps its zeros', (tester) async {
    await _pump(tester, _Docs());
    expect(_figures(tester).take(2), ['0', '0'],
        reason: 'an empty shelf is a measurement; `?? null` everywhere would '
            'pass the two tests above');
  });
}
