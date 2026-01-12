import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/progress_donut_chart.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Screens/Progress/progress_page.dart';
import 'package:habit_tracker/Screens/Queue/Queue%20UI/cumulative_score_graph.dart';
import 'package:habit_tracker/Screens/Queue/Logic/queue_utils.dart';
import 'package:habit_tracker/Helper/utils/queue_filter_state_manager.dart';
import 'package:habit_tracker/Helper/utils/queue_sort_state_manager.dart';
import 'package:habit_tracker/Screens/Queue/Queue%20UI/queue_filter_dialog.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';

/// Helper class for building queue UI components
class QueueUIBuilders {
  /// Build progress charts widget
  static Widget buildProgressCharts({
    required BuildContext context,
    required double dailyPercentage,
    required double dailyTarget,
    required double pointsEarned,
    required List<Map<String, dynamic>> miniGraphHistory,
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
              Column(
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
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  Text(
                    '${pointsEarned.toStringAsFixed(1)} / ${dailyTarget.toStringAsFixed(1)}',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                  ),
                ],
              ),
              // Cumulative Score Graph
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 120,
                    height: 80,
                    child: buildCumulativeScoreMiniGraph(
                      context: context,
                      history: miniGraphHistory,
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
                            style: FlutterFlowTheme.of(context)
                                .bodySmall
                                .override(
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
                            // Calculate daily gain consistently: today's score (from shared state) - yesterday's score (from graph history)
                            // This ensures both pages show the same value
                            final todayScore = miniGraphHistory.isNotEmpty
                                ? (miniGraphHistory.last['score'] as double)
                                : TodayProgressState().cumulativeScore;

                            double dailyGain = 0.0;
                            if (miniGraphHistory.length >= 2) {
                              // Use yesterday's score from history to match the graph
                              final yesterdayScore = miniGraphHistory[
                                  miniGraphHistory.length - 2]['score']
                                  as double;
                              dailyGain = todayScore - yesterdayScore;
                            } else if (miniGraphHistory.length == 1) {
                              // Only one day in history, can't calculate difference - use fallback
                              dailyGain =
                                  (miniGraphHistory.last['gain'] as double?) ??
                                      0.0;
                            }

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

  /// Build cumulative score mini graph
  static Widget buildCumulativeScoreMiniGraph({
    required BuildContext context,
    required List<Map<String, dynamic>> history,
  }) {
    if (history.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Center(
          child: Text(
            'No data',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ),
      );
    }

    return CumulativeScoreGraph(
      history: history,
      color: FlutterFlowTheme.of(context).primary,
    );
  }

  /// Build filter button widget
  static Widget buildFilterButton({
    required BuildContext context,
    required QueueFilterState currentFilter,
    required List<CategoryRecord> categories,
    required Function(QueueFilterState) onFilterChanged,
    required bool isDefaultFilterState,
    required int excludedCategoryCount,
  }) {
    final theme = FlutterFlowTheme.of(context);
    final isFilterActive = !isDefaultFilterState;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isFilterActive
                ? theme.primary.withOpacity(0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isFilterActive
                ? Border.all(
                    color: theme.primary.withOpacity(0.4),
                    width: 1.5,
                  )
                : null,
          ),
          child: IconButton(
            icon: Icon(
              Icons.filter_list,
              color: isFilterActive ? theme.primary : theme.secondaryText,
            ),
            onPressed: () async {
              final result = await showQueueFilterDialog(
                context: context,
                categories: categories,
                initialFilter: currentFilter,
              );
              if (result != null) {
                onFilterChanged(result);
              }
            },
            tooltip: 'Filter',
          ),
        ),
        if (excludedCategoryCount > 0)
          Positioned(
            right: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: theme.primary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.primaryBackground,
                  width: 1.5,
                ),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Center(
                child: Text(
                  excludedCategoryCount > 99 ? '99+' : '$excludedCategoryCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
