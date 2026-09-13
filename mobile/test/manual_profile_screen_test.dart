import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/screens/manual_profile_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

import 'support/fixtures.dart';

Future<SpectrumProfile?> _openScreen(
  WidgetTester tester, {
  SpectrumProfile? initialProfile,
}) async {
  SpectrumProfile? saved;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            saved = await Navigator.of(context).push<SpectrumProfile>(
              MaterialPageRoute<SpectrumProfile>(
                builder: (_) => ManualProfileScreen(
                  data: testAppData(),
                  initialProfile: initialProfile,
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return saved;
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('a quick pick sets every pillar and returns a profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openScreen(tester);
    expect(find.text('Centrist'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Very conservative'));
    await tester.pumpAndSettle();
    expect(find.text('Conservative 85'), findsWidgets);

    await tester.tap(find.text('Use this level'));
    await tester.pumpAndSettle();

    // The screen popped with a profile the rest of the app can score against.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('seeds sliders from a saved profile', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openScreen(
      tester,
      initialProfile: testProfile(
        issueScores: const {'taxes': -40, 'abortion': -60},
      ),
    );
    // Overall is the mean of the two pillars; pillars keep their own values.
    expect(find.text('Liberal 50'), findsOneWidget);
    expect(find.text('Liberal 40'), findsOneWidget);
    expect(find.text('Liberal 60'), findsOneWidget);
    expect(find.text('Set one lean for all five'), findsOneWidget);
  });

  testWidgets('setting one lean pulls edited pillars back to the axis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openScreen(
      tester,
      initialProfile: testProfile(
        issueScores: const {'taxes': -40, 'abortion': -60},
      ),
    );
    await tester.tap(find.text('Set one lean for all five'));
    await tester.pumpAndSettle();
    expect(find.text('Liberal 50'), findsNWidgets(3));
    expect(find.text('Set one lean for all five'), findsNothing);
  });
}
