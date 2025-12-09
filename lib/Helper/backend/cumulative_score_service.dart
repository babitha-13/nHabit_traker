import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
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
  static const double decayMultiplier = 0.2;
  static const double consistencyBonusFull = 5.0;
  static const double consistencyBonusPartial = 2.0;

  /// Calculate daily score based on completion percentage
  static double calculateDailyScore(double completionPercentage) {
    return (completionPercentage / 100.0) * basePointsPerDay;
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

  /// Calculate decay penalty for poor performance
  static double calculateDecayPenalty(double dailyCompletion) {
    if (dailyCompletion >= decayThreshold) return 0.0;
    return (decayThreshold - dailyCompletion) * decayMultiplier;
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
  ) async {
    try {
      // Get historical data for calculations
      final last7Days = await _getLastNDays(userId, 7, targetDate);
      final last30Days = await _getLastNDays(userId, 30, targetDate);

      // Calculate components
      final dailyScore = calculateDailyScore(todayCompletionPercentage);
      final consistencyBonus = calculateConsistencyBonus(last7Days);
      final decayPenalty = calculateDecayPenalty(todayCompletionPercentage);
      final weightedPerformance =
          calculateWeightedPerformance(last7Days, last30Days);

      // Get or create user stats
      final userStats = await _getOrCreateUserStats(userId);

      // Calculate new cumulative score
      final dailyGain = dailyScore + consistencyBonus - decayPenalty;
      final newCumulativeScore =
          (userStats.cumulativeScore + dailyGain).clamp(0.0, double.infinity);

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
      );

      return {
        'cumulativeScore': newCumulativeScore,
        'dailyGain': dailyGain,
        'dailyScore': dailyScore,
        'consistencyBonus': consistencyBonus,
        'decayPenalty': decayPenalty,
        'weightedPerformance': weightedPerformance,
        'currentStreak': newCurrentStreak,
        'longestStreak': newLongestStreak,
      };
    } catch (e) {
      print('Error updating cumulative score: $e');
      rethrow;
    }
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
          createdAt: now,
          lastUpdatedAt: now,
        );
        await docRef.set(data);
        return UserProgressStatsRecord.getDocumentFromData(data, docRef);
      }
      
      return await UserProgressStatsRecord.getDocumentOnce(docRef);
    } catch (e) {
      print('Error getting cumulative score: $e');
      return null;
    }
  }

  /// Calculate projected daily score without writing to database
  /// Used for live display of today's potential cumulative score
  static Future<Map<String, dynamic>> calculateProjectedDailyScore(
    String userId,
    double todayCompletionPercentage,
  ) async {
    try {
      // Get current cumulative score from UserProgressStats
      final userStats = await getCumulativeScore(userId);
      final currentCumulative = userStats?.cumulativeScore ?? 0.0;

      // Get last 7 days for bonus calculations
      final today = DateTime.now();
      final last7Days = await _getLastNDays(userId, 7, today);

      // Calculate components (same as updateCumulativeScore but read-only)
      final dailyScore = calculateDailyScore(todayCompletionPercentage);
      final consistencyBonus = calculateConsistencyBonus(last7Days);
      final decayPenalty = calculateDecayPenalty(todayCompletionPercentage);

      final projectedGain = dailyScore + consistencyBonus - decayPenalty;
      final projectedCumulative =
          (currentCumulative + projectedGain).clamp(0.0, double.infinity);

      return {
        'currentCumulative': currentCumulative,
        'projectedGain': projectedGain,
        'projectedCumulative': projectedCumulative,
        'dailyScore': dailyScore,
        'consistencyBonus': consistencyBonus,
        'decayPenalty': decayPenalty,
      };
    } catch (e) {
      print('Error calculating projected daily score: $e');
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
        };
      } catch (e2) {
        // If even the fallback fails, return zeros
        print('Error in fallback calculation: $e2');
        return {
          'currentCumulative': 0.0,
          'projectedGain': 0.0,
          'projectedCumulative': 0.0,
          'dailyScore': 0.0,
          'consistencyBonus': 0.0,
          'decayPenalty': 0.0,
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

      for (int i = 0; i < allProgress.length; i++) {
        final day = allProgress[i];
        final completion = day.completionPercentage;

        // Calculate daily score
        final dailyScore = calculateDailyScore(completion);

        // Calculate consistency bonus (need last 7 days)
        final startIndex = (i >= 6) ? i - 6 : 0;
        final last7Days = allProgress.sublist(startIndex, i + 1);
        final consistencyBonus = calculateConsistencyBonus(last7Days);

        // Calculate decay penalty
        final decayPenalty = calculateDecayPenalty(completion);

        // Update cumulative score
        final dailyGain = dailyScore + consistencyBonus - decayPenalty;
        cumulativeScore =
            (cumulativeScore + dailyGain).clamp(0.0, double.infinity);

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
        await _saveUserStats(
          userId,
          cumulativeScore,
          lastDate,
          cumulativeScore, // Historical high is the current score after recalculation
          totalDays,
          currentStreak,
          longestStreak,
          allProgress.isNotEmpty
              ? calculateDailyScore(allProgress.last.completionPercentage)
              : 0.0,
        );
      }
    } catch (e) {
      print('Error recalculating from history: $e');
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
        createdAt: now,
        lastUpdatedAt: now,
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
  ) async {
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
      lastUpdatedAt: now,
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
