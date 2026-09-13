import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/theme/app_theme.dart';
import 'package:voteaxis/widgets/pillar_bars.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('pillar bars list each pillar on the public scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: PillarBars(
            pillarScores: {'economy': -50, 'society': 20},
            pillarLabels: {'economy': 'Economy', 'society': 'Society'},
          ),
        ),
      ),
    );
    expect(find.text('Your pillars'), findsOneWidget);
    expect(find.text('Economy'), findsOneWidget);
    expect(find.text('Society'), findsOneWidget);
    expect(find.text('Liberal 100 ← 0 → Conservative 100'), findsOneWidget);
  });

  testWidgets('hard lean flips a steel-man card', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: IssueScoreBreakdown(
            issueScores: const {'taxes': -40, 'abortion': -80},
            issueLabels: const {'taxes': 'Taxes', 'abortion': 'Abortion'},
            questions: testQuestions,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Your issue scores'));
    await tester.pumpAndSettle();
    expect(find.text('Steel-man the opposite'), findsOneWidget);
    expect(find.text('Taxes'), findsOneWidget);
    await tester.tap(find.text('Steel-man the opposite'));
    await tester.pumpAndSettle();
    expect(find.textContaining('equal protection'), findsOneWidget);
    expect(find.text('STEEL MAN'), findsOneWidget);
  });
}
