import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// API base is configurable at build time via --dart-define=API_BASE=https://...
// Defaults to same-origin (web) or localhost (dev mobile).
const String _defaultBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: '',
);

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  late final Dio dio;
  late final String baseUrl;

  Future<void> init() async {
    baseUrl = _defaultBase.isNotEmpty ? _defaultBase : 'http://localhost:8080';

    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
      // Required on web: tells the browser's XHR to include cookies on
      // cross-origin requests (Flutter dev server ≠ Go backend port).
      extra: {'withCredentials': true},
    );

    dio = Dio(options);

    // On non-web platforms, manage the session token manually via secure
    // storage. This is more reliable than PersistCookieJar across different
    // hosts and protocols (HTTP dev vs HTTPS production).
    if (!kIsWeb) {
      dio.interceptors.add(_SessionInterceptor());
    }
  }

  // Called by auth layer after login/signup with the token from the response body.
  Future<void> setSessionToken(String token) =>
      _SessionInterceptor._storage.write(
          key: _SessionInterceptor._key, value: token);

  // Called by auth layer on logout.
  Future<void> clearSessionToken() =>
      _SessionInterceptor._storage.delete(key: _SessionInterceptor._key);

  // Convenience helpers
  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      dio.put(path, data: data);

  Future<Response> delete(String path) => dio.delete(path);

  Future<Response> postForm(String path, FormData formData) =>
      dio.post(path, data: formData);
}

// Intercepts every request/response to manage the session cookie manually.
// On request: reads the stored token and injects it as a Cookie header.
// On response: looks for Set-Cookie and saves or clears the session token.
class _SessionInterceptor extends Interceptor {
  static const _storage = FlutterSecureStorage();
  static const _key = 'session_token';

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: _key);
    if (token != null && token.isNotEmpty) {
      options.headers['Cookie'] = 'session=$token';
    }
    handler.next(options);
  }

}
