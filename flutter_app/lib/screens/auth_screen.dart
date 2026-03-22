import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../main.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // Check auth on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authProvider.notifier).checkAuth();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    final notifier = ref.read(authProvider.notifier);
    final isLogin = _tabs.index == 0;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final ok = isLogin
        ? await notifier.login(username, password)
        : await notifier.signup(username, password);

    if (mounted) {
      setState(() => _loading = false);
      if (ok) context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authProvider).error;

    return Scaffold(
      backgroundColor: AppTheme.sageFaint,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Logo / title
                const SizedBox(height: 32),
                Text(
                  'TakeCharge',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        color: AppTheme.sageDark,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your daily habit tracker',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMid,
                      ),
                ),
                const SizedBox(height: 40),

                // Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TabBar(
                          controller: _tabs,
                          labelColor: AppTheme.sageDark,
                          unselectedLabelColor: AppTheme.textLight,
                          indicatorColor: AppTheme.sageDark,
                          tabs: const [
                            Tab(text: 'Login'),
                            Tab(text: 'Sign up'),
                          ],
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _usernameController,
                          decoration: const InputDecoration(labelText: 'Username'),
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          decoration: const InputDecoration(labelText: 'Password'),
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                        if (error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            error,
                            style: const TextStyle(color: Colors.red, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Continue'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
