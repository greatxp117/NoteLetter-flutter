// A builder for a request the server answers 410 is a dead endpoint waiting
// for a caller (round 3, item 5; the parity read's one "broken" finding).
// `fn_scripture_newsletter_settings` answers GET with a deliberate 410
// (api/scripture.md, fixture `scripture-newsletter:settings-get-gone`); its
// settings are read through the SDK. `Api.getScriptureNewsletterSettings()`
// did that GET, and nothing called it.
//
// The rule is read off the fixtures, so it holds for any endpoint a captured
// case says answers a method with 410. Mutant run against it (red): the GET
// builder restored in lib/services/api.dart.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('no builder sends a request a captured case says is gone (410)', () {
    final gone = <(String, String)>{};
    for (final dir in Directory('${contractsRoot()}/fixtures/api')
        .listSync()
        .whereType<Directory>()) {
      final f = File('${dir.path}/cases.json');
      if (!f.existsSync()) continue;
      final suite = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final c in (suite['cases'] as List).cast<Map<String, dynamic>>()) {
        final req = (c['request'] as Map?)?.cast<String, dynamic>() ?? {};
        final status = (c['response'] as Map?)?['status'];
        if (status == 410 && req['endpoint'] != null && req['method'] != null) {
          gone.add((req['method'] as String, req['endpoint'] as String));
        }
      }
    }
    expect(gone, contains(('GET', 'fn_scripture_newsletter_settings')),
        reason: 'a gate that reads no gone request reads nothing');
    final api = File('lib/services/api.dart').readAsStringSync();
    final hits = [
      for (final (method, endpoint) in gone)
        if (RegExp('_http\\.${method.toLowerCase()}\\(\\s*\'/$endpoint[\'?]')
            .hasMatch(api))
          '$method $endpoint',
    ];
    expect(hits, isEmpty, reason: 'a builder for a 410: ${hits.join(', ')}');
  });
}
