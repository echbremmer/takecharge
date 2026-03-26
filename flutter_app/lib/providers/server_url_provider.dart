import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';

enum ServerUrlStatus { loading, set, unset }

class ServerUrlState {
  final ServerUrlStatus status;
  final String? url;
  final String? error;

  const ServerUrlState({required this.status, this.url, this.error});

  ServerUrlState copyWith({
    ServerUrlStatus? status,
    String? url,
    String? error,
    bool clearError = false,
  }) =>
      ServerUrlState(
        status: status ?? this.status,
        url: url ?? this.url,
        error: clearError ? null : (error ?? this.error),
      );
}

class ServerUrlNotifier extends StateNotifier<ServerUrlState> {
  ServerUrlNotifier()
      : super(const ServerUrlState(status: ServerUrlStatus.loading));

  Future<void> load() async {
    final saved = await ApiClient.instance.loadServerUrl();
    if (saved != null && saved.isNotEmpty) {
      state = ServerUrlState(status: ServerUrlStatus.set, url: saved);
    } else {
      state = const ServerUrlState(status: ServerUrlStatus.unset);
    }
  }

  /// Validates, persists, and reinitialises the API client with [url].
  /// Returns true on success, false if the server was not reachable.
  Future<bool> save(String url) async {
    state = state.copyWith(clearError: true);
    await ApiClient.instance.reinit(url);
    // Probe the server: any HTTP response (even 401) means it's reachable.
    try {
      await ApiClient.instance.dio.get(
        '/api/auth/me',
        options: Options(validateStatus: (_) => true),
      );
    } on DioException {
      // Network error — server not reachable at this URL.
      state = state.copyWith(
        status: ServerUrlStatus.unset,
        error: 'Could not reach server at $url',
      );
      return false;
    }
    state = ServerUrlState(status: ServerUrlStatus.set, url: url);
    return true;
  }

  void clearError() => state = state.copyWith(clearError: true);
}

final serverUrlProvider =
    StateNotifierProvider<ServerUrlNotifier, ServerUrlState>(
  (ref) => ServerUrlNotifier(),
);
