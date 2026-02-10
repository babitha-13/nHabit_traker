import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Screens/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Progress/Pages/progress_breakdown_dialog.dart';
import 'package:habit_tracker/Screens/Progress/backend/progress_page_data_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/aggregate_score_statistics_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_coordinator.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/today_score_calculator.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_persistence_service.dart';
import 'package:habit_tracker/Helper/Helpers/milestone_service.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Progress/UI/progress_stats_widgets.dart';
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
  double dailyPoints = 0.0;
  double consistencyBonus = 0.0;
  double recoveryBonus = 0.0;
  double decayPenalty = 0.0;
  double categoryNeglectPenalty = 0.0;
  double averageDailyGain7Day = 0.0;
  double averageDailyGain30Day = 0.0;
  double bestDailyGain = 0.0;
  double worstDailyGain = 0.0;
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
          projectedCumulativeScore = data['cumulativeScore'] as double? ?? projectedCumulativeScore;
          projectedDailyGain = data['todayScore'] as double? ?? projectedDailyGain;
          final breakdown = data['breakdown'] as Map<String, double>?;
          if (breakdown != null) {
            dailyPoints = breakdown['dailyPoints'] ?? 0.0;
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
    NotificationCenter.addObserver(this, 'progressDataRecalculated', (param) {
      if (mounted) {
        // Reload everything after recalculation
        loadProgressHistory();
        loadCumulativeScore();
        loadCumulativeScoreHistoryData();
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
            Text('Calculating today\'s breakdown...'),
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
        SnackBar(content: Text('Error calculating today\'s breakdown: $error')),
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
    if (dayData.habitBreakdown.isEmpty && dayData.taskBreakdown.isEmpty) {
      showCalculatedBreakdown(context, date, dayData);
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

  void showCalculatedBreakdown(BuildContext context, DateTime date, DailyProgressRecord dayData) {
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
    calculateBreakdownForDate(date).then((breakdown) {
      Navigator.of(context).pop();
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
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error calculating breakdown: $error')),
      );
    });
  }

  Future<Map<String, dynamic>> calculateTodayBreakdown() async {
    try {
      final userId = await waitForCurrentUserUid();
      final today = DateService.currentDate;
      return await ProgressPageDataService.calculateBreakdownForDate(
        userId: userId,
        date: today,
      );
    } catch (e) {
      return {
        'habitBreakdown': <Map<String, dynamic>>[],
        'taskBreakdown': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> calculateBreakdownForDate(DateTime date) async {
    try {
      final userId = await waitForCurrentUserUid();
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

      // Initialize with yesterday's score to avoid showing 0 while loading
      if (!hasLiveScore && projectedCumulativeScore == 0.0) {
        try {
          final yesterdayScore = await TodayScoreCalculator.getCumulativeScoreTillYesterday(
            userId: userId,
          );
          if (yesterdayScore > 0 && mounted) {
            setState(() {
              projectedCumulativeScore = yesterdayScore;
            });
          }
        } catch (e) {
          // If we can't get yesterday's score, continue with 0
        }
      }

      if (hasLiveScore) {
        if (mounted) {
          setState(() {
            projectedCumulativeScore = (sharedScoreData['cumulativeScore'] as double?) ?? projectedCumulativeScore;
            projectedDailyGain = (sharedScoreData['todayScore'] as double?) ?? 0.0;
            final breakdown = sharedScoreData['breakdown'] as Map<String, double>?;
            if (breakdown != null) {
              dailyPoints = breakdown['dailyPoints'] ?? 0.0;
              consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
              recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
              decayPenalty = breakdown['decayPenalty'] ?? 0.0;
              categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
            }
            hasProjection = true;
          });
        }
      } else {
        final userStats = await ScorePersistenceService.getUserStats(userId);
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
            // If we don't have a projection yet, use userStats cumulative score
            // But if it's from today, use yesterday's value (score - today's gain)
            if (projectedCumulativeScore == 0.0 || (isLastCalcToday && projectedCumulativeScore == 0.0)) {
              if (isLastCalcToday) {
                projectedCumulativeScore = (userStats.cumulativeScore - userStats.lastDailyGain).clamp(0.0, double.infinity);
              } else {
                projectedCumulativeScore = userStats.cumulativeScore;
              }
            }
            averageDailyGain7Day = userStats.averageDailyGain7Day;
            averageDailyGain30Day = userStats.averageDailyGain30Day;
            bestDailyGain = userStats.bestDailyGain;
            worstDailyGain = userStats.worstDailyGain;
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
      // Statistics already loaded from UserProgressStats (lines 354-361)
      // No need to recalculate - we want stable historical stats without today
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
          projectedCumulativeScore = (sharedScoreData['cumulativeScore'] as double?) ?? 0.0;
          projectedDailyGain = (sharedScoreData['todayScore'] as double?) ?? 0.0;
          final breakdown = sharedScoreData['breakdown'] as Map<String, double>?;
          if (breakdown != null) {
            dailyPoints = breakdown['dailyPoints'] ?? 0.0;
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
        projectedCumulativeScore = (result['cumulativeScore'] as num?)?.toDouble() ?? 0.0;
        projectedDailyGain = (result['todayScore'] as num?)?.toDouble() ?? 0.0;
        hasProjection = true;
        dailyPoints = (result['dailyPoints'] as num?)?.toDouble() ?? 0.0;
        consistencyBonus = (result['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
        recoveryBonus = (result['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
        decayPenalty = (result['decayPenalty'] as num?)?.toDouble() ?? 0.0;
        categoryNeglectPenalty = (result['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0;
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
        currentCumulativeScore = (sharedScoreData['cumulativeScore'] as double?);
        currentTodayScore = (sharedScoreData['todayScore'] as double?);
      } else if (hasProjection) {
        currentCumulativeScore = projectedCumulativeScore;
        currentTodayScore = projectedDailyGain;
      }

      // Always load 30 days to ensure consistency between 7-day and 30-day views
      final historyResult = await ScoreCoordinator.loadScoreHistoryWithToday(
        userId: userId,
        days: 30,
        cumulativeScore: currentCumulativeScore,
        todayScore: currentTodayScore,
      );
      var history = (historyResult['history'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // Filter to last 7 days if showing 7-day view
      // This ensures both views use the same underlying dataset
      if (!show30Days && history.length > 7) {
        history = history.sublist(history.length - 7);
      }

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

  /// DEPRECATED: Score Statistics should only show historical data (up to yesterday)
  /// Statistics are loaded from UserProgressStats in loadCumulativeScore()
  /// This method was used to include today's live score, which is no longer desired
  @Deprecated('Statistics should not include today\'s changing score')
  Future<void> calculateStatisticsFromHistory() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final stats = await AggregateScoreStatisticsService.calculateStatisticsFromHistory(
        userId: userId,
        progressHistory: progressHistory,
        projectedCumulativeScore: hasProjection && todayPercentage > 0 ? projectedCumulativeScore : null,
        projectedDailyGain: hasProjection && todayPercentage > 0 ? projectedDailyGain : null,
        cumulativeScore: cumulativeScore,
        dailyScoreGain: dailyScoreGain,
        todayPercentage: todayPercentage,
        hasProjection: hasProjection && todayPercentage > 0,
      );

      if (mounted) {
        setState(() {
          averageDailyGain7Day = stats['averageDailyGain7Day'] as double;
          averageDailyGain30Day = stats['averageDailyGain30Day'] as double;
          bestDailyGain = stats['bestDailyGain'] as double;
          worstDailyGain = stats['worstDailyGain'] as double;
          positiveDaysCount7Day = stats['positiveDaysCount7Day'] as int;
          positiveDaysCount30Day = stats['positiveDaysCount30Day'] as int;
          averageCumulativeScore7Day = stats['averageCumulativeScore7Day'] as double;
          averageCumulativeScore30Day = stats['averageCumulativeScore30Day'] as double;
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
    final total = historicalRecords.fold(0.0, (sum, record) => sum + record.completionPercentage) + todayPercentage;
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
    final total = historicalRecords.fold(0.0, (sum, record) => sum + record.targetPoints) + todayTarget;
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
    final total = historicalRecords.fold(0.0, (sum, record) => sum + record.earnedPoints) + todayEarned;
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
        (record) => record.date != null && isSameDay(record.date!, normalizedDate),
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
    final achievedMilestonesCount = MilestoneService.getAchievedMilestones(achievedMilestones);

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
            dailyPoints = breakdown['dailyPoints'] ?? 0.0;
            consistencyBonus = breakdown['consistencyBonus'] ?? 0.0;
            recoveryBonus = breakdown['recoveryBonus'] ?? 0.0;
            decayPenalty = breakdown['decayPenalty'] ?? 0.0;
            categoryNeglectPenalty = breakdown['categoryNeglectPenalty'] ?? 0.0;
          });
        }
        return;
      }

      if (hasProjection &&
          dailyPoints == 0.0 &&
          consistencyBonus == 0.0 &&
          recoveryBonus == 0.0 &&
          decayPenalty == 0.0 &&
          categoryNeglectPenalty == 0.0 &&
          projectedDailyGain != 0.0) {
        try {
          final userId = await waitForCurrentUserUid();
          if (userId.isEmpty) return;

          final instancesData = await ProgressPageDataService.fetchInstancesForBreakdown(userId: userId);
          final categoriesResult = instancesData['categories'] as List<CategoryRecord>;
          final habitInstances = instancesData['habits'] as List<ActivityInstanceRecord>;

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
              dailyPoints = (result['dailyPoints'] as num?)?.toDouble() ?? 0.0;
              consistencyBonus = (result['consistencyBonus'] as num?)?.toDouble() ?? 0.0;
              recoveryBonus = (result['recoveryBonus'] as num?)?.toDouble() ?? 0.0;
              decayPenalty = (result['decayPenalty'] as num?)?.toDouble() ?? 0.0;
              categoryNeglectPenalty = (result['categoryNeglectPenalty'] as num?)?.toDouble() ?? 0.0;
            });
          }
        } catch (e) {}
      }
    }

    final sharedData = TodayProgressState().getCumulativeScoreData();
    final breakdown = sharedData['breakdown'] as Map<String, double>?;
    if (breakdown != null && breakdown.isNotEmpty && mounted) {
      setState(() {
              dailyPoints = breakdown['dailyPoints'] ?? 0.0;
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
                  final totalCheck = dailyPoints + consistencyBonus + recoveryBonus - decayPenalty - categoryNeglectPenalty;
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
                      if (hasProjection) ...[
                        ProgressStatsWidgets.buildBreakdownRow(
                          context,
                          'Base Daily Points',
                          dailyPoints,
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
                          style: FlutterFlowTheme.of(context).bodyMedium.override(
                                fontFamily: 'Readex Pro',
                                color: FlutterFlowTheme.of(context).secondaryText,
                              ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) {
                          final totalFromBreakdown = dailyPoints + consistencyBonus + recoveryBonus - decayPenalty - categoryNeglectPenalty;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
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
                                  totalFromBreakdown >= 0
                                      ? '+${totalFromBreakdown.toStringAsFixed(1)}'
                                      : totalFromBreakdown.toStringAsFixed(1),
                                  style: FlutterFlowTheme.of(context).bodyMedium.override(
                                        fontFamily: 'Readex Pro',
                                        fontWeight: FontWeight.bold,
                                        color: totalFromBreakdown >= 0 ? Colors.green : Colors.red,
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
