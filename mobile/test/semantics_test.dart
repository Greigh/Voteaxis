import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/screens/quiz_screen.dart';
import 'package:voteaxis/screens/settings_screen.dart';
import 'package:voteaxis/widgets/pillar_bars.dart';
import 'package:voteaxis/widgets/spectrum_bar.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

/// Screen-reader coverage: charts announce a summary, controls announce role
/// and state, and progress speaks. Paired with tap_target_test.dart, which
/// owns the 48dp sweep.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Future<SemanticsHandle> pump(
    WidgetTester tester,
    Widget home, {
    double width = 800,
    double height = 1600,
  }) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.light(), home: home));
    await tester.pumpAndSettle();
    return handle;
  }

  testWidgets('SpectrumBar announces pins and plotted markers', (tester) async {
    final handle = await pump(
      tester,
      const Scaffold(
        body: SpectrumBar(
          userScore: -62,
          otherScore: 30,
          markers: [
            SpectrumMarker(id: 'a', score: -40),
            SpectrumMarker(id: 'b', score: 55),
          ],
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(SpectrumBar));
    expect(node.label, contains('Liberal 100'));
    expect(node.label, contains('Your position: Strongly liberal, -62'));
    expect(node.label, contains('Friend position: Moderately conservative'));
    expect(node.label, contains('2 politicians plotted'));
    handle.dispose();
  });

  testWidgets('SpectrumBar without a user pin does not invent one', (
    tester,
  ) async {
    final handle = await pump(
      tester,
      const Scaffold(
        body: SpectrumBar(markers: [SpectrumMarker(id: 'a', score: 10)]),
      ),
    );
    final node = tester.getSemantics(find.byType(SpectrumBar));
    expect(node.label, isNot(contains('Your position')));
    expect(node.label, contains('1 politicians plotted'));
    handle.dispose();
  });

  testWidgets('pillar rows merge into one spoken score', (tester) async {
    final handle = await pump(
      tester,
      const Scaffold(
        body: PillarBars(
          pillarScores: {'economy': -40},
          pillarLabels: {'economy': 'Economy'},
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Economy: Moderately liberal, Liberal 40'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('quiz progress announces question position', (tester) async {
    final handle = await pump(
      tester,
      QuizScreen(
        questions: testQuestions,
        issuesById: {for (final i in testIssues) i.id: i},
        showDealbreakers: false,
        onComplete: (_) async {},
        onExit: () async {},
      ),
      height: 900,
    );
    expect(
      find.bySemanticsLabel('Quiz progress, question 1 of 2'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('settings segmented options expose selected state', (
    tester,
  ) async {
    final handle = await pump(
      tester,
      SettingsScreen(
        settings: const AppSettings(theme: AppThemeMode.dark),
        onSettings: (_) async {},
        homeStateCode: 'MI',
        onHomeState: (_) async {},
        hasInProgress: false,
        hasSavedResult: false,
      ),
      height: 3200,
    );
    // TalkBack reads "Dark, selected, button" — tapping via the semantics
    // action must flip the setting, same as the visual control.
    final node = tester.getSemantics(find.bySemanticsLabel('Dark'));
    expect(node.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    handle.dispose();
  });

  testWidgets('home survives 1.3x text scaling without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Builder(
            builder: (context) => QuizScreen(
              questions: testQuestions,
              issuesById: {for (final i in testIssues) i.id: i},
              showDealbreakers: true,
              onComplete: (_) async {},
              onExit: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // An overflow throws FlutterError during layout — reaching here is the test.
    expect(find.byType(QuizScreen), findsOneWidget);
  });
}
