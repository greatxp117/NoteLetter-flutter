// A bucket nothing enumerates is a bucket that vanishes (umbrella CLAUDE.md).
// The kind vocabulary (`kKindByType`, component-kit §6.4.1) is half of what a
// plate needs; the label table that RENDERS each kind is the other half, and
// nothing tied them together — `video` mapped to its own kind from 4.13.0 while
// KitFileBadge had no label for it, so every uploaded video plated as DOC.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/theme/app_theme.dart';
import 'package:flutter_app/widgets/kit/kit.dart';

void main() {
  final kinds = kKindByType.values.toSet();

  test('every kind the vocabulary produces has a plate label', () {
    final unlabelled = kinds.where((k) => !KitFileBadge.labels.containsKey(k));
    expect(unlabelled, isEmpty,
        reason: 'a kind with no label plates as DOC with no error');
  });

  test('every plate label is a kind the vocabulary produces', () {
    final orphan = KitFileBadge.labels.keys.where((k) => !kinds.contains(k));
    expect(orphan, isEmpty, reason: 'a label no type can reach is dead vocabulary');
  });

  test("the label table is the reference's LABELS (shared/FileBadge.jsx)", () {
    final src = File('../NoteLetter-web/src/shared/FileBadge.jsx').readAsStringSync();
    final body = RegExp(r'const LABELS = \{([^}]*)\}').firstMatch(src)?.group(1);
    expect(body, isNotNull, reason: 'web LABELS not found — the reader read nothing');
    final web = {
      for (final m in RegExp(r"(\w+):\s*'([^']*)'").allMatches(body!))
        m.group(1)!: m.group(2)!,
    };
    expect(web, isNotEmpty);
    expect(KitFileBadge.labels, equals(web));
  });

  testWidgets('a video document plates VIDEO, never DOC', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: KitFileBadge(kitDocKind('video')))),
    ));
    expect(find.text('VIDEO'), findsOneWidget);
    expect(find.text('DOC'), findsNothing);
  });
}
