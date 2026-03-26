import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../main.dart';
import '../providers/server_url_provider.dart';

class ServerUrlScreen extends ConsumerStatefulWidget {
  const ServerUrlScreen({super.key});

  @override
  ConsumerState<ServerUrlScreen> createState() => _ServerUrlScreenState();
}

class _ServerUrlScreenState extends ConsumerState<ServerUrlScreen> {
  final _controller = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final lastUrl = ref.read(serverUrlProvider).url;
    if (lastUrl != null && lastUrl.isNotEmpty) {
      _controller.text = lastUrl;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValidUrl(String s) {
    final uri = Uri.tryParse(s);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (!_isValidUrl(url)) {
      ref.read(serverUrlProvider.notifier).clearError();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid URL (http:// or https://)')),
      );
      return;
    }

    setState(() => _loading = true);
    final ok = await ref.read(serverUrlProvider.notifier).save(url);
    if (mounted) {
      setState(() => _loading = false);
      if (ok) context.go('/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = ref.watch(serverUrlProvider).error;

    return Scaffold(
      backgroundColor: AppTheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 48),

                // Logo mark
                SvgPicture.asset(
                  'assets/logo.svg',
                  width: 72,
                  height: 72,
                ),

                const SizedBox(height: 16),

                // Logo text / wordmark
                SvgPicture.asset(
                  'assets/logo-text.svg',
                  width: 180,
                ),

                const SizedBox(height: 32),

                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxWidth: 360),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceCard,
                    borderRadius: BorderRadius.circular(24),
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
                      const SizedBox(height: 24),

                      // URL field
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SERVER ENDPOINT URL',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 11 * 0.08,
                              color: AppTheme.onSurfaceMuted,
                            ),
                          ),
                          const SizedBox(height: 5),
                          TextField(
                            controller: _controller,
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submit(),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              color: AppTheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: 'http://192.168.x.x:8080',
                              hintStyle: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                color: AppTheme.onSurfaceMuted,
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceNest,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
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
                            ),
                          ),
                        ],
                      ),

                      // Error message
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

                      // Next button — same gradient pill as auth screen
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
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2),
                                  )
                                : Text(
                                    'Next',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
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
