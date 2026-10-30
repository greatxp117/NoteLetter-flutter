// Ask's conversations on a phone (direction D, F-143; screens/ask.md
// §Composition, kit §9 note and §30): the §9 rail is no longer an overlay
// reached from a *History* link — it is the page's sheet, and on a phone its
// RUNNING HEAD: one line under the app header (the history glyph,
// *Conversations* or the open title, the count), which drops the list down
// from itself, and which the scrim, or choosing *New conversation* or an
// entry, folds.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/models/ask_thread.dart';
import 'package:flutter_app/pages/chat_page.dart';
import 'package:flutter_app/services/firestore_service.dart';
import 'package:flutter_app/state/chat_notifier.dart';
import 'package:flutter_app/state/tags_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

import 'sources_harness.dart' show StubTags;

class _Threads extends FirestoreService {
  _Threads() : super.stub();

  @override
  Stream<List<AskThread>> subscribeAskThreads({int limit = 100}) =>
      Stream.value([
        AskThread(
          id: 't1',
          title: 'What did I read about grace?',
          preview: 'and about mercy?',
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ]);

  @override
  Stream<List<AskMessage>> subscribeAskMessages(String threadId) =>
      Stream.value(const []);
}

void main() {
  testWidgets('the running head drops the conversations, and the scrim and '
      'New conversation fold them', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FirestoreService.instance = _Threads();
    addTearDown(FirestoreService.resetInstance);
    KitPageTools.instance.reset();

    final router = GoRouter(initialLocation: '/ask', routes: [
      GoRoute(
          path: '/ask', builder: (_, _) => const Scaffold(body: ChatPage())),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
        ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await settle();

    expect(find.text('History'), findsNothing, reason: 'the pre-D link');
    expect(find.byType(KitInspectorRail), findsNothing,
        reason: 'no overlay rail in D');
    final peek = find.byKey(const ValueKey('d-peek'));
    expect(peek, findsOneWidget);
    expect(find.descendant(of: peek, matching: find.text('Conversations')),
        findsOneWidget);
    expect(find.descendant(of: peek, matching: find.text('1')),
        findsOneWidget, reason: 'the count of conversations');
    expect(tester.getRect(peek).top, 0, reason: 'fixed at the top');

    // Folded, its body is inert.
    expect(find.text('What did I read about grace?').hitTestable(),
        findsNothing);
    await tester.tap(peek);
    await settle();
    expect(find.text('What did I read about grace?').hitTestable(),
        findsOneWidget, reason: 'tapping the line drops the sheet');

    // The scrim folds it.
    await tester.tapAt(const Offset(200, 840));
    await settle();
    expect(find.text('What did I read about grace?').hitTestable(),
        findsNothing);

    // So does choosing New conversation.
    await tester.tap(peek);
    await settle();
    await tester.tap(find.byKey(const ValueKey('ask-new')));
    await settle();
    expect(find.text('What did I read about grace?').hitTestable(),
        findsNothing, reason: 'choosing a row folds the running head');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
