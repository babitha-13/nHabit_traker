import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';

/// Service to calculate aggregate statistics from daily scores and cumulative scores
/// Uses in-memory caching to avoid repetitive Firestore reads
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
        cached.calculatedAt.add(_cacheValidityDuration).isAfter(DateTime.now()) &&
        _isSameDay(cached.referenceDate, referenceDate)) {
      return cached.stats;
    }

    // Query DailyProgressRecord for last 90 days
    final records = await _getDailyProgressRecords(userId, referenceDate);

    // Calculate all statistics
    final last7Days = _getLastNDays(records, 7, referenceDate);
    final last30Days = _getLastNDays(records, 30, referenceDate);

    final stats = {
      'averageDailyScore7Day': calculateAverageDailyScore(last7Days),
      'averageDailyScore30Day': calculateAverageDailyScore(last30Days),
      'bestDailyScoreGain': calculateBestWorstDailyScore(records)['best'] ?? 0.0,
      'worstDailyScoreGain': calculateBestWorstDailyScore(records)['worst'] ?? 0.0,
      'positiveDaysCount7Day': calculatePositiveDaysCount(last7Days),
      'positiveDaysCount30Day': calculatePositiveDaysCount(last30Days),
      'scoreGrowthRate7Day': calculateScoreGrowthRate(last7Days),
      'scoreGrowthRate30Day': calculateScoreGrowthRate(last30Days),
      'averageCumulativeScore7Day': calculateAverageCumulativeScore(last7Days),
      'averageCumulativeScore30Day': calculateAverageCumulativeScore(last30Days),
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

  /// Get daily progress records (with date range optimization)
  static Future<List<DailyProgressRecord>> _getDailyProgressRecords(
    String userId,
    DateTime referenceDate,
  ) async {
    final startDate = referenceDate.subtract(const Duration(days: 90));
    final query = DailyProgressRecord.collectionForUser(userId)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: referenceDate)
        .orderBy('date', descending: false);
    final snapshot = await query.get();
    return snapshot.docs
        .map((doc) => DailyProgressRecord.fromSnapshot(doc))
        .toList();
  }

  /// Get last N days of records up to reference date
  static List<DailyProgressRecord> _getLastNDays(
    List<DailyProgressRecord> records,
    int n,
    DateTime referenceDate,
  ) {
    final cutoffDate = referenceDate.subtract(Duration(days: n - 1));
    return records
        .where((record) =>
            record.date != null &&
            !record.date!.isBefore(cutoffDate) &&
            !record.date!.isAfter(referenceDate))
        .toList();
  }

  /// Calculate average daily score gain for a period
  static double calculateAverageDailyScore(
    List<DailyProgressRecord> records,
  ) {
    if (records.isEmpty) return 0.0;

    final validRecords = records.where((r) => r.hasDailyScoreGain()).toList();
    if (validRecords.isEmpty) return 0.0;

    final total = validRecords.fold(
        0.0, (sum, record) => sum + record.dailyScoreGain);
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
        .where((record) =>
            record.hasDailyScoreGain() && record.dailyScoreGain > 0)
        .length;
  }

  /// Calculate score growth rate (average daily gain trend)
  /// Uses linear regression to calculate the trend
  static double calculateScoreGrowthRate(
    List<DailyProgressRecord> records,
  ) {
    final validRecords = records
        .where((r) => r.hasDailyScoreGain() && r.date != null)
        .toList();
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

