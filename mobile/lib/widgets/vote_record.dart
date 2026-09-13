import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/politician.dart';
import '../models/scoring.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';
import 'spectrum_bar.dart';

class VoteRecord extends StatefulWidget {
  const VoteRecord({
    super.key,
    required this.politician,
    required this.userScore,
    required this.issueLabels,
    required this.lifetimeAxis,
    this.lifetimeDistance,
  });

  final Politician politician;
  final double userScore;
  final Map<String, String> issueLabels;
  final double lifetimeAxis;
  final double? lifetimeDistance;

  @override
  State<VoteRecord> createState() => _VoteRecordState();
}

class _VoteRecordState extends State<VoteRecord> {
  late int _index;

  List<RollcallSession> get _sessions => widget.politician.rollcallSessions;

  @override
  void initState() {
    super.initState();
    _index = _sessions.isEmpty ? 0 : _sessions.length - 1;
  }

  @override
  void didUpdateWidget(covariant VoteRecord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.politician.id != widget.politician.id) {
      _index = _sessions.isEmpty ? 0 : _sessions.length - 1;
    }
  }

  void _select(int index) {
    setState(() => _index = index.clamp(0, _sessions.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.politician.hasVoteRecord) {
      return SpectrumBar(
        userScore: widget.userScore,
        markers: [
          SpectrumMarker(
            id: widget.politician.id,
            score: widget.lifetimeAxis,
            distance: widget.lifetimeDistance,
          ),
        ],
        highlightId: widget.politician.id,
      );
    }

    final session = _sessions[_index];
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading('Vote record'),
        const SizedBox(height: 4),
        Text(
          'Floor votes by Congress. Drag to see how their axis moved. This does not change their match score.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            height: 1.4,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 12),
        SpectrumBar(
          userScore: widget.userScore,
          path: [for (final s in _sessions) s.axisScore],
          markers: [
            SpectrumMarker(
              id: widget.politician.id,
              score: session.axisScore,
              distance: widget.lifetimeDistance,
            ),
          ],
          highlightId: widget.politician.id,
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            activeTrackColor: AppColors.navy,
            inactiveTrackColor: AppColors.ink.withValues(alpha: 0.12),
            thumbColor: AppColors.accent,
            overlayColor: AppColors.accent.withValues(alpha: 0.16),
            tickMarkShape: SliderTickMarkShape.noTickMark,
          ),
          child: Slider(
            value: _index.toDouble(),
            min: 0,
            max: (_sessions.length - 1).toDouble(),
            divisions: _sessions.length - 1,
            label: session.label,
            onChanged: (value) => _select(value.round()),
          ),
        ),
        Row(
          children: [
            for (var i = 0; i < _sessions.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _select(i),
                  child: AnimatedOpacity(
                    duration: reduce
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    opacity: i == _index ? 1 : 0.45,
                    // A two-line label is 33pt tall on its own — pad it out so
                    // the year tabs clear the 48dp minimum.
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 48),
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _sessions[i].label.replaceAll(' Congress', ''),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.ibmPlexMono(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                              color: i == _index
                                  ? AppColors.navy
                                  : AppColors.inkMuted,
                            ),
                          ),
                          Text(
                            '${_sessions[i].year}',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              fontWeight: i == _index
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          '${session.label} · ${session.yearSpan}',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          '${Scoring.formatScore(session.axisScore)} on the floor that session',
          style: GoogleFonts.manrope(fontSize: 13, color: AppColors.inkMuted),
        ),
        if (session.moves.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'VOTES THAT PULLED THIS SESSION',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          for (final move in session.moves)
            _MoveCard(
              move: move,
              issueLabel: widget.issueLabels[move.issueId] ?? move.issueId,
            ),
        ],
      ],
    );
  }
}

class _MoveCard extends StatelessWidget {
  const _MoveCard({required this.move, required this.issueLabel});

  final RollcallMove move;
  final String issueLabel;

  @override
  Widget build(BuildContext context) {
    final pull = move.pulledConservative ? 'conservative' : 'liberal';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (move.cast.isNotEmpty) move.cast,
                    if (move.bill != null) 'on ${move.bill}',
                    if (move.desc != null) '— ${move.desc}',
                  ].join(' '),
                  style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  '$issueLabel · pulled $pull${move.date != null ? ' · ${move.date}' : ''}',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.sheet,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                [
                  if (move.cast.isNotEmpty) move.cast,
                  if (move.bill != null) move.bill,
                ].join(' · '),
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (move.question != null) ...[
                const SizedBox(height: 6),
                Text(move.question!, style: GoogleFonts.manrope(height: 1.4)),
              ],
              if (move.desc != null) ...[
                const SizedBox(height: 6),
                Text(
                  move.desc!,
                  style: GoogleFonts.manrope(
                    height: 1.4,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                [
                  issueLabel,
                  if (move.chamber != null) move.chamber,
                  if (move.date != null) move.date,
                  move.pulledConservative
                      ? 'Pulled conservative'
                      : 'Pulled liberal',
                ].join(' · '),
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  color: AppColors.inkMuted,
                ),
              ),
              if (move.url != null) ...[
                const SizedBox(height: 10),
                SelectableText(
                  move.url!,
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
