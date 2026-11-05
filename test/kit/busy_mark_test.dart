// Component kit §6.1 State — Busy (ADR-237): a control whose own request is in
// flight draws one mark, from one view, and only the control that was pressed.
// Grey alone read as a hung app (Xavier, 2026-11-05).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/pages/reader/supersession_confirm.dart';
import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {bool reducedMotion = false}) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reducedMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  ));
}

void main() {
  group('the view', () {
    testWidgets('turns, and stops turning under reduced motion', (tester) async {
      await _pump(tester, const KitBusyMark(color: Color(0xFF000000)));
      final moving = tester.widget<RotationTransition>(find.descendant(of: find.byType(KitBusyMark), matching: find.byType(RotationTransition)));
      final at = moving.turns.value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(moving.turns.value, isNot(at), reason: 'a mark that does not move is the hang it replaces');

      await _pump(tester, const KitBusyMark(color: Color(0xFF000000)), reducedMotion: true);
      final held = tester.widget<RotationTransition>(find.descendant(of: find.byType(KitBusyMark), matching: find.byType(RotationTransition)));
      final still = held.turns.value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(held.turns.value, still);
      expect(find.byType(KitBusyMark), findsOneWidget, reason: 'it stays drawn');
    });

    testWidgets('says nothing to a screen reader', (tester) async {
      await _pump(tester, const KitBusyMark(color: Color(0xFF000000)));
      expect(find.byType(ExcludeSemantics), findsWidgets);
    });
  });

  group('KitButton', () {
    testWidgets('busy holds it and takes the glyph\'s place', (tester) async {
      var pressed = 0;
      await _pump(tester, KitButton.primary('Saving…',
          icon: Icons.check, busy: true, onPressed: () => pressed++));
      expect(find.byType(KitBusyMark), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      await tester.tap(find.byType(KitButton));
      expect(pressed, 0, reason: 'held whatever onPressed says');
    });

    testWidgets('a trailing glyph stays: the mark leads', (tester) async {
      await _pump(tester, const KitButton.primary('Saving…',
          icon: Icons.arrow_forward, iconTrailing: true, busy: true));
      expect(find.byType(KitBusyMark), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('held for another reason draws no mark', (tester) async {
      await _pump(tester, const KitButton.primary('Save'));
      expect(find.byType(KitBusyMark), findsNothing);
      await _pump(tester, KitButton.primary('Send now', wait: 42, onPressed: () {}));
      expect(find.byType(KitBusyMark), findsNothing, reason: 'a cooldown is not a request');
    });
  });

  group('the other kit controls', () {
    final cases = <String, Widget>{
      'link': const KitSettingLink('Reconnecting…', icon: null, busy: true),
      'row action': const KitLibAct('Connecting…', busy: true),
      'hx link': const KitHxLink('Load more', busy: true),
      'also': const SizedBox(width: 240, child: KitAlsoButton('Asking…', icon: Icons.title, busy: true)),
      'icon': const KitIconButton(Icons.refresh, busy: true),
      'pill': const KitDayPill('Import', on: false, busy: true),
      'switch': const KitSwitch(value: true, busy: true),
      'tag': KitTag('Folder', onRemove: () {}, removeBusy: true),
    };
    cases.forEach((name, control) {
      testWidgets('$name draws the mark', (tester) async {
        await _pump(tester, control);
        expect(find.byType(KitBusyMark), findsOneWidget);
      });
    });

    testWidgets('a chosen chip gives its tick to the mark, not both', (tester) async {
      await _pump(tester, const KitChoiceChip('My notes', on: true, busy: true));
      expect(find.byType(KitBusyMark), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('a pressed-by-nobody control draws nothing', (tester) async {
      await _pump(tester, const Column(children: [
        KitSettingLink('Reconnect', icon: null),
        KitLibAct('Connect'),
        KitHxLink('Load more'),
        KitIconButton(Icons.refresh),
        KitDayPill('Import', on: false),
        KitSwitch(value: true),
      ]));
      expect(find.byType(KitBusyMark), findsNothing);
    });
  });

  group("§34's slide switch knows which option was pressed", () {
    Widget host(ValueNotifier<bool> held, {required bool holds}) =>
        ValueListenableBuilder<bool>(
          valueListenable: held,
          builder: (context, h, _) => KitSlideSwitch<String>(
            label: 'How often',
            value: 'daily',
            held: h,
            onChanged: (_) {
              if (holds) held.value = true;
            },
            options: const [
              KitSlideOption('daily', 'Daily'),
              KitSlideOption('weekly', 'Weekly'),
              KitSlideOption('monthly', 'Monthly'),
            ],
          ),
        );

    Finder markIn(String label) => find.descendant(
        of: find.ancestor(of: find.text(label), matching: find.byType(Row)).first,
        matching: find.byType(KitBusyMark));

    testWidgets('the one pressed, for as long as it is held', (tester) async {
      final held = ValueNotifier(false);
      await _pump(tester, host(held, holds: true));
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      expect(find.byType(KitBusyMark), findsOneWidget);
      expect(markIn('Weekly'), findsOneWidget);
      expect(markIn('Monthly'), findsNothing);
      held.value = false;
      await tester.pump();
      expect(find.byType(KitBusyMark), findsNothing);
    });

    testWidgets('a local choice that holds nothing leaves nothing behind',
        (tester) async {
      final held = ValueNotifier(false);
      await _pump(tester, host(held, holds: false));
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(KitBusyMark), findsNothing);
      // A later hold from elsewhere is not this press.
      held.value = true;
      await tester.pump();
      expect(find.byType(KitBusyMark), findsNothing);
    });
  });

  testWidgets('a control that left while its confirm was open does not throw',
      (tester) async {
    final show = ValueNotifier(true);
    final asked = <bool>[];
    await _pump(tester, ValueListenableBuilder<bool>(
      valueListenable: show,
      builder: (context, on, _) => on
          ? Builder(builder: (rowContext) => KitButton('Retry', onPressed: () {
              SupersessionConfirm.run(rowContext,
                  docId: 'd',
                  title: 'Retry?',
                  lead: 'It goes again.',
                  confirmLabel: 'Retry',
                  // Owed, so the confirm opens.
                  editCheck: (_) async => true,
                  studyCheck: (_) async => false,
                  onAsking: asked.add,
                  action: () async => null);
            }))
          : const SizedBox.shrink(),
    ));
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked, [true]);
    // A snapshot takes the row away behind the open panel, and the reader keeps it.
    show.value = false;
    await tester.pump();
    await tester.tap(find.text('Keep it as it is'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(asked, [true], reason: 'nothing left to tell: this used to setState a disposed row');
    expect(tester.takeException(), isNull);
  });

  testWidgets("§18's confirm marks its confirming button, not its Cancel",
      (tester) async {
    await _pump(tester, Builder(builder: (context) => KitButton('Open',
        onPressed: () => KitConfirm.show(context,
            title: 'Delete?',
            body: 'Gone.',
            confirmLabel: 'Delete',
            cancelLabel: 'Keep',
            busyLabel: 'Deleting…',
            onConfirm: () async {
              await Future<void>.delayed(const Duration(milliseconds: 500));
              return null;
            }))));
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Delete'));
    await tester.pump();
    final marks = find.byType(KitBusyMark);
    expect(marks, findsOneWidget);
    expect(find.ancestor(of: marks, matching: find.widgetWithText(KitButton, 'Keep')), findsNothing);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
