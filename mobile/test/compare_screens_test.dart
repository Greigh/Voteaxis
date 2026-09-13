import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voteaxis/screens/compare_screen.dart';
import 'package:voteaxis/services/result_store.dart';
import 'package:voteaxis/screens/friend_compare_screen.dart';
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

  testWidgets('compare saved runs screen loads', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CompareScreen(baseProfile: testProfile(), data: testAppData()),
      ),
    );
    await tester.pump();
    expect(find.text('Compare saved runs'), findsOneWidget);
  });

  testWidgets('a hand-set run leads the earlier-run list', (tester) async {
    final store = ResultStore();
    // Saved oldest first, so the hand-set run sits in the middle of history.
    await store.saveRun(
      QuizRun(
        timestampMs: 1,
        issueScores: const {'taxes': -10, 'abortion': -10},
        pillarScores: const {'economy': -10, 'society': -10},
        axisScore: -10,
      ),
    );
    await store.saveRun(
      QuizRun(
        timestampMs: 2,
        issueScores: const {'taxes': -20, 'abortion': -20},
        pillarScores: const {'economy': -20, 'society': -20},
        axisScore: -20,
        label: QuizRun.handSetLabel,
      ),
    );
    await store.saveRun(
      QuizRun(
        timestampMs: 3,
        issueScores: const {'taxes': -30, 'abortion': -30},
        pillarScores: const {'economy': -30, 'society': -30},
        axisScore: -30,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: CompareScreen(baseProfile: testProfile(), data: testAppData()),
      ),
    );
    await tester.pumpAndSettle();

    // Newest (timestamp 3) is the latest run, so the earlier list leads with
    // the hand-set run — and that is what the Earlier tile compares against,
    // not the older scored run at Liberal 10.
    expect(find.text('Liberal 20'), findsOneWidget);
    expect(find.text('Liberal 10'), findsNothing);
  });

  testWidgets('friend compare explains the 6-digit code', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FriendCompareScreen(data: testAppData(), profile: testProfile()),
      ),
    );
    await tester.pump();
    expect(find.text('Compare with a friend'), findsOneWidget);
    expect(find.textContaining('show the QR'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('invalid typed code stays local', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FriendCompareScreen(data: testAppData(), profile: testProfile()),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1');
    await tester.pump();
    await tester.ensureVisible(find.text('Plot us'));
    await tester.tap(find.text('Plot us'));
    await tester.pump();
    expect(find.text('That code is not valid.'), findsOneWidget);
  });
}
