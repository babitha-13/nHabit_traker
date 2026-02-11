import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Shared service for querying DailyProgressRecord
/// Eliminates duplicate query patterns across Progress backend services
/// Includes TTL-based caching to reduce redundant Firestore reads
class DailyProgressQueryService {
  // Cache storage: key = "userId:startDate:endDate:orderDescending"
  static final Map<String, List<DailyProgressRecord>> _cache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};

  // Cache TTL (Time To Live) in seconds
  // Historical data (past days) can be cached longer since it doesn't change
  // Today's data needs shorter TTL since it updates during the day
  static const int _historicalCacheTTL = 600; // 10 minutes for historical data
  static const int _todayCacheTTL = 60; // 1 minute for today's data

  /// Check if cache is still valid based on TTL
  static bool _isCacheValid(
      String cacheKey, DateTime? timestamp, DateTime? endDate) {
    if (timestamp == null) return false;

    // Use shorter TTL if query includes today
    final today = DateService.todayStart;
    final includesToday = endDate != null &&
        !DateService.normalizeToStartOfDay(endDate).isBefore(today);
    final ttlSeconds = includesToday ? _todayCacheTTL : _historicalCacheTTL;

    final age = DateTime.now().difference(timestamp).inSeconds;
    return age < ttlSeconds;
  }

  /// Generate cache key from query parameters
  static String _generateCacheKey({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    bool orderDescending = false,
  }) {
    final normalizedStart = startDate != null
        ? DateService.normalizeToStartOfDay(startDate).toIso8601String()
        : 'null';
    final normalizedEnd = endDate != null
        ? DateService.normalizeToStartOfDay(endDate).toIso8601String()
        : 'null';
    return '$userId:$normalizedStart:$normalizedEnd:$orderDescending';
  }

  /// Invalidate cache for a specific user (called on day transition)
  static void invalidateUserCache(String userId) {
    final keysToRemove = <String>[];
    for (final key in _cache.keys) {
      if (key.startsWith('$userId:')) {
        keysToRemove.add(key);
      }
    }
    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
    }
  }

  /// Invalidate all cache (use sparingly)
  static void invalidateAllCache() {
    _cache.clear();
    _cacheTimestamps.clear();
  }

  /// Query DailyProgressRecord with optional date range
  /// Dates are automatically normalized to start of day
  /// Uses TTL-based caching to reduce redundant Firestore reads
  static Future<List<DailyProgressRecord>> queryDailyProgress({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    bool orderDescending = false,
  }) async {
    // Generate cache key
    final cacheKey = _generateCacheKey(
      userId: userId,
      startDate: startDate,
      endDate: endDate,
      orderDescending: orderDescending,
    );

    // Check cache first
    final cached = _cache[cacheKey];
    final timestamp = _cacheTimestamps[cacheKey];
    if (cached != null && _isCacheValid(cacheKey, timestamp, endDate)) {
      return List<DailyProgressRecord>.from(cached); // Return copy
    }

    // Cache miss - fetch from Firestore
    Query query = DailyProgressRecord.collectionForUser(userId);

    if (startDate != null) {
      final normalizedStart = DateService.normalizeToStartOfDay(startDate);
      query = query.where('date', isGreaterThanOrEqualTo: normalizedStart);
    }

    if (endDate != null) {
      final normalizedEnd = DateService.normalizeToStartOfDay(endDate);
      query = query.where('date', isLessThanOrEqualTo: normalizedEnd);
    }

    query = query.orderBy('date', descending: orderDescending);

    final snapshot = await query.get();
    final records = snapshot.docs
        .map((doc) => DailyProgressRecord.fromSnapshot(doc))
        .toList();

    // Update cache
    _cache[cacheKey] = records;
    _cacheTimestamps[cacheKey] = DateTime.now();

    return records;
  }

  /// Query last N days of DailyProgressRecord up to endDate
  /// Automatically calculates startDate and normalizes dates
  static Future<List<DailyProgressRecord>> queryLastNDays({
    required String userId,
    required int n,
    required DateTime endDate,
    bool orderDescending = false,
  }) async {
    final normalizedEnd = DateService.normalizeToStartOfDay(endDate);
    final startDate = normalizedEnd.subtract(Duration(days: n - 1));

    return queryDailyProgress(
      userId: userId,
      startDate: startDate,
      endDate: normalizedEnd,
      orderDescending: orderDescending,
    );
  }

  /// Filter existing records to get last N days up to referenceDate
  /// Useful when you already have records and want to filter them
  static List<DailyProgressRecord> filterLastNDays({
    required List<DailyProgressRecord> records,
    required int n,
    required DateTime referenceDate,
  }) {
    final normalizedReference =
        DateService.normalizeToStartOfDay(referenceDate);
    final cutoffDate = normalizedReference.subtract(Duration(days: n - 1));

    return records
        .where((record) =>
            record.date != null &&
            !record.date!.isBefore(cutoffDate) &&
            !record.date!.isAfter(normalizedReference))
        .toList();
  }

  /// Query DailyProgressRecord for a specific date range (e.g., last 90 days)
  /// Used by aggregate statistics service
  static Future<List<DailyProgressRecord>> queryDateRange({
    required String userId,
    required DateTime endDate,
    required int daysBack,
    bool orderDescending = false,
  }) async {
    final normalizedEnd = DateService.normalizeToStartOfDay(endDate);
    final startDate = normalizedEnd.subtract(Duration(days: daysBack));

    return queryDailyProgress(
      userId: userId,
      startDate: startDate,
      endDate: normalizedEnd,
      orderDescending: orderDescending,
    );
  }
}
