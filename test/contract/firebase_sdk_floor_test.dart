// The eMudhra floor (Firebase advisory, 2026-11-03). On 2026-10-17 the private
// keys of several eMudhra intermediate CAs leaked and Google revoked them. Two
// TLS stacks in this app compile their trust in, so neither an OS update nor
// any server change reaches an installed build:
//
//   - iOS: FirebaseFirestore's gRPC carries its own root bundle. 12.19.2 and
//     earlier trust the revoked intermediates; 12.19.3 does not. CocoaPods
//     never gets Firebase 13, so 12.19.3 is the floor on this line.
//   - Android (all of Dart's `dart:io`, so Dio's fn_* calls as well as
//     Firestore): Dart validates with its own BoringSSL and never reads the
//     OS blocklist. Dart 3.13.7 / Flutter 3.47.8 is the fix.
//
// A build below either floor can be shown a forged certificate for Firestore
// or our functions and will accept it, while every request still succeeds.
// Nothing else can notice that, so this test checks the resolved versions
// rather than trusting the constraints that should produce them.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

List<int> _v(String s) =>
    s.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();

bool _atLeast(String have, String floor) {
  final a = _v(have), b = _v(floor);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return true;
}

String _locked(String lock, String package) {
  final m = RegExp('\\n  $package:\\n(?:    .*\\n)*?    version: "([^"]+)"')
      .firstMatch(lock);
  expect(m, isNotNull, reason: '$package is not in pubspec.lock');
  return m!.group(1)!;
}

String _pod(String lock, String pod) {
  final m = RegExp('\\n  - ${RegExp.escape(pod)} \\(([0-9.]+)\\)').firstMatch(lock);
  expect(m, isNotNull, reason: '$pod is not in ios/Podfile.lock');
  return m!.group(1)!;
}

void main() {
  test('the Dart that builds this app carries the patched BoringSSL roots', () {
    // `Platform.version` is the running Dart, which is the SDK's own: the one
    // `flutter build` compiles into the Android binary.
    final dart = Platform.version.split(' ').first;
    expect(_atLeast(dart, '3.13.7'), isTrue,
        reason: 'Dart $dart (Flutter < 3.47.8) trusts the revoked eMudhra '
            'intermediates on Android. Use /Volumes/DevCache/flutter-sdk/3.47.9 '
            '(the umbrella SessionStart hook), not ~/development/flutter');
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(RegExp(r"^\s+flutter: '>=3\.47\.8'", multiLine: true).hasMatch(pubspec),
        isTrue,
        reason: "pubspec.yaml's environment must keep flutter: '>=3.47.8', so "
            'an older SDK fails at pub get instead of building');
  });

  test('FlutterFire resolves at or above the eMudhra-patched BoM 4.20.1', () {
    final lock = File('pubspec.lock').readAsStringSync();
    const floors = {
      'cloud_firestore': '6.10.1',
      'firebase_core': '4.15.1', // pins the Firebase iOS SDK to 12.19.3
    };
    floors.forEach((package, floor) {
      final have = _locked(lock, package);
      expect(_atLeast(have, floor), isTrue,
          reason: '$package $have is below $floor, which is affected by the '
              'eMudhra advisory');
    });
  });

  test('the iOS Firestore that ships is 12.19.3 or later', () {
    final lock = File('ios/Podfile.lock').readAsStringSync();
    for (final pod in const [
      'FirebaseFirestore',
      'FirebaseFirestoreInternal',
      'FirebaseCore',
    ]) {
      final have = _pod(lock, pod);
      expect(_atLeast(have, '12.19.3'), isTrue,
          reason: '$pod $have trusts the revoked eMudhra intermediates. Run '
              '`pod update` in ios/; a stale Podfile.lock ships the old one '
              'even with pubspec.lock patched');
    }
  });

  test('the Podfile names no Firebase pod by a literal version', () {
    // The Share target once pinned `pod 'FirebaseAuth', '12.17.0'`, which left
    // the whole app unable to resolve 12.19.3. Versions come from FlutterFire's
    // firebase_sdk_version.rb.
    final podfile = File('ios/Podfile').readAsStringSync();
    final literal = RegExp(r'''^\s*pod\s+['"]Firebase[^'"]*['"]\s*,\s*['"][~>=<\s]*[0-9]''',
        multiLine: true);
    expect(literal.hasMatch(podfile), isFalse,
        reason: 'use firebase_sdk_version!, not a literal Firebase version');
  });
}
