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

/// A shelf page whose shelves could not be read says so (INV-24, 5.37.1).
///
/// A failed tags read leaves the list empty, so the shelf is not in it, and
/// the page said "Shelf not found · This shelf may have been deleted" — a
/// claim about a list it never received. Both directions: a read that
/// SUCCEEDED without the shelf is still "not found".
class _Tags extends TagsNotifier {
  _Tags(this.failure);
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

class _Docs extends DocumentsNotifier {
  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  List<Document> get complete => const [];
}

Future<void> _open(WidgetTester tester, String? failure) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<TagsNotifier>(create: (_) => _Tags(failure)),
      ChangeNotifierProvider<DocumentsNotifier>(create: (_) => _Docs()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ShelfPage(shelfId: 's1')),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('a failed read is a failure, not a deleted shelf', (tester) async {
    await _open(tester, 'Missing or insufficient permissions.');
    expect(find.byType(KitFailureBlock), findsOneWidget);
    expect(find.text('This shelf could not be read.'), findsOneWidget);
    expect(find.text('Shelf not found'), findsNothing);
  });

  testWidgets('a read without the shelf is still not found', (tester) async {
    await _open(tester, null);
    expect(find.text('Shelf not found'), findsOneWidget);
    expect(find.byType(KitFailureBlock), findsNothing);
  });
}
