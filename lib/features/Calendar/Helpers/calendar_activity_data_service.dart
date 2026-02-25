import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/diagnostics/fallback_read_logger.dart';

/// Service to fetch tasks and habits from the queue that are due today
/// for display in the calendar
class CalendarQueueService {
  /// Get start of date (midnight)
  static DateTime _startOfDay(DateTime? date) {
    if (date == null) return DateService.todayStart;
    return DateTime(date.year, date.month, date.day);
  }

  /// Check if instance is due on target date
  /// For today: includes overdue tasks
  /// For other dates: strict due date check
  static bool _isDueOnDate(
      ActivityInstanceRecord instance, DateTime targetDate) {
    final targetStart = _startOfDay(targetDate);
    final todayStart = DateService.todayStart;
    final isTargetToday = targetStart.isAtSameMomentAs(todayStart);

    if (instance.dueDate == null) {
      // No due date = today only (backlog/unscheduled)
      return isTargetToday;
    }

    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);

    // For habits: include if targetDate is within the window [dueDate, windowEndDate]
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;
      if (windowEnd != null) {
        // targetDate should be >= dueDate AND <= windowEnd
        final windowEndDate =
            DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
        final isWithinWindow = !targetStart.isBefore(dueDate) &&
            !targetStart.isAfter(windowEndDate);
        return isWithinWindow;
      }
      // Fallback to due date check if no window
      final isDueOnTarget = dueDate.isAtSameMomentAs(targetStart);
      return isDueOnTarget;
    }

    // For tasks:
    if (isTargetToday) {
      // If today, include overdue
      return dueDate.isAtSameMomentAs(targetStart) ||
          dueDate.isBefore(targetStart);
    } else {
      // Specific date: only items due strictly on that date
      return dueDate.isAtSameMomentAs(targetStart);
    }
  }

  /// Check if instance was completed or skipped on target date
  static bool _wasActionedOnDate(
      ActivityInstanceRecord instance, DateTime targetDate) {
    final targetStart = _startOfDay(targetDate);

    // Completed on target date
    if (instance.status == 'completed' && instance.completedAt != null) {
      final completedAt = instance.completedAt!;
      final completedDateOnly =
          DateTime(completedAt.year, completedAt.month, completedAt.day);
      return completedDateOnly.isAtSameMomentAs(targetStart);
    }

    // Skipped on target date (may have partial progress/sessions)
    if (instance.status == 'skipped' && instance.skippedAt != null) {
      final skippedAt = instance.skippedAt!;
      final skippedDateOnly =
          DateTime(skippedAt.year, skippedAt.month, skippedAt.day);
      return skippedDateOnly.isAtSameMomentAs(targetStart);
    }

    return false;
  }

  static void _mergeInstancesById(
    Map<String, ActivityInstanceRecord> merged,
    Iterable<ActivityInstanceRecord> items,
  ) {
    for (final item in items) {
      merged[item.reference.id] = item;
    }
  }

  static Future<List<ActivityInstanceRecord>> _queryPlannedFallbackCandidates({
    required String userId,
    required DateTime targetDate,
    required bool isTargetToday,
  }) async {
    final merged = <String, ActivityInstanceRecord>{};

    Future<void> collectCandidates({
      required Future<dynamic> Function() runQuery,
      required String queryDescription,
      required String queryShape,
    }) async {
      try {
        final result = await runQuery();
        final docs = result.docs;
        final items = docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((instance) => instance.isActive);
        _mergeInstancesById(merged, items);
        FallbackReadTelemetry.logQueryFallback(
          FallbackReadEvent(
            scope: 'calendar_activity_data_service.getPlannedItems',
            reason: 'date_scoped_candidate_fallback_query_executed',
            queryShape: queryShape,
            userCountSampled: 1,
            fallbackDocsReadEstimate: docs.length,
          ),
        );
      } catch (e) {
        logFirestoreIndexError(
          e,
          queryDescription,
          'activity_instances',
        );
        FallbackReadTelemetry.logQueryFallback(
          FallbackReadEvent(
            scope: 'calendar_activity_data_service.getPlannedItems',
            reason: 'date_scoped_candidate_fallback_query_failed',
            queryShape: queryShape,
            userCountSampled: 1,
            fallbackDocsReadEstimate: 0,
          ),
        );
      }
    }

    if (isTargetToday) {
      await collectCandidates(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('dueDate', isLessThanOrEqualTo: targetDate)
            .limit(500)
            .get(),
        queryDescription:
            'Planned fallback candidates (today pending dueDate<=target)',
        queryShape: 'status=pending,dueDate<=targetDate,limit=500',
      );
      await collectCandidates(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('windowEndDate', isGreaterThanOrEqualTo: targetDate)
            .limit(500)
            .get(),
        queryDescription:
            'Planned fallback candidates (today pending habits windowEndDate>=target)',
        queryShape:
            'status=pending,templateCategoryType=habit,windowEndDate>=targetDate,limit=500',
      );
      await collectCandidates(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('dueDate', isEqualTo: null)
            .limit(200)
            .get(),
        queryDescription:
            'Planned fallback candidates (today pending dueDate=null)',
        queryShape: 'status=pending,dueDate=null,limit=200',
      );
    } else {
      await collectCandidates(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('dueDate', isEqualTo: targetDate)
            .limit(500)
            .get(),
        queryDescription:
            'Planned fallback candidates (date pending dueDate==target)',
        queryShape: 'status=pending,dueDate=targetDate,limit=500',
      );
      await collectCandidates(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('belongsToDate', isEqualTo: targetDate)
            .limit(500)
            .get(),
        queryDescription:
            'Planned fallback candidates (date pending habits belongsToDate==target)',
        queryShape:
            'status=pending,templateCategoryType=habit,belongsToDate=targetDate,limit=500',
      );
      await collectCandidates(
        runQuery: () => ActivityInstanceRecord.collectionForUser(userId)
            .where('status', isEqualTo: 'pending')
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('windowEndDate', isGreaterThanOrEqualTo: targetDate)
            .limit(500)
            .get(),
        queryDescription:
            'Planned fallback candidates (date pending habits windowEndDate>=target)',
        queryShape:
            'status=pending,templateCategoryType=habit,windowEndDate>=targetDate,limit=500',
      );
    }

    return merged.values.toList();
  }

  /// Get planned tasks/habits due on date (pending status)
  /// Returns list of ActivityInstanceRecord that are due on date and not completed
  /// Optimized: Uses Firestore date queries when possible instead of loading all instances
  static Future<List<ActivityInstanceRecord>> getPlannedItems({
    String? userId,
    DateTime? date,
  }) async {
    final uid = userId ?? await waitForCurrentUserUid();
    if (uid.isEmpty) return [];

    final targetDate = _startOfDay(date);
    final todayStart = DateService.todayStart;
    final isTargetToday = targetDate.isAtSameMomentAs(todayStart);

    try {
      List<ActivityInstanceRecord> instances;

      // Optimize: Use Firestore query by dueDate when possible.
      // For habits and index failures, use scoped candidate queries only.
      if (!isTargetToday) {
        // For non-today dates, try querying by dueDate (exact match)
        try {
          final query = ActivityInstanceRecord.collectionForUser(uid)
              .where('status', isEqualTo: 'pending')
              .where('dueDate', isEqualTo: targetDate);
          final result = await query.get();
          instances = result.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .where((instance) => instance.isActive)
              .toList();
        } catch (e) {
          // Log index error if present
          logFirestoreIndexError(
            e,
            'Get planned items for specific date (status=pending, dueDate=date)',
            'activity_instances',
          );
          FallbackReadTelemetry.logQueryFallback(
            const FallbackReadEvent(
              scope: 'calendar_activity_data_service.getPlannedItems',
              reason: 'primary_specific_date_query_failed',
              queryShape: 'status=pending,dueDate=targetDate',
              userCountSampled: 1,
              fallbackDocsReadEstimate: 0,
            ),
          );
          instances = await _queryPlannedFallbackCandidates(
            userId: uid,
            targetDate: targetDate,
            isTargetToday: isTargetToday,
          );
        }
      } else {
        // For today, we need to include overdue, so query is more complex
        // Try querying dueDate <= today OR dueDate == today
        try {
          // Query for items due today or earlier
          final query = ActivityInstanceRecord.collectionForUser(uid)
              .where('status', isEqualTo: 'pending')
              .where('dueDate', isLessThanOrEqualTo: targetDate);
          final result = await query.get();
          instances = result.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .where((instance) => instance.isActive)
              .toList();
        } catch (e) {
          // Log index error if present
          logFirestoreIndexError(
            e,
            'Get planned items for today (status=pending, dueDate<=today)',
            'activity_instances',
          );
          FallbackReadTelemetry.logQueryFallback(
            const FallbackReadEvent(
              scope: 'calendar_activity_data_service.getPlannedItems',
              reason: 'primary_today_query_failed',
              queryShape: 'status=pending,dueDate<=targetDate',
              userCountSampled: 1,
              fallbackDocsReadEstimate: 0,
            ),
          );
          instances = await _queryPlannedFallbackCandidates(
            userId: uid,
            targetDate: targetDate,
            isTargetToday: isTargetToday,
          );
        }
      }

      // Filter for items due on targetDate that are pending
      final plannedItems = instances.where((instance) {
        // Must be pending (already filtered in query, but double-check)
        if (instance.status != 'pending') return false;

        // Must be due on targetDate (or overdue if targetDate is today)
        // This handles habit window logic and edge cases
        if (!_isDueOnDate(instance, targetDate)) return false;

        // Skip snoozed instances
        if (instance.snoozedUntil != null &&
            DateTime.now().isBefore(instance.snoozedUntil!)) {
          return false;
        }

        return true;
      }).toList();

      return plannedItems;
    } catch (e) {
      // Log any unexpected errors
      logFirestoreIndexError(
        e,
        'Get planned items (unexpected error)',
        'activity_instances',
      );
      // Error getting planned items - fallback to date-scoped candidate queries
      try {
        final fallbackInstances = await _queryPlannedFallbackCandidates(
          userId: uid,
          targetDate: targetDate,
          isTargetToday: isTargetToday,
        );
        return fallbackInstances.where((instance) {
          if (!instance.isActive) return false;
          if (instance.status != 'pending') return false;
          if (!_isDueOnDate(instance, targetDate)) return false;
          if (instance.snoozedUntil != null &&
              DateTime.now().isBefore(instance.snoozedUntil!)) {
            return false;
          }
          return true;
        }).toList();
      } catch (e2) {
        logFirestoreIndexError(
          e2,
          'Get planned items fallback (date-scoped queries)',
          'activity_instances',
        );
        return [];
      }
    }
  }

  /// Get completed and skipped tasks/habits that were actioned on date.
  /// Skipped items are only included if they have time log sessions.
  static Future<List<ActivityInstanceRecord>> getCompletedItems({
    String? userId,
    DateTime? date,
  }) async {
    final uid = userId ?? await waitForCurrentUserUid();
    if (uid.isEmpty) return [];

    final targetDate = _startOfDay(date);
    final targetDateEnd = targetDate.add(const Duration(days: 1));
    final mergedById = <String, ActivityInstanceRecord>{};

    // Query 1: Completed items by completedAt range
    try {
      final result = await ActivityInstanceRecord.collectionForUser(uid)
          .where('status', isEqualTo: 'completed')
          .where('completedAt', isGreaterThanOrEqualTo: targetDate)
          .where('completedAt', isLessThan: targetDateEnd)
          .get();
      for (final doc in result.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive) {
          mergedById[instance.reference.id] = instance;
        }
      }
    } catch (e) {
      logFirestoreIndexError(
        e,
        'getCompletedItems (status=completed, completedAt range)',
        'activity_instances',
      );
    }

    // Query 2: Skipped items by skippedAt range (only those with time sessions)
    try {
      final result = await ActivityInstanceRecord.collectionForUser(uid)
          .where('status', isEqualTo: 'skipped')
          .where('skippedAt', isGreaterThanOrEqualTo: targetDate)
          .where('skippedAt', isLessThan: targetDateEnd)
          .get();
      for (final doc in result.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.isActive && instance.timeLogSessions.isNotEmpty) {
          mergedById[instance.reference.id] = instance;
        }
      }
    } catch (e) {
      logFirestoreIndexError(
        e,
        'getCompletedItems (status=skipped, skippedAt range)',
        'activity_instances',
      );
    }

    // Verify date match in-memory
    return mergedById.values.where((instance) {
      if (!instance.isActive) return false;
      return _wasActionedOnDate(instance, targetDate);
    }).toList();
  }

  // Deprecated/Alias methods for backward compatibility
  static Future<List<ActivityInstanceRecord>> getPlannedItemsToday(
      {String? userId}) {
    return getPlannedItems(userId: userId);
  }

  static Future<List<ActivityInstanceRecord>> getCompletedItemsToday(
      {String? userId}) {
    return getCompletedItems(userId: userId);
  }

  /// Get both planned and completed items in one call
  /// Returns a map with 'planned' and 'completed' keys
  static Future<Map<String, List<ActivityInstanceRecord>>> getQueueItems({
    String? userId,
    DateTime? date,
  }) async {
    final planned = await getPlannedItems(userId: userId, date: date);
    final completed = await getCompletedItems(userId: userId, date: date);

    return {
      'planned': planned,
      'completed': completed,
    };
  }

  static Future<Map<String, List<ActivityInstanceRecord>>> getTodayQueueItems({
    String? userId,
    DateTime? date, // Optional date override
  }) async {
    return getQueueItems(userId: userId, date: date);
  }
}
