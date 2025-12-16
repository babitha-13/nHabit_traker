import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/habit_statistics_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/utils/completion_calendar_widget.dart';
import 'package:habit_tracker/Helper/utils/habit_trend_chart_widget.dart';
import 'package:habit_tracker/Helper/utils/habit_distribution_chart_widget.dart';
import 'package:habit_tracker/Helper/utils/habit_period_comparison_widget.dart';
import 'package:habit_tracker/Helper/utils/habit_progress_trend_widget.dart';

class HabitDetailStatisticsPage extends StatefulWidget {
  final String habitName;
  
  const HabitDetailStatisticsPage({
    Key? key,
    required this.habitName,
  }) : super(key: key);
  
  @override
  State<HabitDetailStatisticsPage> createState() =>
      _HabitDetailStatisticsPageState();
}

class _HabitDetailStatisticsPageState
    extends State<HabitDetailStatisticsPage> {
  HabitStatistics? _stats;
  bool _isLoading = true;
  String _selectedPeriod = '30';
  Map<DateTime, String> _completionHistory = {};
  
  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }
  
  Future<void> _loadStatistics() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      
      DateTime? startDate;
      final endDate = DateService.currentDate;
      
      switch (_selectedPeriod) {
        case '7':
          startDate = endDate.subtract(const Duration(days: 7));
          break;
        case '30':
          startDate = endDate.subtract(const Duration(days: 30));
          break;
        case '90':
          startDate = endDate.subtract(const Duration(days: 90));
          break;
        case 'all':
          startDate = null;
          break;
      }
      
      final stats = await HabitStatisticsService.getHabitStatistics(
        userId,
        widget.habitName,
        startDate: startDate,
        endDate: endDate,
      );
      
      // Get completion history for calendar
      final days = _selectedPeriod == 'all' ? 365 : int.parse(_selectedPeriod);
      final history = await HabitStatisticsService.getHabitCompletionHistory(
        userId,
        widget.habitName,
        days,
      );
      
      if (mounted) {
        setState(() {
          _stats = stats;
          _completionHistory = history;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading habit statistics: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primary,
        title: Text(
          widget.habitName,
          style: FlutterFlowTheme.of(context).headlineMedium.override(
                fontFamily: 'Readex Pro',
                color: Colors.white,
                fontSize: 20,
              ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null
              ? Center(
                  child: Text(
                    'No data available',
                    style: FlutterFlowTheme.of(context).bodyLarge.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Time period selector
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FlutterFlowTheme.of(context).secondaryBackground,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Time Period:',
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    fontFamily: 'Readex Pro',
                                  ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedPeriod,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                    value: '7',
                                    child: Text('7 Days'),
                                  ),
                                  DropdownMenuItem(
                                    value: '30',
                                    child: Text('30 Days'),
                                  ),
                                  DropdownMenuItem(
                                    value: '90',
                                    child: Text('90 Days'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text('All Time'),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedPeriod = value;
                                    });
                                    _loadStatistics();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Key metrics cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              'Completion Rate',
                              '${_stats!.completionRate.toStringAsFixed(1)}%',
                              Icons.check_circle,
                              _getCompletionColor(_stats!.completionRate),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              'Total Completions',
                              '${_stats!.totalCompletions}',
                              Icons.event_available,
                              FlutterFlowTheme.of(context).primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              'Days Tracked',
                              '${_stats!.totalDaysTracked}',
                              Icons.calendar_today,
                              FlutterFlowTheme.of(context).secondary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              'Consistency',
                              '${_stats!.consistencyScore.toStringAsFixed(0)}%',
                              Icons.trending_up,
                              _getConsistencyColor(_stats!.consistencyScore),
                            ),
                          ),
                        ],
                      ),
                      // Time-based statistics (for time-tracked habits)
                      if (_stats!.trackingType == 'time' && _stats!.totalSessions > 0) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Time Statistics',
                          style: FlutterFlowTheme.of(context).titleMedium.override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                'Total Time',
                                _formatDuration(_stats!.totalTimeSpent),
                                Icons.timer,
                                FlutterFlowTheme.of(context).primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                'Avg Session',
                                _formatDuration(_stats!.averageSessionDuration),
                                Icons.access_time,
                                Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                'Total Sessions',
                                '${_stats!.totalSessions}',
                                Icons.play_circle_outline,
                                Colors.purple,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(), // Empty space for alignment
                            ),
                          ],
                        ),
                      ],
                      // Quantity-based statistics (for quantity habits)
                      if (_stats!.trackingType == 'quantity' && _stats!.totalQuantityCompleted > 0) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Quantity Statistics',
                          style: FlutterFlowTheme.of(context).titleMedium.override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                'Total Quantity',
                                _stats!.totalQuantityCompleted.toStringAsFixed(1),
                                Icons.stacked_bar_chart,
                                FlutterFlowTheme.of(context).primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMetricCard(
                                context,
                                'Avg per Completion',
                                _stats!.averageQuantityPerCompletion.toStringAsFixed(1),
                                Icons.analytics,
                                Colors.blue,
                              ),
                            ),
                          ],
                        ),
                      ],
                      // Best day/week/month
                      if (_stats!.bestDayOfWeek != null || _stats!.bestWeek != null || _stats!.bestMonth != null) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Best Performance',
                          style: FlutterFlowTheme.of(context).titleMedium.override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (_stats!.bestDayOfWeek != null)
                              _buildBestPerformanceCard(
                                context,
                                'Best Day',
                                _getDayName(_stats!.bestDayOfWeek!),
                                Icons.calendar_today,
                              ),
                            if (_stats!.bestWeek != null)
                              _buildBestPerformanceCard(
                                context,
                                'Best Week',
                                _formatWeekDate(_stats!.bestWeek!),
                                Icons.date_range,
                              ),
                            if (_stats!.bestMonth != null)
                              _buildBestPerformanceCard(
                                context,
                                'Best Month',
                                _formatMonthDate(_stats!.bestMonth!),
                                Icons.calendar_month,
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      // Trend chart
                      Text(
                        'Completion Trend',
                        style: FlutterFlowTheme.of(context).titleMedium.override(
                              fontFamily: 'Readex Pro',
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      HabitTrendChartWidget(
                        dailyHistory: _stats!.dailyHistory,
                        height: 200,
                      ),
                      const SizedBox(height: 24),
                      // Completion calendar
                      Text(
                        'Completion Calendar',
                        style: FlutterFlowTheme.of(context).titleMedium.override(
                              fontFamily: 'Readex Pro',
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      CompletionCalendarWidget(
                        completionHistory: _completionHistory,
                        daysToShow: _selectedPeriod == 'all'
                            ? 365
                            : int.parse(_selectedPeriod),
                      ),
                      const SizedBox(height: 24),
                      // Distribution charts
                      if (_stats!.completionsByDayOfWeek.isNotEmpty) ...[
                        Text(
                          'Distribution Analysis',
                          style: FlutterFlowTheme.of(context).titleMedium.override(
                                fontFamily: 'Readex Pro',
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 12),
                        HabitDistributionChartWidget(
                          data: _stats!.completionsByDayOfWeek,
                          isDayOfWeek: true,
                          height: 200,
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Hour distribution (for time-tracked habits)
                      if (_stats!.trackingType == 'time' && _stats!.completionsByHour.isNotEmpty) ...[
                        HabitDistributionChartWidget(
                          data: _stats!.completionsByHour,
                          isDayOfWeek: false,
                          height: 200,
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Quantity progress trend (for quantity habits)
                      if (_stats!.trackingType == 'quantity') ...[
                        HabitProgressTrendWidget(
                          dailyHistory: _stats!.dailyHistory,
                          height: 200,
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Period comparisons
                      if (_stats!.weeklyBreakdown.isNotEmpty || _stats!.monthlyBreakdown.isNotEmpty) ...[
                        HabitPeriodComparisonWidget(
                          weeklyBreakdown: _stats!.weeklyBreakdown,
                          monthlyBreakdown: _stats!.monthlyBreakdown,
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Status breakdown
                      Text(
                        'Status Breakdown',
                        style: FlutterFlowTheme.of(context).titleMedium.override(
                              fontFamily: 'Readex Pro',
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 12),
                      _buildStatusBreakdown(context),
                    ],
                  ),
                ),
    );
  }
  
  Widget _buildBestPerformanceCard(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: FlutterFlowTheme.of(context).primary, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      fontFamily: 'Readex Pro',
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
              ),
              Text(
                value,
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return '${duration.inSeconds}s';
    }
  }
  
  String _getDayName(int dayOfWeek) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[dayOfWeek - 1];
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
  
  Color _getConsistencyColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }
  
  Widget _buildMetricCard(
    BuildContext context,
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: FlutterFlowTheme.of(context).headlineSmall.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: FlutterFlowTheme.of(context).secondaryText,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatusBreakdown(BuildContext context) {
    final completed = _stats!.statusBreakdown['completed'] ?? 0;
    final skipped = _stats!.statusBreakdown['skipped'] ?? 0;
    final pending = _stats!.statusBreakdown['pending'] ?? 0;
    final total = completed + skipped + pending;
    
    if (total == 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'No status data available',
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
      );
    }
    
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
        children: [
          _buildStatusItem(context, 'Completed', completed, total, Colors.green),
          const SizedBox(height: 12),
          _buildStatusItem(context, 'Skipped', skipped, total, Colors.orange),
          const SizedBox(height: 12),
          _buildStatusItem(context, 'Pending', pending, total, Colors.grey),
        ],
      ),
    );
  }
  
  Widget _buildStatusItem(
    BuildContext context,
    String label,
    int count,
    int total,
    Color color,
  ) {
    final percentage = total > 0 ? (count / total) * 100 : 0.0;
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                ),
          ),
        ),
        Text(
          '$count (${percentage.toStringAsFixed(1)}%)',
          style: FlutterFlowTheme.of(context).bodyMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
  
  Color _getCompletionColor(double rate) {
    if (rate >= 80) return Colors.green;
    if (rate >= 50) return Colors.orange;
    return Colors.red;
  }
}

