import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/features/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/features/Progress/Pages/progress_breakdown_dialog.dart';
import 'package:habit_tracker/features/Progress/backend/progress_page_data_service.dart';
import 'package:habit_tracker/features/Progress/backend/aggregate_score_statistics_service.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_finalization_service.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_coordinator.dart';
import 'package:habit_tracker/services/milestone_service.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Progress/UI/progress_stats_widgets.dart';
import 'dart:async';

mixin ProgressPageLogic<T extends StatefulWidget> on State<T> {
  List<DailyProgressRecord> progressHistory = [];
  bool isLoading = true;
  int historyDays = 7;
  double todayTarget = 0.0;
  double todayEarned = 0.0;
  double todayPercentage = 0.0;
  double cumulativeScore = 0.0;
  double dailyScoreGain = 0.0;
  int achievedMilestones = 0;
  List<Map<String, dynamic>> cumulativeScoreHistory = [];
  bool show30Days = false;
  double projectedCumulativeScore = 0.0;
  double projectedDailyGain = 0.0;
  bool hasProjection = false;
  double dailyScore = 0.0;
  double consistencyBonus = 0.0;
  double recoveryBonus = 0.0;
  double decayPenalty = 0.0;
  double categoryNeglectPenalty = 0.0;
  double averageDailyScore7Day = 0.0;
  double averageDailyScore30Day = 0.0;
  double bestDailyScoreGain = 0.0;
  double worstDailyScoreGain = 0.0;
  int positiveDaysCount7Day = 0;
  int positiveDaysCount30Day = 0;
  double averageCumulativeScore7Day = 0.0;
  double averageCumulativeScore30Day = 0.0;
  DateTime? lastKnownDate;

  @override
  void initState() {
    super.initState();
    lastKnownDate = DateService.todayStart;
    loadProgressHistory();
    NotificationCenter.addObserver(this, 'todayProgressUpdated', (param) {
      if (mounted) {
        setState(() {
          final data = TodayProgressState().getProgressData();
          todayTarget = data['target']!;
          todayEarned = data['earned']!;
          todayPercentage = data['percentage']!;
        });
        updateTodayScore();
      }
    });
    NotificationCenter.addObserver(this, 'cumulativeScoreUpdated', (param) {
      if (mounted) {
        setState(() {
          final data = TodayProgressState().getCumulativeScoreData();
          final hasLiveScore = data['hasLiveScore'] as bool? ?? false;
          projectedCumulativeScore =
              data['cumulativeScore'] as double? ?? projectedCumulativeScore;
          projectedDailyGain =
              data['todayScore'] as double? ?? projectedDailyGain;
          final breakdown = data['breakdown'] as Map<String, double>?;
          if (breakdown != null) {
            dailyScore = breakdown['dailyScore'] ?? 0.0;
            consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
          }
          if (hasLiveScore) {
            hasProjection = true;
          }
        });
        updateHistoryWithTodayScore();
      }
    });
    loadInitialTodayProgress();
    loadCumulativeScore();
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  void checkDayTransition() {
    final today = DateService.todayStart;
    if (lastKnownDate != null && !isSameDay(lastKnownDate!, today)) {
      lastKnownDate = today;
      DailyProgressQueryService.invalidateUserCache(currentUserUid);
      loadProgressHistory();
      loadInitialTodayProgress();
      loadCumulativeScore();
    } else if (lastKnownDate == null) {
      lastKnownDate = today;
    }
  }

  void showProgressBreakdown(BuildContext context, DateTime date) {
    final today = DateService.currentDate;
    if (isSameDay(date, today)) {
      showTodayBreakdown(context);
    } else {
      showHistoricalBreakdown(context, date);
    }
  }

  void showTodayBreakdown(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Loading today\'s breakdown...'),
          ],
        ),
      ),
    );

    calculateTodayBreakdown().then((breakdown) {
      Navigator.of(context).pop();
      showDialog(
        context: context,
        builder: (context) => ProgressBreakdownDialog(
          date: DateService.currentDate,
          totalEarned: todayEarned,
          totalTarget: todayTarget,
          percentage: todayPercentage,
          habitBreakdown: breakdown['habitBreakdown'] ?? [],
          taskBreakdown: breakdown['taskBreakdown'] ?? [],
        ),
      );
    }).catchError((error) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading today\'s breakdown: $error')),
      );
    });
  }

  void showHistoricalBreakdown(BuildContext context, DateTime date) {
    final dayData = getProgressForDate(date);
    if (dayData == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No data available for this date')),
      );
      return;
    }

    final hasBreakdown =
        dayData.habitBreakdown.isNotEmpty || dayData.taskBreakdown.isNotEmpty;
    final hadTrackedItems = dayData.totalHabits > 0 || dayData.totalTasks > 0;
    if (!hasBreakdown && hadTrackedItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Stored daily breakdown is missing for this date. Recompute fallback is disabled.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

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

  Future<Map<String, dynamic>> calculateTodayBreakdown() async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) {
      throw Exception('User not authenticated');
    }
    final today = DateService.currentDate;
    final breakdown = await ProgressPageDataService.calculateBreakdownForDate(
      userId: userId,
      date: today,
    );

    final habitBreakdown =
        breakdown['habitBreakdown'] as List<Map<String, dynamic>>? ?? [];
    final taskBreakdown =
        breakdown['taskBreakdown'] as List<Map<String, dynamic>>? ?? [];
    final totalHabits = breakdown['totalHabits'] as int? ?? 0;
    final totalTasks = breakdown['totalTasks'] as int? ?? 0;
    final hasBreakdown =
        habitBreakdown.isNotEmpty || taskBreakdown.isNotEmpty;

    if (!hasBreakdown && (totalHabits > 0 || totalTasks > 0)) {
      throw Exception(
        'Stored daily breakdown is missing for today. Recompute fallback is disabled.',
      );
    }

    return breakdown;
  }

  Future<void> loadProgressHistory() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
    });
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }
      final daysToLoad = historyDays > 30 ? historyDays : 30;
      final progressData = await ProgressPageDataService.fetchProgressHistory(
        userId: userId,
        days: daysToLoad,
      );
      if (mounted) {
        setState(() {
          progressHistory = progressData;
          isLoading = false;
        });
        calculateStatisticsFromHistory();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void loadInitialTodayProgress() {
    final data = TodayProgressState().getProgressData();
    setState(() {
      todayTarget = data['target']!;
      todayEarned = data['earned']!;
      todayPercentage = data['percentage']!;
    });
  }

  Future<void> loadCumulativeScore() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final sharedScoreData = TodayProgressState().getCumulativeScoreData();
      final hasLiveScore = sharedScoreData['hasLiveScore'] as bool? ?? false;

      if (hasLiveScore) {
        if (mounted) {
          setState(() {
            projectedCumulativeScore =
                (sharedScoreData['cumulativeScore'] as double?) ?? 0.0;
            projectedDailyGain =
                (sharedScoreData['todayScore'] as double?) ?? 0.0;
            final breakdown =
                sharedScoreData['breakdown'] as Map<String, double>?;
            if (breakdown != null) {
              dailyScore = breakdown['dailyScore'] ?? 0.0;
              consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
              recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
              decayPenalty = breakdown['decayPenalty'] ?? 0.0;
              categoryNeglectPenalty =
                  breakdown['categoryNeglectPenalty'] ?? 0.0;
            }
            hasProjection = true;
          });
        }
      } else {
        final userStats =
            await CumulativeScoreService.getCumulativeScore(userId);
        if (userStats != null && mounted) {
          setState(() {
            cumulativeScore = userStats.cumulativeScore;
            final today = DateService.todayStart;
            final lastCalc = userStats.lastCalculationDate;
            final isLastCalcToday = lastCalc != null &&
                lastCalc.year == today.year &&
                lastCalc.month == today.month &&
                lastCalc.day == today.day;
            dailyScoreGain = isLastCalcToday ? userStats.lastDailyGain : 0.0;
            averageDailyScore7Day = userStats.averageDailyScore7Day;
            averageDailyScore30Day = userStats.averageDailyScore30Day;
            bestDailyScoreGain = userStats.bestDailyScoreGain;
            worstDailyScoreGain = userStats.worstDailyScoreGain;
            positiveDaysCount7Day = userStats.positiveDaysCount7Day;
            positiveDaysCount30Day = userStats.positiveDaysCount30Day;
            averageCumulativeScore7Day = userStats.averageCumulativeScore7Day;
            averageCumulativeScore30Day = userStats.averageCumulativeScore30Day;
          });
        }
        if (!hasLiveScore && todayPercentage > 0) {
          await updateTodayScore();
        }
      }
      await loadCumulativeScoreHistoryData();
      await calculateStatisticsFromHistory();
    } catch (e) {}
  }

  Future<void> updateTodayScore() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final sharedScoreData = TodayProgressState().getCumulativeScoreData();
      final hasLiveScore = sharedScoreData['hasLiveScore'] as bool? ?? false;

      if (hasLiveScore) {
        if (!mounted) return;
        setState(() {
          projectedCumulativeScore =
              (sharedScoreData['cumulativeScore'] as double?) ?? 0.0;
          projectedDailyGain =
              (sharedScoreData['todayScore'] as double?) ?? 0.0;
          final breakdown =
              sharedScoreData['breakdown'] as Map<String, double>?;
          if (breakdown != null) {
            dailyScore = breakdown['dailyScore'] ?? 0.0;
            consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
          }
          hasProjection = true;
        });
        updateHistoryWithTodayScore();
        return;
      }

      final result = await ScoreCoordinator.updateTodayScore(
        userId: userId,
        completionPercentage: todayPercentage,
        pointsEarned: todayEarned,
        categories: null,
        habitInstances: null,
        includeBreakdown: true,
      );

      if (!mounted) return;
      setState(() {
        projectedCumulativeScore =
            (result['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
        projectedDailyGain = (result['todayScore'] as num?)?.toDouble() ?? 0.0;
        hasProjection = true;
        dailyScore = (result['dailyScore'] as num?)?.toDouble() ?? 0.0;
        consistencyBonus =
            (result['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
        recoveryBonus = (result['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
        decayPenalty = (result['decayPenalty'] as num?)?.toDouble() ?? 0.0;
        categoryNeglectPenalty =
            (result['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0;
      });
      updateHistoryWithTodayScore();
    } catch (e) {}
  }

  Future<void> loadCumulativeScoreHistoryData() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final sharedScoreData = TodayProgressState().getCumulativeScoreData();
      final hasLiveScore = sharedScoreData['hasLiveScore'] as bool? ?? false;

      double? currentCumulativeScore;
      double? currentTodayScore;

      if (hasLiveScore) {
        currentCumulativeScore =
            (sharedScoreData['cumulativeScore'] as double?);
        currentTodayScore = (sharedScoreData['todayScore'] as double?);
      } else if (hasProjection) {
        currentCumulativeScore = projectedCumulativeScore;
        currentTodayScore = projectedDailyGain;
      }

      final daysToLoad = show30Days ? 30 : 7;
      final historyResult = await ScoreCoordinator.loadScoreHistoryWithToday(
        userId: userId,
        days: daysToLoad,
        cumulativeScore: currentCumulativeScore,
        todayScore: currentTodayScore,
      );
      final history =
          (historyResult['history'] as List?)?.cast<Map<String, dynamic>>() ??
              [];

      if (mounted) {
        setState(() {
          cumulativeScoreHistory = history;
        });
      }
    } catch (e) {}
  }

  void updateHistoryWithTodayScore() {
    if (!hasProjection) return;

    final changed = ScoreCoordinator.updateHistoryWithTodayScore(
      cumulativeScoreHistory,
      projectedDailyGain,
      projectedCumulativeScore,
    );

    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> calculateStatisticsFromHistory() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final stats =
          await AggregateScoreStatisticsService.calculateStatisticsFromHistory(
        userId: userId,
        progressHistory: progressHistory,
        projectedCumulativeScore: hasProjection && todayPercentage > 0
            ? projectedCumulativeScore
            : null,
        projectedDailyGain:
            hasProjection && todayPercentage > 0 ? projectedDailyGain : null,
        cumulativeScore: cumulativeScore,
        dailyScoreGain: dailyScoreGain,
        todayPercentage: todayPercentage,
        hasProjection: hasProjection && todayPercentage > 0,
      );

      if (mounted) {
        setState(() {
          averageDailyScore7Day = stats['averageDailyScore7Day'] as double;
          averageDailyScore30Day = stats['averageDailyScore30Day'] as double;
          bestDailyScoreGain = stats['bestDailyScoreGain'] as double;
          worstDailyScoreGain = stats['worstDailyScoreGain'] as double;
          positiveDaysCount7Day = stats['positiveDaysCount7Day'] as int;
          positiveDaysCount30Day = stats['positiveDaysCount30Day'] as int;
          averageCumulativeScore7Day =
              stats['averageCumulativeScore7Day'] as double;
          averageCumulativeScore30Day =
              stats['averageCumulativeScore30Day'] as double;
        });
      }
    } catch (e) {}
  }

  List<DailyProgressRecord> getLastNDays(int n) {
    final endDate = DateService.currentDate;
    final startDate = endDate.subtract(Duration(days: n));
    return progressHistory.where((record) {
      if (record.date == null) return false;
      return record.date!.isAfter(startDate) &&
          record.date!.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();
  }

  double calculateAveragePercentage(List<DailyProgressRecord> records) {
    final today = DateService.currentDate;
    final historicalRecords = records.where((record) {
      if (record.date == null) return false;
      return !isSameDay(record.date!, today);
    }).toList();

    if (historicalRecords.isEmpty) {
      return todayPercentage;
    }
    final total = historicalRecords.fold(
            0.0, (sum, record) => sum + record.completionPercentage) +
        todayPercentage;
    final count = historicalRecords.length + 1;
    return total / count;
  }

  double calculateAverageTarget(List<DailyProgressRecord> records) {
    final today = DateService.currentDate;
    final historicalRecords = records.where((record) {
      if (record.date == null) return false;
      return !isSameDay(record.date!, today);
    }).toList();

    if (historicalRecords.isEmpty) {
      return todayTarget;
    }
    final total = historicalRecords.fold(
            0.0, (sum, record) => sum + record.targetPoints) +
        todayTarget;
    final count = historicalRecords.length + 1;
    return total / count;
  }

  double calculateAverageEarned(List<DailyProgressRecord> records) {
    final today = DateService.currentDate;
    final historicalRecords = records.where((record) {
      if (record.date == null) return false;
      return !isSameDay(record.date!, today);
    }).toList();

    if (historicalRecords.isEmpty) {
      return todayEarned;
    }
    final total = historicalRecords.fold(
            0.0, (sum, record) => sum + record.earnedPoints) +
        todayEarned;
    final count = historicalRecords.length + 1;
    return total / count;
  }

  Color getPerformanceColor(double percentage) {
    if (percentage < 30) return Colors.red;
    if (percentage < 70) return Colors.orange;
    return Colors.green;
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DailyProgressRecord? getProgressForDate(DateTime date) {
    final normalizedDate = DateTime(date.year, date.month, date.day);
    try {
      return progressHistory.firstWhere(
        (record) =>
            record.date != null && isSameDay(record.date!, normalizedDate),
      );
    } catch (e) {
      return null;
    }
  }

  String getDayName(DateTime date) {
    final now = DateService.currentDate;
    if (isSameDay(date, now)) {
      return 'Today';
    } else if (isSameDay(date, now.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    } else {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }
  }

  Widget buildMilestoneProgress(double currentScore) {
    final nextMilestone = MilestoneService.getNextMilestone(currentScore);
    final progress = MilestoneService.getProgressToNextMilestone(currentScore);
    final achievedMilestonesCount =
        MilestoneService.getAchievedMilestones(achievedMilestones);

    if (nextMilestone == null) {
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
            const Icon(Icons.emoji_events, color: Colors.amber, size: 20),
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
          if (achievedMilestonesCount.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: achievedMilestonesCount.map((milestone) {
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

  void showScoreBreakdownDialog(double displayGain) {
    Future<void> ensureBreakdownLoaded() async {
      final sharedData = TodayProgressState().getCumulativeScoreData();
      final breakdown = sharedData['breakdown'] as Map<String, double>?;

      if (breakdown != null && breakdown.isNotEmpty) {
        if (mounted) {
          setState(() {
            dailyScore = breakdown['dailyScore'] ?? 0.0;
            consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
          });
        }
        return;
      }

      if (hasProjection &&
          dailyScore == 0.0 &&
          consistencyBonus == 0.0 &&
          recoveryBonus == 0.0 &&
          decayPenalty == 0.0 &&
          categoryNeglectPenalty == 0.0 &&
          projectedDailyGain != 0.0) {
        try {
          final userId = await waitForCurrentUserUid();
          if (userId.isEmpty) return;

          final instancesData =
              await ProgressPageDataService.fetchInstancesForBreakdown(
                  userId: userId);
          final categoriesResult =
              instancesData['categories'] as List<CategoryRecord>;
          final habitInstances =
              instancesData['habits'] as List<ActivityInstanceRecord>;

          final result = await ScoreCoordinator.updateTodayScore(
            userId: userId,
            completionPercentage: todayPercentage,
            pointsEarned: todayEarned,
            categories: categoriesResult,
            habitInstances: habitInstances,
            includeBreakdown: true,
            updateSharedState: false,
          );

          if (mounted) {
            setState(() {
              dailyScore = (result['dailyScore'] as num?)?.toDouble() ?? 0.0;
              consistencyBonus =
                  (result['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
              recoveryBonus =
                  (result['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
              decayPenalty =
                  (result['decayPenalty'] as num?)?.toDouble() ?? 0.0;
              categoryNeglectPenalty =
                  (result['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0;
            });
          }
        } catch (e) {}
      }
    }

    final sharedData = TodayProgressState().getCumulativeScoreData();
    final breakdown = sharedData['breakdown'] as Map<String, double>?;
    if (breakdown != null && breakdown.isNotEmpty && mounted) {
      setState(() {
        dailyScore = breakdown['dailyScore'] ?? 0.0;
        consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
        recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
        decayPenalty = breakdown['decayPenalty'] ?? 0.0;
        categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
      });
    }

    ensureBreakdownLoaded().then((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && hasProjection) {
                  final totalCheck = dailyScore +
                      consistencyBonus +
                      recoveryBonus -
                      decayPenalty -
                      categoryNeglectPenalty;
                  if (totalCheck != 0.0 || projectedDailyGain != 0.0) {
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
                      if (hasProjection) ...[
                        ProgressStatsWidgets.buildBreakdownRow(
                          context,
                          'Completion Score',
                          dailyScore,
                          Colors.blue,
                        ),
                        if (consistencyBonus > 0)
                          ProgressStatsWidgets.buildBreakdownRow(
                            context,
                            'Consistency Bonus',
                            consistencyBonus,
                            Colors.green,
                          ),
                        if (recoveryBonus > 0)
                          ProgressStatsWidgets.buildBreakdownRow(
                            context,
                            'Recovery Bonus',
                            recoveryBonus,
                            Colors.green,
                          ),
                        if (decayPenalty != 0)
                          ProgressStatsWidgets.buildBreakdownRow(
                            context,
                            'Low Performance Penalty',
                            -decayPenalty,
                            Colors.red,
                          ),
                        if (categoryNeglectPenalty != 0)
                          ProgressStatsWidgets.buildBreakdownRow(
                            context,
                            'Category Neglect Penalty',
                            -categoryNeglectPenalty,
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
                      Builder(
                        builder: (context) {
                          final totalFromBreakdown = dailyScore +
                              consistencyBonus +
                              recoveryBonus -
                              decayPenalty -
                              categoryNeglectPenalty;

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
}
