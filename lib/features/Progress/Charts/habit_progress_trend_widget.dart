import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';

/// Widget to display quantity progress trend over time for quantity-tracked habits
class HabitProgressTrendWidget extends StatelessWidget {
  final List<Map<String, dynamic>> dailyHistory;
  final double height;

  const HabitProgressTrendWidget({
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

    // Extract quantity values (using 'earned' as quantity for completed days)
    final quantityData =
        dailyHistory.where((day) => day['status'] == 'completed').map((day) {
      final date = day['date'] as DateTime?;
      final earned = (day['earned'] as num?)?.toDouble() ?? 0.0;
      return {
        'date': date,
        'quantity': earned,
      };
    }).toList();

    if (quantityData.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No completed days with quantity data',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }

    final quantities =
        quantityData.map((d) => d['quantity'] as double).toList();
    final minValue = 0.0;
    final maxValue =
        quantities.isEmpty ? 1.0 : quantities.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue;

    return Container(
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quantity Progress Trend',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: CustomPaint(
              painter: QuantityTrendLinePainter(
                data: quantities,
                minValue: minValue,
                maxValue: maxValue,
                range: range,
                color: FlutterFlowTheme.of(context).primary,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for quantity trend line chart
class QuantityTrendLinePainter extends CustomPainter {
  final List<double> data;
  final double minValue;
  final double maxValue;
  final double range;
  final Color color;

  QuantityTrendLinePainter({
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

    // Horizontal grid lines
    for (final percentage in [0.0, 0.25, 0.5, 0.75, 1.0]) {
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

    // Draw value labels at points
    final textPainter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    for (int i = 0; i < data.length; i++) {
      if (i % (data.length ~/ 5 + 1) == 0 || i == data.length - 1) {
        // Show label for every 5th point or last point
        textPainter.text = TextSpan(
          text: data[i].toStringAsFixed(0),
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        textPainter.paint(
          canvas,
          Offset(
            points[i].dx - textPainter.width / 2,
            points[i].dy - textPainter.height - 8,
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
