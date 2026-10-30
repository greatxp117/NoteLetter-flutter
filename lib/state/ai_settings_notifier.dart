import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/error_text.dart';
import '../services/firestore_service.dart';

/// The generative-AI switch's four states (web `genAIState`). Only [on] draws
/// a generated surface (api/ai.md §What the switch hides): [loading] and
/// [failed] draw none of them, so a reader who switched AI off never sees one
/// flash in and out while the document is read (INV-34).
enum GenAI { loading, on, off, failed }

/// Video reading's states (web `videoAIChoice`): [loading] and [failed] draw
/// no control (INV-24); otherwise the STORED choice.
enum VideoAI { loading, openai, claude, failed }

/// `/users/{uid}/settings/ai`, subscribed ONCE app-wide (5.29.0, ADR-186,
/// INV-34; 5.33.0, ADR-190, INV-36) — every gated surface and both Settings
/// rows read this one object, so they cannot disagree.
///
/// **Reading rule** (api/ai.md): `generativeAI` is off only for a stored
/// literal `false` — absent, `"false"`, `0` are on; `videoAI` is Claude only
/// for a stored literal `"claude"` — absent, `"Claude"`, `""` are OpenAI.
///
/// **Write before you move.** [setGenerativeAI] and [setVideoAI] each send
/// exactly their own key, hold their control while the request is out, and
/// change nothing locally: the control moves when the subscription delivers
/// the stored value. A refusal is the server's sentence ([aiError],
/// [videoError]), and the control stays where it was.
///
/// [start] is idempotent and lazy (nothing touches Firestore until something
/// asks), and binds to the signed-in account: called under another account it
/// subscribes again, so a switch of accounts never shows the last one's
/// choice. The seams exist for the widget tests, which have no Firebase.
class AiSettingsNotifier extends ChangeNotifier {
  AiSettingsNotifier({
    Stream<Map<String, dynamic>> Function()? subscribe,
    Future<Object?> Function({bool? generativeAI, String? videoAI})? write,
    String? Function()? uid,
  }) : _subscribe = subscribe,
       _write = write,
       _uidOf = uid;

  final Stream<Map<String, dynamic>> Function()? _subscribe;
  final Future<Object?> Function({bool? generativeAI, String? videoAI})? _write;
  final String? Function()? _uidOf;

  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _bound;
  Map<String, dynamic>? _data;
  String? _error;

  bool _aiBusy = false;
  bool _videoBusy = false;
  String? _aiError;
  String? _videoError;

  /// Only a stored literal `false` is off (api/ai.md §Reading it).
  static bool generativeAiOf(Map<String, dynamic>? data) =>
      data?['generativeAI'] != false;

  /// Only a stored literal `"claude"` is Claude (api/ai.md §Video reading).
  static VideoAI videoAiOf(Map<String, dynamic>? data) =>
      data?['videoAI'] == 'claude' ? VideoAI.claude : VideoAI.openai;

  String? _currentUid() {
    final f = _uidOf;
    if (f != null) return f();
    if (_subscribe != null) return 'test';
    return AuthService.instance.currentUser?.uid;
  }

  void start() {
    final uid = _currentUid();
    if (_sub != null && uid == _bound) return;
    _sub?.cancel();
    _bound = uid;
    // A Retry (or another account) reads again from unread: say so now, or a
    // failure block would stand until the first snapshot arrives.
    final changed = _data != null || _error != null;
    _data = null;
    _error = null;
    if (changed) notifyListeners();
    final stream =
        (_subscribe ?? FirestoreService.instance.subscribeAiSettings)();
    _sub = stream.listen(
      (d) {
        _data = d;
        _error = null;
        notifyListeners();
      },
      onError: (Object e) {
        _error = describeSdkError(e);
        // The next start — a Retry, the next screen — reads again rather
        // than keeping a refused subscription for the life of the app.
        _sub?.cancel();
        _sub = null;
        notifyListeners();
      },
    );
  }

  GenAI get genAI {
    if (_error != null) return GenAI.failed;
    if (_data == null) return GenAI.loading;
    return generativeAiOf(_data) ? GenAI.on : GenAI.off;
  }

  /// Whether generated surfaces are drawn: only a READ `on`.
  bool get aiOn => genAI == GenAI.on;

  VideoAI get videoAI {
    if (_error != null) return VideoAI.failed;
    if (_data == null) return VideoAI.loading;
    return videoAiOf(_data);
  }

  /// The subscription's failure (INV-24), the section's one failure.
  String? get error => _error;
  bool get aiBusy => _aiBusy;
  bool get videoBusy => _videoBusy;
  String? get aiError => _aiError;
  String? get videoError => _videoError;

  Future<String?> _send({bool? generativeAI, String? videoAI}) async {
    try {
      final w = _write;
      if (w != null) {
        await w(generativeAI: generativeAI, videoAI: videoAI);
      } else {
        await Api.instance.updateAiSettings(
          generativeAI: generativeAI,
          videoAI: videoAI,
        );
      }
      return null;
    } on ApiException catch (e) {
      return e.message;
    } catch (e) {
      return describeSdkError(e);
    }
  }

  /// The switch row: `fn_ai_settings` PUT `{generativeAI}`. Returns the
  /// refusal's sentence, or null.
  Future<String?> setGenerativeAI(bool value) async {
    if (_aiBusy) return null;
    _aiBusy = true;
    _aiError = null;
    notifyListeners();
    final err = await _send(generativeAI: value);
    _aiBusy = false;
    _aiError = err;
    notifyListeners();
    return err;
  }

  /// Video reading: `fn_ai_settings` PUT `{videoAI}` alone. A press on the
  /// stored choice sends nothing.
  Future<String?> setVideoAI(VideoAI value) async {
    if (_videoBusy || value == videoAI) return null;
    if (value != VideoAI.openai && value != VideoAI.claude) return null;
    _videoBusy = true;
    _videoError = null;
    notifyListeners();
    final err = await _send(
      videoAI: value == VideoAI.claude ? 'claude' : 'openai',
    );
    _videoBusy = false;
    _videoError = err;
    notifyListeners();
    return err;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
