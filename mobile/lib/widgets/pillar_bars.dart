import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/question.dart';
import '../models/scoring.dart';
import '../theme/app_theme.dart';
import 'steel_man_card.dart';

/// Visual pillar placements on Liberal 100 ← 0 → Conservative 100.
class PillarBars extends StatelessWidget {
  const PillarBars({
    super.key,
    required this.pillarScores,
    required this.pillarLabels,
    this.title = 'Your pillars',
  });

  final Map<String, double> pillarScores;
  final Map<String, String> pillarLabels;
  final String title;

  @override
  Widget build(BuildContext context) {
    final entries = pillarScores.entries.toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Liberal 100 ← 0 → Conservative 100',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 16),
          for (final e in entries) ...[
            _PillarRow(label: pillarLabels[e.key] ?? e.key, score: e.value),
            if (e.key != entries.last.key) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _PillarRow extends StatelessWidget {
  const _PillarRow({required this.label, required this.score});

  final String label;
  final double score;

  @override
  Widget build(BuildContext context) {
    final t = ((score + 100) / 200).clamp(0.0, 1.0);
    final color = score < -4
        ? AppColors.liberal
        : score > 4
        ? AppColors.conservative
        : AppColors.center;

    // Merged so a reader hears "Economy, moderately liberal, 40" once — the
    // gradient bar itself carries no semantics.
    return MergeSemantics(
      child: Semantics(
        label:
            '$label: ${Scoring.labelForScore(score)}, '
            '${Scoring.formatScore(score)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                Text(
                  Scoring.formatScore(score),
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 18,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final x = t * constraints.maxWidth;
                  return Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(99),
                          gradient: LinearGradient(
                            colors: [
                              AppColors.liberal,
                              AppColors.parchment,
                              AppColors.conservative,
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: (x - 7).clamp(0.0, constraints.maxWidth - 14),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.sheet,
                            shape: BoxShape.circle,
                            border: Border.all(color: color, width: 2.5),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.ink.withValues(alpha: 0.12),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Expandable list of issue-level scores with clear side labels.
class IssueScoreBreakdown extends StatelessWidget {
  const IssueScoreBreakdown({
    super.key,
    required this.issueScores,
    required this.issueLabels,
    this.issueWeights = const {},
    this.questions = const [],
  });

  final Map<String, double> issueScores;
  final Map<String, String> issueLabels;
  final Map<String, double> issueWeights;
  final List<Question> questions;

  @override
  Widget build(BuildContext context) {
    final entries = issueScores.entries.toList()
      ..sort((a, b) {
        final wa = issueWeights[a.key] ?? 1.0;
        final wb = issueWeights[b.key] ?? 1.0;
        final byWeight = wb.compareTo(wa);
        if (byWeight != 0) return byWeight;
        return (issueLabels[a.key] ?? a.key).compareTo(
          issueLabels[b.key] ?? b.key,
        );
      });

    return Material(
      color: AppColors.sheet,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          title: Text(
            'Your issue scores',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
          subtitle: Text(
            issueWeights.isEmpty
                ? 'Tap to see every issue you were scored on'
                : 'Sorted by how much you said it matters',
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          children: [
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _IssueScoreRow(
                  score: e.value,
                  label: issueLabels[e.key] ?? e.key,
                  weightLabel: issueWeights.isEmpty
                      ? null
                      : Scoring.importanceLabelForWeight(
                          issueWeights[e.key] ?? 1.0,
                        ),
                  steelMan: Scoring.steelManQuestion(
                    issueId: e.key,
                    userScore: e.value,
                    questions: questions,
                  )?.steelManArgument,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _IssueScoreRow extends StatelessWidget {
  const _IssueScoreRow({
    required this.score,
    required this.label,
    required this.weightLabel,
    required this.steelMan,
  });

  final double score;
  final String label;
  final String? weightLabel;
  final String? steelMan;

  @override
  Widget build(BuildContext context) {
    if (steelMan != null) {
      return SteelManCard(
        issueLabel: label,
        scoreLabel: Scoring.formatScore(score),
        score: score,
        argument: steelMan!,
      );
    }
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
              if (weightLabel != null)
                Text(
                  weightLabel!,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          Scoring.formatScore(score),
          style: GoogleFonts.manrope(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: score < -4
                ? AppColors.liberal
                : score > 4
                ? AppColors.conservative
                : AppColors.center,
          ),
        ),
      ],
    );
  }
}
