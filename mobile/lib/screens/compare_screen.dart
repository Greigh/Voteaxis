import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_data.dart';
import '../models/scoring.dart';
import '../services/result_store.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import '../widgets/rank_list.dart';
import '../widgets/spectrum_bar.dart';
import 'politician_detail_screen.dart';

class CompareScreen extends StatefulWidget {
  const CompareScreen({
    super.key,
    required this.baseProfile,
    required this.data,
  });

  final SpectrumProfile baseProfile;
  final AppData data;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  List<QuizRun> _runs = [];
  QuizRun? _compareRun;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    final runs = await ResultStore().loadRuns();
    if (!mounted) return;
    setState(() {
      _runs = runs;
      final earlier = _earlierRuns;
      _compareRun = earlier.isEmpty ? null : earlier.first;
    });
  }

  /// Everything but the latest run, hand-set placements first. A placement the
  /// user set themselves is the one they came here to check against, so it
  /// leads the list; the rest stay newest to oldest.
  List<QuizRun> get _earlierRuns {
    final rest = _runs.skip(1).toList();
    final handSet = rest.where((run) => run.isHandSet);
    final scored = rest.where((run) => !run.isHandSet);
    return [...handSet, ...scored];
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.baseProfile;
    final earlier = _compareRun?.toProfile();

    return Scaffold(
      appBar: AppBar(title: const Text('Compare saved runs')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            'Importance is set in the quiz, not after. Retake to change what '
            'matters to you — or compare two saved runs to see how your '
            'placement moved.',
            style: GoogleFonts.manrope(
              fontSize: 13.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          if (_runs.length < 2) ...[
            const SizedBox(height: 20),
            const EmptyState(
              icon: Icons.history_toggle_off_rounded,
              title: 'Only one run so far',
              body:
                  'Take the quiz again later and this page will show how '
                  'your placement moved between the two.',
            ),
          ] else ...[
            const SizedBox(height: 22),
            const SectionHeading('Pick a run to compare'),
            DropdownButtonFormField<int>(
              key: ValueKey(_compareRun?.timestampMs ?? 0),
              initialValue: _compareRun?.timestampMs,
              decoration: const InputDecoration(
                labelText: 'Earlier run',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final run in _earlierRuns)
                  DropdownMenuItem(
                    value: run.timestampMs,
                    child: Text(
                      _formatRun(run),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (ms) {
                setState(() {
                  _compareRun = null;
                  for (final run in _runs) {
                    if (run.timestampMs == ms) {
                      _compareRun = run;
                      break;
                    }
                  }
                });
              },
            ),
            if (earlier != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Latest',
                      value: Scoring.formatScore(base.axisScore),
                      caption: Scoring.labelForScore(base.axisScore),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatTile(
                      label: 'Earlier',
                      value: Scoring.formatScore(earlier.axisScore),
                      caption: Scoring.labelForScore(earlier.axisScore),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionHeading('How your place moved'),
              const SizedBox(height: 4),
              Text(
                'Oldest run on the left of the line, latest as the pin.',
                style: TextStyle(
                  color: AppColors.ink.withValues(alpha: 0.65),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              SpectrumBar(
                userScore: base.axisScore,
                trail: [
                  for (final run in _runs.reversed)
                    if (run.timestampMs != _runs.first.timestampMs)
                      run.axisScore,
                ],
                markers: const [],
                height: 84,
              ),
              const SizedBox(height: 20),
              SectionHeading('Closest matches on the earlier run'),
              const SizedBox(height: 10),
              RankList(
                matches: Scoring.rankPoliticians(
                  user: earlier,
                  politicians: widget.data.politicians,
                  issues: widget.data.issues,
                ).take(8).toList(),
                data: widget.data,
                onTap: (politician) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PoliticianDetailScreen(
                        politician: politician,
                        userProfile: earlier,
                        data: widget.data,
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatRun(QuizRun run) {
    final dt = DateTime.fromMillisecondsSinceEpoch(run.timestampMs);
    final stamp =
        '${dt.month}/${dt.day}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    final label = run.label;
    return label == null
        ? '$stamp · ${Scoring.formatScore(run.axisScore)}'
        : '$stamp · ${Scoring.formatScore(run.axisScore)} · $label';
  }
}
