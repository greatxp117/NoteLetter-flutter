// TODO L182 + L337 + L2647, one cause: the alt suite's Firestore emulator ran
// out of Java heap after ~200 frames' listeners, then wrote plausible wrong
// frames, and lanes set JAVA_TOOL_OPTIONS=-Xmx5g by hand. `tool/emu_alt.sh up`
// now starts the emulators with a heap by default. These run the script
// itself (`heap` prints what `up` exports).
//
// Mutants run against it (each turns a case red): the default dropped; the
// heap REPLACING the options already set (a cloud VM's proxy and truststore
// live there); a value that names its own -Xmx overridden; `up` starting the
// emulators without exporting it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<String> _heap(Map<String, String> env) async {
  final base = Map<String, String>.from(Platform.environment)
    ..remove('JAVA_TOOL_OPTIONS')
    ..remove('NL_EMU_HEAP');
  final r = await Process.run('sh', ['tool/emu_alt.sh', 'heap'],
      environment: {...base, ...env}, includeParentEnvironment: false);
  expect(r.exitCode, 0, reason: '${r.stderr}');
  return (r.stdout as String).trim();
}

void main() {
  test('with nothing set, the emulators get 5 GB', () async {
    expect(await _heap({}), '-Xmx5g');
  });

  test('it is appended to the options already set, never in their place',
      () async {
    expect(
        await _heap({'JAVA_TOOL_OPTIONS': '-Dhttps.proxyHost=127.0.0.1'}),
        '-Dhttps.proxyHost=127.0.0.1 -Xmx5g');
  });

  test('a heap already named is kept, and NL_EMU_HEAP sizes the default',
      () async {
    expect(await _heap({'JAVA_TOOL_OPTIONS': '-Dx=1 -Xmx2g'}), '-Dx=1 -Xmx2g');
    expect(await _heap({'NL_EMU_HEAP': '8g'}), '-Xmx8g');
  });

  test('up exports it before the emulators start', () {
    final src = File('tool/emu_alt.sh').readAsStringSync();
    final up = src.substring(src.indexOf('up() {'));
    final set = up.indexOf(r'JAVA_TOOL_OPTIONS="$(java_opts)"');
    final exported = up.indexOf('export JAVA_TOOL_OPTIONS');
    final start = up.indexOf('firebase emulators:start');
    expect(set, isNonNegative);
    expect(exported, greaterThan(set));
    expect(start, greaterThan(exported));
  });
}
