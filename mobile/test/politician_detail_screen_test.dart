import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/screens/politician_detail_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'detail shows match story, stance card, and ancestry when past UI is on',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = testPolitician();
      final kennedy = testPolitician(
        id: 'jfk',
        name: 'John F. Kennedy',
        role: '35th President',
        officeHistory: const ['President of the United States (1961–1963)'],
        issues: const {'taxes': -45, 'abortion': -40},
        signatureStances: const [],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PoliticianDetailScreen(
            politician: now,
            userProfile: testProfile(),
            data: testAppData(politicians: [now, kennedy]),
            figureFloor: 2000,
          ),
        ),
      );
      expect(find.text('Barack Obama'), findsWidgets);
      expect(find.textContaining('match'), findsWidgets);
      expect(find.text('STANCE CARDS'), findsOneWidget);
      expect(find.text('POLITICAL ANCESTRY'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: PoliticianDetailScreen(
            politician: now,
            userProfile: testProfile(),
            data: testAppData(politicians: [now, kennedy]),
            figureFloor: 1980,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('POLITICAL ANCESTRY'), findsOneWidget);
      expect(find.text('John F. Kennedy'), findsOneWidget);
    },
  );

  testWidgets('detail vote record slider moves the session label', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PoliticianDetailScreen(
          politician: senator,
          userProfile: testProfile(),
          data: testAppData(politicians: [senator]),
        ),
      ),
    );
    expect(find.text('VOTE RECORD'), findsOneWidget);
    expect(find.textContaining('118th Congress'), findsWidgets);
    await tester.tap(find.text('117th'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2021–2022'), findsOneWidget);
    expect(find.textContaining('Corporate tax cut'), findsOneWidget);
  });
}
