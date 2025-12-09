import 'package:flutter/material.dart';

/// Custom painter for cumulative score line chart
class CumulativeScoreLinePainter extends CustomPainter {
  final List<Map<String, dynamic>> data;
  final double minScore;
  final double maxScore;
  final double scoreRange;
  final Color color;

  CumulativeScoreLinePainter({
    required this.data,
    required this.minScore,
    required this.maxScore,
    required this.scoreRange,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final points = <Offset>[];
    final denominator = data.length > 1 ? data.length - 1 : 1;

    for (int i = 0; i < data.length; i++) {
      final score = data[i]['score'] as double;
      final x = (i / denominator) * size.width;
      final y = size.height -
          ((score - minScore) / (scoreRange > 0 ? scoreRange : 1)) *
              size.height;
      points.add(Offset(x, y));
    }

    // Draw line
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }

    // Draw points
    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
