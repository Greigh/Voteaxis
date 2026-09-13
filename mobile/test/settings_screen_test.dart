import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/app_settings.dart';
import 'package:voteaxis/models/politician.dart';
import 'package:voteaxis/screens/settings_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  /// Pumps the screen and hands back the last settings it emitted.
  Future<AppSettings Function()> pump(
    WidgetTester tester, {
    AppSettings settings = const AppSettings(),
    String? homeStateCode = 'MI',
    VoidCallback? onTransfer,
    Future<void> Function()? onClearProgress,
    Future<void> Function()? onDeleteEverything,
    Future<void> Function(String)? onHomeState,
    bool hasInProgress = false,
    bool hasSavedResult = false,
  }) async {
    var latest = settings;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SettingsScreen(
          settings: settings,
          onSettings: (next) async => latest = next,
          homeStateCode: homeStateCode,
          onHomeState: onHomeState ?? (_) async {},
          onTransfer: onTransfer,
          onClearProgress: onClearProgress,
          onDeleteEverything: onDeleteEverything,
          hasInProgress: hasInProgress,
          hasSavedResult: hasSavedResult,
        ),
      ),
    );
    return () => latest;
  }

  Future<void> toggle(WidgetTester tester, String title) async {
    await tester.scrollUntilVisible(find.text(title), 200);
    // scrollUntilVisible ends in an ensureVisible that jumps without pumping,
    // so the render tree is a frame behind until we settle it.
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  group('how far back', () {
    testWidgets('three floors are exclusive and 2000s plus is default', (
      tester,
    ) async {
      final latest = await pump(tester);
      await tester.scrollUntilVisible(find.text('2000s plus'), 200);
      await tester.pumpAndSettle();
      expect(find.text('2000s plus'), findsOneWidget);
      expect(find.text('1980s plus'), findsOneWidget);
      expect(find.text('1960s plus'), findsOneWidget);

      await tester.tap(find.text('1980s plus'));
      await tester.pumpAndSettle();
      expect(latest().figureFloor, 1980);
    });

    testWidgets('time-blind is disabled on 2000s plus', (tester) async {
      await pump(tester, settings: const AppSettings(timeBlind: true));
      await tester.scrollUntilVisible(find.text('Time-blind matching'), 200);
      await tester.pumpAndSettle();
      final toggle = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Time-blind matching'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(toggle.onChanged, isNull);
      expect(toggle.value, isFalse);
    });

    testWidgets('time-blind is settable once the floor allows it', (
      tester,
    ) async {
      final latest = await pump(
        tester,
        settings: const AppSettings(figureFloor: FigureFloor.year1960),
      );
      await toggle(tester, 'Time-blind matching');
      expect(latest().timeBlind, isTrue);
    });
  });

  group('the quiz', () {
    testWidgets('skip the quiz is off by default and toggles on', (
      tester,
    ) async {
      final latest = await pump(tester);
      expect(latest().skipQuiz, isFalse);
      await toggle(tester, 'Skip the quiz');
      expect(latest().skipQuiz, isTrue);
    });

    testWidgets('quiz length offers three options and reports the choice', (
      tester,
    ) async {
      final latest = await pump(tester);
      await tester.scrollUntilVisible(find.text('Quiz length'), 200);
      expect(find.text('Short'), findsOneWidget);
      expect(find.text('Standard'), findsOneWidget);
      expect(find.text('Long'), findsOneWidget);

      await tester.tap(find.text('Long'));
      await tester.pumpAndSettle();
      expect(latest().quizLength, 40);

      await tester.tap(find.text('Short'));
      await tester.pumpAndSettle();
      expect(latest().quizLength, 12);
    });

    testWidgets('dealbreaker prompts can be turned off', (tester) async {
      final latest = await pump(tester);
      await toggle(tester, 'Dealbreaker prompts');
      expect(latest().dealbreakerPrompts, isFalse);
    });
  });

  group('feel', () {
    testWidgets('haptics, motion, and the widget each toggle independently', (
      tester,
    ) async {
      final latest = await pump(tester);
      await toggle(tester, 'Haptics');
      expect(latest().haptics, isFalse);
      expect(latest().reduceMotion, isFalse);

      await toggle(tester, 'Reduce motion');
      expect(latest().reduceMotion, isTrue);
      expect(latest().haptics, isFalse);

      await toggle(tester, 'Issue of the Day widget');
      expect(latest().issueWidget, isFalse);
    });
  });

  group('your ballot', () {
    testWidgets('shows the home state and opens the picker', (tester) async {
      String? picked;
      await pump(tester, onHomeState: (code) async => picked = code);
      await tester.scrollUntilVisible(find.text('Home state'), 200);
      expect(find.text('Michigan'), findsOneWidget);

      await tester.tap(find.text('Home state'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Alabama'));
      await tester.pumpAndSettle();
      expect(picked, 'AL');
      expect(find.text('Alabama'), findsOneWidget);
    });

    testWidgets('the section is hidden with no handler', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: SettingsScreen(
            settings: const AppSettings(),
            onSettings: (_) async {},
          ),
        ),
      );
      expect(find.text('Home state'), findsNothing);
    });
  });

  group('your data', () {
    testWidgets('transfer is only offered when it is wired up', (tester) async {
      await pump(tester);
      expect(find.text('Share & transfer'), findsNothing);

      var opened = false;
      await pump(tester, onTransfer: () => opened = true);
      await tester.scrollUntilVisible(find.text('Share & transfer'), 200);
      await tester.tap(find.text('Share & transfer'));
      expect(opened, isTrue);
    });

    testWidgets('discarding a draft is disabled with nothing in progress', (
      tester,
    ) async {
      var cleared = false;
      await pump(tester, onClearProgress: () async => cleared = true);
      await tester.scrollUntilVisible(
        find.text('Discard in-progress quiz'),
        200,
      );
      expect(find.text('Nothing in progress'), findsOneWidget);
      await tester.tap(find.text('Discard in-progress quiz'));
      await tester.pumpAndSettle();
      expect(cleared, isFalse);
    });

    testWidgets('discarding a draft runs and then reads as empty', (
      tester,
    ) async {
      var cleared = false;
      await pump(
        tester,
        hasInProgress: true,
        onClearProgress: () async => cleared = true,
      );
      await tester.scrollUntilVisible(
        find.text('Discard in-progress quiz'),
        200,
      );
      await tester.tap(find.text('Discard in-progress quiz'));
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
      expect(find.text('In-progress quiz discarded'), findsOneWidget);
      expect(find.text('Nothing in progress'), findsOneWidget);
    });

    testWidgets('delete everything asks first and can be cancelled', (
      tester,
    ) async {
      var deleted = false;
      await pump(
        tester,
        hasSavedResult: true,
        onDeleteEverything: () async => deleted = true,
      );
      await tester.scrollUntilVisible(find.text('Delete everything'), 200);
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      expect(find.text('Delete everything?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);
    });

    testWidgets('confirming delete runs it and resets the visible settings', (
      tester,
    ) async {
      var deleted = false;
      await pump(
        tester,
        settings: const AppSettings(skipQuiz: true),
        hasSavedResult: true,
        onDeleteEverything: () async => deleted = true,
      );
      await tester.scrollUntilVisible(find.text('Delete everything'), 200);
      await tester.tap(find.text('Delete everything'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);

      await tester.scrollUntilVisible(find.text('Skip the quiz'), -200);
      final toggle = tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text('Skip the quiz'),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(toggle.value, isFalse);
    });
  });

  testWidgets('contribute is always reachable', (tester) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.text('Contribute to Voteaxis'), 200);
    expect(find.text('Contribute to Voteaxis'), findsOneWidget);
  });
}
