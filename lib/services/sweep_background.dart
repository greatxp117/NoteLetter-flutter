import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The camera-roll sweep's background pass (F-125 S4): a `BGProcessingTask`,
/// `xp.NoteLetter.Flutter.camerasweep.refresh`, that iOS runs when it allows
/// — opportunistically, on power, with the network — and whose pass is the
/// FOREGROUND's own (`CameraSweepHost`): one engine, one ledger, one tray.
///
/// Native: `ios/Runner/CameraSweep/SweepBackgroundTask.swift`. It calls
/// `run` when the system launches the task, and `expire` when the system
/// takes the time back; the task is completed when `run` answers (the pass
/// ended) or right after `expire` does.
abstract class SweepBackground {
  /// Starts answering the native side. A task that arrived before this is
  /// run now.
  Future<void> attach({
    required Future<Map<String, Object?>> Function() onRun,
    required Future<void> Function() onExpire,
  });

  /// Stops answering (the host was disposed).
  void detach();

  /// Asks iOS for the task (on) or withdraws the request (off). The answer
  /// says whether iOS took it: the simulator, and a phone with Background App
  /// Refresh off, refuse.
  Future<SweepSchedule> setScheduled(bool on);
}

class SweepSchedule {
  const SweepSchedule({required this.scheduled, this.error});
  final bool scheduled;
  final String? error;

  @override
  String toString() => scheduled ? 'scheduled' : 'not scheduled${error == null ? '' : ' ($error)'}';
}

class NativeSweepBackground implements SweepBackground {
  NativeSweepBackground({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'xp.noteletter/camera_sweep/background';

  /// The identifier Info.plist permits and the native side registers.
  static const taskIdentifier = 'xp.NoteLetter.Flutter.camerasweep.refresh';

  final MethodChannel _channel;

  /// The one channel answers one host: a host disposed after its successor
  /// attached must not take the successor's handler with it.
  static NativeSweepBackground? _attached;

  @override
  Future<void> attach({
    required Future<Map<String, Object?>> Function() onRun,
    required Future<void> Function() onExpire,
  }) async {
    _attached = this;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'run':
          return await onRun();
        case 'expire':
          await onExpire();
          return null;
      }
      throw MissingPluginException('camera sweep background: ${call.method}');
    });
    await _channel.invokeMethod<void>('attach');
  }

  @override
  void detach() {
    if (!identical(_attached, this)) return;
    _attached = null;
    _channel.setMethodCallHandler(null);
  }

  @override
  Future<SweepSchedule> setScheduled(bool on) async {
    final raw = await _channel.invokeMethod<Object?>('setScheduled', {'on': on});
    if (raw is! Map || raw['scheduled'] is! bool) {
      throw FormatException('camera sweep background: setScheduled answered $raw');
    }
    return SweepSchedule(scheduled: raw['scheduled'] as bool, error: raw['error'] as String?);
  }

  // ── Debug builds only: what Apple's development guide types into the
  //    debugger, so a device test can drive the task. ─────────────────────────

  @visibleForTesting
  Future<void> debugSimulateLaunch() => _channel.invokeMethod<void>('debugSimulateLaunch');

  @visibleForTesting
  Future<void> debugSimulateExpiration() =>
      _channel.invokeMethod<void>('debugSimulateExpiration');

  @visibleForTesting
  Future<List<String>> debugPending() async =>
      ((await _channel.invokeMethod<List<Object?>>('debugPending')) ?? const [])
          .cast<String>();

  /// The native side's record of what happened, in order: each entry has an
  /// `event` and its `atMs`.
  @visibleForTesting
  Future<List<Map<String, Object?>>> debugTrail() async =>
      ((await _channel.invokeMethod<List<Object?>>('debugTrail')) ?? const [])
          .map((e) => Map<String, Object?>.from(e as Map))
          .toList();

  /// When iOS woke the app for the upload session's events.
  @visibleForTesting
  Future<Map<String, Object?>> debugUploads() async => Map<String, Object?>.from(
      (await _channel.invokeMethod<Map<Object?, Object?>>('debugUploads')) ?? const {});
}
