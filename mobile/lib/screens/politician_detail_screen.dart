import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_data.dart';
import '../duo/duo_scope.dart';
import '../models/politician.dart';
import '../models/scoring.dart';
import '../services/voteaxis_api.dart';
import '../theme/app_theme.dart';
import '../widgets/pillar_bars.dart';
import '../widgets/ui_kit.dart';
import '../widgets/vote_record.dart';

class PoliticianDetailScreen extends StatelessWidget {
  const PoliticianDetailScreen({
    super.key,
    required this.politician,
    this.userProfile,
    required this.data,
    this.match,
    this.figureFloor = FigureFloor.year2000,
    this.embedded = false,
    this.onOpenPolitician,
  });

  final Politician politician;

  /// The viewer's placement. Null when the roster is being browsed without a
  /// quiz (explore mode) — the page then shows their record and issue
  /// positions but no match score, since there is nothing to compare to.
  final SpectrumProfile? userProfile;
  final AppData data;
  final MatchResult? match;
  final int figureFloor;

  /// Rendered inside a fold split's secondary pane rather than pushed as a
  /// route: no back affordance, and ancestry taps are handed to the host
  /// pane instead of navigating.
  final bool embedded;

  /// Host-pane navigation for ancestry taps when [embedded]. Null keeps the
  /// ordinary push behavior.
  final ValueChanged<Politician>? onOpenPolitician;

  @override
  Widget build(BuildContext context) {
    final profile = data.profileFor(politician);
    final user = userProfile;
    final distance = user == null
        ? null
        : Scoring.vectorDistance(
            user.issueScores,
            politician.issues,
            user.issueWeights.isEmpty ? null : user.issueWeights,
          );
    final closeness =
        match?.closeness ??
        (distance == null ? null : Scoring.closenessFromDistance(distance));
    final overlaps = user == null
        ? const <IssueOverlap>[]
        : (politician.issues.keys.where(user.issueScores.containsKey).map((id) {
            final u = user.issueScores[id]!;
            final p = politician.issues[id]!;
            return IssueOverlap(
              issueId: id,
              diff: (u - p).abs(),
              userScore: u,
              politicianScore: p,
            );
          }).toList()..sort((a, b) => a.diff.compareTo(b.diff)));

    final agreements = match?.agreements ?? overlaps.take(3).toList();
    final disagreements =
        match?.disagreements ?? overlaps.reversed.take(2).toList();
    final issueLabels = {for (final i in data.issues) i.id: i.label};
    final story = user == null
        ? ''
        : Scoring.matchStory(
            agreements: agreements,
            disagreements: disagreements,
            issueLabels: issueLabels,
          );
    final pillarLabels = {for (final p in data.pillars) p.id: p.label};
    final dealLabels = user == null
        ? const <String>[]
        : (match?.dealbreakerHits ??
                  Scoring.dealbreakerHits(
                    user: user.issueScores,
                    politician: politician.issues,
                    dealbreakerIssueIds: user.dealbreakerIssueIds,
                  ))
              .map((id) => issueLabels[id] ?? id)
              .toList();
    final ancestor = FigureFloor.showsPastUi(figureFloor)
        ? Scoring.politicalAncestry(
            person: politician,
            roster: data.politicians,
            issues: data.issues,
            floorYear: figureFloor,
          )
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(politician.name),
        automaticallyImplyLeading: !embedded,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: profile.axisScore < 0
                    ? AppColors.liberal.withValues(alpha: 0.15)
                    : AppColors.conservative.withValues(alpha: 0.15),
                foregroundColor: profile.axisScore < 0
                    ? AppColors.liberal
                    : AppColors.conservative,
                child: Text(
                  politician.initials,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      politician.name,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      politician.role,
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.65),
                      ),
                    ),
                    Text(
                      [
                        politician.party,
                        if (politician.state.isNotEmpty) politician.state,
                        if (politician.current) 'Current',
                      ].join(' · '),
                      style: TextStyle(
                        color: AppColors.ink.withValues(alpha: 0.5),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _ConfidenceChip(
                      tag: politician.profileConfidence,
                      note: politician.profileConfidenceNote,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.sheet,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
            ),
            child: user == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Scoring.formatScore(profile.axisScore),
                        style: GoogleFonts.manrope(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        Scoring.labelForScore(profile.axisScore),
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: profile.axisScore < 0
                              ? AppColors.liberal
                              : AppColors.conservative,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Take the quiz and this card shows your match '
                        'instead — where you two line up and where you split.',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$closeness% match',
                        style: GoogleFonts.manrope(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        story,
                        style: GoogleFonts.manrope(
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      if (dealLabels.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Dealbreaker clash on ${dealLabels.join(' and ')}.',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: AppColors.conservative,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
          if (ancestor != null) ...[
            const SizedBox(height: 12),
            Material(
              color: AppColors.sheet,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final open = onOpenPolitician;
                  if (open != null) {
                    open(ancestor);
                    return;
                  }
                  Navigator.of(context).push(
                    foldAwareRoute<void>(
                      context,
                      builder: (_) => PoliticianDetailScreen(
                        politician: ancestor,
                        userProfile: userProfile,
                        data: data,
                        figureFloor: figureFloor,
                      ),
                    ),
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.ink.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POLITICAL ANCESTRY',
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.1,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ancestor.name,
                        style: GoogleFonts.manrope(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Closest match among figures last in office before $figureFloor.',
                        style: GoogleFonts.manrope(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          if (politician.bio.isNotEmpty ||
              politician.officeHistory.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading('Background'),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (politician.bio.isNotEmpty)
                    Text(
                      politician.bio,
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (politician.bio.isNotEmpty &&
                      politician.officeHistory.isNotEmpty)
                    const SizedBox(height: 14),
                  if (politician.officeHistory.isNotEmpty) ...[
                    const MonoNote('OFFICE HISTORY'),
                    const SizedBox(height: 8),
                    ...politician.officeHistory.map(
                      (h) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '• $h',
                          style: GoogleFonts.manrope(
                            fontSize: 13.5,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          SectionHeading(user == null ? 'Issue positions' : 'Side by side'),
          SurfaceCard(
            child: user == null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Where each issue lands them on the axis. A '
                        'floor-vote mark means that score was blended with '
                        'coded roll calls.',
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...politician.issues.entries.map((entry) {
                        return _IssuePositionRow(
                          label: issueLabels[entry.key] ?? entry.key,
                          score: entry.value,
                          rollcallN: politician.rollcallCounts[entry.key],
                        );
                      }),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatRow(
                              label: 'Their axis',
                              value: Scoring.formatScore(profile.axisScore),
                            ),
                          ),
                          Expanded(
                            child: _StatRow(
                              label: 'Your axis',
                              value: Scoring.formatScore(user.axisScore),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Your score against theirs on the issues you share. A '
                        'floor-vote mark means that issue was blended with coded '
                        'roll calls.',
                        style: GoogleFonts.manrope(
                          fontSize: 12.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...overlaps.map((o) {
                        final label = issueLabels[o.issueId] ?? o.issueId;
                        return _IssueCompareRow(
                          label: label,
                          userScore: o.userScore,
                          politicianScore: o.politicianScore,
                          rollcallN: politician.rollcallCounts[o.issueId],
                        );
                      }),
                    ],
                  ),
          ),
          const SizedBox(height: 24),
          const SectionHeading('Pillars'),
          PillarBars(
            pillarScores: profile.pillarScores,
            pillarLabels: pillarLabels,
            title: 'Their pillars',
          ),
          if (politician.displayStances.isNotEmpty) ...[
            const SizedBox(height: 24),
            const SectionHeading('Stance cards'),
            Text(
              'Tap a card for the source note. Documented is a public record; '
              'rollcall is blended from floor votes; inferred is a judgment '
              'from the record we have.',
              style: GoogleFonts.manrope(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 10),
            ...politician.displayStances.map((s) {
              final label = data.issuesById[s.issueId]?.label ?? s.issueId;
              final conf = politician.confidence[s.issueId] ?? 'inferred';
              return _StanceCard(
                issueLabel: label,
                blurb: s.blurb,
                confidence: conf,
                quote: s.quote,
                sourceUrl: s.sourceUrl,
              );
            }),
          ],
          if (politician.bioguideId != null) ...[
            const SizedBox(height: 24),
            _ReceiptsSection(bioguideId: politician.bioguideId!),
          ],
          const SizedBox(height: 24),
          if (!politician.hasVoteRecord)
            const SectionHeading('On the spectrum'),
          VoteRecord(
            politician: politician,
            userScore: user?.axisScore,
            issueLabels: issueLabels,
            lifetimeAxis: profile.axisScore,
            lifetimeDistance: distance,
          ),
        ],
      ),
    );
  }
}

class _IssueCompareRow extends StatelessWidget {
  const _IssueCompareRow({
    required this.label,
    required this.userScore,
    required this.politicianScore,
    this.rollcallN,
  });

  final String label;
  final double userScore;
  final double politicianScore;
  final int? rollcallN;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.sheet,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
            ),
            if (rollcallN != null &&
                rollcallN! >= Scoring.rollcallMinVotes) ...[
              const SizedBox(height: 2),
              Text(
                '$rollcallN floor votes in the SII blend',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'You  ${Scoring.formatScore(userScore)}',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Them  ${Scoring.formatScore(politicianScore)}',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StanceCard extends StatefulWidget {
  const _StanceCard({
    required this.issueLabel,
    required this.blurb,
    required this.confidence,
    this.quote,
    this.sourceUrl,
  });

  final String issueLabel;
  final String blurb;
  final String confidence;
  final String? quote;
  final String? sourceUrl;

  @override
  State<_StanceCard> createState() => _StanceCardState();
}

class _StanceCardState extends State<_StanceCard> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _flipped = !_flipped),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.issueLabel,
                        style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.parchment,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.confidence,
                        style: GoogleFonts.ibmPlexMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _flipped
                      ? widget.blurb
                      : 'Tap for the source note on this stance.',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: _flipped ? AppColors.ink : AppColors.inkMuted,
                  ),
                ),
                if (_flipped && widget.quote != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '“${widget.quote}”',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      height: 1.4,
                      fontStyle: FontStyle.italic,
                      color: AppColors.ink,
                    ),
                  ),
                ],
                if (_flipped && widget.sourceUrl != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    widget.sourceUrl!,
                    style: GoogleFonts.ibmPlexMono(
                      fontSize: 11,
                      height: 1.35,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Profile-level rollup of the per-issue confidence map, shown under the name.
class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.tag, required this.note});

  final String tag;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
          ),
          child: Text(
            '$tag profile',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.inkMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            note,
            style: GoogleFonts.manrope(
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: AppColors.ink.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Two of these sit side by side, so the two axes read as one comparison
/// rather than two facts in a list.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.ibmPlexMono(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.manrope(
            fontWeight: FontWeight.w800,
            fontSize: 18,
            letterSpacing: -0.4,
          ),
        ),
      ],
    );
  }
}

class _ReceiptsSection extends StatefulWidget {
  const _ReceiptsSection({required this.bioguideId});

  final String bioguideId;

  @override
  State<_ReceiptsSection> createState() => _ReceiptsSectionState();
}

class _ReceiptsSectionState extends State<_ReceiptsSection> {
  final _api = VoteaxisApi();
  late final Future<CongressReceipts> _future = _api.receipts(
    widget.bioguideId,
  );

  @override
  void dispose() {
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CongressReceipts>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          final message = snapshot.error is ApiException
              ? (snapshot.error! as ApiException).message
              : 'Congress receipts are unavailable right now.';
          return _receiptsHeader(context, message);
        }
        final receipts = snapshot.data!;
        if (receipts.isEmpty) {
          return _receiptsHeader(
            context,
            'No recent sponsored or cosponsored bills are in the Voteaxis Congress index.',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading('Congress receipts'),
            const SizedBox(height: 4),
            Text(
              'Roster from BICAM. Latest action and official summaries from Congress.gov when available. These are bills, not a rescore of the Spectrum Issue Index.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
            if (receipts.sponsored.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Sponsored',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              for (final bill in receipts.sponsored.take(5))
                _ReceiptCard(bill: bill),
            ],
            if (receipts.cosponsored.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Cosponsored',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                  color: AppColors.inkMuted,
                ),
              ),
              const SizedBox(height: 8),
              for (final bill in receipts.cosponsored.take(5))
                _ReceiptCard(bill: bill),
            ],
            if (receipts.memberUrl.isNotEmpty)
              SelectableText(
                receipts.memberUrl,
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: AppColors.inkMuted,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _receiptsHeader(BuildContext context, String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading('Congress receipts'),
        const SizedBox(height: 6),
        Text(
          message,
          style: GoogleFonts.manrope(
            fontSize: 13,
            height: 1.4,
            color: AppColors.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({required this.bill});

  final CongressBill bill;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.sheet,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bill.title,
              style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
            ),
            if (bill.summary != null) ...[
              const SizedBox(height: 6),
              Text(
                bill.summary!,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.4,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              bill.citation,
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.inkMuted,
              ),
            ),
            if (bill.introducedDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Introduced ${bill.introducedDate}',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
            if (bill.latestAction != null) ...[
              const SizedBox(height: 6),
              Text(
                bill.latestAction!,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  height: 1.35,
                  color: AppColors.inkMuted,
                ),
              ),
            ],
            const SizedBox(height: 8),
            SelectableText(
              bill.url,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 11,
                height: 1.35,
                color: AppColors.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One issue line in browse mode — label plus where it lands them, with the
/// same roll-call footnote the side-by-side rows carry.
class _IssuePositionRow extends StatelessWidget {
  const _IssuePositionRow({
    required this.label,
    required this.score,
    this.rollcallN,
  });

  final String label;
  final double score;
  final int? rollcallN;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.sheet,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.manrope(fontWeight: FontWeight.w700),
                  ),
                  if (rollcallN != null &&
                      rollcallN! >= Scoring.rollcallMinVotes) ...[
                    const SizedBox(height: 2),
                    Text(
                      '$rollcallN floor votes in the SII blend',
                      style: GoogleFonts.ibmPlexMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              Scoring.formatScore(score),
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: score < 0 ? AppColors.liberal : AppColors.conservative,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
