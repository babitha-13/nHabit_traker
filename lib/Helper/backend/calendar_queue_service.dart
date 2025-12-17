import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

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
  static bool _isDueOnDate(ActivityInstanceRecord instance, DateTime targetDate) {
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
        final windowEndDate = DateTime(windowEnd.year, windowEnd.month, windowEnd.day);
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
       return dueDate.isAtSameMomentAs(targetStart) || dueDate.isBefore(targetStart);
    } else {
       // Specific date: only items due strictly on that date
       return dueDate.isAtSameMomentAs(targetStart);
    }
  }

  /// Check if instance was completed on target date
  static bool _wasCompletedOnDate(ActivityInstanceRecord instance, DateTime targetDate) {
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
  static Future<List<ActivityInstanceRecord>> getPlannedItems({
    String? userId,
    DateTime? date,
  }) async {
    final uid = userId ?? currentUserUid;
    if (uid.isEmpty) return [];
    
    final targetDate = _startOfDay(date);

    try {
      // Get all instances
      final allInstances = await queryAllInstances(userId: uid);

      // Filter for items due on targetDate that are pending
      final plannedItems = allInstances.where((instance) {
        // Must be active
        if (!instance.isActive) return false;

        // Must be pending (not completed or skipped)
        if (instance.status != 'pending') return false;

        // Must be due on targetDate (or overdue if targetDate is today)
        if (!_isDueOnDate(instance, targetDate)) return false;

        // Skip snoozed instances (only if snoozed until AFTER target date?)
        // If viewing past, snoozed status might be irrelevant or we assume it was snoozed.
        // But logic relies on current state.
        if (instance.snoozedUntil != null &&
            DateTime.now().isBefore(instance.snoozedUntil!)) {
            // If snoozed until future, don't show?
            // Existing logic: hide if snoozed.
            return false;
        }

        return true;
      }).toList();

      return plannedItems;
    } catch (e) {
      // Error getting planned items
      return [];
    }
  }

  /// Get completed tasks/habits that were completed on date
  static Future<List<ActivityInstanceRecord>> getCompletedItems({
    String? userId,
    DateTime? date,
  }) async {
    final uid = userId ?? currentUserUid;
    if (uid.isEmpty) return [];
    
    final targetDate = _startOfDay(date);

    try {
      // Get all instances
      final allInstances = await queryAllInstances(userId: uid);

      // Filter for items completed on targetDate
      final completedItems = allInstances.where((instance) {
        // Must be active
        if (!instance.isActive) return false;

        // Must be completed on targetDate
        return _wasCompletedOnDate(instance, targetDate);
      }).toList();

      return completedItems;
    } catch (e) {
      // Error getting completed items
      return [];
    }
  }

  // Deprecated/Alias methods for backward compatibility
  static Future<List<ActivityInstanceRecord>> getPlannedItemsToday({String? userId}) {
    return getPlannedItems(userId: userId);
  }
  
  static Future<List<ActivityInstanceRecord>> getCompletedItemsToday({String? userId}) {
    return getCompletedItems(userId: userId);
  }

  /// Get both planned and completed items in one call
  /// Returns a map with 'planned' and 'completed' keys
  static Future<Map<String, List<ActivityInstanceRecord>>>
      getQueueItems({
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
  
  static Future<Map<String, List<ActivityInstanceRecord>>>
      getTodayQueueItems({
    String? userId,
    DateTime? date, // Optional date override
  }) async {
      return getQueueItems(userId: userId, date: date);
  }
}
