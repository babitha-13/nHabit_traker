import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Screens/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

/// Service to calculate aggregate statistics from daily scores and cumulative scores
/// Uses in-memory caching to avoid repetitive Firestore reads
/// Uses effective gain concept (filters out negative gains when cumulative is 0)
class AggregateScoreStatisticsService {
  // In-memory cache to avoid repetitive Firestore reads
  static final Map<String, _CachedStats> _cache = {};
  static const Duration _cacheValidityDuration = Duration(hours: 1);

  /// Calculate all aggregate statistics for a user (with caching)
  static Future<Map<String, dynamic>> calculateAggregateStatistics(
    String userId,
    DateTime referenceDate,
  ) async {
    // Check cache first
    final cacheKey = userId;
    final cached = _cache[cacheKey];
    if (cached != null &&
        cached.calculatedAt
            .add(_cacheValidityDuration)
            .isAfter(DateTime.now()) &&
        _isSameDay(cached.referenceDate, referenceDate)) {
      return cached.stats;
    }

    // Query DailyProgressRecord for last 90 days
    final records = await DailyProgressQueryService.queryDateRange(
      userId: userId,
      endDate: referenceDate,
      daysBack: 90,
    );

    // Sort records by date for effective gain calculation
    records.sort((a, b) {
      if (a.date == null || b.date == null) return 0;
      return a.date!.compareTo(b.date!);
    });

    // Build day-by-day data structure with effective gains
    final dayData = <Map<String, dynamic>>[];
    double previousCumulative = 0.0;

    for (final record in records) {
      if (!record.hasDailyScoreGain()) continue;

      final actualGain = record.dailyScoreGain;
      final effectiveGain =
          calculateEffectiveGain(previousCumulative, actualGain);
      final cumulativeAtEnd = record.cumulativeScoreSnapshot;

      dayData.add({
        'date': record.date,
        'actualGain': actualGain,
        'effectiveGain': effectiveGain,
        'cumulativeAtEnd': cumulativeAtEnd,
      });

      previousCumulative = cumulativeAtEnd;
    }

    // Filter for 7-day and 30-day periods
    final last7Days = DailyProgressQueryService.filterLastNDays(
      records: records,
      n: 7,
      referenceDate: referenceDate,
    );
    final last30Days = DailyProgressQueryService.filterLastNDays(
      records: records,
      n: 30,
      referenceDate: referenceDate,
    );

    // Calculate averages using effective gains
    final dayData7Days = dayData.where((day) {
      final dayDate = day['date'] as DateTime?;
      if (dayDate == null) return false;
      final cutoff7Days = referenceDate.subtract(const Duration(days: 6));
      return !dayDate.isBefore(cutoff7Days) && !dayDate.isAfter(referenceDate);
    }).toList();

    final dayData30Days = dayData.where((day) {
      final dayDate = day['date'] as DateTime?;
      if (dayDate == null) return false;
      final cutoff30Days = referenceDate.subtract(const Duration(days: 29));
      return !dayDate.isBefore(cutoff30Days) && !dayDate.isAfter(referenceDate);
    }).toList();

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
    final bestWorst = calculateBestWorstDailyScore(records);

    // Calculate positive days count using effective gains
    final positive7Day =
        dayData7Days.where((d) => (d['effectiveGain'] as double) > 0).length;
    final positive30Day =
        dayData30Days.where((d) => (d['effectiveGain'] as double) > 0).length;

    // Calculate growth rates (same as average of effective gains)
    double growthRate7Day = avg7Day;
    double growthRate30Day = avg30Day;

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

    final stats = {
      'averageDailyScore7Day': avg7Day,
      'averageDailyScore30Day': avg30Day,
      'bestDailyScoreGain': bestWorst['best'] ?? 0.0,
      'worstDailyScoreGain': bestWorst['worst'] ?? 0.0,
      'positiveDaysCount7Day': positive7Day,
      'positiveDaysCount30Day': positive30Day,
      'scoreGrowthRate7Day': growthRate7Day,
      'scoreGrowthRate30Day': growthRate30Day,
      'averageCumulativeScore7Day': avgCumulative7Day,
      'averageCumulativeScore30Day': avgCumulative30Day,
    };

    // Update cache
    _cache[cacheKey] = _CachedStats(
      stats: stats,
      calculatedAt: DateTime.now(),
      referenceDate: referenceDate,
    );

    return stats;
  }

  /// Clear cache for a user (call when new data is added)
  static void clearCache(String userId) {
    _cache.remove(userId);
  }

  /// Clear all cache
  static void clearAllCache() {
    _cache.clear();
  }

  /// Calculate effective gain for a day
  /// If previous cumulative was 0 and gain is negative, it's ineffective (return 0)
  /// Otherwise, use actual gain
  static double calculateEffectiveGain(
    double previousCumulative,
    double dailyGain,
  ) {
    // If previous cumulative was 0 and gain is negative, it's ineffective
    if (previousCumulative <= 0 && dailyGain < 0) {
      return 0.0;
    }
    // Otherwise, use actual gain
    return dailyGain;
  }

  /// Calculate statistics from progress history with effective gain
  /// Queries DailyProgressRecord directly (more efficient than using passed history)
  /// Supports projection data for today's score
  /// Returns map with all calculated statistics
  static Future<Map<String, dynamic>> calculateStatisticsFromHistory({
    required String userId,
    List<DailyProgressRecord>? progressHistory,
    double? projectedCumulativeScore,
    double? projectedDailyGain,
    double? cumulativeScore,
    double? dailyScoreGain,
    double? todayPercentage,
    bool hasProjection = false,
  }) async {
    // Check cache first (use userId as cache key)
    final cacheKey = '$userId-stats';
    final cached = _cache[cacheKey];
    final today = DateService.currentDate;
    if (cached != null &&
        cached.calculatedAt
            .add(_cacheValidityDuration)
            .isAfter(DateTime.now()) &&
        _isSameDay(cached.referenceDate, today)) {
      // Return cached stats, but apply projection if provided
      if (hasProjection && projectedCumulativeScore != null) {
        // Cache doesn't include today's projection, so we need to recalculate
        // Fall through to calculation
      } else {
        return cached.stats;
      }
    }

    // Query DailyProgressRecord for last 30 days (more efficient than using passed history)
    final records = await DailyProgressQueryService.queryLastNDays(
      userId: userId,
      n: 30,
      endDate: today,
    );

    if (records.isEmpty) {
      return _getDefaultStats();
    }

    final cutoff7Days = today.subtract(const Duration(days: 6));
    final cutoff30Days = today.subtract(const Duration(days: 29));

    // Filter records for last 30 days
    final last30DaysRecords = records.where((record) {
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
      final effectiveGain =
          calculateEffectiveGain(previousCumulative, actualGain);
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
    final todayDate = DateService.normalizeToStartOfDay(today);
    final isTodayInRange =
        !todayDate.isBefore(cutoff30Days) && !todayDate.isAfter(today);

    if (isTodayInRange) {
      // Get today's gain and cumulative score
      double todayActualGain = 0.0;
      double todayCumulative = 0.0;

      if (hasProjection && todayPercentage != null && todayPercentage > 0) {
        todayActualGain = projectedDailyGain ?? 0.0;
        todayCumulative = projectedCumulativeScore ?? 0.0;
      } else {
        todayActualGain = dailyScoreGain ?? 0.0;
        todayCumulative = cumulativeScore ?? 0.0;
      }

      // Only add today if we have valid data
      if (todayActualGain != 0.0 || todayCumulative > 0.0) {
        final todayEffectiveGain =
            calculateEffectiveGain(previousCumulative, todayActualGain);
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

    final stats = {
      'averageDailyScore7Day': avg7Day,
      'averageDailyScore30Day': avg30Day,
      'bestDailyScoreGain': bestDay,
      'worstDailyScoreGain': worstDay,
      'positiveDaysCount7Day': positive7Day,
      'positiveDaysCount30Day': positive30Day,
      'scoreGrowthRate7Day': growthRate7Day,
      'scoreGrowthRate30Day': growthRate30Day,
      'averageCumulativeScore7Day': avgCumulative7Day,
      'averageCumulativeScore30Day': avgCumulative30Day,
    };

    // Update cache
    _cache[cacheKey] = _CachedStats(
      stats: stats,
      calculatedAt: DateTime.now(),
      referenceDate: today,
    );

    return stats;
  }

  /// Get default statistics (all zeros)
  static Map<String, dynamic> _getDefaultStats() {
    return {
      'averageDailyScore7Day': 0.0,
      'averageDailyScore30Day': 0.0,
      'bestDailyScoreGain': 0.0,
      'worstDailyScoreGain': 0.0,
      'positiveDaysCount7Day': 0,
      'positiveDaysCount30Day': 0,
      'scoreGrowthRate7Day': 0.0,
      'scoreGrowthRate30Day': 0.0,
      'averageCumulativeScore7Day': 0.0,
      'averageCumulativeScore30Day': 0.0,
    };
  }

  /// Calculate average daily score gain for a period
  static double calculateAverageDailyScore(
    List<DailyProgressRecord> records,
  ) {
    if (records.isEmpty) return 0.0;

    final validRecords = records.where((r) => r.hasDailyScoreGain()).toList();
    if (validRecords.isEmpty) return 0.0;

    final total =
        validRecords.fold(0.0, (sum, record) => sum + record.dailyScoreGain);
    return total / validRecords.length;
  }

  /// Calculate best/worst daily score
  static Map<String, double> calculateBestWorstDailyScore(
    List<DailyProgressRecord> records,
  ) {
    final validRecords = records.where((r) => r.hasDailyScoreGain()).toList();
    if (validRecords.isEmpty) {
      return {'best': 0.0, 'worst': 0.0};
    }

    double best = validRecords.first.dailyScoreGain;
    double worst = validRecords.first.dailyScoreGain;

    for (final record in validRecords) {
      if (record.dailyScoreGain > best) {
        best = record.dailyScoreGain;
      }
      if (record.dailyScoreGain < worst) {
        worst = record.dailyScoreGain;
      }
    }

    return {'best': best, 'worst': worst};
  }

  /// Calculate positive days count
  static int calculatePositiveDaysCount(
    List<DailyProgressRecord> records,
  ) {
    return records
        .where(
            (record) => record.hasDailyScoreGain() && record.dailyScoreGain > 0)
        .length;
  }

  /// Calculate score growth rate (average daily gain trend)
  /// Uses linear regression to calculate the trend
  static double calculateScoreGrowthRate(
    List<DailyProgressRecord> records,
  ) {
    final validRecords =
        records.where((r) => r.hasDailyScoreGain() && r.date != null).toList();
    if (validRecords.length < 2) return 0.0;

    // Sort by date
    validRecords.sort((a, b) => a.date!.compareTo(b.date!));

    // Calculate linear regression slope
    final n = validRecords.length;
    double sumX = 0.0;
    double sumY = 0.0;
    double sumXY = 0.0;
    double sumX2 = 0.0;

    for (int i = 0; i < n; i++) {
      final x = i.toDouble(); // Day index
      final y = validRecords[i].dailyScoreGain;
      sumX += x;
      sumY += y;
      sumXY += x * y;
      sumX2 += x * x;
    }

    // Calculate slope: (n*sumXY - sumX*sumY) / (n*sumX2 - sumX*sumX)
    final denominator = n * sumX2 - sumX * sumX;
    if (denominator == 0) return 0.0;

    final slope = (n * sumXY - sumX * sumY) / denominator;
    return slope;
  }

  /// Calculate average cumulative score
  static double calculateAverageCumulativeScore(
    List<DailyProgressRecord> records,
  ) {
    final validRecords =
        records.where((r) => r.hasCumulativeScoreSnapshot()).toList();
    if (validRecords.isEmpty) return 0.0;

    final total = validRecords.fold(
        0.0, (sum, record) => sum + record.cumulativeScoreSnapshot);
    return total / validRecords.length;
  }

  /// Check if two dates are on the same day
  static bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

/// Internal class for caching statistics
class _CachedStats {
  final Map<String, dynamic> stats;
  final DateTime calculatedAt;
  final DateTime referenceDate;

  _CachedStats({
    required this.stats,
    required this.calculatedAt,
    required this.referenceDate,
  });
}
