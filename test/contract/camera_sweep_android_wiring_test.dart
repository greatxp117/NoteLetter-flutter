// F-125 S5: the camera-roll sweep's Android native side, read — what the
// Dart sweep and the Kotlin under it must agree on, and what no widget test
// can see (the Kotlin runs only on a device; that run is owed). The iOS half
// of these checks is camera_sweep_background_test.dart's `native wiring`.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/services/camera_sweep_bridge.dart';
import 'package:flutter_app/services/sweep_background.dart';
import 'package:flutter_app/services/sweep_uploader.dart';

const _kt = 'android/app/src/main/kotlin/xp/NoteLetter/Flutter';

String _read(String path) => File(path).readAsStringSync();

/// A Kotlin `const val NAME = "…"`.
String? _const(String src, String name) =>
    RegExp('const val $name = "([^"]*)"').firstMatch(src)?.group(1);

void main() {
  final channel = _read('$_kt/camerasweep/CameraSweepChannel.kt');
  final uploader = _read('$_kt/camerasweep/SweepUploader.kt');
  final background = _read('$_kt/camerasweep/SweepBackground.kt');
  final activity = _read('$_kt/MainActivity.kt');
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final gradle = _read('android/app/build.gradle.kts');
  final mainDart = _read('lib/main.dart');

  test('the four channels are the names the Dart side calls', () {
    expect(_const(channel, 'NAME'), CameraSweepBridge.channelName);
    expect(_const(channel, 'CHANGES'), CameraSweepBridge.changesName);
    expect(_const(uploader, 'EVENTS'), NativeSweepUploader.eventsName);
    expect(_const(background, 'CHANNEL'), NativeSweepBackground.channelName);
  });

  test('every method the Dart side invokes is answered natively', () {
    for (final m in [
      'constants',
      'access',
      'requestAccess',
      'openSettings',
      'fetchImages',
      'examine',
      'renderedJpeg',
      'thumbnail',
      'stageUpload',
      'startUpload',
      'discardUpload',
      'uploadsInFlight',
      'finishedUploads',
      'acknowledgeUploads',
    ]) {
      expect(channel.contains('"$m"'), isTrue, reason: m);
    }
    for (final m in ['attach', 'setScheduled']) {
      expect(background.contains('"$m" ->'), isTrue, reason: m);
    }
    // And the two the native side invokes are the host's.
    expect(background.contains('invokeMethod("run"'), isTrue);
    expect(background.contains('invokeMethod("expire"'), isTrue);
  });

  test('the app engine registers the bridge and the background channel', () {
    expect(activity.contains('CameraSweepChannel(applicationContext)'), isTrue);
    expect(activity.contains('SweepBackground.register('), isTrue);
    expect(
      activity.contains('CameraSweepChannel.REQUEST_CODE'),
      isTrue,
      reason:
          'requestAccess answers only when the permission result is forwarded',
    );
  });

  test('the background engine runs an entrypoint that exists and is kept', () {
    final entry = RegExp(
      r'DartEntrypoint\([^,]+,\s*"(\w+)"\)',
    ).firstMatch(background)?.group(1);
    expect(entry, 'sweepBackgroundMain');
    expect(
      RegExp(
        "@pragma\\('vm:entry-point'\\)\\s*Future<void> $entry\\(",
      ).hasMatch(mainDart),
      isTrue,
      reason:
          'without the pragma a release build strips it, and the job starts nothing',
    );
    // The background engine builds the bridge too: the host's pass needs it.
    expect(
      background.contains('CameraSweepChannel(context).register(messenger)'),
      isTrue,
    );
  });

  test('§1: the three permissions, the legacy one capped at API 32', () {
    expect(manifest.contains('android.permission.READ_MEDIA_IMAGES'), isTrue);
    expect(
      manifest.contains('android.permission.READ_MEDIA_VISUAL_USER_SELECTED'),
      isTrue,
    );
    expect(
      RegExp(
        r'READ_EXTERNAL_STORAGE"\s*android:maxSdkVersion="32"',
      ).hasMatch(manifest),
      isTrue,
    );
  });

  test('§2: the text model is the BUNDLED one, never the downloaded one', () {
    expect(gradle.contains('com.google.mlkit:text-recognition:'), isTrue);
    expect(gradle.contains('play-services-mlkit-text-recognition'), isFalse);
    expect(
      RegExp(r'const val MINIMUM_CHARACTERS = 80\b').hasMatch(channel),
      isTrue,
    );
    expect(
      RegExp(r'const val THUMBNAIL_EDGE = 1024\b').hasMatch(channel),
      isTrue,
    );
  });

  test('INV-08: the upload is a bare PUT, no Authorization header', () {
    expect(uploader.contains('requestMethod = "PUT"'), isTrue);
    // Every header the worker sets, read from the code (the KDoc names the
    // one it must not set).
    final headers = RegExp(
      r'(?:set|add)RequestProperty\("([^"]+)"',
    ).allMatches(uploader).map((m) => m.group(1)).toList();
    expect(headers, ['Content-Type']);
  });

  test('§5: iOS\'s background conditions — network, power, an hour out', () {
    expect(_const(background, 'WORK'), NativeSweepBackground.taskIdentifier);
    expect(background.contains('NetworkType.CONNECTED'), isTrue);
    expect(background.contains('setRequiresCharging(true)'), isTrue);
    expect(background.contains('setInitialDelay(1, TimeUnit.HOURS)'), isTrue);
  });
}
