import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/app_data.dart';
import '../models/scoring.dart';
import '../theme/app_theme.dart';

/// Bypass the quiz: place yourself on the axis by hand, optionally pillar by
/// pillar. Produces the same [SpectrumProfile] shape a quiz run produces, so
/// matching, sharing, and friend compare all keep working.
class ManualProfileScreen extends StatefulWidget {
  const ManualProfileScreen({
    super.key,
    required this.data,
    this.initialProfile,
  });

  final AppData data;

  /// Seeds the sliders from a saved run so this doubles as an edit screen.
  final SpectrumProfile? initialProfile;

  @override
  State<ManualProfileScreen> createState() => _ManualProfileScreenState();
}

class _ManualProfileScreenState extends State<ManualProfileScreen> {
  static const _presets = <String, double>{
    'Very liberal': -85,
    'Liberal': -55,
    'Lean liberal': -25,
    'Centrist': 0,
    'Lean conservative': 25,
    'Conservative': 55,
    'Very conservative': 85,
  };

  late double _overall;
  late Map<String, double> _pillars;

  /// Pillars still tracking the overall slider. Moving one drops it out.
  late Set<String> _linked;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialProfile;
    _overall = _round(seed?.axisScore ?? 0);
    _pillars = {
      for (final p in widget.data.pillars)
        p.id: _round(seed?.pillarScores[p.id] ?? _overall),
    };
    _linked = {
      for (final p in widget.data.pillars)
        if (seed == null || (_pillars[p.id]! - _overall).abs() < 0.5) p.id,
    };
  }

  static double _round(double value) =>
      (value / 5).roundToDouble().clamp(-20.0, 20.0) * 5;

  bool get _split => _linked.length != widget.data.pillars.length;

  /// What the pillar scores actually average out to. Once the pillars are set
  /// by hand the overall slider no longer speaks for them, so the card shows
  /// this instead — the same number [_save] writes.
  double get _derivedAxis => Scoring.profileFromPillarScores(
    pillarScores: _pillars,
    issues: widget.data.issues,
  ).axisScore;

  void _setOverall(double value) {
    setState(() {
      _overall = value;
      for (final id in _linked) {
        _pillars[id] = value;
      }
    });
  }

  void _setPillar(String id, double value) {
    setState(() {
      _linked.remove(id);
      _pillars[id] = value;
    });
  }

  void _relink() {
    setState(() {
      _linked = {for (final p in widget.data.pillars) p.id};
      for (final id in _linked) {
        _pillars[id] = _overall;
      }
    });
  }

  void _save() {
    final profile = Scoring.profileFromPillarScores(
      pillarScores: _pillars,
      issues: widget.data.issues,
    );
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set your level')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(
            'Skip the quiz and place yourself. Score the pillars you care '
            'about, or set one lean for all five. Matching uses the same '
            'scale, so your ballot, pillars, and friend compare all work the '
            'same way.',
            style: GoogleFonts.manrope(
              fontSize: 14,
              height: 1.45,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Score each pillar',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Move any pillar to score it yourself. Anything you leave alone '
            'follows the overall lean below.',
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 12),
          for (final pillar in widget.data.pillars) ...[
            _PillarSlider(
              label: pillar.label,
              description: pillar.description,
              score: _pillars[pillar.id] ?? _overall,
              linked: _linked.contains(pillar.id),
              onChanged: (value) => _setPillar(pillar.id, value),
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 18),
          _AxisCard(
            score: _split ? _derivedAxis : _overall,
            split: _split,
            onChanged: _setOverall,
            onRelink: _relink,
          ),
          const SizedBox(height: 16),
          Text(
            'Quick picks',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sets all five pillars to one lean.',
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _presets.entries)
                ChoiceChip(
                  label: Text(entry.key),
                  labelStyle: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: !_split && _overall == entry.value
                        ? AppColors.sheet
                        : AppColors.ink,
                  ),
                  backgroundColor: AppColors.sheet,
                  selectedColor: AppColors.ink,
                  showCheckmark: false,
                  side: BorderSide(
                    color: AppColors.ink.withValues(alpha: 0.12),
                  ),
                  selected: !_split && _overall == entry.value,
                  onSelected: (_) {
                    _setOverall(entry.value);
                    _relink();
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'A hand-set level is a placement, not a measurement — the quiz also '
            'weighs how much each issue matters to you. Your saved runs stay in '
            'your history either way.',
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.45,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _save,
            child: const Text('Use this level'),
          ),
        ),
      ),
    );
  }
}

Color _sideColor(double score) {
  if (score.abs() < 8) return AppColors.center;
  return score < 0 ? AppColors.liberal : AppColors.conservative;
}

class _AxisCard extends StatelessWidget {
  const _AxisCard({
    required this.score,
    required this.split,
    required this.onChanged,
    required this.onRelink,
  });

  final double score;

  /// At least one pillar is scored by hand, so [score] is the average of the
  /// pillars rather than a value this card sets.
  final bool split;
  final ValueChanged<double> onChanged;
  final VoidCallback onRelink;

  @override
  Widget build(BuildContext context) {
    final color = _sideColor(score);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERALL LEAN',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            Scoring.labelForScore(score),
            style: GoogleFonts.manrope(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            Scoring.formatScore(score),
            style: GoogleFonts.ibmPlexMono(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (split) ...[
            Text(
              'Averaged from the pillars above — this is what gets saved.',
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.4,
                color: AppColors.inkMuted,
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onRelink,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Set one lean for all five'),
              ),
            ),
            const SizedBox(height: 4),
          ] else ...[
            _AxisSlider(score: score, color: color, onChanged: onChanged),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Liberal 100',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
                ),
                Text(
                  'Conservative 100',
                  style: GoogleFonts.ibmPlexMono(
                    fontSize: 11,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AxisSlider extends StatelessWidget {
  const _AxisSlider({
    required this.score,
    required this.color,
    required this.onChanged,
    this.semanticLabel,
  });

  final double score;
  final Color color;
  final ValueChanged<double> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 5,
        activeTrackColor: color,
        inactiveTrackColor: AppColors.ink.withValues(alpha: 0.10),
        thumbColor: color,
        overlayColor: color.withValues(alpha: 0.12),
        valueIndicatorColor: AppColors.ink,
      ),
      child: Slider(
        value: score,
        min: -100,
        max: 100,
        divisions: 40,
        label: Scoring.formatScore(score),
        semanticFormatterCallback: (value) =>
            '${semanticLabel == null ? '' : '$semanticLabel: '}'
            '${Scoring.formatScore(value)}',
        onChanged: onChanged,
      ),
    );
  }
}

class _PillarSlider extends StatelessWidget {
  const _PillarSlider({
    required this.label,
    required this.description,
    required this.score,
    required this.linked,
    required this.onChanged,
  });

  final String label;
  final String description;
  final double score;
  final bool linked;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                Scoring.formatScore(score),
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: linked ? AppColors.inkMuted : _sideColor(score),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: GoogleFonts.manrope(
              fontSize: 12,
              height: 1.35,
              color: AppColors.inkMuted,
            ),
          ),
          _AxisSlider(
            score: score,
            color: _sideColor(score),
            semanticLabel: label,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
