import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/newsletter.dart';
import 'package:flutter_app/services/row_decode.dart';

/// One row that cannot be read costs that row, never the list (TODO
/// 2026-10-13: a readings letter whose `lead` was not a bool failed this
/// client's whole letters read; web keeps the row, `api.js` hands it through
/// as data).
///
/// Firestore itself is not reachable from a test here (`fake_cloud_firestore`
/// does not resolve against this SDK), so the rule is the extracted
/// [decodeRows], driven over plain rows, and a sweep that every list read in
/// `firestore_service.dart` goes through it.
typedef Row = (String, Map<String, dynamic>);

String idOf(Row r) => r.$1;

void main() {
  group('decodeRows', () {
    test('drops the row that throws, logs it, and keeps the rest in order', () {
      final dropped = <(String, String, Object)>[];
      final rows = <Row>[
        ('a', {'status': 'sent'}),
        ('b', {'status': 5}),
        ('c', {'status': 'empty'}),
      ];
      final out = decodeRows<Row, String>('newsletters', rows, idOf,
          (r) => r.$2['status'] as String,
          onDropped: (c, id, e) => dropped.add((c, id, e)));
      expect(out, ['sent', 'empty']);
      expect(dropped, hasLength(1));
      expect(dropped.single.$1, 'newsletters');
      expect(dropped.single.$2, 'b');
      expect(dropped.single.$3, isA<TypeError>());
    });

    test('an empty read is an empty list, and nothing is logged', () {
      var logged = 0;
      expect(
          decodeRows<Row, String>('tags', const [], idOf, (r) => r.$1,
              onDropped: (_, __, ___) => logged++),
          isEmpty);
      expect(logged, 0);
    });
  });

  group('a readings letter', () {
    Map<String, dynamic> letter(List<Map<String, dynamic>> readings) => {
          'user_id': 'u',
          'kind': 'scripture',
          'status': 'sent',
          'trigger': 'scheduled',
          'readings': readings,
        };

    test('whose `lead` is not a bool is read as web reads it, not thrown', () {
      final n = Newsletter.fromJson(
          'r1',
          letter([
            {'label': 'First', 'ref': 'Gen 1:1', 'lead': 'yes'},
            {'label': 'Psalm', 'ref': 'Ps 23', 'lead': 0},
            {'label': 'Second', 'ref': 'Rom 8:1', 'lead': 1},
            {'label': 'Gospel', 'ref': 'Jn 1:1', 'lead': ''},
            {'label': 'Alleluia', 'ref': 'Jn 3:16', 'lead': true},
            {'label': 'Absent', 'ref': 'Mt 5:1'},
          ]));
      // `r.lead ? 'lead' : ''` — JavaScript's truthiness.
      expect(n.readings.map((r) => r.lead).toList(),
          [true, false, true, false, true, false]);
    });

    test('whose `parsed` is not a bool is parsed — only `false` is not', () {
      final n = Newsletter.fromJson(
          'r2',
          letter([
            {'label': 'A', 'ref': 'x', 'parsed': 'no'},
            {'label': 'B', 'ref': 'y', 'parsed': false},
            {'label': 'C', 'ref': 'z'},
          ]));
      // `r.parsed === false`.
      expect(n.readings.map((r) => r.parsed).toList(), [true, false, true]);
    });

    test('in a list beside a row that cannot be read: the list stands', () {
      final rows = <Row>[
        ('daily', {'user_id': 'u', 'status': 'sent', 'trigger': 'scheduled'}),
        (
          'readings',
          letter([
            {'label': 'First', 'ref': 'Gen 1:1', 'lead': 'yes'},
          ])
        ),
        ('broken', {'user_id': 'u', 'status': 7}),
      ];
      final dropped = <String>[];
      final out = decodeRows<Row, Newsletter>('newsletters', rows, idOf,
          (r) => Newsletter.fromJson(r.$1, r.$2),
          onDropped: (_, id, __) => dropped.add(id));
      expect(out.map((n) => n.id), ['daily', 'readings']);
      expect(dropped, ['broken']);
    });
  });

  test('every list read in firestore_service goes through decodeRows', () {
    final src = File('lib/services/firestore_service.dart').readAsStringSync();
    // `docs.map(` / `docs\n  .map(` over a model decode is the shape that let
    // one row fail the list. `getReadHistory` maps to plain values that
    // cannot throw (`tsMs` returns null for a stranger), and is the one
    // exemption; it is named so a second one has to be argued for.
    final hits = RegExp(r'docs\s*\.map\(').allMatches(src).map((m) {
      final before = src.substring(0, m.start);
      final fn = RegExp(r'\n  [A-Za-z<>(), ?\[\]]+? (\w+)\(')
          .allMatches(before)
          .last
          .group(1);
      return fn;
    }).toList();
    expect(hits, ['getReadHistory']);
    expect(RegExp(r'_rows\(').allMatches(src).length, greaterThanOrEqualTo(20));
  });
}
