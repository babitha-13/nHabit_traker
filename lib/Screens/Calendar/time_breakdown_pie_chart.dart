import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:intl/intl.dart';

/// Data class for pie chart segments
class PieChartSegment {
  final String label;
  final double value; // Duration in minutes
  final Color color;
  final String category; // 'habit', 'task', 'non_productive', 'unlogged'

  PieChartSegment({
    required this.label,
    required this.value,
    required this.color,
    required this.category,
  });
}

/// Data model for time breakdown with totals and category-level segments
class TimeBreakdownData {
  final double habitMinutes;
  final double taskMinutes;
  final double nonProductiveMinutes;
  final List<PieChartSegment> segments;

  TimeBreakdownData({
    required this.habitMinutes,
    required this.taskMinutes,
    required this.nonProductiveMinutes,
    required this.segments,
  });

  double get totalLoggedMinutes =>
      habitMinutes + taskMinutes + nonProductiveMinutes;
}

/// Custom painter for pie chart
class PieChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;
  final double strokeWidth;

  PieChartPainter({
    required this.segments,
    this.strokeWidth = 2.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (segments.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        (size.width < size.height ? size.width : size.height) / 2 - strokeWidth;

    // Calculate total value
    final total =
        segments.fold<double>(0, (sum, segment) => sum + segment.value);
    if (total == 0) return;

    // Draw segments
    double startAngle = -math.pi / 2; // Start from top

    for (final segment in segments) {
      if (segment.value <= 0) continue;

      final sweepAngle = (segment.value / total) * 2 * math.pi;

      // Draw arc
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      // Draw border
      final borderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! PieChartPainter) return true;
    if (oldDelegate.segments.length != segments.length) return true;
    for (int i = 0; i < segments.length; i++) {
      if (oldDelegate.segments[i].value != segments[i].value ||
          oldDelegate.segments[i].color != segments[i].color) {
        return true;
      }
    }
    return false;
  }
}

/// Widget to display time breakdown pie chart
class TimeBreakdownPieChart extends StatelessWidget {
  final List<PieChartSegment> segments;
  final double size;

  const TimeBreakdownPieChart({
    super.key,
    required this.segments,
    this.size = 250.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    if (segments.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: theme.alternate.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(
            'No data',
            style: theme.bodyMedium.copyWith(
              color: theme.secondaryText,
            ),
          ),
        ),
      );
    }

    return CustomPaint(
      size: Size(size, size),
      painter: PieChartPainter(segments: segments),
    );
  }
}

/// Widget to display pie chart with legend
class TimeBreakdownChartWidget extends StatelessWidget {
  final TimeBreakdownData breakdownData;
  final DateTime selectedDate;

  const TimeBreakdownChartWidget({
    super.key,
    required this.breakdownData,
    required this.selectedDate,
  });

  String _formatDuration(double minutes) {
    final hours = (minutes / 60).floor();
    final mins = (minutes % 60).round();
    if (hours > 0) {
      return '${hours}h ${mins}m';
    }
    return '${mins}m';
  }

  String _formatPercentage(double value, double total) {
    if (total == 0) return '0%';
    return '${((value / total) * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final totalHours = 24.0 * 60.0; // 24 hours in minutes
    final totalLoggedMinutes = breakdownData.totalLoggedMinutes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date subtitle
        Text(
          DateFormat('MMM d, y').format(selectedDate),
          style: theme.titleMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Total Logged: ${_formatDuration(totalLoggedMinutes)} / 24h',
          style: theme.bodyMedium.copyWith(
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(height: 16),

        // Summary row with totals (Habits, Tasks, Non-Productive)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (breakdownData.habitMinutes > 0)
              _buildSummaryChip(
                context,
                'Habits',
                breakdownData.habitMinutes,
                Colors.orange,
                theme,
              ),
            if (breakdownData.taskMinutes > 0)
              _buildSummaryChip(
                context,
                'Tasks',
                breakdownData.taskMinutes,
                const Color(0xFF1A1A1A),
                theme,
              ),
            if (breakdownData.nonProductiveMinutes > 0)
              _buildSummaryChip(
                context,
                'Non-Productive',
                breakdownData.nonProductiveMinutes,
                Colors.grey,
                theme,
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Chart and Legend
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pie Chart - increased size
            TimeBreakdownPieChart(
              segments: breakdownData.segments,
              size: 240.0,
            ),
            const SizedBox(width: 24),

            // Legend
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: breakdownData.segments.map((segment) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12.0),
                    child: Row(
                      children: [
                        // Color indicator
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: segment.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Label and value
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                segment.label,
                                style: theme.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${_formatDuration(segment.value)} • ${_formatPercentage(segment.value, totalHours)}',
                                style: theme.bodySmall.copyWith(
                                  color: theme.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryChip(
    BuildContext context,
    String label,
    double minutes,
    Color color,
    FlutterFlowTheme theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$label: ${_formatDuration(minutes)}',
            style: theme.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.primaryText,
            ),
          ),
        ],
      ),
    );
  }
}
