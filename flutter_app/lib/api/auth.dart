import 'package:dio/dio.dart';
import 'client.dart';

class AuthApi {
  final _client = ApiClient.instance;

  Future<Map<String, dynamic>> me() async {
    final res = await _client.get('/api/auth/me');
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final res = await _client.post('/api/auth/login',
        data: {'username': username, 'password': password});
    return res.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> signup(String username, String password) async {
    final res = await _client.post('/api/auth/signup',
        data: {'username': username, 'password': password});
    return res.data as Map<String, dynamic>;
  }

  Future<void> logout() async {
    await _client.post('/api/auth/logout');
  }
}

// Single instance
final authApi = AuthApi();
