// Dev harness: boots straight into QuizScreen with the bundled question bank,
// so the wide-canvas Duo layout can be screenshotted without tapping through
// onboarding. Run: flutter run -t lib/main_quiz_preview.dart -d <device>.

import 'package:flutter/material.dart';

import 'data/app_data.dart';
import 'screens/quiz_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final data = await AppData.load();
  runApp(
    MaterialApp(
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      home: QuizScreen(
        questions: data.questions,
        issuesById: data.issuesById,
        onComplete: (_) async {},
        onExit: () async {},
      ),
    ),
  );
}
