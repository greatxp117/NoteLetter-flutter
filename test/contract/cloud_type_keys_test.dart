/// The sync type vocabulary, read both ways against the contract (4.120.0,
/// ADR-157) — web's `tests/contract/cloud-type-keys.test.js`. A key the spec
/// names and this client omits is a type the reader cannot tick; a key named
/// here that the backend refuses is a pill whose save is a 400. The labels are
/// the ones `screens/sources.md` §Folder contents gives.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/models/import_job.dart';
import 'package:flutter_app/pages/sources/folder_contents.dart';
import 'package:flutter_app/pages/sources/sync_settings_panel.dart';

void main() {
  final spec = File('../NoteLetter-contracts/spec/api/cloud-storage.md')
      .readAsStringSync();
  final screen = File('../NoteLetter-contracts/spec/screens/sources.md')
      .readAsStringSync();

  test('every file type the contract accepts is a pill, and nothing else is', () {
    final set = RegExp(r'`include_types` ⊆ `([^`]+)`').firstMatch(spec)?.group(1);
    expect(set, isNotNull, reason: 'cloud-storage.md no longer names the set');
    final contract = set!.split('|').map((s) => s.trim())
        .where((k) => k != 'notion').toList()..sort();
    expect([...cloudFileTypes]..sort(), contract);
  });

  test('every key wears the label screens/sources.md gives it', () {
    final line = RegExp(r'The type labels are ([^—]+?) —').firstMatch(screen)?.group(1);
    expect(line, isNotNull, reason: 'sources.md no longer lists the type labels');
    final labels = line!.split('·').map((s) => s.trim()).toList();
    expect([...cloudFileTypes, 'notion'].map(cloudTypeLabel).toList(), labels);
  });

  test('a provider mime maps onto every key — a book included', () {
    String? key(String mime) =>
        ImportJob.fromJson('j', {'mime_type': mime}).typeKey;
    expect(key('application/epub+zip'), 'epub');
    final mapped = {
      for (final m in [
        'application/pdf',
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'application/epub+zip',
      ])
        key(m)
    };
    expect(mapped, cloudFileTypes.toSet());
  });
}
