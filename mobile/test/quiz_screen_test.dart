import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/screens/quiz_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('selecting an answer enables Next', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    QuizResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: QuizScreen(
          questions: testQuestions,
          issuesById: {for (final i in testIssues) i.id: i},
          onComplete: (value) async => result = value,
          onExit: () async {},
        ),
      ),
    );
    expect(find.text('Taxes on high earners should go up.'), findsOneWidget);
    expect(find.text('Strongly agree'), findsOneWidget);
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Abortion should remain legal.'), findsOneWidget);
    await tester.tap(find.text('Disagree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See my results'));
    await tester.pumpAndSettle();
    expect(result?.likertIndexes, [3, 1]);
  });

  Future<void> pumpQuiz(
    WidgetTester tester, {
    required bool showDealbreakers,
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: QuizScreen(
          questions: testQuestions,
          issuesById: {for (final i in testIssues) i.id: i},
          showDealbreakers: showDealbreakers,
          onComplete: (_) async {},
          onExit: () async {},
        ),
      ),
    );
  }

  testWidgets('the dealbreaker flag is shown by default', (tester) async {
    await pumpQuiz(tester, showDealbreakers: true);
    expect(find.textContaining('Mark as a dealbreaker'), findsOneWidget);
  });

  testWidgets('settings can hide the dealbreaker flag', (tester) async {
    await pumpQuiz(tester, showDealbreakers: false);
    expect(find.textContaining('dealbreaker'), findsNothing);
    // The rest of the question is untouched.
    expect(find.text('Taxes on high earners should go up.'), findsOneWidget);
    expect(find.text('How much does this matter to you?'), findsOneWidget);
  });

  testWidgets('hiding the flag still scores a completed run', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    QuizResult? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: QuizScreen(
          questions: testQuestions,
          issuesById: {for (final i in testIssues) i.id: i},
          showDealbreakers: false,
          onComplete: (value) async => result = value,
          onExit: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Agree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disagree'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('See my results'));
    await tester.pumpAndSettle();
    expect(result?.likertIndexes, [3, 1]);
    expect(result?.dealbreakerIssueIds, isEmpty);
  });
}
