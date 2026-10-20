import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;
import 'package:go_router/go_router.dart';

import '../shared/share_content.dart';

/// The Android share target's Dart side (F-123): takes what `MainActivity`
/// describes over `xp.noteletter/share`, classifies it, and opens `/share`.
///
/// iOS has no use for this — its share sheet is the native `ios/Share`
/// extension (F-122) and never enters the app.
class ShareIntake extends ChangeNotifier {
  ShareIntake._();
  static final ShareIntake instance = ShareIntake._();

  static const _channel = MethodChannel('xp.noteletter/share');

  static bool get isAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  GoRouter? _router;
  SharedContent? _content;

  /// True when the share LAUNCHED the app: closing the screen then returns to
  /// the app that shared, as the iOS sheet does. Otherwise it returns to
  /// [_returnTo], where the reader was.
  bool _launched = false;
  String? _returnTo;

  /// What the share screen shows; null when nothing has been shared.
  SharedContent? get content => _content;

  /// Listen for shares, and take the one that launched the app, if any.
  Future<void> start(GoRouter router) async {
    if (!isAvailable) return;
    _router = router;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'arrived') await _take(launched: false);
    });
    // After the first frame: the router is not built before it, and a share
    // is opened over the screen the app starts on.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _take(launched: true));
  }

  Future<void> _take({required bool launched}) async {
    final Object? raw;
    try {
      raw = await _channel.invokeMethod<Object?>('take');
    } on MissingPluginException {
      return;
    } on PlatformException catch (e) {
      // A share arrived and could not be described: said, never dropped.
      show(
        SharedUnreadable(readFailure(e.message ?? e.code)),
        launched: launched,
      );
      return;
    }
    if (raw is! Map) return;
    show(classifyShare(SharePayload.fromMap(raw)), launched: launched);
  }

  /// Open the share screen on [content]. Public for the widget tests, which
  /// have no `MainActivity` to describe a share.
  void show(SharedContent content, {bool launched = false}) {
    final router = _router;
    if (!launched && router != null) {
      String? here;
      try {
        here = router.state.uri.toString();
      } catch (_) {
        here = null; // no configuration yet
      }
      // A second share while the first is on screen keeps the first's return.
      if (here != null && !here.startsWith('/share')) _returnTo = here;
    }
    _launched = launched;
    _content = content;
    notifyListeners();
    router?.go('/share');
  }

  /// Copy one accepted stream into the app's cache under its own name.
  /// Throws a [ShareReadException] with the sentence to show.
  Future<({String path, int size})> copy(SharedStream s) async {
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('copy', {
        'uri': s.uri,
        'name': s.name,
      });
      final path = r?['path'] as String?;
      if (path == null) {
        throw ShareReadException(readFailure('nothing came back'));
      }
      return (path: path, size: (r?['size'] as num?)?.toInt() ?? s.size);
    } on PlatformException catch (e) {
      throw ShareReadException(readFailure(e.message ?? e.code));
    }
  }

  /// Cancel or Done: back to the app that shared, or to where the reader was.
  void close() {
    final launched = _launched;
    final back = _returnTo;
    _content = null;
    _launched = false;
    _returnTo = null;
    notifyListeners();
    if (launched) {
      SystemNavigator.pop();
    } else {
      _router?.go(back ?? '/');
    }
  }
}

class ShareReadException implements Exception {
  final String message;
  ShareReadException(this.message);
  @override
  String toString() => message;
}
