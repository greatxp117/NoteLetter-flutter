import 'dart:async';

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

/// A shelf's place in the letter (4.88.0, ADR-122; QUEUE F-19).
///
/// Until 4.88.0 the reference's switch and Lead/Mixed picker stored nothing:
/// the letter never read them and a reload put them back. What this pins is
/// the write-before-move half — the controls draw the STORED value, are
/// disabled while `fn_update_tag` is out, stay put on a refusal with the
/// server's sentence beside them, and move only when the subscription carries
/// the accepted value back.
class _Tags extends TagsNotifier {
  _Tags(this._shelf);
  Tag _shelf;
  final calls = <String?>[];
  Completer<String?>? pending;

  @override
  void start() {}
  @override
  bool get loading => false;
  @override
  String? get error => null;
  @override
  List<Tag> get tags => [_shelf];

  @override
  Future<String?> updateTag(String tagId,
      {String? title,
      String? description,
      String? color,
      String? letterMode}) async {
    calls.add(letterMode);
    pending = Completer<String?>();
    final err = await pending!.future;
    if (err == null && letterMode != null) {
      // The subscription carrying the accepted value back (INV-02).
      _shelf = Tag(
          id: _shelf.id,
          userId: 'u1',
          title: _shelf.title,
          letterMode: letterMode);
      notifyListeners();
    }
    return err;
  }
}

class _Docs extends DocumentsNotifier {
  @override
  void start() {}
  @override
  List<Document> get complete => const [];
  @override
  String? get error => null;
}

Future<_Tags> _pump(WidgetTester tester, {String? mode}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tags = _Tags(Tag.fromJson('s1', {
    'user_id': 'u1',
    'title': 'Psalms',
    if (mode != null) 'letter_mode': mode,
  }));
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
  return tags;
}

final _weight = find.byKey(const ValueKey('shelf-letter-weight'));

bool _switchOn(WidgetTester tester) =>
    tester.widget<KitSwitch>(find.byType(KitSwitch)).value;

void main() {
  testWidgets('reads the stored mode — absent and unknown read as Mixed',
      (tester) async {
    await _pump(tester, mode: 'muted');
    expect(_switchOn(tester), isFalse);
    expect(find.text('This shelf is muted — its passages stay out of your letter.'),
        findsOneWidget);
    expect(_weight, findsNothing);   // no weight while muted
    expect(find.text('Muted'), findsOneWidget);          // the stat

    await _pump(tester);
    expect(_switchOn(tester), isTrue);
    expect(tester.widget<KitSegmented>(_weight).selected, 1);

    await _pump(tester, mode: 'loud');
    expect(tester.widget<KitSegmented>(_weight).selected, 1);
  });

  testWidgets('a refused mute keeps the switch on and says why',
      (tester) async {
    final tags = await _pump(tester, mode: 'lead');
    await tester.tap(find.byType(KitSwitch));
    await tester.pump();

    // In flight: the stored value, and both controls disabled.
    expect(tags.calls, ['muted']);
    expect(_switchOn(tester), isTrue);
    expect(tester.widget<KitSwitch>(find.byType(KitSwitch)).onChanged, isNull);
    expect(tester.widget<KitSegmented>(_weight).onChanged,
        isNull);

    tags.pending!.complete('letter_mode must be one of: lead, mixed, muted');
    await tester.pump();
    await tester.pump();
    expect(_switchOn(tester), isTrue);
    expect(find.text('letter_mode must be one of: lead, mixed, muted'),
        findsOneWidget);
    expect(tester.widget<KitSegmented>(_weight).selected, 0);
  });

  testWidgets('an accepted choice moves only once the write resolves',
      (tester) async {
    final tags = await _pump(tester);
    await tester.tap(find.text('Lead'));
    await tester.pump();
    expect(tags.calls, ['lead']);
    expect(tester.widget<KitSegmented>(_weight).selected, 1);

    tags.pending!.complete(null);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<KitSegmented>(_weight).selected, 0);
    expect(find.text('often opens your letter'), findsOneWidget);
    expect(find.byType(KitFailureInline), findsNothing);
  });
}
