import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/screens/contribute_screen.dart';
import 'package:voteaxis/theme/app_theme.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('US locale offers web checkout and does not unlock features', (
    tester,
  ) async {
    Uri? launched;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ContributeScreen(
          locale: const Locale('en', 'US'),
          onLaunch: (uri) async {
            launched = uri;
            return true;
          },
        ),
      ),
    );
    expect(find.text('Fund the instrument, not a paywall'), findsOneWidget);
    expect(find.textContaining('does not unlock fairness'), findsOneWidget);
    expect(find.text('Continue on the web'), findsOneWidget);
    await tester.tap(find.text('Continue on the web'));
    await tester.pump();
    expect(launched.toString(), 'https://voteaxis.org/contribute');
  });

  testWidgets('non-US locale has no checkout button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ContributeScreen(
          locale: const Locale('en', 'GB'),
          onLaunch: (_) async => true,
        ),
      ),
    );
    expect(find.text('Continue on the web'), findsNothing);
    expect(find.text('voteaxis.org/contribute'), findsOneWidget);
  });
}
