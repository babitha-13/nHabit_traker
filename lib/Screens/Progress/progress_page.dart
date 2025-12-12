import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Progress/progress_breakdown_dialog.dart';
import 'package:habit_tracker/Helper/backend/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/cumulative_score_service.dart';
import 'package:habit_tracker/Helper/utils/cumulative_score_line_painter.dart';
import 'package:habit_tracker/Screens/Progress/habit_statistics_tab.dart';
import 'package:habit_tracker/Screens/Progress/category_statistics_tab.dart';
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
  // Live today's progress data
  double _todayTarget = 0.0;
  double _todayEarned = 0.0;
  double _todayPercentage = 0.0;
  // Cumulative score data
  double _cumulativeScore = 0.0;
  double _dailyScoreGain = 0.0;
  List<Map<String, dynamic>> _cumulativeScoreHistory = [];
  bool _show30Days = false;
  // Projected score data for today
  double _projectedCumulativeScore = 0.0;
  double _projectedDailyGain = 0.0;
  bool _hasProjection = false;
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
        // Recalculate projected score when today's progress updates
        _updateProjectedScore();
      }
    });
    // Load initial today's progress
    _loadInitialTodayProgress();
    // Load cumulative score data
    _loadCumulativeScore();
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  void _showProgressBreakdown(BuildContext context, DateTime date) {
    // Check if it's today
    final today = DateService.currentDate;
    if (_isSameDay(date, today)) {
      // Use live data from shared state
      _showTodayBreakdown(context);
    } else {
      // Use historical data
      _showHistoricalBreakdown(context, date);
    }
  }

  void _showTodayBreakdown(BuildContext context) {
    // Show loading dialog while calculating today's breakdown
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Calculating today\'s breakdown...'),
          ],
        ),
      ),
    );

    // Calculate today's breakdown on-demand
    _calculateTodayBreakdown().then((breakdown) {
      Navigator.of(context).pop(); // Close loading dialog
      showDialog(
        context: context,
        builder: (context) => ProgressBreakdownDialog(
          date: DateService.currentDate,
          totalEarned: _todayEarned,
          totalTarget: _todayTarget,
          percentage: _todayPercentage,
          habitBreakdown: breakdown['habitBreakdown'] ?? [],
          taskBreakdown: breakdown['taskBreakdown'] ?? [],
        ),
      );
    }).catchError((error) {
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating today\'s breakdown: $error')),
      );
    });
  }

  void _showHistoricalBreakdown(BuildContext context, DateTime date) {
    final dayData = _getProgressForDate(date);
    if (dayData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available for this date')),
      );
      return;
    }
    // Debug logging
    print('ProgressPage: Showing breakdown for ${date.toIso8601String()}');
    if (dayData.habitBreakdown.isNotEmpty) {}
    if (dayData.taskBreakdown.isNotEmpty) {}
    // If no breakdown data exists, calculate it on-demand
    if (dayData.habitBreakdown.isEmpty && dayData.taskBreakdown.isEmpty) {
      _showCalculatedBreakdown(context, date, dayData);
    } else {
      showDialog(
        context: context,
        builder: (context) => ProgressBreakdownDialog(
          date: date,
          totalEarned: dayData.earnedPoints,
          totalTarget: dayData.targetPoints,
          percentage: dayData.completionPercentage,
          habitBreakdown: dayData.habitBreakdown,
          taskBreakdown: dayData.taskBreakdown,
        ),
      );
    }
  }

  void _showCalculatedBreakdown(
      BuildContext context, DateTime date, DailyProgressRecord dayData) {
    // Show loading dialog while calculating
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Calculating breakdown...'),
          ],
        ),
      ),
    );
    // Calculate breakdown on-demand
    _calculateBreakdownForDate(date).then((breakdown) {
      Navigator.of(context).pop(); // Close loading dialog
      showDialog(
        context: context,
        builder: (context) => ProgressBreakdownDialog(
          date: date,
          totalEarned: dayData.earnedPoints,
          totalTarget: dayData.targetPoints,
          percentage: dayData.completionPercentage,
          habitBreakdown: breakdown['habitBreakdown'] ?? [],
          taskBreakdown: breakdown['taskBreakdown'] ?? [],
        ),
      );
    }).catchError((error) {
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating breakdown: $error')),
      );
    });
  }

  Future<Map<String, dynamic>> _calculateTodayBreakdown() async {
    try {
      final userId = currentUserUid;
      final today = DateService.currentDate;

      // Get all habit instances for today
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit');
      final habitSnapshot = await habitQuery.get();
      final allHabits = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Get all task instances for today
      final taskQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'task');
      final taskSnapshot = await taskQuery.get();
      final allTasks = taskSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();

      // Get categories
      final categoryQuery = CategoryRecord.collectionForUser(userId)
          .where('categoryType', isEqualTo: 'habit');
      final categorySnapshot = await categoryQuery.get();
      final categories = categorySnapshot.docs
          .map((doc) => CategoryRecord.fromSnapshot(doc))
          .toList();

      // Calculate breakdown using the daily progress calculator
      final result = await DailyProgressCalculator.calculateDailyProgress(
        userId: userId,
        targetDate: today,
        allInstances: allHabits,
        categories: categories,
        taskInstances: allTasks,
      );

      // Debug logging to understand the 153% issue
      print('=== TODAY\'S PROGRESS DEBUG ===');
      print('Total Target: ${result['target']}');
      print('Total Earned: ${result['earned']}');
      print('Percentage: ${result['percentage']}%');
      print('Habit Target: ${result['habitTarget']}');
      print('Habit Earned: ${result['habitEarned']}');
      print('Task Target: ${result['taskTarget']}');
      print('Task Earned: ${result['taskEarned']}');

      return {
        'habitBreakdown':
            result['habitBreakdown'] as List<Map<String, dynamic>>? ?? [],
        'taskBreakdown':
            result['taskBreakdown'] as List<Map<String, dynamic>>? ?? [],
      };
    } catch (e) {
      print('Error calculating today\'s breakdown: $e');
      return {
        'habitBreakdown': <Map<String, dynamic>>[],
        'taskBreakdown': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> _calculateBreakdownForDate(DateTime date) async {
    try {
      final userId = currentUserUid;
      // Get all habit instances for the date
      final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'habit');
      final habitSnapshot = await habitQuery.get();
      final allHabits = habitSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      // Get all task instances for the date
      final taskQuery = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateCategoryType', isEqualTo: 'task');
      final taskSnapshot = await taskQuery.get();
      final allTasks = taskSnapshot.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      // Get categories
      final categoryQuery = CategoryRecord.collectionForUser(userId)
          .where('categoryType', isEqualTo: 'habit');
      final categorySnapshot = await categoryQuery.get();
      final categories = categorySnapshot.docs
          .map((doc) => CategoryRecord.fromSnapshot(doc))
          .toList();
      // Calculate breakdown using the daily progress calculator
      final result = await DailyProgressCalculator.calculateDailyProgress(
        userId: userId,
        targetDate: date,
        allInstances: allHabits,
        categories: categories,
        taskInstances: allTasks,
      );
      return {
        'habitBreakdown':
            result['habitBreakdown'] as List<Map<String, dynamic>>? ?? [],
        'taskBreakdown':
            result['taskBreakdown'] as List<Map<String, dynamic>>? ?? [],
      };
    } catch (e) {
      return {
        'habitBreakdown': <Map<String, dynamic>>[],
        'taskBreakdown': <Map<String, dynamic>>[],
      };
    }
  }

  Future<void> _loadProgressHistory() async {
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
      // Load last 90 days of progress data to match heat map range
      final endDate = DateService.currentDate;
      final startDate = endDate.subtract(const Duration(days: 90));
      final query = await DailyProgressRecord.collectionForUser(userId)
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
    } catch (e) {
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

  Future<void> _loadCumulativeScore() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final userStats = await CumulativeScoreService.getCumulativeScore(userId);
      if (userStats != null && mounted) {
        setState(() {
          _cumulativeScore = userStats.cumulativeScore;
          _dailyScoreGain = userStats.lastDailyGain;
        });
      }

      // Calculate projected score for today
      await _updateProjectedScore();

      // Load cumulative score history
      await _loadCumulativeScoreHistory();
    } catch (e) {
      print('Error loading cumulative score: $e');
    }
  }

  Future<void> _updateProjectedScore() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      // Only show projection if today has progress
      if (_todayPercentage > 0) {
        final projectionData =
            await CumulativeScoreService.calculateProjectedDailyScore(
          userId,
          _todayPercentage,
        );

        if (mounted) {
          setState(() {
            _projectedCumulativeScore = projectionData['projectedCumulative'] ?? 0.0;
            _projectedDailyGain = projectionData['projectedGain'] ?? 0.0;
            _hasProjection = true;
          });
          
          // Publish cumulative score to shared state
          TodayProgressState().updateCumulativeScore(
            cumulativeScore: _projectedCumulativeScore,
            dailyGain: _projectedDailyGain,
            hasLiveScore: true,
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _hasProjection = false;
          });
          
          // Publish base cumulative score (without projection)
          TodayProgressState().updateCumulativeScore(
            cumulativeScore: _cumulativeScore,
            dailyGain: _dailyScoreGain,
            hasLiveScore: false,
          );
        }
      }
    } catch (e) {
      print('Error updating projected score: $e');
    }
  }

  Future<void> _loadCumulativeScoreHistory() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final endDate = DateService.currentDate;
      final startDate = endDate.subtract(const Duration(days: 30));

      final query = await DailyProgressRecord.collectionForUser(userId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: false)
          .get();

      final history = <Map<String, dynamic>>[];
      for (final doc in query.docs) {
        final record = DailyProgressRecord.fromSnapshot(doc);
        if (record.cumulativeScoreSnapshot > 0) {
          history.add({
            'date': record.date,
            'score': record.cumulativeScoreSnapshot,
            'gain': record.dailyScoreGain,
          });
        }
      }

      if (mounted) {
        setState(() {
          _cumulativeScoreHistory = history;
        });
      }
    } catch (e) {
      print('Error loading cumulative score history: $e');
    }
  }

  // Removed manual progress generation to avoid unintended side effects.
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
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
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
              Tab(icon: Icon(Icons.list_alt), text: 'Habits'),
              Tab(icon: Icon(Icons.category), text: 'Categories'),
            ],
          ),
        ),
        body: SafeArea(
          top: true,
          child: TabBarView(
            children: [
              // Overview tab (existing content)
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildProgressContent(),
              // Habits tab
              const HabitStatisticsTab(),
              // Categories tab
              const CategoryStatisticsTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressContent() {
    // Show content even if no historical data - we have today's live progress
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCumulativeScoreCard(),
          const SizedBox(height: 16),
          _buildSummaryCards(),
          const SizedBox(height: 24),
          _buildTrendChart(),
        ],
      ),
    );
  }

  // Removed _buildEmptyState - we always show progress (at least today's live data)
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

  Widget _buildCumulativeScoreCard() {
    // Use live score if today has progress, otherwise use stored cumulative score
    final showLive = _hasProjection && _todayPercentage > 0;
    final displayScore = showLive ? _projectedCumulativeScore : _cumulativeScore;
    final displayGain = showLive ? _projectedDailyGain : _dailyScoreGain;
    
    final gainColor = displayGain >= 0 ? Colors.green : Colors.red;
    final gainIcon = displayGain >= 0 ? Icons.trending_up : Icons.trending_down;
    final gainText = displayGain >= 0
        ? '+${displayGain.toStringAsFixed(1)}'
        : displayGain.toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            FlutterFlowTheme.of(context).primary.withOpacity(0.1),
            FlutterFlowTheme.of(context).secondaryBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: FlutterFlowTheme.of(context).primary.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events,
                color: FlutterFlowTheme.of(context).primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Cumulative Score',
                style: FlutterFlowTheme.of(context).titleLarge.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.bold,
                      color: FlutterFlowTheme.of(context).primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayScore.toStringAsFixed(0),
                      style: FlutterFlowTheme.of(context).displaySmall.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.bold,
                            color: FlutterFlowTheme.of(context).primaryText,
                          ),
                    ),
                    Text(
                      'Total Points',
                      style: FlutterFlowTheme.of(context).bodySmall.override(
                            fontFamily: 'Readex Pro',
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Icon(gainIcon, color: gainColor, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        gainText,
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              fontFamily: 'Readex Pro',
                              color: gainColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  Text(
                    'Today',
                    style: FlutterFlowTheme.of(context).bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCumulativeScoreGraph(),
        ],
      ),
    );
  }

  Widget _buildCumulativeScoreGraph() {
    final displayData = _show30Days
        ? _cumulativeScoreHistory
        : _cumulativeScoreHistory.take(7).toList();

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
                _show30Days ? '30-Day Score Trend' : '7-Day Score Trend',
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              GestureDetector(
                onTap: () {
                  setState(() {
                    _show30Days = !_show30Days;
                  });
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _show30Days ? '7D' : '30D',
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
            child: _buildLineChart(displayData),
          ),
        ],
      ),
    );
  }

  Widget _buildLineChart(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox();

    final minScore =
        data.map((d) => d['score'] as double).reduce((a, b) => a < b ? a : b);
    final maxScore =
        data.map((d) => d['score'] as double).reduce((a, b) => a > b ? a : b);
    final scoreRange = maxScore - minScore;

    return CustomPaint(
      painter: CumulativeScoreLinePainter(
        data: data,
        minScore: minScore,
        maxScore: maxScore,
        scoreRange: scoreRange,
        color: FlutterFlowTheme.of(context).primary,
      ),
      size: const Size(double.infinity, double.infinity),
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
    final today = DateService.currentDate;
    // Filter out today's record if it exists in historical data
    final historicalRecords = records.where((record) {
      if (record.date == null) return false;
      return !_isSameDay(record.date!, today);
    }).toList();

    if (historicalRecords.isEmpty) {
      // If no historical data, return today's percentage
      return _todayPercentage;
    }
    // Include today's live data in average
    final total = historicalRecords.fold(
            0.0, (sum, record) => sum + record.completionPercentage) +
        _todayPercentage;
    final count = historicalRecords.length + 1; // +1 for today
    return total / count;
  }

  double _calculateAverageTarget(List<DailyProgressRecord> records) {
    final today = DateService.currentDate;
    // Filter out today's record if it exists in historical data
    final historicalRecords = records.where((record) {
      if (record.date == null) return false;
      return !_isSameDay(record.date!, today);
    }).toList();

    if (historicalRecords.isEmpty) {
      // If no historical data, return today's target
      return _todayTarget;
    }
    // Include today's live data in average
    final total = historicalRecords.fold(
            0.0, (sum, record) => sum + record.targetPoints) +
        _todayTarget;
    final count = historicalRecords.length + 1; // +1 for today
    return total / count;
  }

  double _calculateAverageEarned(List<DailyProgressRecord> records) {
    final today = DateService.currentDate;
    // Filter out today's record if it exists in historical data
    final historicalRecords = records.where((record) {
      if (record.date == null) return false;
      return !_isSameDay(record.date!, today);
    }).toList();

    if (historicalRecords.isEmpty) {
      // If no historical data, return today's earned
      return _todayEarned;
    }
    // Include today's live data in average
    final total = historicalRecords.fold(
            0.0, (sum, record) => sum + record.earnedPoints) +
        _todayEarned;
    final count = historicalRecords.length + 1; // +1 for today
    return total / count;
  }

  Color _getPerformanceColor(double percentage) {
    if (percentage < 30) return Colors.red;
    if (percentage < 70) return Colors.orange;
    return Colors.green;
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
    // Pre-calculate chart data to simplify widget tree for compiler
    final chartData = _prepareChartData();
    
    // Find max target for scaling
    double maxTarget = 100.0;
    if (chartData.isNotEmpty) {
      final maxVal = chartData
          .map((d) => d['target'] as double)
          .reduce((a, b) => a > b ? a : b);
      if (maxVal > 0) maxTarget = maxVal;
    }

    return Column(
      children: [
        // Chart area
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: chartData.map((dayData) {
              return _buildSingleDayColumn(dayData, maxTarget);
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        // Legend
        _buildChartLegend(),
      ],
    );
  }

  List<Map<String, dynamic>> _prepareChartData() {
    final List<Map<String, dynamic>> chartData = [];
    final today = DateService.currentDate;
    
    for (int i = 6; i >= 0; i--) {
      // Use explicit Duration constant to avoid optimization issues
      final date = today.subtract(Duration(days: i));
      final isToday = _isSameDay(date, today);
      
      if (isToday) {
        chartData.add({
          'date': date,
          'target': _todayTarget,
          'earned': _todayEarned,
          'percentage': _todayPercentage,
          'dayName': 'Today',
        });
      } else {
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
    return chartData;
  }

  Widget _buildSingleDayColumn(Map<String, dynamic> dayData, double maxTarget) {
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
            // Column
            Expanded(
              child: GestureDetector(
                onTap: () => _showProgressBreakdown(
                    context, dayData['date'] as DateTime),
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Target bar
                    Container(
                      width: 20,
                      height: targetHeight,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).alternate,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    // Earned bar
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
  }

  Widget _buildChartLegend() {
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
