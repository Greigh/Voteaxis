import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('AppColors ambient palette', () {
    tearDown(() => AppColors.sync(Brightness.light));

    test('defaults to the light palette before any sync', () {
      AppColors.sync(Brightness.light);
      expect(AppColors.ink, AppPalette.light.ink);
      expect(AppColors.sheet, AppPalette.light.sheet);
      expect(AppColors.brightness, Brightness.light);
    });

    test('sync(dark) swaps every role to the dark palette', () {
      AppColors.sync(Brightness.dark);
      expect(AppColors.ink, AppPalette.dark.ink);
      expect(AppColors.paper, AppPalette.dark.paper);
      expect(AppColors.sheet, AppPalette.dark.sheet);
      expect(AppColors.liberal, AppPalette.dark.liberal);
      expect(AppColors.conservative, AppPalette.dark.conservative);
      expect(AppColors.brightness, Brightness.dark);
    });

    test('role inversion keeps ink-on-sheet contrast in both modes', () {
      double contrast(Color a, Color b) {
        double lum(Color c) => c.computeLuminance();
        final (hi, lo) = lum(a) > lum(b) ? (lum(a), lum(b)) : (lum(b), lum(a));
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final palette in [AppPalette.light, AppPalette.dark]) {
        // Body text on a card surface — WCAG AA for normal text is 4.5.
        expect(
          contrast(palette.ink, palette.sheet),
          greaterThanOrEqualTo(4.5),
          reason:
              'ink on sheet in ${palette == AppPalette.light ? 'light' : 'dark'}',
        );
        // Muted text on the page surface — same threshold.
        expect(
          contrast(palette.inkMuted, palette.paper),
          greaterThanOrEqualTo(4.5),
          reason: 'muted on paper',
        );
        // Accent renders as 12px labels and behind badge text — AA text level.
        expect(
          contrast(palette.accent, palette.paper),
          greaterThanOrEqualTo(4.5),
          reason: 'accent on paper',
        );
        // Badge text uses sheet-on-accent.
        expect(
          contrast(palette.sheet, palette.accent),
          greaterThanOrEqualTo(4.5),
          reason: 'sheet on accent badge',
        );
      }
    });
  });

  group('AppTheme', () {
    test('light and dark themes report their brightness', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(AppTheme.light().scaffoldBackgroundColor, AppPalette.light.paper);
      expect(AppTheme.dark().scaffoldBackgroundColor, AppPalette.dark.paper);
    });
  });
}
