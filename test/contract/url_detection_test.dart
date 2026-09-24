import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/state/upload_notifier.dart';

import 'fixtures.dart';

/// 4.86.0 / ADR-120: the shared normalize-then-detect table. Every case maps
/// `input` to exactly the `url` fn_ingest_url is sent and its `type`.
void main() {
  final cases = (jsonDecode(File('${contractsRoot()}/fixtures/url-detection/cases.json')
          .readAsStringSync()) as Map<String, dynamic>)['cases'] as List;
  test('table is non-empty', () => expect(cases, isNotEmpty));
  for (final c in cases.cast<Map<String, dynamic>>()) {
    test('url-detection ${c['id']}', () {
      expect(normalizeUrl(c['input'] as String), c['url']);
      expect(detectUrlType(c['input'] as String), c['type']);
    });
  }
}
