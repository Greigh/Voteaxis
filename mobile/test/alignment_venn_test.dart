import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/theme/app_theme.dart';
import 'package:voteaxis/widgets/alignment_venn.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('Venn lists aligned and diverged issues', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AlignmentVenn(
            venn: CivicVenn(
              aligned: const [
                IssueOverlap(
                  issueId: 'taxes',
                  diff: 10,
                  userScore: -40,
                  politicianScore: -30,
                ),
              ],
              youMoreLiberal: const [
                IssueOverlap(
                  issueId: 'abortion',
                  diff: 100,
                  userScore: -80,
                  politicianScore: 20,
                ),
              ],
              theyMoreLiberal: const [],
            ),
            issueLabels: const {'taxes': 'Taxes', 'abortion': 'Abortion'},
            friendLabel: 'Sam',
          ),
        ),
      ),
    );
    expect(find.text('WHERE YOU OVERLAP'), findsOneWidget);
    expect(find.textContaining('Taxes'), findsOneWidget);
    expect(find.textContaining('Abortion'), findsOneWidget);
    expect(find.text('Sam more liberal'), findsWidgets);
  });
}
