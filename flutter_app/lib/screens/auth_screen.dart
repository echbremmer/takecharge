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

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;

    setState(() => _loading = true);
    final notifier = ref.read(authProvider.notifier);
    final ok = _isLogin
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
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const SizedBox(height: 64),

                // Title
                Text(
                  'TAKECHARGE',
                  style: const TextStyle(
                    color: AppTheme.sageDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3.5,
                    fontFamily: 'Manrope',
                  ),
                ),

                const SizedBox(height: 40),

                // Card
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.sageDark.withOpacity(0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Heading
                      Text(
                        _isLogin ? 'Sign in' : 'Sign up',
                        style: const TextStyle(
                          color: AppTheme.textDark,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Manrope',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Username field
                      _FieldLabel('USERNAME'),
                      const SizedBox(height: 6),
                      _PillTextField(
                        controller: _usernameController,
                        hint: '',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      _FieldLabel('PASSWORD'),
                      const SizedBox(height: 6),
                      _PillTextField(
                        controller: _passwordController,
                        hint: '',
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),

                      // Error
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Submit button — pill shape
                      SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.sageMid,
                            foregroundColor: AppTheme.white,
                            shape: const StadiumBorder(),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  _isLogin ? 'Sign in' : 'Sign up',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Toggle link
                      Center(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _isLogin = !_isLogin;
                            ref.read(authProvider.notifier).clearError();
                          }),
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                  fontSize: 13, color: AppTheme.textMid),
                              children: [
                                TextSpan(
                                  text: _isLogin
                                      ? 'No account? '
                                      : 'Already have an account? ',
                                ),
                                TextSpan(
                                  text: _isLogin ? 'Sign up' : 'Sign in',
                                  style: const TextStyle(
                                    color: AppTheme.sageDark,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppTheme.textMid,
        fontFamily: 'Manrope',
      ),
    );
  }
}

class _PillTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _PillTextField({
    required this.controller,
    required this.hint,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(
        color: AppTheme.textDark,
        fontSize: 15,
        fontFamily: 'Manrope',
      ),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppTheme.sageFaint,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: const BorderSide(color: AppTheme.sageMid, width: 1.5),
        ),
      ),
    );
  }
}
