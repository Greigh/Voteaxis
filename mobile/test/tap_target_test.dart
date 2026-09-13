import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/models/rollcall_history.dart';
import 'package:voteaxis/screens/compare_screen.dart';
import 'package:voteaxis/screens/contribute_screen.dart';
import 'package:voteaxis/screens/friend_compare_screen.dart';
import 'package:voteaxis/screens/home_screen.dart';
import 'package:voteaxis/screens/manual_profile_screen.dart';
import 'package:voteaxis/screens/methodology_screen.dart';
import 'package:voteaxis/screens/onboarding_screen.dart';
import 'package:voteaxis/screens/politician_detail_screen.dart';
import 'package:voteaxis/screens/quiz_screen.dart';
import 'package:voteaxis/screens/results_screen.dart';
import 'package:voteaxis/screens/settings_screen.dart';
import 'package:voteaxis/screens/transfer_screen.dart';
import 'package:voteaxis/services/voteaxis_api.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

/// Every tappable thing has to clear 48dp — Material's minimum, and the one
/// that also satisfies the 44pt iOS floor.
///
/// Caveat worth knowing when this fails: the widget-test font draws every
/// glyph as a square of the font size, so text runs wider here than on a real
/// device. Heights are representative; a *width* that only just passes in this
/// test may still be tight in the app.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Pumps at a 390pt-wide phone — the narrow end of the devices we target.
  /// A few screens need a wider view here only because the square-glyph test
  /// font overflows rows that fit fine in the app; see [width].
  Future<SemanticsHandle> pumpPhone(
    WidgetTester tester,
    Widget home, {
    double height = 2400,
    double width = 390,
  }) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
    return handle;
  }

  testWidgets('home', (tester) async {
    final handle = await pumpPhone(
      tester,
      HomeScreen(
        hasSavedResult: true,
        hasInProgress: true,
        homeStateCode: 'MI',
        onHomeStateChanged: (_) async {},
        onStartQuiz: () {},
        onResumeQuiz: () {},
        onViewResults: () {},
        onMethodology: () {},
        onSettings: () {},
        onSetLevel: () {},
        onFriendCompare: () {},
        week: const IssueOfTheWeek(
          weekOf: '2026-08-10',
          issueId: 'immigration',
          headline: 'Who belongs, and on what terms?',
          question: 'Expand legal paths or tighten enforcement?',
          context: 'Editorial prompt.',
        ),
      ),
      width: 800,
    );
    await tester.pump(const Duration(milliseconds: 900));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('quiz', (tester) async {
    final handle = await pumpPhone(
      tester,
      QuizScreen(
        questions: testQuestions,
        issuesById: {for (final i in testIssues) i.id: i},
        showDealbreakers: true,
        onComplete: (_) async {},
        onExit: () async {},
      ),
      height: 900,
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('results, including a flipped steel-man card', (tester) async {
    final handle = await pumpPhone(
      tester,
      ResultsScreen(
        userProfile: testProfile(),
        data: testAppData(),
        homeStateCode: 'MI',
        figureFloor: 1980,
        onRetake: () {},
        onHome: () {},
      ),
      width: 800,
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.tap(find.text('Your issue scores'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.tap(find.text('Steel-man the opposite').first);
    await tester.pumpAndSettle();
    expect(find.text('STEEL MAN'), findsOneWidget);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    // The second tab and the filter sheet it opens.
    await tester.tap(find.textContaining('Matches ·'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('settings', (tester) async {
    final handle = await pumpPhone(
      tester,
      SettingsScreen(
        settings: const AppSettings(),
        onSettings: (_) async {},
        homeStateCode: 'MI',
        onHomeState: (_) async {},
        onTransfer: () {},
        onClearProgress: () async {},
        onDeleteEverything: () async {},
        hasInProgress: true,
        hasSavedResult: true,
      ),
      height: 3000,
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('politician detail with a vote record', (tester) async {
    final senator = testSenator().copyWith(
      rollcallSessions: const [
        RollcallSession(
          congress: 117,
          year: 2021,
          label: '117th Congress',
          axisScore: 40,
          moves: [
            RollcallMove(
              issueId: 'taxes',
              cast: 'Yea',
              contribution: 100,
              bill: 'S123',
              desc: 'Corporate tax cut',
            ),
          ],
        ),
        RollcallSession(
          congress: 118,
          year: 2023,
          label: '118th Congress',
          axisScore: -80,
        ),
      ],
    );
    final handle = await pumpPhone(
      tester,
      PoliticianDetailScreen(
        politician: senator,
        userProfile: testProfile(),
        data: testAppData(politicians: [senator]),
        figureFloor: 1980,
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('manual profile', (tester) async {
    final handle = await pumpPhone(
      tester,
      ManualProfileScreen(data: testAppData()),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('transfer', (tester) async {
    final handle = await pumpPhone(
      tester,
      TransferScreen(profile: testProfile(), homeStateCode: 'MI'),
      height: 3000,
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('friend compare, compare, methodology, contribute', (
    tester,
  ) async {
    final handle = await pumpPhone(
      tester,
      FriendCompareScreen(data: testAppData(), profile: testProfile()),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CompareScreen(baseProfile: testProfile(), data: testAppData()),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const MethodologyScreen()),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const ContributeScreen()),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('onboarding', (tester) async {
    final handle = await pumpPhone(
      tester,
      OnboardingScreen(onContinue: (_) async {}),
      height: 1400,
    );
    // The mist backdrop animates forever, so settle is not an option here.
    await tester.pump(const Duration(milliseconds: 1200));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
