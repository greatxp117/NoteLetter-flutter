import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;

  const ApiException(this.statusCode, this.message);

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class UnauthorizedException extends ApiException {
  const UnauthorizedException() : super(401, 'Session expired. Please log in again.');
}

class ApiService {
  static final ApiService instance = ApiService._();

  static const _baseUrl =
      'https://us-central1-luxletter-b7a40.cloudfunctions.net';

  late final Dio _client;

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
    if (e.response?.data is Map) {
      final errField = (e.response!.data as Map)['error'];
      if (errField is String && errField.isNotEmpty) message = errField;
    } else if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      message = 'Request timed out. Check your connection and try again.';
    } else if (e.type == DioExceptionType.connectionError) {
      message = 'Could not connect to the server. Check your internet connection.';
    }

    return ApiException(e.response?.statusCode ?? 0, message);
  }
}

class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await AuthService.instance.getIdToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}
