import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'api/client.dart';
import 'providers/auth_provider.dart';
import 'providers/server_url_provider.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Light status bar to match the app's light surface
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  await ApiClient.instance.init();
  runApp(const ProviderScope(child: AppStartup()));
}

/// Triggers checkAuth() once on startup before rendering anything.
class AppStartup extends ConsumerStatefulWidget {
  const AppStartup({super.key});

  @override
  ConsumerState<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends ConsumerState<AppStartup> {
  @override
  void initState() {
    super.initState();
    ref.read(serverUrlProvider.notifier).load().then((_) {
      ref.read(authProvider.notifier).checkAuth();
    });
  }

  @override
  Widget build(BuildContext context) => const VandagApp();
}

class VandagApp extends ConsumerWidget {
  const VandagApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Vandag',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Design tokens mirrored exactly from the web frontend CSS variables.
class AppTheme {
  // ── Colours ──────────────────────────────────────────────────────────────
  static const surface      = Color(0xFFF8FAF3); // --surface
  static const surfaceNest  = Color(0xFFECEFE8); // --surface-nest
  static const surfaceCard  = Color(0xFFFFFFFF); // --surface-card
  static const primary      = Color(0xFF55624D); // --primary
  static const primaryCont  = Color(0xFF98A68E); // --primary-container
  static const primaryFixed = Color(0xFFD9E7CD); // --primary-fixed
  static const secondary    = Color(0xFF755754); // --secondary
  static const secondaryCont= Color(0xFFFED7D2); // --secondary-container
  static const onSurface    = Color(0xFF191C18); // --on-surface
  static const onSurfaceVar = Color(0xFF444841); // --on-surface-var
  static const onSurfaceMuted=Color(0xFF888C84); // --on-surface-muted

  // Kept for backwards compat in existing widgets
  static const sageDark   = primary;
  static const sageMid    = primaryCont;
  static const sageLight  = onSurfaceMuted;
  static const sagePale   = primaryFixed;
  static const sageFaint  = surface;
  static const white      = surfaceCard;
  static const textDark   = onSurface;
  static const textMid    = onSurfaceVar;
  static const textLight  = onSurfaceMuted;
  static const accent     = secondary;
  static const accentLight= secondaryCont;

  static ThemeData get light {
    // Base text theme using Plus Jakarta Sans (body) + Manrope overrides (headings)
    final base = GoogleFonts.plusJakartaSansTextTheme().apply(
      bodyColor: onSurfaceVar,
      displayColor: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        primary: primary,
        secondary: secondary,
        surface: surface,
        onPrimary: surfaceCard,
        onSecondary: surfaceCard,
        onSurface: onSurface,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: base.copyWith(
        // Manrope for display / title styles (numbers, large headings)
        displayLarge:  GoogleFonts.manrope(textStyle: base.displayLarge,  color: onSurface,    fontWeight: FontWeight.w700),
        displayMedium: GoogleFonts.manrope(textStyle: base.displayMedium, color: onSurface,    fontWeight: FontWeight.w700),
        headlineLarge: GoogleFonts.manrope(textStyle: base.headlineLarge, color: onSurface,    fontWeight: FontWeight.w700),
        headlineMedium:GoogleFonts.manrope(textStyle: base.headlineMedium,color: onSurface,    fontWeight: FontWeight.w700),
        titleLarge:    GoogleFonts.manrope(textStyle: base.titleLarge,    color: onSurface,    fontWeight: FontWeight.w700),
        titleMedium:   GoogleFonts.manrope(textStyle: base.titleMedium,   color: onSurfaceVar, fontWeight: FontWeight.w600),
      ),

      // ── App bar: light frosted surface (matches web top-bar) ──────────────
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xCCF8FAF3), // rgba(248,250,243,.80)
        foregroundColor: onSurfaceVar,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle: GoogleFonts.manrope(
          color: primary,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 3.0,
        ),
        iconTheme: const IconThemeData(color: onSurface),
      ),

      // ── Bottom nav: white card surface (matches web bottom-nav) ──────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceCard,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x10558899),
        indicatorColor: primaryFixed,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: primary, size: 24);
          }
          return const IconThemeData(color: onSurfaceMuted, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return GoogleFonts.plusJakartaSans(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: selected ? primary : onSurfaceMuted,
          );
        }),
      ),

      // ── Cards ─────────────────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surfaceCard,
        elevation: 0,
        shadowColor: const Color(0x12557455),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // ── Buttons ───────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: surfaceCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          elevation: 0,
        ),
      ),

      // ── Inputs ────────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceNest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          borderSide: const BorderSide(color: primaryFixed, width: 2),
        ),
      ),
    );
  }
}
