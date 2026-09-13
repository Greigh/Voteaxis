import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/screens/onboarding_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('asks for a home state before continuing', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: OnboardingScreen(onContinue: (code) async => chosen = code),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Where do you vote?'), findsOneWidget);
    expect(find.text('Your state'), findsOneWidget);
    expect(chosen, isNull);
  });
}
