import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Soft cool-mist field with liberal / conservative washes.
class MistBackdrop extends StatelessWidget {
  const MistBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEEF2F8), AppColors.paper, Color(0xFFF3F0F0)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned(
            left: -80,
            top: -60,
            child: _Wash(color: AppColors.liberal, size: 280, opacity: 0.10),
          ),
          const Positioned(
            right: -70,
            top: 40,
            child: _Wash(
              color: AppColors.conservative,
              size: 260,
              opacity: 0.09,
            ),
          ),
          const Positioned(
            right: -40,
            bottom: -40,
            child: _Wash(color: AppColors.liberal, size: 180, opacity: 0.05),
          ),
          child,
        ],
      ),
    );
  }
}

class _Wash extends StatelessWidget {
  const _Wash({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Animated spectrum rail — the product's visual signature.
class SpectrumHeroRail extends StatefulWidget {
  const SpectrumHeroRail({
    super.key,
    this.height = 72,
    this.markerScore = -18,
    this.animate = true,
  });

  final double height;
  final double markerScore;
  final bool animate;

  @override
  State<SpectrumHeroRail> createState() => _SpectrumHeroRailState();
}

class _SpectrumHeroRailState extends State<SpectrumHeroRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    );
    if (widget.animate) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final wobble = widget.animate
            ? math.sin(_controller.value * math.pi) * 8
            : 0.0;
        return CustomPaint(
          painter: _HeroRailPainter(markerScore: widget.markerScore + wobble),
          child: SizedBox(height: widget.height, width: double.infinity),
        );
      },
    );
  }
}

class _HeroRailPainter extends CustomPainter {
  _HeroRailPainter({required this.markerScore});

  final double markerScore;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height * 0.55;
    final trackH = 14.0;
    final pad = 4.0;
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad, cy - trackH / 2, size.width - pad * 2, trackH),
      Radius.circular(trackH),
    );

    final shader = const LinearGradient(
      colors: [
        AppColors.liberal,
        Color(0xFF6B8FE8),
        Color(0xFFE8EEF6),
        Color(0xFFE07A6A),
        AppColors.conservative,
      ],
    ).createShader(track.outerRect);

    canvas.drawRRect(
      track.inflate(1.5),
      Paint()..color = AppColors.ink.withValues(alpha: 0.06),
    );
    canvas.drawRRect(track, Paint()..shader = shader);

    final t = ((markerScore + 100) / 200).clamp(0.0, 1.0);
    final x = pad + trackH / 2 + t * (size.width - pad * 2 - trackH);

    // Soft glow under marker
    canvas.drawCircle(
      Offset(x, cy),
      16,
      Paint()..color = AppColors.ink.withValues(alpha: 0.08),
    );
    canvas.drawCircle(Offset(x, cy), 11, Paint()..color = AppColors.sheet);
    canvas.drawCircle(
      Offset(x, cy),
      11,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = AppColors.ink,
    );
    canvas.drawCircle(Offset(x, cy), 4.5, Paint()..color = AppColors.ink);
  }

  @override
  bool shouldRepaint(covariant _HeroRailPainter oldDelegate) =>
      oldDelegate.markerScore != markerScore;
}
