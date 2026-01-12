import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/progress_donut_chart.dart';

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
