import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service to fetch tasks and habits from the queue that are due today
/// for display in the calendar
class CalendarQueueService {
  /// Get today's date at midnight
  static DateTime _todayDate() {
    return DateService.todayStart;
  }

  /// Check if instance is due today or overdue (same logic as queue_page)
  static bool _isTodayOrOverdue(ActivityInstanceRecord instance) {
    if (instance.dueDate == null) return true; // No due date = today
    final today = _todayDate();
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    // For habits: include if today is within the window [dueDate, windowEndDate]
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;
      if (windowEnd != null) {
        // Today should be >= dueDate AND <= windowEnd
        final isWithinWindow = !today.isBefore(dueDate) &&
            !today.isAfter(
                DateTime(windowEnd.year, windowEnd.month, windowEnd.day));
        return isWithinWindow;
      }
      // Fallback to due date check if no window
      final isDueToday = dueDate.isAtSameMomentAs(today);
      return isDueToday;
    }
    // For tasks: only if due today or overdue
    final isTodayOrOverdue =
        dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today);
    return isTodayOrOverdue;
  }

  /// Check if instance was completed today
  static bool _wasCompletedToday(ActivityInstanceRecord instance) {
    if (instance.status != 'completed' || instance.completedAt == null) {
      return false;
    }
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final completedAt = instance.completedAt!;
    final completedDateOnly =
        DateTime(completedAt.year, completedAt.month, completedAt.day);
    return completedDateOnly.isAtSameMomentAs(todayStart);
  }

  /// Get planned tasks/habits due today (pending status)
  /// Returns list of ActivityInstanceRecord that are due today and not completed
  static Future<List<ActivityInstanceRecord>> getPlannedItemsToday({
    String? userId,
  }) async {
    final uid = userId ?? currentUserUid;
    if (uid.isEmpty) return [];

    try {
      // Get all instances
      final allInstances = await queryAllInstances(userId: uid);

      // Filter for items due today that are pending
      final plannedItems = allInstances.where((instance) {
        // Must be active
        if (!instance.isActive) return false;

        // Must be pending (not completed or skipped)
        if (instance.status != 'pending') return false;

        // Must be due today or overdue
        if (!_isTodayOrOverdue(instance)) return false;

        // Skip snoozed instances
        if (instance.snoozedUntil != null &&
            DateTime.now().isBefore(instance.snoozedUntil!)) {
          return false;
        }

        return true;
      }).toList();

      return plannedItems;
    } catch (e) {
      print('CalendarQueueService: Error getting planned items: $e');
      return [];
    }
  }

  /// Get completed tasks/habits that were completed today
  /// Returns list of ActivityInstanceRecord that were completed today
  static Future<List<ActivityInstanceRecord>> getCompletedItemsToday({
    String? userId,
  }) async {
    final uid = userId ?? currentUserUid;
    if (uid.isEmpty) return [];

    try {
      // Get all instances
      final allInstances = await queryAllInstances(userId: uid);

      // Filter for items completed today
      final completedItems = allInstances.where((instance) {
        // Must be active
        if (!instance.isActive) return false;

        // Must be completed today
        return _wasCompletedToday(instance);
      }).toList();

      return completedItems;
    } catch (e) {
      print('CalendarQueueService: Error getting completed items: $e');
      return [];
    }
  }

  /// Get both planned and completed items in one call
  /// Returns a map with 'planned' and 'completed' keys
  static Future<Map<String, List<ActivityInstanceRecord>>>
      getTodayQueueItems({
    String? userId,
  }) async {
    final planned = await getPlannedItemsToday(userId: userId);
    final completed = await getCompletedItemsToday(userId: userId);

    return {
      'planned': planned,
      'completed': completed,
    };
  }
}

