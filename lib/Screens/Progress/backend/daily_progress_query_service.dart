import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

/// Shared service for querying DailyProgressRecord
/// Eliminates duplicate query patterns across Progress backend services
class DailyProgressQueryService {
  /// Query DailyProgressRecord with optional date range
  /// Dates are automatically normalized to start of day
  static Future<List<DailyProgressRecord>> queryDailyProgress({
    required String userId,
    DateTime? startDate,
    DateTime? endDate,
    bool orderDescending = false,
  }) async {
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
    return snapshot.docs
        .map((doc) => DailyProgressRecord.fromSnapshot(doc))
        .toList();
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
