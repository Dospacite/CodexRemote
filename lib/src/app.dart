import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_controller.dart';
import 'home_page.dart';

class CodexRemoteApp extends StatelessWidget {
  const CodexRemoteApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Codex Remote',
          debugShowCheckedModeBanner: false,
          themeMode: controller.settings.materialThemeMode,
          theme: _buildLightTheme(),
          darkTheme: _buildDarkTheme(),
          home: HomePage(controller: controller),
        );
      },
    );
  }
}

ThemeData _buildLightTheme() {
  const background = Color(0xFFFAF8F5);
  const surface = Color(0xFFFFFFFF);
  const primary = Color(0xFFB45309);
  const secondary = Color(0xFFD97706);
  const accent = Color(0xFF059669);
  const text = Color(0xFF451A03);
  const muted = Color(0xFF9A7B63);
  const border = Color(0xFFE7DED5);

  final scheme = const ColorScheme(
    brightness: Brightness.light,
    primary: primary,
    onPrimary: Colors.white,
    secondary: secondary,
    onSecondary: Colors.white,
    error: Color(0xFFB42318),
    onError: Colors.white,
    surface: surface,
    onSurface: text,
  );

  return _buildTheme(
    scheme: scheme,
    background: background,
    muted: muted,
    border: border,
    accent: accent,
  );
}

ThemeData _buildDarkTheme() {
  const background = Color(0xFF0F0F0F);
  const surface = Color(0xFF1A1A1A);
  const primary = Color(0xFF00D4AA);
  const secondary = Color(0xFF00A3CC);
  const accent = Color(0xFFFF6B9D);
  const text = Color(0xFFF5F5F5);
  const muted = Color(0xFF9D9D9D);
  const border = Color(0xFF2A2A2A);

  final scheme = const ColorScheme(
    brightness: Brightness.dark,
    primary: primary,
    onPrimary: Color(0xFF07110F),
    secondary: secondary,
    onSecondary: Color(0xFF071217),
    error: Color(0xFFFF8A8A),
    onError: Color(0xFF2A0608),
    surface: surface,
    onSurface: text,
  );

  return _buildTheme(
    scheme: scheme,
    background: background,
    muted: muted,
    border: border,
    accent: accent,
  );
}

ThemeData _buildTheme({
  required ColorScheme scheme,
  required Color background,
  required Color muted,
  required Color border,
  required Color accent,
}) {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
  );
  final textTheme = GoogleFonts.ibmPlexSansTextTheme(base.textTheme).copyWith(
    titleLarge: GoogleFonts.ibmPlexSans(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    titleMedium: GoogleFonts.ibmPlexSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    bodyLarge: GoogleFonts.ibmPlexSans(
      fontSize: 15,
      height: 1.45,
      color: scheme.onSurface,
    ),
    bodyMedium: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      height: 1.45,
      color: scheme.onSurface,
    ),
    bodySmall: GoogleFonts.ibmPlexSans(
      fontSize: 13,
      height: 1.35,
      color: muted,
    ),
    labelLarge: GoogleFonts.ibmPlexSans(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: textTheme.titleLarge,
    ),
    dividerColor: border,
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        foregroundColor: scheme.onSurface,
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide(color: border),
      backgroundColor: scheme.surface,
      selectedColor: accent.withValues(alpha: 0.16),
      labelStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurface),
    ),
  );
}
