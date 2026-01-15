import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';

/// Widget to display habit completion trend as a line chart
class HabitTrendChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> dailyHistory;
  final double height;

  const HabitTrendChartWidget({
    Key? key,
    required this.dailyHistory,
    this.height = 200,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (dailyHistory.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No data available',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }

    // Calculate completion rates for each day
    final chartData = dailyHistory.map((day) {
      final progress = (day['progress'] as num?)?.toDouble() ?? 0.0;
      return progress * 100.0; // Convert to percentage
    }).toList();

    if (chartData.isEmpty) {
      return Container(
        height: height,
        child: Center(
          child: Text(
            'No data available',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }

    final minValue = 0.0;
    final maxValue = 100.0;
    final range = maxValue - minValue;

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: CustomPaint(
        painter: HabitTrendLinePainter(
          data: chartData,
          minValue: minValue,
          maxValue: maxValue,
          range: range,
          color: FlutterFlowTheme.of(context).primary,
        ),
        size: Size.infinite,
      ),
    );
  }
}

/// Custom painter for habit trend line chart
class HabitTrendLinePainter extends CustomPainter {
  final List<double> data;
  final double minValue;
  final double maxValue;
  final double range;
  final Color color;

  HabitTrendLinePainter({
    required this.data,
    required this.minValue,
    required this.maxValue,
    required this.range,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final pointPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final points = <Offset>[];

    // Calculate points
    for (int i = 0; i < data.length; i++) {
      final value = data[i];
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height -
          ((value - minValue) / (range > 0 ? range : 1)) * size.height;
      points.add(Offset(x, y));
    }

    // Draw grid lines
    final gridPaint = Paint()
      ..color = color.withOpacity(0.1)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Horizontal grid lines at 0%, 50%, 100%
    for (final percentage in [0.0, 0.5, 1.0]) {
      final y = size.height - (percentage * size.height);
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Draw line
    if (points.length > 1) {
      final path = Path();
      path.moveTo(points[0].dx, points[0].dy);

      for (int i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }

      canvas.drawPath(path, paint);
    }

    // Draw points
    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
