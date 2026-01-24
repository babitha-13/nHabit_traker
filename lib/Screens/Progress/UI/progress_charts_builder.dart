import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Queue/Queue_charts_section/cumulative_score_line_painter.dart';
import '../Logic/progress_page_logic.dart';

class ProgressChartsBuilder {
  static Widget buildTrendChart({
    required BuildContext context,
    required ProgressPageLogic logic,
  }) {
    final last7Days = logic.getLastNDays(7);
    return Container(
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
            '7-Day Progress Trend',
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: build7DayColumnChart(context: context, data: last7Days, logic: logic),
          ),
        ],
      ),
    );
  }

  static Widget build7DayColumnChart({
    required BuildContext context,
    required List<DailyProgressRecord> data,
    required ProgressPageLogic logic,
  }) {
    final chartData = _prepareChartData(logic);

    double maxTarget = 100.0;
    if (chartData.isNotEmpty) {
      final maxVal = chartData
          .map((d) => d['target'] as double)
          .reduce((a, b) => a > b ? a : b);
      if (maxVal > 0) maxTarget = maxVal;
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: chartData.map((dayData) {
              return buildSingleDayColumn(context: context, dayData: dayData, maxTarget: maxTarget, logic: logic);
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        buildChartLegend(context),
      ],
    );
  }

  static List<Map<String, dynamic>> _prepareChartData(ProgressPageLogic logic) {
    final List<Map<String, dynamic>> chartData = [];
    final today = DateService.currentDate;

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final isToday = logic.isSameDay(date, today);

      if (isToday) {
        chartData.add({
          'date': date,
          'target': logic.todayTarget,
          'earned': logic.todayEarned,
          'percentage': logic.todayPercentage,
          'dayName': 'Today',
        });
      } else {
        final dayData = logic.getProgressForDate(date);
        chartData.add({
          'date': date,
          'target': dayData?.targetPoints ?? 0.0,
          'earned': dayData?.earnedPoints ?? 0.0,
          'percentage': dayData?.completionPercentage ?? 0.0,
          'dayName': logic.getDayName(date),
        });
      }
    }
    return chartData;
  }

  static Widget buildSingleDayColumn({
    required BuildContext context,
    required Map<String, dynamic> dayData,
    required double maxTarget,
    required ProgressPageLogic logic,
  }) {
    final target = dayData['target'] as double;
    final earned = dayData['earned'] as double;
    final percentage = dayData['percentage'] as double;
    final dayName = dayData['dayName'] as String;

    final targetHeight = (target / maxTarget) * 100;
    final earnedHeight = target > 0 ? (earned / target) * targetHeight : 0.0;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: () => logic.showProgressBreakdown(context, dayData['date'] as DateTime),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    Container(
                      width: 20,
                      height: targetHeight,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).alternate,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    if (earnedHeight > 0)
                      Container(
                        width: 20,
                        height: earnedHeight,
                        decoration: BoxDecoration(
                          color: logic.getPerformanceColor(percentage),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              dayName,
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    fontFamily: 'Readex Pro',
                    fontSize: 10,
                    color: FlutterFlowTheme.of(context).secondaryText,
                  ),
              textAlign: TextAlign.center,
            ),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    fontFamily: 'Readex Pro',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: logic.getPerformanceColor(percentage),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildChartLegend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).alternate,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Target',
          style: FlutterFlowTheme.of(context).bodySmall.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
        const SizedBox(width: 16),
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Completed',
          style: FlutterFlowTheme.of(context).bodySmall.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
      ],
    );
  }

  static Widget buildCumulativeScoreGraph({
    required BuildContext context,
    required ProgressPageLogic logic,
    required VoidCallback onToggleRange,
  }) {
    final displayData = logic.cumulativeScoreHistory;

    if (displayData.isEmpty) {
      return Container(
        height: 120,
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No score history yet',
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }

    return Container(
      height: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                logic.show30Days ? '30-Day Score Trend' : '7-Day Score Trend',
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              GestureDetector(
                onTap: onToggleRange,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    logic.show30Days ? '7D' : '30D',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).primary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: buildLineChart(context: context, data: displayData),
          ),
        ],
      ),
    );
  }

  static Widget buildLineChart({
    required BuildContext context,
    required List<Map<String, dynamic>> data,
  }) {
    if (data.isEmpty) return const SizedBox();

    final scores = data.map((d) => d['score'] as double).toList();
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    final adjustedMaxScore = maxScore == minScore ? minScore + 10.0 : maxScore;
    final adjustedRange = adjustedMaxScore - minScore;

    final numLabels = 5;
    final scaleLabels = <double>[];
    for (int i = 0; i < numLabels; i++) {
      final value = minScore + (adjustedRange * i / (numLabels - 1));
      scaleLabels.add(value);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: scaleLabels.reversed.map((value) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                value.toStringAsFixed(0),
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      fontFamily: 'Readex Pro',
                      fontSize: 9,
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
              ),
            );
          }).toList(),
        ),
        Expanded(
          child: CustomPaint(
            painter: CumulativeScoreLinePainter(
              data: data,
              minScore: minScore,
              maxScore: adjustedMaxScore,
              scoreRange: adjustedRange,
              color: FlutterFlowTheme.of(context).primary,
            ),
            size: const Size(double.infinity, double.infinity),
          ),
        ),
      ],
    );
  }
}

class SimpleLineChartPainter extends CustomPainter {
  final List<DailyProgressRecord> data;
  SimpleLineChartPainter(this.data);
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    final points = <Offset>[];
    final maxValue = 100.0;
    final minValue = 0.0;
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height -
          ((data[i].completionPercentage - minValue) / (maxValue - minValue)) *
              size.height;
      points.add(Offset(x, y));
    }
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }
    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    for (final point in points) {
      canvas.drawCircle(point, 3, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
