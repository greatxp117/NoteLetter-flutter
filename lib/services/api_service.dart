import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'auth_service.dart';
import 'endpoint_budgets.dart';
import 'analytics.dart';
import '../shared/plan_limit_signal.dart';

/// Resolves the Firebase ID token for INV-01. Defaults to the signed-in user;
/// swappable in the conformance harness so request construction is testable
/// without a live Firebase session (mirrors the web reference's mocked auth).
typedef TokenProvider = Future<String?> Function();

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;
  final String? requestId;

  /// True exactly when [message] is the ENVELOPE's own sentence — the `error`
  /// or `message` the backend wrote — and false when it is one of `_handle`'s
  /// constants standing in for a body that carried none (C11).
  ///
  /// Without this a site cannot tell the two apart: both arrive in the same
  /// field, so "Please wait 43 seconds before regenerating again." and
  /// "Something went wrong. Please try again." are one value, and a screen
  /// that wants to render the server's words verbatim has no way to ask
  /// whether there are any. That is what [cooldownSentence] asks.
  final bool serverSentence;

  const ApiException(this.statusCode, this.message,
      {this.errorCode, this.requestId, this.serverSentence = false});

  @override
  String toString() => 'ApiException($statusCode, $errorCode): $message';
}

/// A cooldown's sentence is the SERVER's (audit B11 on the reference, C11
/// here). Mirrors `cooldownSentence` in `NoteLetter-web/src/api.js`.
///
/// Every cooldown branch in the backend computes the exact remaining wait and
/// says it — "Please wait 43 seconds before regenerating again." — and this
/// client overwrote that with a constant guess: "give it a minute" (60s),
/// "less than a minute ago" (60s), "try again in a few minutes" (300s). A
/// guess is wrong in both directions at once (it reads as a minute when three
/// seconds remain, and as a minute when fifty-five do) and it goes stale
/// silently the day a cooldown constant moves — nothing ties the two numbers
/// together. So: render what came back.
///
/// [fallback] covers only the refusal that carried no sentence at all, where
/// `message` is a constant of ours and quoting it would say nothing about the
/// wait.
String cooldownSentence(ApiException e, String fallback) {
  if (!e.serverSentence) return fallback;
  final sentence = e.message.trim();
  return sentence.isEmpty ? fallback : sentence;
}

class UnauthorizedException extends ApiException {
  /// The server's own sentence, where the 401 carried one (C8). It stays a
  /// distinct TYPE because notifiers catch it by type to route to sign-in —
  /// but the constant it used to hold unconditionally threw away the only
  /// words that could tell an expired session from a revoked token or a clock
  /// that has drifted, which are three different next moves (ADR-070).
  const UnauthorizedException([String? serverSentence])
      : super(401, serverSentence ?? 'Session expired. Please log in again.',
            errorCode: 'UNAUTHORIZED', serverSentence: serverSentence != null);
}

class ApiService {
  static final ApiService instance = ApiService._();

  /// Emulator switch (umbrella law 1: **all** Firestore/Functions-touching dev
  /// and testing runs against the emulator suite, never prod
  /// `noteletter-7a111`). Compile-time so a release build cannot carry it.
  ///
  ///   flutter run --dart-define=USE_EMULATOR=true
  static const useEmulator =
      bool.fromEnvironment('USE_EMULATOR', defaultValue: false);

  /// Loopback differs by platform: an Android emulator reaches the host at
  /// 10.0.2.2, while an iOS simulator and desktop share the host's localhost.
  /// Getting this wrong fails as a connection timeout with no other clue.
  static String get emulatorHost =>
      !kIsWeb && Platform.isAndroid ? '10.0.2.2' : 'localhost';

  /// Ports are overridable so this suite can run BESIDE another workspace's
  /// emulators on the defaults — the same reason the web app takes
  /// `VITE_EMULATOR_*_PORT`. A collision does not announce itself: the second
  /// suite simply refuses to start, or worse, the app talks to the first one.
  static const firestorePort =
      int.fromEnvironment('EMULATOR_FIRESTORE_PORT', defaultValue: 8080);
  static const authPort =
      int.fromEnvironment('EMULATOR_AUTH_PORT', defaultValue: 9099);
  static const functionsPort =
      int.fromEnvironment('EMULATOR_FUNCTIONS_PORT', defaultValue: 5001);

  /// The functions emulator segfaults on this Mac, so local `fn_*` are served
  /// by `functions/dev_server.py`, which is a plain HTTP shim with no
  /// `/{project}/{region}` path prefix. Set EMULATOR_FUNCTIONS_SHIM=true when
  /// pointing at it.
  static const useFunctionsShim =
      bool.fromEnvironment('EMULATOR_FUNCTIONS_SHIM', defaultValue: false);

  static String get _baseUrl {
    if (!useEmulator) {
      return 'https://us-central1-noteletter-7a111.cloudfunctions.net';
    }
    final root = 'http://$emulatorHost:$functionsPort';
    return useFunctionsShim ? root : '$root/noteletter-7a111/us-central1';
  }

  late final Dio _client;

  /// INV-01 token source. Overridden by the conformance harness.
  TokenProvider tokenProvider = () => AuthService.instance.getIdToken();

  /// Test seam: inject a Dio adapter that captures the outgoing request and
  /// returns a canned response, so a suite can assert request construction —
  /// or answer with a real status and body — without touching the network.
  set httpClientAdapter(HttpClientAdapter adapter) =>
      _client.httpClientAdapter = adapter;

  late final HttpClientAdapter _defaultAdapter;
  late final TokenProvider _defaultTokenProvider;

  /// Puts both seams back (C4g).
  ///
  /// This was a **one-way door**: `ApiService.instance` is a static singleton,
  /// both seams are set on it, and nothing could undo either. `api_requests_
  /// test` set the adapter and the token provider in `setUpAll` and left them
  /// there, so every suite that ran after it in the same process inherited a
  /// canned transport — green for as long as nothing else made a request, and
  /// a mystery on the day something did. It is the shape `test_isolation_test`
  /// already refuses for `FirestoreService.instance`, one layer over.
  @visibleForTesting
  void resetTestSeams() {
    _client.httpClientAdapter = _defaultAdapter;
    _rawClient.httpClientAdapter = _defaultRawAdapter;
    tokenProvider = _defaultTokenProvider;
  }

  // Separate client for GCS direct uploads — no auth header, no base URL.
  final Dio _rawClient = Dio(BaseOptions(
    sendTimeout: const Duration(minutes: 5),
    receiveTimeout: const Duration(minutes: 5),
  ));

  /// Test seam for the GCS direct-upload client (INV-08's bare PUT).
  ///
  /// Separate from [httpClientAdapter] because `_rawClient` is a separate Dio
  /// with no auth header and no base URL: a suite that canned only the `fn_*`
  /// transport still went to the real network here, so the half of an upload
  /// that actually moves the bytes could not be driven at all.
  set rawClientAdapter(HttpClientAdapter adapter) =>
      _rawClient.httpClientAdapter = adapter;

  late final HttpClientAdapter _defaultRawAdapter;

  ApiService._() {
    _client = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      // No flat receive deadline (C5). It was 30s, which is SHORTER than every
      // deadline this backend deploys — 47 endpoints at 60s and 13 above it —
      // so the client gave up first on every slow request and reported a
      // failure the server never had. The budget is per call now, from
      // `clientTimeoutFor`, and a request with no entry falls back to the
      // fleet norm rather than to the old 30s.
      receiveTimeout: kDefaultTimeout,
      headers: {'Content-Type': 'application/json'},
    ));
    _client.interceptors.add(_AuthInterceptor());
    // Captured rather than reconstructed: Dio picks its adapter by platform,
    // and a reset that builds a new one is a reset to something that was
    // never there.
    _defaultAdapter = _client.httpClientAdapter;
    _defaultRawAdapter = _rawClient.httpClientAdapter;
    _defaultTokenProvider = tokenProvider;
  }

  /// The per-call receive budget (C5). Kept as one helper so every verb reads
  /// the same table — six call sites each doing their own lookup is six places
  /// for one to be forgotten.
  Options _budget(String path) =>
      Options(receiveTimeout: clientTimeoutFor(path));

  /// A 2xx body this client can read, or a rejection — never an empty answer.
  ///
  /// This was `response.data as Map<String, dynamic>` at five call sites (C8).
  /// A 2xx whose body is not JSON — a proxy's error page, a truncated
  /// response, a deploy serving something else — threw a `TypeError` from the
  /// cast: not an `ApiException`, so no screen could render it as §14 and the
  /// one place that counts `request_failed` never saw it. ADR-112 makes it an
  /// ordinary rejection, carrying the status it arrived with.
  Map<String, dynamic> _decode(Response<dynamic> response, String path) {
    final data = response.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    final status = response.statusCode ?? 0;
    _trackFailure(path, null, status);
    throw ApiException(status, _noEnvelope(status));
  }

  /// `api/endpoints.md` §A body that is NOT this envelope (ADR-112). The words
  /// are the contract's, the same in all four clients, gated by NON-ENVELOPE.
  static String _noEnvelope(int status) =>
      'The server did not answer as expected (HTTP $status).';

  void _trackFailure(String path, String? errorCode, int status) {
    Analytics.track('request_failed', {
      'endpoint': Analytics.endpointName(path),
      'error_code': errorCode ?? 'NONE',
      'status': status,
    });
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _client.get(path, queryParameters: queryParameters, options: _budget(path));
      return _decode(response, path);
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _client.post(path, data: data, options: _budget(path));
      return _decode(response, path);
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _client.put(path, data: data, options: _budget(path));
      return _decode(response, path);
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _client.patch(path, data: data, options: _budget(path));
      return _decode(response, path);
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  Future<Map<String, dynamic>> delete(
    String path, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic>? data,
  }) async {
    try {
      final response = await _client.delete(path,
          queryParameters: queryParameters, data: data, options: _budget(path));
      return _decode(response, path);
    } on DioException catch (e) {
      throw _handle(e);
    }
  }

  /// PUT raw bytes to a GCS signed URL.
  /// Must NOT include the Authorization header.
  Future<void> putBytes(
    String url,
    Uint8List bytes,
    String mimeType,
  ) async {
    try {
      await _rawClient.put(
        url,
        data: bytes,
        options: Options(
          headers: {'Content-Type': mimeType},
          validateStatus: (s) => s != null && s < 400,
        ),
      );
    } on DioException catch (e) {
      throw ApiException(
        e.response?.statusCode ?? 0,
        'Storage upload failed. Please try again.',
      );
    }
  }

  ApiException _handle(DioException e) {
    // The ONE place every verb's failure passes through, which is why the
    // measurement sits here and not at a call site — the reference's `call()`
    // wraps every `fn_*` for the same reason. Before the 401 exit, because a
    // session that has expired mid-use is a failure the operator wants counted
    // exactly like any other (4.41.0, ADR-079).
    //
    // `endpointName` strips the query string: six builders put one on the path
    // and the params of `fn_list_cloud_files` and `fn_check_source_freshness`
    // are the reader's own cloud folder ids (INV-25b).
    final body = e.response?.data is Map ? e.response!.data as Map : const {};
    final status = e.response?.statusCode ?? 0;
    final errorCode = body['error_code'] as String?;
    final requestId = body['request_id'] as String?;
    // The envelope's own sentence, where the response carried one. Read BEFORE
    // the 401 exit so that branch can quote it too (C8).
    final errField = body['error'] ?? body['message'];
    final serverSentence =
        errField is String && errField.isNotEmpty ? errField : null;

    _trackFailure(e.requestOptions.path, errorCode, status);

    // A plan refusal (4.79.0, ADR-113) is the one rejection another screen
    // draws a consequence of: the Settings Plan row refetches its measured
    // figures on this signal rather than counting anything itself. Fired here,
    // beside the measurement, because this is the one place every verb's
    // failure passes through — a call site would cover the surface it knows.
    if (errorCode == 'PLAN_LIMIT') PlanLimitSignal.fire();

    if (status == 401) return UnauthorizedException(serverSentence);

    // One choice, not an `else if` chain over the BODY. The old first arm was
    // `data is Map`, so a timeout or a dropped connection that happened to
    // carry a Map with no `error` in it fell into that arm, found nothing, and
    // kept the generic constant — losing its own sentence to a branch that had
    // no answer either (C8).
    final String message;
    if (serverSentence != null) {
      message = serverSentence;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      message = 'Request timed out. Check your connection and try again.';
    } else if (e.type == DioExceptionType.connectionError) {
      message = 'Could not connect to the server. Check your internet connection.';
    } else if (e.response != null) {
      // ADR-112: the server answered, and what it sent is not our envelope — a
      // load-balancer's HTML 504, a proxy's error page. This was "Something
      // went wrong. Please try again.": no status, no words, and a 504
      // indistinguishable from a malformed body in a support thread.
      message = _noEnvelope(status);
    } else {
      // No response at all, and not a timeout or a refused connection. Saying
      // the server answered unexpectedly would be a claim about a server we
      // never heard from.
      message = 'Something went wrong. Please try again.';
    }

    return ApiException(status, message,
        errorCode: errorCode,
        requestId: requestId,
        // Only the first arm above quoted the envelope; every other one is a
        // constant of ours (C11).
        serverSentence: serverSentence != null);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await ApiService.instance.tokenProvider();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
