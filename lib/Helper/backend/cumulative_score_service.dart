import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/milestone_service.dart';
import 'package:habit_tracker/Helper/backend/aggregate_score_statistics_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Service for calculating and managing cumulative progress scores
/// Implements a weighted scoring system that rewards consistency and recent performance
class CumulativeScoreService {
  // Configuration constants
  static const double basePointsPerDay = 10.0;
  static const double weeklyWeight = 0.6;
  static const double monthlyWeight = 0.4;
  static const double consistencyThreshold = 80.0;
  static const double decayThreshold = 50.0;
  static const double penaltyBaseMultiplier = 0.04;
  static const double categoryNeglectPenalty = 0.4;
  static const double consistencyBonusFull = 5.0;
  static const double consistencyBonusPartial = 2.0;

  /// Calculate daily score based on completion percentage and raw points earned
  static double calculateDailyScore(
    double completionPercentage,
    double rawPointsEarned,
  ) {
    // Percentage component (max 10 points)
    final percentageComponent = (completionPercentage / 100.0) * basePointsPerDay;
    
    // Raw points bonus using square root scaling divided by 2
    final rawPointsBonus = sqrt(rawPointsEarned) / 2.0;
    
    // Combined score (no cap)
    return percentageComponent + rawPointsBonus;
  }

  /// Calculate consistency bonus based on 7-day performance
  static double calculateConsistencyBonus(List<DailyProgressRecord> last7Days) {
    if (last7Days.length < 7) return 0.0;

    final highPerformanceDays = last7Days
        .where((day) => day.completionPercentage >= consistencyThreshold)
        .length;

    if (highPerformanceDays == 7) {
      return consistencyBonusFull;
    } else if (highPerformanceDays >= 5) {
      return consistencyBonusPartial;
    }
    return 0.0;
  }

  /// Calculate combined penalty for poor performance with diminishing returns over time
  static double calculateCombinedPenalty(
    double dailyCompletion,
    int consecutiveLowDays,
  ) {
    if (dailyCompletion >= decayThreshold) return 0.0;
    
    // Combined penalty with diminishing returns over time
    // Formula: (50 - completion%) * 0.04 / log(consecutiveDays + 1)
    final pointsBelowThreshold = decayThreshold - dailyCompletion;
    final penalty = pointsBelowThreshold * penaltyBaseMultiplier / log(consecutiveLowDays + 1);
    
    return penalty;
  }

  /// Calculate recovery bonus when breaking low-completion streak
  static double calculateRecoveryBonus(int consecutiveLowDays) {
    if (consecutiveLowDays == 0) return 0.0;
    
    // Recovery bonus when breaking low-completion streak
    // Capped at 5 points to ensure < 50% of typical penalties
    // Formula: min(5, sqrt(consecutiveLowDays) * 1.0)
    final bonus = sqrt(consecutiveLowDays) * 1.0;
    return min(5.0, bonus);
  }

  /// Calculate category neglect penalty for ignored habit categories
  /// Penalty: 0.4 points per category with >1 habit that has zero activity
  /// Note: habitInstances should already be filtered for the target date
  static double calculateCategoryNeglectPenalty(
    List<CategoryRecord> categories,
    List<ActivityInstanceRecord> habitInstances,
    DateTime targetDate,
  ) {
    if (categories.isEmpty || habitInstances.isEmpty) return 0.0;

    final normalizedDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
    double totalPenalty = 0.0;

    for (final category in categories) {
      // Only check habit categories
      if (category.categoryType != 'habit') continue;

      // Get all habits in this category (instances are already filtered for target date)
      final categoryHabits = habitInstances
          .where((inst) => inst.templateCategoryId == category.reference.id)
          .toList();

      // Only apply penalty if category has more than 1 habit
      if (categoryHabits.length <= 1) continue;

      // Check if category has any activity (completed or partial)
      bool hasActivity = false;
      for (final habit in categoryHabits) {
        // Check if completed on target date
        if (habit.status == 'completed' && habit.completedAt != null) {
          final completedDate = DateTime(
            habit.completedAt!.year,
            habit.completedAt!.month,
            habit.completedAt!.day,
          );
          if (completedDate.isAtSameMomentAs(normalizedDate)) {
            hasActivity = true;
            break;
          }
        }
        // Check if has partial progress (currentValue > 0)
        if (habit.currentValue != null) {
          final value = habit.currentValue;
          if (value is num && value > 0) {
            hasActivity = true;
            break;
          }
        }
        // Check if has time logged
        final accumulatedTime = habit.accumulatedTime;
        if (accumulatedTime > 0) {
          hasActivity = true;
          break;
        }
      }

      // If no activity in category with >1 habit, apply penalty
      if (!hasActivity) {
        totalPenalty += categoryNeglectPenalty;
      }
    }

    return totalPenalty;
  }

  /// Calculate weighted performance score from weekly and monthly averages
  static double calculateWeightedPerformance(
    List<DailyProgressRecord> last7Days,
    List<DailyProgressRecord> last30Days,
  ) {
    final weeklyAvg = _calculateAverageCompletion(last7Days);
    final monthlyAvg = _calculateAverageCompletion(last30Days);

    return (weeklyAvg * weeklyWeight) + (monthlyAvg * monthlyWeight);
  }

  /// Update user's cumulative score with today's performance
  static Future<Map<String, dynamic>> updateCumulativeScore(
    String userId,
    double todayCompletionPercentage,
    DateTime targetDate,
    double rawPointsEarned, {
    double categoryNeglectPenalty = 0.0,
  }) async {
    try {
      // Get historical data for calculations
      final last7Days = await _getLastNDays(userId, 7, targetDate);
      final last30Days = await _getLastNDays(userId, 30, targetDate);

      // Calculate components
      final dailyScore = calculateDailyScore(todayCompletionPercentage, rawPointsEarned);
      final consistencyBonus = calculateConsistencyBonus(last7Days);
      final weightedPerformance =
          calculateWeightedPerformance(last7Days, last30Days);

      // Get or create user stats
      final userStats = await _getOrCreateUserStats(userId);

      // Track consecutive low days and calculate penalty/recovery bonus
      int newConsecutiveLowDays;
      double penalty = 0.0;
      double recoveryBonus = 0.0;

      if (todayCompletionPercentage < decayThreshold) {
        // Completion < 50%: increment counter and apply penalty
        newConsecutiveLowDays = userStats.consecutiveLowDays + 1;
        penalty = calculateCombinedPenalty(todayCompletionPercentage, newConsecutiveLowDays);
      } else {
        // Completion >= 50%: calculate recovery bonus and reset counter
        if (userStats.consecutiveLowDays > 0) {
          recoveryBonus = calculateRecoveryBonus(userStats.consecutiveLowDays);
        }
        newConsecutiveLowDays = 0;
      }

      // Calculate new cumulative score
      final dailyGain = dailyScore + consistencyBonus + recoveryBonus - penalty - categoryNeglectPenalty;
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
        final milestoneIndex = MilestoneService.milestones.indexOf(milestoneValue);
        if (milestoneIndex >= 0) {
          newAchievedMilestones = MilestoneService.setMilestoneAchieved(
            newAchievedMilestones,
            milestoneIndex,
          );
        }
      }

      // Update streaks
      final newCurrentStreak =
          _calculateCurrentStreak(last7Days, todayCompletionPercentage);
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
        aggregateStats = await AggregateScoreStatisticsService.calculateAggregateStatistics(
          userId,
          targetDate,
        );
        // Clear cache after calculation to ensure fresh data on next read
        AggregateScoreStatisticsService.clearCache(userId);
      } catch (e) {
        // Continue without aggregate stats if calculation fails
      }

      // Save updated stats
      await _saveUserStats(
        userId,
        newCumulativeScore,
        targetDate,
        newHistoricalHigh,
        userStats.totalDaysTracked + 1,
        newCurrentStreak,
        newLongestStreak,
        dailyGain,
        newConsecutiveLowDays,
        newAchievedMilestones,
        aggregateStats: aggregateStats,
      );

      return {
        'cumulativeScore': newCumulativeScore,
        'dailyGain': dailyGain,
        'dailyScore': dailyScore,
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

  /// Get bonus notifications based on score data
  static List<Map<String, dynamic>> getBonusNotifications(
    Map<String, dynamic> scoreData,
  ) {
    final notifications = <Map<String, dynamic>>[];
    
    // Consistency bonus notification
    final consistencyBonus = scoreData['consistencyBonus'] ?? 0.0;
    if (consistencyBonus >= 5.0) {
      notifications.add({
        'message': 'Consistency Bonus! You completed more than 80% for the last 7 days, so you get 5 extra points',
        'points': 5.0,
        'type': 'bonus',
      });
    } else if (consistencyBonus >= 2.0) {
      notifications.add({
        'message': 'Partial Consistency Bonus! You completed more than 80% for 5-6 days, so you get 2 extra points',
        'points': 2.0,
        'type': 'bonus',
      });
    }
    
    // Recovery bonus notification
    final recoveryBonus = scoreData['recoveryBonus'] ?? 0.0;
    if (recoveryBonus > 0) {
      final consecutiveDays = scoreData['consecutiveLowDays'] ?? 0;
      notifications.add({
        'message': 'Recovery Bonus! You\'re back on track after ${consecutiveDays} day${consecutiveDays == 1 ? '' : 's'} of low completion, so you get ${recoveryBonus.toStringAsFixed(1)} extra points',
        'points': recoveryBonus,
        'type': 'bonus',
      });
    }
    
    // Combined penalty notification (with diminishing returns)
    final penalty = scoreData['decayPenalty'] ?? 0.0;
    if (penalty > 0) {
      final consecutiveDays = scoreData['consecutiveLowDays'] ?? 0;
      notifications.add({
        'message': 'Low Completion Penalty: Today\'s completion was below 50% (day ${consecutiveDays} of low completion), so you lose ${penalty.toStringAsFixed(1)} points',
        'points': -penalty,
        'type': 'penalty',
      });
    }
    
    // Category neglect penalty notification
    final categoryPenalty = scoreData['categoryNeglectPenalty'] ?? 0.0;
    if (categoryPenalty > 0) {
      final ignoredCategories = (categoryPenalty / categoryNeglectPenalty).round();
      notifications.add({
        'message': 'Category Neglect Penalty: You ignored ${ignoredCategories} habit categor${ignoredCategories == 1 ? 'y' : 'ies'} today, so you lose ${categoryPenalty.toStringAsFixed(1)} points',
        'points': -categoryPenalty,
        'type': 'penalty',
      });
    }
    
    return notifications;
  }

  /// Get current cumulative score for a user
  static Future<UserProgressStatsRecord?> getCumulativeScore(
      String userId) async {
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

  /// Calculate projected daily score without writing to database
  /// Used for live display of today's potential cumulative score
  static Future<Map<String, dynamic>> calculateProjectedDailyScore(
    String userId,
    double todayCompletionPercentage,
    double rawPointsEarned,
  ) async {
    try {
      // Get current cumulative score from UserProgressStats
      final userStats = await getCumulativeScore(userId);
      final currentCumulative = userStats?.cumulativeScore ?? 0.0;

      // Get last 7 days for bonus calculations
      final today = DateTime.now();
      final last7Days = await _getLastNDays(userId, 7, today);

      // Get current consecutive low days from user stats
      final consecutiveLowDays = userStats?.consecutiveLowDays ?? 0;

      // Calculate components (same as updateCumulativeScore but read-only)
      final dailyScore = calculateDailyScore(todayCompletionPercentage, rawPointsEarned);
      final consistencyBonus = calculateConsistencyBonus(last7Days);
      
      // Calculate penalty/recovery bonus based on today's completion
      double penalty = 0.0;
      double recoveryBonus = 0.0;
      
      if (todayCompletionPercentage < decayThreshold) {
        // Completion < 50%: calculate penalty with incremented counter
        final projectedConsecutiveDays = consecutiveLowDays + 1;
        penalty = calculateCombinedPenalty(todayCompletionPercentage, projectedConsecutiveDays);
      } else {
        // Completion >= 50%: calculate recovery bonus if there were low days
        if (consecutiveLowDays > 0) {
          recoveryBonus = calculateRecoveryBonus(consecutiveLowDays);
        }
      }

      final projectedGain = dailyScore + consistencyBonus + recoveryBonus - penalty;
      final projectedCumulative =
          (currentCumulative + projectedGain).clamp(0.0, double.infinity);

      return {
        'currentCumulative': currentCumulative,
        'projectedGain': projectedGain,
        'projectedCumulative': projectedCumulative,
        'dailyScore': dailyScore,
        'consistencyBonus': consistencyBonus,
        'decayPenalty': penalty,
        'recoveryBonus': recoveryBonus,
      };
    } catch (e) {
      // Return safe defaults on error
      try {
        final userStats = await getCumulativeScore(userId);
        final currentCumulative = userStats?.cumulativeScore ?? 0.0;
        return {
          'currentCumulative': currentCumulative,
          'projectedGain': 0.0,
          'projectedCumulative': currentCumulative,
          'dailyScore': 0.0,
          'consistencyBonus': 0.0,
          'decayPenalty': 0.0,
          'recoveryBonus': 0.0,
        };
      } catch (e2) {
        // If even the fallback fails, return zeros
        return {
          'currentCumulative': 0.0,
          'projectedGain': 0.0,
          'projectedCumulative': 0.0,
          'dailyScore': 0.0,
          'consistencyBonus': 0.0,
          'decayPenalty': 0.0,
          'recoveryBonus': 0.0,
        };
      }
    }
  }

  /// Recalculate cumulative score from historical data
  static Future<void> recalculateFromHistory(String userId) async {
    try {
      // Get all historical progress data
      final query = await DailyProgressRecord.collectionForUser(userId)
          .orderBy('date', descending: false)
          .get();

      final allProgress = query.docs
          .map((doc) => DailyProgressRecord.fromSnapshot(doc))
          .toList();

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
        final dailyScore = calculateDailyScore(completion, rawPoints);

        // Calculate consistency bonus (need last 7 days)
        final startIndex = (i >= 6) ? i - 6 : 0;
        final last7Days = allProgress.sublist(startIndex, i + 1);
        final consistencyBonus = calculateConsistencyBonus(last7Days);

        // Track consecutive low days and calculate penalty/recovery bonus
        double penalty = 0.0;
        double recoveryBonus = 0.0;
        
        if (completion < decayThreshold) {
          // Completion < 50%: increment counter and apply penalty
          consecutiveLowDays++;
          penalty = calculateCombinedPenalty(completion, consecutiveLowDays);
        } else {
          // Completion >= 50%: calculate recovery bonus and reset counter
          if (consecutiveLowDays > 0) {
            recoveryBonus = calculateRecoveryBonus(consecutiveLowDays);
          }
          consecutiveLowDays = 0;
        }

        // Update cumulative score
        final dailyGain = dailyScore + consistencyBonus + recoveryBonus - penalty;
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
          final milestoneIndex = MilestoneService.milestones.indexOf(milestoneValue);
          if (milestoneIndex >= 0) {
            achievedMilestones = MilestoneService.setMilestoneAchieved(
              achievedMilestones,
              milestoneIndex,
            );
          }
        }

        // Update streaks
        if (completion >= consistencyThreshold) {
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
          aggregateStats = await AggregateScoreStatisticsService.calculateAggregateStatistics(
            userId,
            lastDate,
          );
          AggregateScoreStatisticsService.clearCache(userId);
        } catch (e) {
          // Error calculating aggregate statistics during recalculation
        }

        await _saveUserStats(
          userId,
          cumulativeScore,
          lastDate,
          cumulativeScore, // Historical high is the current score after recalculation
          totalDays,
          currentStreak,
          longestStreak,
          allProgress.isNotEmpty
              ? calculateDailyScore(
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

  /// Get last N days of progress data
  static Future<List<DailyProgressRecord>> _getLastNDays(
    String userId,
    int n,
    DateTime endDate,
  ) async {
    final startDate = endDate.subtract(Duration(days: n - 1));
    final query = await DailyProgressRecord.collectionForUser(userId)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .orderBy('date', descending: false)
        .get();

    return query.docs
        .map((doc) => DailyProgressRecord.fromSnapshot(doc))
        .toList();
  }

  /// Get or create user progress stats
  static Future<UserProgressStatsRecord> _getOrCreateUserStats(
      String userId) async {
    final docRef =
        UserProgressStatsRecord.collectionForUser(userId).doc('main');

    try {
      return await UserProgressStatsRecord.getDocumentOnce(docRef);
    } catch (e) {
      // Create new stats record
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
  }

  /// Save user progress stats
  static Future<void> _saveUserStats(
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
      averageDailyScore7Day: aggregateStats?['averageDailyScore7Day'] as double?,
      averageDailyScore30Day: aggregateStats?['averageDailyScore30Day'] as double?,
      bestDailyScoreGain: aggregateStats?['bestDailyScoreGain'] as double?,
      worstDailyScoreGain: aggregateStats?['worstDailyScoreGain'] as double?,
      positiveDaysCount7Day: aggregateStats?['positiveDaysCount7Day'] as int?,
      positiveDaysCount30Day: aggregateStats?['positiveDaysCount30Day'] as int?,
      scoreGrowthRate7Day: aggregateStats?['scoreGrowthRate7Day'] as double?,
      scoreGrowthRate30Day: aggregateStats?['scoreGrowthRate30Day'] as double?,
      averageCumulativeScore7Day: aggregateStats?['averageCumulativeScore7Day'] as double?,
      averageCumulativeScore30Day: aggregateStats?['averageCumulativeScore30Day'] as double?,
      lastAggregateStatsCalculationDate: aggregateStats != null ? now : null,
    );

    await docRef.set(data, SetOptions(merge: true));
  }

  /// Calculate average completion percentage from a list of progress records
  static double _calculateAverageCompletion(List<DailyProgressRecord> records) {
    if (records.isEmpty) return 0.0;
    final total =
        records.fold(0.0, (sum, record) => sum + record.completionPercentage);
    return total / records.length;
  }

  /// Calculate current streak based on recent performance
  static int _calculateCurrentStreak(
    List<DailyProgressRecord> last7Days,
    double todayCompletion,
  ) {
    int streak = 0;

    // Check today's performance
    if (todayCompletion >= consistencyThreshold) {
      streak = 1;
    } else {
      return 0;
    }

    // Count backwards from yesterday
    for (int i = last7Days.length - 1; i >= 0; i--) {
      if (last7Days[i].completionPercentage >= consistencyThreshold) {
        streak++;
      } else {
        break;
      }
    }

    return streak;
  }
}
