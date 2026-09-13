import 'package:flutter/services.dart';

import '../models/app_settings.dart';

/// Global feel gates.
///
/// Haptics and motion are read from screens that get pushed outside the
/// shell's subtree (the quiz, the scanner, transfer), so they live here
/// instead of being threaded through every constructor. The shell calls
/// [apply] whenever settings change.
class AppFeel {
  AppFeel._();

  static bool haptics = true;
  static bool reduceMotion = false;

  static void apply(AppSettings settings) {
    haptics = settings.haptics;
    reduceMotion = settings.reduceMotion;
  }

  static void selection() {
    if (haptics) HapticFeedback.selectionClick();
  }

  static void light() {
    if (haptics) HapticFeedback.lightImpact();
  }

  static void medium() {
    if (haptics) HapticFeedback.mediumImpact();
  }

  /// Collapses an animation to nothing when the user asked for less motion.
  static Duration duration(Duration full) =>
      reduceMotion ? Duration.zero : full;
}
