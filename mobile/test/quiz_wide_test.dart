import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/screens/quiz_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';
import 'support/fixtures.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('wide Duo canvas shows the companion rail', (tester) async {
    tester.view.physicalSize = const Size(951, 669);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: QuizScreen(
          questions: testQuestions,
          issuesById: {for (final i in testIssues) i.id: i},
          onComplete: (_) async {},
          onExit: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NOW ANSWERING'), findsOneWidget);
    expect(find.text('Private by design'), findsOneWidget);
    expect(find.text('Taxes on high earners should go up.'), findsOneWidget);
  });

  testWidgets('phone width keeps the single column', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: QuizScreen(
          questions: testQuestions,
          issuesById: {for (final i in testIssues) i.id: i},
          onComplete: (_) async {},
          onExit: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NOW ANSWERING'), findsNothing);
    expect(find.text('Taxes on high earners should go up.'), findsOneWidget);
  });
}
