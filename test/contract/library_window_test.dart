/// The library reads the whole library (5.58.0, ADR-211) — web
/// `tests/contract/library-window.test.js` and
/// `library-window-folios.test.js`.
///
/// The documents subscription was the newest 200 and both folios printed it
/// as the library: Xavier's 551 volumes read "200 volumes" before a 61-page
/// import and after it. The window is now 2,000, and a full window says so on
/// every count drawn from it — counted over EVERY row, not only the complete
/// ones. A Dart const cannot be mocked down as web's module is (its folio
/// test draws a window of 12), so the folios are drawn over a REAL full window
/// of 2,000 rows — slower, and it proves the production number end to end.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/pages/reader/reader_prefs.dart';
import 'package:flutter_app/shared/document_window.dart';
import 'package:flutter_app/shared/relmap_layout.dart' as relmap;
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_test/flutter_test.dart';

import 'home_harness.dart';
import 'sources_harness.dart';

/// `n` documents, the first three complete (4 passages each) and the rest
/// failed: a full window that is mostly NOT complete volumes, which is
/// exactly the case a complete-only count missed.
List<Document> _library(int n) {
  final now = DateTime(2026, 11, 4).millisecondsSinceEpoch;
  return [
    for (var i = 0; i < n; i++)
      Document(
        id: 'd$i',
        userId: 'u1',
        title: 'Source $i',
        type: 'article',
        status: i < 3 ? DocumentStatus.complete : DocumentStatus.error,
        createdAt: now - i * 1000,
        chunkCount: i < 3 ? 4 : null,
        viewCount: 1,
      ),
  ];
}

String _homeFolio(WidgetTester tester) =>
    tester.widget<KitMasthead>(find.byType(KitMasthead)).folio;

String _libraryFolio(WidgetTester tester) =>
    tester.widget<KitDPage>(find.byType(KitDPage)).folio;

void main() {
  group('the documents window (ADR-211)', () {
    test('is 2,000, one constant read by the subscription and the map', () {
      expect(documentWindow, 2000);
      expect(relmap.documentWindow, 2000,
          reason: 'the map counts inside the same window');
      final service =
          File('lib/services/firestore_service.dart').readAsStringSync();
      expect(service,
          contains('subscribeDocuments({int limit = documentWindow})'));
      // No caller sizes the window itself: a number at a call site is a
      // second opinion about the window.
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        expect(f.readAsStringSync(),
            isNot(matches(RegExp(r'subscribeDocuments\(\s*limit:\s*\d'))),
            reason: f.path);
      }
    });

    test('every label naming the window prints it with separators', () {
      // *of your most recent 2,000* — the shelves standfirst and the map's
      // legend printed the bare number, which read "2000" at the new size.
      final bare = RegExp(r'most recent \$(documentWindow|windowSize)\b');
      var labels = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = f.readAsStringSync();
        expect(src, isNot(matches(bare)), reason: f.path);
        labels += RegExp(r'most recent \$\{kitThousands\((documentWindow|windowSize)\)\}')
            .allMatches(src)
            .length;
      }
      expect(labels, 3,
          reason: 'the shelves standfirst, the map legend and the reading '
              'figures — a count that moves means a label was added or lost');
    });

    test('is full at exactly the window, over every row', () {
      expect(windowFull(_library(documentWindow - 1)), isFalse);
      expect(windowFull(_library(documentWindow)), isTrue);
      expect(windowFull(null), isFalse);
    });
  });

  group('a full window says so on both folios', () {
    testWidgets("Home's figures are floors on a full window, and totals "
        'below it', (tester) async {
      await pumpHome(tester, HomeReads(docs: _library(documentWindow)));
      expect(_homeFolio(tester), endsWith(' · 3+ sources · 12+ passages'));
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpHome(tester, HomeReads(docs: _library(documentWindow - 1)));
      expect(_homeFolio(tester), endsWith(' · 3 sources · 12 passages'));
    });

    testWidgets("the Library's volumes figure and its reading figures say a "
        'full window is one, keyed on every row; below it they are totals',
        (tester) async {
      // One test for both, because each 2,000-row pump is the cost here.
      ReaderPrefs.current.value = const ReaderPrefs(stats: true);
      addTearDown(() => ReaderPrefs.current.value = const ReaderPrefs());

      await pumpSources(tester,
          SourcesStubService(documents: Stream.value(_library(documentWindow))));
      expect(_libraryFolio(tester), 'The library · 3+ volumes · 0 shelves');
      expect(find.text('Of your most recent 2,000.'), findsOneWidget,
          reason: 'three complete volumes in a full window: the line was '
              'keyed on the complete ones alone, and missed it — and it '
              'prints the window, with separators');
      await tester.pumpWidget(const SizedBox.shrink());

      await pumpSources(
          tester,
          SourcesStubService(
              documents: Stream.value(_library(documentWindow - 1))));
      expect(_libraryFolio(tester), 'The library · 3 volumes · 0 shelves');
      expect(find.textContaining('Of your most recent'), findsNothing);
    });
  });
}
