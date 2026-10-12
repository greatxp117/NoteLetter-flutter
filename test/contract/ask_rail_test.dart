// F-78 (4) — Ask's §9 rail on a phone is drawn over everything (the shell's
// bar and footer included), the full height of the screen, from the header's
// History link. It moved onto the ROOT overlay in ae81173 and was given the
// view's insets in 1da6a97 with analyze as its only gate; the 2026-10-12 frame
// batch found History opening nothing. This is the gate that was missing.
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
      Stream.value(const []);

  @override
  Stream<List<AskMessage>> subscribeAskMessages(String threadId) =>
      Stream.value(const []);
}

void main() {
  testWidgets('History opens the rail over the whole screen, and the scrim '
      'closes it', (tester) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FirestoreService.instance = _Threads();
    addTearDown(FirestoreService.resetInstance);

    final router = GoRouter(initialLocation: '/ask', routes: [
      GoRoute(
          path: '/ask',
          builder: (_, _) => const Scaffold(body: ChatPage())),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ChatNotifier>(create: (_) => ChatNotifier()),
        ChangeNotifierProvider<TagsNotifier>(create: (_) => StubTags()),
      ],
      child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(KitInspectorRail), findsNothing);
    await tester.tap(find.text('History'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitInspectorRail), findsOneWidget,
        reason: 'History opens §9');
    final rail = tester.getRect(find.byType(KitInspectorRail));
    expect(rail.top, 0, reason: 'top: 0, over the shell\'s bar');
    expect(rail.height, 874, reason: 'the full height of the screen');

    await tester.tapAt(const Offset(390, 400)); // the scrim, right of the rail
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(KitInspectorRail), findsNothing,
        reason: 'the backdrop closes on press');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
