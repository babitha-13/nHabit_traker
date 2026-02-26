import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/features/Progress/Pages/progress_page.dart';
import 'package:habit_tracker/features/Queue/Queue_charts_section/cumulative_score_chart.dart';
import 'package:habit_tracker/features/Queue/Queue_charts_section/daily_completion_donut_chart.dart';

/// Helper class for building queue UI components
class QueueUIBuilders {
  /// Build progress charts widget
  static Widget buildProgressCharts({
    required BuildContext context,
    required double dailyPercentage,
    required double dailyTarget,
    required double pointsEarned,
    required List<Map<String, dynamic>> miniGraphHistory,
    bool isHistoryLoading = false,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ProgressPage(),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              blurRadius: 4,
              color: Color(0x33000000),
              offset: Offset(0, 2),
            )
          ],
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Daily Progress Donut Chart
              // Use key to force rebuild when values change
              DailyProgressChart(
                key: ValueKey(
                  [dailyPercentage, pointsEarned, dailyTarget].join('_'),
                ),
                dailyPercentage: dailyPercentage,
                dailyTarget: dailyTarget,
                pointsEarned: pointsEarned,
              ),
              // Cumulative Score Graph
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 136,
                    height: 80,
                    child: CumulativeScoreGraph(
                      // Use key based on last score to force rebuild when history changes
                      key: ValueKey(
                        miniGraphHistory.isNotEmpty
                            ? miniGraphHistory.last['score'] as double
                            : 0.0,
                      ),
                      history: miniGraphHistory,
                      color: FlutterFlowTheme.of(context).primary,
                      isLoading: isHistoryLoading,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cumulative Score',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Builder(
                        builder: (context) {
                          // Use the same value as the graph for consistency
                          // The graph's last point is always the projected score for today
                          final score = miniGraphHistory.isNotEmpty
                              ? (miniGraphHistory.last['score'] as double)
                              : TodayProgressState().cumulativeScore;

                          return Text(
                            '${score.toStringAsFixed(0)} pts',
                            style:
                                FlutterFlowTheme.of(context).bodySmall.override(
                                      fontFamily: 'Readex Pro',
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                          );
                        },
                      ),
                      if (miniGraphHistory.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            // Use the same displayed history point as the chart.
                            // This keeps chart movement and delta text in sync.
                            final dailyGain =
                                (miniGraphHistory.last['gain'] as num?)
                                        ?.toDouble() ??
                                    0.0;

                            if (dailyGain == 0) return const SizedBox.shrink();
                            return Text(
                              dailyGain >= 0
                                  ? '+${dailyGain.toStringAsFixed(1)}'
                                  : dailyGain.toStringAsFixed(1),
                              style: FlutterFlowTheme.of(context)
                                  .bodySmall
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    color: dailyGain >= 0
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight: FontWeight.w600,
                                  ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
