import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';

/// Tells the iOS share extension where a DEBUG build's traffic goes (F-122).
///
/// The extension is started by the system from another app's share sheet, so
/// it gets no dart-defines and no environment. A debug app on the emulator
/// writes the emulator's address into the shared App Group
/// (`ios/Runner/AppDelegate.swift`); a debug app on prod clears it, and the
/// debug extension then refuses rather than reach prod (umbrella law 1). A
/// release build never calls this, and the native side ignores it there too.
class ShareConfigChannel {
  static const _channel = MethodChannel('xp.noteletter/share_config');

  static Future<void> publish() async {
    if (!kDebugMode || kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'setEmulator',
        ApiService.useEmulator
            ? {
                'host': ApiService.emulatorHost,
                'authPort': ApiService.authPort,
                'functionsPort': ApiService.functionsPort,
                'shim': ApiService.useFunctionsShim,
              }
            : null,
      );
    } on MissingPluginException {
      // A test binding, or a host that registered no channel: nothing to tell.
    }
  }
}
