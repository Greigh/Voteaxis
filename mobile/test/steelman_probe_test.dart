import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/theme/app_theme.dart';
import 'package:voteaxis/widgets/pillar_bars.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('steel man card geometry', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: IssueScoreBreakdown(
              issueScores: const {'abortion': -80},
              issueLabels: const {'abortion': 'Abortion'},
              questions: testQuestions,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Your issue scores'));
    await tester.pumpAndSettle();
    final front = find
        .ancestor(of: find.text('Steel-man the opposite'), matching: find.byType(InkWell))
        .first;
    // ignore: avoid_print
    print('### front toggle rect ${tester.getRect(front)}');
    // ignore: avoid_print
    print('### card rect ${tester.getRect(find.byType(IssueScoreBreakdown))}');
    await tester.tap(find.text('Steel-man the opposite'));
    await tester.pumpAndSettle();
    final back = find
        .ancestor(of: find.text('Back to your score'), matching: find.byType(InkWell))
        .first;
    // ignore: avoid_print
    print('### back toggle rect ${tester.getRect(back)}');
    // ignore: avoid_print
    print('### back label rect ${tester.getRect(find.text('Back to your score'))}');
    // gap between the toggle and the row underneath
    // ignore: avoid_print
    print('### argument text rect ${tester.getRect(find.textContaining('equal protection'))}');
  });
}
