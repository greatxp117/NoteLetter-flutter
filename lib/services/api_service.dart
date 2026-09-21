import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'auth_service.dart';
import 'endpoint_budgets.dart';
import 'analytics.dart';

/// Resolves the Firebase ID token for INV-01. Defaults to the signed-in user;
/// swappable in the conformance harness so request construction is testable
/// without a live Firebase session (mirrors the web reference's mocked auth).
typedef TokenProvider = Future<String?> Function();

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? errorCode;
  final String? requestId;

  const ApiException(this.statusCode, this.message, {this.errorCode, this.requestId});

  @override
  String toString() => 'ApiException($statusCode, $errorCode): $message';
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException()
      : super(401, 'Session expired. Please log in again.', errorCode: 'UNAUTHORIZED');
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
    tokenProvider = _defaultTokenProvider;
  }

  // Separate client for GCS direct uploads — no auth header, no base URL.
  final Dio _rawClient = Dio(BaseOptions(
    sendTimeout: const Duration(minutes: 5),
    receiveTimeout: const Duration(minutes: 5),
  ));

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
    _defaultTokenProvider = tokenProvider;
  }

  /// The per-call receive budget (C5). Kept as one helper so every verb reads
  /// the same table — six call sites each doing their own lookup is six places
  /// for one to be forgotten.
  Options _budget(String path) =>
      Options(receiveTimeout: clientTimeoutFor(path));

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _client.get(path, queryParameters: queryParameters, options: _budget(path));
      return response.data as Map<String, dynamic>;
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
      return response.data as Map<String, dynamic>;
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
      return response.data as Map<String, dynamic>;
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
      return response.data as Map<String, dynamic>;
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
      return response.data as Map<String, dynamic>;
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
    Analytics.track('request_failed', {
      'endpoint': Analytics.endpointName(e.requestOptions.path),
      'error_code': (body['error_code'] as String?) ?? 'NONE',
      'status': e.response?.statusCode ?? 0,
    });

    if (e.response?.statusCode == 401) return const UnauthorizedException();

    String message = 'Something went wrong. Please try again.';
    String? errorCode;
    String? requestId;
    if (e.response?.data is Map) {
      final body = e.response!.data as Map;
      final errField = body['error'] ?? body['message'];
      if (errField is String && errField.isNotEmpty) message = errField;
      errorCode = body['error_code'] as String?;
      requestId = body['request_id'] as String?;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      message = 'Request timed out. Check your connection and try again.';
    } else if (e.type == DioExceptionType.connectionError) {
      message = 'Could not connect to the server. Check your internet connection.';
    }

    return ApiException(e.response?.statusCode ?? 0, message,
        errorCode: errorCode, requestId: requestId);
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
