import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'auth_service.dart';

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
  /// returns a canned response, so the api/* conformance suite can assert
  /// request construction without touching the network.
  set httpClientAdapter(HttpClientAdapter adapter) =>
      _client.httpClientAdapter = adapter;

  // Separate client for GCS direct uploads — no auth header, no base URL.
  final Dio _rawClient = Dio(BaseOptions(
    sendTimeout: const Duration(minutes: 5),
    receiveTimeout: const Duration(minutes: 5),
  ));

  ApiService._() {
    _client = Dio(BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _client.interceptors.add(_AuthInterceptor());
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response =
          await _client.get(path, queryParameters: queryParameters);
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
      final response = await _client.post(path, data: data);
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
      final response = await _client.put(path, data: data);
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
      final response = await _client.patch(path, data: data);
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
      final response =
          await _client.delete(path, queryParameters: queryParameters, data: data);
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
