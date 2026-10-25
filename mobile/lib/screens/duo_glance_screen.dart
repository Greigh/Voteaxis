// The propped-pose surface on iPhone Duo: an ambient Issue-of-the-Week card
// that owns the window above the horizontal crease while the device sits in
// tent/laptop pose. No controls — glance content is read at a distance, and
// the pane below the crease stays dark.

import 'package:duo_fold/duo_fold.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/issue_of_the_day.dart';
import '../theme/app_theme.dart';
import '../widgets/mist_backdrop.dart';
import '../widgets/voteaxis_logo.dart';

class DuoGlanceScreen extends StatelessWidget {
  const DuoGlanceScreen({
    super.key,
    required this.fold,
    required this.day,
    this.issueLabel,
    this.axisLabel,
  });

  final DuoFoldState fold;
  final IssueOfTheDay day;

  /// The issue's display name (resolved by the caller — this screen stays
  /// free of app-data plumbing so it can sit above any route).
  final String? issueLabel;

  /// The user's own placement, e.g. "Liberal 62", when a profile exists.
  final String? axisLabel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final division = fold.divisionRegion;
    // In tent pose the horizontal crease splits the display; the visible
    // surface is the pane above it. Fall back to the window when the band
    // is not reported.
    final pane = (division != null && division.width > division.height)
        ? FoldLayout.primaryRect(FoldMode.splitHorizontal, division, size)
        : (Offset.zero & size);

    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        children: [
          Positioned.fromRect(
            rect: pane,
            child: ClipRect(
              child: MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: pane.size,
                  padding: EdgeInsets.zero,
                  viewPadding: EdgeInsets.zero,
                ),
                child: _GlanceCard(
                  day: day,
                  issueLabel: issueLabel,
                  axisLabel: axisLabel,
                ),
              ),
            ),
          ),
          if (division != null && division.width > division.height)
            Positioned.fromRect(
              rect: division.intersect(Offset.zero & size),
              child: ColoredBox(color: AppColors.ink),
            ),
        ],
      ),
    );
  }
}

class _GlanceCard extends StatelessWidget {
  const _GlanceCard({required this.day, this.issueLabel, this.axisLabel});

  final IssueOfTheDay day;
  final String? issueLabel;
  final String? axisLabel;

  @override
  Widget build(BuildContext context) {
    return MistBackdrop(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(36, 24, 36, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const VoteaxisMark(size: 34),
                  const SizedBox(width: 12),
                  Text(
                    'VOTEAXIS',
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.6,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  if (axisLabel != null)
                    Text(
                      axisLabel!,
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: AppColors.inkMuted,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                (issueLabel ?? day.headline).toUpperCase(),
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.8,
                  color: AppColors.liberal,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                day.question,
                style: GoogleFonts.manrope(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1.15,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Open Voteaxis to answer it',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}
