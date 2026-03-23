import 'client.dart';

class HabitsApi {
  final _client = ApiClient.instance;

  // ── Habits list ───────────────────────────────────────────────────────────
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

  // ── Timer habit ───────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> getActive(int habitId) async {
    try {
      final res = await _client.get('/api/habits/$habitId/active');
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return null; // 404 = no active session
    }
  }

  Future<void> startActive(int habitId, int startMs) async {
    await _client.post('/api/habits/$habitId/active', data: {'start': startMs});
  }

  Future<void> adjustActive(int habitId, int newStartMs) async {
    await _client.put('/api/habits/$habitId/active', data: {'start': newStartMs});
  }

  Future<void> stopActive(int habitId) async {
    await _client.delete('/api/habits/$habitId/active');
  }

  Future<List<dynamic>> getSessions(int habitId) async {
    final res = await _client.get('/api/habits/$habitId/sessions');
    return res.data as List<dynamic>;
  }

  Future<void> deleteSession(int habitId, int sessionId) async {
    await _client.delete('/api/habits/$habitId/sessions/$sessionId');
  }

  Future<List<dynamic>> getGoals(int habitId) async {
    final res = await _client.get('/api/habits/$habitId/goals');
    return res.data as List<dynamic>;
  }

  Future<Map<String, dynamic>> setGoal(int habitId, int weekStartMs, int valueMs) async {
    final res = await _client.post('/api/habits/$habitId/goals',
        data: {'week_start_ms': weekStartMs, 'value': valueMs});
    return res.data as Map<String, dynamic>;
  }

  // ── Daily habit ───────────────────────────────────────────────────────────
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
    final res = await _client.get('/api/habits/$habitId/logs',
        params: dayMs != null ? {'day': dayMs} : null);
    return res.data as List<dynamic>;
  }

  Future<void> logDelta(int habitId, int targetId, int dayMs, int delta) async {
    await _client.post('/api/habits/$habitId/logs',
        data: {'target_id': targetId, 'day_ms': dayMs, 'delta': delta});
  }

  // ── Todo habit ────────────────────────────────────────────────────────────
  Future<List<dynamic>> getTodos(int habitId, {int? weekMs}) async {
    final res = await _client.get('/api/habits/$habitId/todos',
        params: weekMs != null ? {'week': weekMs} : null);
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
