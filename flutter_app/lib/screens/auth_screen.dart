import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../providers/auth_provider.dart';
import '../providers/server_url_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController  = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;
    if (!_isLogin && password != _confirmController.text) {
      ref.read(authProvider.notifier).clearError();
      return;
    }

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

  void _toggle() {
    setState(() => _isLogin = !_isLogin);
    ref.read(authProvider.notifier).clearError();
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(authProvider).error;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 48),

                // "TAKECHARGE" — matches the web <h1> style
                Text(
                  'TAKECHARGE',
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 15 * 0.2, // 0.2em
                    color: AppTheme.primary,
                  ),
                ),

                const SizedBox(height: 32),

                // Auth card — matches .auth-card
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 360),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(24), // --radius-xl
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F55624D),
                        blurRadius: 40,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Title — matches .auth-title
                      Text(
                        _isLogin ? 'Sign in' : 'Create account',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.manrope(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Username
                      _AuthField(
                        label: 'Username',
                        controller: _usernameController,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),

                      // Password
                      _AuthField(
                        label: 'Password',
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: _isLogin ? TextInputAction.done : TextInputAction.next,
                        onSubmitted: _isLogin ? (_) => _submit() : null,
                      ),

                      // Confirm password (sign-up only)
                      if (!_isLogin) ...[
                        const SizedBox(height: 12),
                        _AuthField(
                          label: 'Confirm password',
                          controller: _confirmController,
                          obscureText: true,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                      ],

                      // Error — matches .auth-error
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppTheme.secondary,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Submit button — matches .auth-btn (gradient pill)
                      SizedBox(
                        height: 48,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppTheme.primary, AppTheme.primaryCont],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x4055624D),
                                blurRadius: 20,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: _loading ? null : _submit,
                            child: _loading
                                ? const SizedBox(
                                    height: 20, width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    _isLogin ? 'Sign in' : 'Create account',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Toggle link — matches .auth-switch
                      GestureDetector(
                        onTap: _toggle,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              color: AppTheme.onSurfaceMuted,
                            ),
                            children: [
                              TextSpan(
                                text: _isLogin ? 'No account? ' : 'Already have an account? ',
                              ),
                              TextSpan(
                                text: _isLogin ? 'Sign up' : 'Sign in',
                                style: const TextStyle(
                                  color: AppTheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Back to server URL
                      GestureDetector(
                        onTap: () {
                          ref.read(serverUrlProvider.notifier).clearError();
                          ref.read(serverUrlProvider.notifier).clear();
                        },
                        child: Text(
                          '← Wrong server? Change URL',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppTheme.onSurfaceMuted,
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

class _AuthField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _AuthField({
    required this.label,
    required this.controller,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label — matches .auth-field label (uppercase, muted, small)
        Text(
          label.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 11 * 0.08, // 0.08em
            color: AppTheme.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            color: AppTheme.onSurface,
          ),
          decoration: InputDecoration(
            // Overrides to match auth-field input exactly
            filled: true,
            fillColor: AppTheme.surfaceNest,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusColor: AppTheme.primaryFixed,
          ),
        ),
      ],
    );
  }
}
