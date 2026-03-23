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
    final data = res.data as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token != null && token.isNotEmpty) {
      await _client.setSessionToken(token);
    }
    return data;
  }

  Future<Map<String, dynamic>> signup(String username, String password) async {
    final res = await _client.post('/api/auth/signup',
        data: {'username': username, 'password': password});
    final data = res.data as Map<String, dynamic>;
    final token = data['token'] as String?;
    if (token != null && token.isNotEmpty) {
      await _client.setSessionToken(token);
    }
    return data;
  }

  Future<void> logout() async {
    await _client.post('/api/auth/logout');
    await _client.clearSessionToken();
  }
}

// Single instance
final authApi = AuthApi();
