import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/screens/home_screen.dart';
import 'package:voteaxis/services/voteaxis_api.dart';
import 'package:voteaxis/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('home shows quiz, settings, and issue of the week', (
    tester,
  ) async {
    var started = false;
    var openedSettings = false;
    var openedLevel = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(
          hasSavedResult: false,
          hasInProgress: false,
          homeStateCode: 'MI',
          onHomeStateChanged: (_) async {},
          onStartQuiz: () => started = true,
          onResumeQuiz: () {},
          onViewResults: () {},
          onMethodology: () {},
          onSettings: () => openedSettings = true,
          onSetLevel: () => openedLevel = true,
          week: const IssueOfTheWeek(
            weekOf: '2026-08-10',
            issueId: 'immigration',
            headline: 'Who belongs, and on what terms?',
            question: 'Expand legal paths or tighten enforcement?',
            context: 'Editorial prompt.',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Start the quiz'), findsOneWidget);
    expect(find.text('ISSUE OF THE WEEK'), findsOneWidget);
    expect(find.text('Who belongs, and on what terms?'), findsOneWidget);
    expect(find.text('MI'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    expect(openedSettings, isTrue);
    await tester.tap(find.text('Start the quiz'));
    expect(started, isTrue);
    await tester.scrollUntilVisible(
      find.text('Skip the quiz — set your level'),
      400,
    );
    await tester.tap(find.text('Skip the quiz — set your level'));
    expect(openedLevel, isTrue);
    await tester.scrollUntilVisible(find.text('Stays yours'), 400);
    expect(find.text('Five pillars'), findsOneWidget);
    expect(find.text('Receipts'), findsOneWidget);
    expect(find.text('Steel man'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Contribute to Voteaxis'), 400);
    expect(find.text('Contribute to Voteaxis'), findsOneWidget);
  });

  testWidgets('saved result unlocks last results and a new-quiz CTA', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(
          hasSavedResult: true,
          hasInProgress: true,
          homeStateCode: 'MI',
          onHomeStateChanged: (_) async {},
          onStartQuiz: () {},
          onResumeQuiz: () {},
          onViewResults: () {},
          onMethodology: () {},
          onSetLevel: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Start a new quiz'), findsOneWidget);
    expect(find.text('Set your level by hand'), findsOneWidget);
    expect(find.text('Resume quiz'), findsOneWidget);
    expect(find.text('Last results'), findsOneWidget);
    expect(find.textContaining('Issue of the Day widget'), findsOneWidget);
    // The what-you-get pitch is first-run only; a returning user is past it.
    expect(find.text('WHAT YOU GET'), findsNothing);
    expect(find.text('Stays yours'), findsNothing);
  });

  testWidgets('skip the quiz leads with hand-set placement', (tester) async {
    var started = false;
    var level = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(
          hasSavedResult: false,
          hasInProgress: false,
          homeStateCode: 'MI',
          onHomeStateChanged: (_) async {},
          onStartQuiz: () => started = true,
          onResumeQuiz: () {},
          onViewResults: () {},
          onMethodology: () {},
          onSetLevel: () => level = true,
          skipQuiz: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));

    // The hand-set path is now the dark primary button.
    expect(find.text('Set your level'), findsOneWidget);
    expect(find.text('Skip the quiz — set your level'), findsNothing);
    expect(find.textContaining('thirty seconds'), findsOneWidget);

    await tester.tap(find.text('Set your level'));
    expect(level, isTrue);

    // The quiz is still reachable, just demoted.
    await tester.tap(find.text('Start the quiz'));
    expect(started, isTrue);
  });

  testWidgets('a saved result relabels both paths', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(
          hasSavedResult: true,
          hasInProgress: false,
          homeStateCode: 'MI',
          onHomeStateChanged: (_) async {},
          onStartQuiz: () {},
          onResumeQuiz: () {},
          onViewResults: () {},
          onMethodology: () {},
          onSetLevel: () {},
          skipQuiz: true,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Adjust your level'), findsOneWidget);
    expect(find.text('Start a new quiz'), findsOneWidget);
    expect(find.textContaining('adjust your level'), findsOneWidget);
  });

  testWidgets('reduce motion skips the entrance fade', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: HomeScreen(
          hasSavedResult: false,
          hasInProgress: false,
          homeStateCode: 'MI',
          onHomeStateChanged: (_) async {},
          onStartQuiz: () {},
          onResumeQuiz: () {},
          onViewResults: () {},
          onMethodology: () {},
          reduceMotion: true,
        ),
      ),
    );
    // One frame, no settling: the content is already fully opaque.
    await tester.pump();
    // The outermost FadeTransition is the screen's entrance animation.
    final fade = tester.widget<FadeTransition>(
      find.byType(FadeTransition).first,
    );
    expect(fade.opacity.value, 1.0);
  });
}
