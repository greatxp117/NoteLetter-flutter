import 'dart:typed_data';
import 'package:dio/dio.dart';
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

  static const _baseUrl =
      'https://us-central1-noteletter-7a111.cloudfunctions.net';

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
