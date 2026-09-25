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

/// A refused rename puts the field back (component-kit §Rules, the text-field
/// clause of *write before you move*, 4.75.2; QUEUE F-32).
///
/// The save was already pessimistic — `_savedName` moved only on success — but
/// the controller kept the refused text, so the field showed a name the shelf
/// does not have under a sentence saying it could not be saved. Both
/// directions are asserted: a revert that also fired on SUCCESS would undo
/// every rename, which is worse than no revert at all.
class _Tags extends TagsNotifier {
  _Tags(this.answer);
  final String? answer;
  final titles = <String?>[];

  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  List<Tag> get tags =>
      [Tag.fromJson('s1', {'user_id': 'u1', 'title': 'Psalms'})];

  @override
  Future<String?> updateTag(String tagId,
      {String? title,
      String? description,
      String? color,
      String? letterMode}) async {
    titles.add(title);
    return answer;
  }
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

Future<_Tags> _rename(WidgetTester tester, String? answer) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tags = _Tags(answer);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<TagsNotifier>.value(value: tags),
      ChangeNotifierProvider<DocumentsNotifier>(create: (_) => _Docs()),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: ShelfPage(shelfId: 's1')),
    ),
  ));
  await tester.pump();
  await tester.tap(find.text('Settings'));
  await tester.pump();

  final field = find.descendant(
      of: find.byType(KitTextField), matching: find.byType(TextField));
  await tester.tap(field.first);
  await tester.pump();
  await tester.enterText(field.first, 'Psalter');
  // Leave the field: the save runs on blur, as the reference's does.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.pump();
  return tags;
}

String _fieldText(WidgetTester tester) => tester
    .widget<TextField>(find.descendant(
        of: find.byType(KitTextField), matching: find.byType(TextField)).first)
    .controller!
    .text;

void main() {
  testWidgets('a refused rename reverts to the name the server holds',
      (tester) async {
    const refusal = 'A shelf called “Psalter” already exists.';
    final tags = await _rename(tester, refusal);
    expect(tags.titles, ['Psalter'], reason: 'the rename was sent');
    expect(_fieldText(tester), 'Psalms',
        reason: 'the field showed a name the shelf does not have');
    expect(
        find.descendant(
            of: find.byType(KitFailureInline), matching: find.text(refusal)),
        findsOneWidget,
        reason: 'the server\'s sentence, inline (§14.2)');
  });

  testWidgets('an accepted rename keeps the new text', (tester) async {
    final tags = await _rename(tester, null);
    expect(tags.titles, ['Psalter']);
    expect(_fieldText(tester), 'Psalter',
        reason: 'a revert that fires on success undoes every rename');
    expect(find.byType(KitFailureInline), findsNothing);
  });
}
