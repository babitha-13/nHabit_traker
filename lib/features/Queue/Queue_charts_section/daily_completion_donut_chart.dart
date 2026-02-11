import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';

/// Daily progress chart widget showing donut chart with progress details
class DailyProgressChart extends StatelessWidget {
  final double dailyPercentage;
  final double dailyTarget;
  final double pointsEarned;

  const DailyProgressChart({
    super.key,
    required this.dailyPercentage,
    required this.dailyTarget,
    required this.pointsEarned,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Column(
      children: [
        ProgressDonutChart(
          percentage: dailyPercentage,
          totalTarget: dailyTarget,
          pointsEarned: pointsEarned,
          size: 80,
        ),
        const SizedBox(height: 4),
        Text(
          'Daily Progress',
          style: theme.bodyMedium.override(
            fontFamily: 'Readex Pro',
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '${pointsEarned.toStringAsFixed(1)} / ${dailyTarget.toStringAsFixed(1)}',
          style: theme.bodySmall.override(
            fontFamily: 'Readex Pro',
            color: theme.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// Custom donut chart widget for displaying daily progress
class ProgressDonutChart extends StatelessWidget {
  final double percentage;
  final double totalTarget;
  final double pointsEarned;
  final double size;
  const ProgressDonutChart({
    Key? key,
    required this.percentage,
    required this.totalTarget,
    required this.pointsEarned,
    this.size = 120.0,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    // Debug logging
    return Container(
      width: size,
      height: size,
      child: CustomPaint(
        painter: DonutChartPainter(
          percentage: percentage,
          totalTarget: totalTarget,
          pointsEarned: pointsEarned,
          backgroundColor: theme.alternate,
          progressColor: _getProgressColor(percentage),
        ),
        child: Center(
          child: Text(
            '${percentage.toStringAsFixed(0)}%',
            style: theme.titleLarge.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }

  /// Get progress color based on percentage
  Color _getProgressColor(double percentage) {
    if (percentage < 30) {
      return Colors.red;
    } else if (percentage < 70) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }
}

/// Custom painter for the donut chart
class DonutChartPainter extends CustomPainter {
  final double percentage;
  final double totalTarget;
  final double pointsEarned;
  final Color backgroundColor;
  final Color progressColor;
  DonutChartPainter({
    required this.percentage,
    required this.totalTarget,
    required this.pointsEarned,
    required this.backgroundColor,
    required this.progressColor,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 20) / 2; // 20px padding
    final strokeWidth = 12.0;
    // Draw background circle
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, backgroundPaint);
    // Draw progress arc
    if (percentage > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      final sweepAngle = (percentage / 100) * 2 * 3.14159; // Convert to radians
      const startAngle = -3.14159 / 2; // Start from top (-90 degrees)
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is DonutChartPainter) {
      return oldDelegate.percentage != percentage ||
          oldDelegate.totalTarget != totalTarget ||
          oldDelegate.pointsEarned != pointsEarned ||
          oldDelegate.backgroundColor != backgroundColor ||
          oldDelegate.progressColor != progressColor;
    }
    return true;
  }
}
