import 'package:flutter/material.dart';

/// Custom painter for cumulative score line chart
/// used in both queue page and progress page
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
    final availableWidth =
        size.width - leftPadding - rightPadding - (2 * pointRadius);
    final availableHeight = size.height - topPadding - bottomPadding;

    for (int i = 0; i < data.length; i++) {
      final score = data[i]['score'] as double;
      // Position points so both first and last point circles fit within bounds
      // First point at: leftPadding + pointRadius
      // Last point at: size.width - rightPadding - pointRadius
      final x = leftPadding + pointRadius + (i / denominator) * availableWidth;
      final y = topPadding +
          availableHeight -
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
  bool shouldRepaint(covariant CumulativeScoreLinePainter oldDelegate) {
    // Always repaint if data length changed
    if (data.length != oldDelegate.data.length) return true;

    // OPTIMIZATION: Check last point first (most likely to change)
    // Only check historical points if last point changed or if we need to verify
    if (data.isNotEmpty && oldDelegate.data.isNotEmpty) {
      final lastIndex = data.length - 1;
      final currentLastScore = data[lastIndex]['score'] as double;
      final oldLastScore = oldDelegate.data[lastIndex]['score'] as double;

      // If last point changed, we need to repaint (but only the last segment will actually change)
      if (currentLastScore != oldLastScore) return true;

      // If last point is same, check historical points (rare case - only when history is reloaded)
      for (int i = 0; i < lastIndex; i++) {
        final currentScore = data[i]['score'] as double;
        final oldScore = oldDelegate.data[i]['score'] as double;
        if (currentScore != oldScore) return true;
      }
    }

    // Check if min/max/range changed (affects scaling)
    if (minScore != oldDelegate.minScore ||
        maxScore != oldDelegate.maxScore ||
        scoreRange != oldDelegate.scoreRange ||
        color != oldDelegate.color) {
      return true;
    }

    return false;
  }
}

/// Optimized painter for historical data (static - rarely changes)
/// Only repaints when historical data actually changes (e.g., day transition)
class CumulativeScoreHistoricalPainter extends CustomPainter {
  final List<Map<String, dynamic>> historicalData;
  final double minScore;
  final double maxScore;
  final double scoreRange;
  final Color color;
  final int
      totalDataPoints; // Total points including current day (for positioning)

  CumulativeScoreHistoricalPainter({
    required this.historicalData,
    required this.minScore,
    required this.maxScore,
    required this.scoreRange,
    required this.color,
    required this.totalDataPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (historicalData.isEmpty) return;

    const double topPadding = 8.0;
    const double rightPadding = 8.0;
    const double bottomPadding = 4.0;
    const double leftPadding = 0.0;
    const double pointRadius = 3.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final availableWidth =
        size.width - leftPadding - rightPadding - (2 * pointRadius);
    final availableHeight = size.height - topPadding - bottomPadding;
    final denominator = totalDataPoints > 1 ? totalDataPoints - 1 : 1;

    final points = <Offset>[];
    for (int i = 0; i < historicalData.length; i++) {
      final score = historicalData[i]['score'] as double;
      // Use totalDataPoints for positioning to align with current day painter
      final x = leftPadding + pointRadius + (i / denominator) * availableWidth;
      final y = topPadding +
          availableHeight -
          ((score - minScore) / (scoreRange > 0 ? scoreRange : 1)) *
              availableHeight;
      points.add(Offset(x, y));
    }

    // Draw historical lines (all except last segment which connects to current day)
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }

    // Draw all historical points including the last one (yesterday)
    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CumulativeScoreHistoricalPainter oldDelegate) {
    // Historical data rarely changes - only on day transition or history reload
    if (historicalData.length != oldDelegate.historicalData.length) return true;
    if (totalDataPoints != oldDelegate.totalDataPoints) return true;
    if (minScore != oldDelegate.minScore ||
        maxScore != oldDelegate.maxScore ||
        scoreRange != oldDelegate.scoreRange ||
        color != oldDelegate.color) {
      return true;
    }

    // Check if any historical scores changed (should be rare)
    for (int i = 0; i < historicalData.length; i++) {
      final currentScore = historicalData[i]['score'] as double;
      final oldScore = oldDelegate.historicalData[i]['score'] as double;
      if (currentScore != oldScore) return true;
    }

    return false;
  }
}

/// Optimized painter for current day point and connecting line segment (dynamic - updates frequently)
/// Only repaints when current day score changes
class CumulativeScoreCurrentDayPainter extends CustomPainter {
  final Map<String, dynamic>?
      previousDayData; // Second-to-last point (for connecting line)
  final Map<String, dynamic> currentDayData; // Last point (current day)
  final double minScore;
  final double maxScore;
  final double scoreRange;
  final Color color;
  final int totalDataPoints; // Total points (for positioning)

  CumulativeScoreCurrentDayPainter({
    required this.previousDayData,
    required this.currentDayData,
    required this.minScore,
    required this.maxScore,
    required this.scoreRange,
    required this.color,
    required this.totalDataPoints,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double topPadding = 8.0;
    const double rightPadding = 8.0;
    const double bottomPadding = 4.0;
    const double leftPadding = 0.0;
    const double pointRadius = 3.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final availableWidth =
        size.width - leftPadding - rightPadding - (2 * pointRadius);
    final availableHeight = size.height - topPadding - bottomPadding;
    final denominator = totalDataPoints > 1 ? totalDataPoints - 1 : 1;

    // Calculate current day point position (last point)
    final currentDayIndex = totalDataPoints - 1;
    final currentScore = currentDayData['score'] as double;
    final currentX = leftPadding +
        pointRadius +
        (currentDayIndex / denominator) * availableWidth;
    final currentY = topPadding +
        availableHeight -
        ((currentScore - minScore) / (scoreRange > 0 ? scoreRange : 1)) *
            availableHeight;
    final currentPoint = Offset(currentX, currentY);

    // Draw connecting line from previous day to current day (if previous day exists)
    if (previousDayData != null) {
      final previousIndex = totalDataPoints - 2;
      final previousScore = previousDayData!['score'] as double;
      final previousX = leftPadding +
          pointRadius +
          (previousIndex / denominator) * availableWidth;
      final previousY = topPadding +
          availableHeight -
          ((previousScore - minScore) / (scoreRange > 0 ? scoreRange : 1)) *
              availableHeight;
      final previousPoint = Offset(previousX, previousY);
      canvas.drawLine(previousPoint, currentPoint, paint);
    }

    // Draw current day point
    canvas.drawCircle(currentPoint, 3, pointPaint);
  }

  @override
  bool shouldRepaint(covariant CumulativeScoreCurrentDayPainter oldDelegate) {
    // Only repaint if current day score changed (most common case)
    final currentScore = currentDayData['score'] as double;
    final oldCurrentScore = oldDelegate.currentDayData['score'] as double;
    if (currentScore != oldCurrentScore) return true;

    // Check if previous day changed (rare - only on day transition)
    if (previousDayData != null && oldDelegate.previousDayData != null) {
      final prevScore = previousDayData!['score'] as double;
      final oldPrevScore = oldDelegate.previousDayData!['score'] as double;
      if (prevScore != oldPrevScore) return true;
    } else if (previousDayData != oldDelegate.previousDayData) {
      return true; // One is null, other isn't
    }

    // Check if scaling changed
    if (minScore != oldDelegate.minScore ||
        maxScore != oldDelegate.maxScore ||
        scoreRange != oldDelegate.scoreRange ||
        color != oldDelegate.color ||
        totalDataPoints != oldDelegate.totalDataPoints) {
      return true;
    }

    return false;
  }
}
