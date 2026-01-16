import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';

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

  /// Check if instance was completed on target date
  static bool _wasCompletedOnDate(
      ActivityInstanceRecord instance, DateTime targetDate) {
    if (instance.status != 'completed' || instance.completedAt == null) {
      return false;
    }

    final targetStart = _startOfDay(targetDate);
    final completedAt = instance.completedAt!;
    final completedDateOnly =
        DateTime(completedAt.year, completedAt.month, completedAt.day);
    return completedDateOnly.isAtSameMomentAs(targetStart);
  }

  /// Get planned tasks/habits due on date (pending status)
  /// Returns list of ActivityInstanceRecord that are due on date and not completed
  /// Optimized: Uses Firestore date queries when possible instead of loading all instances
  static Future<List<ActivityInstanceRecord>> getPlannedItems({
    String? userId,
    DateTime? date,
  }) async {
    final uid = userId ?? currentUserUid;
    if (uid.isEmpty) return [];

    final targetDate = _startOfDay(date);
    final todayStart = DateService.todayStart;
    final isTargetToday = targetDate.isAtSameMomentAs(todayStart);

    try {
      List<ActivityInstanceRecord> instances;
      
      // Optimize: Use Firestore query by dueDate when possible
      // For tasks on a specific date, we can query by dueDate
      // For habits, we need to check window logic, so fallback to loading all
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
          // Fallback to loading all if query fails (e.g., no index)
          instances = await queryAllInstances(userId: uid);
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
          // Fallback to loading all if query fails
          instances = await queryAllInstances(userId: uid);
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
      // Error getting planned items - fallback to original method
      try {
        final allInstances = await queryAllInstances(userId: uid);
        return allInstances.where((instance) {
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
          'Get planned items fallback (queryAllInstances)',
          'activity_instances',
        );
        return [];
      }
    }
  }

  /// Get completed tasks/habits that were completed on date
  /// Optimized: Uses Firestore completedAt query when possible
  static Future<List<ActivityInstanceRecord>> getCompletedItems({
    String? userId,
    DateTime? date,
  }) async {
    final uid = userId ?? currentUserUid;
    if (uid.isEmpty) return [];

    final targetDate = _startOfDay(date);
    final targetDateEnd = targetDate.add(const Duration(days: 1));

    try {
      List<ActivityInstanceRecord> instances;
      
      // Optimize: Query by completedAt field at Firestore level
      try {
        // Query for items completed on targetDate (completedAt >= start of day AND < end of day)
        final query = ActivityInstanceRecord.collectionForUser(uid)
            .where('status', isEqualTo: 'completed')
            .where('completedAt', isGreaterThanOrEqualTo: targetDate)
            .where('completedAt', isLessThan: targetDateEnd);
        final result = await query.get();
        instances = result.docs
            .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
            .where((instance) => instance.isActive)
            .toList();
      } catch (e) {
        // Log index error if present
        logFirestoreIndexError(
          e,
          'Get completed items (status=completed, completedAt range query)',
          'activity_instances',
        );
        // Fallback: If composite query fails (e.g., no index), use simple query
        try {
          final query = ActivityInstanceRecord.collectionForUser(uid)
              .where('status', isEqualTo: 'completed')
              .where('completedAt', isGreaterThanOrEqualTo: targetDate)
              .where('completedAt', isLessThan: targetDateEnd);
          final result = await query.get();
          instances = result.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
              .where((instance) => instance.isActive)
              .toList();
        } catch (e2) {
          // Log second error too
          logFirestoreIndexError(
            e2,
            'Get completed items fallback query',
            'activity_instances',
          );
          // Final fallback: Load all and filter in memory
          instances = await queryAllInstances(userId: uid);
        }
      }

      // Filter for items completed on targetDate (verify date match)
      final completedItems = instances.where((instance) {
        // Must be active (already filtered, but double-check)
        if (!instance.isActive) return false;

        // Must be completed on targetDate
        return _wasCompletedOnDate(instance, targetDate);
      }).toList();

      return completedItems;
    } catch (e) {
      // Log any unexpected errors
      logFirestoreIndexError(
        e,
        'Get completed items (unexpected error)',
        'activity_instances',
      );
      // Error getting completed items - fallback to original method
      try {
        final allInstances = await queryAllInstances(userId: uid);
        return allInstances.where((instance) {
          if (!instance.isActive) return false;
          return _wasCompletedOnDate(instance, targetDate);
        }).toList();
      } catch (e2) {
        logFirestoreIndexError(
          e2,
          'Get completed items fallback (queryAllInstances)',
          'activity_instances',
        );
        return [];
      }
    }
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
