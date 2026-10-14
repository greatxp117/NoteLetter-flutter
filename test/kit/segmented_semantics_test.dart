/// §6.8 is a named group of toggle buttons (web d35e334): the track carries
/// the name beside it and every segment says whether it is pressed. Before,
/// a segment announced only its label — "Recent, button. Title, button." —
/// and nothing about the order in use; no track had a name at all.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  testWidgets('the track is named; each segment is a button that says if it '
      'is the one pressed', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: KitSegmented(
            groupLabel: 'Order by',
            segments: const [KitSegment('Recent'), KitSegment('Title')],
            selected: 0,
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    expect(find.bySemanticsLabel('Order by'), findsOneWidget);
    expect(tester.getSemantics(find.bySemanticsLabel('Recent')),
        containsSemantics(isButton: true, isSelected: true));
    expect(tester.getSemantics(find.bySemanticsLabel('Title')),
        containsSemantics(isButton: true, isSelected: false));
    handle.dispose();
  });

  test('no track in lib/ is named with nothing', () {
    final empty = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      if (RegExp(r"groupLabel:\s*''").hasMatch(src)) empty.add(f.path);
    }
    expect(empty, isEmpty);
  });
}
