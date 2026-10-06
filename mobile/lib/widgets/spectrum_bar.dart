import 'package:flutter/material.dart';

import '../models/scoring.dart';
import '../theme/app_theme.dart';

class SpectrumMarker {
  const SpectrumMarker({required this.id, required this.score, this.distance});

  final String id;
  final double score;

  /// Mean-absolute issue distance from the user, if known. Used to fade dots.
  final double? distance;
}

class SpectrumBar extends StatefulWidget {
  const SpectrumBar({
    super.key,
    this.userScore,
    required this.markers,
    this.height = 96,
    this.highlightId,
    this.trail = const [],
    this.path = const [],
    this.otherScore,
  });

  /// The "you" pin. Null in browse mode — the bar shows the roster without
  /// pretending the viewer has a placement.
  final double? userScore;
  final List<SpectrumMarker> markers;
  final double height;
  final String? highlightId;

  /// Older axis scores, oldest first. Drawn as a polyline into the current pin.
  final List<double> trail;

  /// Scores to connect in order (vote-record migration). Does not attach to the user pin.
  final List<double> path;

  /// Optional second pin (friend compare).
  final double? otherScore;

  @override
  State<SpectrumBar> createState() => _SpectrumBarState();
}

class _SpectrumBarState extends State<SpectrumBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _t;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _t = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _play();
    }
  }

  @override
  void didUpdateWidget(covariant SpectrumBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userScore != widget.userScore ||
        oldWidget.highlightId != widget.highlightId ||
        oldWidget.otherScore != widget.otherScore ||
        !_sameScores(oldWidget.markers, widget.markers) ||
        oldWidget.path != widget.path) {
      _play();
    }
  }

  bool _sameScores(List<SpectrumMarker> a, List<SpectrumMarker> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].score != b[i].score) return false;
    }
    return true;
  }

  void _play() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    if (reduce) {
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// One spoken summary of the chart: axis bounds, the user's pin, the
  /// friend's pin, and how many roster dots are plotted. The painted bar and
  /// the "Liberal 100 · 0 · Conservative 100" scale row are excluded so the
  /// reader hears this once instead of as fragments.
  String _describe() {
    final buffer = StringBuffer(
      'Political spectrum, from Liberal 100 to Conservative 100.',
    );
    if (widget.userScore != null) {
      final score = widget.userScore!.round();
      buffer.write(
        ' Your position: ${Scoring.labelForScore(widget.userScore!)}, '
        '$score.',
      );
    }
    if (widget.otherScore != null) {
      final score = widget.otherScore!.round();
      buffer.write(
        ' Friend position: ${Scoring.labelForScore(widget.otherScore!)}, '
        '$score.',
      );
    }
    if (widget.markers.isNotEmpty) {
      buffer.write(' ${widget.markers.length} politicians plotted.');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _describe(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: widget.height,
              child: AnimatedBuilder(
                animation: _t,
                builder: (context, _) {
                  return CustomPaint(
                    painter: _SpectrumPainter(
                      userScore: widget.userScore,
                      markers: widget.markers,
                      highlightId: widget.highlightId,
                      trail: widget.trail,
                      path: widget.path,
                      otherScore: widget.otherScore,
                      t: _t.value,
                    ),
                    child: const SizedBox.expand(),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Liberal 100',
                  style: TextStyle(
                    color: AppColors.liberal,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '0',
                  style: TextStyle(
                    color: AppColors.center,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Conservative 100',
                  style: TextStyle(
                    color: AppColors.conservative,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
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

class _SpectrumPainter extends CustomPainter {
  _SpectrumPainter({
    required this.userScore,
    required this.markers,
    required this.t,
    this.highlightId,
    this.trail = const [],
    this.path = const [],
    this.otherScore,
  });

  final double? userScore;
  final List<SpectrumMarker> markers;
  final String? highlightId;
  final List<double> trail;
  final List<double> path;
  final double? otherScore;
  final double t;

  double _xFor(double score, double width) {
    const pad = 12.0;
    final u = (score + 100) / 200;
    return pad + u * (width - pad * 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final trackY = size.height * 0.62;
    final trackRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(8, trackY - 6, size.width - 16, 12),
      const Radius.circular(8),
    );

    final gradient = LinearGradient(
      colors: [
        AppColors.liberal,
        AppColors.liberal.withValues(alpha: 0.55),
        AppColors.parchment,
        AppColors.conservative.withValues(alpha: 0.55),
        AppColors.conservative,
      ],
    );

    final paint = Paint()..shader = gradient.createShader(trackRect.outerRect);
    canvas.drawRRect(trackRect, paint);

    final centerX = _xFor(0, size.width);
    canvas.drawLine(
      Offset(centerX, trackY - 14),
      Offset(centerX, trackY + 14),
      Paint()
        ..color = AppColors.ink.withValues(alpha: 0.35)
        ..strokeWidth = 1.5,
    );

    void drawPath(List<double> scores, {required bool includeTip}) {
      if (scores.isEmpty) return;
      final line = Path()..moveTo(_xFor(scores.first, size.width), trackY);
      for (var i = 1; i < scores.length; i++) {
        line.lineTo(_xFor(scores[i], size.width), trackY);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.navy.withValues(alpha: 0.28 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
      final dots = includeTip ? scores.sublist(0, scores.length - 1) : scores;
      for (var i = 0; i < dots.length; i++) {
        final x = _xFor(dots[i], size.width);
        final age = (i + 1) / (dots.length + 1);
        canvas.drawCircle(
          Offset(x, trackY),
          3.2,
          Paint()
            ..color = AppColors.navy.withValues(alpha: 0.2 + 0.35 * age * t),
        );
      }
    }

    if (trail.isNotEmpty) {
      drawPath(
        userScore == null ? trail : [...trail, userScore!],
        includeTip: userScore != null,
      );
    }
    if (path.length >= 2) {
      drawPath(path, includeTip: false);
    }

    for (final m in markers) {
      final x = _xFor(m.score, size.width);
      final highlighted = m.id == highlightId;
      final closeness = m.distance == null
          ? 0.45
          : (1.0 - (m.distance! / 200.0).clamp(0.0, 1.0));
      final alpha = highlighted ? 0.95 * t : (0.14 + closeness * 0.5) * t;
      canvas.drawCircle(
        Offset(x, trackY),
        highlighted ? 6.5 : 3.5,
        Paint()
          ..color = highlighted
              ? AppColors.accent.withValues(alpha: alpha)
              : AppColors.ink.withValues(alpha: alpha),
      );
    }

    if (userScore != null) {
      final ux = _xFor(userScore!, size.width);
      final drop = (1 - t) * 22;
      final pinPath = Path()
        ..moveTo(ux, trackY - 28 - drop)
        ..lineTo(ux - 8, trackY - 12 - drop)
        ..lineTo(ux + 8, trackY - 12 - drop)
        ..close();
      canvas.drawPath(
        pinPath,
        Paint()..color = AppColors.navy.withValues(alpha: 0.35 + 0.65 * t),
      );
      canvas.drawCircle(
        Offset(ux, trackY),
        7,
        Paint()..color = AppColors.navy.withValues(alpha: 0.35 + 0.65 * t),
      );
      canvas.drawCircle(
        Offset(ux, trackY),
        3.5,
        Paint()..color = AppColors.cream.withValues(alpha: t),
      );
    }

    if (otherScore != null) {
      final ox = _xFor(otherScore!, size.width);
      final friendPath = Path()
        ..moveTo(ox, trackY + 28)
        ..lineTo(ox - 8, trackY + 12)
        ..lineTo(ox + 8, trackY + 12)
        ..close();
      canvas.drawPath(
        friendPath,
        Paint()..color = AppColors.accent.withValues(alpha: 0.35 + 0.65 * t),
      );
      canvas.drawCircle(
        Offset(ox, trackY),
        6,
        Paint()..color = AppColors.accent.withValues(alpha: 0.35 + 0.65 * t),
      );
      canvas.drawCircle(
        Offset(ox, trackY),
        2.8,
        Paint()..color = AppColors.cream.withValues(alpha: t),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) {
    return oldDelegate.userScore != userScore ||
        oldDelegate.highlightId != highlightId ||
        oldDelegate.markers != markers ||
        oldDelegate.trail != trail ||
        oldDelegate.path != path ||
        oldDelegate.otherScore != otherScore ||
        oldDelegate.t != t;
  }
}
