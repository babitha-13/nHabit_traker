import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/auth/logout_cleanup.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Progress/Pages/progress_breakdown_dialog.dart';
import 'package:habit_tracker/Screens/Progress/backend/progress_page_data_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/aggregate_score_statistics_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/old_score_formula_service.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/old_cumulative_score_calculator.dart';
import 'package:habit_tracker/Helper/Helpers/milestone_service.dart';
import 'package:habit_tracker/Screens/Queue/Queue_charts_section/cumulative_score_line_painter.dart';
import 'package:habit_tracker/Screens/Progress/Pages/habit_statistics_tab.dart';
import 'package:habit_tracker/Screens/Progress/Pages/category_statistics_tab.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Helper/Helpers/sharedPreference.dart';
import 'package:habit_tracker/Helper/Helpers/login_response.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Essential/essential_templates_page_main.dart';
import 'package:habit_tracker/Screens/Settings/notification_settings_page.dart';
import 'package:habit_tracker/Screens/Habits/habits_page.dart';
import 'package:habit_tracker/Screens/Categories/manage_categories.dart';

class ProgressPage extends StatefulWidget {
  const ProgressPage({Key? key}) : super(key: key);
  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<DailyProgressRecord> _progressHistory = [];
  bool _isLoading = true;
  // Progress history range: 7, 30, or 90 days
  int _historyDays = 7; // Start with 7 days for faster initial load
  // Live today's progress data
  double _todayTarget = 0.0;
  double _todayEarned = 0.0;
  double _todayPercentage = 0.0;
  // Cumulative score data
  double _cumulativeScore = 0.0;
  double _dailyScoreGain = 0.0;
  int _achievedMilestones = 0;
  List<Map<String, dynamic>> _cumulativeScoreHistory = [];
  bool _show30Days = false;
  // Projected score data for today
  double _projectedCumulativeScore = 0.0;
  double _projectedDailyGain = 0.0;
  bool _hasProjection = false;
  // Breakdown components for tooltip
  double _dailyScore = 0.0;
  double _consistencyBonus = 0.0;
  double _recoveryBonus = 0.0;
  double _decayPenalty = 0.0;
  double _categoryNeglectPenalty = 0.0;
  // Aggregate statistics
  double _averageDailyScore7Day = 0.0;
  double _averageDailyScore30Day = 0.0;
  double _bestDailyScoreGain = 0.0;
  double _worstDailyScoreGain = 0.0;
  int _positiveDaysCount7Day = 0;
  int _positiveDaysCount30Day = 0;
  double _averageCumulativeScore7Day = 0.0;
  double _averageCumulativeScore30Day = 0.0;
  DateTime?
      _lastKnownDate; // Track last known date for day transition detection
  @override
  void initState() {
    super.initState();
    _lastKnownDate = DateService.todayStart;
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
        // Recalculate today's score when completion points update
        _updateTodayScore();
      }
    });
    // Listen for score updates from Queue page (shared state as source of truth)
    NotificationCenter.addObserver(this, 'cumulativeScoreUpdated', (param) {
      if (mounted) {
        setState(() {
          // Update local state from shared state to trigger UI rebuild
          final data = TodayProgressState().getCumulativeScoreData();
          final hasLiveScore = data['hasLiveScore'] as bool? ?? false;
          _projectedCumulativeScore =
              data['cumulativeScore'] as double? ?? _projectedCumulativeScore;
          _projectedDailyGain =
              data['todayScore'] as double? ?? _projectedDailyGain;
          // Extract breakdown data from shared state (calculated by Queue Page)
          final breakdown = data['breakdown'] as Map<String, double>?;
          if (breakdown != null) {
            _dailyScore = breakdown['dailyScore'] ?? 0.0;
            _consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            _recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            _decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            _categoryNeglectPenalty =
                breakdown['categoryNeglectPenalty'] ?? 0.0;
          }
          // Ensure _hasProjection is set if we have live score
          if (hasLiveScore) {
            _hasProjection = true;
          }
        });
        // Update history with live score
        _updateHistoryWithTodayScore();
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for day transition when page becomes visible
    _checkDayTransition();
  }

  void _checkDayTransition() {
    final today = DateService.todayStart;
    if (_lastKnownDate != null && !_isSameDay(_lastKnownDate!, today)) {
      // Day has changed - reload all data
      _lastKnownDate = today;
      // Invalidate daily progress cache since historical data may have changed
      DailyProgressQueryService.invalidateUserCache(currentUserUid);
      _loadProgressHistory();
      _loadInitialTodayProgress();
      _loadCumulativeScore();
    } else if (_lastKnownDate == null) {
      _lastKnownDate = today;
    }
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
      final userId = await waitForCurrentUserUid();
      final today = DateService.currentDate;

      // Use service to calculate breakdown (encapsulates Firestore access)
      return await ProgressPageDataService.calculateBreakdownForDate(
        userId: userId,
        date: today,
      );
    } catch (e) {
      // Error calculating today's breakdown
      return {
        'habitBreakdown': <Map<String, dynamic>>[],
        'taskBreakdown': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> _calculateBreakdownForDate(DateTime date) async {
    try {
      final userId = await waitForCurrentUserUid();
      // Use service to calculate breakdown (encapsulates Firestore access)
      return await ProgressPageDataService.calculateBreakdownForDate(
        userId: userId,
        date: date,
      );
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
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      // Load at least 30 days of progress data for statistics calculation
      final daysToLoad = _historyDays > 30 ? _historyDays : 30;
      // Use service to fetch progress history (encapsulates Firestore access)
      final progressData = await ProgressPageDataService.fetchProgressHistory(
        userId: userId,
        days: daysToLoad,
      );
      if (mounted) {
        setState(() {
          _progressHistory = progressData;
          _isLoading = false;
        });
        // Recalculate statistics after loading history
        _calculateStatisticsFromHistory();
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
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      // Check shared state first - if queue page already calculated today's score, use it
      final sharedScoreData = TodayProgressState().getCumulativeScoreData();
      final hasLiveScore = sharedScoreData['hasLiveScore'] as bool? ?? false;

      if (hasLiveScore) {
        // Use live score from shared state (calculated by queue page)
        if (mounted) {
          setState(() {
            _projectedCumulativeScore =
                (sharedScoreData['cumulativeScore'] as double?) ?? 0.0;
            _projectedDailyGain =
                (sharedScoreData['todayScore'] as double?) ?? 0.0;
            // Extract breakdown data from shared state (calculated by Queue Page)
            final breakdown =
                sharedScoreData['breakdown'] as Map<String, double>?;
            if (breakdown != null) {
              _dailyScore = breakdown['dailyScore'] ?? 0.0;
              _consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
              _recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
              _decayPenalty = breakdown['decayPenalty'] ?? 0.0;
              _categoryNeglectPenalty =
                  breakdown['categoryNeglectPenalty'] ?? 0.0;
            }
            _hasProjection = true;
          });
        }
      } else {
        // No live score available, load from backend
        final userStats =
            await CumulativeScoreService.getCumulativeScore(userId);
        if (userStats != null && mounted) {
          setState(() {
            _cumulativeScore = userStats.cumulativeScore;

            // Check if the last calculation was today
            final today = DateService.todayStart;
            final lastCalc = userStats.lastCalculationDate;
            final isLastCalcToday = lastCalc != null &&
                lastCalc.year == today.year &&
                lastCalc.month == today.month &&
                lastCalc.day == today.day;

            // If last calculation wasn't today, today's gain is 0 initially,
            // but will be overwritten by _updateTodayScore() below
            _dailyScoreGain = isLastCalcToday ? userStats.lastDailyGain : 0.0;

            // Load aggregate statistics
            _averageDailyScore7Day = userStats.averageDailyScore7Day;
            _averageDailyScore30Day = userStats.averageDailyScore30Day;
            _bestDailyScoreGain = userStats.bestDailyScoreGain;
            _worstDailyScoreGain = userStats.worstDailyScoreGain;
            _positiveDaysCount7Day = userStats.positiveDaysCount7Day;
            _positiveDaysCount30Day = userStats.positiveDaysCount30Day;
            _averageCumulativeScore7Day = userStats.averageCumulativeScore7Day;
            _averageCumulativeScore30Day =
                userStats.averageCumulativeScore30Day;
          });
        }

        // Only calculate if we don't have live score from queue page
        // This avoids duplicate calculations and ensures consistency
        if (!hasLiveScore && _todayPercentage > 0) {
          await _updateTodayScore();
        }
      }

      // Load cumulative score history
      await _loadCumulativeScoreHistory();

      // Calculate statistics from loaded progress history
      await _calculateStatisticsFromHistory();
    } catch (e) {
      // Error loading cumulative score
    }
  }

  Future<void> _updateTodayScore() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      // Check shared state first - queue page may have already calculated the score
      final sharedScoreData = TodayProgressState().getCumulativeScoreData();
      final hasLiveScore = sharedScoreData['hasLiveScore'] as bool? ?? false;

      if (hasLiveScore) {
        // Use live score from shared state (calculated by queue page with full data)
        // This ensures consistency and avoids duplicate calculations
        if (!mounted) return;
        setState(() {
          _projectedCumulativeScore =
              (sharedScoreData['cumulativeScore'] as double?) ?? 0.0;
          _projectedDailyGain =
              (sharedScoreData['todayScore'] as double?) ?? 0.0;
          // Extract breakdown data from shared state (already calculated by Queue Page)
          final breakdown =
              sharedScoreData['breakdown'] as Map<String, double>?;
          if (breakdown != null) {
            _dailyScore = breakdown['dailyScore'] ?? 0.0;
            _consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            _recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            _decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            _categoryNeglectPenalty =
                breakdown['categoryNeglectPenalty'] ?? 0.0;
          }
          _hasProjection = true;
        });
        // Update history with live score
        _updateHistoryWithTodayScore();
        return;
      }

      // No live score available, calculate it ourselves
      // Note: This is a fallback - normally queue page should calculate it first
      // We skip category penalty here since we don't have instances/categories
      // The queue page calculation (with full data) takes precedence via shared state

      final result = await CumulativeScoreCalculator.updateTodayScore(
        userId: userId,
        completionPercentage: _todayPercentage,
        pointsEarned: _todayEarned,
        categories: null, // Skip category penalty (would need instances)
        habitInstances: null,
        includeBreakdown: true,
      );

      if (!mounted) return;
      setState(() {
        _projectedCumulativeScore =
            (result['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
        _projectedDailyGain = (result['todayScore'] as num?)?.toDouble() ?? 0.0;
        _hasProjection = true;

        _dailyScore = (result['dailyScore'] as num?)?.toDouble() ?? 0.0;
        _consistencyBonus =
            (result['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
        _recoveryBonus = (result['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
        _decayPenalty = (result['decayPenalty'] as num?)?.toDouble() ?? 0.0;
        _categoryNeglectPenalty =
            (result['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0;
      });

      // Update history with live score
      _updateHistoryWithTodayScore();
    } catch (e) {
      // Error updating today's score
    }
  }

  Future<void> _loadCumulativeScoreHistory() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      // Check shared state first - use live score from queue page if available
      final sharedScoreData = TodayProgressState().getCumulativeScoreData();
      final hasLiveScore = sharedScoreData['hasLiveScore'] as bool? ?? false;

      double? cumulativeScore;
      double? todayScore;

      if (hasLiveScore) {
        // Use live score from shared state (calculated by queue page)
        cumulativeScore = (sharedScoreData['cumulativeScore'] as double?);
        todayScore = (sharedScoreData['todayScore'] as double?);
      } else if (_hasProjection) {
        // Fallback to local projection if no shared state
        cumulativeScore = _projectedCumulativeScore;
        todayScore = _projectedDailyGain;
      }

      // Load history based on current toggle state (7 or 30 days)
      final daysToLoad = _show30Days ? 30 : 7;
      final historyResult =
          await CumulativeScoreCalculator.loadCumulativeScoreHistory(
        userId: userId,
        days: daysToLoad,
        cumulativeScore: cumulativeScore,
        todayScore: todayScore,
      );
      final history =
          (historyResult['history'] as List?)?.cast<Map<String, dynamic>>() ??
              [];

      if (mounted) {
        setState(() {
          _cumulativeScoreHistory = history;
        });
      }
    } catch (e) {
      // Error loading cumulative score history
    }
  }

  void _updateHistoryWithTodayScore() {
    if (!_hasProjection) return;

    final changed = CumulativeScoreCalculator.updateHistoryWithTodayScore(
      _cumulativeScoreHistory,
      _projectedDailyGain,
      _projectedCumulativeScore,
    );

    if (changed && mounted) {
      setState(() {
        // Trigger rebuild
      });
    }
  }

  Future<void> _calculateStatisticsFromHistory() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      // Use service to calculate statistics (encapsulates business logic)
      // Service queries DailyProgressRecord directly (more efficient) and uses effective gain
      final stats =
          await AggregateScoreStatisticsService.calculateStatisticsFromHistory(
        userId: userId,
        progressHistory: _progressHistory, // Optional, service queries directly
        projectedCumulativeScore: _hasProjection && _todayPercentage > 0
            ? _projectedCumulativeScore
            : null,
        projectedDailyGain:
            _hasProjection && _todayPercentage > 0 ? _projectedDailyGain : null,
        cumulativeScore: _cumulativeScore,
        dailyScoreGain: _dailyScoreGain,
        todayPercentage: _todayPercentage,
        hasProjection: _hasProjection && _todayPercentage > 0,
      );

      if (mounted) {
        setState(() {
          _averageDailyScore7Day = stats['averageDailyScore7Day'] as double;
          _averageDailyScore30Day = stats['averageDailyScore30Day'] as double;
          _bestDailyScoreGain = stats['bestDailyScoreGain'] as double;
          _worstDailyScoreGain = stats['worstDailyScoreGain'] as double;
          _positiveDaysCount7Day = stats['positiveDaysCount7Day'] as int;
          _positiveDaysCount30Day = stats['positiveDaysCount30Day'] as int;
          _averageCumulativeScore7Day =
              stats['averageCumulativeScore7Day'] as double;
          _averageCumulativeScore30Day =
              stats['averageCumulativeScore30Day'] as double;
        });
      }
    } catch (e) {
      // Error calculating statistics from history
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
        drawer: _buildDrawer(context),
        appBar: AppBar(
          backgroundColor: FlutterFlowTheme.of(context).primary,
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
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
            // History range selector
            PopupMenuButton<int>(
              icon: const Icon(Icons.calendar_today, color: Colors.white),
              tooltip: 'History Range',
              onSelected: (days) {
                if (days != _historyDays) {
                  setState(() {
                    _historyDays = days;
                  });
                  _loadProgressHistory();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 7,
                  child: Text('Last 7 days'),
                ),
                const PopupMenuItem(
                  value: 30,
                  child: Text('Last 30 days'),
                ),
                const PopupMenuItem(
                  value: 90,
                  child: Text('Last 90 days'),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadProgressHistory,
              tooltip: 'Refresh',
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
          const SizedBox(height: 16),
          _buildAggregateStatsSection(),
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

  Widget _buildAggregateStatsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Score Statistics',
          style: FlutterFlowTheme.of(context).titleMedium.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 12),
        // Daily Score Statistics Row
        Row(
          children: [
            Expanded(
              child: _buildAggregateStatCard(
                'Avg Daily Score (7d)',
                _averageDailyScore7Day.toStringAsFixed(1),
                Icons.trending_up,
                _averageDailyScore7Day >= 0 ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAggregateStatCard(
                'Avg Daily Score (30d)',
                _averageDailyScore30Day.toStringAsFixed(1),
                Icons.calendar_month,
                _averageDailyScore30Day >= 0 ? Colors.green : Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Best/Worst Row
        Row(
          children: [
            Expanded(
              child: _buildAggregateStatCard(
                'Best Day',
                _bestDailyScoreGain.toStringAsFixed(1),
                Icons.arrow_upward,
                Colors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAggregateStatCard(
                'Worst Day',
                _worstDailyScoreGain.toStringAsFixed(1),
                Icons.arrow_downward,
                Colors.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Positive Days Row
        Row(
          children: [
            Expanded(
              child: _buildAggregateStatCard(
                'Positive Days (7d)',
                '$_positiveDaysCount7Day/7',
                Icons.check_circle,
                _positiveDaysCount7Day >= 5 ? Colors.green : Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAggregateStatCard(
                'Positive Days (30d)',
                '$_positiveDaysCount30Day/30',
                Icons.check_circle_outline,
                _positiveDaysCount30Day >= 20 ? Colors.green : Colors.orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Average Cumulative Score Row
        Row(
          children: [
            Expanded(
              child: _buildAggregateStatCard(
                'Avg Cumulative (7d)',
                _averageCumulativeScore7Day.toStringAsFixed(0),
                Icons.bar_chart,
                FlutterFlowTheme.of(context).primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAggregateStatCard(
                'Avg Cumulative (30d)',
                _averageCumulativeScore30Day.toStringAsFixed(0),
                Icons.assessment,
                FlutterFlowTheme.of(context).primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAggregateStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
            style: FlutterFlowTheme.of(context).bodyLarge.override(
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
                  fontSize: 10,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
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
    // Use shared state as single source of truth for consistency with Queue page
    final sharedData = TodayProgressState().getCumulativeScoreData();
    final displayScore =
        sharedData['cumulativeScore'] as double? ?? _projectedCumulativeScore;

    // Calculate daily gain consistently: today's score (from graph) - yesterday's score (from graph history)
    // This ensures both pages show the same value and matches the graph trend exactly
    final todayScore = _cumulativeScoreHistory.isNotEmpty
        ? (_cumulativeScoreHistory.last['score'] as double)
        : displayScore;
    double displayGain = 0.0;
    if (_cumulativeScoreHistory.length >= 2) {
      // Use yesterday's score from history to match the graph
      final yesterdayScore =
          _cumulativeScoreHistory[_cumulativeScoreHistory.length - 2]['score']
              as double;
      displayGain = todayScore - yesterdayScore;
    } else if (_cumulativeScoreHistory.length == 1) {
      // Only one day in history, can't calculate difference - use fallback
      displayGain = sharedData['dailyGain'] as double? ?? _projectedDailyGain;
    }

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
              Tooltip(
                message: 'Tap to see score breakdown',
                child: GestureDetector(
                  onTap: () => _showScoreBreakdownDialog(displayGain),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          Icon(gainIcon, color: gainColor, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            gainText,
                            style: FlutterFlowTheme.of(context)
                                .bodyMedium
                                .override(
                                  fontFamily: 'Readex Pro',
                                  color: gainColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.info_outline,
                            color: gainColor,
                            size: 14,
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
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMilestoneProgress(displayScore),
          const SizedBox(height: 12),
          _buildCumulativeScoreGraph(),
        ],
      ),
    );
  }

  void _showScoreBreakdownDialog(double displayGain) {
    // Try to get breakdown from shared state first (calculated by Queue Page)
    // This ensures consistency - same calculation, same result
    Future<void> ensureBreakdownLoaded() async {
      // Check if breakdown is already loaded from shared state
      final sharedData = TodayProgressState().getCumulativeScoreData();
      final breakdown = sharedData['breakdown'] as Map<String, double>?;

      if (breakdown != null && breakdown.isNotEmpty) {
        // Breakdown already available from shared state, use it
        if (mounted) {
          setState(() {
            _dailyScore = breakdown['dailyScore'] ?? 0.0;
            _consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            _recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            _decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            _categoryNeglectPenalty =
                breakdown['categoryNeglectPenalty'] ?? 0.0;
          });
        }
        return;
      }

      // Fallback: Only recalculate if breakdown is truly missing
      // This should rarely happen if Queue Page is active
      if (_hasProjection &&
          _dailyScore == 0.0 &&
          _consistencyBonus == 0.0 &&
          _recoveryBonus == 0.0 &&
          _decayPenalty == 0.0 &&
          _categoryNeglectPenalty == 0.0 &&
          _projectedDailyGain != 0.0) {
        try {
          final userId = await waitForCurrentUserUid();
          if (userId.isEmpty) return;

          // Fetch instances and categories for accurate penalty calculation
          final instancesData =
              await ProgressPageDataService.fetchInstancesForBreakdown(
                  userId: userId);
          final categories =
              instancesData['categories'] as List<CategoryRecord>;
          final habitInstances =
              instancesData['habits'] as List<ActivityInstanceRecord>;

          final result = await CumulativeScoreCalculator.updateTodayScore(
            userId: userId,
            completionPercentage: _todayPercentage,
            pointsEarned: _todayEarned,
            categories: categories,
            habitInstances: habitInstances,
            includeBreakdown: true,
            updateSharedState:
                false, // Don't overwrite if Queue Page has calculated
          );

          if (mounted) {
            setState(() {
              _dailyScore = (result['dailyScore'] as num?)?.toDouble() ?? 0.0;
              _consistencyBonus =
                  (result['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
              _recoveryBonus =
                  (result['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
              _decayPenalty =
                  (result['decayPenalty'] as num?)?.toDouble() ?? 0.0;
              _categoryNeglectPenalty =
                  (result['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0;
            });
          }
        } catch (e) {
          // Error calculating breakdown - will show 0 values
        }
      }
    }

    // Always refresh breakdown from shared state before showing dialog
    // This ensures we have the latest breakdown calculated by Queue Page
    final sharedData = TodayProgressState().getCumulativeScoreData();
    final breakdown = sharedData['breakdown'] as Map<String, double>?;
    if (breakdown != null && breakdown.isNotEmpty && mounted) {
      setState(() {
        _dailyScore = breakdown['dailyScore'] ?? 0.0;
        _consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
        _recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
        _decayPenalty = breakdown['decayPenalty'] ?? 0.0;
        _categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
      });
    }

    // Load breakdown if needed, then show dialog
    ensureBreakdownLoaded().then((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              // Re-check breakdown after async load
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _hasProjection) {
                  final totalCheck = _dailyScore +
                      _consistencyBonus +
                      _recoveryBonus -
                      _decayPenalty -
                      _categoryNeglectPenalty;
                  // If breakdown was just loaded, update dialog
                  if (totalCheck != 0.0 || _projectedDailyGain != 0.0) {
                    setDialogState(() {});
                  }
                }
              });

              return Dialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Score Breakdown',
                            style: FlutterFlowTheme.of(context)
                                .titleLarge
                                .override(
                                  fontFamily: 'Readex Pro',
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Breakdown items
                      if (_hasProjection) ...[
                        _buildBreakdownRow(
                          context,
                          'Completion Score',
                          _dailyScore,
                          Colors.blue,
                        ),
                        if (_consistencyBonus > 0)
                          _buildBreakdownRow(
                            context,
                            'Consistency Bonus',
                            _consistencyBonus,
                            Colors.green,
                          ),
                        if (_recoveryBonus > 0)
                          _buildBreakdownRow(
                            context,
                            'Recovery Bonus',
                            _recoveryBonus,
                            Colors.green,
                          ),
                        if (_decayPenalty != 0)
                          _buildBreakdownRow(
                            context,
                            'Low Performance Penalty',
                            -_decayPenalty,
                            Colors.red,
                          ),
                        if (_categoryNeglectPenalty != 0)
                          _buildBreakdownRow(
                            context,
                            'Category Neglect Penalty',
                            -_categoryNeglectPenalty,
                            Colors.red,
                          ),
                      ] else ...[
                        Text(
                          'Breakdown available only for today\'s live score',
                          style: FlutterFlowTheme.of(context)
                              .bodyMedium
                              .override(
                                fontFamily: 'Readex Pro',
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Total - calculate from breakdown items to ensure accuracy
                      Builder(
                        builder: (context) {
                          // Calculate total from all breakdown items
                          final totalFromBreakdown = _dailyScore +
                              _consistencyBonus +
                              _recoveryBonus -
                              _decayPenalty -
                              _categoryNeglectPenalty;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context)
                                  .primary
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Total Change',
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  totalFromBreakdown >= 0
                                      ? '+${totalFromBreakdown.toStringAsFixed(1)}'
                                      : totalFromBreakdown.toStringAsFixed(1),
                                  style: FlutterFlowTheme.of(context)
                                      .bodyMedium
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontWeight: FontWeight.bold,
                                        color: totalFromBreakdown >= 0
                                            ? Colors.green
                                            : Colors.red,
                                      ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    });
  }

  Widget _buildBreakdownRow(
    BuildContext context,
    String label,
    double value,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                ),
          ),
          Text(
            value >= 0
                ? '+${value.toStringAsFixed(1)}'
                : value.toStringAsFixed(1),
            style: FlutterFlowTheme.of(context).bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneProgress(double currentScore) {
    final nextMilestone = MilestoneService.getNextMilestone(currentScore);
    final progress = MilestoneService.getProgressToNextMilestone(currentScore);
    final achievedMilestones =
        MilestoneService.getAchievedMilestones(_achievedMilestones);

    if (nextMilestone == null) {
      // All milestones achieved
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.amber.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'All Milestones Achieved! 🎉',
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade800,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final pointsToNext = nextMilestone - currentScore;
    final progressPercent = (progress * 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).alternate.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Next Milestone: $nextMilestone points',
                style: FlutterFlowTheme.of(context).bodyMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                '$progressPercent%',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      fontFamily: 'Readex Pro',
                      color: FlutterFlowTheme.of(context).primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor:
                  FlutterFlowTheme.of(context).alternate.withOpacity(0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                FlutterFlowTheme.of(context).primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${currentScore.toStringAsFixed(1)} / $nextMilestone',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      fontFamily: 'Readex Pro',
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
              ),
              Text(
                '${pointsToNext.toStringAsFixed(1)} points to go',
                style: FlutterFlowTheme.of(context).bodySmall.override(
                      fontFamily: 'Readex Pro',
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
              ),
            ],
          ),
          if (achievedMilestones.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: achievedMilestones.map((milestone) {
                final isMajor = MilestoneService.isMajorMilestone(milestone);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isMajor
                        ? Colors.amber.withOpacity(0.2)
                        : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isMajor
                          ? Colors.amber.withOpacity(0.5)
                          : Colors.blue.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isMajor ? Icons.emoji_events : Icons.star,
                        size: 14,
                        color: isMajor
                            ? Colors.amber.shade800
                            : Colors.blue.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$milestone',
                        style: FlutterFlowTheme.of(context).bodySmall.override(
                              fontFamily: 'Readex Pro',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isMajor
                                  ? Colors.amber.shade800
                                  : Colors.blue.shade800,
                            ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCumulativeScoreGraph() {
    // History is already loaded with the correct number of days based on _show30Days
    // Just use it directly - no need to filter
    final displayData = _cumulativeScoreHistory;

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
                  // Reload history with the new day range
                  _loadCumulativeScoreHistory();
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

    final scores = data.map((d) => d['score'] as double).toList();
    final minScore = scores.reduce((a, b) => a < b ? a : b);
    final maxScore = scores.reduce((a, b) => a > b ? a : b);
    // Adjust maxScore to ensure proper rendering when all values are the same
    final adjustedMaxScore = maxScore == minScore ? minScore + 10.0 : maxScore;
    final adjustedRange = adjustedMaxScore - minScore;

    // Generate scale labels (3-5 labels)
    final numLabels = 5;
    final scaleLabels = <double>[];
    for (int i = 0; i < numLabels; i++) {
      final value = minScore + (adjustedRange * i / (numLabels - 1));
      scaleLabels.add(value);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Y-axis scale labels
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
        // Chart
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

  Widget _buildDrawer(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final SharedPref sharedPref = SharedPref();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: theme.primary,
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Today',
                          style: theme.headlineSmall.override(
                            fontFamily: 'Outfit',
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          currentUserEmail.isNotEmpty
                              ? currentUserEmail
                              : "email",
                          style: theme.bodyMedium.override(
                            fontFamily: 'Readex Pro',
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: [
                        _DrawerItem(
                          icon: Icons.home,
                          label: 'Home',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.pushReplacementNamed(context, home);
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.repeat,
                          label: 'Habits',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const HabitsPage(showCompleted: true),
                              ),
                            );
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.category,
                          label: 'Manage Categories',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const ManageCategories(),
                              ),
                            );
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.monitor_heart,
                          label: 'Essential Activities',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const essentialTemplatesPage(),
                              ),
                            );
                          },
                        ),
                        _DrawerItem(
                          icon: Icons.trending_up,
                          label: 'Progress History',
                          onTap: () {
                            Navigator.pop(context);
                            // Already on Progress History page, just close drawer
                          },
                        ),
                        // Development/Testing only - show in debug mode
                        if (kDebugMode) ...[
                          _DrawerItem(
                            icon: Icons.science,
                            label: 'Testing Tools',
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SimpleTestingPage(),
                                ),
                              );
                            },
                          ),
                        ],
                        const Divider(),
                        _DrawerItem(
                          icon: Icons.settings,
                          label: 'Settings',
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    const NotificationSettingsPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _DrawerItem(
              icon: Icons.logout,
              label: 'Log Out',
              onTap: () async {
                await performLogout(
                  sharedPref: sharedPref,
                  onLoggedOut: () async {
                    users = LoginResponse();
                    if (!context.mounted) return;
                    Navigator.pushReplacementNamed(context, login);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
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

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.primary),
      title: Text(label, style: theme.bodyLarge),
      onTap: onTap,
    );
  }
}
