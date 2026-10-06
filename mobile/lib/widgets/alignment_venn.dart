import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/scoring.dart';
import '../theme/app_theme.dart';
import 'ui_kit.dart';

class AlignmentVenn extends StatelessWidget {
  const AlignmentVenn({
    super.key,
    required this.venn,
    required this.issueLabels,
    required this.friendLabel,
  });

  final CivicVenn venn;
  final Map<String, String> issueLabels;
  final String friendLabel;

  String _name(IssueOverlap o) => issueLabels[o.issueId] ?? o.issueId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading('Where you overlap'),
        const SizedBox(height: 6),
        Text(
          'Aligned issues sit in the middle. The sides are where one of you '
          'is clearly more liberal than the other.',
          style: GoogleFonts.manrope(
            fontSize: 13,
            height: 1.4,
            color: AppColors.inkMuted,
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          label:
              'Alignment chart: ${venn.youMoreLiberal.length} issues where you '
              'are more liberal, ${venn.aligned.length} where you align, '
              '${venn.theyMoreLiberal.length} where $friendLabel is more '
              'liberal.',
          child: SizedBox(
            height: 168,
            child: CustomPaint(
              painter: _VennPainter(
                left: venn.youMoreLiberal.length,
                mid: venn.aligned.length,
                right: venn.theyMoreLiberal.length,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'You more liberal',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              'Align',
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Expanded(
              child: Text(
                '$friendLabel more liberal',
                textAlign: TextAlign.right,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _IssueColumn(
          title: 'Align',
          empty: 'No close matches on shared issues.',
          items: [for (final o in venn.aligned) _name(o)],
        ),
        const SizedBox(height: 12),
        _IssueColumn(
          title: 'You more liberal',
          empty: 'No hard left-of-them gaps.',
          items: [for (final o in venn.youMoreLiberal) _name(o)],
        ),
        const SizedBox(height: 12),
        _IssueColumn(
          title: '$friendLabel more liberal',
          empty: 'No hard left-of-you gaps.',
          items: [for (final o in venn.theyMoreLiberal) _name(o)],
        ),
      ],
    );
  }
}

class _IssueColumn extends StatelessWidget {
  const _IssueColumn({
    required this.title,
    required this.empty,
    required this.items,
  });

  final String title;
  final String empty;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.sheet,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.ink.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.ibmPlexMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.inkMuted,
            ),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(
              empty,
              style: GoogleFonts.manrope(
                fontSize: 13,
                color: AppColors.inkMuted,
              ),
            )
          else
            Text(
              items.join(' · '),
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}

class _VennPainter extends CustomPainter {
  const _VennPainter({
    required this.left,
    required this.mid,
    required this.right,
  });

  final int left;
  final int mid;
  final int right;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.height * 0.42, size.width * 0.28);
    final cy = size.height * 0.52;
    final leftC = Offset(size.width * 0.38, cy);
    final rightC = Offset(size.width * 0.62, cy);

    final youFill = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.10)
      ..style = PaintingStyle.fill;
    final themFill = Paint()
      ..color = AppColors.accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    canvas.drawCircle(leftC, r, youFill);
    canvas.drawCircle(rightC, r, themFill);
    canvas.drawCircle(leftC, r, stroke);
    canvas.drawCircle(rightC, r, stroke);

    final overlap = Paint()
      ..color = AppColors.ink.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final overlapPath = Path()
      ..addOval(Rect.fromCircle(center: leftC, radius: r));
    final rightPath = Path()
      ..addOval(Rect.fromCircle(center: rightC, radius: r));
    canvas.drawPath(
      Path.combine(PathOperation.intersect, overlapPath, rightPath),
      overlap,
    );

    void label(Offset at, String text, {Color? color}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color ?? AppColors.ink,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label(Offset(leftC.dx - r * 0.45, cy), '$left');
    label(Offset(size.width / 2, cy), '$mid');
    label(
      Offset(rightC.dx + r * 0.45, cy),
      '$right',
      color: const Color(0xFF6B5420),
    );
  }

  @override
  bool shouldRepaint(covariant _VennPainter oldDelegate) {
    return oldDelegate.left != left ||
        oldDelegate.mid != mid ||
        oldDelegate.right != right;
  }
}
