/// F-201 — a shelved source is never *Unshelved* under a refused tags read
/// (INV-24, ADR-071; web d534372: shared/shelvesRead.js `noShelfWord`,
/// ShelfTag, RegisterRow, Catalogue, Cover, ReaderView, CloudImportPanel;
/// tests/contract/shelf-word-refused.test.js).
///
/// The DOCUMENT says whether it is shelved; the tags read only NAMES the
/// shelf. So while that read is refused, a source carrying `tag_ids` is a
/// dash, like any figure nobody read — and a source on none is still
/// *Unshelved*, because the document says so. F-196 said it on the loaded
/// reader's folio and identity; every other surface naming a source's shelf
/// said *Unshelved*: the reader's loading masthead, §35's tag (so §32's row
/// and an import row), the Grid wall's caption and Home's cover strip.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/document.dart';
import 'package:flutter_app/models/tag.dart';
import 'package:flutter_app/pages/reader_page.dart' show readerLoadingFolio;
import 'package:flutter_app/shared/shelf_pick.dart' show noShelfWord;
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';
import 'package:flutter_app/widgets/shelves_read_scope.dart';

const _denied = 'NoteLetter could not read this. Sign out and back in, or '
    'contact support.';

/// The tags read as the test says it is: [failure] a refusal (§14.3's
/// sentence, as TagsNotifier stores it).
class _Tags extends TagsNotifier {
  _Tags({this.failure});
  final String? failure;

  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => failure;
  @override
  List<Tag> get tags => const [];
}

Document _doc(String id, List<String> tags) => Document.fromJson(id, {
      'user_id': 'u1',
      'title': 'Stew $id',
      'type': 'url',
      'status': 'complete',
      'chunk_count': 4,
      'tag_ids': tags,
      'created_at': DateTime(2026, 11, 1).millisecondsSinceEpoch,
    });

final _shelved = _doc('s1', const ['t9']);
final _loose = _doc('l1', const []);

Future<void> _host(WidgetTester tester, String? failure, Widget child) async {
  tester.view.physicalSize = const Size(1100, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<TagsNotifier>.value(
      value: _Tags(failure: failure),
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => ShelvesReadScope(child: child!),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// The word each §35 tag drew (its own Semantics label: the tag paints its
/// text, and a register row merges its cells into the link's one node).
List<String> _tagWords(WidgetTester tester) => [
      for (final e in find
          .descendant(
            of: find.byType(KitShelfTag),
            matching: find.byType(Semantics),
          )
          .evaluate())
        (e.widget as Semantics).properties.label!,
    ];

void main() {
  group("noShelfWord: the document says shelved, the read only names", () {
    test('refused + shelved → —; refused + on none → Unshelved; answered → '
        'Unshelved', () {
      expect(noShelfWord(_shelved, true), '—');
      expect(noShelfWord(_loose, true), 'Unshelved');
      expect(noShelfWord(_shelved, false), 'Unshelved');
      expect(noShelfWord(null, true), 'Unshelved');
    });
  });

  group("the reader's loading masthead under a refused tags read", () {
    final pasta = Tag(id: 't9', userId: 'u', title: 'Pasta', color: 'sage-500');

    Future<String> folio(
      WidgetTester tester,
      String? failure,
      Document row,
      Tag? shelf,
    ) async {
      late String out;
      await _host(
        tester,
        failure,
        Builder(builder: (context) {
          out = readerLoadingFolio(context, row, shelf);
          return const SizedBox();
        }),
      );
      return out;
    }

    testWidgets('a shelved source is "—", never "Unshelved"', (tester) async {
      expect(await folio(tester, _denied, _shelved, null), '— · Web clip');
    });

    testWidgets('a source on no shelf is still "Unshelved" — the document '
        'says so, not the read', (tester) async {
      expect(await folio(tester, _denied, _loose, null), 'Unshelved · Web clip');
    });

    testWidgets('answered, it names the shelf', (tester) async {
      expect(await folio(tester, null, _shelved, pasta), 'Pasta · Web clip');
    });
  });

  group('the listings under a refused tags read', () {
    testWidgets("§32's register row: a shelved source's tag is —",
        (tester) async {
      await _host(tester, _denied, KitRegisterRow(doc: _shelved));
      expect(_tagWords(tester), ['—']);
    });

    testWidgets("§32's register row: a source on no shelf is still Unshelved",
        (tester) async {
      await _host(tester, _denied, KitRegisterRow(doc: _loose));
      expect(_tagWords(tester), ['Unshelved']);
    });

    testWidgets("§35's tag with no source to ask stays Unshelved (an answer, "
        'not a guess)', (tester) async {
      await _host(tester, _denied, const KitShelfTag());
      expect(_tagWords(tester), ['Unshelved']);
    });

    testWidgets('an import row whose source is shelved: —', (tester) async {
      await _host(
        tester,
        _denied,
        Column(children: [
          KitImportShelves(shelves: const [], doc: _shelved),
          KitImportShelves(shelves: const [], doc: _loose),
        ]),
      );
      expect(_tagWords(tester), ['—', 'Unshelved']);
    });

    testWidgets("the Grid wall's caption", (tester) async {
      await _host(tester, _denied, KitLibWall(items: [_shelved, _loose]));
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Unshelved'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('—')).dx,
        lessThan(tester.getTopLeft(find.text('Unshelved')).dx),
        reason: 'the shelved source is the first cover',
      );
    });

    testWidgets("Home's cover strip", (tester) async {
      await _host(
        tester,
        _denied,
        KitCoverStrip(items: [_shelved, _loose], homeOf: (_) => null),
      );
      expect(find.text('—'), findsOneWidget);
      expect(find.text('Unshelved'), findsOneWidget);
    });

    testWidgets('answered, every one of them is Unshelved for a source whose '
        'shelf was not found', (tester) async {
      await _host(
        tester,
        null,
        Column(children: [
          KitRegisterRow(doc: _shelved),
          KitLibWall(items: [_shelved]),
          KitCoverStrip(items: [_shelved], homeOf: (_) => null),
        ]),
      );
      expect(find.text('—'), findsNothing);
      expect(find.text('Unshelved'), findsNWidgets(2));
      expect(_tagWords(tester), ['Unshelved']);
    });
  });
}
