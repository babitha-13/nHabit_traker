// Compatibility layer for CumulativeScoreService
// This file maintains backward compatibility while delegating to new services
// New code should use the new services directly:
// - ScoreFormulas (pure calculations)
// - ScorePersistenceService (database access)
// - ScoreCoordinator (orchestration)

import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_formulas.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_persistence_service.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/services/milestone_service.dart';
import 'package:habit_tracker/features/Progress/backend/aggregate_score_statistics_service.dart';

/// Legacy compatibility class - delegates to new services
/// New code should use ScoreFormulas, ScorePersistenceService, and ScoreCoordinator directly
@Deprecated(
    'Use ScoreFormulas, ScorePersistenceService, and ScoreCoordinator instead')
class CumulativeScoreService {
  // Expose constants for backward compatibility
  static const double basePointsPerDay = ScoreFormulas.basePointsPerDay;
  static const double weeklyWeight = ScoreFormulas.weeklyWeight;
  static const double monthlyWeight = ScoreFormulas.monthlyWeight;
  static const double consistencyThreshold = ScoreFormulas.consistencyThreshold;
  static const double decayThreshold = ScoreFormulas.decayThreshold;
  static const double penaltyBaseMultiplier =
      ScoreFormulas.penaltyBaseMultiplier;
  static const double categoryNeglectPenalty =
      ScoreFormulas.categoryNeglectPenalty;
  static const double consistencyBonusFull = ScoreFormulas.consistencyBonusFull;
  static const double consistencyBonusPartial =
      ScoreFormulas.consistencyBonusPartial;

  // Delegate all calculation methods to ScoreFormulas
  static double calculateDailyScore(
    double completionPercentage,
    double rawPointsEarned,
  ) {
    return ScoreFormulas.calculateDailyScore(
        completionPercentage, rawPointsEarned);
  }

  static double calculateConsistencyBonus(List<DailyProgressRecord> last7Days) {
    return ScoreFormulas.calculateConsistencyBonus(last7Days);
  }

  static double calculateCombinedPenalty(
    double dailyCompletion,
    int consecutiveLowDays,
  ) {
    return ScoreFormulas.calculateCombinedPenalty(
        dailyCompletion, consecutiveLowDays);
  }

  static double calculateRecoveryBonus(double cumulativeLowStreakPenalty) {
    return ScoreFormulas.calculateRecoveryBonus(cumulativeLowStreakPenalty);
  }

  static double calculateCategoryNeglectPenalty(
    List<CategoryRecord> categories,
    List<ActivityInstanceRecord> habitInstances,
    DateTime targetDate,
  ) {
    return ScoreFormulas.calculateCategoryNeglectPenalty(
      categories,
      habitInstances,
      targetDate,
    );
  }

  static double calculateWeightedPerformance(
    List<DailyProgressRecord> last7Days,
    List<DailyProgressRecord> last30Days,
  ) {
    return ScoreFormulas.calculateWeightedPerformance(last7Days, last30Days);
  }

  // Delegate persistence methods to ScorePersistenceService
  static Future<UserProgressStatsRecord?> getCumulativeScore(
      String userId) async {
    return ScorePersistenceService.getUserStats(userId);
  }

  static Future<void> recalculateFromHistory(String userId) async {
    return ScorePersistenceService.recalculateFromHistory(userId);
  }

  // Complex orchestration method - kept for backward compatibility
  // This is used by day_end_processor and morning_catchup_service
  static Future<Map<String, dynamic>> updateCumulativeScore(
    String userId,
    double todayCompletionPercentage,
    DateTime targetDate,
    double rawPointsEarned, {
    double categoryNeglectPenalty = 0.0,
  }) async {
    try {
      // Get historical data for calculations
      final last7Days = await DailyProgressQueryService.queryLastNDays(
        userId: userId,
        n: 7,
        endDate: targetDate,
      );
      final last30Days = await DailyProgressQueryService.queryLastNDays(
        userId: userId,
        n: 30,
        endDate: targetDate,
      );

      // Calculate components using formulas
      final dailyScore = ScoreFormulas.calculateDailyScore(
        todayCompletionPercentage,
        rawPointsEarned,
      );
      final consistencyBonus =
          ScoreFormulas.calculateConsistencyBonus(last7Days);
      final weightedPerformance =
          ScoreFormulas.calculateWeightedPerformance(last7Days, last30Days);

      // Get or create user stats
      final userStats = await ScorePersistenceService.getUserStats(userId);
      if (userStats == null) {
        throw Exception('Failed to get user stats');
      }

      // Slump streak is driven by visible cumulative decline.
      final prevDropDays = userStats.consecutiveLowDays;
      final prevLossPool = userStats.cumulativeLowStreakPenalty;
      int newConsecutiveLowDays = prevDropDays;
      double newCumulativeLowStreakPenalty = prevLossPool;

      // Apply diminishing only when the day would otherwise be negative.
      final rawDecayPenalty =
          ScoreFormulas.calculateRawDecayPenalty(todayCompletionPercentage);
      final preDiminishGain =
          dailyScore + consistencyBonus - rawDecayPenalty - categoryNeglectPenalty;

      final penalty = preDiminishGain < 0
          ? ScoreFormulas.calculateCombinedPenalty(
              todayCompletionPercentage,
              prevDropDays + 1,
            )
          : rawDecayPenalty;

      final gainBeforeRecovery =
          dailyScore + consistencyBonus - penalty - categoryNeglectPenalty;
      final endBeforeRecovery =
          (userStats.cumulativeScore + gainBeforeRecovery)
              .clamp(0.0, double.infinity)
              .toDouble();
      final isSlumpDay = endBeforeRecovery < userStats.cumulativeScore;

      double recoveryBonus = 0.0;
      if (isSlumpDay) {
        final lossToday = userStats.cumulativeScore - endBeforeRecovery;
        newConsecutiveLowDays = prevDropDays + 1;
        newCumulativeLowStreakPenalty = prevLossPool + lossToday;
      } else {
        if (prevDropDays > 0 && prevLossPool > 0) {
          recoveryBonus = ScoreFormulas.calculateRecoveryBonus(prevLossPool);
        }
        newConsecutiveLowDays = 0;
        newCumulativeLowStreakPenalty = 0.0;
      }

      // Calculate new cumulative score
      final dailyGain = gainBeforeRecovery + recoveryBonus;
      final newCumulativeScore =
          (userStats.cumulativeScore + dailyGain).clamp(0.0, double.infinity);

      // Check for new milestones
      final oldScore = userStats.cumulativeScore;
      final newMilestones = MilestoneService.getNewMilestones(
        oldScore,
        newCumulativeScore,
        userStats.achievedMilestones,
      );

      // Update achieved milestones bitmask
      int newAchievedMilestones = userStats.achievedMilestones;
      for (final milestoneValue in newMilestones) {
        final milestoneIndex =
            MilestoneService.milestones.indexOf(milestoneValue);
        if (milestoneIndex >= 0) {
          newAchievedMilestones = MilestoneService.setMilestoneAchieved(
            newAchievedMilestones,
            milestoneIndex,
          );
        }
      }

      // Update streaks
      final newCurrentStreak = ScoreFormulas.calculateCurrentStreak(
          last7Days, todayCompletionPercentage);
      final newLongestStreak = [userStats.longestStreak, newCurrentStreak]
          .reduce((a, b) => a > b ? a : b);

      // Update historical high score
      final newHistoricalHigh = [
        userStats.historicalHighScore,
        newCumulativeScore
      ].reduce((a, b) => a > b ? a : b);

      // Calculate aggregate statistics
      Map<String, dynamic> aggregateStats = {};
      try {
        aggregateStats =
            await AggregateScoreStatisticsService.calculateAggregateStatistics(
          userId,
          targetDate,
        );
        // Clear cache after calculation to ensure fresh data on next read
        AggregateScoreStatisticsService.clearCache(userId);
      } catch (e) {
        // Continue without aggregate stats if calculation fails
      }

      // Save updated stats
      await ScorePersistenceService.saveUserStats(
        userId,
        newCumulativeScore,
        targetDate,
        newHistoricalHigh,
        userStats.totalDaysTracked + 1,
        newCurrentStreak,
        newLongestStreak,
        dailyGain,
        newConsecutiveLowDays,
        newCumulativeLowStreakPenalty,
        newAchievedMilestones,
        aggregateStats: aggregateStats,
      );

      // Calculate effective gain (change in cumulative score)
      // This accounts for the floor at 0.0
      final effectiveGain = newCumulativeScore - userStats.cumulativeScore;

      return {
        'cumulativeScore': newCumulativeScore,
        'previousCumulativeScore': userStats.cumulativeScore,
        'dailyGain': dailyGain,
        'effectiveGain': effectiveGain,
        'dailyScore': dailyScore,
        'dailyPoints': dailyScore,
        'consistencyBonus': consistencyBonus,
        'decayPenalty': penalty,
        'recoveryBonus': recoveryBonus,
        'categoryNeglectPenalty': categoryNeglectPenalty,
        'weightedPerformance': weightedPerformance,
        'currentStreak': newCurrentStreak,
        'longestStreak': newLongestStreak,
        'consecutiveLowDays': newConsecutiveLowDays,
        'newMilestones': newMilestones,
        'achievedMilestones': newAchievedMilestones,
        'aggregateStats': aggregateStats,
      };
    } catch (e) {
      rethrow;
    }
  }

  /// Get bonus notification data based on score data
  static Map<String, dynamic> getBonusNotificationData(
    Map<String, dynamic> scoreData,
  ) {
    return {
      'consistencyBonus': scoreData['consistencyBonus'] ?? 0.0,
      'recoveryBonus': scoreData['recoveryBonus'] ?? 0.0,
      'decayPenalty': scoreData['decayPenalty'] ?? 0.0,
      'categoryNeglectPenalty': scoreData['categoryNeglectPenalty'] ?? 0.0,
      'consecutiveLowDays': scoreData['consecutiveLowDays'] ?? 0,
    };
  }
}
