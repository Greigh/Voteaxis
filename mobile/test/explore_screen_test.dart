import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/screens/explore_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpExplore(
    WidgetTester tester, {
    dynamic data,
    dynamic profile,
    double height = 2400,
  }) async {
    tester.view.physicalSize = Size(800, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ExploreScreen(data: data ?? testAppData(), userProfile: profile),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Browse mode', () {
    testWidgets('lists the roster with no profile and no match scores', (
      tester,
    ) async {
      await pumpExplore(tester);
      // testAppData: a former president plus a sitting senator.
      expect(find.text('Barack Obama'), findsOneWidget);
      expect(find.text('Bernie Sanders'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(
        find.textContaining('no match scores until you take the quiz'),
        findsOneWidget,
      );
    });

    testWidgets('search narrows by name', (tester) async {
      await pumpExplore(tester);
      await tester.enterText(find.byType(TextField), 'obama');
      await tester.pumpAndSettle();

      expect(find.text('Barack Obama'), findsOneWidget);
      expect(find.text('Bernie Sanders'), findsNothing);
    });

    testWidgets('office filter narrows the list', (tester) async {
      await pumpExplore(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('U.S. Senate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Filters').last); // scrim-safe close
      await tester.pumpAndSettle();

      expect(find.text('Bernie Sanders'), findsOneWidget);
      expect(find.text('Barack Obama'), findsNothing);
    });

    testWidgets('a profile turns on match percentages', (tester) async {
      await pumpExplore(tester, profile: testProfile());
      expect(find.textContaining('%'), findsWidgets);
    });
  });

  group('Detail without a profile', () {
    testWidgets('opens the record with an axis card instead of a match', (
      tester,
    ) async {
      await pumpExplore(tester);
      await tester.tap(find.text('Bernie Sanders'));
      await tester.pumpAndSettle();

      // Browse mode: their axis, no "NN% match" claim.
      expect(find.text('ISSUE POSITIONS'), findsOneWidget);
      expect(find.text('SIDE BY SIDE'), findsNothing);
      expect(find.textContaining('% match'), findsNothing);
      expect(
        find.textContaining('Take the quiz and this card shows your match'),
        findsOneWidget,
      );
    });

    testWidgets('with a profile the same screen shows the match', (
      tester,
    ) async {
      await pumpExplore(tester, profile: testProfile());
      await tester.tap(find.text('Bernie Sanders'));
      await tester.pumpAndSettle();

      expect(find.text('SIDE BY SIDE'), findsOneWidget);
      expect(find.textContaining('% match'), findsOneWidget);
    });
  });
}
