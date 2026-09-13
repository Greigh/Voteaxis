import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/screens/results_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpResults(
    WidgetTester tester, {
    String? homeState = 'MI',
    int figureFloor = 2000,
    bool handSet = false,
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
        home: ResultsScreen(
          userProfile: profile ?? testProfile(),
          data: data ?? testAppData(),
          homeStateCode: homeState,
          figureFloor: figureFloor,
          handSet: handSet,
          onRetake: () {},
          onHome: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The list, its filters and its sort all live behind the second tab.
  Future<void> openMatches(WidgetTester tester) async {
    await tester.tap(find.textContaining('Matches ·'));
    await tester.pumpAndSettle();
  }

  group('The two tabs', () {
    testWidgets('open on You, with the score and closest above both', (
      tester,
    ) async {
      await pumpResults(tester);
      expect(find.text('Your spectrum'), findsOneWidget);
      expect(find.text('Overall place'), findsOneWidget);
      expect(find.textContaining('Closest:'), findsOneWidget);

      // You tab: the breakdown, not the roster.
      expect(find.text('On the axis'), findsOneWidget);
      expect(find.text('Your pillars'), findsOneWidget);
      expect(find.text('Filters'), findsNothing);
    });

    testWidgets('the compact strip drops the label, not the match', (
      tester,
    ) async {
      // On the Matches tab the strip has to share one row with the sort and
      // scope controls. "Conservative 19" already carries the side, so the
      // long label goes and the lead match keeps the room.
      await pumpResults(tester);
      final label = Scoring.labelForScore(testProfile().axisScore);
      expect(label, contains('liberal'));
      expect(find.text(label), findsOneWidget);

      await openMatches(tester);
      expect(find.text(label), findsNothing);
      expect(find.textContaining('Closest:'), findsOneWidget);
    });

    testWidgets('Matches carries the count and the controls', (tester) async {
      await pumpResults(tester);
      // Obama is national; the VT senator is off a Michigan ballot.
      expect(find.text('Matches · 1'), findsOneWidget);

      await openMatches(tester);
      expect(find.text('Filters'), findsOneWidget);
      expect(find.text('Closest first'), findsOneWidget);
      expect(find.text('On the axis'), findsNothing);
      // The strip shrinks here but still names who leads.
      expect(find.textContaining('Closest:'), findsOneWidget);
    });

    testWidgets('2000s plus keeps the Historical tab hidden', (tester) async {
      await pumpResults(tester);
      await openMatches(tester);
      expect(find.text('Historical'), findsNothing);
      expect(find.text('Active ballot'), findsNothing);
    });

    testWidgets('1980s plus unlocks the Historical tab', (tester) async {
      await pumpResults(tester, figureFloor: 1980);
      await openMatches(tester);
      expect(find.text('Historical'), findsOneWidget);
      expect(find.text('Active ballot'), findsOneWidget);
    });
  });

  group('Hand-set placements', () {
    testWidgets('say so above the score, on either tab', (tester) async {
      await pumpResults(tester, handSet: true);
      expect(find.text('Set by hand'), findsOneWidget);
      expect(
        find.textContaining('placed yourself on the axis'),
        findsOneWidget,
      );
      // It leads the page: above the score strip, so it is not lost in a tab.
      expect(
        tester.getTopLeft(find.text('Set by hand')).dy,
        lessThan(tester.getTopLeft(find.text('Overall place')).dy),
      );

      await openMatches(tester);
      expect(find.text('Set by hand'), findsOneWidget);
    });

    testWidgets('a quiz run carries no hand-set marker', (tester) async {
      await pumpResults(tester);
      expect(find.text('Set by hand'), findsNothing);
    });
  });

  group('National / state scope', () {
    /// Two senators from different states plus a president, so the scope
    /// filter has something to actually exclude.
    Future<void> pumpScoped(WidgetTester tester, {String? homeState}) async {
      await pumpResults(
        tester,
        homeState: homeState,
        data: testAppData(
          politicians: [
            testPolitician(),
            testSenator(id: 'peters', name: 'Gary Peters', state: 'MI'),
            testSenator(id: 'sanders', name: 'Bernie Sanders', state: 'VT'),
          ],
        ),
      );
      await openMatches(tester);
    }

    testWidgets('defaults to the state they chose', (tester) async {
      await pumpScoped(tester, homeState: 'MI');
      expect(find.text('Michigan'), findsOneWidget);
      expect(find.text('National'), findsOneWidget);
      expect(find.textContaining('Your Michigan ballot'), findsOneWidget);
      expect(find.text('Gary Peters'), findsOneWidget);
      expect(find.text('Bernie Sanders'), findsNothing);
    });

    testWidgets('National widens the list to other states', (tester) async {
      await pumpScoped(tester, homeState: 'MI');
      await tester.tap(find.text('National'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Everyone nationwide'), findsOneWidget);
      expect(find.text('Bernie Sanders'), findsOneWidget);
    });

    testWidgets('switching back narrows to the state again', (tester) async {
      await pumpScoped(tester, homeState: 'MI');
      await tester.tap(find.text('National'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Michigan'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Your Michigan ballot'), findsOneWidget);
      expect(find.text('Bernie Sanders'), findsNothing);
    });

    testWidgets('no home state means national with no toggle', (tester) async {
      await pumpScoped(tester);
      expect(find.text('National'), findsNothing);
      expect(find.textContaining('Everyone nationwide'), findsOneWidget);
      expect(find.text('Bernie Sanders'), findsOneWidget);
    });
  });

  group('The headline match', () {
    /// A near-perfect out-of-state match plus a middling in-state one, so the
    /// scope toggle actually changes who leads.
    Future<void> pumpRanked(WidgetTester tester, {String? homeState}) async {
      await pumpResults(
        tester,
        homeState: homeState,
        profile: testProfile(
          issueScores: const {'taxes': -90, 'abortion': -80},
        ),
        data: testAppData(
          politicians: [
            testPolitician(),
            testPolitician(
              id: 'peters',
              name: 'Gary Peters',
              role: 'U.S. Senator (MI)',
              state: 'MI',
              officeType: 'senator',
              current: true,
              officeHistory: const ['U.S. Senator, MI (2015–present)'],
              issues: const {'taxes': -85, 'abortion': -75},
            ),
            testSenator(id: 'sanders', name: 'Bernie Sanders'),
          ],
        ),
      );
    }

    testWidgets('follows the state scope the list is set to', (tester) async {
      await pumpRanked(tester, homeState: 'MI');
      expect(find.text('Closest: Gary Peters'), findsOneWidget);
      expect(find.text('MICHIGAN'), findsOneWidget);

      await openMatches(tester);
      await tester.tap(find.text('National'));
      await tester.pumpAndSettle();

      expect(find.text('Closest: Bernie Sanders'), findsOneWidget);
      expect(find.text('NATIONWIDE'), findsOneWidget);
    });

    testWidgets('follows an office filter picked in the sheet', (tester) async {
      await pumpRanked(tester, homeState: 'MI');
      await openMatches(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('U.S. Senate'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Show '));
      await tester.pumpAndSettle();

      expect(find.text('Closest: Gary Peters'), findsOneWidget);
      expect(find.text('MICHIGAN · U.S. SENATE'), findsOneWidget);
    });

    testWidgets('flips to the furthest when the list does', (tester) async {
      await pumpRanked(tester, homeState: 'MI');
      await openMatches(tester);
      await tester.tap(find.text('Closest first'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Closest:'), findsNothing);
      expect(find.text('Furthest: Barack Obama'), findsOneWidget);
      expect(find.text('Furthest first'), findsOneWidget);
    });
  });

  group('The filter sheet', () {
    testWidgets('badges the control and previews the count', (tester) async {
      await pumpResults(
        tester,
        data: testAppData(
          politicians: [
            testPolitician(),
            testSenator(id: 'peters', name: 'Gary Peters', state: 'MI'),
          ],
        ),
      );
      await openMatches(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Show 2 figures'), findsOneWidget);

      await tester.tap(find.text('Democratic'));
      await tester.pumpAndSettle();
      expect(find.text('Show 1 figure'), findsOneWidget);

      await tester.tap(find.text('Show 1 figure'));
      await tester.pumpAndSettle();
      // One active filter, badged on the control and counted on the tab.
      final filtersRow = find
          .ancestor(of: find.text('Filters'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(of: filtersRow, matching: find.text('1')),
        findsOneWidget,
      );
      expect(find.text('Matches · 1'), findsOneWidget);
    });

    testWidgets('filtering to nobody offers the way back', (tester) async {
      await pumpResults(
        tester,
        data: testAppData(politicians: [testPolitician()]),
      );
      await openMatches(tester);
      await tester.tap(find.text('Filters'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Republican'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show 0 figures'));
      await tester.pumpAndSettle();

      expect(find.text('No one is left'), findsOneWidget);
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('No one is left'), findsNothing);
    });
  });

  testWidgets('the match list starts at twenty', (tester) async {
    await pumpResults(
      tester,
      homeState: null,
      data: testAppData(
        politicians: [
          for (var i = 0; i < 25; i++)
            testPolitician(id: 'p$i', name: 'Figure $i'),
        ],
      ),
    );
    await openMatches(tester);
    await tester.scrollUntilVisible(
      find.textContaining('Show more'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Show more (5 left)'), findsOneWidget);
  });

  testWidgets('the app bar shares, left of the methodology button', (
    tester,
  ) async {
    await pumpResults(tester, height: 1600);
    final share = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.ios_share),
    );
    final info = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.info_outline),
    );
    expect(share, findsOneWidget);
    expect(tester.getCenter(share).dx, lessThan(tester.getCenter(info).dx));
  });
}
