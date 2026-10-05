/// One provider list (lib/app_providers.dart), read by the app, the device run
/// and the screenshot hold. F-72 added `ReviewInbox` to `main.dart`'s copy
/// only, and `AppLayout` reads it on every authenticated screen — so every
/// hold and device test would have been a ProviderNotFoundError wall, with
/// analyze and this suite green, because nothing here builds the app's tree.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final list = File('lib/app_providers.dart').readAsStringSync();

  test('the app and both device harnesses build from appProviders', () {
    for (final f in [
      'lib/main.dart',
      'integration_test/device_run_test.dart',
      'integration_test/hold_screen_test.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, contains('appProviders('), reason: f);
      expect(src.contains('ChangeNotifierProvider<'), isFalse,
          reason: '$f spells its own provider — a copy of the list drifts');
    }
  });

  test('every notifier a widget reads is in the list', () {
    final read = RegExp(
        r'(?:watch|read|select)<([A-Z]\w+)>|Consumer\d?<([A-Z][\w, ]+)>|Provider\.of<([A-Z]\w+)>');
    final types = <String>{};
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      for (final m in read.allMatches(f.readAsStringSync())) {
        final g = m.group(1) ?? m.group(2) ?? m.group(3)!;
        types.addAll(g.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty));
      }
    }
    expect(types, isNotEmpty, reason: 'the reader read nothing');
    final missing = [
      for (final t in types)
        if (!list.contains('ChangeNotifierProvider<$t>')) t,
    ];
    expect(missing, isEmpty);
  });
}
