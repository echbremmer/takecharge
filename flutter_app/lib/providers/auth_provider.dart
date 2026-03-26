import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/auth.dart';
import 'server_url_provider.dart';

enum AuthStatus { loading, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final Map<String, dynamic>? user;
  final String? error;

  const AuthState({required this.status, this.user, this.error});

  AuthState copyWith({AuthStatus? status, Map<String, dynamic>? user, String? error, bool clearError = false}) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: clearError ? null : (error ?? this.error),
      );
}

class AuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;

  AuthNotifier(this._ref) : super(const AuthState(status: AuthStatus.loading));

  Future<void> checkAuth() async {
    try {
      final user = await authApi.me();
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } catch (_) {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login(String username, String password) async {
    try {
      final user = await authApi.login(username, password);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      );
      return false;
    }
  }

  Future<bool> signup(String username, String password) async {
    try {
      final user = await authApi.signup(username, password);
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: _extractError(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    await authApi.logout();
    await _ref.read(serverUrlProvider.notifier).clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  String _extractError(Object e) {
    // Dio errors carry response body
    return e.toString();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
