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

    // Padding constants to prevent graph from touching edges
    const double topPadding = 8.0;
    const double rightPadding = 8.0;
    const double bottomPadding = 4.0;
    const double leftPadding = 0.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final points = <Offset>[];
    final denominator = data.length > 1 ? data.length - 1 : 1;
    const double pointRadius = 3.0;
    
    // Calculate available drawing area after padding
    // Account for point radius on both sides to ensure first and last points are fully visible
    final availableWidth = size.width - leftPadding - rightPadding - (2 * pointRadius);
    final availableHeight = size.height - topPadding - bottomPadding;

    for (int i = 0; i < data.length; i++) {
      final score = data[i]['score'] as double;
      // Position points so both first and last point circles fit within bounds
      // First point at: leftPadding + pointRadius
      // Last point at: size.width - rightPadding - pointRadius
      final x = leftPadding + pointRadius + (i / denominator) * availableWidth;
      final y = topPadding + availableHeight -
          ((score - minScore) / (scoreRange > 0 ? scoreRange : 1)) *
              availableHeight;
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
