import 'client.dart';

class SummaryApi {
  final _client = ApiClient.instance;

  Future<Map<String, dynamic>> get() async {
    final res = await _client.get('/api/summary');
    return res.data as Map<String, dynamic>;
  }

  Future<void> seed() async {
    await _client.post('/api/dev/seed', data: {});
  }
}

final summaryApi = SummaryApi();
