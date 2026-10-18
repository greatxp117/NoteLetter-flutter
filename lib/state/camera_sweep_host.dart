import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding, WidgetsBindingObserver;

import '../services/camera_sweep_bridge.dart';
import '../services/camera_sweep_service.dart';
import '../services/sweep_ledger.dart';
import 'auth_notifier.dart';

/// What runs the camera-roll sweep in the FOREGROUND, and what its two screens
/// read (F-125 S3; `spec/features/camera-roll-sweep.md`).
///
/// A pass starts:
///  * **at launch**, once someone is signed in, when the sweep is on and the
///    library is fully readable (Swift `SourcesListView.onAppear` →
///    `startIfEnabled`);
///  * **when the library changes** while the app is open — the native change
///    observer, through [CameraSweepBridge.libraryChanges], settled for
///    [debounce] so a burst of changes (iCloud syncing) is one pass;
///  * **when the app returns to the foreground**, which is also how a grant
///    made in the system settings is noticed;
///  * when the user asks (Settings → Camera roll → Check for new photos).
///
/// A change that arrives while a pass runs is not dropped: one more pass runs
/// after it. No background task: that is S4.
///
/// **It never asks for access at launch** (spec §1): [access] reads the
/// status without prompting, and the prompt fires only in [enable], which the
/// user's switch calls.
class CameraSweepHost extends ChangeNotifier with WidgetsBindingObserver {
  CameraSweepHost({
    required Listenable session,
    required bool Function() isSignedIn,
    required CameraSweepBridge bridge,
    required SweepLedgerStore store,
    required SweepEndpoints endpoints,
    this.debounce = const Duration(seconds: 2),
    bool observeLifecycle = true,
  })  : available = true,
        _session = session,
        _isSignedIn = isSignedIn,
        _bridge = bridge,
        _endpoints = endpoints {
    _session!.addListener(_onSession);
    if (observeLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    ready = _load(store);
  }

  /// A platform with no photo library this client can sweep (web; Android
  /// until S5). Draws nothing and runs nothing.
  CameraSweepHost.unavailable()
      : available = false,
        debounce = Duration.zero,
        _session = null,
        _isSignedIn = null,
        _bridge = null,
        _endpoints = null {
    ready = Future.value();
  }

  /// The app's: iOS gets the real bridge, store and endpoints; every other
  /// platform the inert host.
  factory CameraSweepHost.forApp(AuthNotifier auth) => CameraSweepBridge.isAvailable
      ? CameraSweepHost(
          session: auth,
          isSignedIn: () => auth.isLoggedIn,
          bridge: CameraSweepBridge(),
          store: AppGroupLedgerStore(),
          endpoints: const LiveSweepEndpoints(),
        )
      : CameraSweepHost.unavailable();

  final bool available;

  /// A write to this device's store that did not land — the switch, the
  /// mode, the date, a skip, Start over. The control stays where the store
  /// is (screens/settings.md §Camera-roll sweep card).
  static const notSaved = 'This phone could not save that. Please try again.';

  /// How long the library must be quiet before a change starts a pass.
  final Duration debounce;

  final Listenable? _session;
  final bool Function()? _isSignedIn;
  final CameraSweepBridge? _bridge;
  final SweepEndpoints? _endpoints;
  bool _observing = false;

  /// Completes once the ledger is read (or failed to be).
  late final Future<void> ready;

  SweepLedger? _ledger;
  CameraSweepService? _service;

  /// The device's ledger and the service over it; null until [ready], and
  /// null for good if the store could not be read ([loadError]).
  SweepLedger? get ledger => _ledger;
  CameraSweepService? get service => _service;
  CameraSweepBridge? get bridge => _bridge;

  Object? _loadError;
  Object? get loadError => _loadError;

  SweepAccess? _access;

  /// The library authorization as last read — without prompting. null until
  /// read.
  SweepAccess? get access => _access;

  SweepAccessRefused? _refused;

  /// Why the user's last attempt to turn the sweep on was refused (partial or
  /// no access), until a later attempt or a grant clears it. With the sweep
  /// already on, [access] says the same thing.
  SweepAccessRefused? get refused => _refused;

  int? _inRange;

  /// "Photos in range": images from the backfill start to now, counted by the
  /// library — measured, never estimated. null until read, or when it could
  /// not be.
  int? get inRange => _inRange;

  StreamSubscription<void>? _changes;
  Timer? _settle;
  bool _again = false;
  bool _launched = false;
  bool _disposed = false;

  Future<void> _load(SweepLedgerStore store) async {
    try {
      final ledger = await SweepLedger.load(store);
      _ledger = ledger;
      _service = CameraSweepService(
          bridge: _bridge!, ledger: ledger, endpoints: _endpoints!);
    } catch (e) {
      _loadError = e;
      debugPrint('camera sweep: the ledger could not be read ($e)');
    }
    if (_disposed) return;
    notifyListeners();
    _onSession();
  }

  void _onSession() {
    final service = _service;
    if (service == null || _disposed) return;
    if (_isSignedIn!()) {
      if (!_launched) {
        _launched = true;
        unawaited(_start());
      }
    } else if (_launched) {
      // The tray was found for the account that just left. Nothing was sent
      // for a card, so forgetting it loses nothing.
      _launched = false;
      _unwatch();
      service.stop();
      service.clearTray();
    }
  }

  /// Reads access without asking; if the sweep is on and the library is
  /// fully readable, watches the library and runs a pass.
  Future<void> _start() async {
    final ledger = _ledger;
    if (ledger == null || !ledger.enabled) return;
    await refreshAccess();
    if (_access != SweepAccess.granted || !_signedIn) return;
    _watch();
    kick();
    unawaited(refreshInRange());
  }

  bool get _signedIn => _isSignedIn?.call() ?? false;

  /// Bumped by every answer to the prompt, so a read that STARTED before it
  /// cannot land after it and overwrite the answer with what preceded it.
  int _accessEpoch = 0;

  /// Reads the authorization (never prompts). A standing refusal that no
  /// longer matches — access was changed in the system settings — is dropped.
  Future<void> refreshAccess() async {
    final bridge = _bridge;
    if (bridge == null) return;
    final epoch = _accessEpoch;
    try {
      final got = await bridge.access();
      if (epoch != _accessEpoch) return;
      _access = got;
      if (_refused != null && _refused!.access != got) _refused = null;
    } catch (e) {
      debugPrint('camera sweep: photo access could not be read ($e)');
    }
    if (!_disposed) notifyListeners();
  }

  // ── Starting a pass ─────────────────────────────────────────────────────────

  /// Runs a pass now, or once more after the running one.
  void kick() {
    final service = _service;
    if (service == null || _disposed) return;
    if (!(_ledger?.enabled ?? false) || !_signedIn) return;
    if (service.isSweeping) {
      _again = true;
      return;
    }
    service.sweep().then((pass) {
      if (pass.refused != null) {
        _access = pass.refused!.access;
        _unwatch();
        if (!_disposed) notifyListeners();
      }
    }, onError: (Object e) {
      // A pass that could not enumerate at all (the bridge failed). Said in
      // its own words on both screens, never swallowed.
      service.presentFailure(
          e is PlatformException ? (e.message ?? e.code) : '$e',
          stopsSweep: true);
    }).whenComplete(() {
      if (_again && !_disposed) {
        _again = false;
        kick();
      }
    });
  }

  void _watch() {
    final bridge = _bridge;
    if (bridge == null || _changes != null) return;
    _changes = bridge.libraryChanges().listen((_) {
      _settle?.cancel();
      _settle = Timer(debounce, kick);
    }, onError: (Object e) {
      if (e is SweepAccessRefused) _access = e.access;
      debugPrint('camera sweep: library changes stopped ($e)');
      _unwatch();
      if (!_disposed) notifyListeners();
    });
  }

  void _unwatch() {
    _settle?.cancel();
    _settle = null;
    unawaited(_changes?.cancel());
    _changes = null;
  }

  /// Whether the native change observer is listened to (tests, and the
  /// device run's proof of the wiring).
  @visibleForTesting
  bool get watching => _changes != null;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !(_ledger?.enabled ?? false)) return;
    // Back from the system settings (a grant, or a revocation), or from the
    // camera: read access again, and sweep if the library is readable.
    unawaited(refreshAccess().then((_) {
      if (_access == SweepAccess.granted && _signedIn) {
        _watch();
        kick();
      } else {
        _unwatch();
      }
    }));
  }

  // ── What the settings screen does ───────────────────────────────────────────

  /// The switch turned on. The system prompt fires HERE, on the user's
  /// affirmative action, and only here (spec §1). Full access turns the sweep
  /// on and runs a pass; partial or no access leaves it off and says why
  /// ([refused]). A failed ledger write throws, and the switch stays where
  /// the store is (write before move).
  Future<void> enable() async {
    final bridge = _bridge, ledger = _ledger;
    if (bridge == null || ledger == null) return;
    final got = await bridge.requestAccess();
    _accessEpoch++;
    _access = got;
    if (got != SweepAccess.granted) {
      _refused = got == SweepAccess.limited
          ? SweepAccessRefused.limited
          : SweepAccessRefused.denied;
      notifyListeners();
      return;
    }
    _refused = null;
    await ledger.setEnabled(true);
    _launched = _signedIn;
    notifyListeners();
    if (_signedIn) {
      _watch();
      kick();
    }
    unawaited(refreshInRange());
  }

  /// The switch turned off: the pass stops at its next photo, and nothing
  /// watches the library.
  Future<void> disable() async {
    final ledger = _ledger;
    if (ledger == null) return;
    await ledger.setEnabled(false);
    _unwatch();
    _service?.stop();
    notifyListeners();
  }

  Future<void> setMode(SweepMode mode) async => _ledger?.setMode(mode);

  Future<void> setBackfillStart(DateTime start) async {
    await _ledger?.setBackfillStart(start);
    await refreshInRange();
  }

  /// Counts the images from the backfill start to now.
  Future<void> refreshInRange() async {
    final bridge = _bridge, ledger = _ledger;
    if (bridge == null || ledger == null) return;
    try {
      _inRange = (await bridge.fetchImages(since: ledger.backfillStart, limit: 1)).total;
    } catch (e) {
      _inRange = null;
      debugPrint('camera sweep: photos in range could not be counted ($e)');
    }
    if (!_disposed) notifyListeners();
  }

  /// "Start over" (§18): this phone forgets every verdict and the backfill's
  /// progress. A local reset cannot be refused by a server, but its write can
  /// fail — that sentence goes in the panel. null when done.
  Future<String?> startOver() async {
    final ledger = _ledger;
    if (ledger == null) return null;
    try {
      await ledger.reset();
    } catch (e) {
      debugPrint('camera sweep: the ledger could not be reset ($e)');
      return CameraSweepHost.notSaved;
    }
    await refreshInRange();
    return null;
  }

  /// Opens this app's page in the system settings (both refusals' action).
  Future<void> openSettings() async {
    await _bridge?.openSettings();
  }

  @override
  void dispose() {
    _disposed = true;
    _unwatch();
    _session?.removeListener(_onSession);
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
