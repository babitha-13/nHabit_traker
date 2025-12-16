import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

/// Widget to display period comparisons (week-over-week, month-over-month)
class HabitPeriodComparisonWidget extends StatelessWidget {
  final List<Map<String, dynamic>> weeklyBreakdown;
  final List<Map<String, dynamic>> monthlyBreakdown;
  
  const HabitPeriodComparisonWidget({
    Key? key,
    required this.weeklyBreakdown,
    required this.monthlyBreakdown,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weeklyBreakdown.length >= 2) ...[
          Text(
            'Week-over-Week Comparison',
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          _buildWeekComparison(context),
          const SizedBox(height: 24),
        ],
        if (monthlyBreakdown.length >= 2) ...[
          Text(
            'Month-over-Month Comparison',
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          _buildMonthComparison(context),
        ],
      ],
    );
  }
  
  Widget _buildWeekComparison(BuildContext context) {
    if (weeklyBreakdown.length < 2) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Not enough data for comparison',
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
      );
    }
    
    // Get last two weeks
    final lastWeek = weeklyBreakdown[weeklyBreakdown.length - 1];
    final previousWeek = weeklyBreakdown[weeklyBreakdown.length - 2];
    
    final lastRate = lastWeek['completionRate'] as double;
    final prevRate = previousWeek['completionRate'] as double;
    final change = lastRate - prevRate;
    final changePercent = prevRate > 0 ? (change / prevRate) * 100 : 0.0;
    
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
      child: Row(
        children: [
          Expanded(
            child: _buildPeriodCard(
              context,
              'Previous Week',
              prevRate,
              _formatWeekDate(previousWeek['weekStart'] as DateTime),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildPeriodCard(
              context,
              'Last Week',
              lastRate,
              _formatWeekDate(lastWeek['weekStart'] as DateTime),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildChangeCard(context, change, changePercent),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMonthComparison(BuildContext context) {
    if (monthlyBreakdown.length < 2) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Not enough data for comparison',
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
      );
    }
    
    // Get last two months
    final lastMonth = monthlyBreakdown[monthlyBreakdown.length - 1];
    final previousMonth = monthlyBreakdown[monthlyBreakdown.length - 2];
    
    final lastRate = lastMonth['completionRate'] as double;
    final prevRate = previousMonth['completionRate'] as double;
    final change = lastRate - prevRate;
    final changePercent = prevRate > 0 ? (change / prevRate) * 100 : 0.0;
    
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
      child: Row(
        children: [
          Expanded(
            child: _buildPeriodCard(
              context,
              'Previous Month',
              prevRate,
              _formatMonthDate(previousMonth['monthStart'] as DateTime),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildPeriodCard(
              context,
              'Last Month',
              lastRate,
              _formatMonthDate(lastMonth['monthStart'] as DateTime),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildChangeCard(context, change, changePercent),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPeriodCard(
    BuildContext context,
    String label,
    double completionRate,
    String dateLabel,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            dateLabel,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  fontSize: 10,
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '${completionRate.toStringAsFixed(1)}%',
            style: FlutterFlowTheme.of(context).headlineSmall.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.bold,
                  color: _getCompletionColor(completionRate),
                ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildChangeCard(BuildContext context, double change, double changePercent) {
    final isPositive = change >= 0;
    final color = isPositive ? Colors.green : Colors.red;
    
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Change',
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(
                isPositive ? Icons.arrow_upward : Icons.arrow_downward,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 4),
              Text(
                '${change.abs().toStringAsFixed(1)}%',
                style: FlutterFlowTheme.of(context).headlineSmall.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
              ),
            ],
          ),
          if (changePercent.abs() > 0.1)
            Text(
              '${changePercent.abs().toStringAsFixed(1)}% vs previous',
              style: FlutterFlowTheme.of(context).bodySmall.override(
                    fontFamily: 'Readex Pro',
                    fontSize: 10,
                    color: FlutterFlowTheme.of(context).secondaryText,
                  ),
            ),
        ],
      ),
    );
  }
  
  String _formatWeekDate(DateTime weekStart) {
    final weekEnd = weekStart.add(const Duration(days: 6));
    return '${weekStart.month}/${weekStart.day} - ${weekEnd.month}/${weekEnd.day}';
  }
  
  String _formatMonthDate(DateTime monthStart) {
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
    return '${months[monthStart.month - 1]} ${monthStart.year}';
  }
  
  Color _getCompletionColor(double rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 50) return Colors.orange;
    return Colors.red;
  }
}

