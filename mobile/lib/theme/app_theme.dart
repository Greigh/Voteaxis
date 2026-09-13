import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const ink = Color(0xFF111318);
  static const inkMuted = Color(0xFF5C6575);
  static const paper = Color(0xFFF6F7F9);
  static const sheet = Color(0xFFFFFFFF);
  static const mist = Color(0xFFC8D2E0);
  static const navy = Color(0xFF111318);
  static const cream = Color(0xFFF6F7F9);
  static const parchment = Color(0xFFE8EEF6);
  static const liberal = Color(0xFF1D4ED8);
  static const conservative = Color(0xFFDC2626);
  static const center = Color(0xFF8B93A3);
  static const accent = Color(0xFFC4A035);
}

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final textTheme = GoogleFonts.manropeTextTheme().apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: AppColors.ink,
        secondary: AppColors.accent,
        surface: AppColors.paper,
        onPrimary: AppColors.sheet,
        onSecondary: AppColors.ink,
        onSurface: AppColors.ink,
      ),
      scaffoldBackgroundColor: AppColors.paper,
      textTheme: textTheme,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
        centerTitle: false,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.ink,
          letterSpacing: -0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.sheet,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          textStyle: GoogleFonts.manrope(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink,
          side: BorderSide(
            color: AppColors.ink.withValues(alpha: 0.18),
            width: 1.4,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          textStyle: GoogleFonts.manrope(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      // Material fills a selected segment with colorScheme.secondary, which
      // here is the gold accent — so the scope toggle rendered gold directly
      // under the ink tab switcher and beside the ink sort control. The accent
      // is for small marks (the filter badge, a diagram node), not for a
      // control surface. Ink, like every other selected control.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.ink;
            return AppColors.sheet;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return AppColors.sheet;
            return AppColors.ink;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: AppColors.ink.withValues(alpha: 0.12)),
          ),
          textStyle: WidgetStateProperty.all(
            GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.inkMuted,
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
