import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/api_service.dart';
import 'package:flutter_app/services/error_text.dart';

/// **C7 — an SDK string is not a sentence.**
///
/// Half this app's data arrives by subscription (INV-02), and a subscription
/// failure carries no envelope of ours — no `error`, no `request_id`, none of
/// what ADR-070 §14 is built around. What it carries is a `FirebaseException`,
/// and nineteen screens and notifiers wrote `'$e'` on one straight into the
/// slot a reader reads:
///
///     [cloud_firestore/permission-denied] The caller does not have
///     permission to execute the specified operation.
///
/// The plugin's brackets, the plugin's words, and no next move. Every one of
/// them rendered — §14 in the right place, in the right colour, saying
/// nothing anybody can act on — which is why no direction of 5n could see it:
/// PARTS asks whether the detail slot is FILLED, and it was.
///
/// Two halves here. The mapping, code by code; and the source scan, because a
/// unit test over the helper says nothing about the twentieth site.
void main() {
  group('describeSdkError', () {
    test('permission-denied names the move before support', () {
      final s = describeSdkError(FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
          message: 'The caller does not have permission.'));
      expect(s, 'NoteLetter could not read this. Sign out and back in, or '
          'contact support.');
      expect(s, isNot(contains('cloud_firestore')));
    });

    test('unavailable is the reader\'s own connection', () {
      expect(
          describeSdkError(FirebaseException(
              plugin: 'cloud_firestore', code: 'unavailable')),
          'You appear to be offline.');
    });

    test('failed-precondition is ours, and says so', () {
      // The missing-index shape: nothing the reader can do about it.
      final s = describeSdkError(FirebaseException(
          plugin: 'cloud_firestore',
          code: 'failed-precondition',
          message: 'The query requires an index.'));
      expect(s, 'This view is not ready on the server yet. Contact support.');
      expect(s, isNot(contains('index')));
    });

    test('an unnamed code falls back rather than guessing', () {
      expect(
          describeSdkError(FirebaseException(
              plugin: 'cloud_firestore', code: 'aborted')),
          'This could not be read right now. Please try again.');
    });

    test('a plain error falls back too — no `Instance of`', () {
      final s = describeSdkError(StateError('bad state'));
      expect(s, 'This could not be read right now. Please try again.');
      expect(s, isNot(contains('bad state')));
    });

    test('an ApiException keeps the SERVER\'s sentence (ADR-070)', () {
      // The belt for a site that routes here without a typed arm above it: our
      // own endpoint's words are never replaced by copy of ours.
      expect(
          describeSdkError(const ApiException(
              409, 'That shelf name is already taken.',
              errorCode: 'CONFLICT')),
          'That shelf name is already taken.');
    });
  });

  test('no screen or notifier renders a raw error object', () {
    // The half that outlives this change. `'$e'` in a field a screen draws is
    // the defect itself, and it is one keystroke to write again — so the
    // assertion is over the SOURCE, not over the helper.
    //
    // Scoped to what reaches a reader: `lib/state` and `lib/pages`. A raw
    // error in a log line or a `toString()` is not this defect.
    final offenders = <String>[];
    final rendered = RegExp(
        r"""(?:Error|_error|detail:)\s*[:=]?\s*'\$(?:e|_error|err)'"""
        r"""|'\$\{snap\.error\}'"""
        r"""|—\s*\$\{?(?:snap\.error|e)\}?'""");
    for (final dir in ['lib/state', 'lib/pages']) {
      for (final f in Directory(dir).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (rendered.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'route these through describeSdkError (C7):\n'
            '${offenders.join('\n')}');
  });
}
