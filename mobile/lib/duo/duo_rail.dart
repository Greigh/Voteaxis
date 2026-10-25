// The secondary-pane rail for iPhone Duo splits. Root screens wrap their
// bodies in DuoFoldBuilder + FoldSplitView and put this beside the fold:
// the editorial/daily issue card when one is resolved, plus the privacy
// card, so the pane is never an empty panel.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/issue_of_the_day.dart';
import '../theme/app_theme.dart';

class DuoRail extends StatelessWidget {
  const DuoRail({
    super.key,
    this.day,
    this.issueLabel,
    this.issueContext,
    this.extra = const [],
  });

  final IssueOfTheDay? day;
  final String? issueLabel;

  /// Editorial context for a live issue of the week.
  final String? issueContext;

  /// Screen-specific cards stacked above the standard pair.
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final card in extra) ...[
                    card,
                    const SizedBox(height: 14),
                  ],
                  if (day != null) ...[
                    DuoRailCard(
                      kicker: day.source == 'week'
                          ? 'ISSUE OF THE WEEK'
                          : 'ISSUE OF THE DAY',
                      title: day.source == 'week'
                          ? day.headline
                          : (issueLabel ?? day.headline),
                      body: day.question,
                      footnote: issueContext,
                    ),
                    const SizedBox(height: 14),
                  ],
                  const DuoRailCard(
                    kicker: 'STAYS YOURS',
                    title: 'Private by design',
                    body:
                        'Answers are stored encrypted on this device — '
                        'no account, no profile sold.',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DuoRailCard extends StatelessWidget {
  const DuoRailCard({
    super.key,
    required this.kicker,
    required this.title,
    required this.body,
    this.footnote,
  });

  final String kicker;
  final String title;
  final String body;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            kicker,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
          if (footnote != null && footnote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              footnote!,
              style: GoogleFonts.manrope(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
