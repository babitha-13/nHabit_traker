import 'package:habit_tracker/Helper/backend/schema/cumulative_score_history_record.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_formulas.dart';
import 'package:habit_tracker/Screens/Shared/Points_and_Scores/Scores/score_persistence_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/Helper/Helpers/milestone_service.dart';
import 'package:habit_tracker/Screens/Progress/backend/aggregate_score_statistics_service.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Orchestrator for day-end and catch-up score processing
/// Handles complex multi-step operations:
/// - Score calculation (delegates to ScoreFormulas)
/// - UserProgressStats updates
/// - Milestone detection
/// - Aggregate statistics calculation
class DayEndScoreOrchestrator {
  /// Process and persist scores for a completed day
  /// Used by day_end_processor and morning_catchup_service
  /// 
  /// Returns map with calculated values and metadata for toasts/UI
  static Future<Map<String, dynamic>> processScoreForDay(
    String userId,
    double completionPercentage,
    DateTime targetDate,
    double rawPointsEarned, {
    double categoryNeglectPenalty = 0.0,
    bool setLastProcessedDate = false,
    double? cumulativeScoreAtStart,
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

      // Get or create user stats
      final userStats = await ScorePersistenceService.getUserStats(userId);
      if (userStats == null) {
        throw Exception('Failed to get user stats');
      }

      // Calculate consecutive low days from actual history
      int previousConsecutiveLowDays = 0;
      try {
        final dayBeforeTarget = targetDate.subtract(const Duration(days: 1));
        final recordsBefore = await DailyProgressQueryService.queryDailyProgress(
          userId: userId,
          endDate: dayBeforeTarget,
          orderDescending: true,
        );
        
        for (final record in recordsBefore) {
          if (record.completionPercentage < ScoreFormulas.decayThreshold) {
            previousConsecutiveLowDays++;
          } else {
            break;
          }
        }
      } catch (e) {
        previousConsecutiveLowDays = userStats.consecutiveLowDays;
      }

      // Calculate new consecutive low days
      int newConsecutiveLowDays;
      if (completionPercentage < ScoreFormulas.decayThreshold) {
        newConsecutiveLowDays = previousConsecutiveLowDays + 1;
      } else {
        newConsecutiveLowDays = 0;
      }

      // Calculate all score components using ScoreFormulas
      final dailyPoints = ScoreFormulas.calculateDailyScore(
        completionPercentage,
        rawPointsEarned,
      );
      
      final consistencyBonus = ScoreFormulas.calculateConsistencyBonus(last7Days);
      
      double penalty = 0.0;
      double recoveryBonus = 0.0;

      if (completionPercentage < ScoreFormulas.decayThreshold) {
        penalty = ScoreFormulas.calculateCombinedPenalty(
            completionPercentage, newConsecutiveLowDays);
      } else {
        if (previousConsecutiveLowDays > 0) {
          recoveryBonus = ScoreFormulas.calculateRecoveryBonus(
              previousConsecutiveLowDays);
        }
      }
      
      final dailyGain = dailyPoints +
          consistencyBonus +
          recoveryBonus -
          penalty -
          categoryNeglectPenalty;
      
      final weightedPerformance =
          ScoreFormulas.calculateWeightedPerformance(last7Days, last30Days);
      
      // Calculate new cumulative score
      final startingCumulative = cumulativeScoreAtStart ?? userStats.cumulativeScore;
      final newCumulativeScore =
          (startingCumulative + dailyGain).clamp(0.0, double.infinity);

      // Check for new milestones
      final oldScore = cumulativeScoreAtStart ?? userStats.cumulativeScore;
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
          last7Days, completionPercentage);
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
        AggregateScoreStatisticsService.clearCache(userId);
      } catch (e) {
        // Continue without aggregate stats if calculation fails
      }

      // Save updated stats
      final yesterday = DateService.yesterdayStart;
      final shouldSetLastProcessedDate = setLastProcessedDate && 
          targetDate.year == yesterday.year &&
          targetDate.month == yesterday.month &&
          targetDate.day == yesterday.day;
      
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
        newAchievedMilestones,
        aggregateStats: aggregateStats,
        lastProcessedDate: shouldSetLastProcessedDate ? yesterday : null,
      );

      // Calculate effective gain (actual change in cumulative score)
      final effectiveGain = newCumulativeScore - startingCumulative;

      // Update cumulative score history document
      await _updateCumulativeScoreHistory(
        userId: userId,
        date: targetDate,
        score: newCumulativeScore,
        gain: dailyGain,
        effectiveGain: effectiveGain,
      );

      return {
        'cumulativeScore': newCumulativeScore,
        'dailyGain': dailyGain,
        'dailyPoints': dailyPoints,
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

  /// Update cumulative score history document with today's entry
  /// Keeps last 100 days of history
  static Future<void> _updateCumulativeScoreHistory({
    required String userId,
    required DateTime date,
    required double score,
    required double gain,
    required double effectiveGain,
  }) async {
    try {
      // Read existing history
      final historyDoc = await CumulativeScoreHistoryRecord.getDocument(userId);
      
      List<Map<String, dynamic>> scores = [];
      if (historyDoc.exists) {
        final data = historyDoc.data() as Map<String, dynamic>?;
        if (data != null && data['scores'] is List) {
          scores = List<Map<String, dynamic>>.from(data['scores']);
        }
      }
      
      // Add/update today's entry
      final dateKey = DateFormat('yyyy-MM-dd').format(date);
      scores.removeWhere((s) {
        if (s['date'] is Timestamp) {
          final entryDate = (s['date'] as Timestamp).toDate();
          final entryDateKey = DateFormat('yyyy-MM-dd').format(entryDate);
          return entryDateKey == dateKey;
        }
        return false;
      });
      
      scores.add({
        'date': Timestamp.fromDate(date),
        'score': score,
        'gain': gain,
        'effectiveGain': effectiveGain,
      });
      
      // Keep last 100 days only
      scores.sort((a, b) {
        final dateA = (a['date'] as Timestamp).toDate();
        final dateB = (b['date'] as Timestamp).toDate();
        return dateA.compareTo(dateB);
      });
      if (scores.length > 100) {
        scores = scores.sublist(scores.length - 100);
      }
      
      // Save
      await CumulativeScoreHistoryRecord.setDocument(
        userId: userId,
        scores: scores,
      );
    } catch (e) {
      // Log error but don't fail the entire day-end processing
      // History update is non-critical - can be recalculated from daily_progress
      print('Error updating cumulative score history: $e');
    }
  }
}
