import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Flips an issue row to the strongest case for the opposite stance.
class SteelManCard extends StatefulWidget {
  const SteelManCard({
    super.key,
    required this.issueLabel,
    required this.scoreLabel,
    required this.score,
    required this.argument,
  });

  final String issueLabel;
  final String scoreLabel;
  final double score;
  final String argument;

  @override
  State<SteelManCard> createState() => _SteelManCardState();
}

class _SteelManCardState extends State<SteelManCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flip;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_showBack) {
      await _flip.reverse();
      if (mounted) setState(() => _showBack = false);
    } else {
      setState(() => _showBack = true);
      await _flip.forward();
    }
  }

  Color get _scoreColor {
    if (widget.score < -4) return AppColors.liberal;
    if (widget.score > 4) return AppColors.conservative;
    return AppColors.center;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flip,
      builder: (context, _) {
        final t = Curves.easeInOutCubic.transform(_flip.value);
        final angle = t * math.pi;
        final showBack = angle > math.pi / 2;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(angle),
          child: showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _back(),
                )
              : _front(),
        );
      },
    );
  }

  Widget _front() {
    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.issueLabel,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(
                widget.scoreLabel,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _scoreColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.flip_rounded,
                size: 16,
                color: AppColors.accent.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 6),
              Text(
                'Steel-man the opposite',
                style: GoogleFonts.ibmPlexMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _back() {
    return _shell(
      tint: AppColors.parchment,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEEL MAN',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            widget.argument,
            style: GoogleFonts.manrope(
              fontSize: 13,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Back to your score',
            style: GoogleFonts.ibmPlexMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  /// The whole card is the target — a 16pt text link was never a tap target,
  /// and the natural gesture on a card like this is to tap the card.
  Widget _shell({required Widget child, Color? tint}) {
    return Material(
      color: tint ?? AppColors.sheet,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.ink.withValues(alpha: tint == null ? 0.06 : 0.1),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
