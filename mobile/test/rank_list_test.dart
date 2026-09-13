import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:voteaxis/models/scoring.dart';
import 'package:voteaxis/theme/app_theme.dart';
import 'package:voteaxis/widgets/rank_list.dart';

import 'support/fixtures.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shows closeness and can hide years when time-blind', (
    tester,
  ) async {
    final person = testPolitician();
    final match = MatchResult(
      politician: person,
      distance: 10,
      closeness: 92,
      agreements: const [],
      disagreements: const [],
      axisScore: -40,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RankList(
            matches: [match],
            data: testAppData(politicians: [person]),
            timeBlind: true,
            onTap: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('Barack Obama'), findsOneWidget);
    expect(find.text('92%'), findsWidgets);
    expect(find.textContaining('2009'), findsNothing);
    expect(find.textContaining('President'), findsOneWidget);
  });

  testWidgets('a long conservative place score is not cut off', (tester) async {
    // "Conservative 100" is nearly twice the width of "Liberal 65"; on one
    // ellipsized line the number disappeared entirely.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final person = testPolitician(
      id: 'rogers',
      name: 'Mike Rogers',
      role: '2026 Republican nominee for U.S. Senate (MI)',
      party: 'Republican',
      state: 'MI',
      officeType: 'senator',
      issues: const {'taxes': 100, 'abortion': 90},
    );
    final match = MatchResult(
      politician: person,
      distance: 150,
      closeness: 29,
      agreements: const [],
      disagreements: const [],
      axisScore: 100,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RankList(
            matches: [match],
            data: testAppData(politicians: [person]),
            userAxisScore: -85,
            onTap: (_) {},
          ),
        ),
      ),
    );

    // Side word and number are separate lines, so the number always survives.
    expect(find.text('Conservative'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(
      tester.renderObject<RenderParagraph>(find.text('100')).didExceedMaxLines,
      isFalse,
      reason: 'the score must fit, not ellipsize away',
    );
    // Scaled to fit rather than ellipsized, so the whole word is rendered.
    expect(
      tester
          .renderObject<RenderParagraph>(find.text('Conservative'))
          .didExceedMaxLines,
      isFalse,
      reason: 'the side word must not be truncated',
    );
    expect(
      find.ancestor(
        of: find.text('Conservative'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    // The user's own side is shown next to it and stays intact too.
    expect(find.text('Liberal'), findsOneWidget);
    expect(find.text('85'), findsOneWidget);
  });

  testWidgets('the three stat chips stay level when one wraps', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final person = testPolitician(issues: const {'taxes': 100});
    final match = MatchResult(
      politician: person,
      distance: 150,
      closeness: 29,
      agreements: const [],
      disagreements: const [],
      axisScore: 100,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: RankList(
            matches: [match],
            data: testAppData(politicians: [person]),
            userAxisScore: -85,
            onTap: (_) {},
          ),
        ),
      ),
    );

    final heights = <double>[];
    for (final label in ['Their place', 'You', 'Match']) {
      heights.add(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text(label),
                    matching: find.byType(Container),
                  )
                  .first,
            )
            .height,
      );
    }
    expect(heights.toSet(), hasLength(1), reason: 'chips: $heights');
  });
}
