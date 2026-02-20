import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/schema/user_progress_stats_record.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_formulas.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/Scores/score_persistence_service.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Service for calculating today's score gain based on current completion
/// Today's score = base daily score + bonuses - penalties
/// Can be positive or negative, but cumulative score never goes below 0
class TodayScoreCalculator {
  static const Duration _cacheTtl = Duration(seconds: 30);
  static DateTime? _last7DaysCachedAt;
  static DateTime? _userStatsCachedAt;
  static DateTime? _yesterdayCumulativeCachedAt;
  static List<DailyProgressRecord>? _cachedLast7Days;
  static UserProgressStatsRecord? _cachedUserStats;
  static double? _cachedYesterdayCumulative;

  /// Invalidate the internal caches
  static void invalidateCache() {
    _last7DaysCachedAt = null;
    _userStatsCachedAt = null;
    _yesterdayCumulativeCachedAt = null;
    _cachedLast7Days = null;
    _cachedUserStats = null;
    _cachedYesterdayCumulative = null;
  }

  /// Invalidate the internal caches
  static void invalidateCache() {
    _last7DaysCachedAt = null;
    _userStatsCachedAt = null;
    _yesterdayCumulativeCachedAt = null;
    _cachedLast7Days = null;
    _cachedUserStats = null;
    _cachedYesterdayCumulative = null;
  }

  static bool _isCacheFresh(DateTime? cachedAt) {
    if (cachedAt == null) return false;
    return DateTime.now().difference(cachedAt) <= _cacheTtl;
  }

  /// Calculate today's score from completion percentage + bonuses/penalties
  /// Returns: {todayScore, dailyScore, consistencyBonus, recoveryBonus, decayPenalty, categoryNeglectPenalty}
  static Future<Map<String, dynamic>> calculateTodayScore({
    required String userId,
    required double completionPercentage,
    required double pointsEarned,
    List<CategoryRecord>? categories,
    List<ActivityInstanceRecord>? habitInstances,
  }) async {
    if (userId.isEmpty) {
      return {
        'todayScore': 0.0,
        'dailyScore': 0.0,
        'consistencyBonus': 0.0,
        'recoveryBonus': 0.0,
        'decayPenalty': 0.0,
        'categoryNeglectPenalty': 0.0,
      };
    }

    // Get last 7 days for consistency bonus calculation (cache for fast updates)
    final today = DateService.currentDate;
    List<DailyProgressRecord> last7Days;
    if (_isCacheFresh(_last7DaysCachedAt) && _cachedLast7Days != null) {
      last7Days = _cachedLast7Days!;
    } else {
      last7Days = await DailyProgressQueryService.queryLastNDays(
        userId: userId,
        n: 7,
        endDate: today,
      );
      _cachedLast7Days = last7Days;
      _last7DaysCachedAt = DateTime.now();
    }

    // Base daily score from completion % and points earned
    final dailyScore = ScoreFormulas.calculateDailyScore(
      completionPercentage,
      pointsEarned,
    );

    // Consistency bonus based on last 7 days
    final consistencyBonus = ScoreFormulas.calculateConsistencyBonus(last7Days);

    // Get user stats for consecutive low days and recovery bonus (cache for fast updates)
    UserProgressStatsRecord? userStats;
    if (_isCacheFresh(_userStatsCachedAt) && _cachedUserStats != null) {
      userStats = _cachedUserStats;
    } else {
      userStats = await ScorePersistenceService.getUserStats(userId);
      _cachedUserStats = userStats;
      _userStatsCachedAt = DateTime.now();
    }
    final consecutiveLowDays = userStats?.consecutiveLowDays ?? 0;

    // Calculate penalty/recovery bonus based on today's completion
    double decayPenalty = 0.0;
    double recoveryBonus = 0.0;

    if (completionPercentage < ScoreFormulas.decayThreshold) {
      // Completion < 50%: calculate penalty with incremented counter
      final projectedConsecutiveDays = consecutiveLowDays + 1;
      decayPenalty = ScoreFormulas.calculateCombinedPenalty(
        completionPercentage,
        projectedConsecutiveDays,
      );
    } else {
      // Completion >= 50%: calculate recovery bonus if there were low days
      if (consecutiveLowDays > 0) {
        recoveryBonus =
            ScoreFormulas.calculateRecoveryBonus(consecutiveLowDays);
      }
    }

    // Category neglect penalty (if categories and instances provided)
    double categoryNeglectPenalty = 0.0;
    if (categories != null && habitInstances != null) {
      categoryNeglectPenalty = ScoreFormulas.calculateCategoryNeglectPenalty(
        categories,
        habitInstances,
        today,
      );
    }

    // Today's total score = base + bonuses - penalties
    final todayScore = dailyScore +
        consistencyBonus +
        recoveryBonus -
        decayPenalty -
        categoryNeglectPenalty;

    return {
      'todayScore': todayScore,
      'dailyScore': dailyScore,
      'consistencyBonus': consistencyBonus,
      'recoveryBonus': recoveryBonus,
      'decayPenalty': decayPenalty,
      'categoryNeglectPenalty': categoryNeglectPenalty,
    };
  }

  /// Get cumulative score at end of yesterday
  /// Delegates to ScorePersistenceService
  static Future<double> getCumulativeScoreTillYesterday({
    required String userId,
  }) async {
    if (_isCacheFresh(_yesterdayCumulativeCachedAt) &&
        _cachedYesterdayCumulative != null) {
      return _cachedYesterdayCumulative!;
    }
    final value =
        await ScorePersistenceService.getCumulativeScoreTillYesterday(userId);
    _cachedYesterdayCumulative = value;
    _yesterdayCumulativeCachedAt = DateTime.now();
    return value;
  }

  /// Calculate cumulative score = yesterday's cumulative + today's score (clamped >= 0)
  static Future<double> calculateCumulativeScore({
    required String userId,
    required double todayScore,
  }) async {
    final yesterdayCumulative =
        await getCumulativeScoreTillYesterday(userId: userId);
    final cumulative =
        (yesterdayCumulative + todayScore).clamp(0.0, double.infinity);
    return cumulative;
  }
}
