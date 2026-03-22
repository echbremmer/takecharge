import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/client.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiClient.instance.init();
  runApp(const ProviderScope(child: TakeChargeApp()));
}

class TakeChargeApp extends ConsumerWidget {
  const TakeChargeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'TakeCharge',
      theme: AppTheme.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

class AppTheme {
  // Sage palette — mirrors CSS custom properties in the web frontend
  static const sageDark = Color(0xFF3D5A4C);
  static const sageMid = Color(0xFF5C7A6A);
  static const sageLight = Color(0xFF8FAF9F);
  static const sagePale = Color(0xFFD4E6DC);
  static const sageFaint = Color(0xFFF0F7F3);
  static const white = Color(0xFFFFFFFF);
  static const textDark = Color(0xFF1A2E25);
  static const textMid = Color(0xFF4A6358);
  static const textLight = Color(0xFF8FAF9F);
  static const accent = Color(0xFFE8A87C);
  static const accentLight = Color(0xFFF5D4B8);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: sageMid,
          primary: sageDark,
          secondary: sageMid,
          surface: sageFaint,
          onPrimary: white,
          onSecondary: white,
          onSurface: textDark,
        ),
        fontFamily: 'Manrope',
        scaffoldBackgroundColor: sageFaint,
        appBarTheme: const AppBarTheme(
          backgroundColor: sageDark,
          foregroundColor: white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: sageDark,
            foregroundColor: white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: sagePale),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: sagePale),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: sageMid, width: 2),
          ),
        ),
      );
}
