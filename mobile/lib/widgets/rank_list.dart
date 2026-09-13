import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_data.dart';
import '../models/politician.dart';
import '../models/scoring.dart';
import '../theme/app_theme.dart';

class RankList extends StatelessWidget {
  const RankList({
    super.key,
    required this.matches,
    required this.data,
    required this.onTap,
    this.userAxisScore,
    this.furthest = false,
    this.timeBlind = false,
  });

  final List<MatchResult> matches;
  final AppData data;
  final void Function(Politician politician) onTap;
  final double? userAxisScore;
  final bool furthest;
  final bool timeBlind;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: matches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final match = matches[index];
        final p = match.politician;
        final agree = match.agreements
            .map((o) => data.issuesById[o.issueId]?.label ?? o.issueId)
            .take(2)
            .join(', ');
        final differ = match.disagreements
            .map((o) => data.issuesById[o.issueId]?.label ?? o.issueId)
            .take(2)
            .join(', ');
        final sideColor = match.axisScore < -4
            ? AppColors.liberal
            : match.axisScore > 4
            ? AppColors.conservative
            : AppColors.center;
        final dealLabels = match.dealbreakerHits
            .map((id) => data.issuesById[id]?.label ?? id)
            .join(', ');

        return Material(
          color: AppColors.sheet,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onTap(p),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: match.hasDealbreaker
                      ? AppColors.conservative.withValues(alpha: 0.35)
                      : index == 0
                      ? AppColors.ink.withValues(alpha: 0.16)
                      : AppColors.ink.withValues(alpha: 0.06),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: index == 0
                              ? AppColors.ink
                              : AppColors.parchment,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: index == 0
                                ? AppColors.sheet
                                : AppColors.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: sideColor.withValues(alpha: 0.12),
                        foregroundColor: sideColor,
                        child: Text(
                          p.initials,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              style: GoogleFonts.manrope(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timeBlind ? p.eraBlindRole : p.role,
                              style: GoogleFonts.manrope(
                                color: AppColors.inkMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${match.closeness}%',
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Stretch keeps the three chips level once a long value like
                  // "Conservative 100" wraps onto a second line. It needs a
                  // bounded height, which IntrinsicHeight supplies — the Row
                  // sits in a Column with none of its own.
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _ScoreStat(
                            label: 'Their place',
                            caption: Scoring.splitScore(match.axisScore).side,
                            value: Scoring.splitScore(
                              match.axisScore,
                            ).magnitude,
                            color: sideColor,
                          ),
                        ),
                        if (userAxisScore != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: _ScoreStat(
                              label: 'You',
                              caption: Scoring.splitScore(userAxisScore!).side,
                              value: Scoring.splitScore(
                                userAxisScore!,
                              ).magnitude,
                              color: userAxisScore! < -4
                                  ? AppColors.liberal
                                  : userAxisScore! > 4
                                  ? AppColors.conservative
                                  : AppColors.center,
                            ),
                          ),
                        ],
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ScoreStat(
                            label: furthest ? 'Gap' : 'Match',
                            value: furthest
                                ? '${match.distance.round()} pts'
                                : '${match.closeness}%',
                            color: AppColors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (match.hasDealbreaker) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Dealbreaker clash: $dealLabels',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.conservative,
                      ),
                    ),
                  ],
                  if (agree.isNotEmpty || differ.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      [
                        if (agree.isNotEmpty) 'Closest on $agree',
                        if (differ.isNotEmpty) 'Furthest on $differ',
                      ].join(' · '),
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScoreStat extends StatelessWidget {
  const _ScoreStat({
    required this.label,
    required this.value,
    required this.color,
    this.caption,
  });

  final String label;

  /// The number on its own line, so it is never the part that gets cut.
  final String value;
  final Color color;

  /// Optional side word ("Liberal", "Conservative") above the number.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.inkMuted,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          // "Conservative 100" on one ellipsized line hid the number, which is
          // the part that actually matters. Side word and number are stacked
          // so only the word can ever be shortened.
          if (caption != null)
            // "Conservative" is the longest side word and just overruns the
            // chip at 11px on a narrow phone. Scaling beats ellipsizing: the
            // whole word stays readable either way.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                caption!,
                maxLines: 1,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          Text(
            value,
            maxLines: 1,
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
