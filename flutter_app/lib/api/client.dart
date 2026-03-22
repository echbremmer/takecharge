import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';

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
    // Dev default: always localhost:8080.
    // Production: pass --dart-define=API_BASE= (empty = same-origin) or a full URL.
    baseUrl = _defaultBase.isNotEmpty ? _defaultBase : 'http://localhost:8080';

    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      contentType: 'application/json',
    );

    dio = Dio(options);

    // On non-web platforms use a persistent CookieJar so session survives app restarts
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      final cookieJar = PersistCookieJar(
        storage: FileStorage('${dir.path}/.cookies/'),
      );
      dio.interceptors.add(CookieManager(cookieJar));
    }
    // On web the browser handles cookies automatically (HttpOnly cookies work natively)
  }

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
