import 'package:flutter/material.dart';
import 'package:calendar_view/calendar_view.dart';
import 'package:habit_tracker/Screens/Calendar/Time_breakdown_chart/time_breakdown_chart.dart';
import 'package:habit_tracker/Screens/Calendar/Time_breakdown_chart/time_breakdown_calculator.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

/// Helper class for time breakdown chart modal
class TimeBreakdownModal {
  /// Show time breakdown chart modal
  static void showTimeBreakdownChart({
    required BuildContext context,
    required DateTime selectedDate,
    required List<CalendarEventData> sortedCompletedEvents,
  }) {
    final breakdownData =
        CalendarTimeBreakdownCalculator.calculateTimeBreakdown(
      sortedCompletedEvents,
    );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: FlutterFlowTheme.of(context)
                            .alternate
                            .withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Time Breakdown',
                        style: FlutterFlowTheme.of(context).titleLarge.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: TimeBreakdownChartWidget(
                    breakdownData: breakdownData,
                    selectedDate: selectedDate,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
