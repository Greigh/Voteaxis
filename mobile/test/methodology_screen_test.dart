import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/screens/methodology_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pump(WidgetTester tester, {String? topic}) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MethodologyScreen(initialTopic: topic),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens as a table of contents, not a wall of prose', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Spectrum Issue Index (SII) v1'), findsOneWidget);

    // The three groups, and every chapter titled under them.
    expect(find.text('HOW YOU ARE SCORED'), findsOneWidget);
    expect(find.text('HOW FIGURES ARE SCORED'), findsOneWidget);
    expect(find.text('SETTINGS THAT CHANGE THIS'), findsOneWidget);
    for (final title in [
      'Issues & importance',
      'Five pillars',
      'Overall axis',
      'Matching',
      'Confidence & roll-call votes',
      'Congress receipts',
      'How far back',
      'Issue of the Day widget',
    ]) {
      // Scoped to the tiles: 'Five pillars' is also a step in the diagram.
      expect(
        find.descendant(
          of: find.byType(ExpansionTile),
          matching: find.text(title),
        ),
        findsOneWidget,
        reason: title,
      );
    }

    // Collapsed by default: the bodies are not built until you open one.
    expect(find.textContaining('Steel Man'), findsNothing);
  });

  testWidgets('the pipeline card leads with how a score is built', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Your answers'), findsOneWidget);
    expect(find.text('Issues'), findsOneWidget);
    expect(find.text('Five pillars'), findsNWidgets(2));
    expect(find.text('Your axis'), findsOneWidget);
  });

  testWidgets('a chapter opens on tap', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Issues & importance'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Steel Man'), findsOneWidget);
    expect(find.text('Liberal 100 ← 0 → Conservative 100'), findsOneWidget);
  });

  testWidgets('the floors come from FigureFloor, not a second copy', (
    tester,
  ) async {
    await pump(tester, topic: MethodologyTopic.floor);
    expect(find.text('2000s plus'), findsOneWidget);
    expect(find.text('1980s plus'), findsOneWidget);
    expect(find.text('1960s plus'), findsOneWidget);
    expect(
      find.textContaining('Sitting members always appear'),
      findsOneWidget,
    );
  });

  testWidgets('an initial topic opens that chapter expanded', (tester) async {
    await pump(tester, topic: MethodologyTopic.confidence);
    expect(find.textContaining('DW-NOMINATE'), findsOneWidget);
    // Its neighbours stay shut.
    expect(find.textContaining('Steel Man'), findsNothing);
  });

  testWidgets('the daily widget chapter still disclaims the quiz', (
    tester,
  ) async {
    await pump(tester, topic: MethodologyTopic.dailyIssue);
    expect(find.text('It does not replace the quiz.'), findsOneWidget);
  });
}
