import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/Helper/Helpers/milestone_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/aggregate_score_statistics_service.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_formulas.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for database read/write operations for user score data
/// Handles persistence of cumulative scores, user stats, and historical data
class ScorePersistenceService {
  /// Get current cumulative score for a user
  static Future<UserProgressStatsRecord?> getUserStats(String userId) async {
    try {
      final docRef =
          UserProgressStatsRecord.collectionForUser(userId).doc('main');
      final snapshot = await docRef.get();

      if (!snapshot.exists) {
        // Document doesn't exist, create it with default values
        final now = DateTime.now();
        final data = createUserProgressStatsRecordData(
          userId: userId,
          cumulativeScore: 0.0,
          lastCalculationDate: now,
          historicalHighScore: 0.0,
          totalDaysTracked: 0,
          currentStreak: 0,
          longestStreak: 0,
          lastDailyGain: 0.0,
          consecutiveLowDays: 0,
          achievedMilestones: 0,
          createdAt: now,
          lastUpdatedAt: now,
          averageDailyScore7Day: 0.0,
          averageDailyScore30Day: 0.0,
          bestDailyScoreGain: 0.0,
          worstDailyScoreGain: 0.0,
          positiveDaysCount7Day: 0,
          positiveDaysCount30Day: 0,
          scoreGrowthRate7Day: 0.0,
          scoreGrowthRate30Day: 0.0,
          averageCumulativeScore7Day: 0.0,
          averageCumulativeScore30Day: 0.0,
          lastAggregateStatsCalculationDate: now,
        );
        await docRef.set(data);
        return UserProgressStatsRecord.getDocumentFromData(data, docRef);
      }

      return await UserProgressStatsRecord.getDocumentOnce(docRef);
    } catch (e) {
      return null;
    }
  }

  /// Save user progress stats to database
  static Future<void> saveUserStats(
    String userId,
    double cumulativeScore,
    DateTime lastCalculationDate,
    double historicalHighScore,
    int totalDaysTracked,
    int currentStreak,
    int longestStreak,
    double lastDailyGain,
    int consecutiveLowDays,
    int achievedMilestones, {
    Map<String, dynamic>? aggregateStats,
  }) async {
    final docRef =
        UserProgressStatsRecord.collectionForUser(userId).doc('main');
    final now = DateTime.now();

    final data = createUserProgressStatsRecordData(
      userId: userId,
      cumulativeScore: cumulativeScore,
      lastCalculationDate: lastCalculationDate,
      historicalHighScore: historicalHighScore,
      totalDaysTracked: totalDaysTracked,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      lastDailyGain: lastDailyGain,
      consecutiveLowDays: consecutiveLowDays,
      achievedMilestones: achievedMilestones,
      lastUpdatedAt: now,
      averageDailyScore7Day:
          aggregateStats?['averageDailyScore7Day'] as double?,
      averageDailyScore30Day:
          aggregateStats?['averageDailyScore30Day'] as double?,
      bestDailyScoreGain: aggregateStats?['bestDailyScoreGain'] as double?,
      worstDailyScoreGain: aggregateStats?['worstDailyScoreGain'] as double?,
      positiveDaysCount7Day: aggregateStats?['positiveDaysCount7Day'] as int?,
      positiveDaysCount30Day: aggregateStats?['positiveDaysCount30Day'] as int?,
      scoreGrowthRate7Day: aggregateStats?['scoreGrowthRate7Day'] as double?,
      scoreGrowthRate30Day: aggregateStats?['scoreGrowthRate30Day'] as double?,
      averageCumulativeScore7Day:
          aggregateStats?['averageCumulativeScore7Day'] as double?,
      averageCumulativeScore30Day:
          aggregateStats?['averageCumulativeScore30Day'] as double?,
      lastAggregateStatsCalculationDate: aggregateStats != null ? now : null,
    );

    await docRef.set(data, SetOptions(merge: true));
  }

  /// Get cumulative score at end of yesterday
  /// First tries DailyProgressRecord for yesterday, falls back to UserProgressStatsRecord
  static Future<double> getCumulativeScoreTillYesterday(String userId) async {
    if (userId.isEmpty) return 0.0;

    try {
      // Try to get yesterday's DailyProgressRecord
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayStart =
          DateTime(yesterday.year, yesterday.month, yesterday.day);
      final yesterdayRecords =
          await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        startDate: yesterdayStart,
        endDate: yesterdayStart,
        orderDescending: false,
      );

      if (yesterdayRecords.isNotEmpty) {
        final yesterdayRecord = yesterdayRecords.first;
        if (yesterdayRecord.cumulativeScoreSnapshot > 0) {
          return yesterdayRecord.cumulativeScoreSnapshot;
        }
        // If snapshot is 0 but we have a gain, calculate from previous day
        if (yesterdayRecord.hasDailyScoreGain()) {
          // Get the day before yesterday to calculate backwards
          final dayBefore = yesterdayStart.subtract(const Duration(days: 1));
          final dayBeforeRecords =
              await DailyProgressQueryService.queryDailyProgress(
            userId: userId,
            startDate: dayBefore,
            endDate: dayBefore,
            orderDescending: false,
          );
          if (dayBeforeRecords.isNotEmpty) {
            final dayBeforeRecord = dayBeforeRecords.first;
            if (dayBeforeRecord.cumulativeScoreSnapshot > 0) {
              return dayBeforeRecord.cumulativeScoreSnapshot +
                  yesterdayRecord.dailyScoreGain;
            }
          }
        }
      }

      // Fallback: Get from UserProgressStatsRecord
      // This represents the last known cumulative score
      final userStats = await getUserStats(userId);
      if (userStats != null && userStats.cumulativeScore > 0) {
        // If last calculation was today, subtract today's gain to get yesterday's
        final lastCalcDate = userStats.lastCalculationDate;
        if (lastCalcDate != null) {
          final lastCalcNormalized =
              DateTime(lastCalcDate.year, lastCalcDate.month, lastCalcDate.day);
          final today = DateTime.now();
          final todayNormalized = DateTime(today.year, today.month, today.day);
          if (lastCalcNormalized.isAtSameMomentAs(todayNormalized)) {
            // Last calculation was today, subtract today's gain
            return (userStats.cumulativeScore - userStats.lastDailyGain)
                .clamp(0.0, double.infinity);
          }
        }
        return userStats.cumulativeScore;
      }
    } catch (e) {
      // Error fetching - return 0
    }

    return 0.0;
  }

  /// Recalculate cumulative score from historical data
  static Future<void> recalculateFromHistory(String userId) async {
    try {
      // Get all historical progress data
      final allProgress = await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        orderDescending: false,
      );

      if (allProgress.isEmpty) return;

      double cumulativeScore = 0.0;
      int currentStreak = 0;
      int longestStreak = 0;
      int totalDays = 0;
      int consecutiveLowDays = 0;
      int achievedMilestones = 0;

      for (int i = 0; i < allProgress.length; i++) {
        final day = allProgress[i];
        final completion = day.completionPercentage;
        final rawPoints = day.earnedPoints;

        // Calculate daily score
        final dailyScore =
            ScoreFormulas.calculateDailyScore(completion, rawPoints);

        // Calculate consistency bonus (need last 7 days)
        final startIndex = (i >= 6) ? i - 6 : 0;
        final last7Days = allProgress.sublist(startIndex, i + 1);
        final consistencyBonus =
            ScoreFormulas.calculateConsistencyBonus(last7Days);

        // Track consecutive low days and calculate penalty/recovery bonus
        double penalty = 0.0;
        double recoveryBonus = 0.0;

        if (completion < ScoreFormulas.decayThreshold) {
          // Completion < 50%: increment counter and apply penalty
          consecutiveLowDays++;
          penalty = ScoreFormulas.calculateCombinedPenalty(
              completion, consecutiveLowDays);
        } else {
          // Completion >= 50%: calculate recovery bonus and reset counter
          if (consecutiveLowDays > 0) {
            recoveryBonus =
                ScoreFormulas.calculateRecoveryBonus(consecutiveLowDays);
          }
          consecutiveLowDays = 0;
        }

        // Update cumulative score
        final dailyGain =
            dailyScore + consistencyBonus + recoveryBonus - penalty;
        final oldScore = cumulativeScore;
        cumulativeScore =
            (cumulativeScore + dailyGain).clamp(0.0, double.infinity);

        // Check for new milestones
        final newMilestones = MilestoneService.getNewMilestones(
          oldScore,
          cumulativeScore,
          achievedMilestones,
        );
        // Update achieved milestones bitmask
        for (final milestoneValue in newMilestones) {
          final milestoneIndex =
              MilestoneService.milestones.indexOf(milestoneValue);
          if (milestoneIndex >= 0) {
            achievedMilestones = MilestoneService.setMilestoneAchieved(
              achievedMilestones,
              milestoneIndex,
            );
          }
        }

        // Update streaks
        if (completion >= ScoreFormulas.consistencyThreshold) {
          currentStreak++;
          longestStreak =
              [longestStreak, currentStreak].reduce((a, b) => a > b ? a : b);
        } else {
          currentStreak = 0;
        }

        totalDays++;
      }

      // Save recalculated stats
      final lastDate = allProgress.last.date;
      if (lastDate != null) {
        // Calculate aggregate statistics for recalculated data
        Map<String, dynamic> aggregateStats = {};
        try {
          aggregateStats = await AggregateScoreStatisticsService
              .calculateAggregateStatistics(
            userId,
            lastDate,
          );
          AggregateScoreStatisticsService.clearCache(userId);
        } catch (e) {
          // Error calculating aggregate statistics during recalculation
        }

        await saveUserStats(
          userId,
          cumulativeScore,
          lastDate,
          cumulativeScore, // Historical high is the current score after recalculation
          totalDays,
          currentStreak,
          longestStreak,
          allProgress.isNotEmpty
              ? ScoreFormulas.calculateDailyScore(
                  allProgress.last.completionPercentage,
                  allProgress.last.earnedPoints,
                )
              : 0.0,
          consecutiveLowDays, // Final consecutive low days count
          achievedMilestones, // Final achieved milestones
          aggregateStats: aggregateStats,
        );
      }
    } catch (e) {
      rethrow;
    }
  }
}
