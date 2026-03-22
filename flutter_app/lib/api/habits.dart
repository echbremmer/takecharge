import 'client.dart';

class HabitsApi {
  final _client = ApiClient.instance;

  Future<List<dynamic>> list() async {
    final res = await _client.get('/api/habits');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> create(String name, String type) async {
    final res = await _client.post('/api/habits', data: {'name': name, 'type': type});
    return res.data as Map<String, dynamic>;
  }

  Future<void> delete(int id) async {
    await _client.delete('/api/habits/$id');
  }

  // --- Timer habit ---
  Future<Map<String, dynamic>?> getActive() async {
    try {
      final res = await _client.get('/api/active');
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return null; // 404 = no active fast
    }
  }

  Future<void> startFast(int startMs) async {
    await _client.post('/api/active', data: {'start': startMs});
  }

  Future<void> stopFast() async {
    await _client.delete('/api/active');
  }

  Future<List<dynamic>> getSessions() async {
    final res = await _client.get('/api/sessions');
    return res.data as List<dynamic>;
  }

  // --- Daily habit ---
  Future<List<dynamic>> getTargets(int habitId) async {
    final res = await _client.get('/api/habits/$habitId/targets');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createTarget(int habitId, Map<String, dynamic> body) async {
    final res = await _client.post('/api/habits/$habitId/targets', data: body);
    return res.data as Map<String, dynamic>;
  }

  Future<void> updateTarget(int habitId, int targetId, Map<String, dynamic> body) async {
    await _client.put('/api/habits/$habitId/targets/$targetId', data: body);
  }

  Future<void> deleteTarget(int habitId, int targetId) async {
    await _client.delete('/api/habits/$habitId/targets/$targetId');
  }

  Future<List<dynamic>> getLogs(int habitId, {int? dayMs}) async {
    final res = await _client.get(
      '/api/habits/$habitId/logs',
      params: dayMs != null ? {'day': dayMs} : null,
    );
    return res.data as List<dynamic>;
  }

  Future<void> logDelta(int habitId, int targetId, int dayMs, int delta) async {
    await _client.post('/api/habits/$habitId/logs',
        data: {'target_id': targetId, 'day_ms': dayMs, 'delta': delta});
  }

  // --- Todo habit ---
  Future<List<dynamic>> getTodos(int habitId, {int? weekMs}) async {
    final res = await _client.get(
      '/api/habits/$habitId/todos',
      params: weekMs != null ? {'week': weekMs} : null,
    );
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> createTodo(int habitId, String text, int weekMs) async {
    final res = await _client.post('/api/habits/$habitId/todos',
        data: {'text': text, 'week_ms': weekMs});
    return res.data as Map<String, dynamic>;
  }

  Future<void> toggleTodo(int habitId, int todoId, bool done) async {
    await _client.put('/api/habits/$habitId/todos/$todoId', data: {'done': done});
  }

  Future<void> deleteTodo(int habitId, int todoId) async {
    await _client.delete('/api/habits/$habitId/todos/$todoId');
  }
}

final habitsApi = HabitsApi();
