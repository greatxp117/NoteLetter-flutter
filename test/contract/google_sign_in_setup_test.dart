// F-44a — `GoogleSignInSetup`'s two flags are read from the native config
// files, never trusted as typed.
//
// A missing iOS URL scheme is an NSException on the tap (the app dies, no Dart
// handler runs); a missing Android OAuth client is a DEVELOPER_ERROR from
// Credential Manager. Both are native configuration no Dart code can create,
// so the button asks the flags first — and this test is what keeps the flags
// true: re-download a config after the console step and it goes red until the
// flag follows.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/firebase_options.dart';
import 'package:flutter_app/services/google_sign_in_setup.dart';
import 'package:flutter_test/flutter_test.dart';

String? _plistString(String xml, String key) {
  final m = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(xml);
  return m?.group(1);
}

void main() {
  test('iosReady ⇔ the plist has REVERSED_CLIENT_ID and Info.plist registers it',
      () {
    final google = File('ios/Runner/GoogleService-Info.plist').readAsStringSync();
    final info = File('ios/Runner/Info.plist').readAsStringSync();
    final reversed = _plistString(google, 'REVERSED_CLIENT_ID');
    final registered = reversed != null &&
        info.contains('<key>CFBundleURLSchemes</key>') &&
        info.contains('<string>$reversed</string>');
    expect(GoogleSignInSetup.iosReady, registered,
        reason: 'iosReady must say exactly whether the reversed client id is a '
            'registered URL scheme — a tap without it kills the app');
    // The client id the SDK is initialised with is the plist's, through the
    // generated options.
    expect(DefaultFirebaseOptions.ios.iosClientId,
        _plistString(google, 'CLIENT_ID'));
  });

  test('androidReady ⇔ google-services.json has an Android OAuth client', () {
    final json = jsonDecode(
            File('android/app/google-services.json').readAsStringSync())
        as Map<String, dynamic>;
    final clients = (json['client'] as List).cast<Map<String, dynamic>>();
    final ours = clients.where((c) =>
        c['client_info']['android_client_info']['package_name'] ==
        'xp.NoteLetter.Flutter');
    expect(ours, hasLength(1));
    final oauth =
        ((ours.single['oauth_client'] as List?) ?? const []).cast<Map>();
    final hasAndroidClient = oauth.any((o) => o['client_type'] == 1);
    expect(GoogleSignInSetup.androidReady, hasAndroidClient,
        reason: 'an Android OAuth client (client_type 1) exists only once a '
            'SHA-1 fingerprint is registered for xp.NoteLetter.Flutter; flip '
            'androidReady in the same commit as the re-downloaded json');
    // The server client id Credential Manager is given is the web client.
    final web = oauth.where((o) => o['client_type'] == 3).map((o) => o['client_id']);
    expect(web, contains(GoogleSignInSetup.webClientId));
  });
}
