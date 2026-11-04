// Kit §29 (5.60.0, ADR-214; web library-d.test.js "a ready library: folio,
// Filters (Order, Kind, Shelf)"): the Library's sheet leads with its switch,
// and the shelves, the list that grows with the library, come last.
// Mutant: KitLibOrder moved back under the Shelf facet — red.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';

import 'sources_harness.dart';

Document _doc(String id, String type, {List<String> tagIds = const []}) =>
    Document(
        id: id,
        userId: 'u1',
        title: 'A $type',
        type: type,
        status: DocumentStatus.complete,
        tagIds: tagIds,
        createdAt: DateTime(2026, 11, 4).millisecondsSinceEpoch);

void main() {
  testWidgets('a ready library: Filters lead with Order, then Kind, then Shelf',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpSources(
        tester,
        SourcesStubService(
            documents: Stream.value([
          _doc('a', 'epub', tagIds: ['s1']),
          _doc('b', 'docx'),
        ])),
        shelves: const [Tag(id: 's1', userId: 'u1', title: 'Philosophy')]);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    expect(find.text('ORDER'), findsOneWidget);
    expect(y('ORDER'), lessThan(y('KIND')));
    expect(y('KIND'), lessThan(y('SHELF')));
  });
}
