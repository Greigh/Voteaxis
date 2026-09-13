import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voteaxis/theme/app_theme.dart';
import 'package:voteaxis/widgets/spectrum_bar.dart';

void main() {
  testWidgets('spectrum bar paints user and match markers', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SpectrumBar(
            userScore: -40,
            highlightId: 'obama',
            markers: [
              SpectrumMarker(id: 'obama', score: -42, distance: 8),
              SpectrumMarker(id: 'bush', score: 52, distance: 90),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(SpectrumBar), findsOneWidget);
    expect(find.text('Liberal 100'), findsOneWidget);
    expect(find.text('Conservative 100'), findsOneWidget);
  });
}
