import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

/// Widget to display completion calendar/heatmap similar to GitHub contributions
class CompletionCalendarWidget extends StatelessWidget {
  final Map<DateTime, String> completionHistory;
  final int daysToShow;

  const CompletionCalendarWidget({
    Key? key,
    required this.completionHistory,
    this.daysToShow = 90,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final today = DateService.currentDate;
    final startDate = today.subtract(Duration(days: daysToShow));

    // Generate all dates in range
    final dates = <DateTime>[];
    for (int i = 0; i < daysToShow; i++) {
      dates.add(startDate.add(Duration(days: i)));
    }

    // Group dates by week
    final weeks = <List<DateTime>>[];
    List<DateTime> currentWeek = [];

    for (final date in dates) {
      if (currentWeek.isEmpty) {
        // Fill empty days at start of first week
        final weekday = date.weekday;
        for (int i = 0; i < weekday % 7; i++) {
          currentWeek.add(DateTime(1970, 1, 1)); // Placeholder
        }
      }

      currentWeek.add(date);

      if (currentWeek.length == 7) {
        weeks.add(currentWeek);
        currentWeek = [];
      }
    }

    // Add remaining days to last week
    if (currentWeek.isNotEmpty) {
      while (currentWeek.length < 7) {
        currentWeek.add(DateTime(1970, 1, 1)); // Placeholder
      }
      weeks.add(currentWeek);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        _buildLegend(context),
        const SizedBox(height: 8),
        // Calendar grid
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day labels
              Column(
                children: ['', 'Mon', '', 'Wed', '', 'Fri', '']
                    .map((label) => Container(
                          width: 20,
                          height: 12,
                          margin: const EdgeInsets.only(bottom: 2),
                          child: label.isEmpty
                              ? const SizedBox()
                              : Text(
                                  label,
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontSize: 10,
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                ),
                        ))
                    .toList(),
              ),
              const SizedBox(width: 4),
              // Weeks
              ...weeks.asMap().entries.map((entry) {
                final weekIndex = entry.key;
                final week = entry.value;
                return Column(
                  children: [
                    // Week label (first week of month)
                    if (weekIndex == 0 ||
                        (week.first.year != weeks[weekIndex - 1].first.year ||
                            week.first.month !=
                                weeks[weekIndex - 1].first.month))
                      Container(
                        height: 12,
                        margin: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          _getMonthLabel(week.first),
                          style: FlutterFlowTheme.of(context)
                              .bodySmall
                              .override(
                                fontFamily: 'Readex Pro',
                                fontSize: 10,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                        ),
                      )
                    else
                      const SizedBox(height: 12),
                    // Days in week
                    ...week.asMap().entries.map((dayEntry) {
                      final dayIndex = dayEntry.key;
                      final date = dayEntry.value;

                      // Skip placeholder dates
                      if (date.year == 1970) {
                        return Container(
                          width: 12,
                          height: 12,
                          margin: const EdgeInsets.only(bottom: 2),
                        );
                      }

                      final normalizedDate =
                          DateTime(date.year, date.month, date.day);
                      final status =
                          completionHistory[normalizedDate] ?? 'none';

                      return _buildDayCell(
                          context, date, status, dayIndex == 0);
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime date,
    String status,
    bool isFirstInWeek,
  ) {
    Color color;
    String tooltip;

    switch (status) {
      case 'completed':
        color = Colors.green;
        tooltip = 'Completed';
        break;
      case 'skipped':
        if (_hasProgress(date)) {
          color = Colors.orange;
          tooltip = 'Partial';
        } else {
          color = Colors.grey;
          tooltip = 'Skipped';
        }
        break;
      case 'pending':
        color = Colors.white;
        tooltip = 'Pending';
        break;
      default:
        color = Colors.white;
        tooltip = 'Not tracked';
    }

    return Tooltip(
      message: '${_formatDate(date)}: $tooltip',
      child: Container(
        width: 12,
        height: 12,
        margin: EdgeInsets.only(
          bottom: 2,
          left: isFirstInWeek ? 4 : 2,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: FlutterFlowTheme.of(context).alternate.withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
    );
  }

  bool _hasProgress(DateTime date) {
    // Check if there's any progress data for this date
    // This is a simplified check - in real implementation,
    // you might want to pass progress data separately
    return false;
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year}';
  }

  String _getMonthLabel(DateTime date) {
    if (date.year == 1970) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return months[date.month - 1];
  }

  Widget _buildLegend(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildLegendItem(context, 'Less', Colors.white),
        const SizedBox(width: 4),
        _buildLegendItem(context, '', Colors.grey),
        const SizedBox(width: 4),
        _buildLegendItem(context, '', Colors.orange),
        const SizedBox(width: 4),
        _buildLegendItem(context, 'More', Colors.green),
      ],
    );
  }

  Widget _buildLegendItem(BuildContext context, String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(
              color: FlutterFlowTheme.of(context).alternate.withOpacity(0.3),
              width: 0.5,
            ),
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            label,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  fontSize: 10,
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
        ],
      ],
    );
  }
}
