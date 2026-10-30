import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:flutter_app/pages/ask/ask_off_page.dart';
import 'package:flutter_app/state/ai_settings_notifier.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

/// `/ask` while generative AI is not READ on (5.29.0, ADR-186, INV-34;
/// `screens/ask.md` §While generative AI is off; web `AskOff.jsx`, 22f9461).
void main() {
  const ask = Text('ASK ITSELF');

  Future<StreamController<Map<String, dynamic>>> pump(
    WidgetTester tester, {
    bool fail = false,
  }) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ctl = StreamController<Map<String, dynamic>>();
    addTearDown(ctl.close);
    final ai = AiSettingsNotifier(subscribe: () => ctl.stream)..start();
    await tester.pumpWidget(
      ChangeNotifierProvider<AiSettingsNotifier>.value(
        value: ai,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: AskGate(child: ask)),
        ),
      ),
    );
    // The skeleton's shine never settles: bounded pumps.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return ctl;
  }

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('unread: the frame over the kit skeleton, and nothing of Ask', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('ASK ITSELF'), findsNothing,
        reason: 'Ask must not flash before the switch is read');
    expect(find.byType(KitDPage), findsOneWidget);
    expect(find.byKey(const ValueKey('ask-off-loading')), findsOneWidget,
        reason: 'a bare masthead was the only D page with no loading state');
    expect(find.byType(KitNotice), findsNothing);
    expect(find.byType(KitFailureBlock), findsNothing);
  });

  testWidgets('off: the Notice and its one way back', (tester) async {
    final ctl = await pump(tester);
    ctl.add({'generativeAI': false});
    await frames(tester);
    expect(find.text('ASK ITSELF'), findsNothing);
    expect(find.byKey(const ValueKey('ask-off-loading')), findsNothing);
    expect(find.textContaining('Ask is off.'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('a refused read: §14.1, never Ask and never the Notice', (
    tester,
  ) async {
    final ctl = await pump(tester);
    ctl.addError(Exception('permission-denied'));
    await frames(tester);
    expect(find.text('ASK ITSELF'), findsNothing);
    expect(find.byType(KitFailureBlock), findsOneWidget);
    expect(find.textContaining('Ask is off.'), findsNothing);
  });

  testWidgets('on (absent is on): Ask itself', (tester) async {
    final ctl = await pump(tester);
    ctl.add(const {});
    await frames(tester);
    expect(find.text('ASK ITSELF'), findsOneWidget);
    expect(find.byType(KitDPage), findsNothing);
  });
}
