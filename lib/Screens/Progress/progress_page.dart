import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/day_end_processor.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:flutter/foundation.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({Key? key}) : super(key: key);

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<DailyProgressRecord> _progressHistory = [];
  bool _isLoading = true;
  String _selectedUserId =
      'szbvXb6Z5TXikcqaU1SfChU6iXl2'; // TODO: Get from auth

  // Live today's progress data
  double _todayTarget = 0.0;
  double _todayEarned = 0.0;
  double _todayPercentage = 0.0;

  @override
  void initState() {
    super.initState();
    _loadProgressHistory();

    // Listen for today's progress updates from Queue page
    NotificationCenter.addObserver(this, 'todayProgressUpdated', (param) {
      if (mounted) {
        setState(() {
          final data = TodayProgressState().getProgressData();
          _todayTarget = data['target']!;
          _todayEarned = data['earned']!;
          _todayPercentage = data['percentage']!;
        });
      }
    });

    // Load initial today's progress
    _loadInitialTodayProgress();
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadProgressHistory() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // First, trigger day-end processing to ensure we have progress data
      print(
          'ProgressPage: Triggering day-end processing to generate progress data...');
      await DayEndProcessor.processDayEnd(userId: _selectedUserId);

      // Also process yesterday to catch any missed data
      final yesterday =
          DateService.currentDate.subtract(const Duration(days: 1));
      await DayEndProcessor.processDayEnd(
          userId: _selectedUserId, targetDate: yesterday);

      // Load last 30 days of progress data
      final endDate = DateService.currentDate;
      final startDate = endDate.subtract(const Duration(days: 30));

      final query = await DailyProgressRecord.collectionForUser(_selectedUserId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: true)
          .get();

      final progressData = query.docs
          .map((doc) => DailyProgressRecord.fromSnapshot(doc))
          .toList();

      if (mounted) {
        setState(() {
          _progressHistory = progressData;
          _isLoading = false;
        });
      }

      print('ProgressPage: Loaded ${_progressHistory.length} progress records');
    } catch (e) {
      print('ProgressPage: Error loading progress history: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _loadInitialTodayProgress() {
    final data = TodayProgressState().getProgressData();
    setState(() {
      _todayTarget = data['target']!;
      _todayEarned = data['earned']!;
      _todayPercentage = data['percentage']!;
    });
  }

  Future<void> _generateProgressData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      print('ProgressPage: Manually generating progress data...');

      // Process the last 7 days to generate any missing progress data
      for (int i = 0; i < 7; i++) {
        final date = DateService.currentDate.subtract(Duration(days: i));
        await DayEndProcessor.processDayEnd(
          userId: _selectedUserId,
          targetDate: date,
        );
      }

      // Reload the progress history
      await _loadProgressHistory();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Progress data generated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('ProgressPage: Error generating progress data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating progress data: $e'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primary,
        automaticallyImplyLeading: false,
        title: Text(
          'Progress History',
          style: FlutterFlowTheme.of(context).headlineMedium.override(
                fontFamily: 'Readex Pro',
                color: Colors.white,
                fontSize: 22.0,
              ),
        ),
        centerTitle: false,
        elevation: 0.0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadProgressHistory,
          ),
          IconButton(
            icon: const Icon(Icons.analytics, color: Colors.white),
            onPressed: _generateProgressData,
            tooltip: 'Generate Progress Data',
          ),
          // Development/Testing only - show in debug mode
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.science, color: Colors.white),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SimpleTestingPage(),
                  ),
                );
              },
              tooltip: 'Testing Tools',
            ),
        ],
      ),
      body: SafeArea(
        top: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _buildProgressContent(),
      ),
    );
  }

  Widget _buildProgressContent() {
    if (_progressHistory.isEmpty) {
      return _buildEmptyState();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 24),
          _buildCalendarHeatmap(),
          const SizedBox(height: 24),
          _buildTrendChart(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.analytics_outlined,
            size: 64,
            color: FlutterFlowTheme.of(context).secondaryText,
          ),
          const SizedBox(height: 16),
          Text(
            'No progress data available',
            style: FlutterFlowTheme.of(context).titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Complete some habits to see your progress history',
            style: FlutterFlowTheme.of(context).bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    final last7Days = _getLastNDays(7);
    final last30Days = _getLastNDays(30);

    final avg7Day = _calculateAveragePercentage(last7Days);
    final avg30Day = _calculateAveragePercentage(last30Days);
    final avg7DayTarget = _calculateAverageTarget(last7Days);
    final avg7DayEarned = _calculateAverageEarned(last7Days);
    final avg30DayTarget = _calculateAverageTarget(last30Days);
    final avg30DayEarned = _calculateAverageEarned(last30Days);

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            '7-Day Avg',
            '${avg7Day.toStringAsFixed(0)}%',
            '${avg7DayEarned.toStringAsFixed(0)}/${avg7DayTarget.toStringAsFixed(0)} pts',
            Icons.trending_up,
            _getPerformanceColor(avg7Day),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            '30-Day Avg',
            '${avg30Day.toStringAsFixed(0)}%',
            '${avg30DayEarned.toStringAsFixed(0)}/${avg30DayTarget.toStringAsFixed(0)} pts',
            Icons.calendar_month,
            _getPerformanceColor(avg30Day),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title, String value, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
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
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: FlutterFlowTheme.of(context).bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
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

  Widget _buildCalendarHeatmap() {
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
            'Activity Heatmap',
            style: FlutterFlowTheme.of(context).titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          _buildHeatmapGrid(),
          const SizedBox(height: 12),
          _buildHeatmapLegend(),
        ],
      ),
    );
  }

  Widget _buildHeatmapGrid() {
    final today = DateService.currentDate;
    final startDate = today.subtract(const Duration(days: 89)); // ~3 months
    final progressMap = <DateTime, double>{};

    for (final record in _progressHistory) {
      if (record.date != null) {
        progressMap[record.date!] = record.completionPercentage;
      }
    }

    return Wrap(
      spacing: 2,
      runSpacing: 2,
      children: List.generate(90, (index) {
        final date = startDate.add(Duration(days: index));
        final percentage = progressMap[date] ?? 0.0;
        final color = _getHeatmapColor(percentage);

        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildHeatmapLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Less',
          style: FlutterFlowTheme.of(context).bodySmall.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
        Row(
          children: [
            Container(width: 12, height: 12, color: Colors.grey[300]),
            const SizedBox(width: 4),
            Container(width: 12, height: 12, color: Colors.green[200]),
            const SizedBox(width: 4),
            Container(width: 12, height: 12, color: Colors.green[400]),
            const SizedBox(width: 4),
            Container(width: 12, height: 12, color: Colors.green[600]),
            const SizedBox(width: 4),
            Container(width: 12, height: 12, color: Colors.green[800]),
          ],
        ),
        Text(
          'More',
          style: FlutterFlowTheme.of(context).bodySmall.override(
                fontFamily: 'Readex Pro',
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
        ),
      ],
    );
  }

  Widget _buildTrendChart() {
    // Get last 7 days of progress data
    final last7Days = _getLastNDays(7);

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
            child: _build7DayColumnChart(last7Days),
          ),
        ],
      ),
    );
  }

  // Helper methods
  List<DailyProgressRecord> _getLastNDays(int n) {
    final endDate = DateService.currentDate;
    final startDate = endDate.subtract(Duration(days: n));

    return _progressHistory.where((record) {
      if (record.date == null) return false;
      return record.date!.isAfter(startDate) &&
          record.date!.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();
  }

  double _calculateAveragePercentage(List<DailyProgressRecord> records) {
    if (records.isEmpty) return 0.0;
    final total =
        records.fold(0.0, (sum, record) => sum + record.completionPercentage);
    return total / records.length;
  }

  double _calculateAverageTarget(List<DailyProgressRecord> records) {
    if (records.isEmpty) return 0.0;
    final total = records.fold(0.0, (sum, record) => sum + record.targetPoints);
    return total / records.length;
  }

  double _calculateAverageEarned(List<DailyProgressRecord> records) {
    if (records.isEmpty) return 0.0;
    final total = records.fold(0.0, (sum, record) => sum + record.earnedPoints);
    return total / records.length;
  }

  Color _getPerformanceColor(double percentage) {
    if (percentage < 30) return Colors.red;
    if (percentage < 70) return Colors.orange;
    return Colors.green;
  }

  Color _getHeatmapColor(double percentage) {
    if (percentage == 0) return Colors.grey[300]!;
    if (percentage < 25) return Colors.green[200]!;
    if (percentage < 50) return Colors.green[400]!;
    if (percentage < 75) return Colors.green[600]!;
    return Colors.green[800]!;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // Get progress data for a specific date
  DailyProgressRecord? _getProgressForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    try {
      return _progressHistory.firstWhere(
        (record) =>
            record.date != null && _isSameDay(record.date!, normalizedDate),
      );
    } catch (e) {
      return null;
    }
  }

  // Build 7-day column chart
  Widget _build7DayColumnChart(List<DailyProgressRecord> data) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart,
              size: 32,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 8),
            Text(
              'No data available',
              style: FlutterFlowTheme.of(context).bodyMedium.override(
                    fontFamily: 'Readex Pro',
                    color: FlutterFlowTheme.of(context).secondaryText,
                  ),
            ),
          ],
        ),
      );
    }

    // Create data for last 7 days (including today)
    final List<Map<String, dynamic>> chartData = [];
    final today = DateService.currentDate;

    for (int i = 6; i >= 0; i--) {
      final date = today.subtract(Duration(days: i));
      final isToday = _isSameDay(date, today);

      if (isToday) {
        // Use live data from shared state
        chartData.add({
          'date': date,
          'target': _todayTarget,
          'earned': _todayEarned,
          'percentage': _todayPercentage,
          'dayName': 'Today',
        });
      } else {
        // Use historical snapshot from DailyProgressRecord
        final dayData = _getProgressForDate(date);
        chartData.add({
          'date': date,
          'target': dayData?.targetPoints ?? 0.0,
          'earned': dayData?.earnedPoints ?? 0.0,
          'percentage': dayData?.completionPercentage ?? 0.0,
          'dayName': _getDayName(date),
        });
      }
    }

    // Find max target for scaling
    final maxTarget = chartData
        .map((d) => d['target'] as double)
        .reduce((a, b) => a > b ? a : b);
    final maxHeight =
        maxTarget > 0 ? maxTarget : 100.0; // Fallback to 100 if no data

    return Column(
      children: [
        // Chart area
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: chartData.map((dayData) {
              final target = dayData['target'] as double;
              final earned = dayData['earned'] as double;
              final percentage = dayData['percentage'] as double;
              final dayName = dayData['dayName'] as String;

              // Calculate heights
              final targetHeight = (target / maxHeight) * 100;
              final earnedHeight =
                  target > 0 ? (earned / target) * targetHeight : 0.0;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      // Column
                      Expanded(
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // Target bar (background)
                            Container(
                              width: 20,
                              height: targetHeight,
                              decoration: BoxDecoration(
                                color: FlutterFlowTheme.of(context).alternate,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            // Earned bar (foreground)
                            if (earnedHeight > 0)
                              Container(
                                width: 20,
                                height: earnedHeight,
                                decoration: BoxDecoration(
                                  color: _getPerformanceColor(percentage),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Day label
                      Text(
                        dayName,
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              fontSize: 10,
                              color: FlutterFlowTheme.of(context).secondaryText,
                            ),
                        textAlign: TextAlign.center,
                      ),
                      // Percentage
                      Text(
                        '${percentage.toStringAsFixed(0)}%',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _getPerformanceColor(percentage),
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        Row(
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
        ),
      ],
    );
  }

  String _getDayName(DateTime date) {
    final now = DateService.currentDate;
    if (_isSameDay(date, now)) {
      return 'Today';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    } else {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }
  }
}

/// Custom painter for simple line chart
class LineChartPainter extends CustomPainter {
  final List<DailyProgressRecord> data;

  LineChartPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final points = <Offset>[];
    final maxValue = 100.0; // Percentage max
    final minValue = 0.0;

    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height -
          ((data[i].completionPercentage - minValue) / (maxValue - minValue)) *
              size.height;
      points.add(Offset(x, y));
    }

    // Draw line
    for (int i = 0; i < points.length - 1; i++) {
      canvas.drawLine(points[i], points[i + 1], paint);
    }

    // Draw points
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
