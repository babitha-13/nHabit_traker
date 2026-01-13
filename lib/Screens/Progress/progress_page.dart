import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Testing/simple_testing_page.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/backend/today_progress_state.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Progress/progress_breakdown_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/Point_system_helper/daily_progress_calculator.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Screens/Progress/cumulative_score_service.dart';
import 'package:habit_tracker/Helper/backend/milestone_service.dart';
import 'package:habit_tracker/Screens/Shared/cumulative_score_line_painter.dart';
import 'package:habit_tracker/Screens/Progress/habit_statistics_tab.dart';
import 'package:habit_tracker/Screens/Progress/category_statistics_tab.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/Helpers/constants.dart';
import 'package:habit_tracker/Helper/Helpers/sharedPreference.dart';
import 'package:habit_tracker/Helper/Response/login_response.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Essential/essential_templates_page_main.dart';
import 'package:habit_tracker/Screens/Settings/notification_settings_page.dart';
import 'package:habit_tracker/Screens/Habits/habits_page.dart';
import 'package:habit_tracker/Screens/Categories/manage_categories.dart';
import 'package:intl/intl.dart';

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
  double _scoreGrowthRate7Day = 0.0;
  double _scoreGrowthRate30Day = 0.0;
  double _averageCumulativeScore7Day = 0.0;
  double _averageCumulativeScore30Day = 0.0;
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
    // Listen for cumulative score updates from Queue page (shared state as source of truth)
    NotificationCenter.addObserver(this, 'cumulativeScoreUpdated', (param) {
      if (mounted) {
        setState(() {
          // Update local state from shared state to trigger UI rebuild
          final data = TodayProgressState().getCumulativeScoreData();
          _projectedCumulativeScore =
              data['cumulativeScore'] as double? ?? _projectedCumulativeScore;
          _projectedDailyGain =
              data['dailyGain'] as double? ?? _projectedDailyGain;
        });
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

      return {
        'habitBreakdown':
            result['habitBreakdown'] as List<Map<String, dynamic>>? ?? [],
        'taskBreakdown':
            result['taskBreakdown'] as List<Map<String, dynamic>>? ?? [],
      };
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
      // Load at least 30 days of progress data for statistics calculation
      final endDate = DateService.currentDate;
      final daysToLoad = _historyDays > 30 ? _historyDays : 30;
      final startDate = endDate.subtract(Duration(days: daysToLoad));
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
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final userStats = await CumulativeScoreService.getCumulativeScore(userId);
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
          // but will be overwritten by _updateProjectedScore() below
          _dailyScoreGain = isLastCalcToday ? userStats.lastDailyGain : 0.0;

          // Load aggregate statistics
          _averageDailyScore7Day = userStats.averageDailyScore7Day;
          _averageDailyScore30Day = userStats.averageDailyScore30Day;
          _bestDailyScoreGain = userStats.bestDailyScoreGain;
          _worstDailyScoreGain = userStats.worstDailyScoreGain;
          _positiveDaysCount7Day = userStats.positiveDaysCount7Day;
          _positiveDaysCount30Day = userStats.positiveDaysCount30Day;
          _scoreGrowthRate7Day = userStats.scoreGrowthRate7Day;
          _scoreGrowthRate30Day = userStats.scoreGrowthRate30Day;
          _averageCumulativeScore7Day = userStats.averageCumulativeScore7Day;
          _averageCumulativeScore30Day = userStats.averageCumulativeScore30Day;
        });
      }

      // Always calculate/update projected score for today (handles midnight reset correctly)
      await _updateProjectedScore();

      // Load cumulative score history
      await _loadCumulativeScoreHistory();

      // Calculate statistics from loaded progress history
      await _calculateStatisticsFromHistory();
    } catch (e) {
      // Error loading cumulative score
    }
  }

  Future<void> _updateProjectedScore() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      // Always show projection based on today's current progress (even if 0)
      final projectionData =
          await CumulativeScoreService.calculateProjectedDailyScore(
        userId,
        _todayPercentage,
        _todayEarned,
      );

      if (mounted) {
        setState(() {
          _projectedCumulativeScore =
              projectionData['projectedCumulative'] ?? 0.0;
          _projectedDailyGain = projectionData['projectedGain'] ?? 0.0;
          _hasProjection = true;
          // Store breakdown components for tooltip
          _dailyScore =
              (projectionData['dailyScore'] as num?)?.toDouble() ?? 0.0;
          _consistencyBonus =
              (projectionData['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
          _recoveryBonus =
              (projectionData['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
          _decayPenalty =
              (projectionData['decayPenalty'] as num?)?.toDouble() ?? 0.0;
          _categoryNeglectPenalty =
              0.0; // Not included in projected score calculation
        });

        // Publish cumulative score to shared state
        TodayProgressState().updateCumulativeScore(
          cumulativeScore: _projectedCumulativeScore,
          dailyGain: _projectedDailyGain,
          hasLiveScore: true,
        );

        // Update today's entry in history if available
        _updateTodayInHistory();
      }
    } catch (e) {
      // Error updating projected score
    }
  }

  Future<void> _loadCumulativeScoreHistory() async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      // Use todayStart for consistent midnight-to-midnight querying
      final endDate = DateService.todayStart;
      final startDate = endDate.subtract(const Duration(days: 30));

      final query = await DailyProgressRecord.collectionForUser(userId)
          .where('date', isGreaterThanOrEqualTo: startDate)
          .where('date', isLessThanOrEqualTo: endDate)
          .orderBy('date', descending: false)
          .get();

      // Create a map for quick lookup of existing records
      final recordMap = <String, DailyProgressRecord>{};
      for (final doc in query.docs) {
        final record = DailyProgressRecord.fromSnapshot(doc);
        if (record.date != null) {
          final dateKey = DateFormat('yyyy-MM-dd').format(record.date!);
          recordMap[dateKey] = record;
        }
      }

      final history = <Map<String, dynamic>>[];

      double lastKnownScore = 0.0;

      // Fetch the last record BEFORE the start date to get the baseline score
      try {
        final lastPriorRecordQuery =
            await DailyProgressRecord.collectionForUser(userId)
                .where('date', isLessThan: startDate)
                .orderBy('date', descending: true)
                .limit(1)
                .get();

        if (lastPriorRecordQuery.docs.isNotEmpty) {
          final priorRec =
              DailyProgressRecord.fromSnapshot(lastPriorRecordQuery.docs.first);
          if (priorRec.cumulativeScoreSnapshot > 0) {
            lastKnownScore = priorRec.cumulativeScoreSnapshot;
          }
        } else {
          // If no prior record exists, use the first record in our current range as baseline
          if (recordMap.isNotEmpty) {
            final sortedDates = recordMap.keys.toList()..sort();
            final firstRecord = recordMap[sortedDates.first]!;
            if (firstRecord.cumulativeScoreSnapshot > 0) {
              // Use the score from the day BEFORE the first record
              lastKnownScore = firstRecord.cumulativeScoreSnapshot -
                  firstRecord.dailyScoreGain;
              if (lastKnownScore < 0) lastKnownScore = 0;
            }
          }
        }
      } catch (e) {
        // Error fetching prior cumulative score
      }

      // Iterate day by day from startDate to endDate (30 days)
      for (int i = 0; i <= 30; i++) {
        final date = startDate.add(Duration(days: i));
        final dateKey = DateFormat('yyyy-MM-dd').format(date);

        if (recordMap.containsKey(dateKey)) {
          final record = recordMap[dateKey]!;
          // Use cumulativeScoreSnapshot if available, otherwise calculate from lastKnownScore
          if (record.cumulativeScoreSnapshot > 0) {
            lastKnownScore = record.cumulativeScoreSnapshot;
          } else if (record.hasDailyScoreGain()) {
            // If no snapshot but has gain, calculate from last known score
            lastKnownScore = (lastKnownScore + record.dailyScoreGain)
                .clamp(0.0, double.infinity);
          }
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': record.dailyScoreGain,
          });
        } else {
          // No record for this day, carry forward the last cumulative score
          history.add({
            'date': date,
            'score': lastKnownScore,
            'gain': 0.0,
          });
        }
      }

      // Update today's entry with live score if available
      if (history.isNotEmpty) {
        final lastItem = history.last;
        final lastDate = lastItem['date'] as DateTime;
        final today = DateService.currentDate;

        if (lastDate.year == today.year &&
            lastDate.month == today.month &&
            lastDate.day == today.day) {
          // Always use projected score for today if available (matches Queue page behavior)
          // This ensures the graph shows today's live progress, even if score is 0 or negative
          if (_hasProjection) {
            history[history.length - 1] = {
              'date': lastDate,
              'score': _projectedCumulativeScore,
              'gain': _projectedDailyGain,
            };
          } else if (_cumulativeScore > 0) {
            // Fallback to snapshot score only if projection not available
            history[history.length - 1] = {
              'date': lastDate,
              'score': _cumulativeScore,
              'gain': _dailyScoreGain,
            };
          }
        }
      }

      if (mounted) {
        setState(() {
          _cumulativeScoreHistory = history;
        });
      }
    } catch (e) {
      // Error loading cumulative score history
    }
  }

  void _updateTodayInHistory() {
    if (_cumulativeScoreHistory.isEmpty) return;

    final today = DateService.currentDate;
    final lastItem = _cumulativeScoreHistory.last;
    final lastDate = lastItem['date'] as DateTime;

    if (lastDate.year == today.year &&
        lastDate.month == today.month &&
        lastDate.day == today.day) {
      // Always use projected score for today if available (matches Queue page behavior)
      // This ensures the graph shows today's live progress, even if score is 0 or negative
      if (_hasProjection) {
        _cumulativeScoreHistory[_cumulativeScoreHistory.length - 1] = {
          'date': lastDate,
          'score': _projectedCumulativeScore,
          'gain': _projectedDailyGain,
        };
      } else if (_cumulativeScore > 0) {
        // Fallback to snapshot score only if projection not available
        _cumulativeScoreHistory[_cumulativeScoreHistory.length - 1] = {
          'date': lastDate,
          'score': _cumulativeScore,
          'gain': _dailyScoreGain,
        };
      }
      if (mounted) {
        setState(() {
          // Trigger rebuild
        });
      }
    }
  }

  /// Calculate effective gain for a day
  /// If previous cumulative was 0 and gain is negative, it's ineffective (return 0)
  /// Otherwise, use actual gain
  double _getEffectiveGain(double previousCumulative, double dailyGain) {
    // If previous cumulative was 0 and gain is negative, it's ineffective
    if (previousCumulative <= 0 && dailyGain < 0) {
      return 0.0;
    }
    // Otherwise, use actual gain
    return dailyGain;
  }

  Future<void> _calculateStatisticsFromHistory() async {
    try {
      if (_progressHistory.isEmpty) return;

      final today = DateService.currentDate;
      final cutoff7Days = today.subtract(const Duration(days: 6));
      final cutoff30Days = today.subtract(const Duration(days: 29));

      // Filter and sort records for last 30 days (we need 30 for both 7d and 30d stats)
      final last30DaysRecords = _progressHistory.where((record) {
        if (record.date == null) return false;
        return !record.date!.isBefore(cutoff30Days) &&
            !record.date!.isAfter(today);
      }).toList();

      // Sort by date ascending to process chronologically
      last30DaysRecords.sort((a, b) {
        if (a.date == null || b.date == null) return 0;
        return a.date!.compareTo(b.date!);
      });

      // Build day-by-day data structure with effective gains
      final dayData = <Map<String, dynamic>>[];
      double previousCumulative = 0.0;

      // Process historical records
      for (final record in last30DaysRecords) {
        if (!record.hasDailyScoreGain()) continue;

        final recordDate = record.date!;
        final actualGain = record.dailyScoreGain;
        final effectiveGain = _getEffectiveGain(previousCumulative, actualGain);
        final cumulativeAtStart = previousCumulative;
        final cumulativeAtEnd = record.cumulativeScoreSnapshot;

        dayData.add({
          'date': recordDate,
          'actualGain': actualGain,
          'effectiveGain': effectiveGain,
          'cumulativeAtStart': cumulativeAtStart,
          'cumulativeAtEnd': cumulativeAtEnd,
        });

        // Update previous cumulative for next iteration
        previousCumulative = cumulativeAtEnd;
      }

      // Add today's data if available
      final todayDate = DateTime(today.year, today.month, today.day);
      final isTodayInRange =
          !todayDate.isBefore(cutoff30Days) && !todayDate.isAfter(today);

      if (isTodayInRange) {
        // Get today's gain and cumulative score
        double todayActualGain = 0.0;
        double todayCumulative = 0.0;

        if (_hasProjection && _todayPercentage > 0) {
          todayActualGain = _projectedDailyGain;
          todayCumulative = _projectedCumulativeScore;
        } else {
          todayActualGain = _dailyScoreGain;
          todayCumulative = _cumulativeScore;
        }

        // Only add today if we have valid data
        if (todayActualGain != 0.0 || todayCumulative > 0.0) {
          final todayEffectiveGain =
              _getEffectiveGain(previousCumulative, todayActualGain);
          final todayCumulativeAtEnd = todayCumulative;

          dayData.add({
            'date': todayDate,
            'actualGain': todayActualGain,
            'effectiveGain': todayEffectiveGain,
            'cumulativeAtStart': previousCumulative,
            'cumulativeAtEnd': todayCumulativeAtEnd,
          });
        }
      }

      // Filter for 7-day and 30-day periods
      final dayData7Days = dayData.where((day) {
        final dayDate = day['date'] as DateTime;
        return !dayDate.isBefore(cutoff7Days) && !dayDate.isAfter(today);
      }).toList();

      final dayData30Days = dayData;

      // Calculate averages using effective gains
      double avg7Day = 0.0;
      double avg30Day = 0.0;
      if (dayData7Days.isNotEmpty) {
        final effectiveGains7 =
            dayData7Days.map((d) => d['effectiveGain'] as double).toList();
        avg7Day = effectiveGains7.fold(0.0, (sum, gain) => sum + gain) /
            effectiveGains7.length;
      }
      if (dayData30Days.isNotEmpty) {
        final effectiveGains30 =
            dayData30Days.map((d) => d['effectiveGain'] as double).toList();
        avg30Day = effectiveGains30.fold(0.0, (sum, gain) => sum + gain) /
            effectiveGains30.length;
      }

      // Calculate best/worst from actual gains (not effective)
      double bestDay = 0.0;
      double worstDay = 0.0;
      if (dayData30Days.isNotEmpty) {
        final actualGains30 =
            dayData30Days.map((d) => d['actualGain'] as double).toList();
        bestDay = actualGains30.reduce((a, b) => a > b ? a : b);
        worstDay = actualGains30.reduce((a, b) => a < b ? a : b);
      }

      // Calculate positive days count using effective gains
      final positive7Day =
          dayData7Days.where((d) => (d['effectiveGain'] as double) > 0).length;
      final positive30Day =
          dayData30Days.where((d) => (d['effectiveGain'] as double) > 0).length;

      // Calculate average cumulative scores
      double avgCumulative7Day = 0.0;
      double avgCumulative30Day = 0.0;
      if (dayData7Days.isNotEmpty) {
        final cumulativeScores7 = dayData7Days
            .where((d) => (d['cumulativeAtEnd'] as double) > 0)
            .map((d) => d['cumulativeAtEnd'] as double)
            .toList();
        if (cumulativeScores7.isNotEmpty) {
          avgCumulative7Day =
              cumulativeScores7.fold(0.0, (sum, score) => sum + score) /
                  cumulativeScores7.length;
        }
      }
      if (dayData30Days.isNotEmpty) {
        final cumulativeScores30 = dayData30Days
            .where((d) => (d['cumulativeAtEnd'] as double) > 0)
            .map((d) => d['cumulativeAtEnd'] as double)
            .toList();
        if (cumulativeScores30.isNotEmpty) {
          avgCumulative30Day =
              cumulativeScores30.fold(0.0, (sum, score) => sum + score) /
                  cumulativeScores30.length;
        }
      }

      // Calculate growth rates (same as average of effective gains)
      double growthRate7Day = avg7Day;
      double growthRate30Day = avg30Day;

      if (mounted) {
        setState(() {
          _averageDailyScore7Day = avg7Day;
          _averageDailyScore30Day = avg30Day;
          _bestDailyScoreGain = bestDay;
          _worstDailyScoreGain = worstDay;
          _positiveDaysCount7Day = positive7Day;
          _positiveDaysCount30Day = positive30Day;
          _scoreGrowthRate7Day = growthRate7Day;
          _scoreGrowthRate30Day = growthRate30Day;
          _averageCumulativeScore7Day = avgCumulative7Day;
          _averageCumulativeScore30Day = avgCumulative30Day;
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
        // Growth Rate Row
        Row(
          children: [
            Expanded(
              child: _buildAggregateStatCard(
                'Growth Rate (7d)',
                '${_scoreGrowthRate7Day >= 0 ? '+' : ''}${_scoreGrowthRate7Day.toStringAsFixed(2)}',
                Icons.show_chart,
                _scoreGrowthRate7Day >= 0 ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildAggregateStatCard(
                'Growth Rate (30d)',
                '${_scoreGrowthRate30Day >= 0 ? '+' : ''}${_scoreGrowthRate30Day.toStringAsFixed(2)}',
                Icons.timeline,
                _scoreGrowthRate30Day >= 0 ? Colors.green : Colors.red,
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
    showDialog(
      context: context,
      builder: (BuildContext context) {
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
                      style: FlutterFlowTheme.of(context).titleLarge.override(
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
                  if (_decayPenalty > 0)
                    _buildBreakdownRow(
                      context,
                      'Low Performance Penalty',
                      -_decayPenalty,
                      Colors.red,
                    ),
                  if (_categoryNeglectPenalty > 0)
                    _buildBreakdownRow(
                      context,
                      'Category Neglect Penalty',
                      -_categoryNeglectPenalty,
                      Colors.red,
                    ),
                ] else ...[
                  Text(
                    'Breakdown available only for today\'s live score',
                    style: FlutterFlowTheme.of(context).bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          color: FlutterFlowTheme.of(context).secondaryText,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                // Total
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:
                        FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Change',
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              fontFamily: 'Readex Pro',
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      Text(
                        displayGain >= 0
                            ? '+${displayGain.toStringAsFixed(1)}'
                            : displayGain.toStringAsFixed(1),
                        style: FlutterFlowTheme.of(context).bodyMedium.override(
                              fontFamily: 'Readex Pro',
                              fontWeight: FontWeight.bold,
                              color:
                                  displayGain >= 0 ? Colors.green : Colors.red,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
    final displayData = _show30Days
        ? _cumulativeScoreHistory
        : _cumulativeScoreHistory.length > 7
            ? _cumulativeScoreHistory
                .sublist(_cumulativeScoreHistory.length - 7)
            : _cumulativeScoreHistory;

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
              onTap: () {
                sharedPref
                    .remove(SharedPreference.name.sUserDetails)
                    .then((value) {
                  users = LoginResponse();
                  Navigator.pushReplacementNamed(context, login);
                });
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
