import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

/// The full color vocabulary, one concrete instance per brightness. Kept
/// behind [AppColors]' static getters because the palette is referenced from
/// hundreds of call sites — painters, button styles, semantic chips — and an
/// ambient swap beats threading BuildContext through all of them.
class AppPalette {
  const AppPalette({
    required this.ink,
    required this.inkMuted,
    required this.paper,
    required this.sheet,
    required this.mist,
    required this.navy,
    required this.cream,
    required this.parchment,
    required this.liberal,
    required this.conservative,
    required this.center,
    required this.accent,
  });

  final Color ink;
  final Color inkMuted;
  final Color paper;
  final Color sheet;
  final Color mist;
  final Color navy;
  final Color cream;
  final Color parchment;
  final Color liberal;
  final Color conservative;
  final Color center;
  final Color accent;

  static const light = AppPalette(
    ink: Color(0xFF111318),
    inkMuted: Color(0xFF5C6575),
    paper: Color(0xFFF6F7F9),
    sheet: Color(0xFFFFFFFF),
    mist: Color(0xFFC8D2E0),
    navy: Color(0xFF111318),
    cream: Color(0xFFF6F7F9),
    parchment: Color(0xFFE8EEF6),
    liberal: Color(0xFF1D4ED8),
    conservative: Color(0xFFDC2626),
    center: Color(0xFF8B93A3),
    // Antique gold — deeper than a decorative gold because the accent also
    // sits behind text (filter badge) and renders as 12px labels.
    accent: Color(0xFF8A6D1F),
  );

  /// Roles invert: `ink`/`navy` go light and `sheet`/`cream` go dark, so
  /// "ink text on sheet card" and "cream label on navy button" both keep
  /// their contrast in either mode.
  static const dark = AppPalette(
    ink: Color(0xFFEDEFF4),
    inkMuted: Color(0xFF9AA5B5),
    paper: Color(0xFF0E1013),
    sheet: Color(0xFF161B22),
    mist: Color(0xFF39424F),
    navy: Color(0xFFE9ECF2),
    cream: Color(0xFF10141A),
    parchment: Color(0xFF232A36),
    liberal: Color(0xFF7FA3F5),
    conservative: Color(0xFFEF7A6C),
    center: Color(0xFF8B93A3),
    accent: Color(0xFFE3BC5B),
  );

  static AppPalette forBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }
}

class AppColors {
  AppColors._();

  /// The palette every `AppColors.x` read resolves against. The app shell
  /// calls [sync] from the MaterialApp builder — before any descendant
  /// builds — so static reads inside widgets and painters see the active
  /// brightness without a BuildContext. Outside the shell (tests, isolated
  /// widgets) it stays on light, which is what the values were before dark
  /// mode existed.
  static AppPalette _current = AppPalette.light;

  static Brightness _brightness = Brightness.light;

  static Brightness get brightness => _brightness;

  static void sync(Brightness brightness) {
    _brightness = brightness;
    _current = AppPalette.forBrightness(brightness);
  }

  static Color get ink => _current.ink;
  static Color get inkMuted => _current.inkMuted;
  static Color get paper => _current.paper;
  static Color get sheet => _current.sheet;
  static Color get mist => _current.mist;
  static Color get navy => _current.navy;
  static Color get cream => _current.cream;
  static Color get parchment => _current.parchment;
  static Color get liberal => _current.liberal;
  static Color get conservative => _current.conservative;
  static Color get center => _current.center;
  static Color get accent => _current.accent;
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(AppPalette.light, Brightness.light);

  static ThemeData dark() => _build(AppPalette.dark, Brightness.dark);

  static ThemeData _build(AppPalette colors, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    // google_fonts 9.x builds its TextTheme on package:material_ui, the
    // split-out Material fork — same field names, same dart:ui TextStyle
    // fields, but a different class than flutter/material's. Copy field by
    // field so the app's own ThemeData can consume it.
    final gf = GoogleFonts.manropeTextTheme();
    final textTheme = TextTheme(
      displayLarge: gf.displayLarge,
      displayMedium: gf.displayMedium,
      displaySmall: gf.displaySmall,
      headlineLarge: gf.headlineLarge,
      headlineMedium: gf.headlineMedium,
      headlineSmall: gf.headlineSmall,
      titleLarge: gf.titleLarge,
      titleMedium: gf.titleMedium,
      titleSmall: gf.titleSmall,
      bodyLarge: gf.bodyLarge,
      bodyMedium: gf.bodyMedium,
      bodySmall: gf.bodySmall,
      labelLarge: gf.labelLarge,
      labelMedium: gf.labelMedium,
      labelSmall: gf.labelSmall,
    ).apply(bodyColor: colors.ink, displayColor: colors.ink);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme:
          (isDark ? const ColorScheme.dark() : const ColorScheme.light())
              .copyWith(
                primary: colors.ink,
                secondary: colors.accent,
                surface: colors.paper,
                onPrimary: colors.sheet,
                onSecondary: colors.ink,
                onSurface: colors.ink,
                surfaceContainerHighest: colors.sheet,
              ),
      scaffoldBackgroundColor: colors.paper,
      cardColor: colors.sheet,
      dividerColor: colors.ink.withValues(alpha: 0.08),
      textTheme: textTheme,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: colors.ink,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: colors.ink,
          letterSpacing: -0.2,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.sheet,
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
          foregroundColor: colors.ink,
          side: BorderSide(
            color: colors.ink.withValues(alpha: 0.18),
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
            if (states.contains(WidgetState.selected)) return colors.ink;
            return colors.sheet;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return colors.sheet;
            return colors.ink;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: colors.ink.withValues(alpha: 0.12)),
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
          foregroundColor: colors.inkMuted,
          textStyle: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
