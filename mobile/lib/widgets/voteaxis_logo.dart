import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Brand mark: modern ballot box with blue/red vote check.
class VoteaxisMark extends StatelessWidget {
  const VoteaxisMark({super.key, this.size = 88, this.showAsset = true});

  final double size;
  final bool showAsset;

  @override
  Widget build(BuildContext context) {
    if (showAsset) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset(
          'assets/brand/voteaxis-mark.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              _PaintedMark(size: size),
        ),
      );
    }
    return _PaintedMark(size: size);
  }
}

class _PaintedMark extends StatelessWidget {
  const _PaintedMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _BallotBoxMarkPainter()),
    );
  }
}

class _BallotBoxMarkPainter extends CustomPainter {
  const _BallotBoxMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bg = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.width * 0.22),
    );
    canvas.drawRRect(bg, Paint()..color = AppColors.mist);

    final boxW = size.width * 0.52;
    final boxH = size.height * 0.46;
    final left = (size.width - boxW) / 2;
    final top = size.height * 0.34;
    final radius = size.width * 0.08;

    // Lid / hopper
    final lid = RRect.fromRectAndCorners(
      Rect.fromLTWH(
        left + boxW * 0.06,
        top - size.height * 0.07,
        boxW * 0.88,
        size.height * 0.1,
      ),
      topLeft: Radius.circular(radius * 0.7),
      topRight: Radius.circular(radius * 0.7),
    );
    canvas.drawRRect(lid, Paint()..color = AppColors.ink);

    // Box body
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, boxW, boxH),
      Radius.circular(radius),
    );
    canvas.drawRRect(body, Paint()..color = AppColors.ink);

    // Slot
    final slotY = top - size.height * 0.02;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(size.width / 2, slotY),
          width: boxW * 0.42,
          height: size.height * 0.012,
        ),
        Radius.circular(size.height * 0.006),
      ),
      Paint()..color = AppColors.sheet,
    );

    // Ballot slip
    final slipW = boxW * 0.28;
    final slip = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (size.width - slipW) / 2,
        top - size.height * 0.22,
        slipW,
        size.height * 0.2,
      ),
      Radius.circular(size.width * 0.03),
    );
    canvas.drawRRect(slip, Paint()..color = AppColors.sheet);

    // Blue / red check
    final cx = size.width * 0.46;
    final cy = top + boxH * 0.58;
    final stroke = size.width * 0.085;
    final paintBlue = Paint()
      ..color = AppColors.liberal
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final paintRed = Paint()
      ..color = AppColors.conservative
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(cx - size.width * 0.08, cy - size.height * 0.02),
      Offset(cx, cy + size.height * 0.06),
      paintBlue,
    );
    canvas.drawLine(
      Offset(cx, cy + size.height * 0.06),
      Offset(cx + size.width * 0.16, cy - size.height * 0.12),
      paintRed,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class VoteaxisWordmark extends StatelessWidget {
  const VoteaxisWordmark({super.key, this.fontSize = 40, this.color});

  final double fontSize;

  /// Null tracks the active palette — dark mode recolors the wordmark.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Voteaxis',
      style: GoogleFonts.manrope(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.4,
        height: 1,
        color: color ?? AppColors.ink,
      ),
    );
  }
}

/// Logo mark + wordmark stacked (or row for compact headers).
class VoteaxisBrandLockup extends StatelessWidget {
  const VoteaxisBrandLockup({
    super.key,
    this.markSize = 72,
    this.fontSize = 36,
    this.compact = false,
  });

  final double markSize;
  final double fontSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VoteaxisMark(size: markSize),
          SizedBox(width: markSize * 0.18),
          VoteaxisWordmark(fontSize: fontSize),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        VoteaxisMark(size: markSize),
        SizedBox(height: markSize * 0.22),
        VoteaxisWordmark(fontSize: fontSize),
      ],
    );
  }
}
